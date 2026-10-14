import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/commands/create_restroom_command.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/restroom.dart';
import '../../../domain/models/restroom_draft.dart';
import '../gis/geohash_service.dart';
import 'firestore_codec.dart';
import 'firestore_mutation_adapter.dart';

/// Boundary interface for restroom submission transport.
///
/// Encapsulates the mechanism used to submit community restrooms
/// (e.g. direct Firestore write batches during staging, or trusted
/// Firebase Cloud Functions callables).
abstract class RestroomSubmissionTransport {
  Future<Restroom> submitRestroom({
    required CreateRestroomCommand command,
    required String uid,
  });
}

/// Direct Firestore batch implementation of [RestroomSubmissionTransport].
///
/// Executes an atomic write batch containing the public restroom and private
/// contribution document pair, and reconciles ambiguous network outcomes via
/// transactional point reads.
class DirectFirestoreRestroomSubmissionTransport
    implements RestroomSubmissionTransport {
  final FirestoreMutationAdapter _mutationAdapter;

  DirectFirestoreRestroomSubmissionTransport(
    FirestoreMutationAdapter mutationAdapter,
  ) : _mutationAdapter = mutationAdapter;

  @override
  Future<Restroom> submitRestroom({
    required CreateRestroomCommand command,
    required String uid,
  }) async {
    final restroomId = command.restroomId;
    if (restroomId.isEmpty ||
        restroomId != restroomId.trim() ||
        restroomId.length > 100 ||
        restroomId.contains('/') ||
        restroomId == '.' ||
        restroomId == '..') {
      throw const RepositoryException(
        'Invalid stable restroom ID: must be non-empty, cannot contain leading/trailing whitespace, <= 100 characters, and contain no path separators.',
        'invalid-restroom-id',
      );
    }

    final normalized = command.draft.normalized();
    final validationErrors = normalized.validate();
    if (validationErrors.isNotEmpty) {
      throw RepositoryException(
        'Cannot submit invalid restroom draft: ${validationErrors.join(', ')}',
        'invalid-draft',
      );
    }

    final geohash = GeohashService.encode(normalized.coordinates);

    // Build public payload
    final publicData = <String, dynamic>{
      'id': restroomId,
      'name': normalized.name,
      'latitude': normalized.coordinates.latitude,
      'longitude': normalized.coordinates.longitude,
      'geohash': geohash,
      if (normalized.countryCode != null) 'countryCode': normalized.countryCode,
      if (normalized.region != null) 'region': normalized.region,
      if (normalized.city != null) 'city': normalized.city,
      if (normalized.buildingName != null)
        'buildingName': normalized.buildingName,
      if (normalized.buildingSection != null)
        'buildingSection': normalized.buildingSection,
      if (normalized.floor != null) 'floor': normalized.floor,
      if (normalized.unitOrArea != null) 'unitOrArea': normalized.unitOrArea,
      if (normalized.landmark != null) 'landmark': normalized.landmark,
      if (normalized.directionsNote != null)
        'directionsNote': normalized.directionsNote,
      if (normalized.accessInstructions != null)
        'accessInstructions': normalized.accessInstructions,
      'accessType': normalized.accessType.value,
      if (normalized.feeAmount != null) 'feeAmount': normalized.feeAmount,
      if (normalized.feeCurrency != null) 'feeCurrency': normalized.feeCurrency,
      if (normalized.male != null) 'male': normalized.male,
      if (normalized.female != null) 'female': normalized.female,
      if (normalized.allGender != null) 'allGender': normalized.allGender,
      if (normalized.pwdAccessible.toNullableBool() != null)
        'pwdAccessible': normalized.pwdAccessible.toNullableBool(),
      if (normalized.babyChanging.toNullableBool() != null)
        'babyChanging': normalized.babyChanging.toNullableBool(),
      if (normalized.hasBidet.toNullableBool() != null)
        'hasBidet': normalized.hasBidet.toNullableBool(),
      if (normalized.hasToiletPaper.toNullableBool() != null)
        'hasToiletPaper': normalized.hasToiletPaper.toNullableBool(),
      if (normalized.hasSoap.toNullableBool() != null)
        'hasSoap': normalized.hasSoap.toNullableBool(),
      if (normalized.hasHandDryer.toNullableBool() != null)
        'hasHandDryer': normalized.hasHandDryer.toNullableBool(),
      'averageRating': 0.0,
      'ratingCount': 0,
      'verificationCount': 0,
      'negativeVerificationCount': 0,
      'status': RestroomStatus.unverified.value,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Build private contribution payload
    final privateContributionData = <String, dynamic>{
      'id': 'restroom_$restroomId',
      'contributionType': 'restroom',
      'resourceId': restroomId,
      'restroomId': restroomId,
      'userUid': uid,
      'moderationState': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Execute ONE atomic batch directly without pre-reads
    try {
      await _mutationAdapter.commitRestroomSubmissionBatch(
        restroomId: restroomId,
        publicData: publicData,
        contributionId: 'restroom_$restroomId',
        contributionData: privateContributionData,
      );
    } catch (batchError) {
      // Ambiguous commit reconciliation
      try {
        final publicDoc = await _mutationAdapter.getPublicRestroom(restroomId);
        if (publicDoc == null) {
          if (batchError is AppException) rethrow;
          if (batchError is FirebaseException) {
            throw RepositoryException(
              batchError.message ?? 'Firestore error submitting restroom.',
              batchError.code,
            );
          }
          throw RepositoryException(
            'Unexpected error submitting restroom: $batchError',
          );
        }

        FirestoreDocumentData? privateDoc;
        try {
          privateDoc = await _mutationAdapter.getPrivateContribution(
            'restroom_$restroomId',
          );
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            throw const SubmissionInvariantException(
              'Unable to verify the private contribution paired with this restroom.',
            );
          }
          if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
            throw RepositoryException(
              e.message ??
                  'Transient network error during reconciliation read.',
              e.code,
            );
          }
          rethrow;
        }

        if (privateDoc == null) {
          throw const SubmissionInvariantException(
            'Invariant violation: public restroom exists but private contribution is missing or unreadable.',
          );
        }

        validateReconciliationPair(
          restroomId: restroomId,
          publicDoc: publicDoc,
          privateDoc: privateDoc,
          normalized: normalized,
          geohash: geohash,
          uid: uid,
        );

        return RestroomFirestoreCodec.fromFirestore(
          publicDoc.data,
          documentId: publicDoc.documentId,
        );
      } catch (recErr) {
        if (recErr is SubmissionInvariantException) rethrow;
        if (recErr is RepositoryException) rethrow;
        throw RepositoryException(
          'Reconciliation failed following ambiguous submission error: $recErr',
        );
      }
    }

    // Return successfully submitted Restroom with null timestamps
    return Restroom(
      id: restroomId,
      name: normalized.name,
      coordinates: normalized.coordinates,
      geohash: geohash,
      countryCode: normalized.countryCode,
      region: normalized.region,
      city: normalized.city,
      buildingName: normalized.buildingName,
      buildingSection: normalized.buildingSection,
      floor: normalized.floor,
      unitOrArea: normalized.unitOrArea,
      landmark: normalized.landmark,
      directionsNote: normalized.directionsNote,
      accessInstructions: normalized.accessInstructions,
      accessType: normalized.accessType,
      feeAmount: normalized.feeAmount,
      feeCurrency: normalized.feeCurrency,
      male: normalized.male,
      female: normalized.female,
      allGender: normalized.allGender,
      pwdAccessible: normalized.pwdAccessible.toNullableBool(),
      babyChanging: normalized.babyChanging.toNullableBool(),
      hasBidet: normalized.hasBidet.toNullableBool(),
      hasToiletPaper: normalized.hasToiletPaper.toNullableBool(),
      hasSoap: normalized.hasSoap.toNullableBool(),
      hasHandDryer: normalized.hasHandDryer.toNullableBool(),
      averageRating: 0.0,
      ratingCount: 0,
      verificationCount: 0,
      negativeVerificationCount: 0,
      lastVerifiedAt: null,
      status: RestroomStatus.unverified,
      createdAt: null,
      updatedAt: null,
    );
  }

  static void validateReconciliationPair({
    required String restroomId,
    required FirestoreDocumentData publicDoc,
    required FirestoreDocumentData privateDoc,
    required RestroomDraft normalized,
    required String geohash,
    required String uid,
  }) {
    final publicDocId = publicDoc.documentId;
    final publicStoredId = publicDoc.data['id'] as String?;
    final publicStatus = publicDoc.data['status'] as String?;
    if (publicDocId != restroomId ||
        publicStoredId != restroomId ||
        publicStatus != RestroomStatus.unverified.value) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom identity or status mismatch.',
      );
    }

    final name = publicDoc.data['name'] as String?;
    final lat = (publicDoc.data['latitude'] as num?)?.toDouble();
    final lng = (publicDoc.data['longitude'] as num?)?.toDouble();
    final docGeohash = publicDoc.data['geohash'] as String?;
    final accessType = publicDoc.data['accessType'] as String?;

    if (name != normalized.name ||
        lat != normalized.coordinates.latitude ||
        lng != normalized.coordinates.longitude ||
        docGeohash != geohash ||
        accessType != normalized.accessType.value) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom data does not match submission command.',
      );
    }

    if (publicDoc.data['countryCode'] != normalized.countryCode ||
        publicDoc.data['region'] != normalized.region ||
        publicDoc.data['city'] != normalized.city ||
        publicDoc.data['buildingName'] != normalized.buildingName ||
        publicDoc.data['buildingSection'] != normalized.buildingSection ||
        publicDoc.data['floor'] != normalized.floor ||
        publicDoc.data['unitOrArea'] != normalized.unitOrArea ||
        publicDoc.data['landmark'] != normalized.landmark ||
        publicDoc.data['directionsNote'] != normalized.directionsNote ||
        publicDoc.data['accessInstructions'] != normalized.accessInstructions) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom context does not match submission command.',
      );
    }

    final feeAmount = (publicDoc.data['feeAmount'] as num?)?.toDouble();
    if (feeAmount != normalized.feeAmount ||
        publicDoc.data['feeCurrency'] != normalized.feeCurrency) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom fee configuration does not match submission command.',
      );
    }

    if (publicDoc.data['male'] != normalized.male ||
        publicDoc.data['female'] != normalized.female ||
        publicDoc.data['allGender'] != normalized.allGender ||
        publicDoc.data['pwdAccessible'] !=
            normalized.pwdAccessible.toNullableBool() ||
        publicDoc.data['babyChanging'] !=
            normalized.babyChanging.toNullableBool() ||
        publicDoc.data['hasBidet'] != normalized.hasBidet.toNullableBool() ||
        publicDoc.data['hasToiletPaper'] !=
            normalized.hasToiletPaper.toNullableBool() ||
        publicDoc.data['hasSoap'] != normalized.hasSoap.toNullableBool() ||
        publicDoc.data['hasHandDryer'] !=
            normalized.hasHandDryer.toNullableBool()) {
      throw const SubmissionInvariantException(
        'Invariant violation: public restroom stalls or amenities do not match submission command.',
      );
    }

    final privateDocId = privateDoc.documentId;
    final contribId = privateDoc.data['id'] as String?;
    final contribType = privateDoc.data['contributionType'] as String?;
    final resourceId = privateDoc.data['resourceId'] as String?;
    final contribRestroomId = privateDoc.data['restroomId'] as String?;
    final userUid = privateDoc.data['userUid'] as String?;
    final moderationState = privateDoc.data['moderationState'] as String?;

    if (privateDocId != 'restroom_$restroomId' ||
        contribId != 'restroom_$restroomId' ||
        contribType != 'restroom' ||
        resourceId != restroomId ||
        contribRestroomId != restroomId ||
        userUid != uid ||
        moderationState != 'pending') {
      throw const SubmissionInvariantException(
        'Invariant violation: private contribution metadata mismatch.',
      );
    }
  }
}

/// Firebase Cloud Functions callable implementation of [RestroomSubmissionTransport].
///
/// Invokes the `submitRestroom` callable function in region [region], serializing
/// [CreateRestroomCommand] without Firestore sentinels, contributor UIDs, trusted
/// aggregates, or private contribution documents.
class CallableRestroomSubmissionTransport
    implements RestroomSubmissionTransport {
  final FirebaseFunctions? functions;
  final FirebaseApp? app;
  final String region;
  final FirestoreMutationAdapter? pointReadAdapter;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)?
  callableInvoker;

  CallableRestroomSubmissionTransport({
    this.functions,
    this.app,
    String? region,
    this.pointReadAdapter,
    this.callableInvoker,
  }) : region = region ?? AppConstants.defaultCloudFunctionsRegion;

  /// Serializes a [CreateRestroomCommand] into the validated callable payload schema.
  ///
  /// Strictly omits `FieldValue.serverTimestamp()`, contributor UIDs,
  /// trusted aggregate fields, and private contribution documents.
  static Map<String, dynamic> serializeCommand(CreateRestroomCommand command) {
    final normalized = command.draft.normalized();
    final payload = <String, dynamic>{
      'restroomId': command.restroomId,
      'name': normalized.name,
      'latitude': normalized.coordinates.latitude,
      'longitude': normalized.coordinates.longitude,
      'accessType': normalized.accessType.value,
    };

    if (normalized.countryCode != null) {
      payload['countryCode'] = normalized.countryCode;
    }
    if (normalized.region != null) {
      payload['region'] = normalized.region;
    }
    if (normalized.city != null) {
      payload['city'] = normalized.city;
    }
    if (normalized.buildingName != null) {
      payload['buildingName'] = normalized.buildingName;
    }
    if (normalized.buildingSection != null) {
      payload['buildingSection'] = normalized.buildingSection;
    }
    if (normalized.floor != null) {
      payload['floor'] = normalized.floor;
    }
    if (normalized.unitOrArea != null) {
      payload['unitOrArea'] = normalized.unitOrArea;
    }
    if (normalized.landmark != null) {
      payload['landmark'] = normalized.landmark;
    }
    if (normalized.directionsNote != null) {
      payload['directionsNote'] = normalized.directionsNote;
    }
    if (normalized.accessInstructions != null) {
      payload['accessInstructions'] = normalized.accessInstructions;
    }

    if (normalized.accessType == AccessType.paid) {
      if (normalized.feeAmount != null) {
        payload['feeAmount'] = normalized.feeAmount;
      }
      if (normalized.feeCurrency != null) {
        payload['feeCurrency'] = normalized.feeCurrency;
      }
    }

    if (normalized.male != null) payload['male'] = normalized.male;
    if (normalized.female != null) payload['female'] = normalized.female;
    if (normalized.allGender != null) {
      payload['allGender'] = normalized.allGender;
    }

    final pwd = normalized.pwdAccessible.toNullableBool();
    if (pwd != null) payload['pwdAccessible'] = pwd;

    final baby = normalized.babyChanging.toNullableBool();
    if (baby != null) payload['babyChanging'] = baby;

    final bidet = normalized.hasBidet.toNullableBool();
    if (bidet != null) payload['hasBidet'] = bidet;

    final tp = normalized.hasToiletPaper.toNullableBool();
    if (tp != null) payload['hasToiletPaper'] = tp;

    final soap = normalized.hasSoap.toNullableBool();
    if (soap != null) payload['hasSoap'] = soap;

    final dryer = normalized.hasHandDryer.toNullableBool();
    if (dryer != null) payload['hasHandDryer'] = dryer;

    // Strict privacy and integrity assertions: never transmit sentinels or UIDs
    assert(
      !payload.containsKey('createdAt'),
      'Client cannot transmit createdAt to callable backend',
    );
    assert(
      !payload.containsKey('updatedAt'),
      'Client cannot transmit updatedAt to callable backend',
    );
    assert(
      !payload.containsKey('status'),
      'Client cannot transmit status to callable backend',
    );
    assert(
      !payload.containsKey('averageRating'),
      'Client cannot transmit averageRating to callable backend',
    );
    assert(
      !payload.containsKey('ratingCount'),
      'Client cannot transmit ratingCount to callable backend',
    );
    assert(
      !payload.containsKey('verificationCount'),
      'Client cannot transmit verificationCount to callable backend',
    );
    assert(
      !payload.containsKey('negativeVerificationCount'),
      'Client cannot transmit negativeVerificationCount to callable backend',
    );
    assert(
      !payload.containsKey('lastVerifiedAt'),
      'Client cannot transmit lastVerifiedAt to callable backend',
    );
    assert(
      !payload.containsKey('userUid'),
      'Client cannot transmit userUid to callable backend',
    );
    assert(
      !payload.containsKey('createdByUid'),
      'Client cannot transmit createdByUid to callable backend',
    );
    assert(
      !payload.containsKey('authorUid'),
      'Client cannot transmit authorUid to callable backend',
    );
    assert(
      !payload.containsKey('uid'),
      'Client cannot transmit uid to callable backend',
    );

    return payload;
  }

  @override
  Future<Restroom> submitRestroom({
    required CreateRestroomCommand command,
    required String uid,
  }) async {
    final restroomId = command.restroomId;
    if (restroomId.isEmpty ||
        restroomId != restroomId.trim() ||
        restroomId.length > 100 ||
        restroomId.contains('/') ||
        restroomId == '.' ||
        restroomId == '..') {
      throw const RepositoryException(
        'Invalid stable restroom ID: must be non-empty, cannot contain leading/trailing whitespace, <= 100 characters, and contain no path separators.',
        'invalid-restroom-id',
      );
    }

    final normalized = command.draft.normalized();
    final validationErrors = normalized.validate();
    if (validationErrors.isNotEmpty) {
      throw RepositoryException(
        'Cannot submit invalid restroom draft: ${validationErrors.join(', ')}',
        'invalid-draft',
      );
    }

    final payload = serializeCommand(command);

    Map<String, dynamic> resultData;
    try {
      if (callableInvoker != null) {
        resultData = await callableInvoker!(payload);
      } else {
        final fn =
            functions ??
            FirebaseFunctions.instanceFor(
              app: app ?? Firebase.app(),
              region: region,
            );
        final callable = fn.httpsCallable('submitRestroom');
        final response = await callable.call<dynamic>(payload);
        resultData = Map<String, dynamic>.from(response.data as Map);
      }
    } on FirebaseFunctionsException catch (e) {
      resultData = await _handleFunctionsException(e, command);
    } on TimeoutException catch (e) {
      resultData = await _handleTimeout(e, command);
    } catch (e) {
      if (e is AppException) rethrow;
      throw RepositoryException(
        'Unexpected error invoking submitRestroom: $e',
        'submission-failed',
      );
    }

    final restroomRaw = resultData['restroom'];
    if (restroomRaw is! Map) {
      throw const RepositoryException(
        'Callable response is missing the expected restroom payload.',
        'invalid-response',
      );
    }

    final normalizedMap = _normalizeCallableRestroomMap(
      Map<String, dynamic>.from(restroomRaw),
    );

    return RestroomFirestoreCodec.fromFirestore(
      normalizedMap,
      documentId: command.restroomId,
    );
  }

  Future<Map<String, dynamic>> _handleFunctionsException(
    FirebaseFunctionsException e,
    CreateRestroomCommand command,
  ) async {
    final code = e.code.toLowerCase();

    if (code == 'resource-exhausted') {
      throw RepositoryException(
        e.message ?? 'Submission limit reached. Please wait before submitting another restroom.',
        'rate-limited',
      );
    }

    if (code == 'unauthenticated') {
      throw UnauthenticatedException(
        e.message ?? 'Authentication required. Please check your connection and try again.',
        'unauthenticated',
      );
    }

    if (code == 'permission-denied' || code == 'failed-precondition') {
      throw RepositoryException(
        e.message ?? 'App verification or authorization failed.',
        'app-check-failed',
      );
    }

    if (code == 'already-exists') {
      throw RepositoryException(
        e.message ??
            'A restroom with this ID already exists with different details.',
        'already-exists',
      );
    }

    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return await _verifyAmbiguousPointRead(command, fallbackException: e);
    }

    throw RepositoryException(
      e.message ?? 'Failed to submit restroom ($code).',
      code,
    );
  }

  Future<Map<String, dynamic>> _handleTimeout(
    TimeoutException e,
    CreateRestroomCommand command,
  ) async {
    return await _verifyAmbiguousPointRead(
      command,
      fallbackException: const RepositoryException(
        'Connection timed out. Please check your internet connection.',
        'unavailable',
      ),
    );
  }

  Future<Map<String, dynamic>> _verifyAmbiguousPointRead(
    CreateRestroomCommand command, {
    required Object fallbackException,
  }) async {
    final adapter = pointReadAdapter;
    if (adapter != null) {
      try {
        final publicDoc = await adapter.getPublicRestroom(command.restroomId);
        if (publicDoc != null) {
          if (matchesCanonicalCommand(publicDoc: publicDoc, command: command)) {
            // Transaction successfully committed on server
            return {'success': true, 'restroom': publicDoc.data};
          } else {
            throw const RepositoryException(
              'A restroom with this ID already exists with different details.',
              'already-exists',
            );
          }
        }
      } catch (err) {
        if (err is RepositoryException) rethrow;
        // Point read failed due to network; fall through to throw original failure
      }
    }

    if (fallbackException is FirebaseFunctionsException) {
      throw RepositoryException(
        fallbackException.message ??
            'Connection failed. Please check your internet connection.',
        'unavailable',
      );
    }
    if (fallbackException is AppException) {
      throw fallbackException;
    }
    throw RepositoryException(
      'Connection failed. Please check your internet connection: $fallbackException',
      'unavailable',
    );
  }

  /// Verifies whether an existing public document exactly matches the canonical submission command.
  static bool matchesCanonicalCommand({
    required FirestoreDocumentData publicDoc,
    required CreateRestroomCommand command,
  }) {
    final normalized = command.draft.normalized();
    final data = publicDoc.data;

    if (publicDoc.documentId != command.restroomId ||
        data['id'] != command.restroomId) {
      return false;
    }
    if (data['name'] != normalized.name) return false;

    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    if (lat != normalized.coordinates.latitude ||
        lng != normalized.coordinates.longitude) {
      return false;
    }

    if (data['accessType'] != normalized.accessType.value) return false;

    return true;
  }

  /// Normalizes Map-encoded Timestamps from JSON callable response into Firestore [Timestamp] instances.
  static Map<String, dynamic> _normalizeCallableRestroomMap(
    Map<String, dynamic> rawMap,
  ) {
    final normalized = Map<String, dynamic>.from(rawMap);
    for (final key in ['createdAt', 'updatedAt', 'lastVerifiedAt']) {
      final val = normalized[key];
      if (val is Map) {
        final sec = val['_seconds'] ?? val['seconds'];
        final nano = val['_nanoseconds'] ?? val['nanoseconds'] ?? 0;
        if (sec is int) {
          normalized[key] = Timestamp(sec, (nano is int) ? nano : 0);
        } else if (sec is num) {
          normalized[key] = Timestamp(
            sec.toInt(),
            (nano is num) ? nano.toInt() : 0,
          );
        }
      } else if (val is String) {
        final dt = DateTime.tryParse(val);
        if (dt != null) {
          normalized[key] = Timestamp.fromDate(dt);
        }
      }
    }
    return normalized;
  }
}
