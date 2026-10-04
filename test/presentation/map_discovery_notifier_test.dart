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

    test('24. MAJOR-3: selected restroom cleared when not in new results without jumping to first, and stays unselected', () async {
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
      expect(notifier.selectionOrigin, SelectionOrigin.user);
      expect(notifier.selectionIsUserInitiated, isTrue);

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
      expect(
        notifier.selectionOrigin,
        SelectionOrigin.clearedAfterUserSelection,
      );
      expect(notifier.selectionIsUserInitiated, isFalse);
      expect(notifier.discoveredRestrooms.length, 2);

      // Third query returns yet another set of restrooms
      final rr5 = _sampleRestroom('rr_5');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(items: [rr5]);
      final pannedBounds2 = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.6200, longitude: 121.0900),
        northEast: Coordinates(latitude: 14.6300, longitude: 121.1000),
      );
      notifier.onCameraIdle(bounds: pannedBounds2, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // Selection must STAY null — auto-selection must NOT resume!
      expect(notifier.selectedRestroom, isNull);
      expect(
        notifier.selectionOrigin,
        SelectionOrigin.clearedAfterUserSelection,
      );

      // User subsequently selects rr_5 explicitly
      notifier.selectRestroom(rr5);
      expect(notifier.selectedRestroom?.id, 'rr_5');
      expect(notifier.selectionOrigin, SelectionOrigin.user);
      expect(notifier.selectionIsUserInitiated, isTrue);

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

    test('26. MAJOR-2: Complete A -> start B -> invalidate B -> return to A restores loadedComplete without querying', () async {
      final rrA = _sampleRestroom('rr_A');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rrA],
        rangeCount: 3,
        candidateCount: 8,
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // 1. Viewport A executes and completes
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 1);
      expect(notifier.status, DiscoveryStatus.loadedComplete);
      expect(notifier.discoveredRestrooms.length, 1);

      // 2. Query B starts (in-flight)
      final boundsB = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.6500, longitude: 121.1200),
        northEast: Coordinates(latitude: 14.6600, longitude: 121.1300),
      );
      fakeRepo.viewportCompleter = Completer<DiscoveryResult<Restroom>>();
      notifier.onCameraIdle(bounds: boundsB, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 2);
      expect(notifier.isLoading, isTrue);

      // 3. User moves camera back, invalidating B
      notifier.onCameraMoveStarted();

      // 4. User settles back on viewport equivalent to A
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // 5. No new repository query should have been made
      expect(fakeRepo.getViewportCalls, 2);
      // Status must be restored to loadedComplete (not stuck in loading!)
      expect(notifier.status, DiscoveryStatus.loadedComplete);
      expect(notifier.discoveredRestrooms.first.id, 'rr_A');
      expect(notifier.rangeCount, 3);
      expect(notifier.candidateCount, 8);

      notifier.dispose();
    });

    test('27. MAJOR-2: Degraded A -> leave A -> return to equivalent A restores loadedDegraded and metadata', () async {
      final rrDegraded = _sampleRestroom('rr_degraded');
      fakeRepo.viewportResultToReturn = DiscoveryResult.partial(
        items: [rrDegraded],
        reason: DiscoveryCompletenessReason.rangeCapExceeded,
        rangeCount: 16,
        candidateCount: 150,
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // 1. Viewport A executes and completes degraded
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 1);
      expect(notifier.status, DiscoveryStatus.loadedDegraded);
      expect(notifier.isDegraded, isTrue);
      expect(
        notifier.completenessReason,
        DiscoveryCompletenessReason.rangeCapExceeded,
      );

      // 2. Leave A and invalidate
      notifier.onCameraMoveStarted();

      // 3. Return to equivalent A
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // Repos call count still 1
      expect(fakeRepo.getViewportCalls, 1);
      // State restored to loadedDegraded with completeness reason preserved
      expect(notifier.status, DiscoveryStatus.loadedDegraded);
      expect(notifier.isDegraded, isTrue);
      expect(
        notifier.completenessReason,
        DiscoveryCompletenessReason.rangeCapExceeded,
      );
      expect(notifier.rangeCount, 16);
      expect(notifier.candidateCount, 150);

      notifier.dispose();
    });

    test('28. MAJOR-2: Empty A -> leave -> return restores empty status without new query', () async {
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(items: []);

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 1);
      expect(notifier.status, DiscoveryStatus.empty);

      // Invalidate via camera move
      notifier.onCameraMoveStarted();

      // Return to equivalent A
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 1);
      expect(notifier.status, DiscoveryStatus.empty);
      expect(notifier.discoveredRestrooms, isEmpty);

      notifier.dispose();
    });

    test('29. MAJOR-2: Complete A -> zoom below min (suppressed) -> return to equivalent A restores complete and unsuppresses', () async {
      final rrA = _sampleRestroom('rr_A');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(items: [rrA]);

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // 1. Viewport A executes and completes
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 1);
      expect(notifier.status, DiscoveryStatus.loadedComplete);

      // 2. Zoom out below minimum -> suppressed
      notifier.onCameraIdle(bounds: standardBounds, zoom: 10.0);
      expect(notifier.status, DiscoveryStatus.suppressed);
      expect(notifier.isSuppressed, isTrue);

      // 3. Zoom back into equivalent A
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // No new query
      expect(fakeRepo.getViewportCalls, 1);
      // Status must be restored to loadedComplete, NOT stuck in suppressed
      expect(notifier.status, DiscoveryStatus.loadedComplete);
      expect(notifier.isSuppressed, isFalse);
      expect(notifier.discoveredRestrooms.first.id, 'rr_A');

      notifier.dispose();
    });

    test('30. MAJOR-2: Reuse does NOT restore snapshot for materially different descriptor', () async {
      final rrA = _sampleRestroom('rr_A');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(items: [rrA]);

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // 1. Viewport A executes and completes
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 1);

      // 2. Query B with materially different bounds executes a real query
      final rrB = _sampleRestroom('rr_B');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(items: [rrB]);
      final boundsB = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.6500, longitude: 121.1200),
        northEast: Coordinates(latitude: 14.6600, longitude: 121.1300),
      );
      notifier.onCameraIdle(bounds: boundsB, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 2);
      expect(notifier.discoveredRestrooms.first.id, 'rr_B');

      notifier.dispose();
    });

    test('31. MAJOR-1: Normal map startup issues only one viewport discovery call and zero nearby calls', () async {
      final rr = _sampleRestroom('rr_startup');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(items: [rr]);

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // Normal map startup lifecycle:
      // GoogleMap widget is created, camera settles at initial position,
      // and triggers onCameraIdle. There is NO automatic loadNearbyRestrooms called.
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // Exact call assertions:
      expect(fakeRepo.getViewportCalls, 1);
      expect(fakeRepo.getNearbyCalls, 0);
      expect(notifier.status, DiscoveryStatus.loadedComplete);

      notifier.dispose();
    });

    test('32. Permission grant flow animates camera and converges on viewport discovery with zero nearby calls', () async {
      final rrUser = _sampleRestroom('rr_user_loc');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rrUser],
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // 1. Initial startup at default coordinates (manual exploration):
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 1);
      expect(fakeRepo.getNearbyCalls, 0);

      // 2. User grants location permission:
      // Map screen animates camera to user's location.
      // In-flight debounce/query on previous region is cancelled or superseded.
      // When camera arrives at user location, onCameraIdle fires with user location bounds.
      final userLocationBounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.5500, longitude: 121.0200),
        northEast: Coordinates(latitude: 14.5600, longitude: 121.0300),
      );

      notifier.onCameraMoveStarted();
      notifier.onCameraMove();
      notifier.onCameraIdle(bounds: userLocationBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // Discovery must happen purely through viewport query; zero nearby calls:
      expect(fakeRepo.getViewportCalls, 2);
      expect(fakeRepo.getNearbyCalls, 0);
      expect(fakeRepo.requestedBounds.last, userLocationBounds);
      expect(notifier.status, DiscoveryStatus.loadedComplete);
      expect(notifier.discoveredRestrooms.first.id, 'rr_user_loc');

      notifier.dispose();
    });

    test('33. Denied permission preserves manual exploration with zero nearby calls', () async {
      final rrManual = _sampleRestroom('rr_manual');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rrManual],
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // Startup in denied/fallback exploration mode
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 1);
      expect(fakeRepo.getNearbyCalls, 0);

      // Pan around manually
      final pannedBounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.6000, longitude: 121.0700),
        northEast: Coordinates(latitude: 14.6100, longitude: 121.0800),
      );
      notifier.onCameraMoveStarted();
      notifier.onCameraMove();
      notifier.onCameraIdle(bounds: pannedBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 2);
      expect(fakeRepo.getNearbyCalls, 0);
      expect(fakeRepo.requestedBounds.last, pannedBounds);

      notifier.dispose();
    });

    test('34. Recenter button flow animates camera and converges on viewport discovery with zero nearby calls', () async {
      final rrRecentered = _sampleRestroom('rr_recentered');
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: [rrRecentered],
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: testDebounce,
      );

      // 1. Initial state
      notifier.onCameraIdle(bounds: standardBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(fakeRepo.getViewportCalls, 1);
      expect(fakeRepo.getNearbyCalls, 0);

      // 2. User presses recenter button:
      // MapDiscoveryScreen._recenterOnUser() fetches coordinates and animates camera.
      // Moving camera fires onCameraMoveStarted(), then settles at user position with onCameraIdle().
      final recenteredBounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.5200, longitude: 121.0100),
        northEast: Coordinates(latitude: 14.5300, longitude: 121.0200),
      );
      notifier.onCameraMoveStarted();
      notifier.onCameraIdle(bounds: recenteredBounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(fakeRepo.getViewportCalls, 2);
      expect(fakeRepo.getNearbyCalls, 0);
      expect(fakeRepo.requestedBounds.last, recenteredBounds);
      expect(notifier.discoveredRestrooms.first.id, 'rr_recentered');

      notifier.dispose();
    });
  });
}
