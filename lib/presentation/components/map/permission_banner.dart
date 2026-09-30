import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/models/enums.dart';

/// Informative banner shown when foreground location permission is not granted,
/// ensuring the app gracefully degrades for manual map exploration.
class PermissionBanner extends StatelessWidget {
  final LocationPermissionState permissionState;
  final VoidCallback onRequestPermission;
  final VoidCallback? onDismiss;

  const PermissionBanner({
    super.key,
    required this.permissionState,
    required this.onRequestPermission,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (permissionState.isGranted) {
      return const SizedBox.shrink();
    }

    final isPermanentlyDenied = permissionState.isPermanentlyDenied;
    final message = isPermanentlyDenied
        ? 'Location is permanently disabled. Enable in Settings for automatic nearby restrooms, or explore the map manually.'
        : 'Enable location to automatically find nearby restrooms, or continue exploring the map manually.';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lgBorder,
        border: Border.all(color: AppColors.primaryLight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_searching_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPermanentlyDenied
                      ? 'Location Permission Needed'
                      : 'Explore Faster With Location',
                  style: AppTypography.titleMedium.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(message, style: AppTypography.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: onRequestPermission,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppColors.primary,
                      ),
                      child: Text(
                        isPermanentlyDenied
                            ? 'Open Settings'
                            : 'Enable Location',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onDismiss != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onDismiss,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppColors.textTertiary,
                        ),
                        child: Text(
                          'Explore Manually',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
