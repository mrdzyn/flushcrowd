import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/core/config/app_config.dart';
import 'package:looradar/core/config/environment.dart';
import 'package:looradar/data/repositories/auth_repository_impl.dart';
import 'package:looradar/data/repositories/in_memory_restroom_repository.dart';
import 'package:looradar/data/repositories/location_repository_impl.dart';
import 'package:looradar/main.dart';

void main() {
  testWidgets('LooRadarApp initializes and renders splash value proposition', (
    WidgetTester tester,
  ) async {
    const config = AppConfig(
      environment: Environment.development,
      enableAppCheck: false,
    );

    final authRepo = InMemoryAuthRepository();
    final restroomRepo = InMemoryRestroomRepository();
    final locationRepo = InMemoryLocationRepository();

    await tester.pumpWidget(
      LooRadarApp(
        config: config,
        authRepository: authRepo,
        restroomRepository: restroomRepo,
        locationRepository: locationRepo,
      ),
    );

    await tester.pumpAndSettle();

    // Verify brand title and value proposition items
    expect(find.text('LooRadar'), findsOneWidget);
    expect(find.text('Find a better loo, anywhere.'), findsOneWidget);
    expect(find.text('Find nearby restrooms'), findsOneWidget);
    expect(find.text('See ratings and amenities'), findsOneWidget);
    expect(find.text('Add and help others'), findsOneWidget);
    expect(find.text('No account required'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
