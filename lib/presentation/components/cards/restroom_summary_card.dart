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
///
/// Supports optional contextual expansions for full Explore tab presentation:
/// - [showFullContext]: Includes building, wing, floor, and landmark hierarchy.
/// - [showAccessType]: Renders access type badge (e.g. Free, Paid, Customer Only).
/// - [showAmenities]: Renders compact icon indicators for key facility amenities.
/// - [showVerification]: Renders community verification signal.
/// - [onInfoTap]: Optional secondary tap action (e.g. preview sheet).
class RestroomSummaryCard extends StatelessWidget {
  final Restroom restroom;
  final Coordinates? userLocation;
  final VoidCallback? onTap;
  final VoidCallback? onInfoTap;
  final bool showAmenities;
  final bool showAccessType;
  final bool showFullContext;
  final bool showVerification;

  const RestroomSummaryCard({
    super.key,
    required this.restroom,
    this.userLocation,
    this.onTap,
    this.onInfoTap,
    this.showAmenities = false,
    this.showAccessType = false,
    this.showFullContext = false,
    this.showVerification = false,
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

    String contextLine;
    if (showFullContext) {
      final parts = <String>[];
      if (restroom.buildingName != null &&
          restroom.buildingName!.trim().isNotEmpty) {
        parts.add(restroom.buildingName!.trim());
      }
      if (restroom.buildingSection != null &&
          restroom.buildingSection!.trim().isNotEmpty) {
        parts.add(restroom.buildingSection!.trim());
      }
      if (restroom.floor != null && restroom.floor!.trim().isNotEmpty) {
        parts.add(restroom.floor!.trim());
      }
      if (distanceString.isNotEmpty) {
        parts.add(distanceString);
      }
      contextLine = parts.join(' · ');
    } else {
      final floorInfo = restroom.floor != null ? '${restroom.floor} · ' : '';
      contextLine = '$floorInfo$distanceString';
    }

    final amenityIcons = <_AmenityIconItem>[];
    if (showAmenities) {
      if (restroom.pwdAccessible == true) {
        amenityIcons.add(
          const _AmenityIconItem(Icons.accessible_rounded, 'PWD Accessible'),
        );
      }
      if (restroom.allGender == true) {
        amenityIcons.add(
          const _AmenityIconItem(Icons.all_inclusive_rounded, 'All-Gender'),
        );
      } else {
        if (restroom.female == true) {
          amenityIcons.add(
            const _AmenityIconItem(Icons.female_rounded, 'Female'),
          );
        }
        if (restroom.male == true) {
          amenityIcons.add(const _AmenityIconItem(Icons.male_rounded, 'Male'));
        }
      }
      if (restroom.babyChanging == true) {
        amenityIcons.add(
          const _AmenityIconItem(Icons.child_care_rounded, 'Baby Changing'),
        );
      }
      if (restroom.hasBidet == true) {
        amenityIcons.add(
          const _AmenityIconItem(Icons.water_drop_rounded, 'Bidet'),
        );
      }
      if (restroom.hasToiletPaper == true) {
        amenityIcons.add(
          const _AmenityIconItem(Icons.layers_rounded, 'Toilet Paper'),
        );
      }
      if (restroom.hasSoap == true) {
        amenityIcons.add(
          const _AmenityIconItem(Icons.clean_hands_rounded, 'Soap'),
        );
      }
      if (restroom.hasHandDryer == true) {
        amenityIcons.add(
          const _AmenityIconItem(Icons.air_rounded, 'Hand Dryer'),
        );
      }
    }

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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (contextLine.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          contextLine,
                          style: AppTypography.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (showFullContext &&
                          restroom.landmark != null &&
                          restroom.landmark!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Near ${restroom.landmark!.trim()}',
                          style: AppTypography.bodySmall.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
                          if (showVerification &&
                              (restroom.lastVerifiedAt != null ||
                                  restroom.verificationCount > 0)) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Verified',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (showAccessType) ...[
                            const SizedBox(width: 8),
                            StatusChip(
                              label: restroom.accessType.label,
                              type: restroom.accessType == AccessType.free
                                  ? StatusChipType.success
                                  : StatusChipType.neutral,
                            ),
                          ],
                        ],
                      ),
                      if (amenityIcons.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final a in amenityIcons)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Tooltip(
                                  message: a.label,
                                  child: Icon(
                                    a.icon,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Trailing section
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (restroom.status ==
                        RestroomStatus.temporarilyUnavailable)
                      const StatusChip(
                        label: 'Unavailable',
                        type: StatusChipType.warning,
                      ),
                    if (onInfoTap != null)
                      IconButton(
                        tooltip: 'Preview details',
                        icon: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: onInfoTap,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AmenityIconItem {
  final IconData icon;
  final String label;

  const _AmenityIconItem(this.icon, this.label);
}
