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
