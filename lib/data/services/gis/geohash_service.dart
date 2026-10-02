import 'dart:math' as math;

import '../../../core/constants/app_constants.dart';
import '../../../domain/models/coordinates.dart';
import '../../../domain/models/geo_bounding_box.dart';
import 'haversine.dart';

/// Geohash encoding and query prefix boundary service.
/// Can be replaced or enhanced in later phases if spatial backend changes.
class GeohashService {
  GeohashService._();

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encodes [coordinates] into a geohash string with specified [precision] (1 to 12).
  static String encode(Coordinates coordinates, {int precision = 6}) {
    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;

    final StringBuffer buffer = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2.0;
        if (coordinates.longitude > mid) {
          ch |= (1 << (4 - bit));
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2.0;
        if (coordinates.latitude > mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }

  /// Calculates the bounding box for a given [geohash] string.
  static GeoBoundingBox decodeBounds(String geohash) {
    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;
    bool isEven = true;

    for (int i = 0; i < geohash.length; i++) {
      final c = geohash[i].toLowerCase();
      final charIndex = _base32.indexOf(c);
      if (charIndex == -1) {
        throw ArgumentError('Invalid geohash character: $c');
      }

      for (int bit = 4; bit >= 0; bit--) {
        final mask = 1 << bit;
        if (isEven) {
          final mid = (minLng + maxLng) / 2.0;
          if ((charIndex & mask) != 0) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2.0;
          if ((charIndex & mask) != 0) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isEven = !isEven;
      }
    }

    return GeoBoundingBox(
      southWest: Coordinates(latitude: minLat, longitude: minLng),
      northEast: Coordinates(latitude: maxLat, longitude: maxLng),
    );
  }

  /// Calculates the center [Coordinates] of a given [geohash] string.
  static Coordinates decodeCenter(String geohash) {
    final bounds = decodeBounds(geohash);
    final lat = (bounds.southWest.latitude + bounds.northEast.latitude) / 2.0;
    final lng = (bounds.southWest.longitude + bounds.northEast.longitude) / 2.0;
    return Coordinates(latitude: lat, longitude: lng);
  }

  /// Calculates the adjacent neighbor geohash in direction [dLat] (-1, 0, 1)
  /// and [dLng] (-1, 0, 1) relative to [geohash].
  ///
  /// Handles antimeridian wrapping (-180° / 180°) and clamps at poles (-90° / 90°).
  /// If moving past a pole is requested, returns null.
  static String? neighbor(String geohash, int dLat, int dLng) {
    if (dLat == 0 && dLng == 0) return geohash;

    final bounds = decodeBounds(geohash);
    final latHeight = bounds.northEast.latitude - bounds.southWest.latitude;
    final lngWidth = bounds.northEast.longitude - bounds.southWest.longitude;

    final centerLat =
        (bounds.southWest.latitude + bounds.northEast.latitude) / 2.0;
    final centerLng =
        (bounds.southWest.longitude + bounds.northEast.longitude) / 2.0;

    final double targetLat = centerLat + (dLat * latHeight);
    double targetLng = centerLng + (dLng * lngWidth);

    // Latitude clamping at poles: past 90 or -90 has no geographic neighbor
    if (targetLat > 90.0 || targetLat < -90.0) {
      return null;
    }

    // Longitude wrapping across antimeridian [-180, 180]
    while (targetLng > 180.0) {
      targetLng -= 360.0;
    }
    while (targetLng < -180.0) {
      targetLng += 360.0;
    }
    // Handle exact 180.0 edge case safely
    if (targetLng == 180.0) targetLng = 179.999999;
    if (targetLng == -180.0) targetLng = -179.999999;

    return encode(
      Coordinates(latitude: targetLat, longitude: targetLng),
      precision: geohash.length,
    );
  }

  /// Computes all valid neighbors of [geohash] in 8 directions (N, S, E, W, NE, NW, SE, SW).
  /// Returns a map keyed by direction: 'n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'.
  static Map<String, String> neighbors(String geohash) {
    final result = <String, String>{};

    const directions = {
      'n': [1, 0],
      's': [-1, 0],
      'e': [0, 1],
      'w': [0, -1],
      'ne': [1, 1],
      'nw': [1, -1],
      'se': [-1, 1],
      'sw': [-1, -1],
    };

    for (final entry in directions.entries) {
      final n = neighbor(geohash, entry.value[0], entry.value[1]);
      if (n != null) {
        result[entry.key] = n;
      }
    }

    return result;
  }

  /// Selects the optimal geohash precision for a search radius in meters around [latitude].
  ///
  /// Uses the smaller of latitude height or longitude width (scaled by cos(lat))
  /// to ensure the cell size at this precision is comfortably larger than the radius step,
  /// keeping the total candidate cell count small (typically 4 to 12 cells, well within budget).
  ///
  /// Approximate cell dimensions at equator:
  /// Precision 4: ~39 km x 19.5 km
  /// Precision 5: ~4.9 km x 4.9 km
  /// Precision 6: ~1.2 km x 0.6 km
  /// Precision 7: ~152 m x 152 m
  static int precisionForRadius(double radiusMeters, [double latitude = 0.0]) {
    final latRad = latitude.abs() * (math.pi / 180.0);
    final cosLat = math.cos(latRad).clamp(0.01, 1.0);

    // If radius is large (> 3500 m), use precision 4 to guarantee complete envelope coverage in <= 16 ranges
    if (radiusMeters > 3500) {
      return 4;
    }

    // For radii between 800 m and 3500 m:
    // Precision 5 cell is ~4.9 km tall, and at 60° latitude is ~2.4 km wide.
    // 3500m envelope will require ~2 to 4 cells width and height, easily under 16 cells.
    if (radiusMeters > 800 || cosLat < 0.3) {
      return 5;
    }

    // For radii between 150 m and 800 m:
    // Precision 6 cell is ~610 m tall, and ~1.2 km * cosLat wide.
    if (radiusMeters > 150) {
      return 6;
    }

    // Very small radii (< 150m)
    return 7;
  }

  /// Returns the deduplicated candidate geohash prefixes that completely cover the circular search
  /// area of [radiusMeters] around [center].
  ///
  /// Algorithm:
  /// 1. Computes the conservative bounding envelope in latitude and longitude for [center] + [radiusMeters].
  /// 2. Handles antimeridian crossing and polar clamping safely.
  /// 3. Selects geohash precision so the cell dimensions span the envelope in a small number of steps.
  /// 4. Systematically samples grid points across the entire envelope to ensure 100% geometric coverage.
  /// 5. Deduplicates prefixes and returns them sorted deterministically.
  static List<String> getCandidatePrefixes(
    Coordinates center,
    double radiusMeters, {
    int maxRanges = 16,
  }) {
    // 1. Calculate delta latitude in degrees
    final dLatDeg =
        (radiusMeters / Haversine.earthRadiusMeters) * (180.0 / math.pi);
    final minLat = (center.latitude - dLatDeg).clamp(-90.0, 90.0);
    final maxLat = (center.latitude + dLatDeg).clamp(-90.0, 90.0);

    // 2. Calculate delta longitude in degrees using exact spherical cap geometry.
    // If the circular search cap reaches or encloses either geographic pole,
    // it spans all longitudes [-180, 180].
    final thetaRad = radiusMeters / Haversine.earthRadiusMeters;
    final phiCenterRad = center.latitude.abs() * (math.pi / 180.0);
    final reachesPole = (phiCenterRad + thetaRad) >= (math.pi / 2.0);

    final double minLng;
    final double maxLng;

    if (reachesPole) {
      minLng = -180.0;
      maxLng = 180.0;
    } else {
      // For a small circle on a sphere not enclosing the pole, the maximum longitude delta
      // occurs at the tangent meridians: sin(dLng) = sin(theta) / cos(phiCenter).
      final cosPhi = math.cos(phiCenterRad);
      final sinTheta = math.sin(thetaRad);
      final sinDlng = sinTheta / cosPhi;

      if (sinDlng >= 1.0) {
        minLng = -180.0;
        maxLng = 180.0;
      } else {
        final dLngDeg = math.asin(sinDlng) * (180.0 / math.pi);
        if (dLngDeg >= 180.0) {
          minLng = -180.0;
          maxLng = 180.0;
        } else {
          double rawMin = center.longitude - dLngDeg;
          double rawMax = center.longitude + dLngDeg;
          // Normalize to [-180, 180]
          while (rawMin < -180.0) {
            rawMin += 360.0;
          }
          while (rawMin > 180.0) {
            rawMin -= 360.0;
          }
          while (rawMax < -180.0) {
            rawMax += 360.0;
          }
          while (rawMax > 180.0) {
            rawMax -= 360.0;
          }
          minLng = rawMin;
          maxLng = rawMax;
        }
      }
    }

    final envelope = GeoBoundingBox(
      southWest: Coordinates(latitude: minLat, longitude: minLng),
      northEast: Coordinates(latitude: maxLat, longitude: maxLng),
    );

    // 3. Select optimal precision
    var precision = precisionForRadius(radiusMeters, center.latitude);

    // 4. Sample envelope. If sampling at this precision exceeds maxRanges, drop precision
    // only down to minDiscoveryGeohashPrecision to prevent continental-scale prefix scans.
    List<String> candidatePrefixes = _tileBoundingBox(envelope, precision);
    while (candidatePrefixes.length > maxRanges &&
        precision > AppConstants.minDiscoveryGeohashPrecision) {
      precision--;
      candidatePrefixes = _tileBoundingBox(envelope, precision);
    }

    // 5. Prioritize candidate prefixes nearest to the search center so that if
    // rangeCapExceeded occurs, the most relevant local area is queried first.
    candidatePrefixes.sort((a, b) {
      final centerA = decodeCenter(a);
      final centerB = decodeCenter(b);
      final distA = Haversine.distanceInMeters(center, centerA);
      final distB = Haversine.distanceInMeters(center, centerB);
      final cmp = distA.compareTo(distB);
      if (cmp != 0) return cmp;
      return a.compareTo(b);
    });
    return candidatePrefixes;
  }

  /// Generates candidate geohash prefixes that cover a [GeoBoundingBox].
  ///
  /// Chooses an appropriate precision based on the viewport span and
  /// tiles grid points across the bounding box.
  /// If [maxPrefixes] would be exceeded at default precision, automatically steps down
  /// precision so the full bounding box remains completely covered.
  static List<String> getViewportPrefixes(
    GeoBoundingBox bounds, {
    int maxPrefixes = 16,
  }) {
    final latSpan = bounds.latitudeSpan;
    final lngSpan = bounds.longitudeSpan;
    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;

    int precision;
    if (maxSpan > 2.0) {
      precision = 3; // ~156 km
    } else if (maxSpan > 0.4) {
      precision = 4; // ~39 km
    } else if (maxSpan > 0.08) {
      precision = 5; // ~4.9 km
    } else {
      precision = 6; // ~1.2 km
    }

    var prefixes = _tileBoundingBox(bounds, precision);
    while (prefixes.length > maxPrefixes &&
        precision > AppConstants.minDiscoveryGeohashPrecision) {
      precision--;
      prefixes = _tileBoundingBox(bounds, precision);
    }

    // Prioritize candidate prefixes nearest to viewport center so that if
    // rangeCapExceeded occurs, the visible center area is queried first.
    final viewportCenter = bounds.center;
    prefixes.sort((a, b) {
      final centerA = decodeCenter(a);
      final centerB = decodeCenter(b);
      final distA = Haversine.distanceInMeters(viewportCenter, centerA);
      final distB = Haversine.distanceInMeters(viewportCenter, centerB);
      final cmp = distA.compareTo(distB);
      if (cmp != 0) return cmp;
      return a.compareTo(b);
    });
    return prefixes;
  }

  /// Tiles [bounds] completely with geohash cells at [precision].
  static List<String> _tileBoundingBox(GeoBoundingBox bounds, int precision) {
    final sampleBounds = decodeBounds(
      encode(bounds.southWest, precision: precision),
    );
    final stepLat =
        (sampleBounds.northEast.latitude - sampleBounds.southWest.latitude)
            .abs();
    final stepLng =
        (sampleBounds.northEast.longitude - sampleBounds.southWest.longitude)
            .abs();

    if (stepLat <= 0 || stepLng <= 0) {
      return [encode(bounds.southWest, precision: precision)];
    }

    final prefixes = <String>{};

    // Calculate longitude steps
    final totalLngSpan = bounds.longitudeSpan;
    final numLngSteps = (totalLngSpan / stepLng).ceil() + 1;
    final totalLatSpan = bounds.latitudeSpan;
    final numLatSteps = (totalLatSpan / stepLat).ceil() + 1;

    for (int iLat = 0; iLat <= numLatSteps; iLat++) {
      final lat = (bounds.southWest.latitude + (iLat * stepLat)).clamp(
        -90.0,
        90.0,
      );
      for (int iLng = 0; iLng <= numLngSteps; iLng++) {
        double lng = bounds.southWest.longitude + (iLng * stepLng);
        while (lng > 180.0) {
          lng -= 360.0;
        }
        while (lng < -180.0) {
          lng += 360.0;
        }
        if (lng == 180.0) lng = 179.999999;
        if (lng == -180.0) lng = -179.999999;

        prefixes.add(
          encode(
            Coordinates(latitude: lat, longitude: lng),
            precision: precision,
          ),
        );
      }
    }

    // Always include explicit corner coordinates
    prefixes.add(encode(bounds.southWest, precision: precision));
    prefixes.add(encode(bounds.northEast, precision: precision));
    prefixes.add(
      encode(
        Coordinates(
          latitude: bounds.southWest.latitude,
          longitude: bounds.northEast.longitude,
        ),
        precision: precision,
      ),
    );
    prefixes.add(
      encode(
        Coordinates(
          latitude: bounds.northEast.latitude,
          longitude: bounds.southWest.longitude,
        ),
        precision: precision,
      ),
    );

    return prefixes.toList();
  }
}
