import 'package:flutter/foundation.dart';

import 'environment.dart';

/// Application configuration and environment values.
/// Secrets or platform keys are supplied via --dart-define or native config.
class AppConfig {
  final Environment environment;
  final String mapsApiKeyAndroid;
  final String mapsApiKeyIos;
  final String appCheckDebugToken;
  final bool enableAppCheck;

  const AppConfig({
    required this.environment,
    this.mapsApiKeyAndroid = '',
    this.mapsApiKeyIos = '',
    this.appCheckDebugToken = '',
    this.enableAppCheck = true,
  });

  /// Factory loading configuration from compile-time environment variables.
  factory AppConfig.fromEnvironment() {
    const envString = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const androidKey = String.fromEnvironment(
      'MAPS_API_KEY_ANDROID',
      defaultValue: '',
    );
    const iosKey = String.fromEnvironment('MAPS_API_KEY_IOS', defaultValue: '');
    const debugToken = String.fromEnvironment(
      'APP_CHECK_DEBUG_TOKEN',
      defaultValue: '',
    );
    const enableAppCheck = bool.fromEnvironment(
      'ENABLE_APP_CHECK',
      defaultValue: true,
    );

    return AppConfig(
      environment: Environment.fromString(envString),
      mapsApiKeyAndroid: androidKey,
      mapsApiKeyIos: iosKey,
      appCheckDebugToken: debugToken,
      enableAppCheck: enableAppCheck,
    );
  }

  bool get isProduction => environment.isProduction;
  bool get isDevelopment => environment.isDevelopment;

  @override
  String toString() {
    if (kReleaseMode) {
      return 'AppConfig(environment: ${environment.name})';
    }
    return 'AppConfig(environment: ${environment.name}, enableAppCheck: $enableAppCheck)';
  }
}
