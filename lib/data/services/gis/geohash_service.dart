import '../../../domain/models/coordinates.dart';

/// Geohash bounding box with minimum and maximum coordinates.
class GeoBoundingBox {
  final Coordinates southWest;
  final Coordinates northEast;

  const GeoBoundingBox({required this.southWest, required this.northEast});

  bool contains(Coordinates point) {
    return point.latitude >= southWest.latitude &&
        point.latitude <= northEast.latitude &&
        point.longitude >= southWest.longitude &&
        point.longitude <= northEast.longitude;
  }
}

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

  /// Selects the optimal geohash precision for a search radius in meters.
  ///
  /// Precision 4: ~39 km x 19 km (for very large query, capped at 10km in P1)
  /// Precision 5: ~4.9 km x 4.9 km (for radii 1.2km to 10km)
  /// Precision 6: ~1.2 km x 0.6 km (for radii 200m to 1.2km)
  /// Precision 7: ~152 m x 152 m (for radii < 200m)
  static int precisionForRadius(double radiusMeters) {
    if (radiusMeters > 5000) {
      return 5;
    } else if (radiusMeters > 1200) {
      return 5;
    } else if (radiusMeters > 200) {
      return 6;
    } else {
      return 7;
    }
  }

  /// Returns the deduplicated candidate geohash prefixes for a search radius in meters around [center].
  ///
  /// Generates the center cell plus all valid neighbors (up to 9 cells total)
  /// to ensure facilities across geohash boundaries are never missed.
  /// Deduplicates results deterministically and handles antimeridian and pole edges.
  static List<String> getCandidatePrefixes(
    Coordinates center,
    double radiusMeters,
  ) {
    final precision = precisionForRadius(radiusMeters);
    final centerHash = encode(center, precision: precision);

    final set = <String>{centerHash};
    final nbrs = neighbors(centerHash);
    set.addAll(nbrs.values);

    final sortedList = set.toList()..sort();
    return sortedList;
  }

  /// Generates candidate geohash prefixes that cover a [GeoBoundingBox].
  ///
  /// Chooses an appropriate precision based on the viewport span and
  /// samples grid points across the bounding box.
  /// Caps candidate count to prevent unbounded reads.
  static List<String> getViewportPrefixes(
    GeoBoundingBox bounds, {
    int maxPrefixes = 16,
  }) {
    final latSpan = bounds.northEast.latitude - bounds.southWest.latitude;
    double lngSpan = bounds.northEast.longitude - bounds.southWest.longitude;
    if (lngSpan < 0) {
      // Crosses antimeridian
      lngSpan += 360.0;
    }

    // Determine precision based on maximum dimension
    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
    final int precision;
    if (maxSpan > 2.0) {
      precision = 3; // ~156 km
    } else if (maxSpan > 0.4) {
      precision = 4; // ~39 km
    } else if (maxSpan > 0.08) {
      precision = 5; // ~4.9 km
    } else {
      precision = 6; // ~1.2 km
    }

    // Sample across the bounding box
    final prefixes = <String>{};

    // Calculate approximate step size in lat/lng for chosen precision
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
      prefixes.add(encode(bounds.southWest, precision: precision));
      return prefixes.toList()..sort();
    }

    double lat = bounds.southWest.latitude;
    while (lat <= bounds.northEast.latitude + (stepLat * 0.5)) {
      final clampedLat = lat.clamp(-90.0, 90.0);
      double lng = bounds.southWest.longitude;
      final endLng = bounds.northEast.longitude >= bounds.southWest.longitude
          ? bounds.northEast.longitude
          : bounds.northEast.longitude + 360.0;

      while (lng <= endLng + (stepLng * 0.5)) {
        double normalizedLng = lng;
        while (normalizedLng > 180.0) {
          normalizedLng -= 360.0;
        }
        while (normalizedLng < -180.0) {
          normalizedLng += 360.0;
        }
        if (normalizedLng == 180.0) normalizedLng = 179.999999;
        if (normalizedLng == -180.0) normalizedLng = -179.999999;

        prefixes.add(
          encode(
            Coordinates(latitude: clampedLat, longitude: normalizedLng),
            precision: precision,
          ),
        );
        if (prefixes.length >= maxPrefixes) {
          break;
        }
        lng += stepLng;
      }
      if (prefixes.length >= maxPrefixes) {
        break;
      }
      lat += stepLat;
    }

    // Always ensure corners are included if under limit
    final corners = [
      bounds.southWest,
      bounds.northEast,
      Coordinates(
        latitude: bounds.southWest.latitude,
        longitude: bounds.northEast.longitude,
      ),
      Coordinates(
        latitude: bounds.northEast.latitude,
        longitude: bounds.southWest.longitude,
      ),
    ];
    for (final c in corners) {
      if (prefixes.length < maxPrefixes) {
        prefixes.add(encode(c, precision: precision));
      }
    }

    final sorted = prefixes.toList()..sort();
    return sorted;
  }
}
