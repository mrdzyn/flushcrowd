import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/core/config/app_config.dart';
import 'package:flushcrowd/core/config/environment.dart';
import 'package:flushcrowd/core/constants/app_constants.dart';

void main() {
  group('AppConfig & Environment', () {
    test('default fromEnvironment creates development configuration', () {
      final config = AppConfig.fromEnvironment();
      expect(config.environment, equals(Environment.development));
      expect(config.isDevelopment, isTrue);
      expect(config.isStaging, isFalse);
      expect(config.isProduction, isFalse);
      expect(config.isUnknown, isFalse);
      expect(config.enableAppCheck, isTrue);
      expect(config.isStagingSubmissionAllowed, isFalse);
    });

    test('Environment parses strings correctly', () {
      expect(
        Environment.fromString('development'),
        equals(Environment.development),
      );
      expect(Environment.fromString('dev'), equals(Environment.development));
      expect(Environment.fromString('staging'), equals(Environment.staging));
      expect(Environment.fromString('stage'), equals(Environment.staging));
      expect(
        Environment.fromString('production'),
        equals(Environment.production),
      );
      expect(Environment.fromString('prod'), equals(Environment.production));
      expect(Environment.fromString('unknown'), equals(Environment.unknown));
      expect(Environment.fromString(null), equals(Environment.unknown));
    });

    test('AppConfig boolean environment helpers match environment', () {
      const devConfig = AppConfig(environment: Environment.development);
      expect(devConfig.isDevelopment, isTrue);
      expect(devConfig.isStaging, isFalse);
      expect(devConfig.isProduction, isFalse);
      expect(devConfig.isUnknown, isFalse);

      const stagingConfig = AppConfig(environment: Environment.staging);
      expect(stagingConfig.isDevelopment, isFalse);
      expect(stagingConfig.isStaging, isTrue);
      expect(stagingConfig.isProduction, isFalse);
      expect(stagingConfig.isUnknown, isFalse);

      const prodConfig = AppConfig(environment: Environment.production);
      expect(prodConfig.isDevelopment, isFalse);
      expect(prodConfig.isStaging, isFalse);
      expect(prodConfig.isProduction, isTrue);
      expect(prodConfig.isUnknown, isFalse);

      const unknownConfig = AppConfig(environment: Environment.unknown);
      expect(unknownConfig.isDevelopment, isFalse);
      expect(unknownConfig.isStaging, isFalse);
      expect(unknownConfig.isProduction, isFalse);
      expect(unknownConfig.isUnknown, isTrue);
    });

    test('isStagingSubmissionAllowed strictly requires staging AND flushcrowd-staging', () {
      const validStagingConfig = AppConfig(
        environment: Environment.staging,
        firebaseProjectId: AppConstants.stagingFirebaseProjectId,
      );
      expect(validStagingConfig.isStagingSubmissionAllowed, isTrue);

      const wrongProjectStagingConfig = AppConfig(
        environment: Environment.staging,
        firebaseProjectId: 'wrong-project-id',
      );
      expect(wrongProjectStagingConfig.isStagingSubmissionAllowed, isFalse);

      const nullProjectStagingConfig = AppConfig(
        environment: Environment.staging,
        firebaseProjectId: null,
      );
      expect(nullProjectStagingConfig.isStagingSubmissionAllowed, isFalse);

      const devWithStagingProjectConfig = AppConfig(
        environment: Environment.development,
        firebaseProjectId: AppConstants.stagingFirebaseProjectId,
      );
      expect(devWithStagingProjectConfig.isStagingSubmissionAllowed, isFalse);

      const prodWithStagingProjectConfig = AppConfig(
        environment: Environment.production,
        firebaseProjectId: AppConstants.stagingFirebaseProjectId,
      );
      expect(prodWithStagingProjectConfig.isStagingSubmissionAllowed, isFalse);

      const unknownWithStagingProjectConfig = AppConfig(
        environment: Environment.unknown,
        firebaseProjectId: AppConstants.stagingFirebaseProjectId,
      );
      expect(
        unknownWithStagingProjectConfig.isStagingSubmissionAllowed,
        isFalse,
      );
    });
  });
}
