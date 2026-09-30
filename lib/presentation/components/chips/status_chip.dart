import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_typography.dart';

enum StatusChipType { success, warning, error, neutral }

/// Semantic badge / status indicator chip.
class StatusChip extends StatelessWidget {
  final String label;
  final StatusChipType type;

  const StatusChip({
    super.key,
    required this.label,
    this.type = StatusChipType.success,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    switch (type) {
      case StatusChipType.success:
        bg = AppColors.successContainer;
        fg = AppColors.onSuccessContainer;
        break;
      case StatusChipType.warning:
        bg = AppColors.warningContainer;
        fg = AppColors.onWarningContainer;
        break;
      case StatusChipType.error:
        bg = AppColors.errorContainer;
        fg = AppColors.onErrorContainer;
        break;
      case StatusChipType.neutral:
        bg = AppColors.surfaceVariant;
        fg = AppColors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.smBorder),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
