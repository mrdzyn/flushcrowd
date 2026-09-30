import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/firestore_restroom_repository.dart';
import 'data/repositories/in_memory_restroom_repository.dart';
import 'data/repositories/location_repository_impl.dart';
import 'data/services/firebase/firebase_app_check_service.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/location_repository.dart';
import 'domain/repositories/restroom_repository.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/state/auth_notifier.dart';
import 'presentation/state/location_notifier.dart';
import 'presentation/state/map_discovery_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();

  // Safe Firebase Initialization Boundary
  AuthRepository authRepository;
  RestroomRepository restroomRepository;

  try {
    await Firebase.initializeApp();
    final appCheckService = FirebaseAppCheckService(config: config);
    await appCheckService.initialize();

    authRepository = FirebaseAuthRepositoryImpl();
    restroomRepository = FirestoreRestroomRepository();
  } catch (e) {
    // If Firebase configuration files (google-services.json / GoogleService-Info.plist)
    // are not yet provided in the local dev environment, fall back to in-memory repositories.
    debugPrint('[FirebaseInit] Running in offline/development mode: $e');
    authRepository = InMemoryAuthRepository();
    restroomRepository = InMemoryRestroomRepository();
  }

  final locationRepository = LocationRepositoryImpl();

  runApp(
    LooRadarApp(
      config: config,
      authRepository: authRepository,
      restroomRepository: restroomRepository,
      locationRepository: locationRepository,
    ),
  );
}

class LooRadarApp extends StatelessWidget {
  final AppConfig config;
  final AuthRepository authRepository;
  final RestroomRepository restroomRepository;
  final LocationRepository locationRepository;

  const LooRadarApp({
    super.key,
    required this.config,
    required this.authRepository,
    required this.restroomRepository,
    required this.locationRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppConfig>.value(value: config),
        Provider<AuthRepository>.value(value: authRepository),
        Provider<RestroomRepository>.value(value: restroomRepository),
        Provider<LocationRepository>.value(value: locationRepository),
        ChangeNotifierProvider<AuthNotifier>(
          create: (_) => AuthNotifier(authRepository: authRepository),
        ),
        ChangeNotifierProvider<LocationNotifier>(
          create: (_) =>
              LocationNotifier(locationRepository: locationRepository)
                ..checkInitialPermission(),
        ),
        ChangeNotifierProvider<MapDiscoveryNotifier>(
          create: (_) =>
              MapDiscoveryNotifier(restroomRepository: restroomRepository),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      ),
    );
  }
}
