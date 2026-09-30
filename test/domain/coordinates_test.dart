import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/errors/exceptions.dart';
import 'package:looradar/domain/models/coordinates.dart';

void main() {
  group('Coordinates Value Object', () {
    test('creates valid coordinates within bounds', () {
      final coords = Coordinates(latitude: 14.5839, longitude: 121.0617);
      expect(coords.latitude, 14.5839);
      expect(coords.longitude, 121.0617);
    });

    test('accepts extreme boundary values', () {
      expect(
        () => Coordinates(latitude: 90.0, longitude: 180.0),
        returnsNormally,
      );
      expect(
        () => Coordinates(latitude: -90.0, longitude: -180.0),
        returnsNormally,
      );
      expect(() => Coordinates(latitude: 0.0, longitude: 0.0), returnsNormally);
    });

    test('throws InvalidCoordinatesException when latitude exceeds 90', () {
      expect(
        () => Coordinates(latitude: 90.0001, longitude: 0.0),
        throwsA(isA<InvalidCoordinatesException>()),
      );
    });

    test(
      'throws InvalidCoordinatesException when latitude is less than -90',
      () {
        expect(
          () => Coordinates(latitude: -90.0001, longitude: 0.0),
          throwsA(isA<InvalidCoordinatesException>()),
        );
      },
    );

    test('throws InvalidCoordinatesException when longitude exceeds 180', () {
      expect(
        () => Coordinates(latitude: 0.0, longitude: 180.0001),
        throwsA(isA<InvalidCoordinatesException>()),
      );
    });

    test(
      'throws InvalidCoordinatesException when longitude is less than -180',
      () {
        expect(
          () => Coordinates(latitude: 0.0, longitude: -180.0001),
          throwsA(isA<InvalidCoordinatesException>()),
        );
      },
    );

    test(
      'tryParse returns null on invalid values and coordinates on valid values',
      () {
        expect(Coordinates.tryParse(14.5, 121.0), isNotNull);
        expect(Coordinates.tryParse(100.0, 50.0), isNull);
        expect(Coordinates.tryParse(null, 50.0), isNull);
        expect(Coordinates.tryParse(50.0, null), isNull);
      },
    );

    test('serializes to and from Map correctly', () {
      final original = Coordinates(latitude: 48.8566, longitude: 2.3522);
      final map = original.toMap();
      final restored = Coordinates.fromMap(map);
      expect(restored, equals(original));
    });

    test('supports value equality', () {
      final a = Coordinates(latitude: 37.7749, longitude: -122.4194);
      final b = Coordinates(latitude: 37.7749, longitude: -122.4194);
      final c = Coordinates(latitude: 37.7750, longitude: -122.4194);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
