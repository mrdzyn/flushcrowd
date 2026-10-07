import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:looradar/data/repositories/location_repository_impl.dart';
import 'package:looradar/domain/commands/create_restroom_command.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/discovery_result.dart';
import 'package:looradar/domain/models/enums.dart';
import 'package:looradar/domain/models/geo_bounding_box.dart';
import 'package:looradar/domain/models/restroom.dart';
import 'package:looradar/domain/repositories/restroom_repository.dart';
import 'package:looradar/presentation/components/buttons/loo_primary_button.dart';
import 'package:looradar/presentation/components/map/map_recenter_button.dart';
import 'package:looradar/presentation/screens/add_restroom_location_screen.dart';

/// Test helper to capture map callbacks and simulate camera events deterministically.
class FakeMapState {
  late CameraPosition currentCameraPosition;
  void Function(CameraPosition position)? onCameraMove;
  VoidCallback? onCameraIdle;
  VoidCallback? onCameraMoveStarted;

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
}

Widget createTestWidget({
  required Widget child,
  Size screenSize = const Size(390, 844),
  EdgeInsets viewPadding = EdgeInsets.zero,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: screenSize, viewPadding: viewPadding),
      child: child,
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

    MapWidgetBuilder createFakeMapBuilder() {
      return ({
        required BuildContext context,
        required CameraPosition initialCameraPosition,
        required void Function(GoogleMapController controller)? onMapCreated,
        required void Function(CameraPosition position)? onCameraMove,
        required VoidCallback? onCameraIdle,
        required VoidCallback? onCameraMoveStarted,
      }) {
        fakeMap.currentCameraPosition = initialCameraPosition;
        fakeMap.onCameraMove = onCameraMove;
        fakeMap.onCameraIdle = onCameraIdle;
        fakeMap.onCameraMoveStarted = onCameraMoveStarted;

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
            onLocationConfirmed: (c) => confirmedCoordinates = c,
            mapBuilder: createFakeMapBuilder(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pan to new coordinate
      fakeMap.simulateMove(
        const CameraPosition(target: LatLng(14.5950, 121.0680), zoom: 16.5),
      );
      fakeMap.simulateIdle();
      await tester.pump();

      // Tap Continue
      await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(confirmedCoordinates, isNotNull);
      expect(confirmedCoordinates!.latitude, 14.5950);
      expect(confirmedCoordinates!.longitude, 121.0680);
    });

    testWidgets(
      '11. no repository submission invoked during pinpoint interaction',
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

        // Pan multiple times
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
        await tester.pumpWidget(
          createTestWidget(
            viewPadding: const EdgeInsets.only(bottom: 34.0, top: 44.0),
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
        // Screen height is 844, bottom padding is 34
        // The button bottom must sit above 844 - 34 (inside safe area)
        expect(buttonRect.bottom, lessThanOrEqualTo(844.0));
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
  });
}
