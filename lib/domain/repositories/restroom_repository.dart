import '../../data/services/gis/geohash_service.dart';
import '../models/coordinates.dart';
import '../models/restroom.dart';

/// Repository boundary for restroom data access.
/// Decouples UI and domain logic from Firestore and spatial databases.
abstract class RestroomRepository {
  /// Fetches restrooms within [radiusMeters] of [center].
  Future<List<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  });

  /// Fetches candidate restrooms within visible [bounds] of the map camera.
  Future<List<Restroom>> getViewportRestrooms(GeoBoundingBox bounds);

  /// Retrieves a specific restroom by [id].
  Future<Restroom?> getRestroomById(String id);

  /// Submits a new restroom record.
  Future<void> submitRestroom(Restroom restroom);
}
