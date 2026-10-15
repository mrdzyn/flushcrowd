import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:flushcrowd/core/config/app_config.dart';
import 'package:flushcrowd/core/config/environment.dart';
import 'package:flushcrowd/core/constants/app_constants.dart';
import 'package:flushcrowd/core/errors/exceptions.dart';
import 'package:flushcrowd/data/repositories/firestore_restroom_repository.dart';
import 'package:flushcrowd/data/repositories/location_repository_impl.dart';
import 'package:flushcrowd/data/services/firebase/restroom_submission_transport.dart';
import 'package:flushcrowd/data/services/gis/geohash_service.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/discovery_result.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/geo_bounding_box.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/repositories/auth_repository.dart';
import 'package:flushcrowd/domain/repositories/location_repository.dart';
import 'package:flushcrowd/domain/repositories/restroom_repository.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/restroom_preview_sheet.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_form_screen.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_location_screen.dart';
import 'package:flushcrowd/presentation/screens/main_shell_screen.dart';
import 'package:flushcrowd/presentation/state/auth_notifier.dart';
import 'package:flushcrowd/presentation/state/location_notifier.dart';
import 'package:flushcrowd/presentation/state/map_discovery_notifier.dart';
import 'package:flushcrowd/presentation/state/restroom_id_generator.dart';

// --- Test Doubles ---

class CountingRestroomIdGenerator implements RestroomIdGenerator {
  int generateCalls = 0;
  final String fixedId;

  CountingRestroomIdGenerator([this.fixedId = 'fixed_test_restroom_id_123']);

  @override
  String generate() {
    generateCalls++;
    return fixedId;
  }
}

class FakeAuthRepository implements AuthRepository {
  final StreamController<String?> _authStreamController =
      StreamController<String?>.broadcast();
  String? _uid;

  FakeAuthRepository({String? initialUid}) : _uid = initialUid;

  @override
  Stream<String?> get authStateChanges => _authStreamController.stream;

  @override
  String? get currentUserId => _uid;

  bool get isAuthenticated => _uid != null;

  @override
  Future<String> ensureAnonymousSession() async {
    _uid = _uid ?? 'anon_uid_999';
    _authStreamController.add(_uid);
    return _uid!;
  }

  Future<String> signInAnonymously() async {
    _uid = 'anon_uid_999';
    _authStreamController.add(_uid);
    return _uid!;
  }

  Future<void> signOut() async {
    _uid = null;
    _authStreamController.add(null);
  }
}

class FakeMapCameraController
    implements MapCameraController, MapViewportController {
  final FakeMapState fakeMapState;
  double? lastRequestedZoom;

  FakeMapCameraController(this.fakeMapState);

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate) async {
    fakeMapState.onCameraMoveStarted?.call();
    _applyUpdate(cameraUpdate);
    fakeMapState.simulateIdle();
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {
    fakeMapState.onCameraMoveStarted?.call();
    _applyUpdate(cameraUpdate);
    fakeMapState.simulateIdle();
  }

  @override
  Future<LatLngBounds?> getVisibleRegion() async {
    final target = fakeMapState.currentCameraPosition.target;
    return LatLngBounds(
      southwest: LatLng(target.latitude - 0.005, target.longitude - 0.005),
      northeast: LatLng(target.latitude + 0.005, target.longitude + 0.005),
    );
  }

  @override
  Future<double?> getZoomLevel() async {
    return fakeMapState.currentCameraPosition.zoom;
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
          lastRequestedZoom = zoom;
          fakeMapState.simulateMove(CameraPosition(target: target, zoom: zoom));
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
        }
      }
    } catch (_) {}
  }
}

class FakeMapState {
  bool isInitialized = false;
  bool isCreated = false;
  late CameraPosition currentCameraPosition;
  void Function(CameraPosition position)? onCameraMove;
  VoidCallback? onCameraIdle;
  VoidCallback? onCameraMoveStarted;
  void Function(MapCameraController controller)? onMapCreated;
  late FakeMapCameraController controller;

  FakeMapState() {
    controller = FakeMapCameraController(this);
    currentCameraPosition = const CameraPosition(
      target: LatLng(14.5839, 121.0617),
      zoom: 15.0,
    );
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

    if (!fakeMap.isCreated) {
      fakeMap.isCreated = true;
      onMapCreated?.call(fakeMap.controller);
    }

    return Container(
      key: const ValueKey('fake_map_view'),
      color: Colors.blueGrey,
    );
  };
}

Widget createTestApp({
  required RestroomRepository restroomRepo,
  required LocationRepository locationRepo,
  required LocationNotifier locationNotifier,
  required MapDiscoveryNotifier discoveryNotifier,
  required FakeMapState addFakeMap,
  required FakeMapState discoveryFakeMap,
  required AuthNotifier authNotifier,
  AppConfig config = const AppConfig(
    environment: Environment.staging,
    firebaseProjectId: AppConstants.stagingFirebaseProjectId,
    useCallableSubmission: true,
  ),
  RestroomIdGenerator? formIdGenerator,
}) {
  return MultiProvider(
    providers: [
      Provider<AppConfig>.value(value: config),
      Provider<RestroomRepository>.value(value: restroomRepo),
      Provider<LocationRepository>.value(value: locationRepo),
      ChangeNotifierProvider<LocationNotifier>.value(value: locationNotifier),
      ChangeNotifierProvider<MapDiscoveryNotifier>.value(
        value: discoveryNotifier,
      ),
      ChangeNotifierProvider<AuthNotifier>.value(value: authNotifier),
    ],
    child: MaterialApp(
      home: MainShellScreen(
        addLocationMapBuilder: createFakeMapBuilder(addFakeMap),
        discoveryMapBuilder: createFakeMapBuilder(discoveryFakeMap),
        formIdGenerator: formIdGenerator,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryLocationRepository locationRepo;
  late LocationNotifier locationNotifier;
  late MapDiscoveryNotifier discoveryNotifier;
  late FakeMapState addFakeMap;
  late FakeMapState discoveryFakeMap;
  late FakeAuthRepository authRepo;
  late AuthNotifier authNotifier;

  setUp(() {
    final initialCoords = Coordinates(latitude: 14.5839, longitude: 121.0617);
    locationRepo = InMemoryLocationRepository(
      initialCoordinates: initialCoords,
      initialPermission: LocationPermissionState.granted,
    );
    locationNotifier = LocationNotifier(locationRepository: locationRepo);
    authRepo = FakeAuthRepository(initialUid: 'anon_uid_999');
    authNotifier = AuthNotifier(authRepository: authRepo);
    addFakeMap = FakeMapState();
    discoveryFakeMap = FakeMapState();
  });

  Future<void> navigateToAddForm(
    WidgetTester tester, {
    String name = 'Test Staging Facility',
  }) async {
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.byType(AddRestroomLocationScreen), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(AddRestroomFormScreen), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, name);
    await tester.pumpAndSettle();
  }

  group('P2.6-B — UI Integration & UX Preservation', () {
    testWidgets(
      'Rate-limit rejection preserves draft, surfaces Resume, and reopens identical draft',
      (tester) async {
        final idGenerator = CountingRestroomIdGenerator(
          'stable_rate_limit_test_id',
        );

        final callableTransport = CallableRestroomSubmissionTransport(
          callableInvoker: (payload) async {
            throw const RepositoryException(
              'Daily submission limit reached. You may submit up to 10 restrooms per 24 hours.',
              'rate-limited',
            );
          },
        );

        final repo = FirestoreRestroomRepository(
          authRepository: authRepo,
          submissionTransport: callableTransport,
          appConfig: const AppConfig(
            environment: Environment.staging,
            firebaseProjectId: AppConstants.stagingFirebaseProjectId,
            useCallableSubmission: true,
          ),
        );

        discoveryNotifier = MapDiscoveryNotifier(
          restroomRepository: repo,
          debounceDuration: Duration.zero,
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: repo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            formIdGenerator: idGenerator,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Open Add Restroom flow and enter draft
        await navigateToAddForm(tester, name: 'Rate Limited Restroom');

        // 2. Submit form
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // 3. Rate-limit message displayed in SnackBar with Resume action
        expect(
          find.text(
            'Daily submission limit reached. You may submit up to 10 restrooms per 24 hours.',
          ),
          findsOneWidget,
        );
        expect(find.text('Resume'), findsOneWidget);

        // 5. Tap Resume action: opens Resume Contribution? dialog
        await tester.tap(find.text('Resume'));
        await tester.pumpAndSettle();

        expect(find.text('Resume Contribution?'), findsOneWidget);
        expect(
          find.text(
            'You have a saved draft for "Rate Limited Restroom". Would you like to resume editing this draft or discard it to start fresh?',
          ),
          findsOneWidget,
        );

        // 6. Tap Resume Draft
        await tester.tap(find.text('Resume Draft'));
        await tester.pumpAndSettle();

        expect(find.byType(AddRestroomFormScreen), findsOneWidget);
        expect(find.text('Rate Limited Restroom'), findsOneWidget);

        // Stable ID generator must NOT have been called again (ID preserved)
        expect(idGenerator.generateCalls, equals(1));
      },
    );

    testWidgets(
      '10. Canonical map-refresh behavior after successful callable submission: switches to map, zoom 16.5, Unverified preview',
      (tester) async {
        final idGenerator = CountingRestroomIdGenerator(
          'successful_callable_restroom_123',
        );

        final callableTransport = CallableRestroomSubmissionTransport(
          callableInvoker: (payload) async {
            final lat = (payload['latitude'] as num).toDouble();
            final lng = (payload['longitude'] as num).toDouble();
            return {
              'success': true,
              'restroom': {
                'id': payload['restroomId'],
                'name': payload['name'],
                'latitude': lat,
                'longitude': lng,
                'geohash': GeohashService.encode(
                  Coordinates(latitude: lat, longitude: lng),
                ),
                'accessType': payload['accessType'],
                'status': 'unverified',
                'averageRating': 0.0,
                'ratingCount': 0,
                'createdAt': {'_seconds': 1760000000, '_nanoseconds': 0},
                'updatedAt': {'_seconds': 1760000000, '_nanoseconds': 0},
              },
            };
          },
        );

        final repo = TestCallableIntegrationRepository(
          submissionTransport: callableTransport,
        );

        discoveryNotifier = MapDiscoveryNotifier(
          restroomRepository: repo,
          debounceDuration: Duration.zero,
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: repo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            formIdGenerator: idGenerator,
          ),
        );
        await tester.pumpAndSettle();

        // Open Add Restroom flow and enter draft
        await navigateToAddForm(
          tester,
          name: 'Newly Submitted Callable Facility',
        );

        // Submit form
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Simulate camera settlement at zoom 16.5
        expect(discoveryFakeMap.controller.lastRequestedZoom, equals(16.5));
        discoveryFakeMap.simulateIdle();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify successful submission UI
        expect(
          find.text(
            'Restroom "Newly Submitted Callable Facility" submitted successfully.',
          ),
          findsOneWidget,
        );

        // Verify Unverified preview bottom sheet opened for the submitted facility
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text('Newly Submitted Callable Facility'), findsWidgets);
        expect(find.text('Unverified'), findsOneWidget);
      },
    );

    testWidgets(
      '11. Independent map discovery verification (MINOR-1): when callable submission succeeds but discovery omits the facility, surfaces Refresh SnackBar without optimistic preview',
      (tester) async {
        final idGenerator = CountingRestroomIdGenerator(
          'omitted_discovery_restroom_123',
        );

        final callableTransport = CallableRestroomSubmissionTransport(
          callableInvoker: (payload) async {
            final lat = (payload['latitude'] as num).toDouble();
            final lng = (payload['longitude'] as num).toDouble();
            return {
              'success': true,
              'restroom': {
                'id': payload['restroomId'],
                'name': payload['name'],
                'latitude': lat,
                'longitude': lng,
                'geohash': GeohashService.encode(
                  Coordinates(latitude: lat, longitude: lng),
                ),
                'accessType': payload['accessType'],
                'status': 'unverified',
                'averageRating': 0.0,
                'ratingCount': 0,
                'createdAt': {'_seconds': 1760000000, '_nanoseconds': 0},
                'updatedAt': {'_seconds': 1760000000, '_nanoseconds': 0},
              },
            };
          },
        );

        final repo = TestCallableIntegrationRepository(
          submissionTransport: callableTransport,
          returnSubmittedInDiscovery:
              false, // Facility omitted by backend discovery
        );

        discoveryNotifier = MapDiscoveryNotifier(
          restroomRepository: repo,
          debounceDuration: Duration.zero,
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: repo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            formIdGenerator: idGenerator,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Open Add Restroom flow and enter draft
        await navigateToAddForm(tester, name: 'Facility Absent From Discovery');

        // 2. Submit form
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Simulate camera settlement at zoom 16.5
        expect(discoveryFakeMap.controller.lastRequestedZoom, equals(16.5));
        discoveryFakeMap.simulateIdle();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));

        // 3. Verify that RestroomPreviewSheet is NOT shown (no optimistic preview)
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // 4. Verify recovery SnackBar is shown with 'Refresh' action
        expect(
          find.text(
            'Restroom saved, but not yet visible on map. Tap Refresh to re-check.',
          ),
          findsOneWidget,
        );
        expect(find.text('Refresh'), findsOneWidget);

        // 5. Now simulate the facility appearing in discovery backend
        repo.returnSubmittedInDiscovery = true;

        // 6. Tap 'Refresh' action
        await tester.tap(find.text('Refresh'));
        await tester.pumpAndSettle();

        // Simulate camera movement/idle for refreshed search
        discoveryFakeMap.simulateIdle();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));

        // 7. Now the facility is found, and preview sheet opens
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text('Facility Absent From Discovery'), findsWidgets);
        expect(find.text('Unverified'), findsOneWidget);
      },
    );
  });
}

class TestCallableIntegrationRepository implements RestroomRepository {
  final RestroomSubmissionTransport submissionTransport;
  Restroom? lastSubmittedRestroom;
  bool returnSubmittedInDiscovery;

  TestCallableIntegrationRepository({
    required this.submissionTransport,
    this.returnSubmittedInDiscovery = true,
  });

  @override
  Future<Restroom> submitRestroom(CreateRestroomCommand command) async {
    final restroom = await submissionTransport.submitRestroom(
      command: command,
      uid: 'anon_uid_999',
    );
    lastSubmittedRestroom = restroom;
    return restroom;
  }

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async {
    if (returnSubmittedInDiscovery && lastSubmittedRestroom != null) {
      return DiscoveryResult.complete(items: [lastSubmittedRestroom!]);
    }
    return DiscoveryResult.complete(items: const []);
  }

  @override
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    if (returnSubmittedInDiscovery && lastSubmittedRestroom != null) {
      return DiscoveryResult.complete(items: [lastSubmittedRestroom!]);
    }
    return DiscoveryResult.complete(items: const []);
  }

  @override
  Future<DiscoveryResult<Restroom>> getDuplicateCandidates(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) async {
    return DiscoveryResult.complete(items: const []);
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    if (lastSubmittedRestroom?.id == id) return lastSubmittedRestroom;
    return null;
  }
}
