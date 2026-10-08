import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flushcrowd/core/constants/app_constants.dart';
import 'package:flushcrowd/data/repositories/location_repository_impl.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/discovery_result.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/geo_bounding_box.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/repositories/location_repository.dart';
import 'package:flushcrowd/domain/repositories/restroom_repository.dart';
import 'package:flushcrowd/domain/models/discovery_filters.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/duplicate_warning_sheet.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/restroom_preview_sheet.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_secondary_button.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_form_screen.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_location_screen.dart';
import 'package:flushcrowd/presentation/screens/explore_restrooms_screen.dart';
import 'package:flushcrowd/presentation/screens/main_shell_screen.dart';
import 'package:flushcrowd/presentation/screens/map_discovery_screen.dart';
import 'package:flushcrowd/presentation/state/location_notifier.dart';
import 'package:flushcrowd/presentation/state/map_discovery_notifier.dart';

class CountingRestroomRepository implements RestroomRepository {
  int submitCount = 0;
  int discoveryCount = 0;
  int getRestroomCount = 0;

  @override
  Future<Restroom> submitRestroom(CreateRestroomCommand command) async {
    submitCount++;
    throw UnimplementedError('Submission should never be called in P2.2');
  }

  @override
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    discoveryCount++;
    return DiscoveryResult.complete(items: const []);
  }

  DiscoveryResult<Restroom>? viewportResultToReturn;

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async {
    discoveryCount++;
    return viewportResultToReturn ?? DiscoveryResult.complete(items: const []);
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    getRestroomCount++;
    return null;
  }

  DiscoveryResult<Restroom>? duplicateResultToReturn;
  int duplicateCount = 0;

  @override
  Future<DiscoveryResult<Restroom>> getDuplicateCandidates(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) async {
    duplicateCount++;
    return duplicateResultToReturn ?? DiscoveryResult.complete(items: const []);
  }
}

class FakeMapCameraController implements MapCameraController {
  final FakeMapState fakeMapState;
  int animateCameraCalls = 0;
  int moveCameraCalls = 0;
  CameraUpdate? lastCameraUpdate;
  bool autoSettle = true;
  bool shouldThrow = false;

  FakeMapCameraController(this.fakeMapState);

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate) async {
    animateCameraCalls++;
    lastCameraUpdate = cameraUpdate;
    if (shouldThrow) {
      throw Exception('Platform animateCamera failed');
    }
    if (autoSettle) {
      _applyUpdate(cameraUpdate);
    }
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {
    moveCameraCalls++;
    lastCameraUpdate = cameraUpdate;
    if (shouldThrow) {
      throw Exception('Platform moveCamera failed');
    }
    if (autoSettle) {
      _applyUpdate(cameraUpdate);
    }
  }

  void _applyUpdate(CameraUpdate cameraUpdate) {
    try {
      final json = cameraUpdate.toJson();
      if (json is List && json.isNotEmpty) {
        if (json[0] == 'newLatLngZoom' && json.length >= 3) {
          final targetList = json[1] as List;
          final target = LatLng(
            (targetList[0] as num).toDouble(),
            (targetList[1] as num).toDouble(),
          );
          final zoom = (json[2] as num).toDouble();
          fakeMapState.simulateMove(CameraPosition(target: target, zoom: zoom));
          fakeMapState.simulateIdle();
        } else if (json[0] == 'newLatLng' && json.length >= 2) {
          final targetList = json[1] as List;
          final target = LatLng(
            (targetList[0] as num).toDouble(),
            (targetList[1] as num).toDouble(),
          );
          fakeMapState.simulateMove(
            CameraPosition(
              target: target,
              zoom: fakeMapState.currentCameraPosition.zoom,
            ),
          );
          fakeMapState.simulateIdle();
        }
      }
    } catch (_) {}
  }
}

class FakeMapState {
  bool isInitialized = false;
  late CameraPosition currentCameraPosition;
  void Function(CameraPosition position)? onCameraMove;
  VoidCallback? onCameraIdle;
  VoidCallback? onCameraMoveStarted;
  void Function(MapCameraController controller)? onMapCreated;
  late FakeMapCameraController controller;

  FakeMapState() {
    controller = FakeMapCameraController(this);
  }

  void simulateMapCreated() {
    onMapCreated?.call(controller);
  }

  void simulateMove(CameraPosition position) {
    currentCameraPosition = position;
    onCameraMoveStarted?.call();
    onCameraMove?.call(position);
  }

  void simulateIdle() {
    onCameraIdle?.call();
  }
}

MapWidgetBuilder createFakeMapBuilder(FakeMapState fakeMap) {
  return ({
    required BuildContext context,
    required CameraPosition initialCameraPosition,
    required void Function(MapCameraController controller)? onMapCreated,
    required void Function(CameraPosition position)? onCameraMove,
    required VoidCallback? onCameraIdle,
    required VoidCallback? onCameraMoveStarted,
  }) {
    if (!fakeMap.isInitialized) {
      fakeMap.currentCameraPosition = initialCameraPosition;
      fakeMap.isInitialized = true;
    }
    fakeMap.onMapCreated = onMapCreated;
    fakeMap.onCameraMove = onCameraMove;
    fakeMap.onCameraIdle = onCameraIdle;
    fakeMap.onCameraMoveStarted = onCameraMoveStarted;

    onMapCreated?.call(fakeMap.controller);

    return Container(
      key: const ValueKey('fake_add_location_map'),
      color: Colors.blueGrey,
    );
  };
}

Widget createTestApp({
  required CountingRestroomRepository restroomRepo,
  required LocationRepository locationRepo,
  required LocationNotifier locationNotifier,
  required MapDiscoveryNotifier discoveryNotifier,
  required FakeMapState fakeMap,
  FakeMapState? discoveryFakeMap,
}) {
  return MultiProvider(
    providers: [
      Provider<RestroomRepository>.value(value: restroomRepo),
      Provider<LocationRepository>.value(value: locationRepo),
      ChangeNotifierProvider<LocationNotifier>.value(value: locationNotifier),
      ChangeNotifierProvider<MapDiscoveryNotifier>.value(
        value: discoveryNotifier,
      ),
    ],
    child: MaterialApp(
      home: MainShellScreen(
        addLocationMapBuilder: createFakeMapBuilder(fakeMap),
        discoveryMapBuilder: discoveryFakeMap != null
            ? createFakeMapBuilder(discoveryFakeMap)
            : null,
      ),
    ),
  );
}

void main() {
  group('MainShellScreen — Add Restroom Navigation Entry & Restoration', () {
    late CountingRestroomRepository restroomRepo;
    late InMemoryLocationRepository locationRepo;
    late LocationNotifier locationNotifier;
    late MapDiscoveryNotifier discoveryNotifier;
    late FakeMapState fakeMap;

    setUp(() {
      restroomRepo = CountingRestroomRepository();
      locationRepo = InMemoryLocationRepository(
        initialPermission: LocationPermissionState.granted,
        initialCoordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
      );
      locationNotifier = LocationNotifier(locationRepository: locationRepo);
      discoveryNotifier = MapDiscoveryNotifier(
        restroomRepository: restroomRepo,
      );
      fakeMap = FakeMapState();
    });

    testWidgets('1. Tapping Add opens AddRestroomLocationScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          restroomRepo: restroomRepo,
          locationRepo: locationRepo,
          locationNotifier: locationNotifier,
          discoveryNotifier: discoveryNotifier,
          fakeMap: fakeMap,
        ),
      );

      expect(find.byType(AddRestroomLocationScreen), findsNothing);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.byType(AddRestroomLocationScreen), findsOneWidget);
      expect(find.text('Pinpoint the restroom'), findsOneWidget);
    });

    testWidgets(
      '2. Old Phase 2 placeholder is no longer shown for Add action',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: fakeMap,
          ),
        );

        // Verify old placeholder text is not present initially
        expect(
          find.text(
            'Phase 2 will introduce the community contribution workflow.',
          ),
          findsNothing,
        );

        // Tap Add
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        // Verify old placeholder text is still not present
        expect(
          find.text(
            'Phase 2 will introduce the community contribution workflow.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      '3. No Firestore reads or writes occur merely by entering the Add flow',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: fakeMap,
          ),
        );

        final discoveryCountBeforeAdd = restroomRepo.discoveryCount;
        final submitCountBeforeAdd = restroomRepo.submitCount;
        final getRestroomCountBeforeAdd = restroomRepo.getRestroomCount;

        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

        // Verify ZERO submission writes
        expect(restroomRepo.submitCount, equals(submitCountBeforeAdd));
        expect(restroomRepo.submitCount, equals(0));

        // Verify ZERO single-document reads
        expect(
          restroomRepo.getRestroomCount,
          equals(getRestroomCountBeforeAdd),
        );
        expect(restroomRepo.getRestroomCount, equals(0));

        // Verify entering Add flow did NOT trigger any new discovery queries
        expect(restroomRepo.discoveryCount, equals(discoveryCountBeforeAdd));
      },
    );

    testWidgets('4. Cancel/back returns cleanly to the prior shell/map', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          restroomRepo: restroomRepo,
          locationRepo: locationRepo,
          locationNotifier: locationNotifier,
          discoveryNotifier: discoveryNotifier,
          fakeMap: fakeMap,
        ),
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

      // Tap back button
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(AddRestroomLocationScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsOneWidget);
      // No SnackBar should be displayed on cancel
      expect(
        find.text('Restroom details form is coming in the next milestone.'),
        findsNothing,
      );
    });

    testWidgets(
      '5. Successful P2.2 coordinate confirmation opens AddRestroomFormScreen and does not pretend submission succeeded',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: fakeMap,
          ),
        );

        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(find.byType(AddRestroomLocationScreen), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);

        // Tap Continue to confirm location
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Location screen popped, opens AddRestroomFormScreen
        expect(find.byType(AddRestroomLocationScreen), findsNothing);
        expect(find.byType(AddRestroomFormScreen), findsOneWidget);

        // Selected coordinates are preserved on the form
        expect(find.text('14.58390, 121.06170'), findsOneWidget);

        // Enter valid facility name
        await tester.enterText(
          find.byType(TextFormField).first,
          'Central Station Restroom',
        );
        await tester.pumpAndSettle();

        // Tap Continue on form
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Form popped, back on shell
        expect(find.byType(AddRestroomFormScreen), findsNothing);
        expect(find.byType(MainShellScreen), findsOneWidget);

        // Shows honest temporary coming-soon message
        expect(
          find.text(
            'Restroom details validated. Restroom submission comes in Milestone P2.5.',
          ),
          findsOneWidget,
        );

        // Does NOT pretend submission or contribution succeeded
        expect(find.text('Restroom added!'), findsNothing);
        expect(find.text('Submission succeeded'), findsNothing);
        expect(restroomRepo.submitCount, equals(0));
      },
    );

    testWidgets('6. Navigation can be invoked again after returning', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          restroomRepo: restroomRepo,
          locationRepo: locationRepo,
          locationNotifier: locationNotifier,
          discoveryNotifier: discoveryNotifier,
          fakeMap: fakeMap,
        ),
      );

      // First entry & back
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRestroomLocationScreen), findsNothing);

      // Second entry
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

      // Second exit
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRestroomLocationScreen), findsNothing);
    });

    testWidgets('7. Repeated rapid Add taps do not stack duplicate routes', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          restroomRepo: restroomRepo,
          locationRepo: locationRepo,
          locationNotifier: locationNotifier,
          discoveryNotifier: discoveryNotifier,
          fakeMap: fakeMap,
        ),
      );

      // Tap once, then tap again before route animation completes
      await tester.tap(find.text('Add'));
      await tester.pump(const Duration(milliseconds: 10));
      // Second tap on the Add icon button or area
      await tester.tap(
        find.byIcon(Icons.add_circle_outline_rounded),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

      // Single back pop returns cleanly to MainShellScreen
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(AddRestroomLocationScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsOneWidget);
    });

    testWidgets(
      '8. Non-Add tabs switch normally and preserve active tab after Add dismissal',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: fakeMap,
          ),
        );

        // Switch to Explore (index 1)
        await tester.tap(find.text('Explore'));
        await tester.pumpAndSettle();
        expect(find.byType(ExploreRestroomsScreen), findsOneWidget);
        expect(
          find.widgetWithText(AppBar, 'Explore Restrooms'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Phase 1 will deliver the nearby list and categorized explore view.',
          ),
          findsNothing,
        );

        // Tap Add (index 2) -> pushes AddRestroomLocationScreen
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

        // Pop back
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        // Prior active tab (Explore) remains selected
        expect(find.byType(AddRestroomLocationScreen), findsNothing);
        expect(find.byType(ExploreRestroomsScreen), findsOneWidget);
        expect(
          find.widgetWithText(AppBar, 'Explore Restrooms'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '9. Moving discovery map passes that camera target as initialCoordinates to AddRestroomLocationScreen',
      (tester) async {
        final discoveryFakeMap = FakeMapState();
        final addFakeMap = FakeMapState();

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
          ),
        );
        await tester.pumpAndSettle();

        // Simulate moving the discovery map to a remote coordinate
        const remoteTarget = LatLng(35.6895, 139.6917);
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: remoteTarget, zoom: 15.0),
        );
        await tester.pumpAndSettle();

        // Tap Add
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

        // Verify the AddRestroomLocationScreen started at the remote discovery target
        expect(find.text('35.68950, 139.69170'), findsOneWidget);
        expect(
          addFakeMap.currentCameraPosition.target.latitude,
          equals(35.6895),
        );
        expect(
          addFakeMap.currentCameraPosition.target.longitude,
          equals(139.6917),
        );

        // Did not jump back to GPS location (14.5839, 121.0617)
        expect(find.text('14.58390, 121.06170'), findsNothing);
      },
    );

    testWidgets(
      '10. Fallback remains intact when no discovery camera target has been captured',
      (tester) async {
        final addFakeMap = FakeMapState();

        // Pump without discoveryFakeMap, and without discovery camera target
        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: addFakeMap,
          ),
        );
        await tester.pumpAndSettle();

        // Tap Add immediately
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(find.byType(AddRestroomLocationScreen), findsOneWidget);

        // Fallback centers on device location or default (14.5839, 121.0617)
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
        expect(
          addFakeMap.currentCameraPosition.target.latitude,
          equals(14.5839),
        );
        expect(
          addFakeMap.currentCameraPosition.target.longitude,
          equals(121.0617),
        );
      },
    );

    testWidgets(
      '11. Selecting a restroom on Explore tab switches back to Map tab and displays preview card',
      (tester) async {
        final r = Restroom(
          id: 'test_r1',
          name: 'Greenbelt Mall Restroom',
          coordinates: Coordinates(latitude: 14.5510, longitude: 121.0200),
          geohash: 'wdw4fq',
          accessType: AccessType.free,
          male: true,
          female: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [r],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: fakeMap,
          ),
        );
        await tester.pumpAndSettle();

        // Perform discovery query on map
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.54, longitude: 121.01),
            northEast: Coordinates(latitude: 14.56, longitude: 121.03),
          ),
          zoom: 16.0,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(restroomRepo.discoveryCount, equals(1));
        final discoveryCallsBeforeExplore = restroomRepo.discoveryCount;

        // Switch to Explore tab
        await tester.tap(find.text('Explore'));
        await tester.pumpAndSettle();

        expect(find.byType(ExploreRestroomsScreen), findsOneWidget);
        expect(find.text('Greenbelt Mall Restroom'), findsOneWidget);

        // Tap the restroom card
        await tester.tap(find.text('Greenbelt Mall Restroom'));
        await tester.pumpAndSettle();

        // Should switch back to Map tab (tab index 0)
        expect(discoveryNotifier.selectedRestroom?.id, equals('test_r1'));
        expect(find.text('Greenbelt Mall Restroom'), findsOneWidget);

        // Verify ZERO additional discovery queries were triggered
        expect(
          restroomRepo.discoveryCount,
          equals(discoveryCallsBeforeExplore),
        );
      },
    );

    testWidgets(
      '12. Candidate duplicates show DuplicateWarningSheet and View Existing Restroom centers camera and opens preview',
      (tester) async {
        final discoveryFakeMap = FakeMapState();
        final addFakeMap = FakeMapState();

        final existingRestroom = Restroom(
          id: 'existing_dup_1',
          name: 'Central Station Restroom',
          coordinates: Coordinates(latitude: 14.58390, longitude: 121.06170),
          geohash: 'w4rr7x',
          accessType: AccessType.free,
          buildingName: 'Central Station',
          floor: '1F',
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );

        restroomRepo.duplicateResultToReturn = DiscoveryResult.complete(
          items: [existingRestroom],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
          ),
        );
        await tester.pumpAndSettle();

        // Open Add
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        // Confirm location
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Fill form with identical name & coordinates
        await tester.enterText(
          find.byType(TextFormField).first,
          'Central Station Restroom',
        );
        await tester.pumpAndSettle();

        // Tap Continue on form
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // DuplicateWarningSheet should be displayed!
        expect(find.byType(DuplicateWarningSheet), findsOneWidget);
        expect(find.text('Similar restrooms found nearby'), findsOneWidget);
        expect(find.text('Central Station Restroom'), findsOneWidget);
        expect(find.text('View Existing Restroom'), findsOneWidget);

        // Tap "View Existing Restroom"
        await tester.tap(
          find.widgetWithText(LooSecondaryButton, 'View Existing Restroom'),
        );
        await tester.pumpAndSettle();

        // Sheet is dismissed, shell shows Map tab with candidate selected
        expect(find.byType(DuplicateWarningSheet), findsNothing);
        expect(
          discoveryNotifier.selectedRestroom?.id,
          equals('existing_dup_1'),
        );
        expect(
          discoveryFakeMap.controller.animateCameraCalls,
          greaterThanOrEqualTo(1),
        );
        expect(
          discoveryFakeMap.currentCameraPosition.target.latitude,
          closeTo(14.58390, 0.00001),
        );
        expect(
          discoveryFakeMap.currentCameraPosition.target.longitude,
          closeTo(121.06170, 0.00001),
        );
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text('Central Station Restroom'), findsOneWidget);
      },
    );

    testWidgets(
      '13. DuplicateWarningSheet "No, It\'s a Different Restroom" acknowledges warning and continues flow',
      (tester) async {
        final existingRestroom = Restroom(
          id: 'existing_dup_2',
          name: 'Plaza Public Toilet',
          coordinates: Coordinates(latitude: 14.58390, longitude: 121.06170),
          geohash: 'w4rr7x',
          accessType: AccessType.free,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );

        restroomRepo.duplicateResultToReturn = DiscoveryResult.complete(
          items: [existingRestroom],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: fakeMap,
          ),
        );

        // Open Add
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        // Confirm location
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Fill form
        await tester.enterText(
          find.byType(TextFormField).first,
          'Plaza Public Toilet',
        );
        await tester.pumpAndSettle();

        // Tap Continue on form
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // DuplicateWarningSheet is displayed
        expect(find.byType(DuplicateWarningSheet), findsOneWidget);

        // Tap "No, It's a Different Restroom"
        await tester.tap(
          find.widgetWithText(
            LooPrimaryButton,
            "No, It's a Different Restroom",
          ),
        );
        await tester.pumpAndSettle();

        // Sheet is dismissed
        expect(find.byType(DuplicateWarningSheet), findsNothing);
        expect(
          find.text(
            'Duplicate warning acknowledged. Restroom submission comes in Milestone P2.5.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '14. View Existing Restroom centers camera and opens preview sheet when candidate duplicate lies outside current map viewport',
      (tester) async {
        final discoveryFakeMap = FakeMapState();
        final addFakeMap = FakeMapState();

        // Set initial discovery viewport in South Manila
        final localRestroom = Restroom(
          id: 'local_r1',
          name: 'South Bay Restroom',
          coordinates: Coordinates(latitude: 14.5100, longitude: 121.0100),
          geohash: 'wdw4d1',
          accessType: AccessType.free,
          male: true,
          female: true,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [localRestroom],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            fakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
          ),
        );
        await tester.pumpAndSettle();

        // Perform initial discovery query at south coordinates
        discoveryNotifier.onCameraIdle(
          bounds: GeoBoundingBox(
            southWest: Coordinates(latitude: 14.50, longitude: 121.00),
            northEast: Coordinates(latitude: 14.52, longitude: 121.02),
          ),
          zoom: 15.0,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(
          discoveryNotifier.visibleRestrooms.map((r) => r.id),
          contains('local_r1'),
        );

        // Set active filter that would hide a non-matching facility
        discoveryNotifier.setFilters(
          const DiscoveryFilters(babyChangingOnly: true),
        );
        expect(discoveryNotifier.hasActiveFilters, isTrue);

        // Candidate duplicate is far north outside the viewport and lacks baby changing
        final remoteRestroom = Restroom(
          id: 'remote_dup_1',
          name: 'Far North Terminal Restroom',
          coordinates: Coordinates(latitude: 14.6500, longitude: 121.1500),
          geohash: 'w4rrw0',
          accessType: AccessType.free,
          babyChanging: false,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );

        restroomRepo.duplicateResultToReturn = DiscoveryResult.complete(
          items: [remoteRestroom],
        );

        final initialAnimateCalls =
            discoveryFakeMap.controller.animateCameraCalls;

        // Open Add flow
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        // Move location map to remote coordinates outside initial discovery viewport
        addFakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.6500, 121.1500), zoom: 16.0),
        );
        addFakeMap.simulateIdle();
        await tester.pumpAndSettle();

        // Confirm location
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Fill form
        await tester.enterText(
          find.byType(TextFormField).first,
          'Far North Terminal Restroom',
        );
        await tester.pumpAndSettle();

        // Tap Continue
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(DuplicateWarningSheet), findsOneWidget);
        expect(find.text('Far North Terminal Restroom'), findsOneWidget);

        // Tap "View Existing Restroom"
        await tester.tap(
          find.widgetWithText(LooSecondaryButton, 'View Existing Restroom'),
        );
        await tester.pumpAndSettle();

        // 1. DuplicateWarningSheet is dismissed
        expect(find.byType(DuplicateWarningSheet), findsNothing);

        // 2. Switched back to Map tab
        expect(find.byType(MapDiscoveryScreen), findsOneWidget);

        // 3. Filters were reset to prevent hiding the candidate
        expect(discoveryNotifier.hasActiveFilters, isFalse);

        // 4. Candidate is selected in notifier
        expect(discoveryNotifier.selectedRestroom?.id, equals('remote_dup_1'));

        // 5. Camera animated to remote coordinates outside initial viewport
        expect(
          discoveryFakeMap.controller.animateCameraCalls,
          greaterThan(initialAnimateCalls),
        );
        expect(
          discoveryFakeMap.currentCameraPosition.target.latitude,
          closeTo(14.6500, 0.0001),
        );
        expect(
          discoveryFakeMap.currentCameraPosition.target.longitude,
          closeTo(121.1500, 0.0001),
        );
        expect(
          discoveryFakeMap.currentCameraPosition.zoom,
          equals(AppConstants.defaultZoomLevel),
        );

        // 6. RestroomPreviewSheet is shown on screen for candidate
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(RestroomPreviewSheet),
            matching: find.text('Far North Terminal Restroom'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
