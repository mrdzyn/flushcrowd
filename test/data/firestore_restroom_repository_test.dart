import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/constants/app_constants.dart';
import 'package:looradar/core/errors/exceptions.dart';
import 'package:looradar/data/repositories/firestore_restroom_repository.dart';
import 'package:looradar/data/services/firebase/firestore_query_executor.dart';
import 'package:looradar/data/services/gis/geohash_service.dart';
import 'package:looradar/data/services/gis/haversine.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/discovery_result.dart';
import 'package:looradar/domain/models/geo_bounding_box.dart';

/// Test double that simulates Firestore's range query execution against an in-memory document store.
class FakeFirestoreQueryExecutor implements FirestoreQueryExecutor {
  final List<Map<String, dynamic>> documents;
  final bool throwFirebaseException;
  int recordedQueryCount = 0;
  final List<int> returnedBatchSizes = [];

  FakeFirestoreQueryExecutor({
    List<Map<String, dynamic>>? documents,
    this.throwFirebaseException = false,
  }) : documents = documents ?? [];

  @override
  Future<List<Map<String, dynamic>>> queryRange({
    required String collectionPath,
    required String field,
    required String startAt,
    required String endAt,
    required int limit,
  }) async {
    recordedQueryCount++;
    if (throwFirebaseException) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'The service is temporarily unavailable.',
      );
    }

    final matches = documents
        .where((doc) {
          final val = doc[field];
          if (val is! String) return false;
          return val.compareTo(startAt) >= 0 && val.compareTo(endAt) <= 0;
        })
        .take(limit)
        .toList();

    returnedBatchSizes.add(matches.length);
    return matches;
  }
}

Map<String, dynamic> _makeRestroomDoc({
  required String id,
  required String name,
  required double latitude,
  required double longitude,
  String status = 'active',
  String accessType = 'free',
  double? averageRating,
  int ratingCount = 0,
}) {
  final coords = Coordinates(latitude: latitude, longitude: longitude);
  final geohash = GeohashService.encode(coords, precision: 9);
  return {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'geohash': geohash,
    'status': status,
    'accessType': accessType,
    'isAccessible': true,
    'hasGenderNeutral': false,
    'hasBabyChanging': false,
    'averageRating': averageRating,
    'ratingCount': ratingCount,
    'isVerified': false,
    'verificationCount': 0,
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
  };
}

void main() {
  group('FirestoreRestroomRepository Production Discovery Engine', () {
    test(
      'discovers center cell and adjacent cell facilities within radius',
      () async {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
        // Doc 1: Very close to center (~50m)
        final doc1 = _makeRestroomDoc(
          id: 'rr_center',
          name: 'Center Facility',
          latitude: 14.5841,
          longitude: 121.0619,
        );
        // Doc 2: Adjacent cell, ~500m away
        final doc2 = _makeRestroomDoc(
          id: 'rr_adj',
          name: 'Adjacent Cell Facility',
          latitude: 14.5880,
          longitude: 121.0620,
        );

        final executor = FakeFirestoreQueryExecutor(documents: [doc1, doc2]);
        final repo = FirestoreRestroomRepository(queryExecutor: executor);

        final result = await repo.getNearbyRestrooms(
          center,
          radiusMeters: 1000.0,
        );

        expect(result.isComplete, isTrue);
        expect(result.completenessReason, DiscoveryCompletenessReason.complete);
        expect(
          result.items.map((r) => r.id),
          containsAll(['rr_center', 'rr_adj']),
        );
        expect(executor.recordedQueryCount, greaterThan(0));
      },
    );

    test('exact Haversine filter strips out-of-radius facilities in candidate geohash cells', () async {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
      // Facility inside same precision-5 geohash cell envelope, but distance is ~1200m (radius is 500m)
      final docNear = _makeRestroomDoc(
        id: 'rr_inside',
        name: 'Inside Radius',
        latitude: 14.5842,
        longitude: 121.0620,
      );
      final docOutside = _makeRestroomDoc(
        id: 'rr_outside',
        name: 'Outside Radius',
        latitude: 14.5950,
        longitude: 121.0620,
      );

      final executor = FakeFirestoreQueryExecutor(
        documents: [docNear, docOutside],
      );
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(center, radiusMeters: 500.0);

      expect(result.isComplete, isTrue);
      expect(result.items.map((r) => r.id), contains('rr_inside'));
      expect(result.items.map((r) => r.id), isNot(contains('rr_outside')));
    });

    test('deduplicates documents appearing across multiple query ranges deterministically', () async {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
      final doc = _makeRestroomDoc(
        id: 'rr_single',
        name: 'Deduplicated Facility',
        latitude: 14.5839,
        longitude: 121.0617,
      );

      // Duplicate the document in storage
      final executor = FakeFirestoreQueryExecutor(documents: [doc, doc, doc]);
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(center, radiusMeters: 500.0);

      expect(result.items.length, 1);
      expect(result.items.first.id, 'rr_single');
    });

    test('filters discoverable status: active & unverified included, non-discoverable excluded', () async {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
      final activeDoc = _makeRestroomDoc(
        id: 'active_1',
        name: 'Active',
        latitude: 14.5839,
        longitude: 121.0617,
        status: 'active',
      );
      final unverifiedDoc = _makeRestroomDoc(
        id: 'unverified_1',
        name: 'Unverified',
        latitude: 14.5840,
        longitude: 121.0618,
        status: 'unverified',
      );
      final flaggedDoc = _makeRestroomDoc(
        id: 'flagged_1',
        name: 'Flagged',
        latitude: 14.5841,
        longitude: 121.0619,
        status: 'flagged',
      );
      final removedDoc = _makeRestroomDoc(
        id: 'removed_1',
        name: 'Removed',
        latitude: 14.5842,
        longitude: 121.0620,
        status: 'removed',
      );
      final unavailDoc = _makeRestroomDoc(
        id: 'unavail_1',
        name: 'Unavailable',
        latitude: 14.5843,
        longitude: 121.0621,
        status: 'temporarily_unavailable',
      );

      final executor = FakeFirestoreQueryExecutor(
        documents: [
          activeDoc,
          unverifiedDoc,
          flaggedDoc,
          removedDoc,
          unavailDoc,
        ],
      );
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        center,
        radiusMeters: 1000.0,
      );

      final returnedIds = result.items.map((r) => r.id).toList();
      expect(returnedIds, containsAll(['active_1', 'unverified_1']));
      expect(returnedIds, isNot(contains('flagged_1')));
      expect(returnedIds, isNot(contains('removed_1')));
      expect(returnedIds, isNot(contains('unavail_1')));
    });

    test(
      'sorts nearby results deterministically by Haversine distance ascending',
      () async {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final docFar = _makeRestroomDoc(
          id: 'rr_far',
          name: 'Far',
          latitude: 14.5900,
          longitude: 121.0617,
        );
        final docClose = _makeRestroomDoc(
          id: 'rr_close',
          name: 'Close',
          latitude: 14.5845,
          longitude: 121.0617,
        );
        final docMid = _makeRestroomDoc(
          id: 'rr_mid',
          name: 'Mid',
          latitude: 14.5870,
          longitude: 121.0617,
        );

        final executor = FakeFirestoreQueryExecutor(
          documents: [docFar, docClose, docMid],
        );
        final repo = FirestoreRestroomRepository(queryExecutor: executor);

        final result = await repo.getNearbyRestrooms(
          center,
          radiusMeters: 2000.0,
        );

        expect(result.items.map((r) => r.id).toList(), [
          'rr_close',
          'rr_mid',
          'rr_far',
        ]);
      },
    );

    test(
      'gracefully skips corrupt documents without aborting discovery',
      () async {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final goodDoc = _makeRestroomDoc(
          id: 'rr_good',
          name: 'Good',
          latitude: 14.5840,
          longitude: 121.0618,
        );
        final corruptDoc = {
          'id': 'rr_bad',
          'name': 12345, // corrupt: name is not String
          'latitude': 'invalid', // corrupt: not double
          'geohash': GeohashService.encode(center),
        };

        final executor = FakeFirestoreQueryExecutor(
          documents: [goodDoc, corruptDoc],
        );
        final repo = FirestoreRestroomRepository(queryExecutor: executor);

        final result = await repo.getNearbyRestrooms(
          center,
          radiusMeters: 1000.0,
        );

        expect(result.items.length, 1);
        expect(result.items.first.id, 'rr_good');
      },
    );

    test('surfaces perRangeLimitExceeded reason when a geohash range query hits page cap', () async {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
      final centerPrefix = GeohashService.encode(center, precision: 6);
      // Create docs with same geohash prefix equal to maxDocumentsPerRangeQuery
      final docs = List.generate(AppConstants.maxDocumentsPerRangeQuery, (i) {
        final doc = _makeRestroomDoc(
          id: 'rr_dense_$i',
          name: 'Dense $i',
          latitude: center.latitude,
          longitude: center.longitude,
        );
        doc['geohash'] = '$centerPrefix${i.toString().padLeft(3, '0')}';
        return doc;
      });

      final executor = FakeFirestoreQueryExecutor(documents: docs);
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(center, radiusMeters: 500.0);

      expect(result.isComplete, isFalse);
      expect(
        result.completenessReason,
        DiscoveryCompletenessReason.perRangeLimitExceeded,
      );
    });

    test('surfaces candidateLimitExceeded reason when total candidate docs exceed safety cap', () async {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
      final prefixes = GeohashService.getCandidatePrefixes(center, 2000.0);
      expect(prefixes.length, greaterThanOrEqualTo(6));
      expect(
        prefixes.length,
        lessThanOrEqualTo(AppConstants.maxGeohashQueryRanges),
      );

      // Generate 205 docs distributed across prefixes so no single prefix hits 50 docs
      // (e.g. 205 docs across >= 6 prefixes gives at most ~35 docs per prefix < 50)
      final docs = List.generate(AppConstants.maxCandidateDocuments + 5, (i) {
        final prefix = prefixes[i % prefixes.length];
        final doc = _makeRestroomDoc(
          id: 'rr_cand_$i',
          name: 'Cand $i',
          latitude: center.latitude,
          longitude: center.longitude,
        );
        doc['geohash'] =
            '$prefix${(i ~/ prefixes.length).toString().padLeft(3, '0')}';
        return doc;
      });

      final executor = FakeFirestoreQueryExecutor(documents: docs);
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        center,
        radiusMeters: 2000.0,
      );

      expect(result.isComplete, isFalse);
      expect(
        result.completenessReason,
        DiscoveryCompletenessReason.candidateLimitExceeded,
      );
    });

    test('surfaces resultCapExceeded reason when filtered results exceed maxDiscoveryResults', () async {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
      final prefixes = GeohashService.getCandidatePrefixes(center, 2000.0);
      expect(prefixes.length, greaterThanOrEqualTo(6));

      // Generate 105 active valid docs inside radius distributed across prefixes so no single prefix hits 50 docs
      final docs = List.generate(AppConstants.maxDiscoveryResults + 5, (i) {
        final prefix = prefixes[i % prefixes.length];
        final doc = _makeRestroomDoc(
          id: 'rr_res_$i',
          name: 'Result $i',
          latitude: center.latitude,
          longitude: center.longitude,
        );
        doc['geohash'] =
            '$prefix${(i ~/ prefixes.length).toString().padLeft(3, '0')}';
        return doc;
      });

      final executor = FakeFirestoreQueryExecutor(documents: docs);
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        center,
        radiusMeters: 2000.0,
      );

      expect(result.isComplete, isFalse);
      expect(
        result.completenessReason,
        DiscoveryCompletenessReason.resultCapExceeded,
      );
      expect(result.items.length, AppConstants.maxDiscoveryResults);
    });

    test(
      'maps FirebaseException to RepositoryException in repository layer',
      () async {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final executor = FakeFirestoreQueryExecutor(
          throwFirebaseException: true,
        );
        final repo = FirestoreRestroomRepository(queryExecutor: executor);

        expect(
          () => repo.getNearbyRestrooms(center, radiusMeters: 1000.0),
          throwsA(isA<RepositoryException>()),
        );
      },
    );

    test(
      'discovers facilities in viewport and filters strictly to bounding box',
      () async {
        final bounds = GeoBoundingBox(
          southWest: Coordinates(latitude: 14.5800, longitude: 121.0500),
          northEast: Coordinates(latitude: 14.5900, longitude: 121.0600),
        );

        final inViewDoc = _makeRestroomDoc(
          id: 'in_view',
          name: 'In View',
          latitude: 14.5850,
          longitude: 121.0550,
        );
        final outViewDoc = _makeRestroomDoc(
          id: 'out_view',
          name: 'Out View',
          latitude: 14.5950,
          longitude: 121.0550,
        );

        final executor = FakeFirestoreQueryExecutor(
          documents: [inViewDoc, outViewDoc],
        );
        final repo = FirestoreRestroomRepository(queryExecutor: executor);

        final result = await repo.getViewportRestrooms(bounds);

        expect(result.isComplete, isTrue);
        expect(result.items.length, 1);
        expect(result.items.first.id, 'in_view');
      },
    );

    test(
      'handles antimeridian-crossing viewport discovery correctly',
      () async {
        final antimeridianBounds = GeoBoundingBox(
          southWest: Coordinates(latitude: -16.60, longitude: 179.95),
          northEast: Coordinates(latitude: -16.40, longitude: -179.95),
        );

        final docEast = _makeRestroomDoc(
          id: 'rr_fiji_east',
          name: 'Fiji East',
          latitude: -16.50,
          longitude: 179.98,
        );
        final docWest = _makeRestroomDoc(
          id: 'rr_fiji_west',
          name: 'Fiji West',
          latitude: -16.50,
          longitude: -179.98,
        );
        final docOut = _makeRestroomDoc(
          id: 'rr_fiji_out',
          name: 'Fiji Out',
          latitude: -16.50,
          longitude: 178.00,
        );

        final executor = FakeFirestoreQueryExecutor(
          documents: [docEast, docWest, docOut],
        );
        final repo = FirestoreRestroomRepository(queryExecutor: executor);

        final result = await repo.getViewportRestrooms(antimeridianBounds);

        expect(result.isComplete, isTrue);
        final ids = result.items.map((r) => r.id).toList();
        expect(ids, containsAll(['rr_fiji_east', 'rr_fiji_west']));
        expect(ids, isNot(contains('rr_fiji_out')));
      },
    );

    test('handles polar queries with safe range-cap degradation without continental-scale precision scans', () async {
      final centerNorth = Coordinates(latitude: 89.99, longitude: 0.0);
      // Facility located within search radius in one of the first queried ranges:
      // Polar prefixes at precision 3 are sorted lexicographically starting with 'b...' (around -180° lng).
      // At 89.99° N, -179.0° E is ~1112m from the north pole, and distance to 89.99° N, -179.0° E is 0m.
      // Let's place a restroom at (89.99° N, 0.0° E)
      final docNorth = _makeRestroomDoc(
        id: 'rr_north_pole',
        name: 'North Pole Station',
        latitude: 89.99,
        longitude: 0.0,
      );

      final executor = FakeFirestoreQueryExecutor(documents: [docNorth]);
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        centerNorth,
        radiusMeters: 1000.0,
      );

      // Polar search requires full-longitude coverage (256 candidate ranges at precision 3).
      // Since 256 > AppConstants.maxGeohashQueryRanges (16), the repository safely degrades:
      // queries only 16 ranges, marks isComplete as false, and signals rangeCapExceeded.
      expect(result.isComplete, isFalse);
      expect(
        result.completenessReason,
        DiscoveryCompletenessReason.rangeCapExceeded,
      );
      expect(executor.recordedQueryCount, AppConstants.maxGeohashQueryRanges);
    });

    test('surfaces rangeCapExceeded reason deterministically under real production 16-range budget', () async {
      final centerNearPole = Coordinates(latitude: 89.99, longitude: 0.0);
      final candidatePrefixes = GeohashService.getCandidatePrefixes(
        centerNearPole,
        1000.0,
      );

      // Verify naturally occurring production condition: candidate prefixes exceed 16 ranges
      expect(
        candidatePrefixes.length,
        greaterThan(AppConstants.maxGeohashQueryRanges),
      );
      // Verify all candidate prefixes respect the minimum safe query precision
      expect(
        candidatePrefixes.every(
          (p) => p.length >= AppConstants.minDiscoveryGeohashPrecision,
        ),
        isTrue,
      );

      final executor = FakeFirestoreQueryExecutor();
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        centerNearPole,
        radiusMeters: 1000.0,
      );

      expect(result.isComplete, isFalse);
      expect(
        result.completenessReason,
        DiscoveryCompletenessReason.rangeCapExceeded,
      );
      // Executor should only query the real production range cap (16)
      expect(executor.recordedQueryCount, AppConstants.maxGeohashQueryRanges);
    });

    test('candidate prefixes never coarsen below minDiscoveryGeohashPrecision across all latitudes', () {
      final testCases = [
        Coordinates(latitude: 0.0, longitude: 0.0), // Equator
        Coordinates(
          latitude: 14.5839,
          longitude: 121.0617,
        ), // Manila (tropical)
        Coordinates(
          latitude: 60.1699,
          longitude: 24.9384,
        ), // Helsinki (high latitude)
        Coordinates(latitude: 89.99, longitude: 0.0), // North Pole
        Coordinates(latitude: -89.99, longitude: 0.0), // South Pole
      ];

      for (final center in testCases) {
        for (final radius in [500.0, 1500.0, 5000.0, 10000.0]) {
          final prefixes = GeohashService.getCandidatePrefixes(center, radius);
          expect(prefixes, isNotEmpty);
          for (final prefix in prefixes) {
            expect(
              prefix.length,
              greaterThanOrEqualTo(AppConstants.minDiscoveryGeohashPrecision),
              reason:
                  'Candidate prefix "$prefix" at center $center (radius: $radius) is shorter than minimum safe precision (${AppConstants.minDiscoveryGeohashPrecision})',
            );
          }
        }
      }
    });

    test('discovers facility located in non-immediate geohash cell within search radius', () async {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
      // Precision 6 cell is ~610m tall x ~1180m wide.
      // Center geohash prefix:
      final centerHash6 = GeohashService.encode(center, precision: 6);
      final centerNeighbors = GeohashService.neighbors(centerHash6);
      final immediateCellSet = {
        centerHash6,
        ...centerNeighbors.values.whereType<String>(),
      };

      // At radius 2500m, precision 5 cells are used (~4.9km x ~4.9km).
      // Let's place a facility at ~2100m away (inside 2500m radius).
      // 2100m north: dLat = 2100 / 6371000 * (180 / pi) = ~0.01888 deg.
      final nonImmediateCoords = Coordinates(
        latitude: center.latitude + 0.01888,
        longitude: center.longitude,
      );
      final nonImmediateHash6 = GeohashService.encode(
        nonImmediateCoords,
        precision: 6,
      );
      // Confirm this facility is outside immediate 9 precision-6 cells:
      expect(immediateCellSet, isNot(contains(nonImmediateHash6)));

      // And distance is inside 2500m radius:
      final dist = Haversine.distanceInMeters(center, nonImmediateCoords);
      expect(dist, lessThanOrEqualTo(2500.0));
      expect(dist, greaterThan(1500.0));

      final docNonImm = _makeRestroomDoc(
        id: 'rr_non_immediate',
        name: 'Non Immediate Cell Facility',
        latitude: nonImmediateCoords.latitude,
        longitude: nonImmediateCoords.longitude,
      );

      final executor = FakeFirestoreQueryExecutor(documents: [docNonImm]);
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        center,
        radiusMeters: 2500.0,
      );

      expect(result.isComplete, isTrue);
      expect(result.items.map((r) => r.id), contains('rr_non_immediate'));
    });

    test(
      'discovers facility near 10 km boundary with complete status',
      () async {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
        // Place facility at 9,900m (< 10,000m radius)
        // dLat = 9900 / 6371000 * 180 / pi = 0.08905 deg
        final boundaryCoords = Coordinates(
          latitude: center.latitude + 0.08905,
          longitude: center.longitude,
        );
        final dist = Haversine.distanceInMeters(center, boundaryCoords);
        expect(dist, lessThanOrEqualTo(10000.0));
        expect(dist, greaterThan(9800.0));

        final docBoundary = _makeRestroomDoc(
          id: 'rr_boundary_10km',
          name: '10km Outer Edge Facility',
          latitude: boundaryCoords.latitude,
          longitude: boundaryCoords.longitude,
        );

        final executor = FakeFirestoreQueryExecutor(documents: [docBoundary]);
        final repo = FirestoreRestroomRepository(queryExecutor: executor);

        final result = await repo.getNearbyRestrooms(
          center,
          radiusMeters: 10000.0,
        );

        expect(result.isComplete, isTrue);
        expect(result.completenessReason, DiscoveryCompletenessReason.complete);
        expect(result.items.map((r) => r.id), contains('rr_boundary_10km'));
      },
    );

    test('center/local prefixes are prioritized when rangeCapExceeded occurs in nearby discovery', () async {
      // Near-pole scenario where prefix count (256) exceeds 16-range query limit
      final centerNearPole = Coordinates(latitude: 89.99, longitude: 0.0);

      // Facility 1: Right at the search center (0m away)
      final docCenter = _makeRestroomDoc(
        id: 'rr_center_priority',
        name: 'Center Priority Facility',
        latitude: 89.99,
        longitude: 0.0,
      );

      // Facility 2: Far away in an outer candidate prefix across opposite meridian (180° lng)
      final docFar = _makeRestroomDoc(
        id: 'rr_far_outer',
        name: 'Far Outer Facility',
        latitude: 89.99,
        longitude: 180.0,
      );

      final executor = FakeFirestoreQueryExecutor(
        documents: [docCenter, docFar],
      );
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        centerNearPole,
        radiusMeters: 1000.0,
      );

      expect(result.isComplete, isFalse);
      expect(
        result.completenessReason,
        DiscoveryCompletenessReason.rangeCapExceeded,
      );
      expect(executor.recordedQueryCount, AppConstants.maxGeohashQueryRanges);

      // The center facility MUST be found in the 16 prioritized ranges
      final foundIds = result.items.map((r) => r.id).toList();
      expect(foundIds, contains('rr_center_priority'));
      // The distant opposite-meridian facility is in a dropped outer range
      expect(foundIds, isNot(contains('rr_far_outer')));
    });

    test('viewport discovery prioritizes ranges nearest to viewport center under rangeCapExceeded', () async {
      // Large viewport that requires tiling with center-proximity sorting
      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.0, longitude: 120.0),
        northEast: Coordinates(latitude: 14.4, longitude: 120.4),
      );
      final center = bounds.center;

      final prefixes = GeohashService.getViewportPrefixes(bounds);
      expect(prefixes.length, greaterThanOrEqualTo(2));

      // First prefix must be closer to viewport center than the last prefix
      final firstCenter = GeohashService.decodeCenter(prefixes.first);
      final lastCenter = GeohashService.decodeCenter(prefixes.last);
      final distFirst = Haversine.distanceInMeters(center, firstCenter);
      final distLast = Haversine.distanceInMeters(center, lastCenter);

      expect(distFirst, lessThanOrEqualTo(distLast));
    });
  });
}
