import 'package:flutter/foundation.dart';

import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/restroom_draft.dart';
import 'restroom_id_generator.dart';

/// Presentation state notifier managing user inputs for restroom contribution.
///
/// Responsibilities:
/// - Maintains raw editable UI state.
/// - Builds canonical [RestroomDraft] from raw inputs.
/// - Normalizes and validates data via [RestroomDraft.normalized()] and [RestroomDraft.validate()].
/// - Allocates a stable, idempotent restroom ID upon successful validation.
/// - Prepares [CreateRestroomCommand] in memory without performing persistence.
/// - Preserves data truth: amenities default to [TriStateAmenity.unknown], stalls to null.
class AddRestroomNotifier extends ChangeNotifier {
  final Coordinates coordinates;
  final RestroomIdGenerator _idGenerator;

  // Raw editable form fields
  String _name = '';
  AccessType _accessType = AccessType.free;

  // Indoor context
  String _buildingName = '';
  String _floor = '';
  String _buildingSection = '';
  String _unitOrArea = '';
  String _landmark = '';
  String _directionsNote = '';
  String _countryCode = '';
  String _region = '';
  String _city = '';

  // Access & Pricing
  String _accessInstructions = '';
  String _feeAmountText = '';
  String _feeCurrency = '';

  // Stall options (nullable boolean data-truth)
  bool? _male;
  bool? _female;
  bool? _allGender;

  // Accessibility & Accommodations (Tri-State, defaulting to unknown)
  TriStateAmenity _pwdAccessible = TriStateAmenity.unknown;
  TriStateAmenity _babyChanging = TriStateAmenity.unknown;

  // Hygiene amenities (Tri-State, defaulting to unknown)
  TriStateAmenity _hasBidet = TriStateAmenity.unknown;
  TriStateAmenity _hasToiletPaper = TriStateAmenity.unknown;
  TriStateAmenity _hasSoap = TriStateAmenity.unknown;
  TriStateAmenity _hasHandDryer = TriStateAmenity.unknown;

  // Validation & Preparation state
  List<String> _errors = const [];
  bool _isValidated = false;
  String? _allocatedRestroomId;
  CreateRestroomCommand? _preparedCommand;

  AddRestroomNotifier({
    required this.coordinates,
    RestroomIdGenerator? idGenerator,
    CreateRestroomCommand? initialCommand,
  }) : _idGenerator = idGenerator ?? DefaultRestroomIdGenerator() {
    if (initialCommand != null) {
      final draft = initialCommand.draft;
      _name = draft.name;
      _accessType = draft.accessType;
      _buildingName = draft.buildingName ?? '';
      _floor = draft.floor ?? '';
      _buildingSection = draft.buildingSection ?? '';
      _unitOrArea = draft.unitOrArea ?? '';
      _landmark = draft.landmark ?? '';
      _directionsNote = draft.directionsNote ?? '';
      _countryCode = draft.countryCode ?? '';
      _region = draft.region ?? '';
      _city = draft.city ?? '';
      _accessInstructions = draft.accessInstructions ?? '';
      _feeAmountText = draft.feeAmount != null
          ? draft.feeAmount!.toString()
          : '';
      _feeCurrency = draft.feeCurrency ?? '';
      _male = draft.male;
      _female = draft.female;
      _allGender = draft.allGender;
      _pwdAccessible = draft.pwdAccessible;
      _babyChanging = draft.babyChanging;
      _hasBidet = draft.hasBidet;
      _hasToiletPaper = draft.hasToiletPaper;
      _hasSoap = draft.hasSoap;
      _hasHandDryer = draft.hasHandDryer;
      _allocatedRestroomId = initialCommand.restroomId;
      _preparedCommand = initialCommand;
      _isValidated = true;
    }
  }

  // Getters for form state
  String get name => _name;
  AccessType get accessType => _accessType;
  String get buildingName => _buildingName;
  String get floor => _floor;
  String get buildingSection => _buildingSection;
  String get unitOrArea => _unitOrArea;
  String get landmark => _landmark;
  String get directionsNote => _directionsNote;
  String get countryCode => _countryCode;
  String get region => _region;
  String get city => _city;
  String get accessInstructions => _accessInstructions;
  String get feeAmountText => _feeAmountText;
  String get feeCurrency => _feeCurrency;
  bool? get male => _male;
  bool? get female => _female;
  bool? get allGender => _allGender;
  TriStateAmenity get pwdAccessible => _pwdAccessible;
  TriStateAmenity get babyChanging => _babyChanging;
  TriStateAmenity get hasBidet => _hasBidet;
  TriStateAmenity get hasToiletPaper => _hasToiletPaper;
  TriStateAmenity get hasSoap => _hasSoap;
  TriStateAmenity get hasHandDryer => _hasHandDryer;

  List<String> get errors => _errors;
  bool get isValidated => _isValidated;
  String? get allocatedRestroomId => _allocatedRestroomId;
  CreateRestroomCommand? get preparedCommand => _preparedCommand;

  // Field-level error helpers
  String? get nameError => _findError((e) => e.contains('Facility name'));
  String? get genderStallsError =>
      _findError((e) => e.contains('gender stalls'));
  String? get feeAmountError => _findError((e) => e.contains('fee amount'));
  String? get feeCurrencyError => _findError((e) => e.contains('Fee currency'));
  String? get buildingNameError =>
      _findError((e) => e.contains('Building name'));
  String? get buildingSectionError =>
      _findError((e) => e.contains('Building section'));
  String? get floorError => _findError((e) => e.contains('Floor identifier'));
  String? get unitOrAreaError => _findError((e) => e.contains('Unit or area'));
  String? get landmarkError => _findError((e) => e.contains('Landmark'));
  String? get directionsNoteError =>
      _findError((e) => e.contains('Directions note'));
  String? get accessInstructionsError =>
      _findError((e) => e.contains('Access instructions'));

  String? _findError(bool Function(String) predicate) {
    for (final error in _errors) {
      if (predicate(error)) return error;
    }
    return null;
  }

  // Setters
  void setName(String value) {
    if (_name == value) return;
    _name = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setAccessType(AccessType value) {
    if (_accessType == value) return;
    _accessType = value;
    if (_accessType != AccessType.paid) {
      _feeAmountText = '';
      _feeCurrency = '';
    }
    _clearPreparedCommand();
    notifyListeners();
  }

  void setBuildingName(String value) {
    if (_buildingName == value) return;
    _buildingName = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setFloor(String value) {
    if (_floor == value) return;
    _floor = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setBuildingSection(String value) {
    if (_buildingSection == value) return;
    _buildingSection = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setUnitOrArea(String value) {
    if (_unitOrArea == value) return;
    _unitOrArea = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setLandmark(String value) {
    if (_landmark == value) return;
    _landmark = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setDirectionsNote(String value) {
    if (_directionsNote == value) return;
    _directionsNote = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setCountryCode(String value) {
    if (_countryCode == value) return;
    _countryCode = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setRegion(String value) {
    if (_region == value) return;
    _region = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setCity(String value) {
    if (_city == value) return;
    _city = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setAccessInstructions(String value) {
    if (_accessInstructions == value) return;
    _accessInstructions = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setFeeAmountText(String value) {
    if (_accessType != AccessType.paid) {
      if (_feeAmountText.isEmpty) return;
      _feeAmountText = '';
      _clearPreparedCommand();
      notifyListeners();
      return;
    }
    if (_feeAmountText == value) return;
    _feeAmountText = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setFeeCurrency(String value) {
    if (_accessType != AccessType.paid) {
      if (_feeCurrency.isEmpty) return;
      _feeCurrency = '';
      _clearPreparedCommand();
      notifyListeners();
      return;
    }
    final trimmed = value.trim().toUpperCase();
    if (_feeCurrency == trimmed) return;
    _feeCurrency = trimmed;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setMale(bool? value) {
    if (_male == value) return;
    _male = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setFemale(bool? value) {
    if (_female == value) return;
    _female = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setAllGender(bool? value) {
    if (_allGender == value) return;
    _allGender = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setPwdAccessible(TriStateAmenity value) {
    if (_pwdAccessible == value) return;
    _pwdAccessible = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setBabyChanging(TriStateAmenity value) {
    if (_babyChanging == value) return;
    _babyChanging = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setHasBidet(TriStateAmenity value) {
    if (_hasBidet == value) return;
    _hasBidet = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setHasToiletPaper(TriStateAmenity value) {
    if (_hasToiletPaper == value) return;
    _hasToiletPaper = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setHasSoap(TriStateAmenity value) {
    if (_hasSoap == value) return;
    _hasSoap = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void setHasHandDryer(TriStateAmenity value) {
    if (_hasHandDryer == value) return;
    _hasHandDryer = value;
    _clearPreparedCommand();
    notifyListeners();
  }

  void _clearPreparedCommand() {
    _preparedCommand = null;
  }

  /// Builds raw [RestroomDraft] from the current user inputs.
  RestroomDraft buildDraft() {
    double? parsedFee;
    if (_accessType == AccessType.paid && _feeAmountText.trim().isNotEmpty) {
      parsedFee = double.tryParse(_feeAmountText.trim()) ?? double.nan;
    }

    return RestroomDraft(
      name: _name,
      coordinates: coordinates,
      accessType: _accessType,
      countryCode: _countryCode,
      region: _region,
      city: _city,
      buildingName: _buildingName,
      buildingSection: _buildingSection,
      floor: _floor,
      unitOrArea: _unitOrArea,
      landmark: _landmark,
      directionsNote: _directionsNote,
      accessInstructions: _accessInstructions,
      feeAmount: _accessType == AccessType.paid ? parsedFee : null,
      feeCurrency: _accessType == AccessType.paid ? _feeCurrency : null,
      male: _male,
      female: _female,
      allGender: _allGender,
      pwdAccessible: _pwdAccessible,
      babyChanging: _babyChanging,
      hasBidet: _hasBidet,
      hasToiletPaper: _hasToiletPaper,
      hasSoap: _hasSoap,
      hasHandDryer: _hasHandDryer,
    );
  }

  /// Validates normalized draft inputs and prepares in-memory command with stable ID.
  ///
  /// Returns `true` if validation passes and [preparedCommand] is ready.
  /// Returns `false` if validation fails; allocates zero IDs.
  bool validateAndPrepare() {
    final draft = buildDraft();
    final normalized = draft.normalized();
    final validationErrors = normalized.validate();

    _errors = List<String>.unmodifiable(validationErrors);
    _isValidated = true;

    if (validationErrors.isNotEmpty) {
      _preparedCommand = null;
      notifyListeners();
      return false;
    }

    // Allocate stable restroomId once if not already assigned in this session.
    _allocatedRestroomId ??= _idGenerator.generate();

    _preparedCommand = CreateRestroomCommand(
      restroomId: _allocatedRestroomId!,
      draft: normalized,
    );

    notifyListeners();
    return true;
  }
}
