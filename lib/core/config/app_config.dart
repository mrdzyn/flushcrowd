import 'package:flutter/foundation.dart';

import 'environment.dart';

/// Application configuration and environment values.
/// Runtime environment is supplied via compile-time --dart-define.
/// Native platform keys and Firebase configs are managed through platform-native files.
class AppConfig {
  final Environment environment;
  final bool enableAppCheck;

  const AppConfig({required this.environment, this.enableAppCheck = true});

  /// Factory loading configuration from compile-time environment variables.
  factory AppConfig.fromEnvironment() {
    const envString = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const enableAppCheck = bool.fromEnvironment(
      'ENABLE_APP_CHECK',
      defaultValue: true,
    );

    return AppConfig(
      environment: Environment.fromString(envString),
      enableAppCheck: enableAppCheck,
    );
  }

  bool get isProduction => environment.isProduction;
  bool get isDevelopment => environment.isDevelopment;
  bool get isStaging => environment.isStaging;

  @override
  String toString() {
    if (kReleaseMode) {
      return 'AppConfig(environment: ${environment.name})';
    }
    return 'AppConfig(environment: ${environment.name}, enableAppCheck: $enableAppCheck)';
  }
}
