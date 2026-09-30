import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';

/// Service boundary managing Firebase App Check activation.
/// Enforces environment-appropriate provider strategy:
/// - Debug provider for development & testing
/// - Play Integrity for Android release builds
/// - App Attest with DeviceCheck fallback for Apple release builds
class FirebaseAppCheckService {
  final AppConfig _config;

  FirebaseAppCheckService({required this._config});

  Future<void> initialize() async {
    if (!_config.enableAppCheck) {
      debugPrint('[AppCheck] Disabled by configuration.');
      return;
    }

    try {
      if (kDebugMode || _config.isDevelopment) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidDebugProvider(),
          providerApple: const AppleDebugProvider(),
        );
        debugPrint('[AppCheck] Activated with Debug provider.');
      } else {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidPlayIntegrityProvider(),
          providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
        debugPrint(
          '[AppCheck] Activated with Production providers (Play Integrity / App Attest).',
        );
      }
    } catch (e) {
      // In local development or environments without Play Services / Apple entitlements,
      // log warning instead of crashing app initialization.
      debugPrint('[AppCheck] Initialization notice: $e');
    }
  }
}
