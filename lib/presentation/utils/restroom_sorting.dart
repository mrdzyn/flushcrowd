import '../../../data/services/gis/haversine.dart';
import '../../../domain/models/coordinates.dart';
import '../../../domain/models/restroom.dart';

/// Pure sorting helper for restroom lists guaranteeing deterministic ordering.
class RestroomSorting {
  const RestroomSorting._();

  /// Sorts a list of [Restroom]s deterministically.
  ///
  /// Ordering rules:
  /// - When [userLocation] is provided:
  ///   1. Primary: Haversine distance ascending
  ///   2. Tie-break: Normalized name ascending (case-insensitive)
  ///   3. Final tie-break: Restroom ID ascending
  /// - When [userLocation] is null:
  ///   1. Primary: Normalized name ascending (case-insensitive)
  ///   2. Tie-break: Restroom ID ascending
  static List<Restroom> sort(
    List<Restroom> restrooms, {
    Coordinates? userLocation,
  }) {
    final copy = List<Restroom>.from(restrooms);
    copy.sort((a, b) => compare(a, b, userLocation: userLocation));
    return copy;
  }

  /// Compares two restrooms deterministically.
  static int compare(Restroom a, Restroom b, {Coordinates? userLocation}) {
    if (userLocation != null) {
      final distA = Haversine.distanceInMeters(userLocation, a.coordinates);
      final distB = Haversine.distanceInMeters(userLocation, b.coordinates);
      final distCompare = distA.compareTo(distB);
      if (distCompare != 0) return distCompare;

      final nameCompare = a.name.toLowerCase().trim().compareTo(
        b.name.toLowerCase().trim(),
      );
      if (nameCompare != 0) return nameCompare;

      return a.id.compareTo(b.id);
    } else {
      final nameCompare = a.name.toLowerCase().trim().compareTo(
        b.name.toLowerCase().trim(),
      );
      if (nameCompare != 0) return nameCompare;

      return a.id.compareTo(b.id);
    }
  }
}
