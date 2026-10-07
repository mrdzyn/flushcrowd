import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_secondary_button.dart';
import 'package:flushcrowd/presentation/components/cards/restroom_summary_card.dart';
import 'package:flushcrowd/presentation/components/chips/amenity_chip.dart';
import 'package:flushcrowd/presentation/components/chips/status_chip.dart';
import 'package:flushcrowd/presentation/components/map/permission_banner.dart';

void main() {
  group('UI Design System Components', () {
    testWidgets('LooPrimaryButton renders label and responds to tap', (
      tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LooPrimaryButton(
              label: 'Get Started',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Get Started'), findsOneWidget);
      await tester.tap(find.text('Get Started'));
      expect(tapped, isTrue);
    });

    testWidgets(
      'LooPrimaryButton shows loading indicator when isLoading is true',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LooPrimaryButton(label: 'Loading Action', isLoading: true),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Loading Action'), findsNothing);
      },
    );

    testWidgets('LooSecondaryButton renders and responds to tap', (
      tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LooSecondaryButton(
              label: 'Directions',
              icon: Icons.directions_outlined,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Directions'), findsOneWidget);
      expect(find.byIcon(Icons.directions_outlined), findsOneWidget);
      await tester.tap(find.text('Directions'));
      expect(tapped, isTrue);
    });

    testWidgets('AmenityChip renders icon, label, and responds to tap', (
      tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmenityChip(
              icon: Icons.water_drop_outlined,
              label: 'Bidet',
              isSelected: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Bidet'), findsOneWidget);
      expect(find.byIcon(Icons.water_drop_outlined), findsOneWidget);
      await tester.tap(find.text('Bidet'));
      expect(tapped, isTrue);
    });

    testWidgets('StatusChip renders semantic label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusChip(label: 'Open', type: StatusChipType.success),
          ),
        ),
      );

      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets(
      'RestroomSummaryCard displays restroom name, rating, floor, and distance',
      (tester) async {
        final restroom = Restroom(
          id: 'rr_test_card',
          name: 'SM Megamall - Building A',
          coordinates: Coordinates(latitude: 14.5843, longitude: 121.0568),
          geohash: 'wdw4fq',
          floor: '3F',
          averageRating: 4.6,
          ratingCount: 128,
          accessType: AccessType.free,
        );

        final userLocation = Coordinates(
          latitude: 14.5835,
          longitude: 121.0560,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RestroomSummaryCard(
                restroom: restroom,
                userLocation: userLocation,
              ),
            ),
          ),
        );

        expect(find.text('SM Megamall - Building A'), findsOneWidget);
        expect(find.text('4.6'), findsOneWidget);
        expect(find.text('(128)'), findsOneWidget);
        expect(find.textContaining('3F ·'), findsOneWidget);
        expect(find.text('Open'), findsNothing);
      },
    );

    testWidgets(
      'PermissionBanner renders when permission is denied and triggers action',
      (tester) async {
        bool requested = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PermissionBanner(
                permissionState: LocationPermissionState.denied,
                onRequestPermission: () => requested = true,
              ),
            ),
          ),
        );

        expect(find.text('Explore Faster With Location'), findsOneWidget);
        expect(find.text('Enable Location'), findsOneWidget);

        await tester.tap(find.text('Enable Location'));
        expect(requested, isTrue);
      },
    );
  });
}
