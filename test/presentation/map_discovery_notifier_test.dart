import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/constants/app_constants.dart';
import 'package:looradar/core/errors/exceptions.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/discovery_result.dart';
import 'package:looradar/domain/models/geo_bounding_box.dart';
import 'package:looradar/domain/models/restroom.dart';
import 'package:looradar/domain/repositories/restroom_repository.dart';
import 'package:looradar/presentation/state/map_discovery_notifier.dart';
import 'package:looradar/presentation/state/viewport_query_descriptor.dart';

class FakeRestroomRepository implements RestroomRepository {
  int getNearbyCalls = 0;
  int getViewportCalls = 0;
  final List<GeoBoundingBox> requestedBounds = [];
  final List<Coordinates> requestedCenters = [];

  DiscoveryResult<Restroom>? nearbyResultToReturn;
  DiscoveryResult<Restroom>? viewportResultToReturn;
  Exception? exceptionToThrow;

  Completer<DiscoveryResult<Restroom>>? viewportCompleter;

  @override
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    getNearbyCalls++;
    requestedCenters.add(center);
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    return nearbyResultToReturn ?? DiscoveryResult.complete(items: []);
  }

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async {
    getViewportCalls++;
    requestedBounds.add(bounds);
    if (viewportCompleter != null) {
      return viewportCompleter!.future;
    }
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    return viewportResultToReturn ?? DiscoveryResult.complete(items: []);
  }

  @override
  Future<Restroom?> getRestroomById(String id) async => null;

  @override
  Future<void> submitRestroom(Restroom restroom) async {}
}

Restroom _sampleRestroom(String id, {String name = 'Test Restroom'}) {
  return Restroom(
    id: id,
    name: name,
    coordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
    geohash: 'wdw4fq',
  );
}

void main() {
  group('MapDiscoveryNotifier Query Orchestration', () {
    late FakeRestroomRepository fakeRepo;
    const testDebounce = Duration(milliseconds: 50);

    final standardBounds = GeoBoundingBox(
      southWest: Coordinates(latitude: 14.5800, longitude: 121.0500),
      northEast: Coordinates(latitude: 14.5900, longitude: 121.0600),
    );

    setUp(() {
      fakeRepo = FakeRestroomRepository();
    });

    test('1. no repository call during camera movement', () {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraMoveStarted();
      notifier.onCameraMove();
      notifier.onCameraMove();

      expect(fakeRepo.getViewportCalls, 0);
      expect(fakeRepo.getNearbyCalls, 0);
      notifier.dispose();
    });

    test('2. camera idle triggers query after debounce', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      expect(fakeRepo.getViewportCalls, 0);

      // Wait for debounce window
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 1);
      expect(notifier.status, DiscoveryStatus.empty);
      notifier.dispose();
    });

    test(
      '3. multiple idle events inside debounce window collapse to one query',
      () async {
        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: testDebounce,
        );

        final bounds2 = GeoBoundingBox(
          southWest: Coordinates(latitude: 14.5810, longitude: 121.0510),
          northEast: Coordinates(latitude: 14.5910, longitude: 121.0610),
        );

        notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // Second idle event resets debounce timer
        notifier.onCameraIdle(bounds: bounds2, zoom: 15.0);

        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(fakeRepo.getViewportCalls, 1);
        expect(fakeRepo.requestedBounds.first, bounds2);
        notifier.dispose();
      },
    );

    test('4. moving camera cancels pending debounce', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Camera starts moving again
      notifier.onCameraMoveStarted();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fakeRepo.getViewportCalls, 0);
      notifier.dispose();
    });

    test(
      '5. identical/equivalent viewport suppresses duplicate query',
      () async {
        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: testDebounce,
        );

        // First query executes
        notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(fakeRepo.getViewportCalls, 1);

        // Programmatic recentering or duplicate idle with effectively equivalent bounds (~5m diff)
        final tinyShiftBounds = GeoBoundingBox(
          southWest: Coordinates(
            latitude:
                14.5800 +
                ViewportQueryDescriptor.coordinateToleranceDegrees / 2,
            longitude: 121.0500,
          ),
          northEast: Coordinates(latitude: 14.5900, longitude: 121.0600),
        );

        notifier.onCameraIdle(bounds: tinyShiftBounds, zoom: 15.05);
        await Future<void>.delayed(const Duration(milliseconds: 70));

        // Repositor call count should NOT increase
        expect(fakeRepo.getViewportCalls, 1);
        notifier.dispose();
      },
    );

    test('6. materially changed viewport triggers new query', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // First query
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 1);

      // Materially shifted bounds (> 0.0001 deg tolerance)
      final materiallyDifferentBounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.6000, longitude: 121.0700),
        northEast: Coordinates(latitude: 14.6100, longitude: 121.0800),
      );

      notifier.onCameraIdle(bounds: materiallyDifferentBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 2);
      notifier.dispose();
    });

    test(
      '7. explicit refresh/retry bypasses query reuse and forces query',
      () async {
        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: testDebounce,
        );

        notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(fakeRepo.getViewportCalls, 1);

        // Explicit refresh with identical bounds
        await notifier.refreshCurrentViewport(
          bounds: standardBounds,
          zoom: 15.0,
        );
        expect(fakeRepo.getViewportCalls, 2);
        notifier.dispose();
      },
    );

    test('8. zoom below minimum suppresses query without error', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 11.5);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 0);
      expect(notifier.isSuppressed, isTrue);
      expect(notifier.status, DiscoveryStatus.suppressed);
      expect(notifier.hasError, isFalse);
      notifier.dispose();
    });

    test('9. valid zoom enables query', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(
        bounds: standardBounds,
        zoom: AppConstants.minViewportZoom,
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 1);
      expect(notifier.isSuppressed, isFalse);
      notifier.dispose();
    });

    test(
      '10. oversized viewport exception transitions to suppressed state',
      () async {
        fakeRepo.exceptionToThrow = const ViewportTooLargeException(
          'Viewport too large',
        );

        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: testDebounce,
        );

        notifier.onCameraIdle(bounds: standardBounds, zoom: 14.0);
        await Future<void>.delayed(const Duration(milliseconds: 70));

        expect(fakeRepo.getViewportCalls, 1);
        expect(notifier.isSuppressed, isTrue);
        expect(notifier.status, DiscoveryStatus.suppressed);
        expect(notifier.hasError, isFalse);
        notifier.dispose();
      },
    );

    test('11. newest request wins and 12. stale success is ignored', () async {
      final completerA = Completer<DiscoveryResult<Restroom>>();
      final completerB = Completer<DiscoveryResult<Restroom>>();

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      // Request A starts
      fakeRepo.viewportCompleter = completerA;
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fakeRepo.getViewportCalls, 1);

      // Camera moves, Request B starts
      fakeRepo.viewportCompleter = completerB;
      final boundsB = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.6000, longitude: 121.0700),
        northEast: Coordinates(latitude: 14.6100, longitude: 121.0800),
      );
      notifier.onCameraIdle(bounds: boundsB, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fakeRepo.getViewportCalls, 2);

      // Request B finishes FIRST with restroom B
      final restroomB = _sampleRestroom('rr_b', name: 'Restroom B');
      completerB.complete(DiscoveryResult.complete(items: [restroomB]));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.discoveredRestrooms.length, 1);
      expect(notifier.discoveredRestrooms.first.id, 'rr_b');

      // Request A finishes LATER with restroom A
      final restroomA = _sampleRestroom('rr_a', name: 'Restroom A');
      completerA.complete(DiscoveryResult.complete(items: [restroomA]));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Assert stale request A did NOT overwrite newer request B
      expect(notifier.discoveredRestrooms.length, 1);
      expect(notifier.discoveredRestrooms.first.id, 'rr_b');
      notifier.dispose();
    });

    test(
      '13. stale error is ignored and cannot overwrite newer success',
      () async {
        final completerA = Completer<DiscoveryResult<Restroom>>();
        final completerB = Completer<DiscoveryResult<Restroom>>();

        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: const Duration(milliseconds: 10),
        );

        // Request A starts
        fakeRepo.viewportCompleter = completerA;
        notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Request B starts
        fakeRepo.viewportCompleter = completerB;
        final boundsB = GeoBoundingBox(
          southWest: Coordinates(latitude: 14.6000, longitude: 121.0700),
          northEast: Coordinates(latitude: 14.6100, longitude: 121.0800),
        );
        notifier.onCameraIdle(bounds: boundsB, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Request B succeeds
        final restroomB = _sampleRestroom('rr_b');
        completerB.complete(DiscoveryResult.complete(items: [restroomB]));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(notifier.status, DiscoveryStatus.loadedComplete);

        // Request A fails late
        completerA.completeError(Exception('Network timeout for query A'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Notifier status remains loadedComplete, NOT error
        expect(notifier.status, DiscoveryStatus.loadedComplete);
        expect(notifier.hasError, isFalse);
        notifier.dispose();
      },
    );

    test('14. latest error is exposed when current request fails', () async {
      fakeRepo.exceptionToThrow = Exception('Simulated network failure');

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(notifier.status, DiscoveryStatus.error);
      expect(notifier.hasError, isTrue);
      expect(notifier.errorMessage, contains('Simulated network failure'));
      notifier.dispose();
    });

    test('15. dispose cancels timer and prevents late state writes', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      notifier.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 0);
    });

    test(
      '16. complete DiscoveryResult becomes loadedComplete with metadata',
      () async {
        final restroom = _sampleRestroom('rr_1');
        fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [restroom],
          rangeCount: 4,
          candidateCount: 12,
        );

        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: testDebounce,
        );

        notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 70));

        expect(notifier.status, DiscoveryStatus.loadedComplete);
        expect(notifier.isComplete, isTrue);
        expect(
          notifier.completenessReason,
          DiscoveryCompletenessReason.complete,
        );
        expect(notifier.rangeCount, 4);
        expect(notifier.candidateCount, 12);
        expect(notifier.discoveredRestrooms.length, 1);
        expect(notifier.selectedRestroom?.id, 'rr_1');
        notifier.dispose();
      },
    );

    test('17. incomplete DiscoveryResult becomes loadedDegraded with reason preserved', () async {
      final restroom = _sampleRestroom('rr_degraded');
      fakeRepo.viewportResultToReturn = DiscoveryResult.partial(
        items: [restroom],
        reason: DiscoveryCompletenessReason.rangeCapExceeded,
        rangeCount: 16,
        candidateCount: 150,
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(notifier.status, DiscoveryStatus.loadedDegraded);
      expect(notifier.isDegraded, isTrue);
      expect(notifier.isComplete, isFalse);
      expect(
        notifier.completenessReason,
        DiscoveryCompletenessReason.rangeCapExceeded,
      );
      expect(notifier.rangeCount, 16);
      expect(notifier.candidateCount, 150);
      expect(notifier.discoveredRestrooms.length, 1);
      notifier.dispose();
    });

    test(
      '19. empty result becomes empty with selectedRestroom cleared',
      () async {
        fakeRepo.viewportResultToReturn = DiscoveryResult.complete(items: []);

        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: testDebounce,
        );

        notifier.selectRestroom(_sampleRestroom('prev_selected'));
        expect(notifier.selectedRestroom, isNotNull);

        notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 70));

        expect(notifier.status, DiscoveryStatus.empty);
        expect(notifier.isEmpty, isTrue);
        expect(notifier.discoveredRestrooms, isEmpty);
        expect(notifier.selectedRestroom, isNull);
        notifier.dispose();
      },
    );

    test('20. BLOCKER-1: in-flight request ignored when camera moves before completion', () async {
      fakeRepo.viewportCompleter = Completer<DiscoveryResult<Restroom>>();

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(notifier.isLoading, isTrue);

      // User starts moving the camera while request is in flight
      notifier.onCameraMoveStarted();

      // Complete the in-flight request now
      final lateRestroom = _sampleRestroom('stale_rr');
      fakeRepo.viewportCompleter!.complete(
        DiscoveryResult.complete(items: [lateRestroom]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Result must NOT be committed
      expect(notifier.discoveredRestrooms, isEmpty);
      expect(notifier.selectedRestroom, isNull);
      expect(notifier.lastExecutedDescriptor, isNull);
      notifier.dispose();
    });

    test('21. BLOCKER-1: in-flight error ignored when camera moves before completion', () async {
      fakeRepo.viewportCompleter = Completer<DiscoveryResult<Restroom>>();

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(notifier.isLoading, isTrue);

      // User starts moving the camera
      notifier.onCameraMoveStarted();

      // Complete the in-flight request with error
      fakeRepo.viewportCompleter!.completeError(
        Exception('Late network failure'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Error must NOT overwrite state
      expect(notifier.hasError, isFalse);
      expect(notifier.errorMessage, isNull);
      notifier.dispose();
    });

    test(
      '22. BLOCKER-1: in-flight request invalidated on zoom suppression',
      () async {
        fakeRepo.viewportCompleter = Completer<DiscoveryResult<Restroom>>();

        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: testDebounce,
        );

        notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 70));

        expect(notifier.isLoading, isTrue);

        // Camera zooms out below threshold
        notifier.onCameraIdle(bounds: standardBounds, zoom: 11.0);

        expect(notifier.isSuppressed, isTrue);

        // In-flight request completes
        fakeRepo.viewportCompleter!.complete(
          DiscoveryResult.complete(items: [_sampleRestroom('ignored_rr')]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Suppressed state preserved, stale items not committed
        expect(notifier.isSuppressed, isTrue);
        expect(notifier.discoveredRestrooms, isEmpty);
        notifier.dispose();
      },
    );

    test('23. MAJOR-2: selected restroom lifecycle - survives if present in new results', () async {
      final rr1 = _sampleRestroom('rr_1');
      final rr2 = _sampleRestroom('rr_2');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rr1, rr2],
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // Select rr_2 explicitly as user
      notifier.selectRestroom(rr2);
      expect(notifier.selectedRestroom?.id, 'rr_2');
      expect(notifier.selectionIsUserInitiated, isTrue);

      // Next query returns updated rr_2 and rr_3
      final rr2Updated = _sampleRestroom('rr_2', name: 'Updated RR 2');
      final rr3 = _sampleRestroom('rr_3');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rr3, rr2Updated],
      );

      await notifier.refreshCurrentViewport(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // rr_2 should be preserved (updated instance), not overwritten by first item (rr_3)
      expect(notifier.selectedRestroom?.id, 'rr_2');
      expect(notifier.selectedRestroom?.name, 'Updated RR 2');
      expect(notifier.selectionIsUserInitiated, isTrue);
      notifier.dispose();
    });

    test('24. MAJOR-2: selected restroom cleared when not in new results without jumping to first', () async {
      final rr1 = _sampleRestroom('rr_1');
      final rr2 = _sampleRestroom('rr_2');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rr1, rr2],
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // User selects rr_1
      notifier.selectRestroom(rr1);
      expect(notifier.selectedRestroom?.id, 'rr_1');

      // Next query does NOT contain rr_1 anymore (e.g. panned away)
      final rr3 = _sampleRestroom('rr_3');
      final rr4 = _sampleRestroom('rr_4');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rr3, rr4],
      );

      final pannedBounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.6000, longitude: 121.0700),
        northEast: Coordinates(latitude: 14.6100, longitude: 121.0800),
      );
      notifier.onCameraIdle(bounds: pannedBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // Selection must be cleared to null, NOT jump to rr_3
      expect(notifier.selectedRestroom, isNull);
      expect(notifier.selectionIsUserInitiated, isFalse);
      expect(notifier.discoveredRestrooms.length, 2);
      notifier.dispose();
    });

    test('25. MINOR-1: ViewportQueryDescriptor antimeridian equivalence', () {
      final descriptorA = ViewportQueryDescriptor(
        bounds: GeoBoundingBox(
          southWest: Coordinates(latitude: -10.0, longitude: 179.99995),
          northEast: Coordinates(latitude: 10.0, longitude: -179.99995),
        ),
        zoom: 15.0,
      );

      final descriptorB = ViewportQueryDescriptor(
        bounds: GeoBoundingBox(
          southWest: Coordinates(latitude: -10.0, longitude: 179.99996),
          northEast: Coordinates(latitude: 10.0, longitude: -179.99994),
        ),
        zoom: 15.0,
      );

      // Micro shift across the antimeridian within tolerance should be equivalent
      expect(descriptorA.isEffectivelyEquivalentTo(descriptorB), isTrue);

      // Opposite side or large shift should not be equivalent
      final descriptorFar = ViewportQueryDescriptor(
        bounds: GeoBoundingBox(
          southWest: Coordinates(latitude: -10.0, longitude: 170.0),
          northEast: Coordinates(latitude: 10.0, longitude: -170.0),
        ),
        zoom: 15.0,
      );
      expect(descriptorA.isEffectivelyEquivalentTo(descriptorFar), isFalse);
    });
  });
}
