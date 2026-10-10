import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'coordinates.dart';

/// Geographic bounding box defined by southWest and northEast coordinates.
///
/// Supports standard bounding boxes as well as antimeridian-crossing bounding boxes
/// where southWest.longitude > northEast.longitude.
class GeoBoundingBox extends Equatable {
  final Coordinates southWest;
  final Coordinates northEast;

  const GeoBoundingBox({required this.southWest, required this.northEast});

  /// Creates a bounding box centered at [center] spanning [radiusMeters] in each direction.
  factory GeoBoundingBox.fromCenterAndRadius(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) {
    const earthRadius = 6371008.8;
    final dLatDeg = (radiusMeters / earthRadius) * (180.0 / math.pi);
    final minLat = (center.latitude - dLatDeg).clamp(-90.0, 90.0);
    final maxLat = (center.latitude + dLatDeg).clamp(-90.0, 90.0);
    final cosLat = math.cos(center.latitude * math.pi / 180.0).abs();
    final dLngDeg = cosLat > 1e-6
        ? (radiusMeters / (earthRadius * cosLat)) * (180.0 / math.pi)
        : 180.0;
    var minLng = center.longitude - dLngDeg;
    var maxLng = center.longitude + dLngDeg;
    if (minLng < -180.0) minLng += 360.0;
    if (maxLng > 180.0) maxLng -= 360.0;
    return GeoBoundingBox(
      southWest: Coordinates(latitude: minLat, longitude: minLng),
      northEast: Coordinates(latitude: maxLat, longitude: maxLng),
    );
  }

  /// Returns true if [point] is contained inside this bounding box.
  ///
  /// For standard viewports (`southWest.longitude <= northEast.longitude`):
  /// `latitude in [southWest.latitude, northEast.latitude]` AND
  /// `longitude in [southWest.longitude, northEast.longitude]`.
  ///
  /// For antimeridian-crossing viewports (`southWest.longitude > northEast.longitude`):
  /// `latitude in [southWest.latitude, northEast.latitude]` AND
  /// (`longitude >= southWest.longitude` OR `longitude <= northEast.longitude`).
  bool contains(Coordinates point) {
    final latMatches =
        point.latitude >= southWest.latitude &&
        point.latitude <= northEast.latitude;
    if (!latMatches) return false;

    if (crossesAntimeridian) {
      return point.longitude >= southWest.longitude ||
          point.longitude <= northEast.longitude;
    } else {
      return point.longitude >= southWest.longitude &&
          point.longitude <= northEast.longitude;
    }
  }

  /// Whether this bounding box crosses the antimeridian (180° / -180° longitude).
  bool get crossesAntimeridian => southWest.longitude > northEast.longitude;

  /// The latitude span in degrees.
  double get latitudeSpan => (northEast.latitude - southWest.latitude).abs();

  /// The longitude span in degrees, properly accounting for antimeridian crossing.
  double get longitudeSpan {
    final rawDiff = northEast.longitude - southWest.longitude;
    if (rawDiff < 0) {
      return rawDiff + 360.0;
    }
    return rawDiff;
  }

  /// The geographic center of this bounding box.
  Coordinates get center {
    final centerLat = (southWest.latitude + northEast.latitude) / 2.0;
    double centerLng;
    if (crossesAntimeridian) {
      centerLng = southWest.longitude + (longitudeSpan / 2.0);
      if (centerLng > 180.0) {
        centerLng -= 360.0;
      }
    } else {
      centerLng = (southWest.longitude + northEast.longitude) / 2.0;
    }
    return Coordinates(latitude: centerLat, longitude: centerLng);
  }

  @override
  List<Object?> get props => [southWest, northEast];

  @override
  String toString() =>
      'GeoBoundingBox(SW: $southWest, NE: $northEast, crossesAntimeridian: $crossesAntimeridian)';
}
