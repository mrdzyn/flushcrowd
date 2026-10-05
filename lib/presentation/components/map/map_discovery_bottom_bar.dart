import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/models/coordinates.dart';
import '../../../domain/models/restroom.dart';
import '../cards/restroom_summary_card.dart';

/// Bottom results section on the discovery map:
/// - Accessible whenever visible restrooms exist (even if `selectedRestroom == null`).
/// - Displays 'Nearest to you' + summary card when a restroom is selected.
/// - Displays 'Nearby restrooms (N)' without card when no restroom is selected.
/// - Header 'See all' triggers full nearby list bottom sheet.
class MapDiscoveryBottomBar extends StatelessWidget {
  final List<Restroom> visibleRestrooms;
  final Restroom? selectedRestroom;
  final Coordinates? userCoordinates;
  final VoidCallback onSeeAll;
  final ValueChanged<Restroom>? onCardTap;

  const MapDiscoveryBottomBar({
    super.key,
    required this.visibleRestrooms,
    this.selectedRestroom,
    this.userCoordinates,
    required this.onSeeAll,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    if (visibleRestrooms.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
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
                selectedRestroom != null
                    ? 'Nearest to you'
                    : 'Nearby restrooms (${visibleRestrooms.length})',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: onSeeAll,
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
          if (selectedRestroom != null) ...[
            const SizedBox(height: AppSpacing.sm),
            RestroomSummaryCard(
              restroom: selectedRestroom!,
              userLocation: userCoordinates,
              onTap: onCardTap != null
                  ? () => onCardTap!(selectedRestroom!)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
