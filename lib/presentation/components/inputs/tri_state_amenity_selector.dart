import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/models/restroom_draft.dart';

/// Reusable accessible tri-state selector for FlushCrowd amenities and stall options.
///
/// Supports three explicit states:
/// - [TriStateAmenity.yes] ("Yes")
/// - [TriStateAmenity.no] ("No")
/// - [TriStateAmenity.unknown] ("Unspecified")
///
/// Complies with accessibility invariants:
/// - Minimum 48x48 pt touch targets.
/// - Clear selected state with visual indicators beyond color (e.g., checkmark icons).
/// - Semantic labels and accessibility roles.
/// - Text scaling support.
class TriStateAmenitySelector extends StatelessWidget {
  final String title;
  final TriStateAmenity value;
  final ValueChanged<TriStateAmenity> onChanged;
  final IconData? icon;
  final String? subtitle;
  final String? semanticLabel;

  const TriStateAmenitySelector({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.semanticLabel,
  });

  /// Factory helper that bridges nullable boolean values (stalls: true, false, null)
  /// with the [TriStateAmenity] UI model.
  static Widget forNullableBool({
    Key? key,
    required String title,
    required bool? value,
    required ValueChanged<bool?> onChanged,
    IconData? icon,
    String? subtitle,
    String? semanticLabel,
  }) {
    return TriStateAmenitySelector(
      key: key,
      title: title,
      value: TriStateAmenity.fromNullableBool(value),
      onChanged: (triState) => onChanged(triState.toNullableBool()),
      icon: icon,
      subtitle: subtitle,
      semanticLabel: semanticLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSemanticLabel = semanticLabel ?? title;

    return Semantics(
      container: true,
      label: effectiveSemanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitle!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  Expanded(
                    child: _TriStateOptionButton(
                      label: 'Yes',
                      icon: Icons.check_circle_rounded,
                      isSelected: value == TriStateAmenity.yes,
                      selectedBackgroundColor: AppColors.primaryLight,
                      selectedBorderColor: AppColors.primary,
                      selectedTextColor: AppColors.primaryDark,
                      onTap: () => onChanged(TriStateAmenity.yes),
                      parentLabel: effectiveSemanticLabel,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _TriStateOptionButton(
                      label: 'No',
                      icon: Icons.cancel_rounded,
                      isSelected: value == TriStateAmenity.no,
                      selectedBackgroundColor: AppColors.errorContainer,
                      selectedBorderColor: AppColors.error,
                      selectedTextColor: AppColors.onErrorContainer,
                      onTap: () => onChanged(TriStateAmenity.no),
                      parentLabel: effectiveSemanticLabel,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _TriStateOptionButton(
                      label: 'Unspecified',
                      icon: Icons.help_outline_rounded,
                      isSelected: value == TriStateAmenity.unknown,
                      selectedBackgroundColor: AppColors.surfaceVariant,
                      selectedBorderColor: AppColors.textSecondary,
                      selectedTextColor: AppColors.textPrimary,
                      onTap: () => onChanged(TriStateAmenity.unknown),
                      parentLabel: effectiveSemanticLabel,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TriStateOptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color selectedBackgroundColor;
  final Color selectedBorderColor;
  final Color selectedTextColor;
  final VoidCallback onTap;
  final String parentLabel;

  const _TriStateOptionButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.selectedBackgroundColor,
    required this.selectedBorderColor,
    required this.selectedTextColor,
    required this.onTap,
    required this.parentLabel,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isSelected
        ? selectedBackgroundColor
        : AppColors.surface;
    final borderColor = isSelected ? selectedBorderColor : AppColors.border;
    final textColor = isSelected ? selectedTextColor : AppColors.textSecondary;
    final borderWidth = isSelected ? 2.0 : 1.0;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$parentLabel, $label',
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdBorder,
          side: BorderSide(color: borderColor, width: borderWidth),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.mdBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    Icon(icon, size: 16, color: textColor),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: textColor,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
