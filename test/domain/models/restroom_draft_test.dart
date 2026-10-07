import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/errors/exceptions.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/enums.dart';
import 'package:looradar/domain/models/restroom_draft.dart';

void main() {
  group('TriStateAmenity Mapping', () {
    test('toNullableBool maps accurately', () {
      expect(TriStateAmenity.yes.toNullableBool(), isTrue);
      expect(TriStateAmenity.no.toNullableBool(), isFalse);
      expect(TriStateAmenity.unknown.toNullableBool(), isNull);
    });

    test('fromNullableBool maps accurately', () {
      expect(TriStateAmenity.fromNullableBool(true), TriStateAmenity.yes);
      expect(TriStateAmenity.fromNullableBool(false), TriStateAmenity.no);
      expect(TriStateAmenity.fromNullableBool(null), TriStateAmenity.unknown);
    });
  });

  group('RestroomDraft Normalization', () {
    test('normalized() trims strings, converts whitespace-only optionals to null, and uppercases currency', () {
      final draft = RestroomDraft(
        name: '  Clean Restroom  ',
        coordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
        accessType: AccessType.paid,
        feeAmount: 10.0,
        feeCurrency: '  php  ',
        buildingName: '   ',
        floor: '  2F  ',
        directionsNote: '   ',
        accessInstructions: '  Ask cashier for code  ',
      );

      final normalized = draft.normalized();

      expect(normalized.name, 'Clean Restroom');
      expect(normalized.feeCurrency, 'PHP');
      expect(normalized.buildingName, isNull);
      expect(normalized.floor, '2F');
      expect(normalized.directionsNote, isNull);
      expect(normalized.accessInstructions, 'Ask cashier for code');
    });

    test('normalized() handles null optionals cleanly', () {
      final draft = RestroomDraft(
        name: 'Park Toilet',
        coordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
        accessType: AccessType.free,
      );

      final normalized = draft.normalized();

      expect(normalized.name, 'Park Toilet');
      expect(normalized.feeAmount, isNull);
      expect(normalized.feeCurrency, isNull);
      expect(normalized.buildingName, isNull);
      expect(normalized.floor, isNull);
      expect(normalized.directionsNote, isNull);
      expect(normalized.accessInstructions, isNull);
    });
  });

  group('RestroomDraft Validation', () {
    final validCoords = Coordinates(latitude: 14.5839, longitude: 121.0617);

    test('validates valid draft without error', () {
      final draft = RestroomDraft(
        name: 'Valid Restroom',
        coordinates: validCoords,
        accessType: AccessType.free,
        male: true,
        female: true,
      );

      expect(draft.validate(), isEmpty);
    });

    test('rejects empty or whitespace-only name', () {
      final draftEmpty = RestroomDraft(
        name: '',
        coordinates: validCoords,
        accessType: AccessType.free,
      );
      expect(draftEmpty.validate(), contains('Facility name is required'));

      final draftWhitespace = RestroomDraft(
        name: '    ',
        coordinates: validCoords,
        accessType: AccessType.free,
      );
      expect(
        draftWhitespace.normalized().validate(),
        contains('Facility name is required'),
      );
    });

    test('rejects name longer than 100 characters', () {
      final draftLongName = RestroomDraft(
        name: 'A' * 101,
        coordinates: validCoords,
        accessType: AccessType.free,
      );
      expect(
        draftLongName.validate(),
        contains('Facility name cannot exceed 100 characters'),
      );
    });

    test('rejects invalid coordinates', () {
      expect(
        () => Coordinates(latitude: 91.0, longitude: 121.0),
        throwsA(isA<InvalidCoordinatesException>()),
      );
      expect(
        () => Coordinates(latitude: 14.0, longitude: 181.0),
        throwsA(isA<InvalidCoordinatesException>()),
      );
    });

    test('rejects buildingName longer than 100 characters', () {
      final draft = RestroomDraft(
        name: 'Mall Restroom',
        coordinates: validCoords,
        accessType: AccessType.free,
        buildingName: 'B' * 101,
      );
      expect(
        draft.validate(),
        contains('Building name cannot exceed 100 characters'),
      );
    });

    test('rejects floor longer than 20 characters', () {
      final draft = RestroomDraft(
        name: 'Mall Restroom',
        coordinates: validCoords,
        accessType: AccessType.free,
        floor: 'F' * 21,
      );
      expect(
        draft.validate(),
        contains('Floor identifier cannot exceed 20 characters'),
      );
    });

    test('rejects directionsNote longer than 500 characters', () {
      final draft = RestroomDraft(
        name: 'Mall Restroom',
        coordinates: validCoords,
        accessType: AccessType.free,
        directionsNote: 'D' * 501,
      );
      expect(
        draft.validate(),
        contains('Directions note cannot exceed 500 characters'),
      );
    });

    test('rejects accessInstructions longer than 300 characters', () {
      final draft = RestroomDraft(
        name: 'Mall Restroom',
        coordinates: validCoords,
        accessType: AccessType.free,
        accessInstructions: 'I' * 301,
      );
      expect(
        draft.validate(),
        contains('Access instructions cannot exceed 300 characters'),
      );
    });

    test(
      'paid access type requires valid fee amount and 3-letter currency',
      () {
        // Missing amount
        final draftNoAmount = RestroomDraft(
          name: 'Paid Restroom',
          coordinates: validCoords,
          accessType: AccessType.paid,
          feeCurrency: 'USD',
        );
        expect(
          draftNoAmount.validate(),
          contains(
            'Paid restrooms require a valid fee amount between 0 and 1,000,000',
          ),
        );

        // Negative amount
        final draftNegAmount = RestroomDraft(
          name: 'Paid Restroom',
          coordinates: validCoords,
          accessType: AccessType.paid,
          feeAmount: -5.0,
          feeCurrency: 'USD',
        );
        expect(
          draftNegAmount.validate(),
          contains(
            'Paid restrooms require a valid fee amount between 0 and 1,000,000',
          ),
        );

        // Amount exceeds cap
        final draftHugeAmount = RestroomDraft(
          name: 'Paid Restroom',
          coordinates: validCoords,
          accessType: AccessType.paid,
          feeAmount: 1000001.0,
          feeCurrency: 'USD',
        );
        expect(
          draftHugeAmount.validate(),
          contains(
            'Paid restrooms require a valid fee amount between 0 and 1,000,000',
          ),
        );

        // Missing currency
        final draftNoCurrency = RestroomDraft(
          name: 'Paid Restroom',
          coordinates: validCoords,
          accessType: AccessType.paid,
          feeAmount: 5.0,
        );
        expect(
          draftNoCurrency.validate(),
          contains(
            'Fee currency must be a valid 3-letter uppercase code (e.g., USD)',
          ),
        );

        // Currency not 3 characters
        final draftBadCurrency = RestroomDraft(
          name: 'Paid Restroom',
          coordinates: validCoords,
          accessType: AccessType.paid,
          feeAmount: 5.0,
          feeCurrency: 'US',
        );
        expect(
          draftBadCurrency.validate(),
          contains(
            'Fee currency must be a valid 3-letter uppercase code (e.g., USD)',
          ),
        );

        // Valid paid restroom
        final draftValidPaid = RestroomDraft(
          name: 'Paid Restroom',
          coordinates: validCoords,
          accessType: AccessType.paid,
          feeAmount: 5.0,
          feeCurrency: 'USD',
        );
        expect(draftValidPaid.validate(), isEmpty);
      },
    );

    test('rejects draft where all gender stalls are explicitly false', () {
      final draftAllFalse = RestroomDraft(
        name: 'Restroom No Stalls',
        coordinates: validCoords,
        accessType: AccessType.free,
        male: false,
        female: false,
        allGender: false,
      );
      expect(
        draftAllFalse.validate(),
        contains('Select applicable gender stalls or leave all unspecified'),
      );
    });

    test(
      'accepts draft where gender stalls are null or at least one is true',
      () {
        final draftNull = RestroomDraft(
          name: 'Restroom Unspecified Stalls',
          coordinates: validCoords,
          accessType: AccessType.free,
          male: null,
          female: null,
          allGender: null,
        );
        expect(draftNull.validate(), isEmpty);

        final draftOneTrue = RestroomDraft(
          name: 'Restroom Male Only',
          coordinates: validCoords,
          accessType: AccessType.free,
          male: true,
          female: false,
          allGender: false,
        );
        expect(draftOneTrue.validate(), isEmpty);
      },
    );
  });
}
