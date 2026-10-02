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
import '../../domain/models/geo_bounding_box.dart';
import '../../domain/models/restroom.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDiscovery();
    });
  }

  void _initializeDiscovery() {
    final locationNotifier = context.read<LocationNotifier>();
    final discoveryNotifier = context.read<MapDiscoveryNotifier>();
    final coords = locationNotifier.effectiveCoordinates;
    unawaited(discoveryNotifier.loadNearbyRestrooms(coords));
  }

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
    final nearbyRestrooms = discoveryNotifier.nearbyRestrooms;
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
                // Floating Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenHorizontal,
                    vertical: AppSpacing.sm,
                  ),
                  child: MapSearchBar(
                    onChanged: (q) => discoveryNotifier.setSearchQuery(q),
                    onFilterTap: () {
                      _showFilterPlaceholder(context);
                    },
                  ),
                ),

                // Map discovery status pill (loading / zoom-in suppressed / degraded)
                _buildStatusOverlay(discoveryNotifier),

                // Degraded Location Permission Banner
                if (!locationNotifier.isPermissionGranted)
                  PermissionBanner(
                    permissionState: locationNotifier.permissionState,
                    onRequestPermission: () async {
                      await locationNotifier.requestLocationPermission();
                      if (locationNotifier.hasLocation && mounted) {
                        await discoveryNotifier.loadNearbyRestrooms(
                          locationNotifier.effectiveCoordinates,
                        );
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
                                nearbyRestrooms,
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
                          onTap: () => _showRestroomDetailsSheet(
                            context,
                            selectedRestroom,
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

  void _showFilterPlaceholder(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.topSheetBorder,
      ),
      backgroundColor: AppColors.surface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Filters', style: AppTypography.headlineMedium),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Reset',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Phase 1 Filter Controls will be fully activated here.',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  void _showNearbyListSheet(
    BuildContext context,
    List<Restroom> restrooms,
    Coordinates? userLocation,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.topSheetBorder,
      ),
      backgroundColor: AppColors.surface,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: ListView.separated(
            controller: scrollController,
            itemCount: restrooms.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    'Nearby Restrooms (${restrooms.length})',
                    style: AppTypography.headlineMedium,
                  ),
                );
              }
              final item = restrooms[index - 1];
              return RestroomSummaryCard(
                restroom: item,
                userLocation: userLocation,
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<MapDiscoveryNotifier>().selectRestroom(item);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showRestroomDetailsSheet(BuildContext context, Restroom restroom) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.topSheetBorder,
      ),
      backgroundColor: AppColors.surface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(restroom.name, style: AppTypography.headlineMedium),
            if (restroom.buildingName != null) ...[
              const SizedBox(height: 4),
              Text(
                '${restroom.buildingName} · ${restroom.floor ?? ""}',
                style: AppTypography.bodyMedium,
              ),
            ],
            if (restroom.directionsNote != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: AppRadii.mdBorder,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        restroom.directionsNote!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Phase 1 will deliver the complete interactive details modal and navigation handoff.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
