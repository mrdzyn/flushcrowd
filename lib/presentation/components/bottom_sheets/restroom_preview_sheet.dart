import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/services/gis/haversine.dart';
import '../../../domain/models/coordinates.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/restroom.dart';
import '../../components/buttons/loo_primary_button.dart';
import '../../components/chips/amenity_chip.dart';
import '../../components/chips/status_chip.dart';

/// Full interactive restroom preview bottom sheet matching canonical mobile UX mockup Item 3.
///
/// Strictly renders only real domain fields present on [Restroom].
/// Omits optional fields gracefully without awkward empty labels.
/// Opening/closing this preview causes zero network/Firestore reads.
class RestroomPreviewSheet extends StatelessWidget {
  final Restroom restroom;
  final Coordinates? userLocation;
  final VoidCallback? onDirectionsTap;

  const RestroomPreviewSheet({
    super.key,
    required this.restroom,
    this.userLocation,
    this.onDirectionsTap,
  });

  /// Static helper to display the sheet modal.
  static Future<void> show(
    BuildContext context, {
    required Restroom restroom,
    Coordinates? userLocation,
    VoidCallback? onDirectionsTap,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.topSheetBorder,
      ),
      builder: (ctx) => RestroomPreviewSheet(
        restroom: restroom,
        userLocation: userLocation,
        onDirectionsTap: onDirectionsTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Calculate distance if user location is available
    String? distanceString;
    if (userLocation != null) {
      final meters = Haversine.distanceInMeters(
        userLocation!,
        restroom.coordinates,
      );
      distanceString = Haversine.formatDistance(meters);
    }

    // 2. Format indoor hierarchy string: Building · Wing · Floor · Unit
    final indoorParts = <String>[];
    if (restroom.buildingName != null &&
        restroom.buildingName!.trim().isNotEmpty) {
      indoorParts.add(restroom.buildingName!.trim());
    }
    if (restroom.buildingSection != null &&
        restroom.buildingSection!.trim().isNotEmpty) {
      indoorParts.add(restroom.buildingSection!.trim());
    }
    if (restroom.floor != null && restroom.floor!.trim().isNotEmpty) {
      indoorParts.add(restroom.floor!.trim());
    }
    if (restroom.unitOrArea != null && restroom.unitOrArea!.trim().isNotEmpty) {
      indoorParts.add(restroom.unitOrArea!.trim());
    }
    final indoorHierarchy = indoorParts.join(' · ');

    // 3. Collect supported amenity pills
    final amenityPills = _buildAmenityPills();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle pill
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.border,
                  borderRadius: AppRadii.pillBorder,
                ),
              ),
            ),

            // Header Row: Restroom Name & Close Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restroom.name,
                        style: AppTypography.headlineMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (indoorHierarchy.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          indoorHierarchy,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
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

            const SizedBox(height: AppSpacing.sm),

            // Rating, Distance, and Access Badges Row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Rating pill
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 18,
                      color: AppColors.ratingStar,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      restroom.averageRating.toStringAsFixed(1),
                      style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (restroom.ratingCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${restroom.ratingCount})',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),

                // Distance pill if available
                if (distanceString != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: AppRadii.smBorder,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.near_me_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          distanceString,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Access type badge
                StatusChip(
                  label: restroom.accessType.label,
                  type: restroom.accessType == AccessType.free
                      ? StatusChipType.success
                      : StatusChipType.neutral,
                ),

                // Status chip (Open / Active)
                if (restroom.status == RestroomStatus.active)
                  const StatusChip(label: 'Open', type: StatusChipType.success),
              ],
            ),

            // Landmark context if present
            if (restroom.landmark != null &&
                restroom.landmark!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Near ${restroom.landmark!.trim()}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Directions Note callout if present
            if (restroom.directionsNote != null &&
                restroom.directionsNote!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: AppRadii.mdBorder,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.navigation_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Indoor Directions',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            restroom.directionsNote!.trim(),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Verification freshness banner if verified
            if (restroom.verificationCount > 0 ||
                restroom.lastVerifiedAt != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatVerificationInfo(),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // Amenities & Accessibility Header
            Text(
              'Amenities & Access',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // Amenity chips wrap
            Wrap(spacing: 8, runSpacing: 8, children: amenityPills),

            const SizedBox(height: AppSpacing.xl),

            // Actions row
            Row(
              children: [
                Expanded(
                  child: LooPrimaryButton(
                    label: 'Get Directions',
                    icon: Icons.directions_outlined,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDirectionsTap?.call();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatVerificationInfo() {
    if (restroom.lastVerifiedAt != null) {
      final days = DateTime.now().difference(restroom.lastVerifiedAt!).inDays;
      if (days <= 0) {
        return 'Verified today by community';
      } else if (days == 1) {
        return 'Verified yesterday';
      } else if (days < 30) {
        return 'Verified $days days ago';
      } else {
        return 'Verified recently';
      }
    }
    return 'Verified by community (${restroom.verificationCount})';
  }

  List<Widget> _buildAmenityPills() {
    final pills = <Widget>[];

    // Gender / Restroom types
    if (restroom.allGender) {
      pills.add(
        const AmenityChip(
          icon: Icons.all_inclusive_rounded,
          label: 'All-Gender',
          isSelected: true,
        ),
      );
    } else {
      if (restroom.female) {
        pills.add(
          const AmenityChip(
            icon: Icons.female_rounded,
            label: 'Female',
            isSelected: true,
          ),
        );
      }
      if (restroom.male) {
        pills.add(
          const AmenityChip(
            icon: Icons.male_rounded,
            label: 'Male',
            isSelected: true,
          ),
        );
      }
    }

    // PWD Accessibility
    if (restroom.pwdAccessible) {
      pills.add(
        const AmenityChip(
          icon: Icons.accessible_rounded,
          label: 'PWD Accessible',
          isSelected: true,
        ),
      );
    }

    // Baby Changing
    if (restroom.babyChanging) {
      pills.add(
        const AmenityChip(
          icon: Icons.child_care_rounded,
          label: 'Baby Changing',
          isSelected: true,
        ),
      );
    }

    // Bidet
    if (restroom.hasBidet) {
      pills.add(
        const AmenityChip(
          icon: Icons.water_drop_outlined,
          label: 'Bidet',
          isSelected: true,
        ),
      );
    }

    // Toilet Paper
    if (restroom.hasToiletPaper) {
      pills.add(
        const AmenityChip(
          icon: Icons.receipt_long_outlined,
          label: 'Toilet Paper',
          isSelected: true,
        ),
      );
    }

    // Soap
    if (restroom.hasSoap) {
      pills.add(
        const AmenityChip(
          icon: Icons.soap_outlined,
          label: 'Soap',
          isSelected: true,
        ),
      );
    }

    // Hand Dryer
    if (restroom.hasHandDryer) {
      pills.add(
        const AmenityChip(
          icon: Icons.air_rounded,
          label: 'Hand Dryer',
          isSelected: true,
        ),
      );
    }

    // Fee detail if paid
    if (restroom.accessType == AccessType.paid && restroom.feeAmount != null) {
      final currency = restroom.feeCurrency ?? '';
      pills.add(
        AmenityChip(
          icon: Icons.payments_outlined,
          label: '$currency ${restroom.feeAmount!.toStringAsFixed(2)}'.trim(),
          isSelected: false,
        ),
      );
    }

    return pills;
  }
}
