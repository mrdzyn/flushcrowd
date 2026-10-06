import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/discovery_result.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/geo_bounding_box.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../services/firebase/firestore_codec.dart';
import '../services/firebase/firestore_query_executor.dart';
import '../services/gis/geohash_service.dart';
import '../services/gis/haversine.dart';

/// Cloud Firestore implementation of [RestroomRepository].
///
/// Implements P1.1 production GIS and Firestore discovery engine:
/// - Conservative geometric search circle tiling covering 100% of the radius
/// - Bounded queries per range with document, candidate, and result safety caps
/// - Exact Haversine and viewport bounds post-filtering
/// - Deterministic deduplication and distance sorting
/// - Discoverable status filtering (active, unverified only)
/// - Explicit DiscoveryResult completeness and reason indicators (no silent incompleteness)
/// - FirebaseException mapping to repository exceptions
class FirestoreRestroomRepository implements RestroomRepository {
  final FirebaseFirestore? _firestore;
  final FirestoreQueryExecutor _queryExecutor;
  final FirebaseAuth? firebaseAuth;
  final AuthRepository? authRepository;

  FirestoreRestroomRepository({
    FirebaseFirestore? firestore,
    FirestoreQueryExecutor? queryExecutor,
    this.firebaseAuth,
    this.authRepository,
  }) : _firestore = firestore,
       _queryExecutor =
           queryExecutor ?? ProductionFirestoreQueryExecutor(firestore);

  FirebaseFirestore get _firestoreInstance =>
      _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestoreInstance.collection(AppConstants.restroomsCollection);

  String? get _currentUserId {
    if (authRepository?.currentUserId != null) {
      return authRepository!.currentUserId;
    }
    if (firebaseAuth != null) {
      return firebaseAuth?.currentUser?.uid;
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = AppConstants.defaultSearchRadiusMeters,
  }) async {
    // 1. Validate radius
    if (radiusMeters <= 0 ||
        radiusMeters.isNaN ||
        radiusMeters > AppConstants.maxSearchRadiusMeters) {
      throw InvalidRadiusException(
        'Search radius must be positive and not exceed ${AppConstants.maxSearchRadiusMeters} meters. Received: $radiusMeters',
      );
    }

    try {
      // 2. Generate conservative candidate prefixes covering the entire search circle
      final prefixes = GeohashService.getCandidatePrefixes(
        center,
        radiusMeters,
        maxRanges: AppConstants.maxGeohashQueryRanges,
      );

      bool rangeCapHit = false;
      bool perRangeDocLimitHit = false;
      bool candidateCapHit = false;
      bool resultCapHit = false;

      final limitedPrefixes = prefixes
          .take(AppConstants.maxGeohashQueryRanges)
          .toList();

      if (prefixes.length > AppConstants.maxGeohashQueryRanges) {
        rangeCapHit = true;
      }

      // 3. Execute bounded Firestore reads across prefixes
      final Map<String, Restroom> candidateMap = {};

      for (final prefix in limitedPrefixes) {
        if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
          candidateCapHit = true;
          break;
        }

        final docs = await _queryExecutor.queryRange(
          collectionPath: AppConstants.restroomsCollection,
          field: 'geohash',
          startAt: prefix,
          endAt: '$prefix~',
          limit: AppConstants.maxDocumentsPerRangeQuery,
        );

        if (docs.length >= AppConstants.maxDocumentsPerRangeQuery) {
          perRangeDocLimitHit = true;
        }

        for (final data in docs) {
          final id = data['id'] as String? ?? '';
          if (candidateMap.containsKey(id)) {
            continue; // Deduplicate overlapping candidate documents
          }
          try {
            final restroom = RestroomFirestoreCodec.fromFirestore(
              data,
              documentId: id,
            );
            candidateMap[id] = restroom;
          } catch (_) {
            // Skip documents with corrupted schema or non-compliant timestamps
            continue;
          }

          if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
            candidateCapHit = true;
            break;
          }
        }
      }

      // 4. Filter discoverable statuses: only active and unverified are public
      final discoverable = candidateMap.values.where((r) {
        return r.status == RestroomStatus.active ||
            r.status == RestroomStatus.unverified;
      });

      // 5. Exact Haversine distance filtering
      final inRadius = discoverable.where((r) {
        final dist = Haversine.distanceInMeters(center, r.coordinates);
        return dist <= radiusMeters;
      }).toList();

      // 6. Deterministic sorting: nearest first, then by restroom ID
      inRadius.sort((a, b) {
        final distA = Haversine.distanceInMeters(center, a.coordinates);
        final distB = Haversine.distanceInMeters(center, b.coordinates);
        final cmp = distA.compareTo(distB);
        if (cmp != 0) return cmp;
        return a.id.compareTo(b.id);
      });

      List<Restroom> finalResults = inRadius;
      // 7. Enforce max discovery results limit
      if (inRadius.length > AppConstants.maxDiscoveryResults) {
        resultCapHit = true;
        finalResults = inRadius.sublist(0, AppConstants.maxDiscoveryResults);
      }

      // Determine completeness
      final isComplete =
          !rangeCapHit &&
          !perRangeDocLimitHit &&
          !candidateCapHit &&
          !resultCapHit;

      final DiscoveryCompletenessReason reason;
      if (rangeCapHit) {
        reason = DiscoveryCompletenessReason.rangeCapExceeded;
      } else if (perRangeDocLimitHit) {
        reason = DiscoveryCompletenessReason.perRangeLimitExceeded;
      } else if (candidateCapHit) {
        reason = DiscoveryCompletenessReason.candidateLimitExceeded;
      } else if (resultCapHit) {
        reason = DiscoveryCompletenessReason.resultCapExceeded;
      } else {
        reason = DiscoveryCompletenessReason.complete;
      }

      return DiscoveryResult(
        items: finalResults,
        isComplete: isComplete,
        completenessReason: reason,
        rangeCount: limitedPrefixes.length,
        candidateCount: candidateMap.length,
      );
    } on AppException {
      rethrow;
    } on FirebaseException catch (e) {
      throw RepositoryException(
        e.message ?? 'Firestore error during nearby restroom discovery.',
        e.code,
      );
    } catch (e) {
      throw RepositoryException(
        'Unexpected error during nearby restroom discovery: $e',
      );
    }
  }

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async {
    // 1. Validate viewport bounds scale (reject global/country-scale viewports)
    final latSpan = bounds.latitudeSpan;
    final lngSpan = bounds.longitudeSpan;

    if (latSpan > AppConstants.maxViewportLatitudeSpan ||
        lngSpan > AppConstants.maxViewportLongitudeSpan) {
      throw ViewportTooLargeException(
        'Visible area exceeds safety bounds (lat span: ${latSpan.toStringAsFixed(2)}°, lng span: ${lngSpan.toStringAsFixed(2)}°). Zoom in to discover restrooms.',
      );
    }

    try {
      // 2. Generate candidate geohash prefixes covering viewport
      final prefixes = GeohashService.getViewportPrefixes(
        bounds,
        maxPrefixes: AppConstants.maxGeohashQueryRanges,
      );

      bool rangeCapHit = false;
      bool perRangeDocLimitHit = false;
      bool candidateCapHit = false;
      bool resultCapHit = false;

      final limitedPrefixes = prefixes
          .take(AppConstants.maxGeohashQueryRanges)
          .toList();

      if (prefixes.length > AppConstants.maxGeohashQueryRanges) {
        rangeCapHit = true;
      }

      final Map<String, Restroom> candidateMap = {};

      for (final prefix in limitedPrefixes) {
        if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
          candidateCapHit = true;
          break;
        }

        final docs = await _queryExecutor.queryRange(
          collectionPath: AppConstants.restroomsCollection,
          field: 'geohash',
          startAt: prefix,
          endAt: '$prefix~',
          limit: AppConstants.maxDocumentsPerRangeQuery,
        );

        if (docs.length >= AppConstants.maxDocumentsPerRangeQuery) {
          perRangeDocLimitHit = true;
        }

        for (final data in docs) {
          final id = data['id'] as String? ?? '';
          if (candidateMap.containsKey(id)) {
            continue; // Deduplicate
          }
          try {
            final restroom = RestroomFirestoreCodec.fromFirestore(
              data,
              documentId: id,
            );
            candidateMap[id] = restroom;
          } catch (_) {
            continue;
          }

          if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
            candidateCapHit = true;
            break;
          }
        }
      }

      // 3. Filter discoverable statuses: active and unverified only
      final discoverable = candidateMap.values.where((r) {
        return r.status == RestroomStatus.active ||
            r.status == RestroomStatus.unverified;
      });

      // 4. Exact bounding box post-filtering (antimeridian-aware via GeoBoundingBox.contains)
      final inViewport = discoverable.where((r) {
        return bounds.contains(r.coordinates);
      }).toList();

      // 5. Deterministic sorting by ID
      inViewport.sort((a, b) => a.id.compareTo(b.id));

      List<Restroom> finalResults = inViewport;
      if (inViewport.length > AppConstants.maxDiscoveryResults) {
        resultCapHit = true;
        finalResults = inViewport.sublist(0, AppConstants.maxDiscoveryResults);
      }

      final isComplete =
          !rangeCapHit &&
          !perRangeDocLimitHit &&
          !candidateCapHit &&
          !resultCapHit;

      final DiscoveryCompletenessReason reason;
      if (rangeCapHit) {
        reason = DiscoveryCompletenessReason.rangeCapExceeded;
      } else if (perRangeDocLimitHit) {
        reason = DiscoveryCompletenessReason.perRangeLimitExceeded;
      } else if (candidateCapHit) {
        reason = DiscoveryCompletenessReason.candidateLimitExceeded;
      } else if (resultCapHit) {
        reason = DiscoveryCompletenessReason.resultCapExceeded;
      } else {
        reason = DiscoveryCompletenessReason.complete;
      }

      return DiscoveryResult(
        items: finalResults,
        isComplete: isComplete,
        completenessReason: reason,
        rangeCount: limitedPrefixes.length,
        candidateCount: candidateMap.length,
      );
    } on AppException {
      rethrow;
    } on FirebaseException catch (e) {
      throw RepositoryException(
        e.message ?? 'Firestore error during viewport restroom discovery.',
        e.code,
      );
    } catch (e) {
      throw RepositoryException(
        'Unexpected error during viewport restroom discovery: $e',
      );
    }
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    final docSnapshot = await _collection.doc(id).get();
    final data = docSnapshot.data();
    if (!docSnapshot.exists || data == null) {
      return null;
    }
    return RestroomFirestoreCodec.fromFirestore(
      data,
      documentId: docSnapshot.id,
    );
  }

  @override
  Future<Restroom> submitRestroom(CreateRestroomCommand command) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      throw const UnauthenticatedException();
    }

    final normalized = command.draft.normalized();
    final validationErrors = normalized.validate();
    if (validationErrors.isNotEmpty) {
      throw RepositoryException(
        'Cannot submit invalid restroom draft: ${validationErrors.join(', ')}',
        'invalid-draft',
      );
    }

    final restroomRef = _firestoreInstance
        .collection(AppConstants.restroomsCollection)
        .doc(command.restroomId);
    final contributionRef = _firestoreInstance
        .collection('contributions')
        .doc('restroom_${command.restroomId}');

    // Ambiguous commit reconciliation: check whether either or both documents already exist
    try {
      final restroomSnap = await restroomRef.get();
      final contributionSnap = await contributionRef.get();

      if (restroomSnap.exists && contributionSnap.exists) {
        final rData = restroomSnap.data();
        final cData = contributionSnap.data();
        if (rData != null &&
            cData != null &&
            cData['resourceId'] == command.restroomId &&
            cData['userUid'] == uid) {
          return RestroomFirestoreCodec.fromFirestore(
            rData,
            documentId: command.restroomId,
          );
        } else {
          throw const SubmissionInvariantException(
            'Mismatched existing restroom and contribution pair.',
          );
        }
      } else if (restroomSnap.exists || contributionSnap.exists) {
        throw const SubmissionInvariantException(
          'Invariant violation: only one document of the atomic restroom pair exists.',
        );
      }
    } on AppException {
      rethrow;
    } on FirebaseException catch (e) {
      throw RepositoryException(
        e.message ??
            'Firestore error during pre-submission reconciliation read.',
        e.code,
      );
    } catch (e) {
      throw RepositoryException(
        'Unexpected error during pre-submission reconciliation read: $e',
      );
    }

    final geohash = GeohashService.encode(normalized.coordinates);

    final publicData = <String, dynamic>{
      'id': command.restroomId,
      'name': normalized.name,
      'latitude': normalized.coordinates.latitude,
      'longitude': normalized.coordinates.longitude,
      'geohash': geohash,
      if (normalized.countryCode != null) 'countryCode': normalized.countryCode,
      if (normalized.region != null) 'region': normalized.region,
      if (normalized.city != null) 'city': normalized.city,
      if (normalized.buildingName != null)
        'buildingName': normalized.buildingName,
      if (normalized.buildingSection != null)
        'buildingSection': normalized.buildingSection,
      if (normalized.floor != null) 'floor': normalized.floor,
      if (normalized.unitOrArea != null) 'unitOrArea': normalized.unitOrArea,
      if (normalized.landmark != null) 'landmark': normalized.landmark,
      if (normalized.directionsNote != null)
        'directionsNote': normalized.directionsNote,
      if (normalized.accessInstructions != null)
        'accessInstructions': normalized.accessInstructions,
      'accessType': normalized.accessType.value,
      if (normalized.feeAmount != null) 'feeAmount': normalized.feeAmount,
      if (normalized.feeCurrency != null) 'feeCurrency': normalized.feeCurrency,
      if (normalized.male != null) 'male': normalized.male,
      if (normalized.female != null) 'female': normalized.female,
      if (normalized.allGender != null) 'allGender': normalized.allGender,
      if (normalized.pwdAccessible.toNullableBool() != null)
        'pwdAccessible': normalized.pwdAccessible.toNullableBool(),
      if (normalized.babyChanging.toNullableBool() != null)
        'babyChanging': normalized.babyChanging.toNullableBool(),
      if (normalized.hasBidet.toNullableBool() != null)
        'hasBidet': normalized.hasBidet.toNullableBool(),
      if (normalized.hasToiletPaper.toNullableBool() != null)
        'hasToiletPaper': normalized.hasToiletPaper.toNullableBool(),
      if (normalized.hasSoap.toNullableBool() != null)
        'hasSoap': normalized.hasSoap.toNullableBool(),
      if (normalized.hasHandDryer.toNullableBool() != null)
        'hasHandDryer': normalized.hasHandDryer.toNullableBool(),
      'averageRating': 0.0,
      'ratingCount': 0,
      'verificationCount': 0,
      'negativeVerificationCount': 0,
      'status': RestroomStatus.unverified.value,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final privateContributionData = <String, dynamic>{
      'id': 'restroom_${command.restroomId}',
      'contributionType': 'restroom',
      'resourceId': command.restroomId,
      'restroomId': command.restroomId,
      'userUid': uid,
      'moderationState': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestoreInstance.batch();
    batch.set(restroomRef, publicData);
    batch.set(contributionRef, privateContributionData);

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      // Reconcile in case the write committed before network failure
      try {
        final retryRestroom = await restroomRef.get();
        final retryContribution = await contributionRef.get();
        if (retryRestroom.exists && retryContribution.exists) {
          final rData = retryRestroom.data();
          final cData = retryContribution.data();
          if (rData != null &&
              cData != null &&
              cData['resourceId'] == command.restroomId &&
              cData['userUid'] == uid) {
            return RestroomFirestoreCodec.fromFirestore(
              rData,
              documentId: command.restroomId,
            );
          }
        } else if (retryRestroom.exists || retryContribution.exists) {
          throw const SubmissionInvariantException(
            'Invariant violation: only one document of the atomic restroom pair exists.',
          );
        }
      } catch (recErr) {
        if (recErr is SubmissionInvariantException) rethrow;
      }
      throw RepositoryException(
        e.message ?? 'Firestore error submitting restroom.',
        e.code,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw RepositoryException('Unexpected error submitting restroom: $e');
    }

    return Restroom(
      id: command.restroomId,
      name: normalized.name,
      coordinates: normalized.coordinates,
      geohash: geohash,
      countryCode: normalized.countryCode,
      region: normalized.region,
      city: normalized.city,
      buildingName: normalized.buildingName,
      buildingSection: normalized.buildingSection,
      floor: normalized.floor,
      unitOrArea: normalized.unitOrArea,
      landmark: normalized.landmark,
      directionsNote: normalized.directionsNote,
      accessInstructions: normalized.accessInstructions,
      accessType: normalized.accessType,
      feeAmount: normalized.feeAmount,
      feeCurrency: normalized.feeCurrency,
      male: normalized.male,
      female: normalized.female,
      allGender: normalized.allGender,
      pwdAccessible: normalized.pwdAccessible.toNullableBool(),
      babyChanging: normalized.babyChanging.toNullableBool(),
      hasBidet: normalized.hasBidet.toNullableBool(),
      hasToiletPaper: normalized.hasToiletPaper.toNullableBool(),
      hasSoap: normalized.hasSoap.toNullableBool(),
      hasHandDryer: normalized.hasHandDryer.toNullableBool(),
      averageRating: 0.0,
      ratingCount: 0,
      verificationCount: 0,
      negativeVerificationCount: 0,
      lastVerifiedAt: null,
      status: RestroomStatus.unverified,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
