import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/enums.dart';
import '../components/buttons/loo_primary_button.dart';
import '../components/inputs/tri_state_amenity_selector.dart';
import '../state/add_restroom_notifier.dart';
import '../state/restroom_id_generator.dart';

/// Phase 2 Milestone P2.3: Restroom Contribution Form Screen.
///
/// Features:
/// - Facility identification (Name, Access Type) with compact read-only coordinate summary.
/// - Indoor context & directions (Building, Floor, Wing, Landmark, Directions note).
/// - Accessibility and gender stall configuration (Truthful nullable booleans and TriState).
/// - Hygiene and amenities selectors (TriState).
/// - Access instructions and conditional paid fee configuration.
/// - In-memory normalization, validation, and stable ID allocation via [AddRestroomNotifier].
/// - Zero-persistence milestone: returns prepared [CreateRestroomCommand] without Firestore writes.
class AddRestroomFormScreen extends StatefulWidget {
  final Coordinates coordinates;
  final RestroomIdGenerator? idGenerator;
  final CreateRestroomCommand? initialCommand;

  const AddRestroomFormScreen({
    super.key,
    required this.coordinates,
    this.idGenerator,
    this.initialCommand,
  });

  /// Factory helper creating a typed route returning [CreateRestroomCommand] on valid continuation.
  static MaterialPageRoute<CreateRestroomCommand> route({
    required Coordinates coordinates,
    RestroomIdGenerator? idGenerator,
    CreateRestroomCommand? initialCommand,
  }) {
    return MaterialPageRoute<CreateRestroomCommand>(
      builder: (context) => AddRestroomFormScreen(
        coordinates: coordinates,
        idGenerator: idGenerator,
        initialCommand: initialCommand,
      ),
    );
  }

  @override
  State<AddRestroomFormScreen> createState() => _AddRestroomFormScreenState();
}

class _AddRestroomFormScreenState extends State<AddRestroomFormScreen> {
  late final AddRestroomNotifier _notifier;

  late final TextEditingController _nameController;
  late final TextEditingController _buildingNameController;
  late final TextEditingController _floorController;
  late final TextEditingController _buildingSectionController;
  late final TextEditingController _unitOrAreaController;
  late final TextEditingController _landmarkController;
  late final TextEditingController _directionsNoteController;
  late final TextEditingController _accessInstructionsController;
  late final TextEditingController _feeAmountController;
  late final TextEditingController _feeCurrencyController;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _notifier = AddRestroomNotifier(
      coordinates: widget.coordinates,
      idGenerator: widget.idGenerator,
      initialCommand: widget.initialCommand,
    );

    final draft = widget.initialCommand?.draft;
    _nameController = TextEditingController(text: draft?.name ?? '');
    _buildingNameController = TextEditingController(
      text: draft?.buildingName ?? '',
    );
    _floorController = TextEditingController(text: draft?.floor ?? '');
    _buildingSectionController = TextEditingController(
      text: draft?.buildingSection ?? '',
    );
    _unitOrAreaController = TextEditingController(
      text: draft?.unitOrArea ?? '',
    );
    _landmarkController = TextEditingController(text: draft?.landmark ?? '');
    _directionsNoteController = TextEditingController(
      text: draft?.directionsNote ?? '',
    );
    _accessInstructionsController = TextEditingController(
      text: draft?.accessInstructions ?? '',
    );
    _feeAmountController = TextEditingController(
      text: draft?.feeAmount != null ? draft!.feeAmount!.toString() : '',
    );
    _feeCurrencyController = TextEditingController(
      text: draft?.feeCurrency ?? '',
    );

    _nameController.addListener(() => _notifier.setName(_nameController.text));
    _buildingNameController.addListener(
      () => _notifier.setBuildingName(_buildingNameController.text),
    );
    _floorController.addListener(
      () => _notifier.setFloor(_floorController.text),
    );
    _buildingSectionController.addListener(
      () => _notifier.setBuildingSection(_buildingSectionController.text),
    );
    _unitOrAreaController.addListener(
      () => _notifier.setUnitOrArea(_unitOrAreaController.text),
    );
    _landmarkController.addListener(
      () => _notifier.setLandmark(_landmarkController.text),
    );
    _directionsNoteController.addListener(
      () => _notifier.setDirectionsNote(_directionsNoteController.text),
    );
    _accessInstructionsController.addListener(
      () => _notifier.setAccessInstructions(_accessInstructionsController.text),
    );
    _feeAmountController.addListener(
      () => _notifier.setFeeAmountText(_feeAmountController.text),
    );
    _feeCurrencyController.addListener(
      () => _notifier.setFeeCurrency(_feeCurrencyController.text),
    );
    _notifier.addListener(_syncFeeControllers);
  }

  void _syncFeeControllers() {
    if (_notifier.accessType != AccessType.paid) {
      if (_feeAmountController.text.isNotEmpty) {
        _feeAmountController.clear();
      }
      if (_feeCurrencyController.text.isNotEmpty) {
        _feeCurrencyController.clear();
      }
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_syncFeeControllers);
    _nameController.dispose();
    _buildingNameController.dispose();
    _floorController.dispose();
    _buildingSectionController.dispose();
    _unitOrAreaController.dispose();
    _landmarkController.dispose();
    _directionsNoteController.dispose();
    _accessInstructionsController.dispose();
    _feeAmountController.dispose();
    _feeCurrencyController.dispose();
    _scrollController.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _handleContinue() {
    final success = _notifier.validateAndPrepare();
    if (success && _notifier.preparedCommand != null) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(_notifier.preparedCommand);
      }
    } else {
      // Scroll smoothly toward top so user sees primary error messages
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _notifier,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Add Restroom'),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLocationSummaryCard(),
                        const SizedBox(height: AppSpacing.md),
                        if (_notifier.errors.isNotEmpty) ...[
                          _buildErrorSummaryBanner(),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        _buildFacilityIdentificationCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildIndoorContextCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildAccessibilityAndStallsCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildHygieneAmenitiesCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildAccessInstructionsAndPricingCard(),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
                _buildBottomActionBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocationSummaryCard() {
    final coords = widget.coordinates;
    final latText = coords.latitude.toStringAsFixed(5);
    final lngText = coords.longitude.toStringAsFixed(5);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: AppRadii.lgBorder,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pin_drop_rounded,
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected Entrance Location',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '$latText, $lngText',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSummaryBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadii.lgBorder,
        border: Border.all(color: AppColors.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Please fix the following errors:',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final error in _notifier.errors)
            Padding(
              padding: const EdgeInsets.only(left: 28.0, top: 2.0),
              child: Text(
                '• $error',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onErrorContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFacilityIdentificationCard() {
    return _FormCard(
      title: 'Facility Identification',
      icon: Icons.storefront_rounded,
      children: [
        TextFormField(
          controller: _nameController,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: 'Facility Name *',
            hintText:
                'e.g., Central Station Restroom, Ground Floor Cafe Restroom',
            errorText: _notifier.nameError,
            border: const OutlineInputBorder(borderRadius: AppRadii.mdBorder),
            helperText: 'A recognizable name for this restroom facility',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<AccessType>(
          initialValue: _notifier.accessType,
          decoration: const InputDecoration(
            labelText: 'Access Type',
            border: OutlineInputBorder(borderRadius: AppRadii.mdBorder),
          ),
          items: const [
            DropdownMenuItem(
              value: AccessType.free,
              child: Text('Free (Public Access)'),
            ),
            DropdownMenuItem(
              value: AccessType.paid,
              child: Text('Paid (Fee Required)'),
            ),
            DropdownMenuItem(
              value: AccessType.customerOnly,
              child: Text('Customer Only'),
            ),
            DropdownMenuItem(
              value: AccessType.keyRequired,
              child: Text('Key Required'),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              _notifier.setAccessType(val);
              if (val != AccessType.paid) {
                if (_feeAmountController.text.isNotEmpty) {
                  _feeAmountController.clear();
                }
                if (_feeCurrencyController.text.isNotEmpty) {
                  _feeCurrencyController.clear();
                }
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildIndoorContextCard() {
    return _FormCard(
      title: 'Indoor Context & Directions',
      icon: Icons.directions_walk_rounded,
      subtitle: 'Help community members locate the restroom inside buildings, transit hubs, or malls.',
      children: [
        TextFormField(
          controller: _buildingNameController,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: 'Building Name',
            hintText: 'e.g., Terminal 3, Main Mall, Student Union',
            errorText: _notifier.buildingNameError,
            border: const OutlineInputBorder(borderRadius: AppRadii.mdBorder),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _floorController,
                maxLength: 20,
                decoration: InputDecoration(
                  labelText: 'Floor',
                  hintText: 'e.g., 2F, B1, Ground',
                  errorText: _notifier.floorError,
                  border: const OutlineInputBorder(
                    borderRadius: AppRadii.mdBorder,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _buildingSectionController,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: 'Section / Wing',
                  hintText: 'e.g., East Wing, Food Court',
                  errorText: _notifier.buildingSectionError,
                  border: const OutlineInputBorder(
                    borderRadius: AppRadii.mdBorder,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _unitOrAreaController,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: 'Unit or Specific Area',
            hintText: 'e.g., Next to Gate 14, Near elevators',
            errorText: _notifier.unitOrAreaError,
            border: const OutlineInputBorder(borderRadius: AppRadii.mdBorder),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _landmarkController,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: 'Nearest Landmark',
            hintText: 'e.g., Behind Starbucks, Next to escalator',
            errorText: _notifier.landmarkError,
            border: const OutlineInputBorder(borderRadius: AppRadii.mdBorder),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _directionsNoteController,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Indoor Directions Note',
            hintText: 'e.g., Enter through main entrance, turn right past the food court, located down hallway on the left.',
            errorText: _notifier.directionsNoteError,
            border: const OutlineInputBorder(borderRadius: AppRadii.mdBorder),
          ),
        ),
      ],
    );
  }

  Widget _buildAccessibilityAndStallsCard() {
    return _FormCard(
      title: 'Accessibility & Stalls',
      icon: Icons.accessible_rounded,
      children: [
        TriStateAmenitySelector(
          title: 'PWD / Wheelchair Accessible',
          subtitle: 'Step-free access, grab bars, wide entrance',
          value: _notifier.pwdAccessible,
          onChanged: _notifier.setPwdAccessible,
          icon: Icons.accessible_rounded,
        ),
        const Divider(height: AppSpacing.xl),
        TriStateAmenitySelector(
          title: 'Baby Changing Station',
          subtitle: 'Fold-down table or designated baby care facility',
          value: _notifier.babyChanging,
          onChanged: _notifier.setBabyChanging,
          icon: Icons.child_care_rounded,
        ),
        const Divider(height: AppSpacing.xl),
        Text(
          'Gender Stall Configuration',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Select applicable stalls or leave all unspecified if unknown.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (_notifier.genderStallsError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _notifier.genderStallsError!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TriStateAmenitySelector.forNullableBool(
          title: 'Male Stalls',
          value: _notifier.male,
          onChanged: _notifier.setMale,
          icon: Icons.man_rounded,
        ),
        const SizedBox(height: AppSpacing.md),
        TriStateAmenitySelector.forNullableBool(
          title: 'Female Stalls',
          value: _notifier.female,
          onChanged: _notifier.setFemale,
          icon: Icons.woman_rounded,
        ),
        const SizedBox(height: AppSpacing.md),
        TriStateAmenitySelector.forNullableBool(
          title: 'All-Gender / Unisex Stalls',
          value: _notifier.allGender,
          onChanged: _notifier.setAllGender,
          icon: Icons.wc_rounded,
        ),
      ],
    );
  }

  Widget _buildHygieneAmenitiesCard() {
    return _FormCard(
      title: 'Hygiene & Amenities',
      icon: Icons.sanitizer_rounded,
      children: [
        TriStateAmenitySelector(
          title: 'Bidet Available',
          subtitle: 'Handheld bidet sprayer or electronic washlet',
          value: _notifier.hasBidet,
          onChanged: _notifier.setHasBidet,
          icon: Icons.water_drop_rounded,
        ),
        const Divider(height: AppSpacing.xl),
        TriStateAmenitySelector(
          title: 'Toilet Paper Provided',
          subtitle: 'Stocked rolls or dispenser in stalls',
          value: _notifier.hasToiletPaper,
          onChanged: _notifier.setHasToiletPaper,
          icon: Icons.layers_rounded,
        ),
        const Divider(height: AppSpacing.xl),
        TriStateAmenitySelector(
          title: 'Handwashing Soap Available',
          subtitle: 'Liquid soap, dispenser, or bar soap',
          value: _notifier.hasSoap,
          onChanged: _notifier.setHasSoap,
          icon: Icons.clean_hands_rounded,
        ),
        const Divider(height: AppSpacing.xl),
        TriStateAmenitySelector(
          title: 'Hand Dryer Available',
          subtitle: 'Electric warm air or jet hand dryer only',
          value: _notifier.hasHandDryer,
          onChanged: _notifier.setHasHandDryer,
          icon: Icons.air_rounded,
        ),
      ],
    );
  }

  Widget _buildAccessInstructionsAndPricingCard() {
    final isPaid = _notifier.accessType == AccessType.paid;

    return _FormCard(
      title: 'Access & Pricing',
      icon: Icons.payments_rounded,
      children: [
        TextFormField(
          controller: _accessInstructionsController,
          maxLength: 300,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Access Instructions',
            hintText: 'e.g., Ask barista for key, door code printed on receipt',
            errorText: _notifier.accessInstructionsError,
            border: const OutlineInputBorder(borderRadius: AppRadii.mdBorder),
            helperText: 'Special instructions for unlocking or accessing',
          ),
        ),
        if (isPaid) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _feeAmountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Fee Amount *',
                    hintText: 'e.g., 10.00',
                    errorText: _notifier.feeAmountError,
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.mdBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _feeCurrencyController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: InputDecoration(
                    labelText: 'Currency *',
                    hintText: 'PHP, USD',
                    errorText: _notifier.feeCurrencyError,
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.mdBorder,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: LooPrimaryButton(
        label: 'Continue',
        icon: Icons.arrow_forward_rounded,
        onPressed: _handleContinue,
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;

  const _FormCard({
    required this.title,
    required this.icon,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lgBorder,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}
