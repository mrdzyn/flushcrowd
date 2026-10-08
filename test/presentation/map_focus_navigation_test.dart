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
import 'package:flushcrowd/domain/repositories/restroom_repository.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/restroom_preview_sheet.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_location_screen.dart';
import 'package:flushcrowd/presentation/screens/map_discovery_screen.dart';
import 'package:flushcrowd/presentation/state/location_notifier.dart';
import 'package:flushcrowd/presentation/state/map_discovery_notifier.dart';

class _FakeRestroomRepository implements RestroomRepository {
  @override
  Future<Restroom> submitRestroom(CreateRestroomCommand command) =>
      throw UnimplementedError();

  @override
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async => DiscoveryResult.complete(items: const []);

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async => DiscoveryResult.complete(items: const []);

  @override
  Future<Restroom?> getRestroomById(String id) async => null;

  @override
  Future<DiscoveryResult<Restroom>> getDuplicateCandidates(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) async => DiscoveryResult.complete(items: const []);
}

class _ControllableMapCameraController implements MapCameraController {
  final _ControllableMapState fakeMapState;
  int animateCameraCalls = 0;
  int moveCameraCalls = 0;
  CameraUpdate? lastCameraUpdate;

  _ControllableMapCameraController(this.fakeMapState);

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate) async {
    animateCameraCalls++;
    lastCameraUpdate = cameraUpdate;
    _applyUpdate(cameraUpdate);
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {
    moveCameraCalls++;
    lastCameraUpdate = cameraUpdate;
    _applyUpdate(cameraUpdate);
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

class _ControllableMapState {
  bool isInitialized = false;
  late CameraPosition currentCameraPosition;
  void Function(CameraPosition position)? onCameraMove;
  VoidCallback? onCameraIdle;
  VoidCallback? onCameraMoveStarted;
  void Function(MapCameraController controller)? onMapCreated;
  late _ControllableMapCameraController controller;

  _ControllableMapState() {
    controller = _ControllableMapCameraController(this);
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

MapWidgetBuilder _createControllableMapBuilder({
  required _ControllableMapState fakeMap,
  bool autoCallOnMapCreated = true,
}) {
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

    if (autoCallOnMapCreated) {
      onMapCreated?.call(fakeMap.controller);
    }

    return Container(
      key: const ValueKey('controllable_fake_map'),
      color: Colors.blueGrey,
    );
  };
}

Widget _createTestApp({
  required MapDiscoveryNotifier discoveryNotifier,
  required LocationNotifier locationNotifier,
  required MapWidgetBuilder mapBuilder,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MapDiscoveryNotifier>.value(
        value: discoveryNotifier,
      ),
      ChangeNotifierProvider<LocationNotifier>.value(value: locationNotifier),
    ],
    child: MaterialApp(home: MapDiscoveryScreen(mapBuilder: mapBuilder)),
  );
}

void main() {
  group('MapDiscoveryScreen — Map Focus Navigation & Lifecycle Race Remediation', () {
    late _FakeRestroomRepository restroomRepo;
    late InMemoryLocationRepository locationRepo;
    late LocationNotifier locationNotifier;
    late MapDiscoveryNotifier discoveryNotifier;
    late _ControllableMapState fakeMap;

    final restroom1 = Restroom(
      id: 'restroom_1',
      name: 'North Gate Restroom',
      coordinates: Coordinates(latitude: 14.6000, longitude: 121.0500),
      geohash: 'w4rrw0',
      accessType: AccessType.free,
      status: RestroomStatus.active,
      createdAt: DateTime.now(),
    );

    final restroom2 = Restroom(
      id: 'restroom_2',
      name: 'South Terminal Restroom',
      coordinates: Coordinates(latitude: 14.5000, longitude: 121.0100),
      geohash: 'wdw4d1',
      accessType: AccessType.free,
      status: RestroomStatus.active,
      createdAt: DateTime.now(),
    );

    setUp(() {
      restroomRepo = _FakeRestroomRepository();
      locationRepo = InMemoryLocationRepository(
        initialPermission: LocationPermissionState.granted,
        initialCoordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
      );
      locationNotifier = LocationNotifier(locationRepository: locationRepo);
      discoveryNotifier = MapDiscoveryNotifier(
        restroomRepository: restroomRepo,
      );
      fakeMap = _ControllableMapState();
    });

    testWidgets(
      '1. Focus requested before map controller initialization: defers camera focus and preview, intent not consumed prematurely',
      (tester) async {
        // Map controller is NOT automatically created
        final mapBuilder = _createControllableMapBuilder(
          fakeMap: fakeMap,
          autoCallOnMapCreated: false,
        );

        // Request focus BEFORE pump
        discoveryNotifier.focusOnRestroom(restroom1);

        await tester.pumpWidget(
          _createTestApp(
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
            mapBuilder: mapBuilder,
          ),
        );
        await tester.pump();

        // 1. Camera focus is deferred: animateCamera was NOT called
        expect(fakeMap.controller.animateCameraCalls, equals(0));

        // 2. Preview presentation is deferred: no sheet is shown
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // 3. Intent is NOT consumed prematurely while controller is unavailable
        expect(discoveryNotifier.pendingFocusIntent, isNotNull);
        expect(
          discoveryNotifier.pendingFocusIntent?.restroom.id,
          equals(restroom1.id),
        );
      },
    );

    testWidgets(
      '2. Delayed controller creation: executes deferred focus intent exactly once and opens preview sheet only after controller is created',
      (tester) async {
        final mapBuilder = _createControllableMapBuilder(
          fakeMap: fakeMap,
          autoCallOnMapCreated: false,
        );

        discoveryNotifier.focusOnRestroom(restroom1);

        await tester.pumpWidget(
          _createTestApp(
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
            mapBuilder: mapBuilder,
          ),
        );
        await tester.pump();

        expect(fakeMap.controller.animateCameraCalls, equals(0));
        expect(find.byType(RestroomPreviewSheet), findsNothing);
        expect(discoveryNotifier.pendingFocusIntent, isNotNull);

        // Controller is now created with delay
        fakeMap.simulateMapCreated();
        await tester.pumpAndSettle();

        // 1. Camera focus executed
        expect(fakeMap.controller.animateCameraCalls, equals(1));
        expect(
          fakeMap.currentCameraPosition.target.latitude,
          closeTo(14.6000, 0.0001),
        );
        expect(
          fakeMap.currentCameraPosition.target.longitude,
          closeTo(121.0500, 0.0001),
        );
        expect(
          fakeMap.currentCameraPosition.zoom,
          equals(AppConstants.defaultZoomLevel),
        );

        // 2. Preview sheet is displayed on screen
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text('North Gate Restroom'), findsOneWidget);

        // 3. Intent is now consumed
        expect(discoveryNotifier.pendingFocusIntent, isNull);
      },
    );

    testWidgets(
      '3. No duplicate preview sheets: controller initialization replays deferred intent without opening preview a second time',
      (tester) async {
        final mapBuilder = _createControllableMapBuilder(
          fakeMap: fakeMap,
          autoCallOnMapCreated: false,
        );

        discoveryNotifier.focusOnRestroom(restroom1);

        await tester.pumpWidget(
          _createTestApp(
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
            mapBuilder: mapBuilder,
          ),
        );
        await tester.pump();

        // Initialize controller
        fakeMap.simulateMapCreated();
        await tester.pumpAndSettle();

        // Exactly one preview sheet is open
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);

        // Trigger additional frames / pump cycles
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Must still be exactly one preview sheet (never duplicated)
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);

        // Dismiss the sheet
        Navigator.of(tester.element(find.byType(RestroomPreviewSheet))).pop();
        await tester.pumpAndSettle();

        // Sheet is closed and does NOT reappear
        expect(find.byType(RestroomPreviewSheet), findsNothing);
      },
    );

    testWidgets(
      '4. Rapidly superseded focus intents: only the latest focus intent executes camera focus and opens preview',
      (tester) async {
        // Scenario A: Superseded before controller is available
        final mapBuilderA = _createControllableMapBuilder(
          fakeMap: fakeMap,
          autoCallOnMapCreated: false,
        );

        await tester.pumpWidget(
          _createTestApp(
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
            mapBuilder: mapBuilderA,
          ),
        );
        await tester.pump();

        // Rapid intents: restroom1 then restroom2 before controller creation
        discoveryNotifier.focusOnRestroom(restroom1);
        discoveryNotifier.focusOnRestroom(restroom2);

        // Initialize controller
        fakeMap.simulateMapCreated();
        await tester.pumpAndSettle();

        // Only restroom2 (latest) was focused and previewed
        expect(
          fakeMap.currentCameraPosition.target.latitude,
          closeTo(14.5000, 0.0001),
        );
        expect(
          fakeMap.currentCameraPosition.target.longitude,
          closeTo(121.0100, 0.0001),
        );
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text('South Terminal Restroom'), findsOneWidget);
        expect(find.text('North Gate Restroom'), findsNothing);

        // Dismiss sheet
        Navigator.of(tester.element(find.byType(RestroomPreviewSheet))).pop();
        await tester.pumpAndSettle();

        // Scenario B: Superseded with controller already available
        discoveryNotifier.focusOnRestroom(restroom1);
        discoveryNotifier.focusOnRestroom(restroom2);
        await tester.pumpAndSettle();

        expect(
          fakeMap.currentCameraPosition.target.latitude,
          closeTo(14.5000, 0.0001),
        );
        expect(
          fakeMap.currentCameraPosition.target.longitude,
          closeTo(121.0100, 0.0001),
        );
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text('South Terminal Restroom'), findsOneWidget);
        expect(find.text('North Gate Restroom'), findsNothing);
      },
    );

    testWidgets(
      '5. Normal focus with controller already available: executes camera focus and opens preview directly',
      (tester) async {
        // Controller is created immediately upon map mount
        final mapBuilder = _createControllableMapBuilder(
          fakeMap: fakeMap,
          autoCallOnMapCreated: true,
        );

        await tester.pumpWidget(
          _createTestApp(
            discoveryNotifier: discoveryNotifier,
            locationNotifier: locationNotifier,
            mapBuilder: mapBuilder,
          ),
        );
        await tester.pumpAndSettle();

        final initialCalls = fakeMap.controller.animateCameraCalls;

        // Focus requested when controller is already ready
        discoveryNotifier.focusOnRestroom(restroom1);
        await tester.pumpAndSettle();

        // 1. Camera focus executed
        expect(
          fakeMap.controller.animateCameraCalls,
          greaterThan(initialCalls),
        );
        expect(
          fakeMap.currentCameraPosition.target.latitude,
          closeTo(14.6000, 0.0001),
        );
        expect(
          fakeMap.currentCameraPosition.target.longitude,
          closeTo(121.0500, 0.0001),
        );

        // 2. Preview sheet shown
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text('North Gate Restroom'), findsOneWidget);

        // 3. Intent consumed
        expect(discoveryNotifier.pendingFocusIntent, isNull);
      },
    );
  });
}
