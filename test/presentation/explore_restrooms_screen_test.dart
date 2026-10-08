import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flushcrowd/data/repositories/location_repository_impl.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/discovery_result.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/geo_bounding_box.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/repositories/restroom_repository.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/filter_bottom_sheet.dart';
import 'package:flushcrowd/presentation/components/feedback/error_state_view.dart';
import 'package:flushcrowd/presentation/components/feedback/loading_indicator.dart';
import 'package:flushcrowd/presentation/screens/explore_restrooms_screen.dart';
import 'package:flushcrowd/presentation/state/location_notifier.dart';
import 'package:flushcrowd/presentation/state/map_discovery_notifier.dart';

class CountingRestroomRepository implements RestroomRepository {
  int getNearbyCalls = 0;
  int getViewportCalls = 0;
  int submitCalls = 0;
  int getByIdCalls = 0;

  DiscoveryResult<Restroom>? viewportResultToReturn;
  Completer<DiscoveryResult<Restroom>>? viewportCompleter;
  Exception? exceptionToThrow;

  @override
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    getNearbyCalls++;
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return DiscoveryResult.complete(items: const []);
  }

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async {
    getViewportCalls++;
    if (viewportCompleter != null) return viewportCompleter!.future;
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return viewportResultToReturn ?? DiscoveryResult.complete(items: const []);
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    getByIdCalls++;
    return null;
  }

  @override
  Future<Restroom> submitRestroom(CreateRestroomCommand command) async {
    submitCalls++;
    throw UnimplementedError();
  }
}

Restroom _createRestroom({
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
  bool pwdAccessible = true,
  bool babyChanging = false,
  bool hasBidet = true,
  bool hasToiletPaper = true,
  bool hasSoap = true,
  bool hasHandDryer = true,
  double averageRating = 4.5,
  int ratingCount = 8,
  int verificationCount = 2,
  DateTime? lastVerifiedAt,
  RestroomStatus status = RestroomStatus.active,
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
    status: status,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

Widget _wrapWithProviders({
  required Widget child,
  required MapDiscoveryNotifier discoveryNotifier,
  required LocationNotifier locationNotifier,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MapDiscoveryNotifier>.value(
        value: discoveryNotifier,
      ),
      ChangeNotifierProvider<LocationNotifier>.value(value: locationNotifier),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('ExploreRestroomsScreen', () {
    late CountingRestroomRepository restroomRepo;
    late InMemoryLocationRepository locationRepo;
    late LocationNotifier locationNotifier;
    late MapDiscoveryNotifier discoveryNotifier;

    setUp(() {
      restroomRepo = CountingRestroomRepository();
      locationRepo = InMemoryLocationRepository(
        initialPermission: LocationPermissionState.granted,
        initialCoordinates: Coordinates(latitude: 14.5800, longitude: 121.0500),
      );
      locationNotifier = LocationNotifier(locationRepository: locationRepo);
      discoveryNotifier = MapDiscoveryNotifier(
        restroomRepository: restroomRepo,
        debounceDuration: Duration.zero,
      );
    });

    tearDown(() {
      discoveryNotifier.dispose();
      locationNotifier.dispose();
    });

    testWidgets(
      '1. Zero Firestore queries triggered solely by mounting Explore',
      (tester) async {
        final initialGetNearby = restroomRepo.getNearbyCalls;
        final initialGetViewport = restroomRepo.getViewportCalls;
        final initialGetById = restroomRepo.getByIdCalls;
        final initialSubmit = restroomRepo.submitCalls;

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(restroomRepo.getNearbyCalls, equals(initialGetNearby));
        expect(restroomRepo.getViewportCalls, equals(initialGetViewport));
        expect(restroomRepo.getByIdCalls, equals(initialGetById));
        expect(restroomRepo.submitCalls, equals(initialSubmit));
      },
    );

    testWidgets(
      '2. Renders loaded visible restrooms sorted deterministically with full context',
      (tester) async {
        final r1 = _createRestroom(
          id: 'r1',
          name: 'Greenbelt 3 Restroom',
          buildingName: 'Greenbelt Mall',
          floor: 'Level 2',
          landmark: 'Cinema wing',
          latitude: 14.5510,
          longitude: 121.0200,
          lastVerifiedAt: DateTime.now(),
        );
        final r2 = _createRestroom(
          id: 'r2',
          name: 'Ayala Station Restroom',
          buildingName: 'MRT Station',
          floor: 'Concourse',
          latitude: 14.5490,
          longitude: 121.0280,
          accessType: AccessType.paid,
          feeAmount: 10,
          feeCurrency: 'PHP',
          verificationCount: 0,
        );

        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r1, r2],
        );

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Restrooms (2)'), findsOneWidget);
        expect(find.text('Greenbelt 3 Restroom'), findsOneWidget);
        expect(find.text('Ayala Station Restroom'), findsOneWidget);

        // Verifies full context is rendered (building info, floor, landmark, verified)
        expect(find.textContaining('Greenbelt Mall'), findsOneWidget);
        expect(find.textContaining('Level 2'), findsOneWidget);
        expect(find.text('Near Cinema wing'), findsOneWidget);
        expect(find.text('Recently verified'), findsOneWidget);
        expect(find.text('Paid'), findsOneWidget);
        expect(find.text('Free'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Tapping a restroom card selects it and invokes onSelectRestroom callback',
      (tester) async {
        final r1 = _createRestroom(id: 'r1', name: 'Park Square Restroom');
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r1],
        );

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        Restroom? selectedCallbackRestroom;
        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(
              onSelectRestroom: (r) {
                selectedCallbackRestroom = r;
              },
            ),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Park Square Restroom'));
        await tester.pumpAndSettle();

        expect(selectedCallbackRestroom, isNotNull);
        expect(selectedCallbackRestroom!.id, equals('r1'));
        expect(discoveryNotifier.selectedRestroom?.id, equals('r1'));
      },
    );

    testWidgets(
      '4. Search in MapSearchBar filters list locally with zero network reads',
      (tester) async {
        final r1 = _createRestroom(id: 'r1', name: 'Alpha Mall');
        final r2 = _createRestroom(id: 'r2', name: 'Beta Tower');
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r1, r2],
        );

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final readCountBeforeSearch = restroomRepo.getViewportCalls;

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Alpha Mall'), findsOneWidget);
        expect(find.text('Beta Tower'), findsOneWidget);

        // Enter search text
        await tester.enterText(find.byType(TextField), 'Alpha');
        await tester.pumpAndSettle();

        expect(find.text('Alpha Mall'), findsOneWidget);
        expect(find.text('Beta Tower'), findsNothing);
        expect(restroomRepo.getViewportCalls, equals(readCountBeforeSearch));
      },
    );

    testWidgets('5. Tapping filter icon opens FilterBottomSheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          child: const ExploreRestroomsScreen(),
          discoveryNotifier: discoveryNotifier,
          locationNotifier: locationNotifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(FilterBottomSheet), findsOneWidget);
    });

    testWidgets(
      '6. Geographic empty state displays EmptyStateView and triggers onSwitchToMap',
      (tester) async {
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: const [],
        );

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        bool switchedToMap = false;
        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(
              onSwitchToMap: () => switchedToMap = true,
            ),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No Restrooms Found Nearby'), findsOneWidget);
        expect(find.text('Explore on Map'), findsOneWidget);

        await tester.tap(find.text('Explore on Map'));
        await tester.pumpAndSettle();

        expect(switchedToMap, isTrue);
      },
    );

    testWidgets(
      '7. Filtered empty states render clear/reset actions and reset state',
      (tester) async {
        final r1 = _createRestroom(id: 'r1', name: 'Alpha Mall');
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r1],
        );

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Filter out by non-matching search
        discoveryNotifier.setSearchQuery('NonExistentPlace');

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No restrooms match your search'), findsOneWidget);
        expect(find.text('Clear Search'), findsOneWidget);

        // Tap Clear Search
        await tester.tap(find.text('Clear Search'));
        await tester.pumpAndSettle();

        expect(discoveryNotifier.searchQuery, isEmpty);
        expect(find.text('Alpha Mall'), findsOneWidget);
      },
    );

    testWidgets(
      '8. Zoom-in suppressed state renders prompt with onSwitchToMap action',
      (tester) async {
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 10.0, longitude: 120.0),
            northEast: Coordinates(latitude: 20.0, longitude: 130.0),
          ),
          zoom: 10.0, // below minimum zoom 14.0
        );
        await tester.pump();

        bool switchedToMap = false;
        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(
              onSwitchToMap: () => switchedToMap = true,
            ),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Zoom In on Map to Explore'), findsOneWidget);
        expect(find.text('View Map'), findsOneWidget);

        await tester.tap(find.text('View Map'));
        await tester.pumpAndSettle();

        expect(switchedToMap, isTrue);
      },
    );

    testWidgets('9. Degraded results show warning banner above restroom list', (
      tester,
    ) async {
      final r1 = _createRestroom(id: 'r1', name: 'Dense Center Restroom');
      restroomRepo.viewportResultToReturn = DiscoveryResult.partial(
        items: [r1],
        reason: DiscoveryCompletenessReason.rangeCapExceeded,
      );

      discoveryNotifier.onCameraIdle(
        bounds: GeoBoundingBox(
          southWest: Coordinates(latitude: 14.54, longitude: 121.01),
          northEast: Coordinates(latitude: 14.56, longitude: 121.03),
        ),
        zoom: 16.0,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(
        _wrapWithProviders(
          child: const ExploreRestroomsScreen(),
          discoveryNotifier: discoveryNotifier,
          locationNotifier: locationNotifier,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Showing partial results (safety cap reached)'),
        findsOneWidget,
      );
      expect(find.text('Dense Center Restroom'), findsOneWidget);
    });

    testWidgets(
      '10. Error state without results shows ErrorStateView with retry',
      (tester) async {
        restroomRepo.exceptionToThrow = Exception('Network timeout');

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorStateView), findsOneWidget);
        expect(find.text('Unable to Load Restrooms'), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
      },
    );

    testWidgets(
      '11. Error state with retained prior results shows non-blocking banner and retains list',
      (tester) async {
        final r1 = _createRestroom(id: 'r1', name: 'Retained Restroom');
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r1],
        );

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Now next query fails
        restroomRepo.exceptionToThrow = Exception('Network error');
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.55, longitude: 121.02),
            northEast: Coordinates(latitude: 14.57, longitude: 121.04),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text("Couldn't refresh — showing previous results"),
          findsOneWidget,
        );
        expect(find.text('Retained Restroom'), findsOneWidget);
      },
    );

    testWidgets(
      '12. Loading state without visible results shows LooLoadingIndicator',
      (tester) async {
        final completer = Completer<DiscoveryResult<Restroom>>();
        restroomRepo.viewportCompleter = completer;

        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump(const Duration(milliseconds: 10));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pump();

        expect(find.byType(LooLoadingIndicator), findsOneWidget);
        expect(find.text('Searching nearby restrooms...'), findsOneWidget);

        completer.complete(DiscoveryResult.complete(items: const []));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '13. Verification badge: lastVerifiedAt within 90 days renders recent verification badge',
      (tester) async {
        final fixedNow = DateTime(2026, 10, 8, 12, 0);
        final r = _createRestroom(
          id: 'r_recent',
          name: 'Recent Restroom',
          lastVerifiedAt: fixedNow.subtract(const Duration(days: 10)),
          verificationCount: 1,
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r],
        );
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(now: fixedNow),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recently verified'), findsOneWidget);
        expect(find.text('Verified'), findsNothing);
      },
    );

    testWidgets(
      '14. Verification badge: lastVerifiedAt older than 90 days does NOT render current green Verified badge',
      (tester) async {
        final fixedNow = DateTime(2026, 10, 8, 12, 0);
        final r = _createRestroom(
          id: 'r_old',
          name: 'Older Restroom',
          lastVerifiedAt: fixedNow.subtract(const Duration(days: 95)),
          verificationCount: 1,
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r],
        );
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(now: fixedNow),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recently verified'), findsNothing);
        expect(find.text('Verified'), findsNothing);
        expect(find.text('Previously verified'), findsOneWidget);
      },
    );

    testWidgets(
      '15. Verification badge: verificationCount > 0 without lastVerifiedAt does NOT render current green Verified badge',
      (tester) async {
        final fixedNow = DateTime(2026, 10, 8, 12, 0);
        final r = _createRestroom(
          id: 'r_count_only',
          name: 'Count Only Restroom',
          lastVerifiedAt: null,
          verificationCount: 3,
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r],
        );
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(now: fixedNow),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recently verified'), findsNothing);
        expect(find.text('Verified'), findsNothing);
        expect(find.text('Previously verified'), findsOneWidget);
      },
    );

    testWidgets(
      '16. Verification badge: unverified restroom renders neither recent nor historical badge',
      (tester) async {
        final fixedNow = DateTime(2026, 10, 8, 12, 0);
        final r = _createRestroom(
          id: 'r_unverified',
          name: 'Unverified Restroom',
          lastVerifiedAt: null,
          verificationCount: 0,
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r],
        );
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(now: fixedNow),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recently verified'), findsNothing);
        expect(find.text('Verified'), findsNothing);
        expect(find.text('Previously verified'), findsNothing);
      },
    );

    testWidgets(
      '17. Verification badge: future verification timestamp is not treated as recent',
      (tester) async {
        final fixedNow = DateTime(2026, 10, 8, 12, 0);
        final r = _createRestroom(
          id: 'r_future',
          name: 'Future Restroom',
          lastVerifiedAt: fixedNow.add(const Duration(days: 3)),
          verificationCount: 1,
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r],
        );
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: ExploreRestroomsScreen(now: fixedNow),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recently verified'), findsNothing);
        expect(find.text('Verified'), findsNothing);
      },
    );

    testWidgets(
      '18. Accessibility touch target: summary card info button meets minimum 48x48 interactive size',
      (tester) async {
        final r = _createRestroom(
          id: 'r_target',
          name: 'Touch Target Restroom',
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r],
        );
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(
          _wrapWithProviders(
            child: const ExploreRestroomsScreen(),
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
          ),
        );
        await tester.pumpAndSettle();

        final buttonFinder = find.widgetWithIcon(
          IconButton,
          Icons.chevron_right_rounded,
        );
        expect(buttonFinder, findsOneWidget);
        final size = tester.getSize(buttonFinder);
        expect(size.width, greaterThanOrEqualTo(48.0));
        expect(size.height, greaterThanOrEqualTo(48.0));
      },
    );
  });
}
