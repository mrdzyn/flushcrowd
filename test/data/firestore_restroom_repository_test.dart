import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/constants/app_constants.dart';
import 'package:looradar/core/errors/exceptions.dart';
import 'package:looradar/data/repositories/firestore_restroom_repository.dart';
import 'package:looradar/data/services/firebase/firestore_query_executor.dart';
import 'package:looradar/data/services/gis/geohash_service.dart';
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
      // Generate 205 docs across various prefixes
      final docs = List.generate(
        AppConstants.maxCandidateDocuments + 5,
        (i) => _makeRestroomDoc(
          id: 'rr_cand_$i',
          name: 'Cand $i',
          latitude: 14.5839 + (i * 0.0001),
          longitude: 121.0617,
        ),
      );

      final executor = FakeFirestoreQueryExecutor(documents: docs);
      final repo = FirestoreRestroomRepository(queryExecutor: executor);

      final result = await repo.getNearbyRestrooms(
        center,
        radiusMeters: 5000.0,
      );

      expect(result.isComplete, isFalse);
      expect(
        result.completenessReason,
        isIn([
          DiscoveryCompletenessReason.candidateLimitExceeded,
          DiscoveryCompletenessReason.perRangeLimitExceeded,
        ]),
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
  });
}
