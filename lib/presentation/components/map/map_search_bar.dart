import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_typography.dart';

/// Floating search and filter header over the map.
class MapSearchBar extends StatelessWidget {
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterTap;

  const MapSearchBar({super.key, this.onChanged, this.onFilterTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.pillBorder,
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: AppColors.textTertiary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Search nearby toilets...',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (onFilterTap != null) ...[
            Container(
              height: 24,
              width: 1,
              color: AppColors.border,
              margin: const EdgeInsets.symmetric(horizontal: 8),
            ),
            IconButton(
              icon: const Icon(
                Icons.tune_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
              onPressed: onFilterTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 20,
            ),
          ],
        ],
      ),
    );
  }
}
