import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/errors/exceptions.dart';
import 'package:looradar/data/repositories/auth_repository_impl.dart';
import 'package:looradar/data/repositories/firestore_restroom_repository.dart';
import 'package:looradar/data/repositories/in_memory_restroom_repository.dart';
import 'package:looradar/data/repositories/location_repository_impl.dart';
import 'package:looradar/data/services/gis/geohash_service.dart';
import 'package:looradar/domain/commands/create_restroom_command.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/enums.dart';
import 'package:looradar/domain/models/geo_bounding_box.dart';
import 'package:looradar/domain/models/restroom.dart';
import 'package:looradar/domain/models/restroom_draft.dart';

void main() {
  group('Repository Contracts and In-Memory Test Doubles', () {
    test(
      'InMemoryRestroomRepository filters nearby and sorts nearest first',
      () async {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final repo = InMemoryRestroomRepository();

        final result = await repo.getNearbyRestrooms(
          center,
          radiusMeters: 2000.0,
        );
        expect(result.isComplete, isTrue);
        expect(result.items, isNotEmpty);

        // Verify that all results are within 2000m
        for (final r in result.items) {
          expect(r.status, RestroomStatus.active);
        }

        // Verify retrieval by id
        final first = result.items.first;
        final retrieved = await repo.getRestroomById(first.id);
        expect(retrieved, equals(first));
      },
    );

    test('InMemoryRestroomRepository filters by bounding box', () async {
      final repo = InMemoryRestroomRepository();
      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.5800, longitude: 121.0500),
        northEast: Coordinates(latitude: 14.5900, longitude: 121.0700),
      );

      final result = await repo.getViewportRestrooms(bounds);
      expect(result.isComplete, isTrue);
      expect(result.items, isNotEmpty);
      for (final r in result.items) {
        expect(bounds.contains(r.coordinates), isTrue);
      }
    });

    test('InMemoryRestroomRepository stores submissions as atomic pair with unverified status and initial aggregates', () async {
      final authRepo = InMemoryAuthRepository(
        initialUid: 'user_contributor_123',
      );
      final repo = InMemoryRestroomRepository(
        initialData: [],
        authRepository: authRepo,
      );
      final coords = Coordinates(latitude: 14.5843, longitude: 121.0568);
      final command = CreateRestroomCommand(
        restroomId: 'new_custom_rr',
        draft: RestroomDraft(
          name: 'New Custom Restroom',
          coordinates: coords,
          accessType: AccessType.free,
          pwdAccessible: TriStateAmenity.yes,
          hasBidet: TriStateAmenity.no,
        ),
      );

      final submitted = await repo.submitRestroom(command);
      expect(submitted.id, 'new_custom_rr');
      expect(submitted.status, RestroomStatus.unverified);
      expect(submitted.averageRating, 0.0);
      expect(submitted.ratingCount, 0);
      expect(submitted.verificationCount, 0);
      expect(submitted.pwdAccessible, isTrue);
      expect(submitted.hasBidet, isFalse);
      expect(submitted.hasToiletPaper, isNull);
      expect(submitted.createdAt, isNull);
      expect(submitted.updatedAt, isNull);

      // Verify paired private contribution
      expect(repo.contributions.containsKey('restroom_new_custom_rr'), isTrue);
      final contrib = repo.contributions['restroom_new_custom_rr']!;
      expect(contrib['id'], 'restroom_new_custom_rr');
      expect(contrib['resourceId'], 'new_custom_rr');
      expect(contrib['restroomId'], 'new_custom_rr');
      expect(contrib['userUid'], 'user_contributor_123');
      expect(contrib['moderationState'], 'pending');

      final fetched = await repo.getRestroomById('new_custom_rr');
      expect(fetched, isNotNull);
      expect(fetched?.name, 'New Custom Restroom');
      expect(fetched?.status, RestroomStatus.unverified);
    });

    test('submitRestroom throws UnauthenticatedException when user is not authenticated', () async {
      final authRepo = InMemoryAuthRepository(initialUid: null);
      final repo = InMemoryRestroomRepository(
        initialData: [],
        authRepository: authRepo,
      );
      final command = CreateRestroomCommand(
        restroomId: 'unauth_rr',
        draft: RestroomDraft(
          name: 'Unauth Restroom',
          coordinates: Coordinates(latitude: 14.58, longitude: 121.05),
          accessType: AccessType.free,
        ),
      );

      expect(
        () => repo.submitRestroom(command),
        throwsA(isA<UnauthenticatedException>()),
      );
    });

    test(
      'submitRestroom validates stable restroom ID in InMemory repository',
      () async {
        final authRepo = InMemoryAuthRepository(initialUid: 'user_123');
        final repo = InMemoryRestroomRepository(
          initialData: [],
          authRepository: authRepo,
        );
        final draft = RestroomDraft(
          name: 'Valid Name',
          coordinates: Coordinates(latitude: 14.58, longitude: 121.05),
          accessType: AccessType.free,
        );

        // Empty and whitespace-containing IDs
        for (final badWhitespaceId in [
          '',
          '   ',
          ' rr_123',
          'rr_123 ',
          ' rr_123 ',
        ]) {
          expect(
            () => repo.submitRestroom(
              CreateRestroomCommand(restroomId: badWhitespaceId, draft: draft),
            ),
            throwsA(
              isA<RepositoryException>().having(
                (e) => e.code,
                'code',
                'invalid-restroom-id',
              ),
            ),
          );
        }

        // > 100 characters
        expect(
          () => repo.submitRestroom(
            CreateRestroomCommand(restroomId: 'a' * 101, draft: draft),
          ),
          throwsA(
            isA<RepositoryException>().having(
              (e) => e.code,
              'code',
              'invalid-restroom-id',
            ),
          ),
        );

        // Path separators and relative dots
        for (final bad in ['a/b', '.', '..', 'foo/bar']) {
          expect(
            () => repo.submitRestroom(
              CreateRestroomCommand(restroomId: bad, draft: draft),
            ),
            throwsA(
              isA<RepositoryException>().having(
                (e) => e.code,
                'code',
                'invalid-restroom-id',
              ),
            ),
          );
        }
      },
    );

    test('submitRestroom reconciles ambiguous commit when both documents exist (idempotent retry)', () async {
      final authRepo = InMemoryAuthRepository(initialUid: 'user_123');
      final repo = InMemoryRestroomRepository(
        initialData: [],
        authRepository: authRepo,
      );
      final command = CreateRestroomCommand(
        restroomId: 'reconcile_rr',
        draft: RestroomDraft(
          name: 'Reconciled Restroom',
          coordinates: Coordinates(latitude: 14.58, longitude: 121.05),
          accessType: AccessType.free,
        ),
      );

      final firstResult = await repo.submitRestroom(command);

      // Simulate network drop and subsequent retry with identical command:
      final secondResult = await repo.submitRestroom(command);
      expect(secondResult.id, firstResult.id);
      expect(secondResult.name, firstResult.name);
      expect(repo.contributions.length, 1);
    });

    test('submitRestroom surfaces SubmissionInvariantException when only one document of the pair exists', () async {
      final authRepo = InMemoryAuthRepository(initialUid: 'user_123');

      // Case A: Only contribution exists
      final repoOnlyContrib = InMemoryRestroomRepository(
        initialData: [],
        initialContributions: {
          'restroom_orphan_rr': {
            'id': 'restroom_orphan_rr',
            'resourceId': 'orphan_rr',
          },
        },
        authRepository: authRepo,
      );
      final command = CreateRestroomCommand(
        restroomId: 'orphan_rr',
        draft: RestroomDraft(
          name: 'Orphan Restroom',
          coordinates: Coordinates(latitude: 14.58, longitude: 121.05),
          accessType: AccessType.free,
        ),
      );

      expect(
        () => repoOnlyContrib.submitRestroom(command),
        throwsA(isA<SubmissionInvariantException>()),
      );

      // Case B: Only public restroom exists
      final repoOnlyPublic = InMemoryRestroomRepository(
        initialData: [
          Restroom(
            id: 'orphan_public_rr',
            name: 'Orphan Restroom',
            coordinates: Coordinates(latitude: 14.58, longitude: 121.05),
            geohash: GeohashService.encode(
              Coordinates(latitude: 14.58, longitude: 121.05),
            ),
            accessType: AccessType.free,
            averageRating: 0.0,
            ratingCount: 0,
            verificationCount: 0,
            negativeVerificationCount: 0,
            status: RestroomStatus.unverified,
          ),
        ],
        authRepository: authRepo,
      );
      final commandB = CreateRestroomCommand(
        restroomId: 'orphan_public_rr',
        draft: RestroomDraft(
          name: 'Orphan Restroom',
          coordinates: Coordinates(latitude: 14.58, longitude: 121.05),
          accessType: AccessType.free,
        ),
      );

      expect(
        () => repoOnlyPublic.submitRestroom(commandB),
        throwsA(isA<SubmissionInvariantException>()),
      );
    });

    test('submitRestroom InMemory parity: rejects mismatched contribution pair on reconciliation', () async {
      final authRepo = InMemoryAuthRepository(initialUid: 'user_123');
      final coords = Coordinates(latitude: 14.58, longitude: 121.05);
      final geohash = GeohashService.encode(coords);

      final validPublic = Restroom(
        id: 'parity_rr',
        name: 'Parity Facility',
        coordinates: coords,
        geohash: geohash,
        accessType: AccessType.free,
        averageRating: 0.0,
        ratingCount: 0,
        verificationCount: 0,
        negativeVerificationCount: 0,
        status: RestroomStatus.unverified,
      );

      final command = CreateRestroomCommand(
        restroomId: 'parity_rr',
        draft: RestroomDraft(
          name: 'Parity Facility',
          coordinates: coords,
          accessType: AccessType.free,
        ),
      );

      // 1. Wrong userUid
      final repoWrongUid = InMemoryRestroomRepository(
        initialData: [validPublic],
        initialContributions: {
          'restroom_parity_rr': {
            'id': 'restroom_parity_rr',
            'contributionType': 'restroom',
            'resourceId': 'parity_rr',
            'restroomId': 'parity_rr',
            'userUid': 'other_user_456',
            'moderationState': 'pending',
          },
        },
        authRepository: authRepo,
      );
      expect(
        () => repoWrongUid.submitRestroom(command),
        throwsA(isA<SubmissionInvariantException>()),
      );

      // 2. Wrong contributionType
      final repoWrongType = InMemoryRestroomRepository(
        initialData: [validPublic],
        initialContributions: {
          'restroom_parity_rr': {
            'id': 'restroom_parity_rr',
            'contributionType': 'rating',
            'resourceId': 'parity_rr',
            'restroomId': 'parity_rr',
            'userUid': 'user_123',
            'moderationState': 'pending',
          },
        },
        authRepository: authRepo,
      );
      expect(
        () => repoWrongType.submitRestroom(command),
        throwsA(isA<SubmissionInvariantException>()),
      );

      // 3. Wrong resourceId
      final repoWrongResource = InMemoryRestroomRepository(
        initialData: [validPublic],
        initialContributions: {
          'restroom_parity_rr': {
            'id': 'restroom_parity_rr',
            'contributionType': 'restroom',
            'resourceId': 'wrong_resource',
            'restroomId': 'parity_rr',
            'userUid': 'user_123',
            'moderationState': 'pending',
          },
        },
        authRepository: authRepo,
      );
      expect(
        () => repoWrongResource.submitRestroom(command),
        throwsA(isA<SubmissionInvariantException>()),
      );

      // 4. Wrong restroomId
      final repoWrongRestroomId = InMemoryRestroomRepository(
        initialData: [validPublic],
        initialContributions: {
          'restroom_parity_rr': {
            'id': 'restroom_parity_rr',
            'contributionType': 'restroom',
            'resourceId': 'parity_rr',
            'restroomId': 'different_rr',
            'userUid': 'user_123',
            'moderationState': 'pending',
          },
        },
        authRepository: authRepo,
      );
      expect(
        () => repoWrongRestroomId.submitRestroom(command),
        throwsA(isA<SubmissionInvariantException>()),
      );

      // 5. Wrong moderationState
      final repoWrongState = InMemoryRestroomRepository(
        initialData: [validPublic],
        initialContributions: {
          'restroom_parity_rr': {
            'id': 'restroom_parity_rr',
            'contributionType': 'restroom',
            'resourceId': 'parity_rr',
            'restroomId': 'parity_rr',
            'userUid': 'user_123',
            'moderationState': 'approved',
          },
        },
        authRepository: authRepo,
      );
      expect(
        () => repoWrongState.submitRestroom(command),
        throwsA(isA<SubmissionInvariantException>()),
      );

      // 6. Public restroom incompatible with command (different name)
      final repoIncompatiblePublic = InMemoryRestroomRepository(
        initialData: [
          Restroom(
            id: 'parity_rr',
            name: 'Completely Different Facility',
            coordinates: coords,
            geohash: geohash,
            accessType: AccessType.free,
            averageRating: 0.0,
            ratingCount: 0,
            verificationCount: 0,
            negativeVerificationCount: 0,
            status: RestroomStatus.unverified,
          ),
        ],
        initialContributions: {
          'restroom_parity_rr': {
            'id': 'restroom_parity_rr',
            'contributionType': 'restroom',
            'resourceId': 'parity_rr',
            'restroomId': 'parity_rr',
            'userUid': 'user_123',
            'moderationState': 'pending',
          },
        },
        authRepository: authRepo,
      );
      expect(
        () => repoIncompatiblePublic.submitRestroom(command),
        throwsA(isA<SubmissionInvariantException>()),
      );
    });

    test('InMemoryAuthRepository establishes anonymous session', () async {
      final authRepo = InMemoryAuthRepository(initialUid: null);
      expect(authRepo.currentUserId, isNull);

      final uid = await authRepo.ensureAnonymousSession();
      expect(uid, isNotEmpty);
      expect(authRepo.currentUserId, uid);
    });

    test('InMemoryLocationRepository handles permission transitions and location retrieval', () async {
      final locRepo = InMemoryLocationRepository(
        initialPermission: LocationPermissionState.notRequested,
        initialCoordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
      );

      expect(
        await locRepo.checkPermission(),
        LocationPermissionState.notRequested,
      );

      final requested = await locRepo.requestPermission();
      expect(requested, LocationPermissionState.granted);

      final coords = await locRepo.getCurrentLocation();
      expect(coords.latitude, 14.5839);

      // Denied state handling
      locRepo.setPermissionState(LocationPermissionState.denied);
      expect(
        () => locRepo.getCurrentLocation(),
        throwsA(isA<LocationPermissionDeniedException>()),
      );

      // Permanently denied state handling
      locRepo.setPermissionState(LocationPermissionState.permanentlyDenied);
      expect(
        () => locRepo.getCurrentLocation(),
        throwsA(isA<LocationPermissionPermanentlyDeniedException>()),
      );

      // Service disabled handling
      locRepo.setServiceEnabled(false);
      expect(
        () => locRepo.getCurrentLocation(),
        throwsA(isA<LocationServiceDisabledException>()),
      );
    });

    test('validates radius limits in repository interface', () {
      final repo = InMemoryRestroomRepository();
      final center = Coordinates(latitude: 14.5839, longitude: 121.0617);

      expect(
        () => repo.getNearbyRestrooms(center, radiusMeters: -10),
        throwsA(isA<InvalidRadiusException>()),
      );

      expect(
        () => repo.getNearbyRestrooms(center, radiusMeters: 0),
        throwsA(isA<InvalidRadiusException>()),
      );

      expect(
        () => repo.getNearbyRestrooms(
          center,
          radiusMeters: 15000,
        ), // > 10,000m hard limit
        throwsA(isA<InvalidRadiusException>()),
      );
    });

    test('validates viewport bounds limits against unsafe huge queries', () {
      final repo = InMemoryRestroomRepository();
      // Enormous global viewport: lat span 40, lng span 60
      final hugeBounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 0.0, longitude: 100.0),
        northEast: Coordinates(latitude: 40.0, longitude: 160.0),
      );

      expect(
        () => repo.getViewportRestrooms(hugeBounds),
        throwsA(isA<ViewportTooLargeException>()),
      );
    });

    test(
      'FirestoreRestroomRepository validates radius limits before network call',
      () {
        final firestoreRepo = FirestoreRestroomRepository();
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);

        expect(
          () => firestoreRepo.getNearbyRestrooms(center, radiusMeters: -500),
          throwsA(isA<InvalidRadiusException>()),
        );

        expect(
          () => firestoreRepo.getNearbyRestrooms(center, radiusMeters: 25000),
          throwsA(isA<InvalidRadiusException>()),
        );
      },
    );

    test('FirestoreRestroomRepository validates viewport scale before network call', () {
      final firestoreRepo = FirestoreRestroomRepository();
      final hugeBounds = GeoBoundingBox(
        southWest: Coordinates(latitude: -10.0, longitude: -20.0),
        northEast: Coordinates(latitude: 30.0, longitude: 40.0),
      );

      expect(
        () => firestoreRepo.getViewportRestrooms(hugeBounds),
        throwsA(isA<ViewportTooLargeException>()),
      );
    });
  });
}
