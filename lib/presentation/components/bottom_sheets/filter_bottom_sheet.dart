import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/models/discovery_filters.dart';
import '../../../domain/models/enums.dart';
import '../../components/buttons/loo_primary_button.dart';
import '../../components/chips/amenity_chip.dart';

/// Interactive modal bottom sheet for configuring Phase 1 discovery filters.
///
/// Features:
/// - Staged local state: users can toggle filter pills and click "Apply" or "Reset".
/// - Directly bound to real domain fields supported by [Restroom] and [DiscoveryFilters].
/// - Operates 100% in-memory with zero network reads.
class FilterBottomSheet extends StatefulWidget {
  final DiscoveryFilters initialFilters;
  final ValueChanged<DiscoveryFilters> onApply;
  final VoidCallback onReset;

  const FilterBottomSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    required this.onReset,
  });

  /// Static helper to show the filter sheet modal.
  static Future<void> show(
    BuildContext context, {
    required DiscoveryFilters initialFilters,
    required ValueChanged<DiscoveryFilters> onApply,
    required VoidCallback onReset,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.topSheetBorder,
      ),
      builder: (ctx) => FilterBottomSheet(
        initialFilters: initialFilters,
        onApply: onApply,
        onReset: onReset,
      ),
    );
  }

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late Set<AccessType> _accessTypes;
  late Set<GenderTypeFilter> _genderTypes;
  late bool _pwdAccessible;
  late bool _babyChanging;
  late bool _bidet;
  late bool _toiletPaper;
  late bool _soap;
  late bool _handDryer;
  late bool _recentlyVerified;
  late double _minRating;

  @override
  void initState() {
    super.initState();
    _accessTypes = Set.from(widget.initialFilters.accessTypes);
    _genderTypes = Set.from(widget.initialFilters.genderTypes);
    _pwdAccessible = widget.initialFilters.pwdAccessibleOnly;
    _babyChanging = widget.initialFilters.babyChangingOnly;
    _bidet = widget.initialFilters.bidetOnly;
    _toiletPaper = widget.initialFilters.toiletPaperOnly;
    _soap = widget.initialFilters.soapOnly;
    _handDryer = widget.initialFilters.handDryerOnly;
    _recentlyVerified = widget.initialFilters.recentlyVerifiedOnly;
    _minRating = widget.initialFilters.minRating;
  }

  DiscoveryFilters _buildFilters() {
    return DiscoveryFilters(
      accessTypes: _accessTypes,
      genderTypes: _genderTypes,
      pwdAccessibleOnly: _pwdAccessible,
      babyChangingOnly: _babyChanging,
      bidetOnly: _bidet,
      toiletPaperOnly: _toiletPaper,
      soapOnly: _soap,
      handDryerOnly: _handDryer,
      recentlyVerifiedOnly: _recentlyVerified,
      minRating: _minRating,
    );
  }

  void _resetLocal() {
    setState(() {
      _accessTypes.clear();
      _genderTypes.clear();
      _pwdAccessible = false;
      _babyChanging = false;
      _bidet = false;
      _toiletPaper = false;
      _soap = false;
      _handDryer = false;
      _recentlyVerified = false;
      _minRating = 0.0;
    });
    widget.onReset();
    Navigator.of(context).pop();
  }

  void _applyLocal() {
    final filters = _buildFilters();
    widget.onApply(filters);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
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

              // Title and Reset Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filters', style: AppTypography.headlineMedium),
                  TextButton(
                    onPressed: _resetLocal,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Reset', style: AppTypography.labelLarge),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // 1. Access Types Section
              _buildSectionHeader('Access & Pricing'),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AmenityChip(
                    icon: Icons.money_off_rounded,
                    label: 'Free',
                    isSelected: _accessTypes.contains(AccessType.free),
                    onTap: () {
                      setState(() {
                        if (_accessTypes.contains(AccessType.free)) {
                          _accessTypes.remove(AccessType.free);
                        } else {
                          _accessTypes.add(AccessType.free);
                        }
                      });
                    },
                  ),
                  AmenityChip(
                    icon: Icons.attach_money_rounded,
                    label: 'Paid',
                    isSelected: _accessTypes.contains(AccessType.paid),
                    onTap: () {
                      setState(() {
                        if (_accessTypes.contains(AccessType.paid)) {
                          _accessTypes.remove(AccessType.paid);
                        } else {
                          _accessTypes.add(AccessType.paid);
                        }
                      });
                    },
                  ),
                  AmenityChip(
                    icon: Icons.storefront_outlined,
                    label: 'Customer Only',
                    isSelected: _accessTypes.contains(AccessType.customerOnly),
                    onTap: () {
                      setState(() {
                        if (_accessTypes.contains(AccessType.customerOnly)) {
                          _accessTypes.remove(AccessType.customerOnly);
                        } else {
                          _accessTypes.add(AccessType.customerOnly);
                        }
                      });
                    },
                  ),
                  AmenityChip(
                    icon: Icons.key_outlined,
                    label: 'Key Required',
                    isSelected: _accessTypes.contains(AccessType.keyRequired),
                    onTap: () {
                      setState(() {
                        if (_accessTypes.contains(AccessType.keyRequired)) {
                          _accessTypes.remove(AccessType.keyRequired);
                        } else {
                          _accessTypes.add(AccessType.keyRequired);
                        }
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // 2. Gender / Designation Section
              _buildSectionHeader('Restroom Designation'),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AmenityChip(
                    icon: Icons.female_rounded,
                    label: 'Female',
                    isSelected: _genderTypes.contains(GenderTypeFilter.female),
                    onTap: () {
                      setState(() {
                        if (_genderTypes.contains(GenderTypeFilter.female)) {
                          _genderTypes.remove(GenderTypeFilter.female);
                        } else {
                          _genderTypes.add(GenderTypeFilter.female);
                        }
                      });
                    },
                  ),
                  AmenityChip(
                    icon: Icons.male_rounded,
                    label: 'Male',
                    isSelected: _genderTypes.contains(GenderTypeFilter.male),
                    onTap: () {
                      setState(() {
                        if (_genderTypes.contains(GenderTypeFilter.male)) {
                          _genderTypes.remove(GenderTypeFilter.male);
                        } else {
                          _genderTypes.add(GenderTypeFilter.male);
                        }
                      });
                    },
                  ),
                  AmenityChip(
                    icon: Icons.all_inclusive_rounded,
                    label: 'All-Gender',
                    isSelected: _genderTypes.contains(
                      GenderTypeFilter.allGender,
                    ),
                    onTap: () {
                      setState(() {
                        if (_genderTypes.contains(GenderTypeFilter.allGender)) {
                          _genderTypes.remove(GenderTypeFilter.allGender);
                        } else {
                          _genderTypes.add(GenderTypeFilter.allGender);
                        }
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // 3. Accessibility & Key Amenities Section
              _buildSectionHeader('Accessibility & Amenities'),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AmenityChip(
                    icon: Icons.accessible_rounded,
                    label: 'PWD Accessible',
                    isSelected: _pwdAccessible,
                    onTap: () =>
                        setState(() => _pwdAccessible = !_pwdAccessible),
                  ),
                  AmenityChip(
                    icon: Icons.child_care_rounded,
                    label: 'Baby Changing',
                    isSelected: _babyChanging,
                    onTap: () => setState(() => _babyChanging = !_babyChanging),
                  ),
                  AmenityChip(
                    icon: Icons.water_drop_outlined,
                    label: 'Bidet',
                    isSelected: _bidet,
                    onTap: () => setState(() => _bidet = !_bidet),
                  ),
                  AmenityChip(
                    icon: Icons.receipt_long_outlined,
                    label: 'Toilet Paper',
                    isSelected: _toiletPaper,
                    onTap: () => setState(() => _toiletPaper = !_toiletPaper),
                  ),
                  AmenityChip(
                    icon: Icons.soap_outlined,
                    label: 'Soap',
                    isSelected: _soap,
                    onTap: () => setState(() => _soap = !_soap),
                  ),
                  AmenityChip(
                    icon: Icons.air_rounded,
                    label: 'Hand Dryer',
                    isSelected: _handDryer,
                    onTap: () => setState(() => _handDryer = !_handDryer),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // 4. Quality Signals Section
              _buildSectionHeader('Quality & Freshness'),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AmenityChip(
                    icon: Icons.verified_outlined,
                    label: 'Recently Verified',
                    isSelected: _recentlyVerified,
                    onTap: () =>
                        setState(() => _recentlyVerified = !_recentlyVerified),
                  ),
                  AmenityChip(
                    icon: Icons.star_rounded,
                    label: '4.0+ Stars',
                    isSelected: _minRating >= 4.0,
                    onTap: () {
                      setState(() {
                        _minRating = _minRating >= 4.0 ? 0.0 : 4.0;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xxl),

              // Apply button
              LooPrimaryButton(label: 'Apply Filters', onPressed: _applyLocal),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.titleMedium.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}
