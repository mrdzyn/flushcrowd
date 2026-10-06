import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/data/services/firebase/firestore_codec.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/enums.dart';
import 'package:looradar/domain/models/rating.dart';
import 'package:looradar/domain/models/report.dart';
import 'package:looradar/domain/models/restroom.dart';
import 'package:looradar/domain/models/verification.dart';

void main() {
  group('FirestoreCodec Timestamp Conversions', () {
    test('dateTimeToTimestamp correctly converts DateTime to Timestamp', () {
      final dateTime = DateTime.utc(2026, 9, 30, 12, 34, 56);
      final timestamp = FirestoreCodec.dateTimeToTimestamp(dateTime);

      expect(timestamp, isNotNull);
      expect(timestamp, isA<Timestamp>());
      expect(timestamp!.toDate().toUtc(), dateTime);
    });

    test('dateTimeToTimestamp returns null for null DateTime', () {
      final timestamp = FirestoreCodec.dateTimeToTimestamp(null);
      expect(timestamp, isNull);
    });

    test('timestampToDateTime correctly converts Timestamp to DateTime', () {
      final originalDateTime = DateTime.utc(2026, 9, 30, 12, 34, 56);
      final timestamp = Timestamp.fromDate(originalDateTime);
      final dateTime = FirestoreCodec.timestampToDateTime(timestamp);

      expect(dateTime, isNotNull);
      expect(dateTime, originalDateTime);
    });

    test('timestampToDateTime returns null for null input', () {
      final dateTime = FirestoreCodec.timestampToDateTime(null);
      expect(dateTime, isNull);
    });

    test('timestampToDateTime throws FormatException on malformed/unsupported types', () {
      // String input instead of Firestore Timestamp
      expect(
        () => FirestoreCodec.timestampToDateTime(
          '2026-09-30T12:34:56.000Z',
          fieldName: 'createdAt',
        ),
        throwsFormatException,
      );

      // Integer/epoch input instead of Firestore Timestamp
      expect(
        () => FirestoreCodec.timestampToDateTime(
          1759235696000,
          fieldName: 'updatedAt',
        ),
        throwsFormatException,
      );

      // Boolean input
      expect(
        () => FirestoreCodec.timestampToDateTime(
          true,
          fieldName: 'lastVerifiedAt',
        ),
        throwsFormatException,
      );
    });
  });

  group('RestroomFirestoreCodec', () {
    final testCoords = Coordinates(latitude: 37.7749, longitude: -122.4194);
    final now = DateTime.utc(2026, 9, 30, 14, 0, 0);

    final testRestroom = Restroom(
      id: 'rr_test_101',
      name: 'Yerba Buena Gardens Restroom',
      coordinates: testCoords,
      geohash: '9q8yyk',
      countryCode: 'US',
      region: 'CA',
      city: 'San Francisco',
      buildingName: 'Yerba Buena Center',
      floor: '1F',
      directionsNote: 'Next to carousel',
      accessType: AccessType.free,
      feeAmount: null,
      feeCurrency: null,
      male: true,
      female: true,
      allGender: true,
      pwdAccessible: true,
      babyChanging: true,
      hasBidet: false,
      hasToiletPaper: true,
      hasSoap: true,
      hasHandDryer: true,
      averageRating: 4.2,
      ratingCount: 15,
      verificationCount: 8,
      negativeVerificationCount: 1,
      lastVerifiedAt: now.subtract(const Duration(days: 1)),
      status: RestroomStatus.active,
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now,
    );

    test('toFirestore converts DateTime to Firestore Timestamp and protects privacy', () {
      final map = RestroomFirestoreCodec.toFirestore(testRestroom);

      expect(map['createdAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());
      expect(map['lastVerifiedAt'], isA<Timestamp>());

      // Invariant: Zero contributor UIDs in public document map
      expect(map.containsKey('createdByUid'), isFalse);
      expect(map.containsKey('userUid'), isFalse);
      expect(map.containsKey('userId'), isFalse);
      expect(map.containsKey('authorUid'), isFalse);
      expect(map.containsKey('uid'), isFalse);
    });

    test('Round-trip serialization preserves all fields', () {
      final firestoreMap = RestroomFirestoreCodec.toFirestore(testRestroom);
      final restored = RestroomFirestoreCodec.fromFirestore(
        firestoreMap,
        documentId: testRestroom.id,
      );

      expect(restored.id, testRestroom.id);
      expect(restored.name, testRestroom.name);
      expect(restored.coordinates, testRestroom.coordinates);
      expect(restored.geohash, testRestroom.geohash);
      expect(restored.accessType, testRestroom.accessType);
      expect(restored.status, testRestroom.status);
      expect(restored.createdAt, testRestroom.createdAt);
      expect(restored.updatedAt, testRestroom.updatedAt);
      expect(restored.lastVerifiedAt, testRestroom.lastVerifiedAt);
      expect(restored.averageRating, testRestroom.averageRating);
      expect(restored.ratingCount, testRestroom.ratingCount);
    });

    test('toFirestore and fromFirestore preserve nullable booleans and accessInstructions', () {
      final nullableRestroom = Restroom(
        id: 'rr_nullables',
        name: 'Nullable Facility',
        coordinates: testCoords,
        geohash: '9q8yyk',
        accessType: AccessType.paid,
        feeAmount: 25.5,
        feeCurrency: 'EUR',
        accessInstructions: 'Key with manager at front desk',
        male: true,
        female: false,
        allGender: null,
        pwdAccessible: null,
        babyChanging: true,
        hasBidet: null,
        hasToiletPaper: false,
        hasSoap: true,
        hasHandDryer: null,
        createdAt: now,
      );

      final map = RestroomFirestoreCodec.toFirestore(nullableRestroom);
      expect(map['male'], isTrue);
      expect(map['female'], isFalse);
      expect(map['allGender'], isNull);
      expect(map['hasBidet'], isNull);
      expect(map['hasToiletPaper'], isFalse);
      expect(map['hasSoap'], isTrue);
      expect(map['hasHandDryer'], isNull);
      expect(map['accessInstructions'], 'Key with manager at front desk');
      expect(map['feeAmount'], 25.5);
      expect(map['feeCurrency'], 'EUR');

      final restored = RestroomFirestoreCodec.fromFirestore(
        map,
        documentId: nullableRestroom.id,
      );
      expect(restored.male, isTrue);
      expect(restored.female, isFalse);
      expect(restored.allGender, isNull);
      expect(restored.pwdAccessible, isNull);
      expect(restored.babyChanging, isTrue);
      expect(restored.hasBidet, isNull);
      expect(restored.hasToiletPaper, isFalse);
      expect(restored.hasSoap, isTrue);
      expect(restored.hasHandDryer, isNull);
      expect(restored.accessInstructions, 'Key with manager at front desk');
      expect(restored.feeAmount, 25.5);
      expect(restored.feeCurrency, 'EUR');
    });

    test(
      'fromFirestore decodes legacy documents with missing fields as null',
      () {
        final legacyMap = <String, dynamic>{
          'name': 'Legacy Facility',
          'latitude': testCoords.latitude,
          'longitude': testCoords.longitude,
          'geohash': '9q8yyk',
          'accessType': 'free',
          'status': 'active',
          'averageRating': 0.0,
          'ratingCount': 0,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        };

        final restored = RestroomFirestoreCodec.fromFirestore(
          legacyMap,
          documentId: 'rr_legacy',
        );

        // Data truth invariant: missing fields must NEVER default to true
        expect(restored.male, isNull);
        expect(restored.female, isNull);
        expect(restored.allGender, isNull);
        expect(restored.pwdAccessible, isNull);
        expect(restored.babyChanging, isNull);
        expect(restored.hasBidet, isNull);
        expect(restored.hasToiletPaper, isNull);
        expect(restored.hasSoap, isNull);
        expect(restored.hasHandDryer, isNull);
        expect(restored.accessInstructions, isNull);
        expect(restored.feeAmount, isNull);
        expect(restored.feeCurrency, isNull);
      },
    );

    test(
      'fromFirestore throws FormatException when timestamp is raw ISO String',
      () {
        final invalidMap = <String, dynamic>{
          'id': 'rr_bad_ts',
          'name': 'Invalid Restroom',
          'latitude': 37.77,
          'longitude': -122.41,
          'geohash': '9q8yyk',
          'accessType': 'free',
          'status': 'active',
          'createdAt':
              '2026-09-30T12:00:00.000Z', // Should be Timestamp, not String!
          'updatedAt': '2026-09-30T12:00:00.000Z',
        };

        expect(
          () => RestroomFirestoreCodec.fromFirestore(invalidMap),
          throwsFormatException,
        );
      },
    );
  });

  group('RatingFirestoreCodec', () {
    final now = DateTime.utc(2026, 9, 30, 15, 0, 0);
    final rating = Rating(
      id: 'rate_202',
      restroomId: 'rr_test_101',
      overall: 4.5,
      cleanliness: 4.0,
      supplies: 5.0,
      accessibility: 4.0,
      privacy: 5.0,
      comment: 'Very clean with automatic soap dispensers',
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now,
    );

    test('toFirestore serializes timestamps and strictly omits userUid', () {
      final map = RatingFirestoreCodec.toFirestore(rating);

      expect(map['createdAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());
      expect(map.containsKey('userUid'), isFalse);
      expect(map.containsKey('createdByUid'), isFalse);
    });

    test('Rating round-trip preserves all fields', () {
      final map = RatingFirestoreCodec.toFirestore(rating);
      final restored = RatingFirestoreCodec.fromFirestore(
        map,
        documentId: rating.id,
      );

      expect(restored.id, rating.id);
      expect(restored.restroomId, rating.restroomId);
      expect(restored.overall, rating.overall);
      expect(restored.cleanliness, rating.cleanliness);
      expect(restored.createdAt, rating.createdAt);
      expect(restored.updatedAt, rating.updatedAt);
    });
  });

  group('RestroomReportFirestoreCodec & VerificationFirestoreCodec', () {
    final now = DateTime.utc(2026, 9, 30, 16, 0, 0);

    test('RestroomReport round-trip preserves fields', () {
      final report = RestroomReport(
        id: 'rep_303',
        restroomId: 'rr_test_101',
        reason: ReportReason.wrongLocation,
        notes: 'Door is locked from 6PM',
        status: ReportStatus.pending,
        createdAt: now,
      );

      final map = RestroomReportFirestoreCodec.toFirestore(
        report,
        userUid: 'anon_user_xyz',
      );
      expect(map['userUid'], 'anon_user_xyz');
      expect(map['createdAt'], isA<Timestamp>());

      final restored = RestroomReportFirestoreCodec.fromFirestore(
        map,
        documentId: report.id,
      );
      expect(restored.id, report.id);
      expect(restored.restroomId, report.restroomId);
      expect(restored.reason, ReportReason.wrongLocation);
      expect(restored.createdAt, report.createdAt);
    });

    test('Verification round-trip preserves fields and excludes userUid', () {
      final verification = Verification(
        id: 'ver_404',
        restroomId: 'rr_test_101',
        result: VerificationResult.confirmed,
        createdAt: now,
      );

      final map = VerificationFirestoreCodec.toFirestore(verification);
      expect(map['createdAt'], isA<Timestamp>());
      expect(map.containsKey('userUid'), isFalse);

      final restored = VerificationFirestoreCodec.fromFirestore(
        map,
        documentId: verification.id,
      );
      expect(restored.id, verification.id);
      expect(restored.result, VerificationResult.confirmed);
      expect(restored.createdAt, verification.createdAt);
    });
  });
}
