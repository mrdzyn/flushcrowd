import 'package:equatable/equatable.dart';

import 'coordinates.dart';
import 'enums.dart';

/// Represents a public restroom facility.
/// Strictly excludes any contributor identity / user UIDs to preserve privacy.
class Restroom extends Equatable {
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

  // Access and fee metadata
  final AccessType accessType;
  final double? feeAmount;
  final String? feeCurrency;

  // Amenities and accessibility
  final bool male;
  final bool female;
  final bool allGender;
  final bool pwdAccessible;
  final bool babyChanging;
  final bool hasBidet;
  final bool hasToiletPaper;
  final bool hasSoap;
  final bool hasHandDryer;

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
    this.accessType = AccessType.free,
    this.feeAmount,
    this.feeCurrency,
    this.male = true,
    this.female = true,
    this.allGender = false,
    this.pwdAccessible = false,
    this.babyChanging = false,
    this.hasBidet = false,
    this.hasToiletPaper = true,
    this.hasSoap = true,
    this.hasHandDryer = false,
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
    String? countryCode,
    String? region,
    String? city,
    String? buildingName,
    String? buildingSection,
    String? floor,
    String? unitOrArea,
    String? landmark,
    String? directionsNote,
    AccessType? accessType,
    double? feeAmount,
    String? feeCurrency,
    bool? male,
    bool? female,
    bool? allGender,
    bool? pwdAccessible,
    bool? babyChanging,
    bool? hasBidet,
    bool? hasToiletPaper,
    bool? hasSoap,
    bool? hasHandDryer,
    double? averageRating,
    int? ratingCount,
    int? verificationCount,
    int? negativeVerificationCount,
    DateTime? lastVerifiedAt,
    RestroomStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Restroom(
      id: id ?? this.id,
      name: name ?? this.name,
      coordinates: coordinates ?? this.coordinates,
      geohash: geohash ?? this.geohash,
      countryCode: countryCode ?? this.countryCode,
      region: region ?? this.region,
      city: city ?? this.city,
      buildingName: buildingName ?? this.buildingName,
      buildingSection: buildingSection ?? this.buildingSection,
      floor: floor ?? this.floor,
      unitOrArea: unitOrArea ?? this.unitOrArea,
      landmark: landmark ?? this.landmark,
      directionsNote: directionsNote ?? this.directionsNote,
      accessType: accessType ?? this.accessType,
      feeAmount: feeAmount ?? this.feeAmount,
      feeCurrency: feeCurrency ?? this.feeCurrency,
      male: male ?? this.male,
      female: female ?? this.female,
      allGender: allGender ?? this.allGender,
      pwdAccessible: pwdAccessible ?? this.pwdAccessible,
      babyChanging: babyChanging ?? this.babyChanging,
      hasBidet: hasBidet ?? this.hasBidet,
      hasToiletPaper: hasToiletPaper ?? this.hasToiletPaper,
      hasSoap: hasSoap ?? this.hasSoap,
      hasHandDryer: hasHandDryer ?? this.hasHandDryer,
      averageRating: averageRating ?? this.averageRating,
      ratingCount: ratingCount ?? this.ratingCount,
      verificationCount: verificationCount ?? this.verificationCount,
      negativeVerificationCount:
          negativeVerificationCount ?? this.negativeVerificationCount,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
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
      'countryCode': countryCode,
      'region': region,
      'city': city,
      'buildingName': buildingName,
      'buildingSection': buildingSection,
      'floor': floor,
      'unitOrArea': unitOrArea,
      'landmark': landmark,
      'directionsNote': directionsNote,
      'accessType': accessType.value,
      'feeAmount': feeAmount,
      'feeCurrency': feeCurrency,
      'male': male,
      'female': female,
      'allGender': allGender,
      'pwdAccessible': pwdAccessible,
      'babyChanging': babyChanging,
      'hasBidet': hasBidet,
      'hasToiletPaper': hasToiletPaper,
      'hasSoap': hasSoap,
      'hasHandDryer': hasHandDryer,
      'averageRating': averageRating,
      'ratingCount': ratingCount,
      'verificationCount': verificationCount,
      'negativeVerificationCount': negativeVerificationCount,
      'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
      'status': status.value,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
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
      accessType: AccessType.fromString(map['accessType'] as String?),
      feeAmount: (map['feeAmount'] as num?)?.toDouble(),
      feeCurrency: map['feeCurrency'] as String?,
      male: map['male'] as bool? ?? true,
      female: map['female'] as bool? ?? true,
      allGender: map['allGender'] as bool? ?? false,
      pwdAccessible: map['pwdAccessible'] as bool? ?? false,
      babyChanging: map['babyChanging'] as bool? ?? false,
      hasBidet: map['hasBidet'] as bool? ?? false,
      hasToiletPaper: map['hasToiletPaper'] as bool? ?? true,
      hasSoap: map['hasSoap'] as bool? ?? true,
      hasHandDryer: map['hasHandDryer'] as bool? ?? false,
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
    accessType,
    hasBidet,
    hasToiletPaper,
    pwdAccessible,
    babyChanging,
    averageRating,
    ratingCount,
    status,
  ];
}
