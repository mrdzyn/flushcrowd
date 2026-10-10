import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'environment.dart';

/// Application configuration and environment values.
/// Runtime environment is supplied via compile-time --dart-define.
/// Native platform keys and Firebase configs are managed through platform-native files.
class AppConfig {
  final Environment environment;
  final bool enableAppCheck;
  final String? firebaseProjectId;

  const AppConfig({
    required this.environment,
    this.enableAppCheck = true,
    this.firebaseProjectId,
  });

  /// Factory loading configuration from compile-time environment variables.
  factory AppConfig.fromEnvironment({String? firebaseProjectId}) {
    const envString = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const enableAppCheck = bool.fromEnvironment(
      'ENABLE_APP_CHECK',
      defaultValue: true,
    );
    const compileTimeProjectId = String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: '',
    );

    return AppConfig(
      environment: Environment.fromString(envString),
      enableAppCheck: enableAppCheck,
      firebaseProjectId:
          firebaseProjectId ??
          (compileTimeProjectId.isNotEmpty ? compileTimeProjectId : null),
    );
  }

  bool get isProduction => environment.isProduction;
  bool get isDevelopment => environment.isDevelopment;
  bool get isStaging => environment.isStaging;
  bool get isUnknown => environment.isUnknown;

  /// Whether client contribution writes are allowed in this runtime environment.
  /// Strictly requires verified staging environment AND the approved staging project ID.
  bool get isStagingSubmissionAllowed =>
      isStaging && firebaseProjectId == AppConstants.stagingFirebaseProjectId;

  AppConfig copyWith({
    Environment? environment,
    bool? enableAppCheck,
    String? firebaseProjectId,
  }) {
    return AppConfig(
      environment: environment ?? this.environment,
      enableAppCheck: enableAppCheck ?? this.enableAppCheck,
      firebaseProjectId: firebaseProjectId ?? this.firebaseProjectId,
    );
  }

  @override
  String toString() {
    if (kReleaseMode) {
      return 'AppConfig(environment: ${environment.name}, firebaseProjectId: $firebaseProjectId)';
    }
    return 'AppConfig(environment: ${environment.name}, enableAppCheck: $enableAppCheck, firebaseProjectId: $firebaseProjectId)';
  }
}
