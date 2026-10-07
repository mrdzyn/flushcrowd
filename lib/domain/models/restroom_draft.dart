import 'package:equatable/equatable.dart';

import 'coordinates.dart';
import 'enums.dart';

/// Tri-state representation for user-facing amenity selections.
/// Distinguishes between explicitly verified Yes, explicitly verified No,
/// and Unspecified / Unknown.
enum TriStateAmenity {
  yes,
  no,
  unknown;

  /// Converts this tri-state amenity to a nullable boolean representation:
  /// - [yes] -> `true`
  /// - [no] -> `false`
  /// - [unknown] -> `null`
  bool? toNullableBool() {
    switch (this) {
      case TriStateAmenity.yes:
        return true;
      case TriStateAmenity.no:
        return false;
      case TriStateAmenity.unknown:
        return null;
    }
  }

  /// Reconstitutes a [TriStateAmenity] from a nullable boolean.
  static TriStateAmenity fromNullableBool(bool? value) {
    if (value == null) return TriStateAmenity.unknown;
    return value ? TriStateAmenity.yes : TriStateAmenity.no;
  }
}

/// Domain draft capturing user contribution data before persistence.
///
/// Implements the Phase 2 data-truth contract where amenities default to [TriStateAmenity.unknown]
/// and stalls default to `null`.
class RestroomDraft extends Equatable {
  final String name;
  final Coordinates coordinates;
  final AccessType accessType;

  // Indoor context
  final String? countryCode;
  final String? region;
  final String? city;
  final String? buildingName;
  final String? buildingSection;
  final String? floor;
  final String? unitOrArea;
  final String? landmark;
  final String? directionsNote;

  // Access & Pricing
  final String? accessInstructions;
  final double? feeAmount;
  final String? feeCurrency;

  // Stalls (Nullable)
  final bool? male;
  final bool? female;
  final bool? allGender;

  // Accommodations (Tri-State)
  final TriStateAmenity pwdAccessible;
  final TriStateAmenity babyChanging;

  // Hygiene amenities (Tri-State)
  final TriStateAmenity hasBidet;
  final TriStateAmenity hasToiletPaper;
  final TriStateAmenity hasSoap;
  final TriStateAmenity hasHandDryer;

  const RestroomDraft({
    required this.name,
    required this.coordinates,
    required this.accessType,
    this.countryCode,
    this.region,
    this.city,
    this.buildingName,
    this.buildingSection,
    this.floor,
    this.unitOrArea,
    this.landmark,
    this.directionsNote,
    this.accessInstructions,
    this.feeAmount,
    this.feeCurrency,
    this.male,
    this.female,
    this.allGender,
    this.pwdAccessible = TriStateAmenity.unknown,
    this.babyChanging = TriStateAmenity.unknown,
    this.hasBidet = TriStateAmenity.unknown,
    this.hasToiletPaper = TriStateAmenity.unknown,
    this.hasSoap = TriStateAmenity.unknown,
    this.hasHandDryer = TriStateAmenity.unknown,
  });

  /// Normalizes all strings and fields into canonical domain representations.
  /// Converts whitespace-only strings to null and trims text Unicode-safely.
  RestroomDraft normalized() {
    String? clean(String? val) {
      if (val == null) return null;
      final trimmed = val.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final cleanCurrency = clean(feeCurrency)?.toUpperCase();
    final cleanCountry = clean(countryCode)?.toUpperCase();

    return RestroomDraft(
      name: name.trim(),
      coordinates: coordinates,
      accessType: accessType,
      countryCode: cleanCountry,
      region: clean(region),
      city: clean(city),
      buildingName: clean(buildingName),
      buildingSection: clean(buildingSection),
      floor: clean(floor),
      unitOrArea: clean(unitOrArea),
      landmark: clean(landmark),
      directionsNote: clean(directionsNote),
      accessInstructions: clean(accessInstructions),
      feeAmount: accessType == AccessType.paid ? feeAmount : null,
      feeCurrency: accessType == AccessType.paid ? cleanCurrency : null,
      male: male,
      female: female,
      allGender: allGender,
      pwdAccessible: pwdAccessible,
      babyChanging: babyChanging,
      hasBidet: hasBidet,
      hasToiletPaper: hasToiletPaper,
      hasSoap: hasSoap,
      hasHandDryer: hasHandDryer,
    );
  }

  /// Validates normalized draft fields according to domain rules.
  List<String> validate() {
    final errors = <String>[];
    if (name.isEmpty) errors.add('Facility name is required');
    if (name.length > 100) {
      errors.add('Facility name cannot exceed 100 characters');
    }

    if (coordinates.latitude.isNaN ||
        coordinates.latitude.isInfinite ||
        coordinates.latitude < -90.0 ||
        coordinates.latitude > 90.0) {
      errors.add('Latitude must be a valid number between -90 and 90');
    }
    if (coordinates.longitude.isNaN ||
        coordinates.longitude.isInfinite ||
        coordinates.longitude < -180.0 ||
        coordinates.longitude > 180.0) {
      errors.add('Longitude must be a valid number between -180 and 180');
    }

    if (countryCode != null &&
        (countryCode!.length < 2 || countryCode!.length > 3)) {
      errors.add('Country code must be 2-3 characters');
    }
    if (region != null && region!.length > 100) {
      errors.add('Region cannot exceed 100 characters');
    }
    if (city != null && city!.length > 100) {
      errors.add('City cannot exceed 100 characters');
    }
    if (buildingName != null && buildingName!.length > 100) {
      errors.add('Building name cannot exceed 100 characters');
    }
    if (buildingSection != null && buildingSection!.length > 100) {
      errors.add('Building section cannot exceed 100 characters');
    }
    if (floor != null && floor!.length > 20) {
      errors.add('Floor identifier cannot exceed 20 characters');
    }
    if (unitOrArea != null && unitOrArea!.length > 100) {
      errors.add('Unit or area cannot exceed 100 characters');
    }
    if (landmark != null && landmark!.length > 100) {
      errors.add('Landmark cannot exceed 100 characters');
    }
    if (directionsNote != null && directionsNote!.length > 500) {
      errors.add('Directions note cannot exceed 500 characters');
    }
    if (accessInstructions != null && accessInstructions!.length > 300) {
      errors.add('Access instructions cannot exceed 300 characters');
    }

    if (accessType == AccessType.paid) {
      if (feeAmount == null ||
          feeAmount!.isNaN ||
          feeAmount! < 0 ||
          feeAmount! > 1000000) {
        errors.add(
          'Paid restrooms require a valid fee amount between 0 and 1,000,000',
        );
      }
      if (feeCurrency == null ||
          feeCurrency!.length != 3 ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(feeCurrency!)) {
        errors.add(
          'Fee currency must be a valid 3-letter uppercase code (e.g., USD)',
        );
      }
    }

    // Gender stall configuration: either at least one is explicitly true, or all are null (unknown)
    final hasExplicitGender =
        (male == true) || (female == true) || (allGender == true);
    final allGenderNull =
        (male == null) && (female == null) && (allGender == null);
    if (!hasExplicitGender && !allGenderNull) {
      errors.add('Select applicable gender stalls or leave all unspecified');
    }

    return errors;
  }

  @override
  List<Object?> get props => [
    name,
    coordinates,
    accessType,
    countryCode,
    region,
    city,
    buildingName,
    buildingSection,
    floor,
    unitOrArea,
    landmark,
    directionsNote,
    accessInstructions,
    feeAmount,
    feeCurrency,
    male,
    female,
    allGender,
    pwdAccessible,
    babyChanging,
    hasBidet,
    hasToiletPaper,
    hasSoap,
    hasHandDryer,
  ];
}
