import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/enums.dart';
import '../../domain/repositories/location_repository.dart';
import '../components/buttons/loo_primary_button.dart';
import '../components/map/map_recenter_button.dart';
import '../state/location_notifier.dart';

/// Builder signature allowing test doubles to supply mock map widgets
/// for deterministic testing without native Google Maps platform views.
typedef MapWidgetBuilder = Widget Function({
  required BuildContext context,
  required CameraPosition initialCameraPosition,
  required void Function(GoogleMapController controller)? onMapCreated,
  required void Function(CameraPosition position)? onCameraMove,
  required VoidCallback? onCameraIdle,
  required VoidCallback? onCameraMoveStarted,
});

/// Phase 2 Milestone P2.2: Interactive Location Pinpoint & Map Pin Adjustment Screen.
///
/// Allows the user to precisely choose where the restroom is located via a fixed
/// center crosshair overlay over an interactive Google Map.
///
/// Invariants:
/// - Uses canonical [Coordinates] domain model.
/// - Minimum confirmation zoom: [minConfirmationZoom] (15.0).
/// - Live coordinate readout formatted to 5 decimal places (~1.1m precision).
/// - Coordinates commit on camera idle, not on every camera movement frame.
/// - Zero Firestore reads and zero Firestore writes.
/// - Zero Geocoding / Places / Routes / Directions API dependencies.
/// - Foreground instantaneous location only; no background tracking or movement history.
/// - Manual map exploration is never blocked if GPS is unavailable.
class AddRestroomLocationScreen extends StatefulWidget {
  final Coordinates? initialCoordinates;
  final LocationRepository? locationRepository;
  final ValueChanged<Coordinates>? onLocationConfirmed;
  final MapWidgetBuilder? mapBuilder;

  /// Minimum camera zoom required before location confirmation is allowed.
  static const double minConfirmationZoom = 15.0;

  /// Recommended initial zoom level per Phase 2 specification.
  static const double defaultInitialZoom = 16.0;

  const AddRestroomLocationScreen({
    super.key,
    this.initialCoordinates,
    this.locationRepository,
    this.onLocationConfirmed,
    this.mapBuilder,
  });

  /// Factory helper for standard navigation returning the selected [Coordinates].
  static MaterialPageRoute<Coordinates> route({
    Coordinates? initialCoordinates,
    LocationRepository? locationRepository,
    ValueChanged<Coordinates>? onLocationConfirmed,
    MapWidgetBuilder? mapBuilder,
  }) {
    return MaterialPageRoute<Coordinates>(
      builder: (context) => AddRestroomLocationScreen(
        initialCoordinates: initialCoordinates,
        locationRepository: locationRepository,
        onLocationConfirmed: onLocationConfirmed,
        mapBuilder: mapBuilder,
      ),
    );
  }

  @override
  State<AddRestroomLocationScreen> createState() =>
      _AddRestroomLocationScreenState();
}

class _AddRestroomLocationScreenState extends State<AddRestroomLocationScreen> {
  GoogleMapController? _mapController;

  late Coordinates _selectedCoordinates;
  late LatLng _currentCameraTarget;
  late double _currentZoom;

  bool _isCameraMoving = false;
  bool _isLocating = false;
  bool _isPermissionGranted = false;

  @override
  void initState() {
    super.initState();

    final initial =
        widget.initialCoordinates ??
        Coordinates(
          latitude: AppConstants.defaultLatitude,
          longitude: AppConstants.defaultLongitude,
        );

    _selectedCoordinates = initial;
    _currentCameraTarget = LatLng(initial.latitude, initial.longitude);
    _currentZoom = AddRestroomLocationScreen.defaultInitialZoom;

    // If an explicit coordinate was not provided, attempt to center on known device location
    if (widget.initialCoordinates == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeFromDeviceLocationIfAvailable();
      });
    }
  }

  LocationRepository _getLocationRepository(BuildContext context) {
    if (widget.locationRepository != null) {
      return widget.locationRepository!;
    }
    try {
      return Provider.of<LocationRepository>(context, listen: false);
    } catch (_) {
      return _FallbackLocationRepository();
    }
  }

  Future<void> _initializeFromDeviceLocationIfAvailable() async {
    if (!mounted) return;
    try {
      // 1. Check LocationNotifier if present in the tree
      try {
        final notifier = Provider.of<LocationNotifier>(context, listen: false);
        if (notifier.hasLocation && notifier.currentCoordinates != null) {
          final coords = notifier.currentCoordinates!;
          if (mounted) {
            setState(() {
              _isPermissionGranted = notifier.isPermissionGranted;
              _selectedCoordinates = coords;
              _currentCameraTarget = LatLng(coords.latitude, coords.longitude);
            });
            if (_mapController != null) {
              unawaited(
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    _currentCameraTarget,
                    _currentZoom,
                  ),
                ),
              );
            }
          }
          return;
        }
      } catch (_) {}

      // 2. Check injected or tree LocationRepository
      final repo = _getLocationRepository(context);
      final permission = await repo.checkPermission();
      if (permission.isGranted) {
        final coords = await repo.getCurrentLocation();
        if (mounted) {
          setState(() {
            _isPermissionGranted = true;
            _selectedCoordinates = coords;
            _currentCameraTarget = LatLng(coords.latitude, coords.longitude);
          });
          if (_mapController != null) {
            unawaited(
              _mapController!.animateCamera(
                CameraUpdate.newLatLngZoom(_currentCameraTarget, _currentZoom),
              ),
            );
          }
        }
      }
    } catch (_) {
      // Degraded/offline fallback: remain at safe default coordinates
    }
  }

  void _onCameraMoveStarted() {
    if (!_isCameraMoving) {
      setState(() {
        _isCameraMoving = true;
      });
    }
  }

  void _onCameraMove(CameraPosition position) {
    _currentCameraTarget = position.target;
    _currentZoom = position.zoom;
    if (!_isCameraMoving) {
      setState(() {
        _isCameraMoving = true;
      });
    }
  }

  void _onCameraIdle() {
    // Normalize longitude to [-180.0, 180.0] and clamp latitude to [-90.0, 90.0]
    double lng = _currentCameraTarget.longitude;
    while (lng < -180.0) {
      lng += 360.0;
    }
    while (lng > 180.0) {
      lng -= 360.0;
    }
    final lat = _currentCameraTarget.latitude.clamp(-90.0, 90.0);

    setState(() {
      _isCameraMoving = false;
      _selectedCoordinates = Coordinates(latitude: lat, longitude: lng);
    });
  }

  Future<void> _recenterOnUser() async {
    setState(() => _isLocating = true);

    try {
      Coordinates? targetCoords;

      if (widget.locationRepository != null) {
        final repo = widget.locationRepository!;
        final serviceEnabled = await repo.isLocationServiceEnabled();
        if (!serviceEnabled) {
          _showLocationNotice(
            'Location services are disabled. Move the map manually.',
          );
          return;
        }
        var permission = await repo.checkPermission();
        if (permission == LocationPermissionState.notRequested ||
            permission == LocationPermissionState.denied) {
          permission = await repo.requestPermission();
        }
        if (permission.isGranted) {
          targetCoords = await repo.getCurrentLocation();
          _isPermissionGranted = true;
        } else {
          _showLocationNotice(
            'Location permission denied. Move the map manually.',
          );
          return;
        }
      } else {
        // Fallback to LocationNotifier if present
        try {
          final notifier = Provider.of<LocationNotifier>(
            context,
            listen: false,
          );
          if (!notifier.isPermissionGranted) {
            await notifier.requestLocationPermission();
          } else {
            await notifier.fetchCurrentLocation();
          }
          if (notifier.isPermissionGranted && notifier.hasLocation) {
            targetCoords = notifier.currentCoordinates;
            _isPermissionGranted = true;
          } else {
            _showLocationNotice(
              'Location permission denied. Move the map manually.',
            );
            return;
          }
        } catch (_) {
          if (!mounted) return;
          final repo = _getLocationRepository(context);
          final permission = await repo.requestPermission();
          if (permission.isGranted) {
            targetCoords = await repo.getCurrentLocation();
            _isPermissionGranted = true;
          } else {
            _showLocationNotice(
              'Location permission denied. Move the map manually.',
            );
            return;
          }
        }
      }

      if (targetCoords != null && mounted) {
        final zoom =
            _currentZoom < AddRestroomLocationScreen.minConfirmationZoom
            ? AddRestroomLocationScreen.minConfirmationZoom
            : _currentZoom;

        setState(() {
          _currentCameraTarget = LatLng(
            targetCoords!.latitude,
            targetCoords.longitude,
          );
          _selectedCoordinates = targetCoords;
          _currentZoom = zoom;
        });

        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(targetCoords.latitude, targetCoords.longitude),
              zoom,
            ),
          );
        }
      }
    } catch (_) {
      _showLocationNotice(
        'Unable to determine current location. Move the map manually.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _showLocationNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool get _isZoomSufficient =>
      _currentZoom >= AddRestroomLocationScreen.minConfirmationZoom;

  bool get _canConfirm => _isZoomSufficient && !_isCameraMoving;

  void _handleContinue() {
    if (!_canConfirm) return;
    widget.onLocationConfirmed?.call(_selectedCoordinates);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_selectedCoordinates);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedCoordinates =
        '${_selectedCoordinates.latitude.toStringAsFixed(5)}, ${_selectedCoordinates.longitude.toStringAsFixed(5)}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Pinpoint the restroom',
          style: AppTypography.titleLarge,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            width: double.infinity,
            color: AppColors.primaryLight.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.touch_app_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Move the map so the marker is exactly where the restroom is located.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. Google Map Layer
          _buildMap(),

          // 2. Fixed Center Target Pin Overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Semantics(
                  label: 'Map center target pin',
                  child: _buildCenterTargetIndicator(),
                ),
              ),
            ),
          ),

          // 3. Floating Location Button & Bottom Action Sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // "Use my location" button
                Padding(
                  padding: const EdgeInsets.only(
                    right: AppSpacing.screenHorizontal,
                    bottom: AppSpacing.md,
                  ),
                  child: Semantics(
                    button: true,
                    label: 'Use my location',
                    child: MapRecenterButton(
                      isLoading: _isLocating,
                      onPressed: _recenterOnUser,
                    ),
                  ),
                ),

                // Bottom Confirmation Card
                _buildBottomCard(formattedCoordinates),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final initialCameraPosition = CameraPosition(
      target: _currentCameraTarget,
      zoom: _currentZoom,
    );

    if (widget.mapBuilder != null) {
      return widget.mapBuilder!(
        context: context,
        initialCameraPosition: initialCameraPosition,
        onMapCreated: (controller) => _mapController = controller,
        onCameraMove: _onCameraMove,
        onCameraIdle: _onCameraIdle,
        onCameraMoveStarted: _onCameraMoveStarted,
      );
    }

    return GoogleMap(
      initialCameraPosition: initialCameraPosition,
      myLocationEnabled: _isPermissionGranted,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      onMapCreated: (controller) => _mapController = controller,
      onCameraMoveStarted: _onCameraMoveStarted,
      onCameraMove: _onCameraMove,
      onCameraIdle: _onCameraIdle,
    );
  }

  Widget _buildCenterTargetIndicator() {
    return SizedBox(
      width: 48,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Ground center dot at exact coordinate anchor
          Positioned(
            bottom: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          // Floating Restroom Pin
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            bottom: _isCameraMoving ? 16 : 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: _isCameraMoving ? 8 : 4,
                        offset: Offset(0, _isCameraMoving ? 5 : 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.wc_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
                const CustomPaint(
                  size: Size(10, 6),
                  painter: _PinTipPainter(color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCard(String formattedCoordinates) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.topSheetBorder,
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.lg,
        bottom: bottomInset > 0 ? bottomInset + AppSpacing.sm : AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coordinate readout row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.pin_drop_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Coordinates',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Semantics(
                excludeSemantics: true,
                label: 'Selected coordinates: $formattedCoordinates',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: AppRadii.smBorder,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    formattedCoordinates,
                    style: AppTypography.labelMedium.copyWith(
                      fontFamily: 'monospace',
                      color: AppColors.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Precision guidance hint when zoom is below floor
          if (!_isZoomSufficient) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              excludeSemantics: true,
              label: 'Precision warning: Zoom in to place the restroom more precisely.',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: AppRadii.mdBorder,
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.zoom_in_rounded,
                      size: 20,
                      color: AppColors.onWarningContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Zoom in to place the restroom more precisely.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onWarningContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // Primary confirmation action
          Semantics(
            button: true,
            excludeSemantics: true,
            label: 'Continue to restroom details',
            child: LooPrimaryButton(
              label: 'Continue',
              onPressed: _canConfirm ? _handleContinue : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinTipPainter extends CustomPainter {
  final Color color;
  const _PinTipPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PinTipPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FallbackLocationRepository implements LocationRepository {
  @override
  Future<LocationPermissionState> checkPermission() async =>
      LocationPermissionState.denied;

  @override
  Future<Coordinates> getCurrentLocation() async => Coordinates(
    latitude: AppConstants.defaultLatitude,
    longitude: AppConstants.defaultLongitude,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.denied;
}
