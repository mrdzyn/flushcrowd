import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/data/services/gis/geohash_service.dart';
import 'package:looradar/data/services/gis/haversine.dart';
import 'package:looradar/domain/models/coordinates.dart';

void main() {
  group('GIS and Haversine Services', () {
    test(
      'calculates accurate Haversine distance between known coordinates',
      () {
        // London (51.5074° N, 0.1278° W) to Paris (48.8566° N, 2.3522° E)
        // Known geodesic distance: ~343.5 km
        final london = Coordinates(latitude: 51.5074, longitude: -0.1278);
        final paris = Coordinates(latitude: 48.8566, longitude: 2.3522);

        final distanceKm = Haversine.distanceInKilometers(london, paris);
        expect(distanceKm, greaterThan(340));
        expect(distanceKm, lessThan(346));

        final distanceMeters = Haversine.distanceInMeters(london, paris);
        expect(distanceMeters, closeTo(343500, 3000));
      },
    );

    test('calculates 0 distance for identical coordinates', () {
      final point = Coordinates(latitude: 14.5839, longitude: 121.0617);
      expect(Haversine.distanceInMeters(point, point), 0.0);
    });

    test('formats distance correctly for meters and kilometers', () {
      expect(Haversine.formatDistance(120), '120 m');
      expect(Haversine.formatDistance(950), '950 m');
      expect(Haversine.formatDistance(1000), '1.0 km');
      expect(Haversine.formatDistance(1420), '1.4 km');
      expect(Haversine.formatDistance(12500), '12.5 km');
    });

    test(
      'encodes coordinates to valid geohash string with specified precision',
      () {
        final coords = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final hash6 = GeohashService.encode(coords, precision: 6);
        expect(hash6.length, 6);

        final hash8 = GeohashService.encode(coords, precision: 8);
        expect(hash8.length, 8);
        expect(hash8.startsWith(hash6), isTrue);
      },
    );

    test('decodes geohash bounds containing the original coordinate', () {
      final coords = Coordinates(latitude: 14.5839, longitude: 121.0617);
      final hash = GeohashService.encode(coords, precision: 6);
      final bounds = GeohashService.decodeBounds(hash);

      expect(bounds.contains(coords), isTrue);
    });

    test(
      'getCandidatePrefixes returns correct precision prefixes based on radius',
      () {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);

        final closePrefixes = GeohashService.getCandidatePrefixes(
          center,
          400.0,
        );
        expect(closePrefixes.first.length, 7);

        final mediumPrefixes = GeohashService.getCandidatePrefixes(
          center,
          1500.0,
        );
        expect(mediumPrefixes.first.length, 6);

        final widePrefixes = GeohashService.getCandidatePrefixes(
          center,
          5000.0,
        );
        expect(widePrefixes.first.length, 5);
      },
    );
  });
}
