import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/duplicate_candidate.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/duplicate_warning_sheet.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_secondary_button.dart';

Restroom _createTestRestroom({
  required String id,
  required String name,
  String? buildingName,
  String? floor,
  AccessType accessType = AccessType.free,
}) {
  return Restroom(
    id: id,
    name: name,
    coordinates: Coordinates(latitude: 14.58390, longitude: 121.06170),
    geohash: 'w4rr7x',
    accessType: accessType,
    buildingName: buildingName,
    floor: floor,
    status: RestroomStatus.active,
    createdAt: DateTime(2026, 1, 1),
  );
}

DuplicateCandidate _createCandidate({
  required String id,
  required String name,
  double distanceMeters = 25.0,
  double score = 0.85,
  String? buildingName,
  String? floor,
  AccessType accessType = AccessType.free,
}) {
  return DuplicateCandidate(
    restroom: _createTestRestroom(
      id: id,
      name: name,
      buildingName: buildingName,
      floor: floor,
      accessType: accessType,
    ),
    score: score,
    distanceMeters: distanceMeters,
  );
}

Widget _buildTestApp({
  required List<DuplicateCandidate> candidates,
  ValueChanged<Restroom>? onViewExisting,
  VoidCallback? onProceed,
  ValueChanged<DuplicateWarningAction?>? onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await DuplicateWarningSheet.show(
                context,
                candidates: candidates,
                onViewExisting: onViewExisting,
                onProceed: onProceed,
              );
              onResult?.call(result);
            },
            child: const Text('Open Sheet'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('DuplicateWarningSheet — Widget & Interaction Verification', () {
    testWidgets('1. Renders warning header and advisory explanation', (
      tester,
    ) async {
      final candidates = [
        _createCandidate(
          id: 'c1',
          name: 'Central Mall Restroom',
          distanceMeters: 25.0,
          buildingName: 'Central Mall',
          floor: '2F',
        ),
      ];

      await tester.pumpWidget(_buildTestApp(candidates: candidates));
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(DuplicateWarningSheet), findsOneWidget);
      expect(find.text('Similar restrooms found nearby'), findsOneWidget);
      expect(
        find.text(
          'We found an existing restroom near this location. Is this the same facility?',
        ),
        findsOneWidget,
      );
      expect(find.text('Central Mall Restroom'), findsOneWidget);
      expect(find.text('25 m · Floor: 2F · Central Mall'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('View Existing Restroom'), findsOneWidget);
      expect(find.text("No, It's a Different Restroom"), findsOneWidget);
    });

    testWidgets(
      '2. Displays at most 3 candidate cards even if more are provided',
      (tester) async {
        final candidates = [
          _createCandidate(id: 'c1', name: 'Candidate 1'),
          _createCandidate(id: 'c2', name: 'Candidate 2'),
          _createCandidate(id: 'c3', name: 'Candidate 3'),
          _createCandidate(id: 'c4', name: 'Candidate 4'),
          _createCandidate(id: 'c5', name: 'Candidate 5'),
        ];

        await tester.pumpWidget(_buildTestApp(candidates: candidates));
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Candidate 1'), findsOneWidget);
        expect(find.text('Candidate 2'), findsOneWidget);
        expect(find.text('Candidate 3'), findsOneWidget);
        expect(find.text('Candidate 4'), findsNothing);
        expect(find.text('Candidate 5'), findsNothing);
      },
    );

    testWidgets('3. Renders various access type chips correctly', (
      tester,
    ) async {
      final candidates = [
        _createCandidate(
          id: 'c1',
          name: 'Paid Restroom',
          accessType: AccessType.paid,
        ),
        _createCandidate(
          id: 'c2',
          name: 'Customer Restroom',
          accessType: AccessType.customerOnly,
        ),
        _createCandidate(
          id: 'c3',
          name: 'Key Restroom',
          accessType: AccessType.keyRequired,
        ),
      ];

      await tester.pumpWidget(_buildTestApp(candidates: candidates));
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Customer Only'), findsOneWidget);
      expect(find.text('Key Required'), findsOneWidget);
    });

    testWidgets(
      '4. Tapping "View Existing Restroom" dismisses sheet and returns action',
      (tester) async {
        Restroom? viewedRestroom;
        DuplicateWarningAction? returnedAction;

        final candidates = [
          _createCandidate(
            id: 'c1',
            name: 'Central Mall Restroom',
            buildingName: 'Central Mall',
          ),
        ];

        await tester.pumpWidget(
          _buildTestApp(
            candidates: candidates,
            onViewExisting: (r) => viewedRestroom = r,
            onResult: (a) => returnedAction = a,
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // Tap "View Existing Restroom"
        await tester.tap(
          find.widgetWithText(LooSecondaryButton, 'View Existing Restroom'),
        );
        await tester.pumpAndSettle();

        // Sheet is dismissed
        expect(find.byType(DuplicateWarningSheet), findsNothing);
        expect(viewedRestroom, isNotNull);
        expect(viewedRestroom!.id, equals('c1'));
        expect(returnedAction, isA<ViewExistingRestroomAction>());
        expect(
          (returnedAction as ViewExistingRestroomAction).restroom.id,
          equals('c1'),
        );
      },
    );

    testWidgets(
      '5. Tapping "No, It\'s a Different Restroom" dismisses sheet and returns action',
      (tester) async {
        bool proceedCalled = false;
        DuplicateWarningAction? returnedAction;

        final candidates = [
          _createCandidate(id: 'c1', name: 'Central Mall Restroom'),
        ];

        await tester.pumpWidget(
          _buildTestApp(
            candidates: candidates,
            onProceed: () => proceedCalled = true,
            onResult: (a) => returnedAction = a,
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // Tap "No, It's a Different Restroom"
        await tester.tap(
          find.widgetWithText(
            LooPrimaryButton,
            "No, It's a Different Restroom",
          ),
        );
        await tester.pumpAndSettle();

        // Sheet is dismissed
        expect(find.byType(DuplicateWarningSheet), findsNothing);
        expect(proceedCalled, isTrue);
        expect(returnedAction, isA<ProceedWithSubmissionAction>());
      },
    );

    testWidgets(
      '6. All interactive buttons meet minimum 48dp touch target height',
      (tester) async {
        final candidates = [
          _createCandidate(id: 'c1', name: 'Central Mall Restroom'),
        ];

        await tester.pumpWidget(_buildTestApp(candidates: candidates));
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        final secondaryButtonFinder = find.widgetWithText(
          LooSecondaryButton,
          'View Existing Restroom',
        );
        final primaryButtonFinder = find.widgetWithText(
          LooPrimaryButton,
          "No, It's a Different Restroom",
        );

        final secondarySize = tester.getSize(secondaryButtonFinder);
        final primarySize = tester.getSize(primaryButtonFinder);

        expect(secondarySize.height, greaterThanOrEqualTo(48.0));
        expect(primarySize.height, greaterThanOrEqualTo(48.0));
      },
    );
  });
}
