import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/core/config/app_config.dart';
import 'package:flushcrowd/core/config/environment.dart';
import 'package:flushcrowd/data/repositories/auth_repository_impl.dart';
import 'package:flushcrowd/data/repositories/in_memory_restroom_repository.dart';
import 'package:flushcrowd/data/repositories/location_repository_impl.dart';
import 'package:flushcrowd/main.dart';

void main() {
  testWidgets(
    'FlushCrowdApp initializes and renders splash value proposition',
    (WidgetTester tester) async {
      const config = AppConfig(
        environment: Environment.development,
        enableAppCheck: false,
      );

      final authRepo = InMemoryAuthRepository();
      final restroomRepo = InMemoryRestroomRepository();
      final locationRepo = InMemoryLocationRepository();

      await tester.pumpWidget(
        FlushCrowdApp(
          config: config,
          authRepository: authRepo,
          restroomRepository: restroomRepo,
          locationRepository: locationRepo,
        ),
      );

      await tester.pumpAndSettle();

      // Verify brand title and value proposition items
      expect(find.text('FlushCrowd'), findsOneWidget);
      expect(find.text('Find a better loo, anywhere.'), findsOneWidget);
      expect(find.text('Find nearby restrooms'), findsOneWidget);
      expect(find.text('See ratings and amenities'), findsOneWidget);
      expect(find.text('Add and help others'), findsOneWidget);
      expect(find.text('No account required'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    },
  );
}
