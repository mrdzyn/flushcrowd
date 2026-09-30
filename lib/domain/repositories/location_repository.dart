import '../models/coordinates.dart';
import '../models/enums.dart';

/// Platform boundary for device location and foreground permissions.
/// Does not persist movement trails or background location.
abstract class LocationRepository {
  /// Checks current foreground permission status.
  Future<LocationPermissionState> checkPermission();

  /// Requests foreground location permission from user.
  Future<LocationPermissionState> requestPermission();

  /// Checks if device GPS/location service is enabled.
  Future<bool> isLocationServiceEnabled();

  /// Gets current instantaneous foreground coordinates.
  /// Throws [LocationException] if unavailable or denied.
  Future<Coordinates> getCurrentLocation();
}
