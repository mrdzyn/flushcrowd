import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:flushcrowd/core/config/app_config.dart';
import 'package:flushcrowd/core/config/environment.dart';
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

  @override
  Future<String> ensureAnonymousSession() async {
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

class FakeMapCameraController
    implements MapCameraController, MapViewportController {
  final FakeMapState fakeMapState;
  int animateCameraCalls = 0;
  int moveCameraCalls = 0;
  CameraUpdate? lastCameraUpdate;
  double? lastRequestedZoom;
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

  void simulateMapCreated() {
    isCreated = true;
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
  AppConfig config = const AppConfig(environment: Environment.staging),
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
            'Data invariant violation: only one document of the restroom pair exists. Cannot safely submit.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Resume'), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
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
  });
}
