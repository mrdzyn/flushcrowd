import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/constants/app_constants.dart';
import 'package:looradar/data/services/gis/geohash_service.dart';
import 'package:looradar/data/services/gis/haversine.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/geo_bounding_box.dart';

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

    test('getCandidatePrefixes returns conservative covering prefixes with bounded count', () {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);

      final closePrefixes = GeohashService.getCandidatePrefixes(center, 150.0);
      expect(closePrefixes, isNotEmpty);
      expect(closePrefixes.length, lessThanOrEqualTo(16));
      expect(closePrefixes.first.length, isIn([6, 7]));

      final mediumPrefixes = GeohashService.getCandidatePrefixes(
        center,
        1000.0,
      );
      expect(mediumPrefixes, isNotEmpty);
      expect(mediumPrefixes.length, lessThanOrEqualTo(16));
      expect(mediumPrefixes.first.length, isIn([5, 6]));

      final widePrefixes = GeohashService.getCandidatePrefixes(center, 5000.0);
      expect(widePrefixes, isNotEmpty);
      expect(widePrefixes.length, lessThanOrEqualTo(16));
      expect(widePrefixes.first.length, isIn([4, 5]));
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
      // South neighbor exists, north neighbor past pole is clamped/null
      expect(neighborsNorth['s'], isNotNull);

      final candidatesNorth = GeohashService.getCandidatePrefixes(
        coordsNearNorthPole,
        1000.0,
      );
      expect(candidatesNorth, isNotEmpty);
      // At polar coordinates with full-longitude envelope, precision floors at minDiscoveryGeohashPrecision (3),
      // generating > 16 ranges (safe degradation) rather than collapsing to continental-scale precision 1
      expect(candidatesNorth.length, greaterThan(16));
      expect(
        candidatesNorth.first.length,
        equals(AppConstants.minDiscoveryGeohashPrecision),
      );
      // North pole candidates cover the center coordinate
      final candidatePrecisionNorth = candidatesNorth.first.length;
      final centerNorthPrefix = GeohashService.encode(
        coordsNearNorthPole,
        precision: candidatePrecisionNorth,
      );
      expect(candidatesNorth, contains(centerNorthPrefix));

      // Point at 89.99° N, 30° E has distance ~575m (< 1000m) and must be geometrically covered
      final inRadiusPointNorth = Coordinates(latitude: 89.99, longitude: 30.0);
      final distNorth = Haversine.distanceInMeters(
        coordsNearNorthPole,
        inRadiusPointNorth,
      );
      expect(distNorth, lessThanOrEqualTo(1000.0));
      final inRadiusPrefixNorth = GeohashService.encode(
        inRadiusPointNorth,
        precision: candidatePrecisionNorth,
      );
      expect(candidatesNorth, contains(inRadiusPrefixNorth));

      // Near South Pole: latitude = -89.99
      final coordsNearSouthPole = Coordinates(latitude: -89.99, longitude: 0.0);
      final candidatesSouth = GeohashService.getCandidatePrefixes(
        coordsNearSouthPole,
        1000.0,
      );
      expect(candidatesSouth, isNotEmpty);
      expect(candidatesSouth.length, greaterThan(16));
      expect(
        candidatesSouth.first.length,
        equals(AppConstants.minDiscoveryGeohashPrecision),
      );
      final candidatePrecisionSouth = candidatesSouth.first.length;
      final centerSouthPrefix = GeohashService.encode(
        coordsNearSouthPole,
        precision: candidatePrecisionSouth,
      );
      expect(candidatesSouth, contains(centerSouthPrefix));

      // Point at -89.99° S, 45° W has distance ~832m (< 1000m) and must be geometrically covered
      final inRadiusPointSouth = Coordinates(
        latitude: -89.99,
        longitude: -45.0,
      );
      final distSouth = Haversine.distanceInMeters(
        coordsNearSouthPole,
        inRadiusPointSouth,
      );
      expect(distSouth, lessThanOrEqualTo(1000.0));
      final inRadiusPrefixSouth = GeohashService.encode(
        inRadiusPointSouth,
        precision: candidatePrecisionSouth,
      );
      expect(candidatesSouth, contains(inRadiusPrefixSouth));
    });

    test('candidate prefixes eliminate duplicates and are sorted by center proximity', () {
      final point = Coordinates(latitude: 0.0, longitude: 0.0);
      final candidates = GeohashService.getCandidatePrefixes(point, 1500.0);

      // No duplicates
      expect(candidates.toSet().length, candidates.length);

      // Center prefix should be first (nearest to center)
      final centerPrefix = GeohashService.encode(
        point,
        precision: candidates.first.length,
      );
      expect(candidates.first, equals(centerPrefix));

      // Deterministically sorted by distance to center
      final distances = candidates.map((p) {
        final c = GeohashService.decodeCenter(p);
        return Haversine.distanceInMeters(point, c);
      }).toList();
      for (int i = 0; i < distances.length - 1; i++) {
        expect(distances[i], lessThanOrEqualTo(distances[i + 1]));
      }
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

    test('candidate prefixes completely cover 1.5 km, 5 km, and 10 km search circles', () {
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);

      for (final radius in [1500.0, 5000.0, 10000.0]) {
        final prefixes = GeohashService.getCandidatePrefixes(center, radius);
        expect(prefixes, isNotEmpty);
        expect(prefixes.length, lessThanOrEqualTo(16));

        // Test cardinal and diagonal points on the perimeter of the search circle
        // Each point on perimeter (distance == radius * 0.98 to avoid exact edge ambiguity)
        // MUST have its geohash covered by at least one candidate prefix.
        final dLat =
            (radius * 0.98 / Haversine.earthRadiusMeters) *
            (180.0 / 3.141592653589793);
        final dLng = dLat / 0.9677; // cos(14.58°) ~ 0.9677

        final perimeterPoints = [
          Coordinates(
            latitude: center.latitude + dLat,
            longitude: center.longitude,
          ), // North
          Coordinates(
            latitude: center.latitude - dLat,
            longitude: center.longitude,
          ), // South
          Coordinates(
            latitude: center.latitude,
            longitude: center.longitude + dLng,
          ), // East
          Coordinates(
            latitude: center.latitude,
            longitude: center.longitude - dLng,
          ), // West
          Coordinates(
            latitude: center.latitude + dLat * 0.7,
            longitude: center.longitude + dLng * 0.7,
          ), // NE
          Coordinates(
            latitude: center.latitude - dLat * 0.7,
            longitude: center.longitude - dLng * 0.7,
          ), // SW
        ];

        for (final pt in perimeterPoints) {
          final covered = prefixes.any((prefix) {
            final ptHash = GeohashService.encode(pt, precision: prefix.length);
            return ptHash == prefix;
          });
          expect(
            covered,
            isTrue,
            reason:
                'Point at perimeter of radius $radius m must be covered by candidates: $pt',
          );
        }
      }
    });

    test('candidate prefixes conservatively cover high-latitude locations (e.g. 60°N)', () {
      final oslo = Coordinates(latitude: 60.0, longitude: 10.75);
      final prefixes = GeohashService.getCandidatePrefixes(oslo, 5000.0);

      expect(prefixes, isNotEmpty);
      expect(prefixes.length, lessThanOrEqualTo(16));

      // Check east/west perimeter at high latitude where longitude degrees are shrunk by cos(60) = 0.5
      const dLat =
          (4800.0 / Haversine.earthRadiusMeters) * (180.0 / 3.141592653589793);
      const dLng = dLat / 0.5; // cos(60) = 0.5

      final eastPoint = Coordinates(
        latitude: oslo.latitude,
        longitude: oslo.longitude + dLng,
      );
      final westPoint = Coordinates(
        latitude: oslo.latitude,
        longitude: oslo.longitude - dLng,
      );

      final eastCovered = prefixes.any(
        (p) => GeohashService.encode(eastPoint, precision: p.length) == p,
      );
      final westCovered = prefixes.any(
        (p) => GeohashService.encode(westPoint, precision: p.length) == p,
      );

      expect(eastCovered, isTrue);
      expect(westCovered, isTrue);
    });

    test(
      'candidate prefixes cover search circles crossing the antimeridian',
      () {
        // 100 meters west of the antimeridian
        final fijiPoint = Coordinates(latitude: -16.5, longitude: 179.999);
        final prefixes = GeohashService.getCandidatePrefixes(fijiPoint, 2000.0);

        expect(prefixes, isNotEmpty);
        expect(prefixes.length, lessThanOrEqualTo(16));

        // Point 500m across antimeridian into western hemisphere (negative longitude)
        final crossedPoint = Coordinates(latitude: -16.5, longitude: -179.995);
        final crossedCovered = prefixes.any(
          (p) => GeohashService.encode(crossedPoint, precision: p.length) == p,
        );
        expect(crossedCovered, isTrue);
      },
    );
  });
}
