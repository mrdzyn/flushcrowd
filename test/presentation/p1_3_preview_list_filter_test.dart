import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/discovery_filters.dart';
import 'package:looradar/domain/models/discovery_result.dart';
import 'package:looradar/domain/models/enums.dart';
import 'package:looradar/domain/models/geo_bounding_box.dart';
import 'package:looradar/domain/models/restroom.dart';
import 'package:looradar/presentation/components/bottom_sheets/filter_bottom_sheet.dart';
import 'package:looradar/presentation/components/bottom_sheets/nearby_restrooms_sheet.dart';
import 'package:looradar/presentation/components/bottom_sheets/restroom_preview_sheet.dart';
import 'package:looradar/presentation/state/map_discovery_notifier.dart';

import 'map_discovery_notifier_test.dart';

Restroom _testRestroom({
  required String id,
  required String name,
  double latitude = 14.5800,
  double longitude = 121.0500,
  String? buildingName,
  String? buildingSection,
  String? floor,
  String? unitOrArea,
  String? landmark,
  String? directionsNote,
  AccessType accessType = AccessType.free,
  double? feeAmount,
  String? feeCurrency,
  bool male = true,
  bool female = true,
  bool allGender = false,
  bool pwdAccessible = false,
  bool babyChanging = false,
  bool hasBidet = false,
  bool hasToiletPaper = true,
  bool hasSoap = true,
  bool hasHandDryer = false,
  double averageRating = 4.5,
  int ratingCount = 12,
  int verificationCount = 5,
  DateTime? lastVerifiedAt,
}) {
  return Restroom(
    id: id,
    name: name,
    coordinates: Coordinates(latitude: latitude, longitude: longitude),
    geohash: 'wdw4fq',
    buildingName: buildingName,
    buildingSection: buildingSection,
    floor: floor,
    unitOrArea: unitOrArea,
    landmark: landmark,
    directionsNote: directionsNote,
    accessType: accessType,
    feeAmount: feeAmount,
    feeCurrency: feeCurrency,
    male: male,
    female: female,
    allGender: allGender,
    pwdAccessible: pwdAccessible,
    babyChanging: babyChanging,
    hasBidet: hasBidet,
    hasToiletPaper: hasToiletPaper,
    hasSoap: hasSoap,
    hasHandDryer: hasHandDryer,
    averageRating: averageRating,
    ratingCount: ratingCount,
    verificationCount: verificationCount,
    lastVerifiedAt: lastVerifiedAt,
  );
}

void main() {
  group('P1.3A — Restroom Preview Sheet', () {
    late Restroom fullRestroom;
    late Restroom minimalRestroom;
    final userCoords = Coordinates(latitude: 14.5805, longitude: 121.0505);

    setUp(() {
      fullRestroom = _testRestroom(
        id: 'rr_full',
        name: 'Megamall North Restroom',
        buildingName: 'SM Megamall',
        buildingSection: 'Building B',
        floor: '4F',
        unitOrArea: 'Unit 402',
        landmark: 'Cinema Lobby',
        directionsNote: 'Beside Cinema 4 escalator',
        accessType: AccessType.paid,
        feeAmount: 10.0,
        feeCurrency: 'PHP',
        pwdAccessible: true,
        babyChanging: true,
        hasBidet: true,
        hasHandDryer: true,
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      minimalRestroom = _testRestroom(
        id: 'rr_minimal',
        name: 'Public Park Restroom',
      );
    });

    testWidgets('1. Marker selection exposes correct restroom in preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestroomPreviewSheet(
              restroom: fullRestroom,
              userLocation: userCoords,
            ),
          ),
        ),
      );

      expect(find.text('Megamall North Restroom'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(12)'), findsOneWidget);
    });

    testWidgets('2. Preview renders supported metadata and indoor hierarchy', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestroomPreviewSheet(
              restroom: fullRestroom,
              userLocation: userCoords,
            ),
          ),
        ),
      );

      expect(
        find.text('SM Megamall · Building B · 4F · Unit 402'),
        findsOneWidget,
      );
      expect(find.text('Near Cinema Lobby'), findsOneWidget);
      expect(find.text('Beside Cinema 4 escalator'), findsOneWidget);
      expect(find.text('PWD Accessible'), findsOneWidget);
      expect(find.text('Baby Changing'), findsOneWidget);
      expect(find.text('Bidet'), findsOneWidget);
      expect(find.text('Hand Dryer'), findsOneWidget);
      expect(find.text('PHP 10.00'), findsOneWidget);
      expect(find.text('Get Directions'), findsOneWidget);
    });

    testWidgets('3. Missing optional metadata is omitted gracefully', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestroomPreviewSheet(
              restroom: minimalRestroom,
              userLocation: null,
            ),
          ),
        ),
      );

      expect(find.text('Public Park Restroom'), findsOneWidget);
      // Optional sections should not exist
      expect(find.textContaining('Near '), findsNothing);
      expect(find.text('Indoor Directions'), findsNothing);
      expect(find.text('PWD Accessible'), findsNothing);
      expect(find.text('Baby Changing'), findsNothing);
      expect(find.text('Bidet'), findsNothing);
    });

    testWidgets('4. Opening preview causes zero repository queries', (
      tester,
    ) async {
      final fakeRepo = FakeRestroomRepository();
      final notifier = MapDiscoveryNotifier(restroomRepository: fakeRepo);

      expect(fakeRepo.getViewportCalls, 0);
      expect(fakeRepo.getNearbyCalls, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () {
                  RestroomPreviewSheet.show(ctx, restroom: fullRestroom);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Megamall North Restroom'), findsOneWidget);
      expect(fakeRepo.getViewportCalls, 0);
      expect(fakeRepo.getNearbyCalls, 0);

      notifier.dispose();
    });
  });

  group('P1.3B — Nearby Results List Sheet', () {
    late List<Restroom> restrooms;
    final userCoords = Coordinates(latitude: 14.5800, longitude: 121.0500);

    setUp(() {
      restrooms = [
        _testRestroom(
          id: 'rr_close',
          name: 'Close Restroom',
          latitude: 14.5805,
          longitude: 121.0505,
        ),
        _testRestroom(
          id: 'rr_far',
          name: 'Far Restroom',
          latitude: 14.5900,
          longitude: 121.0600,
        ),
      ];
    });

    testWidgets('5. List uses existing discovered results', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyRestroomsSheet(
              restrooms: restrooms,
              userLocation: userCoords,
              onSelectRestroom: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Nearby Restrooms (2)'), findsOneWidget);
      expect(find.text('Close Restroom'), findsOneWidget);
      expect(find.text('Far Restroom'), findsOneWidget);
    });

    testWidgets('6. Opening list causes zero discovery reads', (tester) async {
      final fakeRepo = FakeRestroomRepository();
      expect(fakeRepo.getViewportCalls, 0);
      expect(fakeRepo.getNearbyCalls, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () {
                  NearbyRestroomsSheet.show(
                    ctx,
                    restrooms: restrooms,
                    onSelectRestroom: (_) {},
                  );
                },
                child: const Text('Show List'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show List'));
      await tester.pumpAndSettle();

      expect(find.text('Nearby Restrooms (2)'), findsOneWidget);
      expect(fakeRepo.getViewportCalls, 0);
      expect(fakeRepo.getNearbyCalls, 0);
    });

    testWidgets('7. List item selection updates canonical selection', (
      tester,
    ) async {
      Restroom? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyRestroomsSheet(
              restrooms: restrooms,
              userLocation: userCoords,
              onSelectRestroom: (r) => selected = r,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Close Restroom'));
      expect(selected?.id, 'rr_close');
    });

    test('8. Selected marker and list item remain synchronized', () async {
      final fakeRepo = FakeRestroomRepository();
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: restrooms,
      );
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      notifier.selectRestroom(restrooms.first);
      expect(notifier.selectedRestroom?.id, 'rr_close');
      expect(
        notifier.markerItems.firstWhere((m) => m.id == 'rr_close').isSelected,
        isTrue,
      );

      // Select second restroom
      notifier.selectRestroom(restrooms[1]);
      expect(notifier.selectedRestroom?.id, 'rr_far');
      expect(
        notifier.markerItems.firstWhere((m) => m.id == 'rr_far').isSelected,
        isTrue,
      );
      expect(
        notifier.markerItems.firstWhere((m) => m.id == 'rr_close').isSelected,
        isFalse,
      );

      notifier.dispose();
    });

    test('9. Deterministic ordering: distance when location available', () {
      final list = List<Restroom>.from(restrooms);
      list.sort((a, b) => a.name.compareTo(b.name));
      expect(list.first.id, 'rr_close');
    });

    testWidgets('10. Distance omitted cleanly when location unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyRestroomsSheet(
              restrooms: restrooms,
              userLocation: null,
              onSelectRestroom: (_) {},
            ),
          ),
        ),
      );

      expect(find.textContaining(' m'), findsNothing);
      expect(find.textContaining(' km'), findsNothing);
    });
  });

  group('P1.3C — Local Filters and Discovery Semantics', () {
    late FakeRestroomRepository fakeRepo;
    late List<Restroom> dataset;

    setUp(() {
      fakeRepo = FakeRestroomRepository();
      dataset = [
        _testRestroom(
          id: 'rr_1',
          name: 'Free PWD Restroom',
          accessType: AccessType.free,
          pwdAccessible: true,
          hasBidet: true,
          female: true,
          male: false,
          allGender: false,
          averageRating: 4.8,
        ),
        _testRestroom(
          id: 'rr_2',
          name: 'Paid All-Gender Restroom',
          accessType: AccessType.paid,
          pwdAccessible: false,
          hasBidet: false,
          female: true,
          male: true,
          allGender: true,
          averageRating: 3.5,
        ),
        _testRestroom(
          id: 'rr_3',
          name: 'Customer Only Restroom',
          accessType: AccessType.customerOnly,
          pwdAccessible: true,
          hasBidet: false,
          babyChanging: true,
          female: true,
          male: true,
          allGender: false,
          averageRating: 4.2,
        ),
      ];
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: dataset,
      );
    });

    test('11. Single amenity filter matches correctly', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.discoveredRestrooms.length, 3);
      expect(notifier.visibleRestrooms.length, 3);

      // Filter: bidet only
      notifier.setFilters(const DiscoveryFilters(bidetOnly: true));
      expect(notifier.visibleRestrooms.length, 1);
      expect(notifier.visibleRestrooms.first.id, 'rr_1');

      notifier.dispose();
    });

    test('12. Multiple values within category use OR semantics', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Access types: Free OR Paid
      notifier.setFilters(
        const DiscoveryFilters(accessTypes: {AccessType.free, AccessType.paid}),
      );
      expect(notifier.visibleRestrooms.length, 2);
      expect(notifier.visibleRestrooms.map((r) => r.id).toSet(), {
        'rr_1',
        'rr_2',
      });

      notifier.dispose();
    });

    test('13. Filters across categories combine with AND semantics', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // PWD Accessible AND (Customer-only)
      notifier.setFilters(
        const DiscoveryFilters(
          pwdAccessibleOnly: true,
          accessTypes: {AccessType.customerOnly},
        ),
      );
      expect(notifier.visibleRestrooms.length, 1);
      expect(notifier.visibleRestrooms.first.id, 'rr_3');

      notifier.dispose();
    });

    test('14. Reset filters restores unfiltered results immediately with zero reads', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final initialReads = fakeRepo.getViewportCalls;

      notifier.setFilters(const DiscoveryFilters(bidetOnly: true));
      expect(notifier.visibleRestrooms.length, 1);

      notifier.resetFilters();
      expect(notifier.visibleRestrooms.length, 3);
      expect(fakeRepo.getViewportCalls, initialReads);

      notifier.dispose();
    });

    test('15. Zero-match filtered state sets isFilteredEmpty without claiming geographic emptiness', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Filter: rating >= 5.0 (none matches)
      notifier.setFilters(const DiscoveryFilters(minRating: 5.0));

      expect(notifier.discoveredRestrooms.length, 3);
      expect(notifier.visibleRestrooms.isEmpty, isTrue);
      expect(notifier.isFilteredEmpty, isTrue);
      expect(notifier.isEmpty, isFalse); // Geographic discovery is not empty!

      notifier.dispose();
    });

    test('16. Selected restroom clears safely when filtered out without auto-selecting next', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Explicit user selection of rr_2
      notifier.selectRestroom(dataset[1]);
      expect(notifier.selectedRestroom?.id, 'rr_2');

      // Filter: only bidet (rr_1 matches, rr_2 is excluded)
      notifier.setFilters(const DiscoveryFilters(bidetOnly: true));

      // Selection must clear to null, NOT jump to rr_1
      expect(notifier.selectedRestroom, isNull);
      expect(
        notifier.selectionOrigin,
        SelectionOrigin.clearedAfterUserSelection,
      );

      notifier.dispose();
    });

    test(
      '17. Applying filters causes zero Firestore discovery reads',
      () async {
        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: const Duration(milliseconds: 10),
        );

        final bounds = GeoBoundingBox(
          southWest: Coordinates(latitude: 14.50, longitude: 121.00),
          northEast: Coordinates(latitude: 14.60, longitude: 121.10),
        );
        notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fakeRepo.getViewportCalls, 1);

        notifier.setFilters(const DiscoveryFilters(pwdAccessibleOnly: true));
        notifier.setFilters(const DiscoveryFilters(babyChangingOnly: true));
        notifier.resetFilters();

        expect(fakeRepo.getViewportCalls, 1);
        expect(fakeRepo.getNearbyCalls, 0);

        notifier.dispose();
      },
    );

    test(
      '18. Underlying degraded discovery status remains degraded when filtered',
      () async {
        fakeRepo.viewportResultToReturn = DiscoveryResult.partial(
          items: dataset,
          reason: DiscoveryCompletenessReason.rangeCapExceeded,
          rangeCount: 16,
          candidateCount: 45,
        );

        final notifier = MapDiscoveryNotifier(
          restroomRepository: fakeRepo,
          debounceDuration: const Duration(milliseconds: 10),
        );

        final bounds = GeoBoundingBox(
          southWest: Coordinates(latitude: 14.50, longitude: 121.00),
          northEast: Coordinates(latitude: 14.60, longitude: 121.10),
        );
        notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(notifier.status, DiscoveryStatus.loadedDegraded);
        expect(notifier.isDegraded, isTrue);

        notifier.setFilters(const DiscoveryFilters(bidetOnly: true));
        expect(notifier.status, DiscoveryStatus.loadedDegraded);
        expect(notifier.isDegraded, isTrue);
        expect(
          notifier.completenessReason,
          DiscoveryCompletenessReason.rangeCapExceeded,
        );

        notifier.dispose();
      },
    );

    test('19. Local text search filters by restroom name', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      notifier.setSearchQuery('paid');
      expect(notifier.visibleRestrooms.length, 1);
      expect(notifier.visibleRestrooms.first.id, 'rr_2');

      notifier.dispose();
    });

    test('20. Local text search filters by building and context', () async {
      final datasetWithContext = [
        _testRestroom(
          id: 'rr_mall',
          name: 'Restroom 1',
          buildingName: 'Ayala Malls Manila Bay',
          landmark: 'Activity Center',
        ),
        _testRestroom(
          id: 'rr_airport',
          name: 'Restroom 2',
          buildingName: 'NAIA Terminal 3',
          landmark: 'Gate 115',
        ),
      ];
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: datasetWithContext,
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      notifier.setSearchQuery('ayala');
      expect(notifier.visibleRestrooms.length, 1);
      expect(notifier.visibleRestrooms.first.id, 'rr_mall');

      notifier.setSearchQuery('gate 115');
      expect(notifier.visibleRestrooms.length, 1);
      expect(notifier.visibleRestrooms.first.id, 'rr_airport');

      notifier.dispose();
    });

    test('21. Local search and filters compose predictably', () async {
      final datasetComposite = [
        _testRestroom(
          id: 'rr_a',
          name: 'Central Mall Free',
          accessType: AccessType.free,
          pwdAccessible: true,
        ),
        _testRestroom(
          id: 'rr_b',
          name: 'Central Mall Paid',
          accessType: AccessType.paid,
          pwdAccessible: true,
        ),
        _testRestroom(
          id: 'rr_c',
          name: 'Other Place Free',
          accessType: AccessType.free,
          pwdAccessible: false,
        ),
      ];
      fakeRepo.viewportResultToReturn = DiscoveryResult.complete(
        items: datasetComposite,
      );

      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Search 'central' -> rr_a and rr_b
      notifier.setSearchQuery('central');
      expect(notifier.visibleRestrooms.length, 2);

      // Add filter: AccessType.free -> only rr_a
      notifier.setFilters(
        const DiscoveryFilters(accessTypes: {AccessType.free}),
      );
      expect(notifier.visibleRestrooms.length, 1);
      expect(notifier.visibleRestrooms.first.id, 'rr_a');

      notifier.dispose();
    });

    test('22. Search reset restores unfiltered results', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      notifier.setSearchQuery('paid');
      expect(notifier.visibleRestrooms.length, 1);

      notifier.setSearchQuery('');
      expect(notifier.visibleRestrooms.length, 3);

      notifier.dispose();
    });

    test('23. Local search causes zero Firestore discovery reads', () async {
      final notifier = MapDiscoveryNotifier(
        restroomRepository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final bounds = GeoBoundingBox(
        southWest: Coordinates(latitude: 14.50, longitude: 121.00),
        northEast: Coordinates(latitude: 14.60, longitude: 121.10),
      );
      notifier.onCameraIdle(bounds: bounds, zoom: 15.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(fakeRepo.getViewportCalls, 1);

      notifier.setSearchQuery('central');
      notifier.setSearchQuery('terminal');
      notifier.setSearchQuery('');

      expect(fakeRepo.getViewportCalls, 1);
      expect(fakeRepo.getNearbyCalls, 0);

      notifier.dispose();
    });
  });

  group('P1.3 UI Components — FilterBottomSheet Widget Tests', () {
    testWidgets('FilterBottomSheet renders sections and invokes callbacks', (
      tester,
    ) async {
      DiscoveryFilters? applied;
      bool resetCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterBottomSheet(
              initialFilters: DiscoveryFilters.empty,
              onApply: (f) => applied = f,
              onReset: () => resetCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Access & Pricing'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('PWD Accessible'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);

      // Tap 'Free' and 'PWD Accessible'
      await tester.tap(find.text('Free'));
      await tester.tap(find.text('PWD Accessible'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(applied?.accessTypes.contains(AccessType.free), isTrue);
      expect(applied?.pwdAccessibleOnly, isTrue);
      expect(resetCalled, isFalse);
    });

    testWidgets('FilterBottomSheet invokes onReset callback', (tester) async {
      bool resetCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterBottomSheet(
              initialFilters: const DiscoveryFilters(pwdAccessibleOnly: true),
              onApply: (_) {},
              onReset: () => resetCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(resetCalled, isTrue);
    });
  });
}
