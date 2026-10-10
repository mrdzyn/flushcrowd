import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:flushcrowd/core/config/app_config.dart';
import 'package:flushcrowd/core/config/environment.dart';
import 'package:flushcrowd/core/constants/app_constants.dart';
import 'package:flushcrowd/core/errors/exceptions.dart';
import 'package:flushcrowd/data/repositories/location_repository_impl.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/discovery_result.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/geo_bounding_box.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/repositories/auth_repository.dart';
import 'package:flushcrowd/domain/repositories/location_repository.dart';
import 'package:flushcrowd/domain/repositories/restroom_repository.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/duplicate_warning_sheet.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/restroom_preview_sheet.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_form_screen.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_location_screen.dart';
import 'package:flushcrowd/presentation/screens/main_shell_screen.dart';
import 'package:flushcrowd/presentation/state/auth_notifier.dart';
import 'package:flushcrowd/presentation/state/location_notifier.dart';
import 'package:flushcrowd/presentation/state/map_discovery_notifier.dart';

// --- Test Doubles ---

class FakeAuthRepository implements AuthRepository {
  final StreamController<String?> _authStreamController =
      StreamController<String?>.broadcast();
  String? _uid;
  bool shouldThrowOnSignIn = false;

  FakeAuthRepository({String? initialUid}) : _uid = initialUid;

  @override
  Stream<String?> get authStateChanges => _authStreamController.stream;

  @override
  String? get currentUserId => _uid;

  void setUid(String? uid) {
    _uid = uid;
    _authStreamController.add(uid);
  }

  Completer<String>? signInCompleter;

  @override
  Future<String> ensureAnonymousSession() async {
    if (signInCompleter != null) {
      final uid = await signInCompleter!.future;
      _uid = uid;
      _authStreamController.add(_uid);
      return uid;
    }
    if (shouldThrowOnSignIn) {
      throw const RepositoryException(
        'Simulated network timeout during anonymous sign in',
        'network-error',
      );
    }
    _uid = _uid ?? 'test_anon_uid_123';
    _authStreamController.add(_uid);
    return _uid!;
  }
}

class TestRestroomRepository implements RestroomRepository {
  int submitCount = 0;
  CreateRestroomCommand? lastSubmittedCommand;
  bool submitShouldThrow = false;
  Object? submitErrorToThrow;
  Completer<Restroom>? submitCompleter;

  int discoveryCount = 0;
  DiscoveryResult<Restroom>? viewportResultToReturn;
  bool viewportQueryShouldThrow = false;
  bool returnLastSubmittedInViewport = false;

  int duplicateCount = 0;
  DiscoveryResult<Restroom>? duplicateResultToReturn;
  bool duplicateShouldThrow = false;

  @override
  Future<Restroom> submitRestroom(CreateRestroomCommand command) async {
    submitCount++;
    lastSubmittedCommand = command;

    if (submitCompleter != null) {
      return submitCompleter!.future;
    }

    if (submitShouldThrow) {
      throw submitErrorToThrow ??
          const RepositoryException('Simulated network error', 'network-error');
    }

    return Restroom(
      id: command.restroomId,
      name: command.draft.name,
      coordinates: command.draft.coordinates,
      geohash: 'w4rr7x',
      accessType: command.draft.accessType,
      status: RestroomStatus.unverified,
      createdAt: DateTime.now(),
    );
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
    if (viewportQueryShouldThrow) {
      throw Exception('Viewport query failed');
    }
    if (returnLastSubmittedInViewport && lastSubmittedCommand != null) {
      final cmd = lastSubmittedCommand!;
      return DiscoveryResult.complete(
        items: [
          Restroom(
            id: cmd.restroomId,
            name: cmd.draft.name,
            coordinates: cmd.draft.coordinates,
            geohash: 'w4rr7x',
            accessType: cmd.draft.accessType,
            status: RestroomStatus.unverified,
            createdAt: DateTime.now(),
          ),
        ],
      );
    }
    return viewportResultToReturn ?? DiscoveryResult.complete(items: const []);
  }

  @override
  Future<Restroom?> getRestroomById(String id) async => null;

  @override
  Future<DiscoveryResult<Restroom>> getDuplicateCandidates(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) async {
    duplicateCount++;
    if (duplicateShouldThrow) {
      throw Exception('Simulated network timeout during duplicate scan');
    }
    return duplicateResultToReturn ?? DiscoveryResult.complete(items: const []);
  }
}

class ThrowingDiscoveryNotifier extends MapDiscoveryNotifier {
  ThrowingDiscoveryNotifier({required super.restroomRepository})
    : super(debounceDuration: Duration.zero);

  @override
  void focusOnSubmittedRestroom({
    required Coordinates coordinates,
    required String restroomId,
    required String facilityName,
    double zoom = 16.5,
  }) {
    throw Exception('Simulated map focus initiation crash');
  }
}

class FakeMapCameraController
    implements MapCameraController, MapViewportController {
  final FakeMapState fakeMapState;
  int animateCameraCalls = 0;
  int moveCameraCalls = 0;
  CameraUpdate? lastCameraUpdate;
  double? lastRequestedZoom;
  bool autoSettle = true;
  bool shouldThrow = false;
  LatLngBounds? Function()? visibleRegionOverride;

  FakeMapCameraController(this.fakeMapState);

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate) async {
    animateCameraCalls++;
    lastCameraUpdate = cameraUpdate;
    if (shouldThrow) {
      throw Exception('Platform animateCamera failed');
    }
    fakeMapState.simulateMoveStarted();
    if (autoSettle) {
      _applyUpdate(cameraUpdate);
      fakeMapState.simulateIdle();
    }
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {
    moveCameraCalls++;
    lastCameraUpdate = cameraUpdate;
    if (shouldThrow) {
      throw Exception('Platform moveCamera failed');
    }
    fakeMapState.simulateMoveStarted();
    if (autoSettle) {
      _applyUpdate(cameraUpdate);
      fakeMapState.simulateIdle();
    }
  }

  @override
  Future<LatLngBounds?> getVisibleRegion() async {
    if (visibleRegionOverride != null) {
      return visibleRegionOverride!();
    }
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

  void simulateMapCreated() {
    isCreated = true;
    onMapCreated?.call(controller);
  }

  void simulateMoveStarted() {
    onCameraMoveStarted?.call();
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
  required TestRestroomRepository restroomRepo,
  required LocationRepository locationRepo,
  required LocationNotifier locationNotifier,
  required MapDiscoveryNotifier discoveryNotifier,
  required FakeMapState addFakeMap,
  required FakeMapState discoveryFakeMap,
  AuthNotifier? authNotifier,
  AppConfig? config = const AppConfig(
    environment: Environment.staging,
    firebaseProjectId: AppConstants.stagingFirebaseProjectId,
  ),
}) {
  return MultiProvider(
    providers: [
      if (config != null) Provider<AppConfig>.value(value: config),
      Provider<RestroomRepository>.value(value: restroomRepo),
      Provider<LocationRepository>.value(value: locationRepo),
      ChangeNotifierProvider<LocationNotifier>.value(value: locationNotifier),
      ChangeNotifierProvider<MapDiscoveryNotifier>.value(
        value: discoveryNotifier,
      ),
      if (authNotifier != null)
        ChangeNotifierProvider<AuthNotifier>.value(value: authNotifier),
    ],
    child: MaterialApp(
      home: MainShellScreen(
        addLocationMapBuilder: createFakeMapBuilder(addFakeMap),
        discoveryMapBuilder: createFakeMapBuilder(discoveryFakeMap),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestRestroomRepository restroomRepo;
  late InMemoryLocationRepository locationRepo;
  late LocationNotifier locationNotifier;
  late MapDiscoveryNotifier discoveryNotifier;
  late FakeMapState addFakeMap;
  late FakeMapState discoveryFakeMap;
  late FakeAuthRepository authRepo;
  late AuthNotifier authNotifier;

  setUp(() {
    restroomRepo = TestRestroomRepository();
    locationRepo = InMemoryLocationRepository(
      initialCoordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
      initialPermission: LocationPermissionState.granted,
    );
    locationNotifier = LocationNotifier(locationRepository: locationRepo);
    discoveryNotifier = MapDiscoveryNotifier(
      restroomRepository: restroomRepo,
      debounceDuration: Duration.zero,
    );
    addFakeMap = FakeMapState();
    discoveryFakeMap = FakeMapState();
    authRepo = FakeAuthRepository(initialUid: 'authenticated_user_uid');
    authNotifier = AuthNotifier(authRepository: authRepo);
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

  group('P2.5-A — Staging Runtime & Identity Safety', () {
    testWidgets(
      'A.1 Anonymous session absent -> signInAnonymously failure does not write, preserves draft, surfaces Retry',
      (tester) async {
        final unauthRepo = FakeAuthRepository(initialUid: null);
        unauthRepo.shouldThrowOnSignIn = true;
        final unauthNotifier = AuthNotifier(authRepository: unauthRepo);

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: unauthNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Auth Fail Restroom');

        // Submit form
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Zero repository writes
        expect(restroomRepo.submitCount, equals(0));

        // Surfaces authentication error SnackBar with Retry action
        expect(
          find.text(
            'Unable to sign in anonymously. Please check your internet connection and try again.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

        // Draft is preserved: tapping Add again shows resume dialog
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(find.text('Resume Contribution?'), findsOneWidget);
      },
    );

    testWidgets(
      'A.2 Staging Firebase initialization failure (firebase-init-failed) surfaces Resume, does not pretend save succeeded in memory',
      (tester) async {
        restroomRepo.submitShouldThrow = true;
        restroomRepo.submitErrorToThrow = const RepositoryException(
          'Submission is unavailable because staging Firebase configuration failed to initialize.',
          'firebase-init-failed',
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Staging Init Failed Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'Submission is unavailable because staging Firebase configuration failed to initialize.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);

        // Does NOT pretend success
        expect(find.textContaining('submitted successfully'), findsNothing);
      },
    );

    testWidgets(
      'A.3 Production safety gate blocks submission write until P2.6',
      (tester) async {
        const prodConfig = AppConfig(environment: Environment.production);

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            config: prodConfig,
          ),
        );

        await navigateToAddForm(tester, name: 'Prod Blocked Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Write is blocked at gate before repo call
        expect(restroomRepo.submitCount, equals(0));
        expect(
          find.text(
            'Community restroom contributions are currently disabled in production until server-side abuse protections are active (Milestone P2.6).',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
      },
    );

    testWidgets(
      'A.4 Default development config (Environment.development) blocks submission write, preserves draft',
      (tester) async {
        const devConfig = AppConfig(environment: Environment.development);

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            config: devConfig,
          ),
        );

        await navigateToAddForm(tester, name: 'Dev Blocked Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(0));
        expect(
          find.text(
            'Community restroom contributions are only permitted in the verified staging environment.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
      },
    );

    testWidgets(
      'A.5 Unknown environment config (Environment.unknown) blocks submission write, preserves draft',
      (tester) async {
        const unknownConfig = AppConfig(environment: Environment.unknown);

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            config: unknownConfig,
          ),
        );

        await navigateToAddForm(tester, name: 'Unknown Env Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(0));
        expect(
          find.text(
            'Community restroom contributions are only permitted in the verified staging environment.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
      },
    );

    testWidgets(
      'A.6 Missing config (config: null) blocks submission write, preserves draft',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            config: null,
          ),
        );

        await navigateToAddForm(tester, name: 'Unconfigured Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(0));
        expect(
          find.text(
            'Community restroom contributions are unavailable due to missing application configuration.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
      },
    );

    testWidgets(
      'A.7 Staging config with mismatched Firebase project ID blocks submission write, preserves draft',
      (tester) async {
        const mismatchedConfig = AppConfig(
          environment: Environment.staging,
          firebaseProjectId: 'flushcrowd-production',
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            config: mismatchedConfig,
          ),
        );

        await navigateToAddForm(tester, name: 'Mismatched Project Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(0));
        expect(
          find.text(
            'Community restroom contributions are restricted to the verified staging Firebase project (flushcrowd-staging).',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
      },
    );

    testWidgets(
      'A.8 Staging config with null Firebase project ID blocks submission write, preserves draft',
      (tester) async {
        const noProjectConfig = AppConfig(
          environment: Environment.staging,
          firebaseProjectId: null,
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
            config: noProjectConfig,
          ),
        );

        await navigateToAddForm(tester, name: 'No Project Staging Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(0));
        expect(
          find.text(
            'Community restroom contributions are restricted to the verified staging Firebase project (flushcrowd-staging).',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
      },
    );
  });

  group('P2.5-B — Single-Flight Submit & Recoverable Failures', () {
    testWidgets(
      'B.1 Stable restroomId reuse: failed submission allows Retry with identical command and restroomId',
      (tester) async {
        restroomRepo.submitShouldThrow = true;
        restroomRepo.submitErrorToThrow = const RepositoryException(
          'Simulated network timeout',
          'network-error',
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Stable ID Facility');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        final firstAttemptCommand = restroomRepo.lastSubmittedCommand;
        expect(firstAttemptCommand, isNotNull);
        final initialRestroomId = firstAttemptCommand!.restroomId;

        expect(
          find.text(
            'Connection failed. Please check your internet connection.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

        // Configure repository to succeed on retry
        restroomRepo.submitShouldThrow = false;
        restroomRepo.returnLastSubmittedInViewport = true;

        // Tap Retry on failure snackbar
        await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(restroomRepo.submitCount, equals(2));
        final secondAttemptCommand = restroomRepo.lastSubmittedCommand;
        expect(secondAttemptCommand, isNotNull);

        // Identical restroomId preserved!
        expect(secondAttemptCommand!.restroomId, equals(initialRestroomId));
        expect(
          find.text('Restroom "Stable ID Facility" submitted successfully.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'B.2 Single-flight submit: duplicate taps while submission is in-flight do not double-submit',
      (tester) async {
        final submitCompleter = Completer<Restroom>();
        restroomRepo.submitCompleter = submitCompleter;
        restroomRepo.returnLastSubmittedInViewport = true;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Single Flight Restroom');

        // First tap initiates submission
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump(); // starts _submitRestroom

        expect(restroomRepo.submitCount, equals(1));
        expect(find.text('Submitting restroom...'), findsAtLeastNWidgets(1));

        // Attempting to tap Add button on shell during flight is ignored
        await tester.tap(find.text('Add'));
        await tester.pump();
        expect(find.byType(AddRestroomLocationScreen), findsNothing);

        // Complete the flight
        submitCompleter.complete(
          Restroom(
            id: restroomRepo.lastSubmittedCommand!.restroomId,
            name: 'Single Flight Restroom',
            coordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
            geohash: 'w4rr7x',
            accessType: AccessType.free,
            status: RestroomStatus.unverified,
            createdAt: DateTime.now(),
          ),
        );
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'Restroom "Single Flight Restroom" submitted successfully.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'B.3 SubmissionInvariantException surfaces data invariant violation and offers Resume (no blind retry)',
      (tester) async {
        restroomRepo.submitShouldThrow = true;
        restroomRepo.submitErrorToThrow = const SubmissionInvariantException(
          'Invariant violation: only one document of the atomic restroom pair exists.',
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Invariant Broken Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Data invariant violation: only one document of the atomic restroom pair exists.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
      },
    );

    testWidgets(
      'B.4 Single-flight submit locks before anonymous sign-in: multiple taps during sign-in trigger exactly 1 repository write',
      (tester) async {
        final delayedAuthRepo = FakeAuthRepository(initialUid: null);
        final signInCompleter = Completer<String>();
        delayedAuthRepo.signInCompleter = signInCompleter;
        final delayedAuthNotifier = AuthNotifier(
          authRepository: delayedAuthRepo,
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: delayedAuthNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Lock Ordering Restroom');

        // First tap initiates submission and begins anonymous sign-in
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();

        // While sign-in is pending, attempt a second submission tap
        await tester.tap(
          find.widgetWithText(LooPrimaryButton, 'Continue'),
          warnIfMissed: false,
        );
        await tester.pump();

        // Also attempt tapping Add on shell during flight
        await tester.tap(find.text('Add'));
        await tester.pump();

        expect(restroomRepo.submitCount, equals(0));

        // Now complete the anonymous sign-in
        signInCompleter.complete('newly_signed_in_uid');
        restroomRepo.returnLastSubmittedInViewport = true;
        await tester.pumpAndSettle();

        // Exactly one repository write occurred!
        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'Restroom "Lock Ordering Restroom" submitted successfully.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('P2.5-C — Canonical Discovery Synchronization', () {
    testWidgets(
      'C.1 Confirmed submission animates camera to zoom 16.5, triggers authoritative discovery, selects by ID, and opens Unverified preview',
      (tester) async {
        const submittedName = 'Authoritative Restroom';

        restroomRepo.submitCompleter = null;
        restroomRepo.returnLastSubmittedInViewport = true;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // 1. Verify camera was animated to zoom 16.5
        expect(
          discoveryFakeMap.controller.animateCameraCalls,
          greaterThanOrEqualTo(1),
        );
        expect(discoveryFakeMap.controller.lastRequestedZoom, equals(16.5));

        // 2. Authoritative discovery was triggered
        expect(restroomRepo.discoveryCount, greaterThanOrEqualTo(1));

        // 3. Exactly one RestroomPreviewSheet is opened
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text(submittedName), findsAtLeastNWidgets(1));

        // 4. Preview sheet clearly displays "Unverified" status chip
        expect(find.text('Unverified'), findsOneWidget);
      },
    );

    testWidgets(
      'C.2 Authoritative query omission surfaces recovery SnackBar with Refresh action without opening false preview',
      (tester) async {
        const submittedName = 'Backend Delayed Restroom';

        // Authoritative query returns empty list (simulating backend delay or omission)
        restroomRepo.returnLastSubmittedInViewport = false;
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: const [],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Preview sheet is NOT opened falsely
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // Surfaces explicit Refresh recovery SnackBar
        expect(
          find.text(
            'Restroom saved, but not yet visible on map. Tap Refresh to re-check.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Refresh'), findsOneWidget);
      },
    );

    testWidgets(
      'C.3 Delayed camera settlement: authoritative query does not fire until camera settles on coordinates',
      (tester) async {
        const submittedName = 'Delayed Settle Restroom';
        restroomRepo.returnLastSubmittedInViewport = true;
        discoveryFakeMap.controller.autoSettle = false;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        final initialDiscoveryCount = restroomRepo.discoveryCount;

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Camera animation was initiated
        expect(
          discoveryFakeMap.controller.animateCameraCalls,
          greaterThanOrEqualTo(1),
        );

        // Map has not settled yet -> discovery query NOT yet fired for submitted restroom
        expect(restroomRepo.discoveryCount, equals(initialDiscoveryCount));
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // Now camera settles on the submitted coordinates
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 16.5),
        );
        discoveryFakeMap.simulateIdle();
        await tester.pumpAndSettle();

        // Query fires after settlement and opens preview
        expect(restroomRepo.discoveryCount, greaterThan(initialDiscoveryCount));
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text(submittedName), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'C.4 Premature camera idle on intermediate/stale bounds does not trigger query until bounds contain coordinates',
      (tester) async {
        const submittedName = 'Stale Bounds Restroom';
        restroomRepo.returnLastSubmittedInViewport = true;
        discoveryFakeMap.controller.autoSettle = false;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        final initialDiscoveryCount = restroomRepo.discoveryCount;

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Intermediate idle at (0.0, 0.0) — does NOT contain (14.5839, 121.0617)
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: LatLng(0.0, 0.0), zoom: 10.0),
        );
        discoveryFakeMap.simulateIdle();
        await tester.pump();

        // Should NOT trigger query for submitted restroom
        expect(restroomRepo.discoveryCount, equals(initialDiscoveryCount));
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // Final settlement at submitted coordinates
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 16.5),
        );
        discoveryFakeMap.simulateIdle();
        await tester.pumpAndSettle();

        expect(restroomRepo.discoveryCount, greaterThan(initialDiscoveryCount));
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
      },
    );

    testWidgets(
      'C.5 Stale focus intent race during settlement: newer focus intent supersedes earlier settlement',
      (tester) async {
        restroomRepo.returnLastSubmittedInViewport = true;
        discoveryFakeMap.controller.autoSettle = false;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Restroom A');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // While Restroom A focus is waiting for settlement, a newer focus intent B arrives
        final restroomB = Restroom(
          id: 'restroom_b',
          name: 'Restroom B',
          coordinates: Coordinates(latitude: 14.5900, longitude: 121.0700),
          geohash: 'w4rr7y',
          accessType: AccessType.free,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );
        discoveryNotifier.focusOnRestroom(restroomB);
        await tester.pump();

        // Now older settlement finishes for Restroom A coordinates
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 16.5),
        );
        discoveryFakeMap.simulateIdle();
        await tester.pumpAndSettle();

        // Restroom A preview sheet should NOT be opened
        expect(
          find.widgetWithText(RestroomPreviewSheet, 'Restroom A'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'C.6 Unverified/out-of-bounds settlement surfaces recovery SnackBar without 500m speculative fallback',
      (tester) async {
        const submittedName = 'Out Of Bounds Restroom';
        restroomRepo.returnLastSubmittedInViewport = true;
        discoveryFakeMap.controller.visibleRegionOverride = () => LatLngBounds(
          southwest: const LatLng(0.0, 0.0),
          northeast: const LatLng(0.01, 0.01),
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // Preview sheet should NOT open
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // Surfaces explicit recovery SnackBar without 500m fallback
        expect(
          find.text(
            'Restroom saved, but map could not confirm centering on $submittedName. Tap to retry.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'C.7 Authoritative discovery query error surfaces retry SnackBar without false preview',
      (tester) async {
        const submittedName = 'Query Error Restroom';
        restroomRepo.viewportQueryShouldThrow = true;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Preview sheet NOT opened
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // Surfaces discovery failure SnackBar
        expect(
          find.text(
            'Restroom saved, but discovery refresh encountered an error. Tap Refresh to try again.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Refresh'), findsOneWidget);
      },
    );

    testWidgets(
      'C.8 Map focus initiation failure surfaces recoverable SnackBar with Center action',
      (tester) async {
        final throwingNotifier = ThrowingDiscoveryNotifier(
          restroomRepository: restroomRepo,
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: throwingNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Focus Crash Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Restroom saved, but map could not navigate automatically. Tap to center.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Center'), findsOneWidget);
      },
    );

    testWidgets(
      'C.9 Wrong zoom rejected during delayed camera settlement: intermediate idle at zoom 13 does not trigger query or preview; final 16.5 idle triggers exactly one authoritative query and preview',
      (tester) async {
        const submittedName = 'Zoom Tolerance Restroom';
        restroomRepo.returnLastSubmittedInViewport = true;
        discoveryFakeMap.controller.autoSettle = false;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        final initialDiscoveryCount = restroomRepo.discoveryCount;

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Step 1: Intermediate idle at submitted coordinates, but at zoom 13.0 (wrong zoom)
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 13.0),
        );
        discoveryFakeMap.simulateIdle();
        await tester.pump();

        // Must NOT trigger authoritative query or open preview at zoom 13.0
        expect(restroomRepo.discoveryCount, equals(initialDiscoveryCount));
        expect(find.byType(RestroomPreviewSheet), findsNothing);

        // Step 2: Camera settles at the requested zoom 16.5
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 16.5),
        );
        discoveryFakeMap.simulateIdle();
        await tester.pumpAndSettle();

        // Exactly one authoritative query fired and preview sheet opened
        expect(restroomRepo.discoveryCount, equals(initialDiscoveryCount + 1));
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text(submittedName), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'C.10 Stale P2.5 recovery actions: newer focus B supersedes failure A, dismisses A recovery SnackBar, and old A callback cannot override B',
      (tester) async {
        const submittedNameA = 'Restroom A';
        restroomRepo.returnLastSubmittedInViewport = false;
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: const [],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedNameA);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // A's recovery snackbar is visible
        expect(
          find.text(
            'Restroom saved, but not yet visible on map. Tap Refresh to re-check.',
          ),
          findsOneWidget,
        );
        final oldRefreshAction = tester.widget<SnackBarAction>(
          find.widgetWithText(SnackBarAction, 'Refresh'),
        );

        // Now user focuses on another restroom B
        final restroomB = Restroom(
          id: 'restroom_b',
          name: 'Restroom B',
          coordinates: Coordinates(latitude: 14.5900, longitude: 121.0700),
          geohash: 'w4rr7y',
          accessType: AccessType.free,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: [restroomB],
        );
        discoveryNotifier.focusOnRestroom(restroomB);
        await tester.pumpAndSettle();

        // A's recovery snackbar must be dismissed
        expect(
          find.text(
            'Restroom saved, but not yet visible on map. Tap Refresh to re-check.',
          ),
          findsNothing,
        );

        // Selection is B
        expect(discoveryNotifier.selectedRestroom, equals(restroomB));

        // Tapping old Refresh callback for A cannot override B
        oldRefreshAction.onPressed();
        await tester.pumpAndSettle();

        // Selection remains B, no pending focus for A
        expect(discoveryNotifier.selectedRestroom, equals(restroomB));
        expect(discoveryNotifier.pendingFocusIntent, isNull);
      },
    );

    testWidgets(
      'C.11 Stale P2.5 recovery actions: explicit user selection of B supersedes failure A, dismisses A recovery SnackBar, and old A callback cannot override B; current A recovery still functions',
      (tester) async {
        const submittedNameA = 'Restroom A';
        restroomRepo.returnLastSubmittedInViewport = false;
        restroomRepo.viewportResultToReturn = DiscoveryResult.complete(
          items: const [],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedNameA);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // A's recovery snackbar is visible
        expect(
          find.text(
            'Restroom saved, but not yet visible on map. Tap Refresh to re-check.',
          ),
          findsOneWidget,
        );
        final oldRefreshAction = tester.widget<SnackBarAction>(
          find.widgetWithText(SnackBarAction, 'Refresh'),
        );

        // User explicitly selects restroom B on the map
        final restroomB = Restroom(
          id: 'restroom_b',
          name: 'Restroom B',
          coordinates: Coordinates(latitude: 14.5900, longitude: 121.0700),
          geohash: 'w4rr7y',
          accessType: AccessType.free,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );
        discoveryNotifier.selectRestroom(restroomB);
        await tester.pumpAndSettle();

        // A's recovery snackbar must be dismissed
        expect(
          find.text(
            'Restroom saved, but not yet visible on map. Tap Refresh to re-check.',
          ),
          findsNothing,
        );

        // Attempting to invoke old Refresh callback for A cannot override B
        oldRefreshAction.onPressed();
        await tester.pumpAndSettle();

        // Selection remains B
        expect(discoveryNotifier.selectedRestroom, equals(restroomB));
        expect(discoveryNotifier.pendingFocusIntent, isNull);

        // Now test valid current recovery for A:
        // Clear selection and re-trigger submitted focus for A where discovery now finds it
        discoveryNotifier.selectRestroom(null);
        restroomRepo.returnLastSubmittedInViewport = true;
        final submittedRestroomId =
            restroomRepo.lastSubmittedCommand!.restroomId;

        discoveryNotifier.focusOnSubmittedRestroom(
          coordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
          restroomId: submittedRestroomId,
          facilityName: submittedNameA,
          zoom: 16.5,
        );
        await tester.pumpAndSettle();

        // Valid recovery succeeded: preview sheet opened for A
        expect(find.byType(RestroomPreviewSheet), findsOneWidget);
        expect(find.text(submittedNameA), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'C.12 Completer disposal race: widget disposal while camera settlement is pending completes safely without error',
      (tester) async {
        const submittedName = 'Pending Teardown Restroom';
        restroomRepo.returnLastSubmittedInViewport = true;
        discoveryFakeMap.controller.autoSettle = false;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Camera settlement is pending. Immediately unmount/tear down widget tree:
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        // Must complete teardown without throwing any StateError
        expect(find.byType(MainShellScreen), findsNothing);
      },
    );

    testWidgets(
      'C.13 Completer disposal race: widget disposal immediately after settlement completes does not throw already-completed StateError',
      (tester) async {
        const submittedName = 'Settled Teardown Restroom';
        restroomRepo.returnLastSubmittedInViewport = true;
        discoveryFakeMap.controller.autoSettle = false;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: submittedName);

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Simulate camera idle settlement
        discoveryFakeMap.simulateMove(
          const CameraPosition(target: LatLng(14.5839, 121.0617), zoom: 16.5),
        );
        discoveryFakeMap.simulateIdle();

        // Immediately tear down widget tree in the same test turn
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        // Must tear down cleanly without StateError: Future already completed
        expect(find.byType(MainShellScreen), findsNothing);
      },
    );
  });

  group('P2.5-D — Duplicate Warning Integration & Error Recovery', () {
    testWidgets(
      'D.1 Duplicate detection query error fails open: proceeds to submission, includes advisory fail-open note',
      (tester) async {
        restroomRepo.duplicateShouldThrow = true;
        restroomRepo.returnLastSubmittedInViewport = true;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Fail Open Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'Duplicate check could not be completed, but contribution proceeds (advisory fail-open). Restroom "Fail Open Restroom" submitted successfully.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'D.2 Duplicate detection partial scan: proceeds to submission, includes advisory partial scan note',
      (tester) async {
        restroomRepo.duplicateResultToReturn = DiscoveryResult.partial(
          items: const [],
          reason: DiscoveryCompletenessReason.rangeCapExceeded,
        );
        restroomRepo.returnLastSubmittedInViewport = true;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Partial Scan Facility');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'No likely duplicates found in the results checked, but the duplicate scan was incomplete. Restroom "Partial Scan Facility" submitted successfully.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'D.3 Duplicate warning acknowledged via "No, It\'s a Different Restroom" proceeds to submission',
      (tester) async {
        final existing = Restroom(
          id: 'existing_candidate_1',
          name: 'Airport Terminal Restroom',
          coordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
          geohash: 'w4rr7x',
          accessType: AccessType.free,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );
        restroomRepo.duplicateResultToReturn = DiscoveryResult.complete(
          items: [existing],
        );
        restroomRepo.returnLastSubmittedInViewport = true;

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Airport Terminal Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(DuplicateWarningSheet), findsOneWidget);

        // Tap "No, It's a Different Restroom"
        await tester.tap(
          find.widgetWithText(
            LooPrimaryButton,
            "No, It's a Different Restroom",
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DuplicateWarningSheet), findsNothing);
        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'Restroom "Airport Terminal Restroom" submitted successfully.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'D.4 Duplicate warning dismissed preserves draft with Review action and does NOT submit',
      (tester) async {
        final existing = Restroom(
          id: 'existing_candidate_2',
          name: 'City Mall Restroom',
          coordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
          geohash: 'w4rr7x',
          accessType: AccessType.free,
          status: RestroomStatus.active,
          createdAt: DateTime.now(),
        );
        restroomRepo.duplicateResultToReturn = DiscoveryResult.complete(
          items: [existing],
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'City Mall Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(DuplicateWarningSheet), findsOneWidget);

        // Dismiss warning sheet without choosing buttons
        Navigator.of(tester.element(find.byType(DuplicateWarningSheet))).pop();
        await tester.pumpAndSettle();

        expect(find.byType(DuplicateWarningSheet), findsNothing);
        expect(restroomRepo.submitCount, equals(0));

        // Draft preservation SnackBar with Review action
        expect(
          find.text(
            'Draft for "City Mall Restroom" preserved. Tap Review to re-check duplicates or resume.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Review'), findsOneWidget);
      },
    );

    testWidgets(
      'D.5 Mid-session authentication invalidation (UnauthenticatedException) preserves draft and offers Retry',
      (tester) async {
        restroomRepo.submitShouldThrow = true;
        restroomRepo.submitErrorToThrow = const UnauthenticatedException();

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Unauth Error Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'Authentication required. Please check your connection and try again.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'D.6 Server permission denied error surfaces permission error SnackBar and preserves draft',
      (tester) async {
        restroomRepo.submitShouldThrow = true;
        restroomRepo.submitErrorToThrow = const RepositoryException(
          'Missing permission',
          'permission-denied',
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Permission Denied Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text(
            'Submission rejected by server permissions. Please ensure your session is valid.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'D.7 Invalid draft error surfaces validation error SnackBar with Resume action',
      (tester) async {
        restroomRepo.submitShouldThrow = true;
        restroomRepo.submitErrorToThrow = const RepositoryException(
          'Coordinates are out of bounds.',
          'invalid-draft',
        );

        await tester.pumpWidget(
          createTestApp(
            restroomRepo: restroomRepo,
            locationRepo: locationRepo,
            locationNotifier: locationNotifier,
            discoveryNotifier: discoveryNotifier,
            addFakeMap: addFakeMap,
            discoveryFakeMap: discoveryFakeMap,
            authNotifier: authNotifier,
          ),
        );

        await navigateToAddForm(tester, name: 'Invalid Coords Restroom');

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(restroomRepo.submitCount, equals(1));
        expect(
          find.text('Invalid restroom details: Coordinates are out of bounds.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
      },
    );
  });
}
