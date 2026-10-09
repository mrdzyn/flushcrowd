import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flushcrowd/data/repositories/location_repository_impl.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/discovery_result.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/geo_bounding_box.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/repositories/location_repository.dart';
import 'package:flushcrowd/domain/repositories/restroom_repository.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/components/map/map_recenter_button.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_location_screen.dart';
import 'package:flushcrowd/presentation/state/location_notifier.dart';

/// Test helper implementing [MapCameraController] to record camera updates deterministically.
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

/// Test helper to capture map callbacks and simulate camera events deterministically.
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

/// Counting restroom repository to verify zero discovery or submission calls occur.
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

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async {
    discoveryCount++;
    return DiscoveryResult.complete(items: const []);
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    getRestroomCount++;
    return null;
  }

  @override
  Future<DiscoveryResult<Restroom>> getDuplicateCandidates(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) async {
    discoveryCount++;
    return DiscoveryResult.complete(items: const []);
  }
}

/// Test double that can simulate fresh location retrieval failure.
class MockFailingLocationRepository extends InMemoryLocationRepository {
  bool shouldThrowOnGetCurrentLocation = false;

  MockFailingLocationRepository({
    super.initialPermission,
    super.initialCoordinates,
    super.serviceEnabled,
  });

  @override
  Future<Coordinates> getCurrentLocation() async {
    if (shouldThrowOnGetCurrentLocation) {
      throw Exception('Fresh GPS hardware lookup failed');
    }
    return super.getCurrentLocation();
  }
}

Widget createTestWidget({
  required Widget child,
  RestroomRepository? restroomRepository,
  LocationRepository? locationRepository,
  LocationNotifier? locationNotifier,
  Size screenSize = const Size(390, 844),
  EdgeInsets viewPadding = EdgeInsets.zero,
}) {
  return MultiProvider(
    providers: [
      Provider<RestroomRepository>.value(
        value: restroomRepository ?? CountingRestroomRepository(),
      ),
      if (locationRepository != null)
        Provider<LocationRepository>.value(value: locationRepository),
      if (locationNotifier != null)
        ChangeNotifierProvider<LocationNotifier>.value(value: locationNotifier),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: screenSize, viewPadding: viewPadding),
        child: child,
      ),
    ),
  );
}

void main() {
  group('Phase 2 Milestone P2.2: AddRestroomLocationScreen', () {
    late FakeMapState fakeMap;
    late InMemoryLocationRepository locationRepo;
    late CountingRestroomRepository restroomRepo;

    setUp(() {
      fakeMap = FakeMapState();
      locationRepo = InMemoryLocationRepository(
        initialPermission: LocationPermissionState.denied,
        initialCoordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
      );
      restroomRepo = CountingRestroomRepository();
    });

    MapWidgetBuilder createFakeMapBuilder({bool autoConnectController = true}) {
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

        if (autoConnectController) {
          onMapCreated?.call(fakeMap.controller);
        }

        return Container(
          key: const Key('fake_map_canvas'),
          color: Colors.blueGrey,
        );
      };
    }

    testWidgets('1. explicit initial coordinate is selected correctly', (
      tester,
    ) async {
      final explicitCoords = Coordinates(
        latitude: 14.5547,
        longitude: 121.0244,
      );

      await tester.pumpWidget(
        createTestWidget(
          child: AddRestroomLocationScreen(
            initialCoordinates: explicitCoords,
            locationRepository: locationRepo,
            mapBuilder: createFakeMapBuilder(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('14.55470, 121.02440'), findsOneWidget);
      expect(fakeMap.currentCameraPosition.target.latitude, 14.5547);
      expect(fakeMap.currentCameraPosition.target.longitude, 121.0244);
    });

    testWidgets(
      '2. coordinate displays to 5 decimal places with trailing zeroes',
      (tester) async {
        final roundCoords = Coordinates(latitude: 14.1, longitude: 121.2);

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: roundCoords,
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('14.10000, 121.20000'), findsOneWidget);
      },
    );

    testWidgets('3. camera idle commits target coordinate', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: AddRestroomLocationScreen(
            initialCoordinates: Coordinates(
              latitude: 14.5839,
              longitude: 121.0617,
            ),
            locationRepository: locationRepo,
            mapBuilder: createFakeMapBuilder(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('14.58390, 121.06170'), findsOneWidget);

      // Pan camera to a new target
      fakeMap.simulateMove(
        const CameraPosition(target: LatLng(14.6000, 121.0800), zoom: 16.0),
      );
      await tester.pump();

      // Camera has moved, but onCameraIdle not yet fired: readout unchanged
      expect(find.text('14.58390, 121.06170'), findsOneWidget);

      // Commit camera movement
      fakeMap.simulateIdle();
      await tester.pump();

      expect(find.text('14.60000, 121.08000'), findsOneWidget);
    });

    testWidgets(
      '4. camera moving sets moving state and disables continue until idle',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // At zoom 16.0 resting, Continue is enabled
        final continueButtonBefore = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(continueButtonBefore.onPressed, isNotNull);

        // Camera starts moving
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5900, 121.0700), zoom: 16.0),
        );
        await tester.pump();

        // While moving, Continue is disabled
        final continueButtonMoving = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(continueButtonMoving.onPressed, isNull);

        // Camera stops
        fakeMap.simulateIdle();
        await tester.pump();

        // Once idle, Continue becomes enabled again
        final continueButtonIdle = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(continueButtonIdle.onPressed, isNotNull);
      },
    );

    testWidgets('5. confirmation disabled below zoom 15', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: AddRestroomLocationScreen(
            initialCoordinates: Coordinates(
              latitude: 14.5839,
              longitude: 121.0617,
            ),
            locationRepository: locationRepo,
            mapBuilder: createFakeMapBuilder(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zoom out to 14.0 and settle
      fakeMap.simulateMove(
        const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 14.0),
      );
      fakeMap.simulateIdle();
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byType(LooPrimaryButton),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('6. precision hint visible below zoom 15', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: AddRestroomLocationScreen(
            initialCoordinates: Coordinates(
              latitude: 14.5839,
              longitude: 121.0617,
            ),
            locationRepository: locationRepo,
            mapBuilder: createFakeMapBuilder(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial zoom is 16.0 -> hint not shown
      expect(
        find.text('Zoom in to place the restroom more precisely.'),
        findsNothing,
      );

      // Zoom out to 14.5
      fakeMap.simulateMove(
        const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 14.5),
      );
      fakeMap.simulateIdle();
      await tester.pump();

      expect(
        find.text('Zoom in to place the restroom more precisely.'),
        findsOneWidget,
      );
    });

    testWidgets(
      '7. confirmation enabled at zoom >= 15 with valid coordinate and hint clears',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Zoom out first
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 13.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();
        expect(
          find.text('Zoom in to place the restroom more precisely.'),
          findsOneWidget,
        );

        // Zoom back in to exactly 15.0
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 15.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        // Hint cleared and button enabled
        expect(
          find.text('Zoom in to place the restroom more precisely.'),
          findsNothing,
        );
        final button = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets(
      '8. current-location action updates camera/selection when available',
      (tester) async {
        final userCoords = Coordinates(latitude: 14.6500, longitude: 121.0500);
        locationRepo.setPermissionState(LocationPermissionState.granted);
        locationRepo.setCoordinates(userCoords);

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('14.58390, 121.06170'), findsOneWidget);

        // Tap "Use my location" button
        await tester.tap(find.byType(MapRecenterButton));
        await tester.pumpAndSettle();

        // Camera target and selected coordinates updated to user position
        expect(find.text('14.65000, 121.05000'), findsOneWidget);
      },
    );

    testWidgets('9. GPS unavailable does not prevent manual map selection', (
      tester,
    ) async {
      locationRepo.setPermissionState(LocationPermissionState.denied);

      await tester.pumpWidget(
        createTestWidget(
          child: AddRestroomLocationScreen(
            locationRepository: locationRepo,
            mapBuilder: createFakeMapBuilder(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default fallback initialized
      expect(find.text('14.58390, 121.06170'), findsOneWidget);

      // Tap "Use my location" -> fails gracefully without crashing
      await tester.tap(find.byType(MapRecenterButton));
      await tester.pumpAndSettle();

      expect(
        find.text('Location permission denied. Move the map manually.'),
        findsOneWidget,
      );

      // User manually pans the map
      fakeMap.simulateMove(
        const CameraPosition(target: LatLng(14.7200, 121.0300), zoom: 16.0),
      );
      fakeMap.simulateIdle();
      await tester.pump();

      // Manual selection works
      expect(find.text('14.72000, 121.03000'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byType(LooPrimaryButton),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('10. selected coordinate returned/passed on Continue', (
      tester,
    ) async {
      Coordinates? confirmedCoordinates;

      await tester.pumpWidget(
        createTestWidget(
          child: AddRestroomLocationScreen(
            initialCoordinates: Coordinates(
              latitude: 14.5839,
              longitude: 121.0617,
            ),
            locationRepository: locationRepo,
            mapBuilder: createFakeMapBuilder(),
            onLocationConfirmed: (coords) {
              confirmedCoordinates = coords;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Move camera
      fakeMap.simulateMove(
        const CameraPosition(target: LatLng(14.6200, 121.0400), zoom: 16.0),
      );
      fakeMap.simulateIdle();
      await tester.pump();

      // Tap Continue
      await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(confirmedCoordinates, isNotNull);
      expect(confirmedCoordinates!.latitude, 14.6200);
      expect(confirmedCoordinates!.longitude, 121.0400);
    });

    testWidgets(
      '11. no Firestore submission write invoked by pinpoint placement / continue',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            restroomRepository: restroomRepo,
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Perform camera movements
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.6, 121.1), zoom: 16.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.7, 121.2), zoom: 16.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        // Tap Continue
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Zero repository submission writes
        expect(restroomRepo.submitCount, 0);
      },
    );

    testWidgets(
      '12. no Firestore discovery operation invoked by pinpoint movement',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            restroomRepository: restroomRepo,
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (int i = 0; i < 5; i++) {
          fakeMap.simulateMove(
            CameraPosition(
              target: LatLng(14.5839 + (i * 0.001), 121.0617 + (i * 0.001)),
              zoom: 16.0,
            ),
          );
          fakeMap.simulateIdle();
          await tester.pump();
        }

        // Zero discovery queries
        expect(restroomRepo.discoveryCount, 0);
        expect(restroomRepo.getRestroomCount, 0);
      },
    );

    testWidgets(
      '13. safe-area layout does not cover primary action where widget-testable',
      (tester) async {
        const testScreenSize = Size(390, 844);
        const testViewPadding = EdgeInsets.only(bottom: 34.0, top: 44.0);

        await tester.pumpWidget(
          createTestWidget(
            screenSize: testScreenSize,
            viewPadding: testViewPadding,
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final buttonFinder = find.widgetWithText(LooPrimaryButton, 'Continue');
        expect(buttonFinder, findsOneWidget);

        final buttonRect = tester.getRect(buttonFinder);
        // Safely inside safe area limit derived from MediaQuery
        final safeAreaBottomLimit =
            testScreenSize.height - testViewPadding.bottom;
        expect(buttonRect.bottom, lessThanOrEqualTo(safeAreaBottomLimit));
        expect(buttonRect.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      '14. semantics/accessibility labels exist for important controls',
      (tester) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check key semantics
        expect(find.bySemanticsLabel('Map center target pin'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Selected coordinates: 14.58390, 121.06170'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Use my location'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Continue to restroom details'),
          findsOneWidget,
        );

        // Precision warning semantics when zoom < 15
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 14.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        expect(
          find.bySemanticsLabel(
            'Precision warning: Zoom in to place the restroom more precisely.',
          ),
          findsOneWidget,
        );

        handle.dispose();
      },
    );

    testWidgets(
      '15. longitude wrapping past antimeridian normalizes cleanly without error',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Simulate camera moving past 180 degrees
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 185.0), zoom: 16.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        // 185 normalized is -175
        expect(find.text('14.58390, -175.00000'), findsOneWidget);
      },
    );

    testWidgets('16. navigation route pop returns selected coordinates', (
      tester,
    ) async {
      Coordinates? returnedCoordinates;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  returnedCoordinates = await Navigator.of(context).push(
                    AddRestroomLocationScreen.route(
                      initialCoordinates: Coordinates(
                        latitude: 14.5839,
                        longitude: 121.0617,
                      ),
                      locationRepository: locationRepo,
                      mapBuilder: createFakeMapBuilder(),
                    ),
                  );
                },
                child: const Text('Open Pinpoint'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open screen
      await tester.tap(find.text('Open Pinpoint'));
      await tester.pumpAndSettle();

      expect(find.text('Pinpoint the restroom'), findsOneWidget);

      // Pan to target
      fakeMap.simulateMove(
        const CameraPosition(target: LatLng(14.6100, 121.0900), zoom: 16.0),
      );
      fakeMap.simulateIdle();
      await tester.pump();

      // Continue pops route
      await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Open Pinpoint'), findsOneWidget);
      expect(returnedCoordinates, isNotNull);
      expect(returnedCoordinates!.latitude, 14.6100);
      expect(returnedCoordinates!.longitude, 121.0900);
    });

    testWidgets(
      '17. Use my location when services disabled shows notice and does not change selection',
      (tester) async {
        locationRepo.setServiceEnabled(false);

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(MapRecenterButton));
        await tester.pumpAndSettle();

        expect(
          find.text('Location services are disabled. Move the map manually.'),
          findsOneWidget,
        );
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
      },
    );

    testWidgets(
      '18. Use my location when permission denied shows notice and does not change selection',
      (tester) async {
        locationRepo.setPermissionState(
          LocationPermissionState.permanentlyDenied,
        );

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(MapRecenterButton));
        await tester.pumpAndSettle();

        expect(
          find.text('Location permission denied. Move the map manually.'),
          findsOneWidget,
        );
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
      },
    );

    testWidgets(
      '19. fresh lookup failure does NOT consume stale cached coordinates from LocationNotifier',
      (tester) async {
        final mockRepo = MockFailingLocationRepository(
          initialPermission: LocationPermissionState.granted,
          initialCoordinates: Coordinates(
            latitude: 14.5000,
            longitude: 121.0000,
          ),
        );
        final notifier = LocationNotifier(locationRepository: mockRepo);
        // Pre-warm notifier to obtain cached coordinates
        await notifier.fetchCurrentLocation();
        expect(notifier.hasLocation, isTrue);
        expect(notifier.currentCoordinates, isNotNull);
        expect(notifier.currentCoordinates!.latitude, 14.5000);

        // Now simulate GPS hardware / network failure on fresh attempt
        mockRepo.shouldThrowOnGetCurrentLocation = true;

        await tester.pumpWidget(
          createTestWidget(
            locationNotifier: notifier,
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Readout starts at explicit coordinates
        expect(find.text('14.58390, 121.06170'), findsOneWidget);

        // Tap "Use my location"
        await tester.tap(find.byType(MapRecenterButton));
        await tester.pumpAndSettle();

        // Shows failure notice
        expect(
          find.text(
            'Unable to determine current location. Move the map manually.',
          ),
          findsOneWidget,
        );

        // Stale coordinates (14.50000, 121.00000) MUST NOT be consumed
        expect(find.text('14.50000, 121.00000'), findsNothing);
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
      },
    );

    testWidgets(
      '20. manual placement functions after failed fresh location attempt',
      (tester) async {
        final mockRepo = MockFailingLocationRepository(
          initialPermission: LocationPermissionState.granted,
          initialCoordinates: Coordinates(
            latitude: 14.5000,
            longitude: 121.0000,
          ),
        );
        mockRepo.shouldThrowOnGetCurrentLocation = true;

        await tester.pumpWidget(
          createTestWidget(
            locationRepository: mockRepo,
            child: AddRestroomLocationScreen(
              initialCoordinates: Coordinates(
                latitude: 14.5839,
                longitude: 121.0617,
              ),
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(MapRecenterButton));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Unable to determine current location. Move the map manually.',
          ),
          findsOneWidget,
        );

        // Manually drag map
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.7500, 121.0500), zoom: 16.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        expect(find.text('14.75000, 121.05000'), findsOneWidget);
        final button = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets(
      '21. Use my location with controller connected does not falsely commit B on idle before movement to B',
      (tester) async {
        final coordA = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final coordB = Coordinates(latitude: 14.6500, longitude: 121.0500);

        locationRepo.setPermissionState(LocationPermissionState.granted);
        locationRepo.setCoordinates(coordB);

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: coordA,
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<AddRestroomLocationScreenState>(
          find.byType(AddRestroomLocationScreen),
        );

        // Initial resting state: Continue is enabled
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
        final initialButton = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(initialButton.onPressed, isNotNull);

        // Disable autoSettle to observe intermediate programmatic moving state
        fakeMap.controller.autoSettle = false;

        // Tap "Use my location"
        await tester.tap(find.byType(MapRecenterButton));
        await tester.pump();

        // Programmatic animateCamera was called
        expect(fakeMap.controller.animateCameraCalls, 1);

        // Readout and actual camera target stay at A before movement callback
        expect(state.actualCameraTarget.latitude, 14.5839);
        expect(state.isProgrammaticMovePending, isTrue);
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
        expect(find.text('14.65000, 121.05000'), findsNothing);

        // Continue button MUST be disabled while programmatic move is pending
        final movingButton = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(movingButton.onPressed, isNull);

        // Premature idle callback without observed movement MUST NOT falsely commit B
        fakeMap.simulateIdle();
        await tester.pump();

        expect(find.text('14.58390, 121.06170'), findsOneWidget);
        expect(find.text('14.65000, 121.05000'), findsNothing);
        expect(state.isProgrammaticMovePending, isTrue);
        final stillDisabledButton = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(stillDisabledButton.onPressed, isNull);

        // Emit actual camera movement to B
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.6500, 121.0500), zoom: 16.0),
        );
        await tester.pump();

        // Emit idle
        fakeMap.simulateIdle();
        await tester.pump();

        // Now coordinates commit to the settled position B and Continue is re-enabled
        expect(find.text('14.65000, 121.05000'), findsOneWidget);
        expect(state.isProgrammaticMovePending, isFalse);
        final settledButton = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(settledButton.onPressed, isNotNull);
      },
    );

    testWidgets(
      '22. queued GPS intent before controller does NOT commit on premature idle until movement to target occurs',
      (tester) async {
        final coordA = Coordinates(latitude: 14.5839, longitude: 121.0617);
        final coordB = Coordinates(latitude: 14.7000, longitude: 121.1000);

        locationRepo.setPermissionState(LocationPermissionState.granted);
        locationRepo.setCoordinates(coordB);

        // Disable autoSettle so controller execution doesn't automatically simulate movement
        fakeMap.controller.autoSettle = false;

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: coordA,
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(autoConnectController: false),
            ),
          ),
        );
        await tester.pump();

        // Tap Use my location before controller is connected
        await tester.tap(find.byType(MapRecenterButton));
        await tester.pump();

        final state = tester.state<AddRestroomLocationScreenState>(
          find.byType(AddRestroomLocationScreen),
        );

        // 1. Destination B is pending, but actual camera state remains A
        expect(state.isProgrammaticMovePending, isTrue);
        expect(state.actualCameraTarget.latitude, 14.5839);
        expect(fakeMap.currentCameraPosition.target.latitude, 14.5839);
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
        expect(find.text('14.70000, 121.10000'), findsNothing);

        // Continue is disabled while pending
        final buttonBefore = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(buttonBefore.onPressed, isNull);

        // 2. Connect controller -> dispatches queued intent
        fakeMap.simulateMapCreated();
        await tester.pump();
        expect(fakeMap.controller.animateCameraCalls, 1);

        // 3. Before any onCameraMove, fire onCameraIdle
        fakeMap.simulateIdle();
        await tester.pump();

        // Selected coordinates MUST remain A!
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
        expect(find.text('14.70000, 121.10000'), findsNothing);
        expect(state.isProgrammaticMovePending, isTrue);

        // Continue MUST remain disabled
        final buttonPremature = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(buttonPremature.onPressed, isNull);

        // 4. Emit actual camera movement to B
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.7000, 121.1000), zoom: 16.0),
        );
        await tester.pump();

        // 5. Emit idle
        fakeMap.simulateIdle();
        await tester.pump();

        // 6. Only now commits B and enables Continue
        expect(find.text('14.70000, 121.10000'), findsOneWidget);
        expect(state.isProgrammaticMovePending, isFalse);
        final buttonSettled = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(buttonSettled.onPressed, isNotNull);
      },
    );

    testWidgets(
      '23. widget rebuild does not implicitly relocate simulated native map',
      (tester) async {
        final coordA = Coordinates(latitude: 14.5839, longitude: 121.0617);

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: coordA,
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeMap.currentCameraPosition.target.latitude, 14.5839);

        // User moves camera to C
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.6100, 121.0900), zoom: 16.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        expect(fakeMap.currentCameraPosition.target.latitude, 14.6100);
        expect(find.text('14.61000, 121.09000'), findsOneWidget);

        // Rebuild the widget tree (e.g. parent rebuilds or orientation change)
        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: coordA,
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pump();

        // Simulated native platform map MUST NOT reset to coordA! It remains at 14.6100.
        expect(fakeMap.currentCameraPosition.target.latitude, 14.6100);
        expect(fakeMap.currentCameraPosition.target.longitude, 121.0900);
        expect(find.text('14.61000, 121.09000'), findsOneWidget);
      },
    );

    testWidgets(
      '24. MapCameraController test double tracks animateCamera and moveCamera invocations',
      (tester) async {
        final controller = fakeMap.controller;
        expect(controller.animateCameraCalls, 0);
        expect(controller.moveCameraCalls, 0);

        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(const LatLng(14.5, 121.0), 16.0),
        );
        expect(controller.animateCameraCalls, 1);

        await controller.moveCamera(
          CameraUpdate.newLatLngZoom(const LatLng(14.6, 121.1), 16.0),
        );
        expect(controller.moveCameraCalls, 1);
      },
    );

    testWidgets(
      '25. camera-command failure recovers state without being stuck in pending move',
      (tester) async {
        final coordA = Coordinates(latitude: 14.5839, longitude: 121.0617);
        locationRepo.setPermissionState(LocationPermissionState.granted);
        locationRepo.setCoordinates(
          Coordinates(latitude: 14.6500, longitude: 121.0500),
        );

        // Both animateCamera and fallback moveCamera will throw
        fakeMap.controller.shouldThrow = true;

        await tester.pumpWidget(
          createTestWidget(
            child: AddRestroomLocationScreen(
              initialCoordinates: coordA,
              locationRepository: locationRepo,
              mapBuilder: createFakeMapBuilder(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<AddRestroomLocationScreenState>(
          find.byType(AddRestroomLocationScreen),
        );

        // Tap "Use my location"
        await tester.tap(find.byType(MapRecenterButton));
        await tester.pumpAndSettle();

        // 1. Not stuck in programmatic pending state
        expect(state.isProgrammaticMovePending, isFalse);

        // 2. Preserves the last legitimately committed coordinate A
        expect(find.text('14.58390, 121.06170'), findsOneWidget);

        // 3. Shows non-blocking notice
        expect(
          find.text('Unable to move map camera. Move the map manually.'),
          findsOneWidget,
        );

        // 4. Manual map placement remains fully functional
        fakeMap.controller.shouldThrow = false;
        fakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.7200, 121.0300), zoom: 16.0),
        );
        fakeMap.simulateIdle();
        await tester.pump();

        expect(find.text('14.72000, 121.03000'), findsOneWidget);
        final button = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LooPrimaryButton),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(button.onPressed, isNotNull);
      },
    );
  });
}
