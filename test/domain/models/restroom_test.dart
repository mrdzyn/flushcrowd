import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/enums.dart';
import 'package:looradar/domain/models/restroom.dart';

void main() {
  group('Restroom Domain Model — Nullable Truth & Sentinel copyWith', () {
    final coords = Coordinates(latitude: 14.5839, longitude: 121.0617);
    final now = DateTime.utc(2026, 10, 1, 12, 0, 0);

    test(
      'amenities and stalls default to null rather than affirmative true',
      () {
        final restroom = Restroom(
          id: 'rr_defaults',
          name: 'Default Amenities Restroom',
          coordinates: coords,
          geohash: 'wdw4fq',
          createdAt: now,
        );

        // Verify all 9 amenity/stall fields default to null
        expect(restroom.male, isNull);
        expect(restroom.female, isNull);
        expect(restroom.allGender, isNull);
        expect(restroom.pwdAccessible, isNull);
        expect(restroom.babyChanging, isNull);
        expect(restroom.hasBidet, isNull);
        expect(restroom.hasToiletPaper, isNull);
        expect(restroom.hasSoap, isNull);
        expect(restroom.hasHandDryer, isNull);
        expect(restroom.accessInstructions, isNull);
      },
    );

    test('copyWith preserves existing values when parameters are omitted', () {
      final original = Restroom(
        id: 'rr_copy_1',
        name: 'Original Name',
        coordinates: coords,
        geohash: 'wdw4fq',
        hasBidet: true,
        hasToiletPaper: false,
        pwdAccessible: null,
        accessInstructions: 'Ring doorbell',
        createdAt: now,
      );

      final copy = original.copyWith(name: 'Updated Name');

      expect(copy.id, original.id);
      expect(copy.name, 'Updated Name');
      expect(copy.hasBidet, isTrue);
      expect(copy.hasToiletPaper, isFalse);
      expect(copy.pwdAccessible, isNull);
      expect(copy.accessInstructions, 'Ring doorbell');
    });

    test(
      'copyWith clears values to null when explicitly passed null via sentinel',
      () {
        final original = Restroom(
          id: 'rr_copy_2',
          name: 'Original Name',
          coordinates: coords,
          geohash: 'wdw4fq',
          hasBidet: true,
          hasToiletPaper: true,
          accessInstructions: 'Code 1234',
          feeAmount: 5.0,
          feeCurrency: 'USD',
          createdAt: now,
        );

        final cleared = original.copyWith(
          hasBidet: null,
          accessInstructions: null,
          feeAmount: null,
          feeCurrency: null,
        );

        expect(cleared.hasBidet, isNull);
        expect(cleared.hasToiletPaper, isTrue); // preserved
        expect(cleared.accessInstructions, isNull);
        expect(cleared.feeAmount, isNull);
        expect(cleared.feeCurrency, isNull);
      },
    );

    test('toMap and fromMap serialize and deserialize nullable amenities truthfully', () {
      final restroom = Restroom(
        id: 'rr_map_test',
        name: 'Map Restroom',
        coordinates: coords,
        geohash: 'wdw4fq',
        male: true,
        female: false,
        allGender: null,
        pwdAccessible: true,
        babyChanging: null,
        hasBidet: true,
        hasToiletPaper: false,
        hasSoap: null,
        hasHandDryer: true,
        accessInstructions: 'Entrance on B1',
        accessType: AccessType.paid,
        feeAmount: 20.0,
        feeCurrency: 'PHP',
        createdAt: now,
      );

      final map = restroom.toMap();

      // Privacy checks
      expect(map.containsKey('createdByUid'), isFalse);
      expect(map.containsKey('userUid'), isFalse);
      expect(map.containsKey('uid'), isFalse);

      // Value checks
      expect(map['male'], isTrue);
      expect(map['female'], isFalse);
      expect(map['allGender'], isNull);
      expect(map['hasBidet'], isTrue);
      expect(map['hasToiletPaper'], isFalse);
      expect(map['hasSoap'], isNull);
      expect(map['accessInstructions'], 'Entrance on B1');
      expect(map['feeAmount'], 20.0);
      expect(map['feeCurrency'], 'PHP');

      final restored = Restroom.fromMap(map, documentId: 'rr_map_test');
      expect(restored.male, isTrue);
      expect(restored.female, isFalse);
      expect(restored.allGender, isNull);
      expect(restored.pwdAccessible, isTrue);
      expect(restored.babyChanging, isNull);
      expect(restored.hasBidet, isTrue);
      expect(restored.hasToiletPaper, isFalse);
      expect(restored.hasSoap, isNull);
      expect(restored.hasHandDryer, isTrue);
      expect(restored.accessInstructions, 'Entrance on B1');
      expect(restored.feeAmount, 20.0);
      expect(restored.feeCurrency, 'PHP');
    });

    test(
      'fromMap decodes legacy missing fields as null, NEVER defaulting to true',
      () {
        // Legacy document without amenity fields
        final legacyMap = <String, dynamic>{
          'name': 'Legacy Facility',
          'latitude': coords.latitude,
          'longitude': coords.longitude,
          'geohash': 'wdw4fq',
          'accessType': 'free',
          'status': 'active',
          'averageRating': 0.0,
          'ratingCount': 0,
        };

        final restored = Restroom.fromMap(legacyMap, documentId: 'rr_legacy');

        // Crucial data truth invariant: missing legacy fields must NOT default to true!
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
      },
    );
  });
}
