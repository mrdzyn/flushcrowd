import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/coordinates.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/rating.dart';
import '../../../domain/models/report.dart';
import '../../../domain/models/restroom.dart';
import '../../../domain/models/verification.dart';

/// Utilities for bi-directional conversion between Dart domain models
/// and Cloud Firestore document representations with native [Timestamp] types.
class FirestoreCodec {
  FirestoreCodec._();

  /// Converts a [DateTime] into a Cloud Firestore [Timestamp].
  /// Returns null if [dateTime] is null.
  static Timestamp? dateTimeToTimestamp(DateTime? dateTime) {
    if (dateTime == null) return null;
    return Timestamp.fromDate(dateTime.toUtc());
  }

  /// Converts a Firestore [Timestamp] into a standard Dart [DateTime] in UTC.
  ///
  /// Throws a [FormatException] if [value] is non-null and not a [Timestamp],
  /// preventing silent acceptance of malformed types (e.g. raw Strings or numbers).
  static DateTime? timestampToDateTime(
    dynamic value, {
    String fieldName = 'timestamp',
  }) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    throw FormatException(
      'Invalid Firestore timestamp for "$fieldName": expected Timestamp or null, '
      'got ${value.runtimeType} ($value)',
    );
  }
}

/// Firestore document codec for [Restroom].
/// Ensures strict type conversion and prevents contributor UIDs in public documents.
class RestroomFirestoreCodec {
  RestroomFirestoreCodec._();

  /// Converts a [Restroom] domain model into a Firestore document map.
  /// Converts [DateTime] fields to Firestore [Timestamp] objects.
  static Map<String, dynamic> toFirestore(Restroom restroom) {
    final map = <String, dynamic>{
      if (restroom.id.isNotEmpty) 'id': restroom.id,
      'name': restroom.name,
      'latitude': restroom.coordinates.latitude,
      'longitude': restroom.coordinates.longitude,
      'geohash': restroom.geohash,
      if (restroom.countryCode != null) 'countryCode': restroom.countryCode,
      if (restroom.region != null) 'region': restroom.region,
      if (restroom.city != null) 'city': restroom.city,
      if (restroom.buildingName != null) 'buildingName': restroom.buildingName,
      if (restroom.buildingSection != null)
        'buildingSection': restroom.buildingSection,
      if (restroom.floor != null) 'floor': restroom.floor,
      if (restroom.unitOrArea != null) 'unitOrArea': restroom.unitOrArea,
      if (restroom.landmark != null) 'landmark': restroom.landmark,
      if (restroom.directionsNote != null)
        'directionsNote': restroom.directionsNote,
      'accessType': restroom.accessType.value,
      if (restroom.feeAmount != null) 'feeAmount': restroom.feeAmount,
      if (restroom.feeCurrency != null) 'feeCurrency': restroom.feeCurrency,
      'male': restroom.male,
      'female': restroom.female,
      'allGender': restroom.allGender,
      'pwdAccessible': restroom.pwdAccessible,
      'babyChanging': restroom.babyChanging,
      'hasBidet': restroom.hasBidet,
      'hasToiletPaper': restroom.hasToiletPaper,
      'hasSoap': restroom.hasSoap,
      'hasHandDryer': restroom.hasHandDryer,
      'averageRating': restroom.averageRating,
      'ratingCount': restroom.ratingCount,
      'verificationCount': restroom.verificationCount,
      'negativeVerificationCount': restroom.negativeVerificationCount,
      if (restroom.lastVerifiedAt != null)
        'lastVerifiedAt': FirestoreCodec.dateTimeToTimestamp(
          restroom.lastVerifiedAt,
        ),
      'status': restroom.status.value,
      if (restroom.createdAt != null)
        'createdAt': FirestoreCodec.dateTimeToTimestamp(restroom.createdAt),
      if (restroom.updatedAt != null)
        'updatedAt': FirestoreCodec.dateTimeToTimestamp(restroom.updatedAt),
    };

    // Strict privacy invariant: Never allow contributor UIDs in public document maps
    assert(
      !map.containsKey('createdByUid'),
      'Public document cannot contain createdByUid',
    );
    assert(
      !map.containsKey('userUid'),
      'Public document cannot contain userUid',
    );
    assert(!map.containsKey('userId'), 'Public document cannot contain userId');
    assert(
      !map.containsKey('authorUid'),
      'Public document cannot contain authorUid',
    );
    assert(!map.containsKey('uid'), 'Public document cannot contain uid');

    return map;
  }

  /// Deserializes a Firestore document map into a [Restroom] domain model.
  /// Strictly expects [Timestamp] values for date fields.
  static Restroom fromFirestore(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final id = documentId ?? (data['id'] as String? ?? '');
    final lat = (data['latitude'] as num).toDouble();
    final lng = (data['longitude'] as num).toDouble();
    final coords = Coordinates(latitude: lat, longitude: lng);

    return Restroom(
      id: id,
      name: data['name'] as String? ?? '',
      coordinates: coords,
      geohash: data['geohash'] as String? ?? '',
      countryCode: data['countryCode'] as String?,
      region: data['region'] as String?,
      city: data['city'] as String?,
      buildingName: data['buildingName'] as String?,
      buildingSection: data['buildingSection'] as String?,
      floor: data['floor'] as String?,
      unitOrArea: data['unitOrArea'] as String?,
      landmark: data['landmark'] as String?,
      directionsNote: data['directionsNote'] as String?,
      accessType: AccessType.fromString(data['accessType'] as String?),
      feeAmount: (data['feeAmount'] as num?)?.toDouble(),
      feeCurrency: data['feeCurrency'] as String?,
      male: data['male'] as bool? ?? true,
      female: data['female'] as bool? ?? true,
      allGender: data['allGender'] as bool? ?? false,
      pwdAccessible: data['pwdAccessible'] as bool? ?? false,
      babyChanging: data['babyChanging'] as bool? ?? false,
      hasBidet: data['hasBidet'] as bool? ?? false,
      hasToiletPaper: data['hasToiletPaper'] as bool? ?? true,
      hasSoap: data['hasSoap'] as bool? ?? true,
      hasHandDryer: data['hasHandDryer'] as bool? ?? false,
      averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      verificationCount: (data['verificationCount'] as num?)?.toInt() ?? 0,
      negativeVerificationCount:
          (data['negativeVerificationCount'] as num?)?.toInt() ?? 0,
      lastVerifiedAt: FirestoreCodec.timestampToDateTime(
        data['lastVerifiedAt'],
        fieldName: 'lastVerifiedAt',
      ),
      status: RestroomStatus.fromString(data['status'] as String?),
      createdAt: FirestoreCodec.timestampToDateTime(
        data['createdAt'],
        fieldName: 'createdAt',
      ),
      updatedAt: FirestoreCodec.timestampToDateTime(
        data['updatedAt'],
        fieldName: 'updatedAt',
      ),
    );
  }
}

/// Firestore document codec for [Rating].
class RatingFirestoreCodec {
  RatingFirestoreCodec._();

  static Map<String, dynamic> toFirestore(Rating rating) {
    final map = <String, dynamic>{
      if (rating.id.isNotEmpty) 'id': rating.id,
      'restroomId': rating.restroomId,
      'overall': rating.overall,
      if (rating.cleanliness != null) 'cleanliness': rating.cleanliness,
      if (rating.supplies != null) 'supplies': rating.supplies,
      if (rating.accessibility != null) 'accessibility': rating.accessibility,
      if (rating.privacy != null) 'privacy': rating.privacy,
      if (rating.comment != null) 'comment': rating.comment,
      if (rating.createdAt != null)
        'createdAt': FirestoreCodec.dateTimeToTimestamp(rating.createdAt),
      if (rating.updatedAt != null)
        'updatedAt': FirestoreCodec.dateTimeToTimestamp(rating.updatedAt),
    };

    assert(
      !map.containsKey('createdByUid'),
      'Public rating cannot contain createdByUid',
    );
    assert(!map.containsKey('userUid'), 'Public rating cannot contain userUid');
    assert(!map.containsKey('userId'), 'Public rating cannot contain userId');
    assert(
      !map.containsKey('authorUid'),
      'Public rating cannot contain authorUid',
    );
    assert(!map.containsKey('uid'), 'Public rating cannot contain uid');

    return map;
  }

  static Rating fromFirestore(Map<String, dynamic> data, {String? documentId}) {
    return Rating(
      id: documentId ?? (data['id'] as String? ?? ''),
      restroomId: data['restroomId'] as String? ?? '',
      overall: (data['overall'] as num?)?.toDouble() ?? 0.0,
      cleanliness: (data['cleanliness'] as num?)?.toDouble(),
      supplies: (data['supplies'] as num?)?.toDouble(),
      accessibility: (data['accessibility'] as num?)?.toDouble(),
      privacy: (data['privacy'] as num?)?.toDouble(),
      comment: data['comment'] as String?,
      createdAt: FirestoreCodec.timestampToDateTime(
        data['createdAt'],
        fieldName: 'createdAt',
      ),
      updatedAt: FirestoreCodec.timestampToDateTime(
        data['updatedAt'],
        fieldName: 'updatedAt',
      ),
    );
  }
}

/// Firestore document codec for [RestroomReport].
class RestroomReportFirestoreCodec {
  RestroomReportFirestoreCodec._();

  static Map<String, dynamic> toFirestore(
    RestroomReport report, {
    String? userUid,
  }) {
    return <String, dynamic>{
      if (report.id.isNotEmpty) 'id': report.id,
      'restroomId': report.restroomId,
      'reason': report.reason.value,
      if (report.notes != null) 'notes': report.notes,
      'status': report.status.value,
      'userUid': ?userUid,
      if (report.createdAt != null)
        'createdAt': FirestoreCodec.dateTimeToTimestamp(report.createdAt),
      if (report.resolvedAt != null)
        'resolvedAt': FirestoreCodec.dateTimeToTimestamp(report.resolvedAt),
    };
  }

  static RestroomReport fromFirestore(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    return RestroomReport(
      id: documentId ?? (data['id'] as String? ?? ''),
      restroomId: data['restroomId'] as String? ?? '',
      reason: ReportReason.fromString(data['reason'] as String?),
      notes: data['notes'] as String?,
      status: ReportStatus.fromString(data['status'] as String?),
      createdAt: FirestoreCodec.timestampToDateTime(
        data['createdAt'],
        fieldName: 'createdAt',
      ),
      resolvedAt: FirestoreCodec.timestampToDateTime(
        data['resolvedAt'],
        fieldName: 'resolvedAt',
      ),
    );
  }
}

/// Firestore document codec for [Verification].
class VerificationFirestoreCodec {
  VerificationFirestoreCodec._();

  static Map<String, dynamic> toFirestore(Verification verification) {
    final map = <String, dynamic>{
      if (verification.id.isNotEmpty) 'id': verification.id,
      'restroomId': verification.restroomId,
      'result': verification.result.value,
      if (verification.createdAt != null)
        'createdAt': FirestoreCodec.dateTimeToTimestamp(verification.createdAt),
    };

    assert(
      !map.containsKey('createdByUid'),
      'Public verification cannot contain createdByUid',
    );
    assert(
      !map.containsKey('userUid'),
      'Public verification cannot contain userUid',
    );
    assert(
      !map.containsKey('userId'),
      'Public verification cannot contain userId',
    );
    assert(
      !map.containsKey('authorUid'),
      'Public verification cannot contain authorUid',
    );
    assert(!map.containsKey('uid'), 'Public verification cannot contain uid');

    return map;
  }

  static Verification fromFirestore(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    return Verification(
      id: documentId ?? (data['id'] as String? ?? ''),
      restroomId: data['restroomId'] as String? ?? '',
      result: VerificationResult.fromString(data['result'] as String?),
      createdAt: FirestoreCodec.timestampToDateTime(
        data['createdAt'],
        fieldName: 'createdAt',
      ),
    );
  }
}
