import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../services/firebase/firestore_codec.dart';
import '../services/gis/geohash_service.dart';

import '../../core/errors/exceptions.dart';
import '../../domain/models/enums.dart';
import '../services/gis/haversine.dart';

/// Cloud Firestore implementation of [RestroomRepository].
///
/// Implements P1.1 production GIS and Firestore discovery engine:
/// - Geohash candidate range generation (center + neighbors)
/// - Bounded queries per range with document and candidate safety caps
/// - Exact Haversine and viewport bounds post-filtering
/// - Deterministic deduplication and distance sorting
/// - Discoverable status filtering (active, unverified only)
/// - FirebaseException mapping to repository exceptions
class FirestoreRestroomRepository implements RestroomRepository {
  final FirebaseFirestore? _firestore;

  FirestoreRestroomRepository({this._firestore});

  CollectionReference<Map<String, dynamic>> get _collection =>
      (_firestore ?? FirebaseFirestore.instance).collection(
        AppConstants.restroomsCollection,
      );

  @override
  Future<List<Restroom>> getNearbyRestrooms(
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
      // 2. Generate bounded candidate geohash prefixes (center + 8 neighbors)
      final prefixes = GeohashService.getCandidatePrefixes(
        center,
        radiusMeters,
      );

      // Enforce query range cap
      final limitedPrefixes = prefixes
          .take(AppConstants.maxGeohashQueryRanges)
          .toList();

      // 3. Execute bounded Firestore reads across prefixes
      final Map<String, Restroom> candidateMap = {};

      for (final prefix in limitedPrefixes) {
        if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
          break;
        }

        final querySnapshot = await _collection
            .where('geohash', isGreaterThanOrEqualTo: prefix)
            .where('geohash', isLessThanOrEqualTo: '$prefix~')
            .limit(AppConstants.maxDocumentsPerRangeQuery)
            .get();

        for (final doc in querySnapshot.docs) {
          if (candidateMap.containsKey(doc.id)) {
            continue; // Deduplicate overlapping candidate documents
          }
          final data = doc.data();
          try {
            final restroom = RestroomFirestoreCodec.fromFirestore(
              data,
              documentId: doc.id,
            );
            candidateMap[doc.id] = restroom;
          } catch (_) {
            // Skip documents with corrupted schema or non-compliant timestamps
            continue;
          }

          if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
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

      // 7. Enforce max discovery results limit
      if (inRadius.length > AppConstants.maxDiscoveryResults) {
        return inRadius.sublist(0, AppConstants.maxDiscoveryResults);
      }

      return inRadius;
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
  Future<List<Restroom>> getViewportRestrooms(GeoBoundingBox bounds) async {
    // 1. Validate viewport bounds scale (reject global/country-scale viewports)
    final latSpan = (bounds.northEast.latitude - bounds.southWest.latitude)
        .abs();
    double lngSpan = bounds.northEast.longitude - bounds.southWest.longitude;
    if (lngSpan < 0) {
      lngSpan += 360.0;
    }

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

      final Map<String, Restroom> candidateMap = {};

      for (final prefix in prefixes) {
        if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
          break;
        }

        final querySnapshot = await _collection
            .where('geohash', isGreaterThanOrEqualTo: prefix)
            .where('geohash', isLessThanOrEqualTo: '$prefix~')
            .limit(AppConstants.maxDocumentsPerRangeQuery)
            .get();

        for (final doc in querySnapshot.docs) {
          if (candidateMap.containsKey(doc.id)) {
            continue; // Deduplicate
          }
          final data = doc.data();
          try {
            final restroom = RestroomFirestoreCodec.fromFirestore(
              data,
              documentId: doc.id,
            );
            candidateMap[doc.id] = restroom;
          } catch (_) {
            continue;
          }

          if (candidateMap.length >= AppConstants.maxCandidateDocuments) {
            break;
          }
        }
      }

      // 3. Filter discoverable statuses: active and unverified only
      final discoverable = candidateMap.values.where((r) {
        return r.status == RestroomStatus.active ||
            r.status == RestroomStatus.unverified;
      });

      // 4. Exact bounding box post-filtering
      final inViewport = discoverable.where((r) {
        return bounds.contains(r.coordinates);
      }).toList();

      // 5. Deterministic sorting by ID
      inViewport.sort((a, b) => a.id.compareTo(b.id));

      if (inViewport.length > AppConstants.maxDiscoveryResults) {
        return inViewport.sublist(0, AppConstants.maxDiscoveryResults);
      }

      return inViewport;
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
