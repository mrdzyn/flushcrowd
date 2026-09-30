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
import '../../domain/models/restroom.dart';
import '../components/cards/restroom_summary_card.dart';
import '../components/map/map_recenter_button.dart';
import '../components/map/map_search_bar.dart';
import '../components/map/permission_banner.dart';
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
      if (mounted) {
        await context.read<MapDiscoveryNotifier>().loadNearbyRestrooms(coords);
      }
    }
    if (mounted) {
      setState(() => _isRecentering = false);
    }
  }

  Set<Marker> _buildMarkers(List<Restroom> restrooms, Restroom? selected) {
    return restrooms.map((restroom) {
      final isSelected = selected?.id == restroom.id;
      return Marker(
        markerId: MarkerId(restroom.id),
        position: LatLng(
          restroom.coordinates.latitude,
          restroom.coordinates.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isSelected ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueBlue,
        ),
        infoWindow: InfoWindow(
          title: restroom.name,
          snippet: restroom.floor != null
              ? '${restroom.floor} · Rating: ${restroom.averageRating}'
              : null,
        ),
        onTap: () {
          context.read<MapDiscoveryNotifier>().selectRestroom(restroom);
        },
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final locationNotifier = context.watch<LocationNotifier>();
    final discoveryNotifier = context.watch<MapDiscoveryNotifier>();

    final userCoords = locationNotifier.currentCoordinates;
    final effectiveCoords = locationNotifier.effectiveCoordinates;
    final nearbyRestrooms = discoveryNotifier.nearbyRestrooms;
    final selectedRestroom = discoveryNotifier.selectedRestroom;

    return Scaffold(
      body: Stack(
        children: [
          // Map Canvas
          _buildMapLayer(
            effectiveCoords,
            nearbyRestrooms,
            selectedRestroom,
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

  Widget _buildMapLayer(
    Coordinates initialCoords,
    List<Restroom> restrooms,
    Restroom? selected,
    bool isPermissionGranted,
  ) {
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
      markers: _buildMarkers(restrooms, selected),
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
