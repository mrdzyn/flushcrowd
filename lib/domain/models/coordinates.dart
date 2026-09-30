import 'package:equatable/equatable.dart';

import '../../core/errors/exceptions.dart';

/// Immutable geographic coordinate value object with strict range validation.
class Coordinates extends Equatable {
  final double latitude;
  final double longitude;

  Coordinates({required this.latitude, required this.longitude}) {
    validate(latitude, longitude);
  }

  /// Validates that latitude is within [-90.0, 90.0] and longitude is within [-180.0, 180.0].
  static void validate(double lat, double lng) {
    if (lat.isNaN || lat < -90.0 || lat > 90.0) {
      throw InvalidCoordinatesException(
        'Latitude must be between -90.0 and 90.0 degrees. Received: $lat',
      );
    }
    if (lng.isNaN || lng < -180.0 || lng > 180.0) {
      throw InvalidCoordinatesException(
        'Longitude must be between -180.0 and 180.0 degrees. Received: $lng',
      );
    }
  }

  /// Safe parser that returns null if invalid.
  static Coordinates? tryParse(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    try {
      return Coordinates(latitude: lat, longitude: lng);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {'latitude': latitude, 'longitude': longitude};
  }

  factory Coordinates.fromMap(Map<String, dynamic> map) {
    final lat = (map['latitude'] as num).toDouble();
    final lng = (map['longitude'] as num).toDouble();
    return Coordinates(latitude: lat, longitude: lng);
  }

  @override
  List<Object?> get props => [latitude, longitude];

  @override
  String toString() => 'Coordinates($latitude, $longitude)';
}
