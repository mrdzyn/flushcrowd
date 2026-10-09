import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/services/gis/haversine.dart';
import '../../../domain/models/duplicate_candidate.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/restroom.dart';
import '../../components/buttons/loo_primary_button.dart';
import '../../components/buttons/loo_secondary_button.dart';

/// Actions that can result from the [DuplicateWarningSheet].
sealed class DuplicateWarningAction {
  const DuplicateWarningAction();
}

/// User selected an existing restroom to view on the discovery map.
class ViewExistingRestroomAction extends DuplicateWarningAction {
  final Restroom restroom;
  const ViewExistingRestroomAction(this.restroom);
}

/// User confirmed that their draft is a distinct facility and chose to proceed.
class ProceedWithSubmissionAction extends DuplicateWarningAction {
  const ProceedWithSubmissionAction();
}

/// Advisory modal bottom sheet displayed when candidate duplicates (score >= 0.50)
/// are detected for a contribution draft.
///
/// Implements Phase 2 Section 9.5:
/// - Header: "Similar restrooms found nearby"
/// - Explanation: "We found an existing restroom near this location. Is this the same facility?"
/// - Up to 3 candidate cards showing name, distance, floor, and access type.
/// - Actions:
///   - "View Existing Restroom": Dismisses sheet, centers map on candidate, opens preview.
///   - "No, It's a Different Restroom": Acknowledges warning and proceeds.
class DuplicateWarningSheet extends StatelessWidget {
  final List<DuplicateCandidate> candidates;
  final ValueChanged<Restroom>? onViewExisting;
  final VoidCallback? onProceed;

  const DuplicateWarningSheet({
    super.key,
    required this.candidates,
    this.onViewExisting,
    this.onProceed,
  });

  /// Static helper to display the sheet modal.
  static Future<DuplicateWarningAction?> show(
    BuildContext context, {
    required List<DuplicateCandidate> candidates,
    ValueChanged<Restroom>? onViewExisting,
    VoidCallback? onProceed,
  }) {
    return showModalBottomSheet<DuplicateWarningAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.topSheetBorder,
      ),
      builder: (ctx) => DuplicateWarningSheet(
        candidates: candidates,
        onViewExisting: onViewExisting,
        onProceed: onProceed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show at most 3 candidates as specified in Section 9.4
    final displayedCandidates = candidates.take(3).toList();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Warning Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Similar restrooms found nearby',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Explanation
              Text(
                'We found an existing restroom near this location. Is this the same facility?',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Candidate Cards (up to 3)
              for (int i = 0; i < displayedCandidates.length; i++) ...[
                _CandidateCard(
                  candidate: displayedCandidates[i],
                  onView: () {
                    final restroom = displayedCandidates[i].restroom;
                    onViewExisting?.call(restroom);
                    Navigator.of(context)
                        .pop(ViewExistingRestroomAction(restroom));
                  },
                ),
                if (i < displayedCandidates.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.lg),

              // Primary Action: "No, It's a Different Restroom"
              LooPrimaryButton(
                label: "No, It's a Different Restroom",
                onPressed: () {
                  onProceed?.call();
                  Navigator.of(context)
                      .pop(const ProceedWithSubmissionAction());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final DuplicateCandidate candidate;
  final VoidCallback onView;

  const _CandidateCard({required this.candidate, required this.onView});

  String _formatAccessType(AccessType accessType) {
    switch (accessType) {
      case AccessType.free:
        return 'Free';
      case AccessType.paid:
        return 'Paid';
      case AccessType.customerOnly:
        return 'Customer Only';
      case AccessType.keyRequired:
        return 'Key Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final restroom = candidate.restroom;
    final distanceText = Haversine.formatDistance(candidate.distanceMeters);

    final details = <String>[];
    details.add(distanceText);
    if (restroom.floor != null && restroom.floor!.trim().isNotEmpty) {
      details.add('Floor: ${restroom.floor!.trim()}');
    }
    if (restroom.buildingName != null &&
        restroom.buildingName!.trim().isNotEmpty) {
      details.add(restroom.buildingName!.trim());
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.mdBorder,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and Access Type row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  restroom.name,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadii.smBorder,
                ),
                child: Text(
                  _formatAccessType(restroom.accessType),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Context & Distance
          Text(
            details.join(' · '),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Action button: "View Existing Restroom"
          LooSecondaryButton(
            label: 'View Existing Restroom',
            icon: Icons.visibility_outlined,
            height: 48.0,
            onPressed: onView,
          ),
        ],
      ),
    );
  }
}
