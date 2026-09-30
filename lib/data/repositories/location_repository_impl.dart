import 'package:geolocator/geolocator.dart'
    hide LocationServiceDisabledException;

import '../../core/errors/exceptions.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/enums.dart';
import '../../domain/repositories/location_repository.dart';

/// Platform implementation of [LocationRepository] via Geolocator.
/// Strictly foreground location only. Does not persist location history.
class LocationRepositoryImpl implements LocationRepository {
  @override
  Future<LocationPermissionState> checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionState.serviceDisabled;
    }

    final permission = await Geolocator.checkPermission();
    return _mapPermission(permission);
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionState.serviceDisabled;
    }

    final permission = await Geolocator.requestPermission();
    return _mapPermission(permission);
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<Coordinates> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionDeniedException();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionPermanentlyDeniedException();
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    return Coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  LocationPermissionState _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.denied:
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionState.permanentlyDenied;
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.notRequested;
    }
  }
}

/// In-memory LocationRepository test double for unit, widget, and simulator testing.
class InMemoryLocationRepository implements LocationRepository {
  LocationPermissionState _permissionState;
  Coordinates _mockCoordinates;
  bool _serviceEnabled;

  InMemoryLocationRepository({
    LocationPermissionState initialPermission =
        LocationPermissionState.notRequested,
    Coordinates? initialCoordinates,
    this._serviceEnabled = true,
  }) : _permissionState = initialPermission,
       _mockCoordinates =
           initialCoordinates ??
           Coordinates(latitude: 14.5839, longitude: 121.0617);

  void setPermissionState(LocationPermissionState state) {
    _permissionState = state;
  }

  void setCoordinates(Coordinates coordinates) {
    _mockCoordinates = coordinates;
  }

  void setServiceEnabled(bool enabled) {
    _serviceEnabled = enabled;
  }

  @override
  Future<LocationPermissionState> checkPermission() async {
    if (!_serviceEnabled) return LocationPermissionState.serviceDisabled;
    return _permissionState;
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    if (!_serviceEnabled) return LocationPermissionState.serviceDisabled;
    if (_permissionState == LocationPermissionState.notRequested) {
      _permissionState = LocationPermissionState.granted;
    }
    return _permissionState;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => _serviceEnabled;

  @override
  Future<Coordinates> getCurrentLocation() async {
    if (!_serviceEnabled) throw const LocationServiceDisabledException();
    if (_permissionState == LocationPermissionState.denied) {
      throw const LocationPermissionDeniedException();
    }
    if (_permissionState == LocationPermissionState.permanentlyDenied) {
      throw const LocationPermissionPermanentlyDeniedException();
    }
    return _mockCoordinates;
  }
}
