import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/restroom_draft.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/components/inputs/tri_state_amenity_selector.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_form_screen.dart';
import 'package:flushcrowd/presentation/state/restroom_id_generator.dart';

class TestRestroomIdGenerator implements RestroomIdGenerator {
  int calls = 0;
  final String nextId;

  TestRestroomIdGenerator([this.nextId = 'test_doc_id_123']);

  @override
  String generate() {
    calls++;
    return nextId;
  }
}

Widget createFormTestApp({
  required Coordinates coordinates,
  RestroomIdGenerator? idGenerator,
  void Function(CreateRestroomCommand? command)? onResult,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<CreateRestroomCommand>(
                    AddRestroomFormScreen.route(
                      coordinates: coordinates,
                      idGenerator: idGenerator,
                    ),
                  );
              onResult?.call(result);
            },
            child: const Text('Launch Form'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final testCoords = Coordinates(latitude: 14.58390, longitude: 121.06170);

  group('AddRestroomFormScreen — Widget & Flow Verification', () {
    testWidgets(
      '17. Selected coordinates are preserved and displayed read-only',
      (tester) async {
        await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
        await tester.tap(find.text('Launch Form'));
        await tester.pumpAndSettle();

        expect(find.byType(AddRestroomFormScreen), findsOneWidget);
        expect(find.text('14.58390, 121.06170'), findsOneWidget);
        expect(find.text('Selected Entrance Location'), findsOneWidget);
      },
    );

    testWidgets(
      '18. Facility Name required validation displays on empty continue',
      (tester) async {
        await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
        await tester.tap(find.text('Launch Form'));
        await tester.pumpAndSettle();

        // Tap continue without entering name
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(find.text('Facility name is required'), findsWidgets);
        expect(find.text('Please fix the following errors:'), findsOneWidget);
      },
    );

    testWidgets('19. Access Type options render and update selection', (
      tester,
    ) async {
      await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
      await tester.tap(find.text('Launch Form'));
      await tester.pumpAndSettle();

      expect(find.text('Free (Public Access)'), findsOneWidget);

      // Open dropdown
      await tester.tap(find.text('Free (Public Access)'));
      await tester.pumpAndSettle();

      // Select Customer Only
      await tester.tap(find.text('Customer Only').last);
      await tester.pumpAndSettle();

      expect(find.text('Customer Only'), findsOneWidget);
    });

    testWidgets('20. Paid selection shows fee controls', (tester) async {
      await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
      await tester.tap(find.text('Launch Form'));
      await tester.pumpAndSettle();

      // Fee controls should not exist initially
      expect(find.widgetWithText(TextFormField, 'Fee Amount *'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Currency *'), findsNothing);

      // Switch to Paid
      await tester.tap(find.text('Free (Public Access)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paid (Fee Required)').last);
      await tester.pumpAndSettle();

      // Fee controls are now visible
      expect(
        find.widgetWithText(TextFormField, 'Fee Amount *'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'Currency *'), findsOneWidget);
    });

    testWidgets(
      '21. Changing away from Paid removes paid controls appropriately',
      (tester) async {
        await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
        await tester.tap(find.text('Launch Form'));
        await tester.pumpAndSettle();

        // Switch to Paid
        await tester.tap(find.text('Free (Public Access)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paid (Fee Required)').last);
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(TextFormField, 'Fee Amount *'),
          findsOneWidget,
        );

        // Switch away to Key Required
        await tester.tap(find.text('Paid (Fee Required)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Key Required').last);
        await tester.pumpAndSettle();

        // Fee controls are hidden
        expect(
          find.widgetWithText(TextFormField, 'Fee Amount *'),
          findsNothing,
        );
        expect(find.widgetWithText(TextFormField, 'Currency *'), findsNothing);
      },
    );

    testWidgets(
      '22. Tri-state amenity selector supports Yes / No / Unspecified',
      (tester) async {
        await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
        await tester.tap(find.text('Launch Form'));
        await tester.pumpAndSettle();

        // Find PWD accessible selector
        final pwdSelector = find.widgetWithText(
          TriStateAmenitySelector,
          'PWD / Wheelchair Accessible',
        );
        expect(pwdSelector, findsOneWidget);
        await tester.ensureVisible(pwdSelector);
        await tester.pumpAndSettle();

        // Tap Yes
        await tester.tap(
          find.descendant(of: pwdSelector, matching: find.text('Yes')),
        );
        await tester.pumpAndSettle();

        // Tap No
        await tester.tap(
          find.descendant(of: pwdSelector, matching: find.text('No')),
        );
        await tester.pumpAndSettle();

        // Tap Unspecified
        await tester.tap(
          find.descendant(of: pwdSelector, matching: find.text('Unspecified')),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets('23. Default amenity UI is Unspecified across all amenities', (
      tester,
    ) async {
      await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
      await tester.tap(find.text('Launch Form'));
      await tester.pumpAndSettle();

      final triStateSelectors = tester.widgetList<TriStateAmenitySelector>(
        find.byType(TriStateAmenitySelector),
      );

      // Every amenity selector must default to unknown
      for (final selector in triStateSelectors) {
        expect(selector.value, equals(TriStateAmenity.unknown));
      }
    });

    testWidgets(
      '24. Stall tri-state selections map correctly to nullable bool',
      (tester) async {
        CreateRestroomCommand? capturedCommand;
        await tester.pumpWidget(
          createFormTestApp(
            coordinates: testCoords,
            onResult: (cmd) => capturedCommand = cmd,
          ),
        );
        await tester.tap(find.text('Launch Form'));
        await tester.pumpAndSettle();

        // Fill name
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Facility Name *'),
          'Station Toilet',
        );
        await tester.pumpAndSettle();

        // Set Male to Yes
        final maleSelector = find.widgetWithText(
          TriStateAmenitySelector,
          'Male Stalls',
        );
        await tester.ensureVisible(maleSelector);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: maleSelector, matching: find.text('Yes')),
        );
        await tester.pumpAndSettle();

        // Set Female to No
        final femaleSelector = find.widgetWithText(
          TriStateAmenitySelector,
          'Female Stalls',
        );
        await tester.ensureVisible(femaleSelector);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: femaleSelector, matching: find.text('No')),
        );
        await tester.pumpAndSettle();

        // All-Gender stays Unspecified

        // Submit
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(capturedCommand, isNotNull);
        expect(capturedCommand!.draft.male, isTrue);
        expect(capturedCommand!.draft.female, isFalse);
        expect(capturedCommand!.draft.allGender, isNull);
      },
    );

    testWidgets('25. Invalid all-false stall configuration shows error', (
      tester,
    ) async {
      await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
      await tester.tap(find.text('Launch Form'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Facility Name *'),
        'Invalid Stall Config',
      );
      await tester.pumpAndSettle();

      // Set all stalls to No (explicit but none positive)
      final male = find.widgetWithText(TriStateAmenitySelector, 'Male Stalls');
      await tester.ensureVisible(male);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: male, matching: find.text('No')));
      await tester.pumpAndSettle();

      final female = find.widgetWithText(
        TriStateAmenitySelector,
        'Female Stalls',
      );
      await tester.ensureVisible(female);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: female, matching: find.text('No')));
      await tester.pumpAndSettle();

      final allGender = find.widgetWithText(
        TriStateAmenitySelector,
        'All-Gender / Unisex Stalls',
      );
      await tester.ensureVisible(allGender);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: allGender, matching: find.text('No')),
      );
      await tester.pumpAndSettle();

      // Try to continue
      await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('Select applicable gender stalls or leave all unspecified'),
        findsWidgets,
      );
    });

    testWidgets('26. Form values survive validation errors', (tester) async {
      await tester.pumpWidget(createFormTestApp(coordinates: testCoords));
      await tester.tap(find.text('Launch Form'));
      await tester.pumpAndSettle();

      // Enter building name and landmark without facility name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Building Name'),
        'Grand Atrium Mall',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nearest Landmark'),
        'Near the Information Counter',
      );
      await tester.pumpAndSettle();

      // Tap continue (validation fails because name is empty)
      await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Facility name is required'), findsWidgets);

      // Verify entered values are intact
      expect(find.text('Grand Atrium Mall'), findsOneWidget);
      expect(find.text('Near the Information Counter'), findsOneWidget);
    });

    testWidgets(
      '27. Successful validation returns command without backend persistence claims',
      (tester) async {
        CreateRestroomCommand? resultCommand;
        final generator = TestRestroomIdGenerator('test_doc_id_456');

        await tester.pumpWidget(
          createFormTestApp(
            coordinates: testCoords,
            idGenerator: generator,
            onResult: (cmd) => resultCommand = cmd,
          ),
        );
        await tester.tap(find.text('Launch Form'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Facility Name *'),
          'Airport North Terminal Restroom',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        // Form popped returning prepared command
        expect(resultCommand, isNotNull);
        expect(resultCommand!.restroomId, equals('test_doc_id_456'));
        expect(
          resultCommand!.draft.name,
          equals('Airport North Terminal Restroom'),
        );
        expect(resultCommand!.draft.coordinates, equals(testCoords));
        expect(generator.calls, equals(1));

        // No claim of submission or persistence
        expect(find.text('Restroom added!'), findsNothing);
        expect(find.text('Submitted to Firestore'), findsNothing);
      },
    );

    testWidgets('28. Cancel/back pops form returning null', (tester) async {
      CreateRestroomCommand? resultCommand = CreateRestroomCommand(
        restroomId: 'placeholder',
        draft: RestroomDraft(
          name: 'placeholder',
          coordinates: Coordinates(latitude: 0, longitude: 0),
          accessType: AccessType.free,
        ),
      );

      await tester.pumpWidget(
        createFormTestApp(
          coordinates: testCoords,
          onResult: (cmd) => resultCommand = cmd,
        ),
      );
      await tester.tap(find.text('Launch Form'));
      await tester.pumpAndSettle();

      expect(find.byType(AddRestroomFormScreen), findsOneWidget);

      // Tap Back button
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(AddRestroomFormScreen), findsNothing);
      expect(resultCommand, isNull);
    });

    testWidgets(
      '29. Paid -> enter fee -> change to non-paid -> change back to Paid: fee controls are empty, notifier/UI agree, Continue requires newly entered valid fee data',
      (tester) async {
        CreateRestroomCommand? resultCommand;
        final generator = TestRestroomIdGenerator('test_doc_id_fee_sync');

        await tester.pumpWidget(
          createFormTestApp(
            coordinates: testCoords,
            idGenerator: generator,
            onResult: (cmd) => resultCommand = cmd,
          ),
        );
        await tester.tap(find.text('Launch Form'));
        await tester.pumpAndSettle();

        // 1. Enter valid facility name
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Facility Name *'),
          'Highway Service Plaza Restroom',
        );
        await tester.pumpAndSettle();

        // 2. Select Paid
        await tester.tap(find.text('Free (Public Access)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paid (Fee Required)').last);
        await tester.pumpAndSettle();

        // 3. Enter fee amount and currency
        final feeAmountField = find.widgetWithText(
          TextFormField,
          'Fee Amount *',
        );
        final feeCurrencyField = find.widgetWithText(
          TextFormField,
          'Currency *',
        );
        await tester.ensureVisible(feeAmountField);
        await tester.enterText(feeAmountField, '25.00');
        await tester.enterText(feeCurrencyField, 'PHP');
        await tester.pumpAndSettle();

        // 4. Change to Free / Customer Only / Key Required (e.g. Customer Only)
        final accessTypeDropdown = find.widgetWithText(
          DropdownButtonFormField<AccessType>,
          'Access Type',
        );
        await tester.ensureVisible(accessTypeDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paid (Fee Required)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Customer Only').last);
        await tester.pumpAndSettle();

        // Ensure fee controls are hidden
        expect(
          find.widgetWithText(TextFormField, 'Fee Amount *'),
          findsNothing,
        );
        expect(find.widgetWithText(TextFormField, 'Currency *'), findsNothing);

        // 5. Change back to Paid
        await tester.ensureVisible(accessTypeDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Customer Only'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paid (Fee Required)').last);
        await tester.pumpAndSettle();

        // 6. Fee controls must be genuinely empty and agree with notifier
        final feeAmountFieldReappeared = find.widgetWithText(
          TextFormField,
          'Fee Amount *',
        );
        final feeCurrencyFieldReappeared = find.widgetWithText(
          TextFormField,
          'Currency *',
        );
        await tester.ensureVisible(feeAmountFieldReappeared);
        await tester.pumpAndSettle();

        final amountWidget = tester.widget<TextFormField>(
          feeAmountFieldReappeared,
        );
        final currencyWidget = tester.widget<TextFormField>(
          feeCurrencyFieldReappeared,
        );
        expect(amountWidget.controller?.text, isEmpty);
        expect(currencyWidget.controller?.text, isEmpty);

        // 7. Attempting to continue requires newly entered valid fee data
        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Paid restrooms require a valid fee amount between 0 and 1,000,000',
          ),
          findsWidgets,
        );
        expect(
          find.text(
            'Fee currency must be a valid 3-letter uppercase code (e.g., USD)',
          ),
          findsWidgets,
        );
        expect(find.byType(AddRestroomFormScreen), findsOneWidget);
        expect(resultCommand, isNull);

        // 8. Entering valid fee data allows successful Continue
        await tester.enterText(feeAmountFieldReappeared, '10.00');
        await tester.enterText(feeCurrencyFieldReappeared, 'USD');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(AddRestroomFormScreen), findsNothing);
        expect(resultCommand, isNotNull);
        expect(resultCommand!.draft.accessType, equals(AccessType.paid));
        expect(resultCommand!.draft.feeAmount, equals(10.00));
        expect(resultCommand!.draft.feeCurrency, equals('USD'));
      },
    );
  });
}
