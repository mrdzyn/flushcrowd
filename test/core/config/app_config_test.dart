import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/core/config/app_config.dart';
import 'package:flushcrowd/core/config/environment.dart';

void main() {
  group('AppConfig & Environment', () {
    test('default fromEnvironment creates development configuration', () {
      final config = AppConfig.fromEnvironment();
      expect(config.environment, equals(Environment.development));
      expect(config.isDevelopment, isTrue);
      expect(config.isStaging, isFalse);
      expect(config.isProduction, isFalse);
      expect(config.enableAppCheck, isTrue);
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
      expect(
        Environment.fromString('unknown'),
        equals(Environment.development),
      );
      expect(Environment.fromString(null), equals(Environment.development));
    });

    test('AppConfig boolean environment helpers match environment', () {
      const devConfig = AppConfig(environment: Environment.development);
      expect(devConfig.isDevelopment, isTrue);
      expect(devConfig.isStaging, isFalse);
      expect(devConfig.isProduction, isFalse);

      const stagingConfig = AppConfig(environment: Environment.staging);
      expect(stagingConfig.isDevelopment, isFalse);
      expect(stagingConfig.isStaging, isTrue);
      expect(stagingConfig.isProduction, isFalse);

      const prodConfig = AppConfig(environment: Environment.production);
      expect(prodConfig.isDevelopment, isFalse);
      expect(prodConfig.isStaging, isFalse);
      expect(prodConfig.isProduction, isTrue);
    });
  });
}
