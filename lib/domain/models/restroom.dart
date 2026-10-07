import 'package:equatable/equatable.dart';

import 'coordinates.dart';
import 'enums.dart';

/// Represents a public restroom facility.
/// Strictly excludes any contributor identity / user UIDs to preserve privacy.
///
/// Under the Phase 2 data-truth contract, amenity and stall properties use
/// nullable booleans (`bool?`), where `true` indicates verified presence,
/// `false` indicates verified absence, and `null` indicates unknown/unspecified.
class Restroom extends Equatable {
  static const _unset = Object();

  final String id;
  final String name;
  final Coordinates coordinates;
  final String geohash;
  final String? countryCode;
  final String? region;
  final String? city;

  // First-class indoor directions metadata
  final String? buildingName;
  final String? buildingSection;
  final String? floor;
  final String? unitOrArea;
  final String? landmark;
  final String? directionsNote;

  // Access, instructions, and fee metadata
  final String? accessInstructions;
  final AccessType accessType;
  final double? feeAmount;
  final String? feeCurrency;

  // Stalls (Nullable)
  final bool? male;
  final bool? female;
  final bool? allGender;

  // Amenities and accessibility (Nullable)
  final bool? pwdAccessible;
  final bool? babyChanging;
  final bool? hasBidet;
  final bool? hasToiletPaper;
  final bool? hasSoap;
  final bool? hasHandDryer;

  // Trusted aggregate signals (managed on backend / aggregates)
  final double averageRating;
  final int ratingCount;
  final int verificationCount;
  final int negativeVerificationCount;
  final DateTime? lastVerifiedAt;

  final RestroomStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Restroom({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.geohash,
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
    this.accessType = AccessType.free,
    this.feeAmount,
    this.feeCurrency,
    this.male,
    this.female,
    this.allGender,
    this.pwdAccessible,
    this.babyChanging,
    this.hasBidet,
    this.hasToiletPaper,
    this.hasSoap,
    this.hasHandDryer,
    this.averageRating = 0.0,
    this.ratingCount = 0,
    this.verificationCount = 0,
    this.negativeVerificationCount = 0,
    this.lastVerifiedAt,
    this.status = RestroomStatus.active,
    this.createdAt,
    this.updatedAt,
  });

  Restroom copyWith({
    String? id,
    String? name,
    Coordinates? coordinates,
    String? geohash,
    Object? countryCode = _unset,
    Object? region = _unset,
    Object? city = _unset,
    Object? buildingName = _unset,
    Object? buildingSection = _unset,
    Object? floor = _unset,
    Object? unitOrArea = _unset,
    Object? landmark = _unset,
    Object? directionsNote = _unset,
    Object? accessInstructions = _unset,
    AccessType? accessType,
    Object? feeAmount = _unset,
    Object? feeCurrency = _unset,
    Object? male = _unset,
    Object? female = _unset,
    Object? allGender = _unset,
    Object? pwdAccessible = _unset,
    Object? babyChanging = _unset,
    Object? hasBidet = _unset,
    Object? hasToiletPaper = _unset,
    Object? hasSoap = _unset,
    Object? hasHandDryer = _unset,
    double? averageRating,
    int? ratingCount,
    int? verificationCount,
    int? negativeVerificationCount,
    Object? lastVerifiedAt = _unset,
    RestroomStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Restroom(
      id: id ?? this.id,
      name: name ?? this.name,
      coordinates: coordinates ?? this.coordinates,
      geohash: geohash ?? this.geohash,
      countryCode: identical(countryCode, _unset)
          ? this.countryCode
          : countryCode as String?,
      region: identical(region, _unset) ? this.region : region as String?,
      city: identical(city, _unset) ? this.city : city as String?,
      buildingName: identical(buildingName, _unset)
          ? this.buildingName
          : buildingName as String?,
      buildingSection: identical(buildingSection, _unset)
          ? this.buildingSection
          : buildingSection as String?,
      floor: identical(floor, _unset) ? this.floor : floor as String?,
      unitOrArea: identical(unitOrArea, _unset)
          ? this.unitOrArea
          : unitOrArea as String?,
      landmark: identical(landmark, _unset)
          ? this.landmark
          : landmark as String?,
      directionsNote: identical(directionsNote, _unset)
          ? this.directionsNote
          : directionsNote as String?,
      accessInstructions: identical(accessInstructions, _unset)
          ? this.accessInstructions
          : accessInstructions as String?,
      accessType: accessType ?? this.accessType,
      feeAmount: identical(feeAmount, _unset)
          ? this.feeAmount
          : feeAmount as double?,
      feeCurrency: identical(feeCurrency, _unset)
          ? this.feeCurrency
          : feeCurrency as String?,
      male: identical(male, _unset) ? this.male : male as bool?,
      female: identical(female, _unset) ? this.female : female as bool?,
      allGender: identical(allGender, _unset)
          ? this.allGender
          : allGender as bool?,
      pwdAccessible: identical(pwdAccessible, _unset)
          ? this.pwdAccessible
          : pwdAccessible as bool?,
      babyChanging: identical(babyChanging, _unset)
          ? this.babyChanging
          : babyChanging as bool?,
      hasBidet: identical(hasBidet, _unset) ? this.hasBidet : hasBidet as bool?,
      hasToiletPaper: identical(hasToiletPaper, _unset)
          ? this.hasToiletPaper
          : hasToiletPaper as bool?,
      hasSoap: identical(hasSoap, _unset) ? this.hasSoap : hasSoap as bool?,
      hasHandDryer: identical(hasHandDryer, _unset)
          ? this.hasHandDryer
          : hasHandDryer as bool?,
      averageRating: averageRating ?? this.averageRating,
      ratingCount: ratingCount ?? this.ratingCount,
      verificationCount: verificationCount ?? this.verificationCount,
      negativeVerificationCount:
          negativeVerificationCount ?? this.negativeVerificationCount,
      lastVerifiedAt: identical(lastVerifiedAt, _unset)
          ? this.lastVerifiedAt
          : lastVerifiedAt as DateTime?,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': coordinates.latitude,
      'longitude': coordinates.longitude,
      'geohash': geohash,
      if (countryCode != null) 'countryCode': countryCode,
      if (region != null) 'region': region,
      if (city != null) 'city': city,
      if (buildingName != null) 'buildingName': buildingName,
      if (buildingSection != null) 'buildingSection': buildingSection,
      if (floor != null) 'floor': floor,
      if (unitOrArea != null) 'unitOrArea': unitOrArea,
      if (landmark != null) 'landmark': landmark,
      if (directionsNote != null) 'directionsNote': directionsNote,
      if (accessInstructions != null) 'accessInstructions': accessInstructions,
      'accessType': accessType.value,
      if (feeAmount != null) 'feeAmount': feeAmount,
      if (feeCurrency != null) 'feeCurrency': feeCurrency,
      if (male != null) 'male': male,
      if (female != null) 'female': female,
      if (allGender != null) 'allGender': allGender,
      if (pwdAccessible != null) 'pwdAccessible': pwdAccessible,
      if (babyChanging != null) 'babyChanging': babyChanging,
      if (hasBidet != null) 'hasBidet': hasBidet,
      if (hasToiletPaper != null) 'hasToiletPaper': hasToiletPaper,
      if (hasSoap != null) 'hasSoap': hasSoap,
      if (hasHandDryer != null) 'hasHandDryer': hasHandDryer,
      'averageRating': averageRating,
      'ratingCount': ratingCount,
      'verificationCount': verificationCount,
      'negativeVerificationCount': negativeVerificationCount,
      if (lastVerifiedAt != null)
        'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
      'status': status.value,
      if (createdAt != null) 'createdAt': createdAt?.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory Restroom.fromMap(Map<String, dynamic> map, {String? documentId}) {
    final id = documentId ?? (map['id'] as String? ?? '');
    final lat = (map['latitude'] as num).toDouble();
    final lng = (map['longitude'] as num).toDouble();
    final coords = Coordinates(latitude: lat, longitude: lng);

    return Restroom(
      id: id,
      name: map['name'] as String? ?? '',
      coordinates: coords,
      geohash: map['geohash'] as String? ?? '',
      countryCode: map['countryCode'] as String?,
      region: map['region'] as String?,
      city: map['city'] as String?,
      buildingName: map['buildingName'] as String?,
      buildingSection: map['buildingSection'] as String?,
      floor: map['floor'] as String?,
      unitOrArea: map['unitOrArea'] as String?,
      landmark: map['landmark'] as String?,
      directionsNote: map['directionsNote'] as String?,
      accessInstructions: map['accessInstructions'] as String?,
      accessType: AccessType.fromString(map['accessType'] as String?),
      feeAmount: (map['feeAmount'] as num?)?.toDouble(),
      feeCurrency: map['feeCurrency'] as String?,
      male: map['male'] as bool?,
      female: map['female'] as bool?,
      allGender: map['allGender'] as bool?,
      pwdAccessible: map['pwdAccessible'] as bool?,
      babyChanging: map['babyChanging'] as bool?,
      hasBidet: map['hasBidet'] as bool?,
      hasToiletPaper: map['hasToiletPaper'] as bool?,
      hasSoap: map['hasSoap'] as bool?,
      hasHandDryer: map['hasHandDryer'] as bool?,
      averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (map['ratingCount'] as num?)?.toInt() ?? 0,
      verificationCount: (map['verificationCount'] as num?)?.toInt() ?? 0,
      negativeVerificationCount:
          (map['negativeVerificationCount'] as num?)?.toInt() ?? 0,
      lastVerifiedAt: map['lastVerifiedAt'] != null
          ? DateTime.tryParse(map['lastVerifiedAt'] as String)
          : null,
      status: RestroomStatus.fromString(map['status'] as String?),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    coordinates,
    geohash,
    buildingName,
    floor,
    accessInstructions,
    accessType,
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
    averageRating,
    ratingCount,
    status,
  ];
}
