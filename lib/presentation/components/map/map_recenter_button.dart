import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Floating circular button to center map camera on user's current position.
class MapRecenterButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const MapRecenterButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.border, width: 1),
      ),
      elevation: 3,
      shadowColor: AppColors.textPrimary.withValues(alpha: 0.12),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.my_location_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}
