import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/rating.dart';
import 'package:flushcrowd/domain/models/report.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/models/verification.dart';

void main() {
  group('Domain Models & Privacy Isolation', () {
    test('Restroom model serializes and deserializes correctly', () {
      final now = DateTime.now();
      final restroom = Restroom(
        id: 'rr_123',
        name: 'Central Mall Restroom',
        coordinates: Coordinates(latitude: 14.5500, longitude: 121.0500),
        geohash: 'wdw4fq',
        buildingName: 'Central Mall',
        floor: '2F',
        directionsNote: 'Beside food court elevator',
        accessType: AccessType.customerOnly,
        hasBidet: true,
        hasToiletPaper: true,
        pwdAccessible: true,
        averageRating: 4.5,
        ratingCount: 10,
        createdAt: now,
      );

      final map = restroom.toMap();

      // Privacy Check: Public serialization must NOT contain contributor UID
      expect(map.containsKey('createdByUid'), isFalse);
      expect(map.containsKey('userUid'), isFalse);
      expect(map.containsKey('uid'), isFalse);

      final restored = Restroom.fromMap(map, documentId: 'rr_123');
      expect(restored.id, 'rr_123');
      expect(restored.name, 'Central Mall Restroom');
      expect(
        restored.coordinates,
        Coordinates(latitude: 14.5500, longitude: 121.0500),
      );
      expect(restored.accessType, AccessType.customerOnly);
      expect(restored.hasBidet, isTrue);
      expect(restored.pwdAccessible, isTrue);
      expect(restored.averageRating, 4.5);
    });

    test(
      'Rating model serializes and deserializes correctly without user UID',
      () {
        final now = DateTime.now();
        final rating = Rating(
          id: 'rate_1',
          restroomId: 'rr_123',
          overall: 4.5,
          cleanliness: 5.0,
          supplies: 4.0,
          comment: 'Very clean and has bidet!',
          createdAt: now,
        );

        final map = rating.toMap();
        expect(map.containsKey('userUid'), isFalse);
        expect(map.containsKey('userId'), isFalse);

        final restored = Rating.fromMap(map, documentId: 'rate_1');
        expect(restored.overall, 4.5);
        expect(restored.cleanliness, 5.0);
        expect(restored.comment, 'Very clean and has bidet!');
      },
    );

    test('Verification model serializes and deserializes correctly', () {
      final verification = Verification(
        id: 'ver_1',
        restroomId: 'rr_123',
        result: VerificationResult.confirmed,
        createdAt: DateTime.now(),
      );

      final map = verification.toMap();
      expect(map.containsKey('userUid'), isFalse);

      final restored = Verification.fromMap(map, documentId: 'ver_1');
      expect(restored.result, VerificationResult.confirmed);
    });

    test('RestroomReport model serializes and deserializes correctly', () {
      const report = RestroomReport(
        id: 'rep_1',
        restroomId: 'rr_123',
        reason: ReportReason.wrongLocation,
        notes: 'Pin is 50 meters off to the east',
        status: ReportStatus.pending,
      );

      final map = report.toMap();
      final restored = RestroomReport.fromMap(map, documentId: 'rep_1');
      expect(restored.reason, ReportReason.wrongLocation);
      expect(restored.notes, 'Pin is 50 meters off to the east');
      expect(restored.status, ReportStatus.pending);
    });

    test('Enum parsing supports all variations and defaults safely', () {
      expect(AccessType.fromString('free'), AccessType.free);
      expect(AccessType.fromString('customer_only'), AccessType.customerOnly);
      expect(AccessType.fromString('unknown_val'), AccessType.free);

      expect(RestroomStatus.fromString('active'), RestroomStatus.active);
      expect(RestroomStatus.fromString('removed'), RestroomStatus.removed);
      expect(RestroomStatus.fromString(null), RestroomStatus.active);

      expect(
        VerificationResult.fromString('confirmed'),
        VerificationResult.confirmed,
      );
      expect(
        VerificationResult.fromString('not_found'),
        VerificationResult.notFound,
      );
      expect(VerificationResult.fromString(null), VerificationResult.confirmed);

      expect(ReportReason.fromString('duplicate'), ReportReason.duplicate);
      expect(
        ReportReason.fromString('wrong_location'),
        ReportReason.wrongLocation,
      );
      expect(ReportReason.fromString('invalid'), ReportReason.other);

      expect(ReportStatus.fromString('pending'), ReportStatus.pending);
      expect(ReportStatus.fromString('resolved'), ReportStatus.resolved);
      expect(ReportStatus.fromString(null), ReportStatus.pending);
    });
  });
}
