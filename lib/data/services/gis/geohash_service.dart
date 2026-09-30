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

  /// Returns candidate geohash query prefixes for a radius in meters around [center].
  static List<String> getCandidatePrefixes(
    Coordinates center,
    double radiusMeters,
  ) {
    // Choose precision according to radius
    // Precision 4: ~39 km x 19 km
    // Precision 5: ~4.9 km x 4.9 km
    // Precision 6: ~1.2 km x 0.6 km
    // Precision 7: ~152 m x 152 m
    final int precision;
    if (radiusMeters > 20000) {
      precision = 4;
    } else if (radiusMeters > 3000) {
      precision = 5;
    } else if (radiusMeters > 500) {
      precision = 6;
    } else {
      precision = 7;
    }

    final centerHash = encode(center, precision: precision);
    return [centerHash];
  }
}
