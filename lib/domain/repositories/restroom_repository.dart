import '../models/coordinates.dart';
import '../models/discovery_result.dart';
import '../models/geo_bounding_box.dart';
import '../models/restroom.dart';

/// Repository boundary for restroom data access.
/// Decouples UI and domain logic from Firestore and spatial databases.
abstract class RestroomRepository {
  /// Fetches restrooms within [radiusMeters] of [center].
  ///
  /// Returns a [DiscoveryResult] indicating discovered restrooms and whether the
  /// query was complete or truncated by safety limits.
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  });

  /// Fetches candidate restrooms within visible [bounds] of the map camera.
  ///
  /// Returns a [DiscoveryResult] indicating discovered restrooms and whether the
  /// query was complete or truncated by safety limits.
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(GeoBoundingBox bounds);

  /// Retrieves a specific restroom by [id].
  Future<Restroom?> getRestroomById(String id);

  /// Submits a new restroom record.
  Future<void> submitRestroom(Restroom restroom);
}
