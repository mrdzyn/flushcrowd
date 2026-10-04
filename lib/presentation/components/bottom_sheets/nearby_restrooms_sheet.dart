import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/models/coordinates.dart';
import '../../../domain/models/restroom.dart';
import '../../state/map_discovery_notifier.dart';
import '../cards/restroom_summary_card.dart';

/// Modal bottom sheet displaying the list of all currently visible/filtered restrooms.
///
/// Features:
/// - Uses existing in-memory discovery/filter results with zero additional network reads.
/// - Deterministic ordering: distance-sorted when [userLocation] is available, name/ID sorted otherwise.
/// - Selecting a list item synchronizes with canonical map/marker selection and closes sheet.
/// - Differentiates between geographic emptiness, search-only, filter-only, and search+filter emptiness.
class NearbyRestroomsSheet extends StatelessWidget {
  final List<Restroom> restrooms;
  final Coordinates? userLocation;
  final String? selectedRestroomId;
  final bool isFilteredEmpty;
  final DerivedEmptyReason? derivedEmptyReason;
  final bool isDegraded;
  final VoidCallback? onResetFilters;
  final VoidCallback? onResetSearch;
  final VoidCallback? onResetSearchAndFilters;
  final ValueChanged<Restroom> onSelectRestroom;

  const NearbyRestroomsSheet({
    super.key,
    required this.restrooms,
    this.userLocation,
    this.selectedRestroomId,
    this.isFilteredEmpty = false,
    this.derivedEmptyReason,
    this.isDegraded = false,
    this.onResetFilters,
    this.onResetSearch,
    this.onResetSearchAndFilters,
    required this.onSelectRestroom,
  });

  /// Static helper to display the sheet modal.
  static Future<void> show(
    BuildContext context, {
    required List<Restroom> restrooms,
    Coordinates? userLocation,
    String? selectedRestroomId,
    bool isFilteredEmpty = false,
    DerivedEmptyReason? derivedEmptyReason,
    bool isDegraded = false,
    VoidCallback? onResetFilters,
    VoidCallback? onResetSearch,
    VoidCallback? onResetSearchAndFilters,
    required ValueChanged<Restroom> onSelectRestroom,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.topSheetBorder,
      ),
      builder: (ctx) => NearbyRestroomsSheet(
        restrooms: restrooms,
        userLocation: userLocation,
        selectedRestroomId: selectedRestroomId,
        isFilteredEmpty: isFilteredEmpty,
        derivedEmptyReason: derivedEmptyReason,
        isDegraded: isDegraded,
        onResetFilters: onResetFilters,
        onResetSearch: onResetSearch,
        onResetSearchAndFilters: onResetSearchAndFilters,
        onSelectRestroom: onSelectRestroom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.border,
                  borderRadius: AppRadii.pillBorder,
                ),
              ),
            ),

            // Header row
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nearby Restrooms (${restrooms.length})',
                    style: AppTypography.headlineMedium,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),

            // Content: Empty State vs Scrollable List
            Expanded(
              child: restrooms.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: restrooms.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      itemBuilder: (_, index) {
                        final item = restrooms[index];
                        final isSelected = item.id == selectedRestroomId;

                        return Container(
                          decoration: isSelected
                              ? BoxDecoration(
                                  borderRadius: AppRadii.lgBorder,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                )
                              : null,
                          child: RestroomSummaryCard(
                            restroom: item,
                            userLocation: userLocation,
                            onTap: () {
                              Navigator.of(context).pop();
                              onSelectRestroom(item);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (isFilteredEmpty) {
      String title;
      String actionLabel;
      VoidCallback? onAction;

      switch (derivedEmptyReason) {
        case DerivedEmptyReason.search:
          title = 'No restrooms match your search';
          actionLabel = 'Clear search';
          onAction = onResetSearch ?? onResetSearchAndFilters;
          break;
        case DerivedEmptyReason.filters:
          title = 'No restrooms match your filters';
          actionLabel = 'Reset filters';
          onAction = onResetFilters ?? onResetSearchAndFilters;
          break;
        case DerivedEmptyReason.searchAndFilters:
        case null:
          title = 'No restrooms match your search & filters';
          actionLabel = 'Clear search & filters';
          onAction = onResetSearchAndFilters ?? onResetFilters;
          break;
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.filter_alt_off_rounded,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                isDegraded
                    ? 'Showing partial results for this area. Try clearing your search criteria.'
                    : 'Try clearing or broadening your search criteria.',
                style: AppTypography.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (onAction != null)
                TextButton.icon(
                  onPressed: () {
                    onAction?.call();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(actionLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              'No restrooms found in this area',
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              'Pan or zoom the map to discover restrooms in other locations.',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
