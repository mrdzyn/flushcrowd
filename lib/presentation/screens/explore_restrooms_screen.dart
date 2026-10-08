import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/models/restroom.dart';
import '../components/bottom_sheets/filter_bottom_sheet.dart';
import '../components/cards/restroom_summary_card.dart';
import '../components/feedback/empty_state_view.dart';
import '../components/feedback/error_state_view.dart';
import '../components/feedback/loading_indicator.dart';
import '../components/map/map_search_bar.dart';
import '../state/location_notifier.dart';
import '../state/map_discovery_notifier.dart';
import '../utils/restroom_sorting.dart';

/// Explore tab screen presenting discovery results in a scrollable, filterable list.
///
/// Features:
/// - Consumes existing in-memory [MapDiscoveryNotifier] state with zero additional network reads.
/// - Deterministic sorting via [RestroomSorting] (distance-sorted when device location is available).
/// - Comprehensive state lifecycle handling: loading, degraded warning, error, suppressed,
///   derived empty (search/filter), geographic empty, and loaded results.
/// - Selecting a restroom card synchronizes selection with [MapDiscoveryNotifier] and switches to map view.
class ExploreRestroomsScreen extends StatelessWidget {
  final ValueChanged<Restroom>? onSelectRestroom;
  final VoidCallback? onSwitchToMap;

  const ExploreRestroomsScreen({
    super.key,
    this.onSelectRestroom,
    this.onSwitchToMap,
  });

  @override
  Widget build(BuildContext context) {
    final discoveryNotifier = context.watch<MapDiscoveryNotifier>();
    final locationNotifier = context.watch<LocationNotifier>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Explore Restrooms'),
        elevation: 0,
        backgroundColor: AppColors.surface,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search and Filter Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.sm,
              ),
              child: MapSearchBar(
                initialQuery: discoveryNotifier.searchQuery.isNotEmpty
                    ? discoveryNotifier.searchQuery
                    : null,
                activeFilterCount: discoveryNotifier.filters.activeFilterCount,
                onChanged: (q) => discoveryNotifier.setSearchQuery(q),
                onFilterTap: () => FilterBottomSheet.show(
                  context,
                  initialFilters: discoveryNotifier.filters,
                  onApply: (filters) => discoveryNotifier.setFilters(filters),
                  onReset: () => discoveryNotifier.resetFilters(),
                ),
              ),
            ),

            // Degraded partial results banner
            if (discoveryNotifier.isDegraded)
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                  vertical: AppSpacing.xs,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer.withValues(alpha: 0.5),
                  borderRadius: AppRadii.smBorder,
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Showing partial results (safety cap reached)',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Non-blocking error banner when previous results are retained
            if (discoveryNotifier.hasError &&
                discoveryNotifier.visibleRestrooms.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                  vertical: AppSpacing.xs,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.5),
                  borderRadius: AppRadii.smBorder,
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Couldn't refresh — showing previous results",
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (discoveryNotifier.canRetryViewportQuery)
                      TextButton(
                        onPressed: () =>
                            discoveryNotifier.retryLastViewportQuery(),
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),

            // Dynamic lifecycle content
            Expanded(
              child: _buildContent(
                context,
                discoveryNotifier,
                locationNotifier,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    MapDiscoveryNotifier discoveryNotifier,
    LocationNotifier locationNotifier,
  ) {
    // 1. Loading state when no visible items exist
    if (discoveryNotifier.isLoading &&
        discoveryNotifier.visibleRestrooms.isEmpty) {
      return const Center(
        child: LooLoadingIndicator(message: 'Searching nearby restrooms...'),
      );
    }

    // 2. Error state when no visible items exist
    if (discoveryNotifier.hasError &&
        discoveryNotifier.visibleRestrooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ErrorStateView(
            title: 'Unable to Load Restrooms',
            message:
                discoveryNotifier.errorMessage ??
                'Please check your connection and try again.',
            onRetry: discoveryNotifier.canRetryViewportQuery
                ? () => discoveryNotifier.retryLastViewportQuery()
                : null,
          ),
        ),
      );
    }

    // 3. Zoom-in suppressed state
    if (discoveryNotifier.isSuppressed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: EmptyStateView(
            icon: Icons.zoom_in_rounded,
            title: 'Zoom In on Map to Explore',
            description: 'Zoom in closer on the map to search and discover nearby restrooms.',
            actionLabel: 'View Map',
            onAction: onSwitchToMap,
          ),
        ),
      );
    }

    // 4. Derived empty results (search / filters)
    if (discoveryNotifier.hasDerivedEmptyResults) {
      return _buildDerivedEmptyState(context, discoveryNotifier);
    }

    // 5. Geographic empty results (zero facilities discovered in area)
    if (discoveryNotifier.isEmpty ||
        discoveryNotifier.discoveredRestrooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: EmptyStateView(
            icon: Icons.location_off_outlined,
            title: 'No Restrooms Found Nearby',
            description: 'No restrooms were found in this area. Pan or zoom the map to search other locations.',
            actionLabel: 'Explore on Map',
            onAction: onSwitchToMap,
          ),
        ),
      );
    }

    // 6. Loaded visible results
    final userCoords = locationNotifier.currentCoordinates;
    final sortedList = RestroomSorting.sort(
      discoveryNotifier.visibleRestrooms,
      userLocation: userCoords,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            'Restrooms (${sortedList.length})',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.xs,
              AppSpacing.screenHorizontal,
              AppSpacing.xl,
            ),
            itemCount: sortedList.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final restroom = sortedList[index];
              final isSelected =
                  restroom.id == discoveryNotifier.selectedRestroom?.id;

              return Container(
                decoration: isSelected
                    ? BoxDecoration(
                        borderRadius: AppRadii.lgBorder,
                        border: Border.all(color: AppColors.primary, width: 2),
                      )
                    : null,
                child: RestroomSummaryCard(
                  restroom: restroom,
                  userLocation: userCoords,
                  showFullContext: true,
                  showAccessType: true,
                  showAmenities: true,
                  showVerification: true,
                  onTap: () {
                    discoveryNotifier.selectRestroom(restroom);
                    onSelectRestroom?.call(restroom);
                  },
                  onInfoTap: () {
                    discoveryNotifier.selectRestroom(restroom);
                    onSelectRestroom?.call(restroom);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDerivedEmptyState(
    BuildContext context,
    MapDiscoveryNotifier notifier,
  ) {
    String title;
    String description;
    String actionLabel;
    VoidCallback onAction;

    switch (notifier.derivedEmptyReason) {
      case DerivedEmptyReason.search:
        title = 'No restrooms match your search';
        description =
            'Try searching with different keywords or clearing the search bar.';
        actionLabel = 'Clear Search';
        onAction = () => notifier.resetSearch();
        break;
      case DerivedEmptyReason.filters:
        title = 'No restrooms match your filters';
        description = 'Try adjusting or resetting your filter options to see more results.';
        actionLabel = 'Reset Filters';
        onAction = () => notifier.resetFilters();
        break;
      case DerivedEmptyReason.searchAndFilters:
      case null:
        title = 'No restrooms match your search & filters';
        description = 'Try clearing your search query and resetting filters to view nearby facilities.';
        actionLabel = 'Clear Search & Filters';
        onAction = () => notifier.resetSearchAndFilters();
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: EmptyStateView(
          icon: Icons.filter_alt_off_rounded,
          title: title,
          description: description,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }
}
