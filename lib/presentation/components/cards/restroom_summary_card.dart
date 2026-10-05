import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/services/gis/haversine.dart';
import '../../../domain/models/coordinates.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/restroom.dart';
import '../chips/status_chip.dart';

/// Compact restroom preview card matching the canonical mockup design.
class RestroomSummaryCard extends StatelessWidget {
  final Restroom restroom;
  final Coordinates? userLocation;
  final VoidCallback? onTap;

  const RestroomSummaryCard({
    super.key,
    required this.restroom,
    this.userLocation,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String distanceString = '';
    if (userLocation != null) {
      final meters = Haversine.distanceInMeters(
        userLocation!,
        restroom.coordinates,
      );
      distanceString = Haversine.formatDistance(meters);
    }

    final floorInfo = restroom.floor != null ? '${restroom.floor} · ' : '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lgBorder,
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.lgBorder,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.lgBorder,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Thumbnail or restroom placeholder icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: AppRadii.mdBorder,
                  ),
                  child: const Icon(
                    Icons.wc_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                // Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        restroom.name,
                        style: AppTypography.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$floorInfo$distanceString',
                        style: AppTypography.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: AppColors.ratingStar,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            restroom.averageRating.toStringAsFixed(1),
                            style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (restroom.ratingCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${restroom.ratingCount})',
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (restroom.status ==
                    RestroomStatus.temporarilyUnavailable) ...[
                  const SizedBox(width: 8),
                  const StatusChip(
                    label: 'Unavailable',
                    type: StatusChipType.warning,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
