import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/discovery_result.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/geo_bounding_box.dart';
import '../../domain/models/restroom.dart';
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

  FirestoreRestroomRepository({
    FirebaseFirestore? firestore,
    FirestoreQueryExecutor? queryExecutor,
  }) : _firestore = firestore,
       _queryExecutor =
           queryExecutor ?? ProductionFirestoreQueryExecutor(firestore);

  CollectionReference<Map<String, dynamic>> get _collection =>
      (_firestore ?? FirebaseFirestore.instance).collection(
        AppConstants.restroomsCollection,
      );

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
  Future<void> submitRestroom(Restroom restroom) async {
    final data = RestroomFirestoreCodec.toFirestore(restroom);
    // Use server timestamp for creation/update to prevent client clock skew
    data['updatedAt'] = FieldValue.serverTimestamp();
    if (restroom.id.isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await _collection.add(data);
    } else {
      await _collection.doc(restroom.id).set(data, SetOptions(merge: true));
    }
  }
}
