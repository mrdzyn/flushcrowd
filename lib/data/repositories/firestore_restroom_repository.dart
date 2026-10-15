import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/config/app_config.dart';
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
import '../services/firebase/firestore_mutation_adapter.dart';
import '../services/firebase/firestore_query_executor.dart';
import '../services/firebase/restroom_submission_transport.dart';
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
  final RestroomSubmissionTransport _submissionTransport;
  final AppConfig? _appConfig;
  final FirebaseAuth? firebaseAuth;
  final AuthRepository? authRepository;

  FirestoreRestroomRepository({
    FirebaseFirestore? firestore,
    FirestoreQueryExecutor? queryExecutor,
    FirestoreMutationAdapter? mutationAdapter,
    RestroomSubmissionTransport? submissionTransport,
    AppConfig? appConfig,
    this.firebaseAuth,
    this.authRepository,
  }) : _firestore = firestore,
       _appConfig = appConfig,
       _queryExecutor =
           queryExecutor ?? ProductionFirestoreQueryExecutor(firestore),
       _submissionTransport =
           submissionTransport ??
           ((appConfig?.useCallableSubmission ?? false)
               ? CallableRestroomSubmissionTransport(
                   pointReadAdapter:
                       mutationAdapter ??
                       ProductionFirestoreMutationAdapter(firestore),
                 )
               : DirectFirestoreRestroomSubmissionTransport(
                   mutationAdapter ??
                       ProductionFirestoreMutationAdapter(firestore),
                 ));

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
    return _queryNearbyRestrooms(
      center: center,
      radiusMeters: radiusMeters,
      maxDocsPerRange: AppConstants.maxDocumentsPerRangeQuery,
      maxCandidates: AppConstants.maxCandidateDocuments,
      maxResults: AppConstants.maxDiscoveryResults,
    );
  }

  @override
  Future<DiscoveryResult<Restroom>> getDuplicateCandidates(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) async {
    return _queryNearbyRestrooms(
      center: center,
      radiusMeters: radiusMeters,
      maxDocsPerRange: 20,
      maxCandidates: 320,
      maxResults: 320,
    );
  }

  Future<DiscoveryResult<Restroom>> _queryNearbyRestrooms({
    required Coordinates center,
    required double radiusMeters,
    required int maxDocsPerRange,
    required int maxCandidates,
    required int maxResults,
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
        if (candidateMap.length >= maxCandidates) {
          candidateCapHit = true;
          break;
        }

        final docs = await _queryExecutor.queryRange(
          collectionPath: AppConstants.restroomsCollection,
          field: 'geohash',
          startAt: prefix,
          endAt: '$prefix~',
          limit: maxDocsPerRange,
        );

        if (docs.length >= maxDocsPerRange) {
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

          if (candidateMap.length >= maxCandidates) {
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
      if (inRadius.length > maxResults) {
        resultCapHit = true;
        finalResults = inRadius.sublist(0, maxResults);
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

    // Defense-in-depth environment checks if AppConfig is configured
    final config = _appConfig;
    if (config != null) {
      if (config.isProduction) {
        throw const RepositoryException(
          'Community restroom contributions are currently disabled in production until server-side abuse protections are active (Milestone P2.6).',
          'production-writes-blocked',
        );
      }
      if (!config.isStaging) {
        throw const RepositoryException(
          'Community restroom contributions are only permitted in the verified staging environment.',
          'non-staging-environment',
        );
      }
      if (config.firebaseProjectId != AppConstants.stagingFirebaseProjectId) {
        throw const RepositoryException(
          'Community restroom contributions are restricted to the verified staging Firebase project (${AppConstants.stagingFirebaseProjectId}).',
          'staging-project-mismatch',
        );
      }
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

    // 4. Delegate to configured submission transport (Direct or Callable)
    return await _submissionTransport.submitRestroom(
      command: command,
      uid: uid,
    );
  }
}
