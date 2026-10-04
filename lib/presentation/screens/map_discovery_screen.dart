import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/services/gis/haversine.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/geo_bounding_box.dart';
import '../../domain/models/restroom.dart';
import '../components/bottom_sheets/filter_bottom_sheet.dart';
import '../components/bottom_sheets/nearby_restrooms_sheet.dart';
import '../components/bottom_sheets/restroom_preview_sheet.dart';
import '../components/cards/restroom_summary_card.dart';
import '../components/map/map_marker_adapter.dart';
import '../components/map/map_recenter_button.dart';
import '../components/map/map_search_bar.dart';
import '../components/map/permission_banner.dart';
import '../models/restroom_marker_item.dart';
import '../state/location_notifier.dart';
import '../state/map_discovery_notifier.dart';

/// Primary map discovery screen matching canonical UX mockup Item 2.
class MapDiscoveryScreen extends StatefulWidget {
  const MapDiscoveryScreen({super.key});

  @override
  State<MapDiscoveryScreen> createState() => _MapDiscoveryScreenState();
}

class _MapDiscoveryScreenState extends State<MapDiscoveryScreen> {
  GoogleMapController? _mapController;
  bool _isRecentering = false;

  Future<void> _recenterOnUser() async {
    setState(() => _isRecentering = true);
    final locationNotifier = context.read<LocationNotifier>();
    await locationNotifier.fetchCurrentLocation();

    final coords = locationNotifier.currentCoordinates;
    if (coords != null && _mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(coords.latitude, coords.longitude),
          AppConstants.defaultZoomLevel,
        ),
      );
    }
    if (mounted) {
      setState(() => _isRecentering = false);
    }
  }

  void _handleClusterTap(Cluster cluster) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        cluster.position,
        // Zoom in by 2 levels to expand the cluster
        // without arbitrarily selecting a single restroom
        16.0,
      ),
    );
  }

  Future<void> _handleCameraIdle() async {
    if (_mapController == null || !mounted) return;
    final notifier = context.read<MapDiscoveryNotifier>();
    try {
      final bounds = await _mapController!.getVisibleRegion();
      final zoom = await _mapController!.getZoomLevel();
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
                        if (coords != null && _mapController != null) {
                          await _mapController!.animateCamera(
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

                // Nearest to you card bottom container
                if (selectedRestroom != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenHorizontal,
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Nearest to you',
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showNearbyListSheet(
                                context,
                                discoveryNotifier,
                                userCoords,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'See all',
                                style: AppTypography.labelMedium.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        RestroomSummaryCard(
                          restroom: selectedRestroom,
                          userLocation: userCoords,
                          onTap: () => _showRestroomPreviewSheet(
                            context,
                            selectedRestroom,
                            userCoords,
                          ),
                        ),
                      ],
                    ),
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
    if (notifier.isLoading) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: AppRadii.pillBorder,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Searching visible area...',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (notifier.isSuppressed) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: AppRadii.pillBorder,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.zoom_in,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Zoom in to see restrooms',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (notifier.isDegraded) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: AppRadii.pillBorder,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline,
                size: 16,
                color: AppColors.warning,
              ),
              const SizedBox(width: 6),
              Text(
                'Showing partial results (safety cap reached)',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (notifier.isFilteredEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
            borderRadius: AppRadii.pillBorder,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.filter_alt_off_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'No matches for current filters',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => notifier.resetFilters(),
                child: Text(
                  'Reset',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
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
      onCameraMove: (_) {
        context.read<MapDiscoveryNotifier>().onCameraMove();
      },
      onCameraIdle: _handleCameraIdle,
      onMapCreated: (controller) {
        _mapController = controller;
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
    // Sort results: distance-sorted if userLocation exists, name-sorted otherwise
    final sortedList = List<Restroom>.from(notifier.visibleRestrooms);
    if (userLocation != null) {
      sortedList.sort((a, b) {
        final distA = Haversine.distanceInMeters(userLocation, a.coordinates);
        final distB = Haversine.distanceInMeters(userLocation, b.coordinates);
        return distA.compareTo(distB);
      });
    } else {
      sortedList.sort((a, b) => a.name.compareTo(b.name));
    }

    NearbyRestroomsSheet.show(
      context,
      restrooms: sortedList,
      userLocation: userLocation,
      selectedRestroomId: notifier.selectedRestroom?.id,
      isFilteredEmpty: notifier.isFilteredEmpty,
      onResetFilters: () => notifier.resetFilters(),
      onSelectRestroom: (restroom) {
        notifier.selectRestroom(restroom);
        if (_mapController != null) {
          _mapController!.animateCamera(
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
