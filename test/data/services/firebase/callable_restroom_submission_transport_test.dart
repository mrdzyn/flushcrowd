import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/core/config/app_config.dart';
import 'package:flushcrowd/core/config/environment.dart';
import 'package:flushcrowd/core/constants/app_constants.dart';
import 'package:flushcrowd/core/errors/exceptions.dart';
import 'package:flushcrowd/data/repositories/auth_repository_impl.dart';
import 'package:flushcrowd/data/repositories/firestore_restroom_repository.dart';
import 'package:flushcrowd/data/services/firebase/firestore_mutation_adapter.dart';
import 'package:flushcrowd/data/services/firebase/restroom_submission_transport.dart';
import 'package:flushcrowd/data/services/gis/geohash_service.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/restroom_draft.dart';

class FakeFirestoreMutationAdapter implements FirestoreMutationAdapter {
  final Map<String, Map<String, dynamic>> publicDocuments = {};
  final Map<String, Map<String, dynamic>> privateDocuments = {};
  final List<Map<String, dynamic>> recordedBatches = [];

  bool throwOnBatchCommit = false;
  FirebaseException? batchCommitException;
  FirebaseException? publicReadException;
  FirebaseException? privateReadException;

  @override
  Future<void> commitRestroomSubmissionBatch({
    required String restroomId,
    required Map<String, dynamic> publicData,
    required String contributionId,
    required Map<String, dynamic> contributionData,
  }) async {
    recordedBatches.add({
      'restroomId': restroomId,
      'publicData': Map<String, dynamic>.from(publicData),
      'contributionId': contributionId,
      'contributionData': Map<String, dynamic>.from(contributionData),
    });

    if (throwOnBatchCommit) {
      throw batchCommitException ??
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
            message: 'Simulated network drop',
          );
    }

    publicDocuments[restroomId] = Map<String, dynamic>.from(publicData);
    privateDocuments[contributionId] = Map<String, dynamic>.from(
      contributionData,
    );
  }

  @override
  Future<FirestoreDocumentData?> getPublicRestroom(String restroomId) async {
    if (publicReadException != null) throw publicReadException!;
    final doc = publicDocuments[restroomId];
    if (doc == null) return null;
    return FirestoreDocumentData(
      documentId: restroomId,
      data: Map<String, dynamic>.from(doc),
    );
  }

  @override
  Future<FirestoreDocumentData?> getPrivateContribution(
    String contributionId,
  ) async {
    if (privateReadException != null) throw privateReadException!;
    final doc = privateDocuments[contributionId];
    if (doc == null) return null;
    return FirestoreDocumentData(
      documentId: contributionId,
      data: Map<String, dynamic>.from(doc),
    );
  }
}

void main() {
  final testCoords = Coordinates(latitude: 14.5839, longitude: 121.0617);
  final testDraft = RestroomDraft(
    name: 'Megamall Ground Floor Restroom',
    coordinates: testCoords,
    countryCode: 'PH',
    region: 'NCR',
    city: 'Mandaluyong',
    buildingName: 'SM Megamall',
    buildingSection: 'Building A',
    floor: 'UG',
    unitOrArea: 'Near Food Court',
    landmark: 'Behind Bakery',
    directionsNote: 'Walk down corridor next to elevators',
    accessInstructions: 'Free access for mallgoers',
    accessType: AccessType.paid,
    feeAmount: 10.0,
    feeCurrency: 'PHP',
    male: true,
    female: true,
    allGender: false,
    pwdAccessible: TriStateAmenity.yes,
    babyChanging: TriStateAmenity.yes,
    hasBidet: TriStateAmenity.yes,
    hasToiletPaper: TriStateAmenity.yes,
    hasSoap: TriStateAmenity.yes,
    hasHandDryer: TriStateAmenity.yes,
  );

  final testCommand = CreateRestroomCommand(
    restroomId: 'rr_test_callable_123',
    draft: testDraft,
  );

  Map<String, dynamic> buildCanonicalPublicData(
    String restroomId,
    RestroomDraft draft,
  ) {
    final geohash = GeohashService.encode(draft.coordinates);
    return {
      'id': restroomId,
      'name': draft.name,
      'latitude': draft.coordinates.latitude,
      'longitude': draft.coordinates.longitude,
      'geohash': geohash,
      'countryCode': draft.countryCode,
      'region': draft.region,
      'city': draft.city,
      'buildingName': draft.buildingName,
      'buildingSection': draft.buildingSection,
      'floor': draft.floor,
      'unitOrArea': draft.unitOrArea,
      'landmark': draft.landmark,
      'directionsNote': draft.directionsNote,
      'accessInstructions': draft.accessInstructions,
      'accessType': draft.accessType.value,
      'feeAmount': draft.feeAmount,
      'feeCurrency': draft.feeCurrency,
      'male': draft.male,
      'female': draft.female,
      'allGender': draft.allGender,
      'pwdAccessible': draft.pwdAccessible.toNullableBool(),
      'babyChanging': draft.babyChanging.toNullableBool(),
      'hasBidet': draft.hasBidet.toNullableBool(),
      'hasToiletPaper': draft.hasToiletPaper.toNullableBool(),
      'hasSoap': draft.hasSoap.toNullableBool(),
      'hasHandDryer': draft.hasHandDryer.toNullableBool(),
      'averageRating': 0.0,
      'ratingCount': 0,
      'verificationCount': 0,
      'negativeVerificationCount': 0,
      'status': 'unverified',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  Map<String, dynamic> buildCanonicalPrivateData(
    String restroomId,
    String uid,
  ) {
    return {
      'id': 'restroom_$restroomId',
      'contributionType': 'restroom',
      'resourceId': restroomId,
      'restroomId': restroomId,
      'userUid': uid,
      'moderationState': 'pending',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  group('P2.6-B — CallableRestroomSubmissionTransport Unit Tests', () {
    test('1. Correct request serialization: omits sentinels, UIDs, aggregates, and status', () {
      final payload = CallableRestroomSubmissionTransport.serializeCommand(
        testCommand,
      );

      // Core required fields
      expect(payload['restroomId'], equals('rr_test_callable_123'));
      expect(payload['name'], equals('Megamall Ground Floor Restroom'));
      expect(payload['latitude'], equals(14.5839));
      expect(payload['longitude'], equals(121.0617));
      expect(payload['accessType'], equals('paid'));
      expect(payload['feeAmount'], equals(10.0));
      expect(payload['feeCurrency'], equals('PHP'));

      // Indoor context
      expect(payload['buildingName'], equals('SM Megamall'));
      expect(payload['floor'], equals('UG'));
      expect(payload['landmark'], equals('Behind Bakery'));

      // Stalls & amenities
      expect(payload['male'], isTrue);
      expect(payload['female'], isTrue);
      expect(payload['allGender'], isFalse);
      expect(payload['pwdAccessible'], isTrue);
      expect(payload['hasBidet'], isTrue);

      // Mandatory exclusion invariants (cannot transmit sentinels or private data)
      expect(payload.containsKey('createdAt'), isFalse);
      expect(payload.containsKey('updatedAt'), isFalse);
      expect(payload.containsKey('status'), isFalse);
      expect(payload.containsKey('averageRating'), isFalse);
      expect(payload.containsKey('ratingCount'), isFalse);
      expect(payload.containsKey('verificationCount'), isFalse);
      expect(payload.containsKey('negativeVerificationCount'), isFalse);
      expect(payload.containsKey('lastVerifiedAt'), isFalse);
      expect(payload.containsKey('userUid'), isFalse);
      expect(payload.containsKey('createdByUid'), isFalse);
      expect(payload.containsKey('authorUid'), isFalse);
      expect(payload.containsKey('uid'), isFalse);
    });

    test('2. Successful submission and stable-ID preservation', () async {
      Map<String, dynamic>? capturedPayload;

      final transport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          capturedPayload = payload;
          return {
            'success': true,
            'isIdempotentRetry': false,
            'restroom': buildCanonicalPublicData(
              payload['restroomId'] as String,
              testDraft,
            ),
          };
        },
      );

      final result = await transport.submitRestroom(
        command: testCommand,
        uid: 'anon_uid_999',
      );

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['restroomId'], equals('rr_test_callable_123'));
      expect(result.id, equals('rr_test_callable_123'));
      expect(result.name, equals('Megamall Ground Floor Restroom'));
      expect(result.status, equals(RestroomStatus.unverified));
      expect(result.createdAt, isNotNull);
      expect(result.updatedAt, isNotNull);
    });

    test('3. Rate-limit rejection: resource-exhausted mapped to rate-limited exception', () async {
      final transport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          throw FirebaseFunctionsException(
            message: 'Daily submission limit reached.',
            code: 'resource-exhausted',
          );
        },
      );

      expect(
        () =>
            transport.submitRestroom(command: testCommand, uid: 'anon_uid_999'),
        throwsA(
          isA<RepositoryException>()
              .having((e) => e.code, 'code', 'rate-limited')
              .having(
                (e) => e.message,
                'message',
                contains('submission limit reached'),
              ),
        ),
      );
    });

    test('4. Authentication and App Check errors', () async {
      final unauthTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          throw FirebaseFunctionsException(
            message: 'User must be authenticated anonymously.',
            code: 'unauthenticated',
          );
        },
      );

      expect(
        () => unauthTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(isA<UnauthenticatedException>()),
      );

      final appCheckTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          throw FirebaseFunctionsException(
            message: 'App Check verification failed.',
            code: 'failed-precondition',
          );
        },
      );

      expect(
        () => appCheckTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'app-check-failed',
          ),
        ),
      );

      final permDeniedTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          throw FirebaseFunctionsException(
            message: 'Caller lacks permission.',
            code: 'permission-denied',
          );
        },
      );

      expect(
        () => permDeniedTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'app-check-failed',
          ),
        ),
      );
    });

    test('5. BLOCKER-1: Ambiguous callable completion integrity — requires verified public/private pairing', () async {
      final mutationAdapter = FakeFirestoreMutationAdapter();

      // Case A: Complete successful reconciliation (both public and private documents match)
      mutationAdapter.publicDocuments['rr_test_callable_123'] =
          buildCanonicalPublicData('rr_test_callable_123', testDraft);
      mutationAdapter.privateDocuments['restroom_rr_test_callable_123'] =
          buildCanonicalPrivateData('rr_test_callable_123', 'anon_uid_999');

      final timeoutTransportSuccess = CallableRestroomSubmissionTransport(
        pointReadAdapter: mutationAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('HTTP request timed out');
        },
      );

      final result = await timeoutTransportSuccess.submitRestroom(
        command: testCommand,
        uid: 'anon_uid_999',
      );
      expect(result.id, equals('rr_test_callable_123'));
      expect(result.name, equals('Megamall Ground Floor Restroom'));
      expect(result.status, equals(RestroomStatus.unverified));

      // Case B: Point read finds NO document -> throws unavailable
      final emptyAdapter = FakeFirestoreMutationAdapter();
      final timeoutTransportFailure = CallableRestroomSubmissionTransport(
        pointReadAdapter: emptyAdapter,
        callableInvoker: (payload) async {
          throw FirebaseFunctionsException(
            message: 'Deadline exceeded',
            code: 'deadline-exceeded',
          );
        },
      );

      expect(
        () => timeoutTransportFailure.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'unavailable',
          ),
        ),
      );

      // Case C: Missing private contribution (orphaned public document) -> throws SubmissionInvariantException
      final orphanedPublicAdapter = FakeFirestoreMutationAdapter();
      orphanedPublicAdapter.publicDocuments['rr_test_callable_123'] =
          buildCanonicalPublicData('rr_test_callable_123', testDraft);
      // privateDocuments left empty

      final orphanedPublicTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: orphanedPublicAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('Timed out');
        },
      );

      expect(
        () => orphanedPublicTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<SubmissionInvariantException>().having(
            (e) => e.message,
            'message',
            contains('private contribution is missing or unreadable'),
          ),
        ),
      );

      // Case D: Wrong contributor on private contribution -> throws SubmissionInvariantException
      final wrongContributorAdapter = FakeFirestoreMutationAdapter();
      wrongContributorAdapter.publicDocuments['rr_test_callable_123'] =
          buildCanonicalPublicData('rr_test_callable_123', testDraft);
      wrongContributorAdapter
              .privateDocuments['restroom_rr_test_callable_123'] =
          buildCanonicalPrivateData(
            'rr_test_callable_123',
            'wrong_contributor_uid',
          );

      final wrongContributorTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: wrongContributorAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('Timed out');
        },
      );

      expect(
        () => wrongContributorTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<SubmissionInvariantException>().having(
            (e) => e.message,
            'message',
            contains('private contribution metadata mismatch'),
          ),
        ),
      );

      // Case E.1: Modified amenities in public document -> throws SubmissionInvariantException
      final modifiedAmenityAdapter = FakeFirestoreMutationAdapter();
      final modAmenityData = buildCanonicalPublicData(
        'rr_test_callable_123',
        testDraft,
      );
      modAmenityData['hasBidet'] = false; // testDraft has hasBidet: true
      modifiedAmenityAdapter.publicDocuments['rr_test_callable_123'] =
          modAmenityData;
      modifiedAmenityAdapter.privateDocuments['restroom_rr_test_callable_123'] =
          buildCanonicalPrivateData('rr_test_callable_123', 'anon_uid_999');

      final modifiedAmenityTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: modifiedAmenityAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('Timed out');
        },
      );

      expect(
        () => modifiedAmenityTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<SubmissionInvariantException>().having(
            (e) => e.message,
            'message',
            contains('stalls or amenities do not match'),
          ),
        ),
      );

      // Case E.2: Modified fee in public document -> throws SubmissionInvariantException
      final modifiedFeeAdapter = FakeFirestoreMutationAdapter();
      final modFeeData = buildCanonicalPublicData(
        'rr_test_callable_123',
        testDraft,
      );
      modFeeData['feeAmount'] = 25.0; // testDraft has feeAmount: 10.0
      modifiedFeeAdapter.publicDocuments['rr_test_callable_123'] = modFeeData;
      modifiedFeeAdapter.privateDocuments['restroom_rr_test_callable_123'] =
          buildCanonicalPrivateData('rr_test_callable_123', 'anon_uid_999');

      final modifiedFeeTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: modifiedFeeAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('Timed out');
        },
      );

      expect(
        () => modifiedFeeTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<SubmissionInvariantException>().having(
            (e) => e.message,
            'message',
            contains('fee configuration does not match'),
          ),
        ),
      );

      // Case F.1: Failed reconciliation read (transient unavailable on public read) -> throws retryable RepositoryException
      final publicReadFailAdapter = FakeFirestoreMutationAdapter();
      publicReadFailAdapter.publicReadException = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Simulated point read network loss',
      );

      final publicReadFailTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: publicReadFailAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('Timed out');
        },
      );

      expect(
        () => publicReadFailTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'unavailable',
          ),
        ),
      );

      // Case F.2: Failed reconciliation read (transient deadline-exceeded on private read) -> throws retryable RepositoryException
      final privateReadFailAdapter = FakeFirestoreMutationAdapter();
      privateReadFailAdapter.publicDocuments['rr_test_callable_123'] =
          buildCanonicalPublicData('rr_test_callable_123', testDraft);
      privateReadFailAdapter.privateReadException = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Simulated private read timeout',
      );

      final privateReadFailTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: privateReadFailAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('Timed out');
        },
      );

      expect(
        () => privateReadFailTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'deadline-exceeded',
          ),
        ),
      );

      // Case F.3: Permission-denied on private contribution read -> throws SubmissionInvariantException
      final permDeniedPrivateAdapter = FakeFirestoreMutationAdapter();
      permDeniedPrivateAdapter.publicDocuments['rr_test_callable_123'] =
          buildCanonicalPublicData('rr_test_callable_123', testDraft);
      permDeniedPrivateAdapter.privateReadException = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing permissions',
      );

      final permDeniedPrivateTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: permDeniedPrivateAdapter,
        callableInvoker: (payload) async {
          throw TimeoutException('Timed out');
        },
      );

      expect(
        () => permDeniedPrivateTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<SubmissionInvariantException>().having(
            (e) => e.message,
            'message',
            contains('Unable to verify the private contribution'),
          ),
        ),
      );
    });

    test('5b. MAJOR-1: Callable response validation fails closed on invalid or malformed payload', () async {
      // 1. success == false even with restroom payload -> throws submission-failed
      final successFalseTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          return {
            'success': false,
            'restroom': buildCanonicalPublicData(
              'rr_test_callable_123',
              testDraft,
            ),
          };
        },
      );

      await expectLater(
        () => successFalseTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'submission-failed',
          ),
        ),
      );

      // 2. Mismatched restroom ID -> throws invalid-response
      final wrongIdData = buildCanonicalPublicData('wrong_id_999', testDraft);
      wrongIdData['id'] = 'wrong_id_999';
      final wrongIdTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          return {'success': true, 'restroom': wrongIdData};
        },
      );

      await expectLater(
        () => wrongIdTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'invalid-response',
          ),
        ),
      );

      // 3. Altered coordinates -> throws invalid-response
      final alteredCoordsData = buildCanonicalPublicData(
        'rr_test_callable_123',
        testDraft,
      );
      alteredCoordsData['latitude'] = 14.9999;
      final alteredCoordsTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          return {'success': true, 'restroom': alteredCoordsData};
        },
      );

      await expectLater(
        () => alteredCoordsTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'invalid-response',
          ),
        ),
      );

      // 4. Altered name -> throws invalid-response
      final alteredNameData = buildCanonicalPublicData(
        'rr_test_callable_123',
        testDraft,
      );
      alteredNameData['name'] = 'Altered Name Entirely';
      final alteredNameTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          return {'success': true, 'restroom': alteredNameData};
        },
      );

      await expectLater(
        () => alteredNameTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'invalid-response',
          ),
        ),
      );

      // 5. Altered status -> throws invalid-response
      final alteredStatusData = buildCanonicalPublicData(
        'rr_test_callable_123',
        testDraft,
      );
      alteredStatusData['status'] = 'active';
      final alteredStatusTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          return {'success': true, 'restroom': alteredStatusData};
        },
      );

      await expectLater(
        () => alteredStatusTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'invalid-response',
          ),
        ),
      );

      // 6. Prohibited contributor UID in restroom payload -> throws invalid-response
      final leakedUidData = buildCanonicalPublicData(
        'rr_test_callable_123',
        testDraft,
      );
      leakedUidData['userUid'] = 'anon_uid_999';
      final leakedUidTransport = CallableRestroomSubmissionTransport(
        callableInvoker: (payload) async {
          return {'success': true, 'restroom': leakedUidData};
        },
      );

      await expectLater(
        () => leakedUidTransport.submitRestroom(
          command: testCommand,
          uid: 'anon_uid_999',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    });

    test('6. No direct-write fallback: callable failure never executes direct Firestore batch', () async {
      final mutationAdapter = FakeFirestoreMutationAdapter();

      final callableTransport = CallableRestroomSubmissionTransport(
        pointReadAdapter: mutationAdapter,
        callableInvoker: (payload) async {
          throw FirebaseFunctionsException(
            message: 'Rate limit exceeded',
            code: 'resource-exhausted',
          );
        },
      );

      final repository = FirestoreRestroomRepository(
        mutationAdapter: mutationAdapter,
        submissionTransport: callableTransport,
        authRepository: InMemoryAuthRepository(initialUid: 'anon_uid_999'),
      );

      await expectLater(
        () => repository.submitRestroom(testCommand),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'rate-limited',
          ),
        ),
      );

      // Invariant: Zero batch writes were attempted on mutation adapter
      expect(mutationAdapter.recordedBatches, isEmpty);
      expect(mutationAdapter.publicDocuments, isEmpty);
      expect(mutationAdapter.privateDocuments, isEmpty);
    });

    test('7. Wrong Firebase project/environment rejection', () async {
      final mutationAdapter = FakeFirestoreMutationAdapter();

      // Wrong project ID in staging
      const wrongProjectConfig = AppConfig(
        environment: Environment.staging,
        firebaseProjectId: 'wrong-project-id',
      );
      final wrongProjectRepo = FirestoreRestroomRepository(
        mutationAdapter: mutationAdapter,
        appConfig: wrongProjectConfig,
        authRepository: InMemoryAuthRepository(initialUid: 'anon_uid_999'),
      );

      await expectLater(
        () => wrongProjectRepo.submitRestroom(testCommand),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'staging-project-mismatch',
          ),
        ),
      );

      // Development environment rejects writes in repository
      const devConfig = AppConfig(
        environment: Environment.development,
        firebaseProjectId: AppConstants.stagingFirebaseProjectId,
      );
      final devRepo = FirestoreRestroomRepository(
        mutationAdapter: mutationAdapter,
        appConfig: devConfig,
        authRepository: InMemoryAuthRepository(initialUid: 'anon_uid_999'),
      );

      await expectLater(
        () => devRepo.submitRestroom(testCommand),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.code,
            'code',
            'non-staging-environment',
          ),
        ),
      );
    });

    test('8. Existing staging direct-write behavior unchanged when useCallableSubmission is false', () async {
      final mutationAdapter = FakeFirestoreMutationAdapter();

      const stagingDirectConfig = AppConfig(
        environment: Environment.staging,
        firebaseProjectId: AppConstants.stagingFirebaseProjectId,
        useCallableSubmission: false,
      );

      final repo = FirestoreRestroomRepository(
        mutationAdapter: mutationAdapter,
        appConfig: stagingDirectConfig,
        authRepository: InMemoryAuthRepository(initialUid: 'anon_uid_999'),
      );

      final result = await repo.submitRestroom(testCommand);

      expect(result.id, equals('rr_test_callable_123'));
      expect(mutationAdapter.recordedBatches, hasLength(1));
      expect(
        mutationAdapter.publicDocuments.containsKey('rr_test_callable_123'),
        isTrue,
      );
      expect(
        mutationAdapter.privateDocuments.containsKey(
          'restroom_rr_test_callable_123',
        ),
        isTrue,
      );
    });

    test(
      '9. Production submissions remain disabled: production-writes-blocked',
      () async {
        final mutationAdapter = FakeFirestoreMutationAdapter();

        const prodConfig = AppConfig(
          environment: Environment.production,
          firebaseProjectId: AppConstants.stagingFirebaseProjectId,
          useCallableSubmission: true,
        );

        final repo = FirestoreRestroomRepository(
          mutationAdapter: mutationAdapter,
          appConfig: prodConfig,
          authRepository: InMemoryAuthRepository(initialUid: 'anon_uid_999'),
        );

        await expectLater(
          () => repo.submitRestroom(testCommand),
          throwsA(
            isA<RepositoryException>().having(
              (e) => e.code,
              'code',
              'production-writes-blocked',
            ),
          ),
        );

        expect(mutationAdapter.recordedBatches, isEmpty);
      },
    );
  });
}
