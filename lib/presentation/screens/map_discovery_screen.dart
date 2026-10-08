import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/geo_bounding_box.dart';
import '../../domain/models/restroom.dart';
import '../components/bottom_sheets/filter_bottom_sheet.dart';
import '../components/bottom_sheets/nearby_restrooms_sheet.dart';
import '../components/bottom_sheets/restroom_preview_sheet.dart';
import '../components/map/map_discovery_bottom_bar.dart';
import '../components/map/map_marker_adapter.dart';
import '../components/map/map_recenter_button.dart';
import '../components/map/map_search_bar.dart';
import '../components/map/map_status_overlay.dart';
import '../components/map/permission_banner.dart';
import '../models/map_focus_intent.dart';
import '../models/restroom_marker_item.dart';
import '../state/location_notifier.dart';
import '../utils/restroom_sorting.dart';
import '../state/map_discovery_notifier.dart';
import 'add_restroom_location_screen.dart';

/// Primary map discovery screen matching canonical UX mockup Item 2.
class MapDiscoveryScreen extends StatefulWidget {
  final MapWidgetBuilder? mapBuilder;
  final ValueChanged<Coordinates>? onCameraTargetChanged;

  const MapDiscoveryScreen({
    super.key,
    this.mapBuilder,
    this.onCameraTargetChanged,
  });

  @override
  State<MapDiscoveryScreen> createState() => _MapDiscoveryScreenState();
}

class _MapDiscoveryScreenState extends State<MapDiscoveryScreen> {
  GoogleMapController? _googleMapController;
  MapCameraController? _mapCameraController;
  bool _isRecentering = false;
  MapDiscoveryNotifier? _discoveryNotifier;
  int? _lastExecutedFocusToken;
  MapFocusIntent? _pendingFocusExecution;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<MapDiscoveryNotifier>();
    if (_discoveryNotifier != notifier) {
      _discoveryNotifier?.removeListener(_onNotifierChanged);
      _discoveryNotifier = notifier;
      _discoveryNotifier?.addListener(_onNotifierChanged);
    }
    _onNotifierChanged();
  }

  @override
  void dispose() {
    _discoveryNotifier?.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() {
    final notifier = _discoveryNotifier;
    if (notifier == null || !mounted) return;
    final intent = notifier.pendingFocusIntent;
    if (intent == null) {
      _pendingFocusExecution = null;
      return;
    }
    if (intent.token == _lastExecutedFocusToken) return;

    if (_mapCameraController == null) {
      // Defer focus execution until map controller is initialized.
      // Do not consume intent and do not open preview prematurely.
      _pendingFocusExecution = intent;
      return;
    }

    _pendingFocusExecution = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _executeFocusIntent(intent, notifier);
    });
  }

  Future<void> _executeFocusIntent(
    MapFocusIntent intent,
    MapDiscoveryNotifier notifier,
  ) async {
    // Guard 1: Never re-execute a token that has already been executed.
    if (intent.token == _lastExecutedFocusToken) return;

    // Guard 2: Ensure the intent is still the active pending intent in the notifier.
    // Stale or superseded intents are safely discarded.
    if (notifier.pendingFocusIntent?.token != intent.token) return;

    // Guard 3: Map controller must be available.
    if (_mapCameraController == null || !mounted) {
      _pendingFocusExecution = intent;
      return;
    }

    // Mark token as executed immediately so no subsequent frame or race can re-enter.
    _lastExecutedFocusToken = intent.token;

    final coords = intent.restroom.coordinates;
    widget.onCameraTargetChanged?.call(coords);

    // 1. Camera focus occurs before preview presentation when possible.
    try {
      await _mapCameraController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(coords.latitude, coords.longitude),
          intent.zoom,
        ),
      );
    } catch (_) {}

    // Guard 4: After await, check mounted and ensure no newer intent superseded this one.
    if (!mounted) return;
    if (notifier.pendingFocusIntent != null &&
        notifier.pendingFocusIntent!.token != intent.token) {
      return;
    }

    // 2. Open preview sheet.
    if (intent.openPreview) {
      final locationNotifier = context.read<LocationNotifier>();
      _showRestroomPreviewSheet(
        context,
        intent.restroom,
        locationNotifier.currentCoordinates,
      );
    }

    // 3. Consume the intent in notifier.
    notifier.consumeFocusIntent(intent.token);
  }

  Future<void> _recenterOnUser() async {
    setState(() => _isRecentering = true);
    final locationNotifier = context.read<LocationNotifier>();
    await locationNotifier.fetchCurrentLocation();

    final coords = locationNotifier.currentCoordinates;
    if (coords != null) {
      widget.onCameraTargetChanged?.call(coords);
      if (_mapCameraController != null) {
        await _mapCameraController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(coords.latitude, coords.longitude),
            AppConstants.defaultZoomLevel,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _isRecentering = false);
    }
  }

  void _handleClusterTap(Cluster cluster) {
    widget.onCameraTargetChanged?.call(
      Coordinates(
        latitude: cluster.position.latitude,
        longitude: cluster.position.longitude,
      ),
    );
    if (_mapCameraController == null) return;
    _mapCameraController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        cluster.position,
        // Zoom in by 2 levels to expand the cluster
        // without arbitrarily selecting a single restroom
        16.0,
      ),
    );
  }

  Future<void> _handleCameraIdle() async {
    if (_googleMapController == null || !mounted) return;
    final notifier = context.read<MapDiscoveryNotifier>();
    try {
      final bounds = await _googleMapController!.getVisibleRegion();
      final zoom = await _googleMapController!.getZoomLevel();
      final geoBounds = GeoBoundingBox(
        southWest: Coordinates(
          latitude: bounds.southwest.latitude,
          longitude: bounds.southwest.longitude,
        ),
        northEast: Coordinates(
          latitude: bounds.northeast.latitude,
          longitude: bounds.northeast.longitude,
        ),
      );
      notifier.onCameraIdle(bounds: geoBounds, zoom: zoom);
    } catch (_) {
      // Ignore map controller errors during teardown or unit testing
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationNotifier = context.watch<LocationNotifier>();
    final discoveryNotifier = context.watch<MapDiscoveryNotifier>();

    final userCoords = locationNotifier.currentCoordinates;
    final effectiveCoords = locationNotifier.effectiveCoordinates;
    final selectedRestroom = discoveryNotifier.selectedRestroom;
    final markerItems = discoveryNotifier.markerItems;

    return Scaffold(
      body: Stack(
        children: [
          // Map Canvas
          _buildMapLayer(
            effectiveCoords,
            markerItems,
            locationNotifier.isPermissionGranted,
          ),

          // Safe Area Overlays
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Floating Search Bar with Filter Badge
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenHorizontal,
                    vertical: AppSpacing.sm,
                  ),
                  child: MapSearchBar(
                    initialQuery: discoveryNotifier.searchQuery.isNotEmpty
                        ? discoveryNotifier.searchQuery
                        : null,
                    activeFilterCount:
                        discoveryNotifier.filters.activeFilterCount,
                    onChanged: (q) => discoveryNotifier.setSearchQuery(q),
                    onFilterTap: () => _showFilterSheet(context),
                  ),
                ),

                // Map discovery status pill (loading / zoom-in suppressed / degraded / filtered empty)
                _buildStatusOverlay(discoveryNotifier),

                // Degraded Location Permission Banner
                if (!locationNotifier.isPermissionGranted)
                  PermissionBanner(
                    permissionState: locationNotifier.permissionState,
                    onRequestPermission: () async {
                      await locationNotifier.requestLocationPermission();
                      if (locationNotifier.hasLocation && mounted) {
                        final coords = locationNotifier.currentCoordinates;
                        if (coords != null && _mapCameraController != null) {
                          await _mapCameraController!.animateCamera(
                            CameraUpdate.newLatLngZoom(
                              LatLng(coords.latitude, coords.longitude),
                              AppConstants.defaultZoomLevel,
                            ),
                          );
                        }
                      }
                    },
                  ),

                const Spacer(),

                // Recenter Button
                Padding(
                  padding: const EdgeInsets.only(
                    right: AppSpacing.screenHorizontal,
                    bottom: AppSpacing.md,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MapRecenterButton(
                      isLoading: _isRecentering,
                      onPressed: _recenterOnUser,
                    ),
                  ),
                ),

                // Bottom results section: accessible whenever visible restrooms exist
                MapDiscoveryBottomBar(
                  visibleRestrooms: discoveryNotifier.visibleRestrooms,
                  selectedRestroom: selectedRestroom,
                  userCoordinates: userCoords,
                  onSeeAll: () => _showNearbyListSheet(
                    context,
                    discoveryNotifier,
                    userCoords,
                  ),
                  onCardTap: (restroom) =>
                      _showRestroomPreviewSheet(context, restroom, userCoords),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOverlay(MapDiscoveryNotifier notifier) {
    return MapStatusOverlay(notifier: notifier);
  }

  void _onDiscoveryMapCreated({
    required MapCameraController controller,
    GoogleMapController? googleController,
    required Coordinates initialCoords,
  }) {
    setState(() {
      _mapCameraController = controller;
      if (googleController != null) {
        _googleMapController = googleController;
      }
    });
    widget.onCameraTargetChanged?.call(initialCoords);

    final intentToExecute =
        _pendingFocusExecution ?? _discoveryNotifier?.pendingFocusIntent;
    _pendingFocusExecution = null;

    if (intentToExecute != null &&
        intentToExecute.token != _lastExecutedFocusToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final notifier = _discoveryNotifier;
        if (notifier != null) {
          _executeFocusIntent(intentToExecute, notifier);
        }
      });
    }
  }

  Widget _buildMapLayer(
    Coordinates initialCoords,
    List<RestroomMarkerItem> markerItems,
    bool isPermissionGranted,
  ) {
    final discoveryNotifier = context.read<MapDiscoveryNotifier>();

    final clusterManager = MapMarkerAdapter.buildClusterManager(
      onClusterTap: _handleClusterTap,
    );

    final markers = MapMarkerAdapter.adaptMarkers(
      items: markerItems,
      onMarkerTap: (restroomId) {
        final restroom = discoveryNotifier.discoveredRestrooms.firstWhere(
          (r) => r.id == restroomId,
        );
        discoveryNotifier.selectRestroom(restroom);
      },
    );

    if (widget.mapBuilder != null) {
      return widget.mapBuilder!(
        context: context,
        initialCameraPosition: CameraPosition(
          target: LatLng(initialCoords.latitude, initialCoords.longitude),
          zoom: AppConstants.defaultZoomLevel,
        ),
        onMapCreated: (controller) {
          _onDiscoveryMapCreated(
            controller: controller,
            initialCoords: initialCoords,
          );
        },
        onCameraMove: (position) {
          context.read<MapDiscoveryNotifier>().onCameraMove();
          widget.onCameraTargetChanged?.call(
            Coordinates(
              latitude: position.target.latitude,
              longitude: position.target.longitude,
            ),
          );
        },
        onCameraIdle: _handleCameraIdle,
        onCameraMoveStarted: () {
          context.read<MapDiscoveryNotifier>().onCameraMoveStarted();
        },
      );
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(initialCoords.latitude, initialCoords.longitude),
        zoom: AppConstants.defaultZoomLevel,
      ),
      myLocationEnabled: isPermissionGranted,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      markers: markers,
      clusterManagers: {clusterManager},
      onCameraMoveStarted: () {
        context.read<MapDiscoveryNotifier>().onCameraMoveStarted();
      },
      onCameraMove: (position) {
        context.read<MapDiscoveryNotifier>().onCameraMove();
        widget.onCameraTargetChanged?.call(
          Coordinates(
            latitude: position.target.latitude,
            longitude: position.target.longitude,
          ),
        );
      },
      onCameraIdle: _handleCameraIdle,
      onMapCreated: (controller) {
        _onDiscoveryMapCreated(
          controller: GoogleMapCameraController(controller),
          googleController: controller,
          initialCoords: initialCoords,
        );
      },
    );
  }

  void _showFilterSheet(BuildContext context) {
    final notifier = context.read<MapDiscoveryNotifier>();
    FilterBottomSheet.show(
      context,
      initialFilters: notifier.filters,
      onApply: (newFilters) => notifier.setFilters(newFilters),
      onReset: () => notifier.resetFilters(),
    );
  }

  void _showNearbyListSheet(
    BuildContext context,
    MapDiscoveryNotifier notifier,
    Coordinates? userLocation,
  ) {
    // Sort results deterministically: distance-sorted if userLocation exists, name/ID sorted otherwise
    final sortedList = RestroomSorting.sort(
      notifier.visibleRestrooms,
      userLocation: userLocation,
    );

    NearbyRestroomsSheet.show(
      context,
      restrooms: sortedList,
      userLocation: userLocation,
      selectedRestroomId: notifier.selectedRestroom?.id,
      isFilteredEmpty: notifier.hasDerivedEmptyResults,
      derivedEmptyReason: notifier.derivedEmptyReason,
      isDegraded: notifier.isDegraded,
      onResetFilters: () => notifier.resetFilters(),
      onResetSearch: () => notifier.resetSearch(),
      onResetSearchAndFilters: () => notifier.resetSearchAndFilters(),
      onSelectRestroom: (restroom) {
        notifier.selectRestroom(restroom);
        if (_mapCameraController != null) {
          _mapCameraController!.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(
                restroom.coordinates.latitude,
                restroom.coordinates.longitude,
              ),
            ),
          );
        }
      },
    );
  }

  void _showRestroomPreviewSheet(
    BuildContext context,
    Restroom restroom,
    Coordinates? userLocation,
  ) {
    RestroomPreviewSheet.show(
      context,
      restroom: restroom,
      userLocation: userLocation,
      onDirectionsTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Directions to ${restroom.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}
