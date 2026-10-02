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

    test('getCandidatePrefixes returns center and 8 neighbors with correct precision', () {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);

      final closePrefixes = GeohashService.getCandidatePrefixes(center, 150.0);
      expect(closePrefixes, isNotEmpty);
      expect(closePrefixes.length, lessThanOrEqualTo(9));
      expect(closePrefixes.first.length, 7);

      final mediumPrefixes = GeohashService.getCandidatePrefixes(
        center,
        1000.0,
      );
      expect(mediumPrefixes.length, lessThanOrEqualTo(9));
      expect(mediumPrefixes.first.length, 6);

      final widePrefixes = GeohashService.getCandidatePrefixes(center, 5000.0);
      expect(widePrefixes.length, lessThanOrEqualTo(9));
      expect(widePrefixes.first.length, 5);
    });

    test(
      'neighbor calculates all 8 cardinal and diagonal directions correctly',
      () {
        const centerHash = 'wdw4fq'; // Precision 6
        final neighbors = GeohashService.neighbors(centerHash);

        expect(
          neighbors.keys,
          containsAll(['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw']),
        );
        expect(neighbors.length, 8);

        for (final n in neighbors.values) {
          expect(n.length, centerHash.length);
          expect(n, isNot(equals(centerHash)));
        }

        // North neighbor has higher latitude than center
        final centerCoord = GeohashService.decodeCenter(centerHash);
        final northCoord = GeohashService.decodeCenter(neighbors['n']!);
        expect(northCoord.latitude, greaterThan(centerCoord.latitude));

        // South neighbor has lower latitude than center
        final southCoord = GeohashService.decodeCenter(neighbors['s']!);
        expect(southCoord.latitude, lessThan(centerCoord.latitude));

        // East neighbor has higher longitude than center
        final eastCoord = GeohashService.decodeCenter(neighbors['e']!);
        expect(eastCoord.longitude, greaterThan(centerCoord.longitude));

        // West neighbor has lower longitude than center
        final westCoord = GeohashService.decodeCenter(neighbors['w']!);
        expect(westCoord.longitude, lessThan(centerCoord.longitude));
      },
    );

    test('discovers facilities across geohash cell boundaries', () {
      // Pick a point near the eastern boundary of a geohash cell
      const cellHash = 'wdw4fq';
      final bounds = GeohashService.decodeBounds(cellHash);
      final lat = (bounds.southWest.latitude + bounds.northEast.latitude) / 2.0;

      // Inside cell, right near the eastern border (0.0001 degrees west of border)
      final pointInside = Coordinates(
        latitude: lat,
        longitude: bounds.northEast.longitude - 0.0001,
      );

      // Outside cell, just across the eastern border (0.0001 degrees east of border)
      final pointAcrossBorder = Coordinates(
        latitude: lat,
        longitude: bounds.northEast.longitude + 0.0001,
      );

      final hashInside = GeohashService.encode(pointInside, precision: 6);
      final hashAcross = GeohashService.encode(pointAcrossBorder, precision: 6);

      // They should have different geohashes
      expect(hashInside, isNot(equals(hashAcross)));

      // But candidate prefixes from pointInside MUST include hashAcross
      final candidatePrefixes = GeohashService.getCandidatePrefixes(
        pointInside,
        500.0,
      );
      expect(candidatePrefixes, contains(hashAcross));
    });

    test('handles antimeridian longitude wraparound cleanly', () {
      // Near Fiji / 180° meridian: longitude ~ 179.999
      final coordsNearEast = Coordinates(latitude: -16.5, longitude: 179.999);
      final hashEast = GeohashService.encode(coordsNearEast, precision: 6);

      final neighbors = GeohashService.neighbors(hashEast);
      expect(neighbors['e'], isNotNull);

      // East neighbor crosses 180 to ~ -179.999
      final eastCoord = GeohashService.decodeCenter(neighbors['e']!);
      expect(eastCoord.longitude, lessThan(0)); // Wrapped to western hemisphere
      expect(eastCoord.longitude, greaterThanOrEqualTo(-180.0));

      final candidates = GeohashService.getCandidatePrefixes(
        coordsNearEast,
        1000.0,
      );
      expect(candidates, isNotEmpty);
      expect(
        candidates.toSet().length,
        candidates.length,
      ); // Deterministic deduplication
    });

    test('handles polar latitude boundaries gracefully without throwing', () {
      // Near North Pole: latitude = 89.99
      final coordsNearNorthPole = Coordinates(latitude: 89.99, longitude: 0.0);
      final hashNorth = GeohashService.encode(
        coordsNearNorthPole,
        precision: 6,
      );

      final neighborsNorth = GeohashService.neighbors(hashNorth);
      // North neighbor is null or clamped past pole
      expect(neighborsNorth['s'], isNotNull);

      final candidatesNorth = GeohashService.getCandidatePrefixes(
        coordsNearNorthPole,
        1000.0,
      );
      expect(candidatesNorth, isNotEmpty);
      expect(candidatesNorth, contains(hashNorth));

      // Near South Pole: latitude = -89.99
      final coordsNearSouthPole = Coordinates(latitude: -89.99, longitude: 0.0);
      final hashSouth = GeohashService.encode(
        coordsNearSouthPole,
        precision: 6,
      );
      final candidatesSouth = GeohashService.getCandidatePrefixes(
        coordsNearSouthPole,
        1000.0,
      );
      expect(candidatesSouth, isNotEmpty);
      expect(candidatesSouth, contains(hashSouth));
    });

    test('candidate prefixes eliminate duplicates and are sorted', () {
      final point = Coordinates(latitude: 0.0, longitude: 0.0);
      final candidates = GeohashService.getCandidatePrefixes(point, 1500.0);

      // No duplicates
      expect(candidates.toSet().length, candidates.length);

      // Deterministically sorted
      final sorted = List<String>.from(candidates)..sort();
      expect(candidates, equals(sorted));
    });

    test(
      'getViewportPrefixes generates bounded candidate list for viewport',
      () {
        final bounds = GeoBoundingBox(
          southWest: Coordinates(latitude: 14.5800, longitude: 121.0500),
          northEast: Coordinates(latitude: 14.5900, longitude: 121.0600),
        );

        final prefixes = GeohashService.getViewportPrefixes(bounds);
        expect(prefixes, isNotEmpty);
        expect(prefixes.length, lessThanOrEqualTo(16));
        expect(prefixes.toSet().length, prefixes.length);
      },
    );
  });
}
