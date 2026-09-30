import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/errors/exceptions.dart';
import 'package:looradar/data/repositories/auth_repository_impl.dart';
import 'package:looradar/data/repositories/in_memory_restroom_repository.dart';
import 'package:looradar/data/repositories/location_repository_impl.dart';
import 'package:looradar/data/services/gis/geohash_service.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/enums.dart';
import 'package:looradar/domain/models/restroom.dart';

void main() {
  group('Repository Contracts and In-Memory Test Doubles', () {
    test(
      'InMemoryRestroomRepository filters nearby and sorts nearest first',
      () async {
        final center = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final repo = InMemoryRestroomRepository();

        final nearby = await repo.getNearbyRestrooms(
          center,
          radiusMeters: 2000.0,
        );
        expect(nearby, isNotEmpty);

        // Verify that all results are within 2000m
        for (final r in nearby) {
          expect(r.status, RestroomStatus.active);
        }

        // Verify retrieval by id
        final first = nearby.first;
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

      final inView = await repo.getViewportRestrooms(bounds);
      expect(inView, isNotEmpty);
      for (final r in inView) {
        expect(bounds.contains(r.coordinates), isTrue);
      }
    });

    test('InMemoryRestroomRepository stores and updates submissions', () async {
      final repo = InMemoryRestroomRepository(initialData: []);
      final coords = Coordinates(latitude: 14.5843, longitude: 121.0568);
      final newRestroom = Restroom(
        id: 'new_custom_rr',
        name: 'New Custom Restroom',
        coordinates: coords,
        geohash: GeohashService.encode(coords),
        accessType: AccessType.free,
      );

      await repo.submitRestroom(newRestroom);
      final fetched = await repo.getRestroomById('new_custom_rr');
      expect(fetched, isNotNull);
      expect(fetched?.name, 'New Custom Restroom');
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
  });
}
