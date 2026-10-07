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
import '../../domain/models/restroom_draft.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../services/firebase/firestore_codec.dart';
import '../services/firebase/firestore_mutation_adapter.dart';
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
  final FirestoreMutationAdapter _mutationAdapter;
  final FirebaseAuth? firebaseAuth;
  final AuthRepository? authRepository;

  FirestoreRestroomRepository({
    FirebaseFirestore? firestore,
    FirestoreQueryExecutor? queryExecutor,
    FirestoreMutationAdapter? mutationAdapter,
    this.firebaseAuth,
    this.authRepository,
  }) : _firestore = firestore,
       _queryExecutor =
           queryExecutor ?? ProductionFirestoreQueryExecutor(firestore),
       _mutationAdapter =
           mutationAdapter ?? ProductionFirestoreMutationAdapter(firestore);

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
    // 1. Authenticate
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      throw const UnauthenticatedException();
    }

    // 2. Validate stable restroom ID (MINOR-2)
    final restroomId = command.restroomId;
    if (restroomId.isEmpty ||
        restroomId != restroomId.trim() ||
        restroomId.length > 100 ||
        restroomId.contains('/') ||
        restroomId == '.' ||
        restroomId == '..') {
      throw const RepositoryException(
        'Invalid stable restroom ID: must be non-empty, cannot contain leading/trailing whitespace, <= 100 characters, and contain no path separators.',
        'invalid-restroom-id',
      );
    }

    // 3. Normalize & validate draft
    final normalized = command.draft.normalized();
    final validationErrors = normalized.validate();
    if (validationErrors.isNotEmpty) {
      throw RepositoryException(
        'Cannot submit invalid restroom draft: ${validationErrors.join(', ')}',
        'invalid-draft',
      );
    }

    // 4. Derive geohash
    final geohash = GeohashService.encode(normalized.coordinates);

    // 5. Build public payload
    final publicData = <String, dynamic>{
      'id': restroomId,
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

    // 6. Build private contribution payload
    final privateContributionData = <String, dynamic>{
      'id': 'restroom_$restroomId',
      'contributionType': 'restroom',
      'resourceId': restroomId,
      'restroomId': restroomId,
      'userUid': uid,
      'moderationState': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 7. Execute ONE atomic batch directly without pre-reads (BLOCKER-1)
    try {
      await _mutationAdapter.commitRestroomSubmissionBatch(
        restroomId: restroomId,
        publicData: publicData,
        contributionId: 'restroom_$restroomId',
        contributionData: privateContributionData,
      );
    } catch (batchError) {
      // Ambiguous commit reconciliation (MAJOR-1, MAJOR-2)
      try {
        final publicDoc = await _mutationAdapter.getPublicRestroom(restroomId);
        if (publicDoc == null) {
          // Public document does not exist: do NOT read private contribution
          if (batchError is AppException) rethrow;
          if (batchError is FirebaseException) {
            throw RepositoryException(
              batchError.message ?? 'Firestore error submitting restroom.',
              batchError.code,
            );
          }
          throw RepositoryException(
            'Unexpected error submitting restroom: $batchError',
          );
        }

        // Public document exists: read private contribution (MAJOR-2)
        FirestoreDocumentData? privateDoc;
        try {
          privateDoc = await _mutationAdapter.getPrivateContribution(
            'restroom_$restroomId',
          );
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            throw const SubmissionInvariantException(
              'Unable to verify the private contribution paired with this restroom.',
            );
          }
          if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
            throw RepositoryException(
              e.message ??
                  'Transient network error during reconciliation read.',
              e.code,
            );
          }
          rethrow;
        }

        if (privateDoc == null) {
          throw const SubmissionInvariantException(
            'Invariant violation: public restroom exists but private contribution is missing or unreadable.',
          );
        }

        // Both exist: validate complete pair
        _validateReconciliationPair(
          restroomId: restroomId,
          publicDoc: publicDoc,
          privateDoc: privateDoc,
          normalized: normalized,
          geohash: geohash,
          uid: uid,
        );

        // Valid committed pair reconciles as success
        return RestroomFirestoreCodec.fromFirestore(
          publicDoc.data,
          documentId: publicDoc.documentId,
        );
      } catch (recErr) {
        if (recErr is SubmissionInvariantException) rethrow;
        if (recErr is RepositoryException) rethrow;
        throw RepositoryException(
          'Reconciliation failed following ambiguous submission error: $recErr',
        );
      }
    }

    // 8. Return successfully submitted Restroom with null timestamps (MINOR-3)
    return Restroom(
      id: restroomId,
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
      createdAt: null,
      updatedAt: null,
    );
  }

  static void _validateReconciliationPair({
    required String restroomId,
    required FirestoreDocumentData publicDoc,
    required FirestoreDocumentData privateDoc,
    required RestroomDraft normalized,
    required String geohash,
    required String uid,
  }) {
    // 1. Public identity & status checks (validates both documentId and stored data['id'] independently)
    final publicDocId = publicDoc.documentId;
    final publicStoredId = publicDoc.data['id'] as String?;
    final publicStatus = publicDoc.data['status'] as String?;
    if (publicDocId != restroomId ||
        publicStoredId != restroomId ||
        publicStatus != RestroomStatus.unverified.value) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom identity or status mismatch.',
      );
    }

    // 2. Public immutable command fields check
    final name = publicDoc.data['name'] as String?;
    final lat = (publicDoc.data['latitude'] as num?)?.toDouble();
    final lng = (publicDoc.data['longitude'] as num?)?.toDouble();
    final docGeohash = publicDoc.data['geohash'] as String?;
    final accessType = publicDoc.data['accessType'] as String?;

    if (name != normalized.name ||
        lat != normalized.coordinates.latitude ||
        lng != normalized.coordinates.longitude ||
        docGeohash != geohash ||
        accessType != normalized.accessType.value) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom data does not match submission command.',
      );
    }

    // Location context & instructions
    if (publicDoc.data['countryCode'] != normalized.countryCode ||
        publicDoc.data['region'] != normalized.region ||
        publicDoc.data['city'] != normalized.city ||
        publicDoc.data['buildingName'] != normalized.buildingName ||
        publicDoc.data['buildingSection'] != normalized.buildingSection ||
        publicDoc.data['floor'] != normalized.floor ||
        publicDoc.data['unitOrArea'] != normalized.unitOrArea ||
        publicDoc.data['landmark'] != normalized.landmark ||
        publicDoc.data['directionsNote'] != normalized.directionsNote ||
        publicDoc.data['accessInstructions'] != normalized.accessInstructions) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom context does not match submission command.',
      );
    }

    // Fees
    final feeAmount = (publicDoc.data['feeAmount'] as num?)?.toDouble();
    if (feeAmount != normalized.feeAmount ||
        publicDoc.data['feeCurrency'] != normalized.feeCurrency) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom fee configuration does not match submission command.',
      );
    }

    // Stalls & Amenities
    if (publicDoc.data['male'] != normalized.male ||
        publicDoc.data['female'] != normalized.female ||
        publicDoc.data['allGender'] != normalized.allGender ||
        publicDoc.data['pwdAccessible'] !=
            normalized.pwdAccessible.toNullableBool() ||
        publicDoc.data['babyChanging'] !=
            normalized.babyChanging.toNullableBool() ||
        publicDoc.data['hasBidet'] != normalized.hasBidet.toNullableBool() ||
        publicDoc.data['hasToiletPaper'] !=
            normalized.hasToiletPaper.toNullableBool() ||
        publicDoc.data['hasSoap'] != normalized.hasSoap.toNullableBool() ||
        publicDoc.data['hasHandDryer'] !=
            normalized.hasHandDryer.toNullableBool()) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom stalls or amenities do not match submission command.',
      );
    }

    // 3. Private contribution checks (validates both documentId and stored data['id'] independently)
    final privateDocId = privateDoc.documentId;
    final contribId = privateDoc.data['id'] as String?;
    final contribType = privateDoc.data['contributionType'] as String?;
    final resourceId = privateDoc.data['resourceId'] as String?;
    final contribRestroomId = privateDoc.data['restroomId'] as String?;
    final userUid = privateDoc.data['userUid'] as String?;
    final moderationState = privateDoc.data['moderationState'] as String?;

    if (privateDocId != 'restroom_$restroomId' ||
        contribId != 'restroom_$restroomId' ||
        contribType != 'restroom' ||
        resourceId != restroomId ||
        contribRestroomId != restroomId ||
        userUid != uid ||
        moderationState != 'pending') {
      throw const SubmissionInvariantException(
        'Invariant violation: private contribution metadata mismatch.',
      );
    }
  }
}
