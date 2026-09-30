import 'dart:math' as math;

import '../../../domain/models/coordinates.dart';

/// Haversine formula calculation for spherical distance between two points on Earth.
class Haversine {
  Haversine._();

  /// Mean Earth radius in meters according to WGS-84 approximation.
  static const double earthRadiusMeters = 6371000.0;
  static const double earthRadiusKilometers = 6371.0;

  /// Calculates distance in meters between [from] and [to].
  static double distanceInMeters(Coordinates from, Coordinates to) {
    final dLat = _toRadians(to.latitude - from.latitude);
    final dLon = _toRadians(to.longitude - from.longitude);

    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) *
            math.sin(dLon / 2) *
            math.cos(lat1) *
            math.cos(lat2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Calculates distance in kilometers between [from] and [to].
  static double distanceInKilometers(Coordinates from, Coordinates to) {
    return distanceInMeters(from, to) / 1000.0;
  }

  /// Formats human-readable distance (e.g., "120 m" or "1.4 km").
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    } else {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  static double _toRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }
}
