import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/enums.dart';
import '../../domain/repositories/location_repository.dart';

/// State notifier for device foreground location and permission lifecycle.
class LocationNotifier extends ChangeNotifier {
  final LocationRepository _locationRepository;

  LocationPermissionState _permissionState =
      LocationPermissionState.notRequested;
  Coordinates? _currentCoordinates;
  bool _isLoading = false;
  String? _errorMessage;

  LocationNotifier({required this._locationRepository});

  LocationPermissionState get permissionState => _permissionState;
  Coordinates? get currentCoordinates => _currentCoordinates;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  LocationRepository get locationRepository => _locationRepository;

  /// Returns user's location if available, or fallback default coordinates for manual exploration.
  Coordinates get effectiveCoordinates =>
      _currentCoordinates ??
      Coordinates(
        latitude: AppConstants.defaultLatitude,
        longitude: AppConstants.defaultLongitude,
      );

  bool get hasLocation => _currentCoordinates != null;
  bool get isPermissionGranted => _permissionState.isGranted;

  Future<void> checkInitialPermission() async {
    _permissionState = await _locationRepository.checkPermission();
    if (_permissionState.isGranted) {
      await fetchCurrentLocation();
    }
    notifyListeners();
  }

  Future<void> requestLocationPermission() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _permissionState = await _locationRepository.requestPermission();
      if (_permissionState.isGranted) {
        await fetchCurrentLocation();
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchCurrentLocation() async {
    try {
      final coords = await _locationRepository.getCurrentLocation();
      _currentCoordinates = coords;
      _permissionState = LocationPermissionState.granted;
    } catch (e) {
      _errorMessage = e.toString();
    }
    notifyListeners();
  }
}
