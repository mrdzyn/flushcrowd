import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/core/theme/app_colors.dart';
import 'package:flushcrowd/data/repositories/location_repository_impl.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/duplicate_candidate.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/models/restroom_draft.dart';
import 'package:flushcrowd/presentation/components/bottom_sheets/duplicate_warning_sheet.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_primary_button.dart';
import 'package:flushcrowd/presentation/components/buttons/loo_secondary_button.dart';
import 'package:flushcrowd/presentation/components/inputs/tri_state_amenity_selector.dart';
import 'package:flushcrowd/presentation/components/map/map_recenter_button.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_form_screen.dart';
import 'package:flushcrowd/presentation/screens/add_restroom_location_screen.dart';

/// Linearize an 8-bit sRGB channel normalized to [0.0, 1.0] per WCAG 2.1 specs.
double _linearizeSrgbChannel(double c) {
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// Computes the WCAG relative luminance L = 0.2126*R + 0.7152*G + 0.0722*B.
double calculateRelativeLuminance(Color color) {
  final r = _linearizeSrgbChannel(color.r);
  final g = _linearizeSrgbChannel(color.g);
  final b = _linearizeSrgbChannel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Computes the WCAG contrast ratio (L1 + 0.05) / (L2 + 0.05).
double calculateContrastRatio(Color foreground, Color background) {
  final l1 = calculateRelativeLuminance(foreground);
  final l2 = calculateRelativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Configures the actual Flutter test viewport and registers teardown reset.
void configureTestViewport(
  WidgetTester tester, {
  required double width,
  double height = 844.0,
  double devicePixelRatio = 1.0,
}) {
  tester.view.physicalSize = Size(
    width * devicePixelRatio,
    height * devicePixelRatio,
  );
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

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

Widget _wrapWithScale({required Widget child, double textScale = 1.0}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        final inherited = MediaQuery.of(context);
        return MediaQuery(
          data: inherited.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child,
        );
      },
    ),
  );
}

Widget _buildLocationScreen({ValueChanged<Coordinates>? onLocationConfirmed}) {
  return AddRestroomLocationScreen(
    initialCoordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
    locationRepository: InMemoryLocationRepository(
      initialCoordinates: Coordinates(latitude: 14.5839, longitude: 121.0617),
    ),
    onLocationConfirmed: onLocationConfirmed,
    mapBuilder:
        ({
          required BuildContext context,
          required initialCameraPosition,
          onCameraIdle,
          onCameraMove,
          onCameraMoveStarted,
          onMapCreated,
        }) {
          return const SizedBox.expand(child: ColoredBox(color: Colors.grey));
        },
  );
}

void main() {
  group('P2.6-F — Milestone Accessibility Verification', () {
    group('1. Touch Targets (Minimum 48 x 48 dp)', () {
      testWidgets(
        'LooPrimaryButton and LooSecondaryButton enforce minHeight >= 48dp',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(
              child: Scaffold(
                body: Column(
                  children: [
                    LooPrimaryButton(label: 'Primary Action', onPressed: () {}),
                    const SizedBox(height: 16),
                    LooSecondaryButton(
                      label: 'Secondary Action',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          );

          final primaryFinder = find.byType(LooPrimaryButton);
          final secondaryFinder = find.byType(LooSecondaryButton);

          final primarySize = tester.getSize(primaryFinder);
          final secondarySize = tester.getSize(secondaryFinder);

          expect(primarySize.height, greaterThanOrEqualTo(48.0));
          expect(primarySize.width, greaterThanOrEqualTo(48.0));
          expect(secondarySize.height, greaterThanOrEqualTo(48.0));
          expect(secondarySize.width, greaterThanOrEqualTo(48.0));
        },
      );

      testWidgets('MapRecenterButton meets minimum 48x48dp target', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrapWithScale(
            child: Scaffold(
              body: Center(child: MapRecenterButton(onPressed: () {})),
            ),
          ),
        );

        final recenterFinder = find.byType(MapRecenterButton);
        final size = tester.getSize(recenterFinder);

        expect(size.width, greaterThanOrEqualTo(48.0));
        expect(size.height, greaterThanOrEqualTo(48.0));
      });

      testWidgets(
        'AddRestroomLocationScreen Confirm Pin, My Location, and Back actions meet >= 48x48dp',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(child: _buildLocationScreen()),
          );
          await tester.pumpAndSettle();

          // 1. Back button in AppBar
          final backFinder = find.byTooltip('Back');
          expect(backFinder, findsOneWidget);
          final backSize = tester.getSize(backFinder);
          expect(backSize.width, greaterThanOrEqualTo(48.0));
          expect(backSize.height, greaterThanOrEqualTo(48.0));

          // 2. My Location button
          final recenterFinder = find.byType(MapRecenterButton);
          expect(recenterFinder, findsOneWidget);
          final recenterSize = tester.getSize(recenterFinder);
          expect(recenterSize.width, greaterThanOrEqualTo(48.0));
          expect(recenterSize.height, greaterThanOrEqualTo(48.0));

          // 3. Confirm Pin Location action ("Continue" button)
          final confirmFinder = find.widgetWithText(
            LooPrimaryButton,
            'Continue',
          );
          expect(confirmFinder, findsOneWidget);
          final confirmSize = tester.getSize(confirmFinder);
          expect(confirmSize.width, greaterThanOrEqualTo(48.0));
          expect(confirmSize.height, greaterThanOrEqualTo(48.0));
        },
      );

      testWidgets(
        'AddRestroomFormScreen Access Type selection dropdown meets >= 48dp height',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(
              child: AddRestroomFormScreen(
                coordinates: Coordinates(
                  latitude: 14.5839,
                  longitude: 121.0617,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final dropdownFinder = find.byType(
            DropdownButtonFormField<AccessType>,
          );
          expect(dropdownFinder, findsOneWidget);
          final dropdownSize = tester.getSize(dropdownFinder);
          expect(dropdownSize.height, greaterThanOrEqualTo(48.0));
          expect(dropdownSize.width, greaterThanOrEqualTo(48.0));
        },
      );

      testWidgets(
        'DuplicateWarningSheet actions meet minimum 48x48dp targets',
        (tester) async {
          final candidate = _createCandidate(
            id: 'cand_target',
            name: 'Terminal 1 Restroom',
            accessType: AccessType.paid,
          );

          await tester.pumpWidget(
            _wrapWithScale(
              child: DuplicateWarningSheet(candidates: [candidate]),
            ),
          );
          await tester.pumpAndSettle();

          // 1. "No, It's a Different Restroom" primary button
          final proceedFinder = find.widgetWithText(
            LooPrimaryButton,
            "No, It's a Different Restroom",
          );
          expect(proceedFinder, findsOneWidget);
          final proceedSize = tester.getSize(proceedFinder);
          expect(proceedSize.height, greaterThanOrEqualTo(48.0));
          expect(proceedSize.width, greaterThanOrEqualTo(48.0));

          // 2. "View Existing Restroom" secondary button
          final viewFinder = find.widgetWithText(
            LooSecondaryButton,
            'View Existing Restroom',
          );
          expect(viewFinder, findsOneWidget);
          final viewSize = tester.getSize(viewFinder);
          expect(viewSize.height, greaterThanOrEqualTo(48.0));
          expect(viewSize.width, greaterThanOrEqualTo(48.0));
        },
      );

      testWidgets(
        'TriStateAmenitySelector options satisfy minimum touch dimensions',
        (tester) async {
          TriStateAmenity selected = TriStateAmenity.yes;
          await tester.pumpWidget(
            _wrapWithScale(
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TriStateAmenitySelector(
                    title: 'Bidet',
                    value: selected,
                    onChanged: (val) => selected = val,
                  ),
                ),
              ),
            ),
          );

          final yesFinder = find.widgetWithText(InkWell, 'Yes');
          final noFinder = find.widgetWithText(InkWell, 'No');
          final unspecFinder = find.widgetWithText(InkWell, 'Unspecified');

          expect(tester.getSize(yesFinder).height, greaterThanOrEqualTo(48.0));
          expect(tester.getSize(yesFinder).width, greaterThanOrEqualTo(48.0));
          expect(tester.getSize(noFinder).height, greaterThanOrEqualTo(48.0));
          expect(tester.getSize(noFinder).width, greaterThanOrEqualTo(48.0));
          expect(
            tester.getSize(unspecFinder).height,
            greaterThanOrEqualTo(48.0),
          );
          expect(
            tester.getSize(unspecFinder).width,
            greaterThanOrEqualTo(48.0),
          );
        },
      );
    });

    group('2. Screen Reader Semantics & State Announcements', () {
      testWidgets(
        'TriStateAmenitySelector exposes parent title, state and selection flag',
        (tester) async {
          final handle = tester.ensureSemantics();
          TriStateAmenity state = TriStateAmenity.yes;

          await tester.pumpWidget(
            StatefulBuilder(
              builder: (context, setState) {
                return _wrapWithScale(
                  child: Scaffold(
                    body: TriStateAmenitySelector(
                      title: 'Toilet Paper',
                      value: state,
                      onChanged: (val) => setState(() => state = val),
                    ),
                  ),
                );
              },
            ),
          );

          // Verify initial selected state
          expect(
            tester.getSemantics(find.bySemanticsLabel('Toilet Paper, Yes')),
            matchesSemantics(
              isButton: true,
              hasSelectedState: true,
              isSelected: true,
              label: 'Toilet Paper, Yes',
            ),
          );
          expect(
            tester.getSemantics(find.bySemanticsLabel('Toilet Paper, No')),
            matchesSemantics(
              isButton: true,
              hasSelectedState: true,
              isSelected: false,
              label: 'Toilet Paper, No',
            ),
          );

          // Tap No option
          await tester.tap(find.text('No'));
          await tester.pumpAndSettle();

          expect(
            tester.getSemantics(find.bySemanticsLabel('Toilet Paper, No')),
            matchesSemantics(
              isButton: true,
              hasSelectedState: true,
              isSelected: true,
              label: 'Toilet Paper, No',
            ),
          );
          expect(
            tester.getSemantics(find.bySemanticsLabel('Toilet Paper, Yes')),
            matchesSemantics(
              isButton: true,
              hasSelectedState: true,
              isSelected: false,
              label: 'Toilet Paper, Yes',
            ),
          );

          handle.dispose();
        },
      );

      testWidgets(
        'AddRestroomFormScreen exposes section headings and live error summary',
        (tester) async {
          final handle = tester.ensureSemantics();

          await tester.pumpWidget(
            _wrapWithScale(
              child: AddRestroomFormScreen(
                coordinates: Coordinates(
                  latitude: 14.5839,
                  longitude: 121.0617,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Verify section headers have header semantics
          expect(
            find.bySemanticsLabel('Facility Identification'),
            findsOneWidget,
          );
          expect(
            tester.getSemantics(
              find.bySemanticsLabel('Facility Identification'),
            ),
            matchesSemantics(isHeader: true, label: 'Facility Identification'),
          );

          expect(
            find.bySemanticsLabel('Indoor Context & Directions'),
            findsOneWidget,
          );
          expect(
            tester.getSemantics(
              find.bySemanticsLabel('Indoor Context & Directions'),
            ),
            matchesSemantics(
              isHeader: true,
              label: 'Indoor Context & Directions',
            ),
          );

          // 2. Trigger validation failure by continuing without facility name
          await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
          await tester.pumpAndSettle();

          // 3. Error summary banner should be present with liveRegion
          final errorBannerFinder = find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.liveRegion == true &&
                w.child is Container,
          );
          expect(errorBannerFinder, findsOneWidget);

          handle.dispose();
        },
      );

      testWidgets(
        'DuplicateWarningSheet renders semantic header and candidate action context',
        (tester) async {
          final handle = tester.ensureSemantics();
          final candidate = _createCandidate(
            id: 'test_c1',
            name: 'Central Restroom',
            accessType: AccessType.free,
          );

          await tester.pumpWidget(
            _wrapWithScale(
              child: DuplicateWarningSheet(candidates: [candidate]),
            ),
          );
          await tester.pumpAndSettle();

          // Header has heading semantics
          expect(
            tester.getSemantics(
              find.bySemanticsLabel('Similar restrooms found nearby'),
            ),
            matchesSemantics(
              isHeader: true,
              label: 'Similar restrooms found nearby',
            ),
          );

          // Candidate action specifies facility name
          expect(
            find.bySemanticsLabel('View existing restroom: Central Restroom'),
            findsOneWidget,
          );

          handle.dispose();
        },
      );
    });

    group('3. Color Contrast Ratios (WCAG AA >= 4.5:1 Mathematical Proof)', () {
      test('WCAG relative luminance calculations meet >= 4.5:1 contrast', () {
        // 1. LooSecondaryButton foreground (AppColors.primaryDark) on white surface
        final primaryDarkOnSurface = calculateContrastRatio(
          AppColors.primaryDark,
          AppColors.surface,
        );
        expect(
          primaryDarkOnSurface,
          greaterThanOrEqualTo(4.5),
          reason:
              'AppColors.primaryDark on white must meet WCAG AA normal text (actual: ${primaryDarkOnSurface.toStringAsFixed(2)}:1)',
        );
        expect(primaryDarkOnSurface, greaterThanOrEqualTo(7.0));

        // 2. LooSecondaryButton foreground (AppColors.primaryDark) on canvas background
        final primaryDarkOnBackground = calculateContrastRatio(
          AppColors.primaryDark,
          AppColors.background,
        );
        expect(
          primaryDarkOnBackground,
          greaterThanOrEqualTo(4.5),
          reason:
              'AppColors.primaryDark on AppColors.background must meet WCAG AA (actual: ${primaryDarkOnBackground.toStringAsFixed(2)}:1)',
        );

        // 3. AppColors.textPrimary on surface and background
        final textPrimaryOnSurface = calculateContrastRatio(
          AppColors.textPrimary,
          AppColors.surface,
        );
        final textPrimaryOnBackground = calculateContrastRatio(
          AppColors.textPrimary,
          AppColors.background,
        );
        expect(textPrimaryOnSurface, greaterThanOrEqualTo(15.0));
        expect(textPrimaryOnBackground, greaterThanOrEqualTo(15.0));

        // 4. AppColors.textSecondary on surface (used for informative descriptions)
        final textSecondaryOnSurface = calculateContrastRatio(
          AppColors.textSecondary,
          AppColors.surface,
        );
        expect(
          textSecondaryOnSurface,
          greaterThanOrEqualTo(4.5),
          reason:
              'AppColors.textSecondary on AppColors.surface must meet WCAG AA (actual: ${textSecondaryOnSurface.toStringAsFixed(2)}:1)',
        );

        // 5. Error text (AppColors.onErrorContainer) on error banner background (AppColors.errorContainer)
        final errorTextContrast = calculateContrastRatio(
          AppColors.onErrorContainer,
          AppColors.errorContainer,
        );
        expect(
          errorTextContrast,
          greaterThanOrEqualTo(4.5),
          reason:
              'Error text on error container must meet WCAG AA (actual: ${errorTextContrast.toStringAsFixed(2)}:1)',
        );
        expect(errorTextContrast, greaterThanOrEqualTo(6.5));

        // 6. Selected TriState text (AppColors.primaryDark) on primaryLight container
        final primaryDarkOnPrimaryLight = calculateContrastRatio(
          AppColors.primaryDark,
          AppColors.primaryLight,
        );
        expect(
          primaryDarkOnPrimaryLight,
          greaterThanOrEqualTo(4.5),
          reason:
              'Selected text on primaryLight container must meet WCAG AA (actual: ${primaryDarkOnPrimaryLight.toStringAsFixed(2)}:1)',
        );
        // 7. Gender stall error text (AppColors.onErrorContainer) on white surface (AppColors.surface)
        final genderStallErrorOnWhite = calculateContrastRatio(
          AppColors.onErrorContainer,
          AppColors.surface,
        );
        expect(
          genderStallErrorOnWhite,
          greaterThanOrEqualTo(4.5),
          reason:
              'Gender stall error text on white surface must meet WCAG AA (actual: ${genderStallErrorOnWhite.toStringAsFixed(2)}:1)',
        );
        expect(genderStallErrorOnWhite, greaterThanOrEqualTo(7.0));
      });

      testWidgets(
        'LooSecondaryButton renders text and icon using AppColors.primaryDark',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(
              child: Scaffold(
                backgroundColor: AppColors.surface,
                body: Center(
                  child: LooSecondaryButton(
                    label: 'Secondary Action',
                    icon: Icons.map_outlined,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          );

          // Verify text styling uses primaryDark
          final textWidget = tester.widget<Text>(find.text('Secondary Action'));
          expect(textWidget.style?.color, equals(AppColors.primaryDark));

          // Verify icon uses primaryDark
          final iconWidget = tester.widget<Icon>(
            find.byIcon(Icons.map_outlined),
          );
          expect(iconWidget.color, equals(AppColors.primaryDark));
        },
      );

      testWidgets(
        'DuplicateWarningSheet access badge uses high-contrast textPrimary',
        (tester) async {
          final candidate = _createCandidate(
            id: 'test_c1',
            name: 'Terminal 1 Restroom',
            accessType: AccessType.customerOnly,
          );

          await tester.pumpWidget(
            _wrapWithScale(
              child: DuplicateWarningSheet(candidates: [candidate]),
            ),
          );
          await tester.pumpAndSettle();

          final badgeTextWidget = tester.widget<Text>(
            find.text('Customer Only'),
          );
          expect(badgeTextWidget.style?.color, equals(AppColors.textPrimary));
        },
      );

      testWidgets(
        'AddRestroomFormScreen coordinate card uses accessible primaryDark header',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(
              child: AddRestroomFormScreen(
                coordinates: Coordinates(
                  latitude: 14.5839,
                  longitude: 121.0617,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final headerText = tester.widget<Text>(
            find.text('Selected Entrance Location'),
          );
          expect(headerText.style?.color, equals(AppColors.primaryDark));
        },
      );

      testWidgets(
        'AddRestroomFormScreen renders gender-stall validation error text with compliant contrast (>= 4.5:1)',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(
              child: AddRestroomFormScreen(
                coordinates: Coordinates(
                  latitude: 14.5839,
                  longitude: 121.0617,
                ),
              ),
              textScale: 1.0,
            ),
          );
          await tester.pumpAndSettle();

          // Scroll to Male Stalls and tap 'No' to trigger invalid configuration
          final maleStallsFinder = find.widgetWithText(
            TriStateAmenitySelector,
            'Male Stalls',
          );
          await tester.scrollUntilVisible(
            maleStallsFinder,
            100,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(
            find.descendant(of: maleStallsFinder, matching: find.text('No')),
          );
          await tester.pumpAndSettle();

          // Scroll to Continue button and tap to trigger validation
          final continueButton = find.widgetWithText(
            LooPrimaryButton,
            'Continue',
          );
          await tester.scrollUntilVisible(
            continueButton,
            100,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(continueButton);
          await tester.pumpAndSettle();

          // Verify the rendered error text widget
          final errorTextFinder = find.text(
            'Select applicable gender stalls or leave all unspecified',
          );
          expect(errorTextFinder, findsOneWidget);

          final errorTextWidget = tester.widget<Text>(errorTextFinder);
          expect(
            errorTextWidget.style?.color,
            equals(AppColors.onErrorContainer),
          );

          // Assert WCAG AA contrast ratio of the actual rendered text color against white surface
          final contrast = calculateContrastRatio(
            errorTextWidget.style!.color!,
            AppColors.surface,
          );
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason:
                'Rendered gender-stall error text must meet WCAG AA contrast (actual: ${contrast.toStringAsFixed(2)}:1)',
          );
          expect(contrast, greaterThanOrEqualTo(7.0));
        },
      );
    });

    group('4. Multi-Viewport & 200% Text Scaling Layout Stability (Zero RenderFlex Overflows)', () {
      const testWidths = [320.0, 375.0, 390.0];

      for (final width in testWidths) {
        testWidgets(
          'AddRestroomLocationScreen with multiline instruction banner renders without overflow at ${width.toInt()}px width and 200% scale',
          (tester) async {
            configureTestViewport(tester, width: width, height: 844.0);

            await tester.pumpWidget(
              _wrapWithScale(child: _buildLocationScreen(), textScale: 2.0),
            );
            await tester.pumpAndSettle();

            final mq = tester.element(find.byType(AddRestroomLocationScreen));
            final mqData = MediaQuery.of(mq);
            expect(mqData.size.width, equals(width));
            expect(mqData.size.height, equals(844.0));
            expect(mqData.textScaler, equals(const TextScaler.linear(2.0)));

            expect(
              tester.takeException(),
              isNull,
              reason: 'Zero RenderFlex overflow on ${width.toInt()}px width',
            );
            expect(find.text('Pinpoint the restroom'), findsOneWidget);
            expect(
              find.textContaining(
                'Move the map so the marker is exactly where',
              ),
              findsOneWidget,
            );
            expect(find.byType(MapRecenterButton), findsOneWidget);
            expect(
              find.widgetWithText(LooPrimaryButton, 'Continue'),
              findsOneWidget,
            );
          },
        );

        testWidgets(
          'AddRestroomFormScreen renders validation error state and paid-fee fields without overflow at ${width.toInt()}px width and 200% scale',
          (tester) async {
            configureTestViewport(tester, width: width, height: 844.0);

            await tester.pumpWidget(
              _wrapWithScale(
                child: AddRestroomFormScreen(
                  coordinates: Coordinates(
                    latitude: 14.5839,
                    longitude: 121.0617,
                  ),
                ),
                textScale: 2.0,
              ),
            );
            await tester.pumpAndSettle();

            final mq = tester.element(find.byType(AddRestroomFormScreen));
            final mqData = MediaQuery.of(mq);
            expect(mqData.size.width, equals(width));
            expect(mqData.size.height, equals(844.0));
            expect(mqData.textScaler, equals(const TextScaler.linear(2.0)));

            // Trigger validation error state
            await tester.tap(find.widgetWithText(LooPrimaryButton, 'Continue'));
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason:
                  'Zero RenderFlex overflow with error banner on ${width.toInt()}px width',
            );
            expect(
              find.text('Please fix the following errors:'),
              findsOneWidget,
            );

            // Scroll to Access Type dropdown to bring it into view and select Paid Access
            await tester.scrollUntilVisible(
              find.text('Free (Public Access)'),
              100,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text('Free (Public Access)'));
            await tester.pumpAndSettle();

            await tester.tap(find.text('Paid (Fee Required)').last);
            await tester.pumpAndSettle();

            // Scroll down to fee inputs
            await tester.scrollUntilVisible(
              find.text('Fee Amount *'),
              100,
              scrollable: find.byType(Scrollable).first,
            );

            expect(
              tester.takeException(),
              isNull,
              reason:
                  'Zero RenderFlex overflow with fee fields on ${width.toInt()}px width',
            );
            expect(find.text('Fee Amount *'), findsOneWidget);
            expect(find.text('Currency *'), findsOneWidget);
          },
        );

        testWidgets(
          'DuplicateWarningSheet renders long content without overflow at ${width.toInt()}px width and 200% scale',
          (tester) async {
            configureTestViewport(tester, width: width, height: 844.0);

            final candidates = [
              _createCandidate(
                id: 'c_long',
                name: 'Grand Central Shopping Mall East Terminal Restroom Facility',
                buildingName:
                    'Grand Central Shopping Mall East Terminal Complex',
                floor: 'Level 3 East Wing Concourse Near Gate 12',
                accessType: AccessType.paid,
              ),
            ];

            await tester.pumpWidget(
              _wrapWithScale(
                child: Scaffold(
                  body: DuplicateWarningSheet(candidates: candidates),
                ),
                textScale: 2.0,
              ),
            );
            await tester.pumpAndSettle();

            // Assert real MediaQuery dimensions
            final mq = tester.element(find.byType(DuplicateWarningSheet));
            final mqData = MediaQuery.of(mq);
            expect(mqData.size.width, equals(width));
            expect(mqData.size.height, equals(844.0));
            expect(mqData.textScaler, equals(const TextScaler.linear(2.0)));

            // Assert nonzero rendered height and bounded by 85% of screen height
            final sheetBox = tester.renderObject(
              find.byType(DuplicateWarningSheet),
            ) as RenderBox;
            expect(sheetBox.size.height, greaterThan(0.0));
            expect(sheetBox.size.height, lessThanOrEqualTo(844.0 * 0.85 + 0.1));

            expect(
              tester.takeException(),
              isNull,
              reason:
                  'Zero RenderFlex overflow on duplicate sheet for ${width.toInt()}px width',
            );
            expect(find.text('Similar restrooms found nearby'), findsOneWidget);

            // Verify warning-sheet actions remain visible, scrollable and accessible at 200% scaling
            final viewExistingFinder = find.widgetWithText(
              LooSecondaryButton,
              'View Existing Restroom',
            );
            await tester.scrollUntilVisible(
              viewExistingFinder,
              100,
              scrollable: find.byType(Scrollable).first,
            );
            expect(viewExistingFinder, findsOneWidget);
            final viewExistingBox =
                tester.renderObject(viewExistingFinder) as RenderBox;
            expect(viewExistingBox.size.height, greaterThanOrEqualTo(48.0));

            final proceedFinder = find.widgetWithText(
              LooPrimaryButton,
              "No, It's a Different Restroom",
            );
            await tester.scrollUntilVisible(
              proceedFinder,
              100,
              scrollable: find.byType(Scrollable).first,
            );
            expect(proceedFinder, findsOneWidget);
            final proceedBox = tester.renderObject(proceedFinder) as RenderBox;
            expect(proceedBox.size.height, greaterThanOrEqualTo(48.0));
          },
        );
      }

      testWidgets(
        'TriStateAmenitySelector renders without overflow at 200% text scale',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(
              textScale: 2.0,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TriStateAmenitySelector(
                    title: 'Accessible Stall for Persons with Disabilities',
                    subtitle: 'Includes grab bars and wider doorway entrance',
                    value: TriStateAmenity.unknown,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Unspecified'), findsOneWidget);
        },
      );

      testWidgets(
        'LooPrimaryButton and LooSecondaryButton scale cleanly at 200% text scale',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithScale(
              textScale: 2.0,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      LooPrimaryButton(
                        label: 'Submit Restroom to Community Directory',
                        onPressed: () {},
                      ),
                      const SizedBox(height: 16),
                      LooSecondaryButton(
                        label: 'View Existing Restroom Facilities Nearby',
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    });
  });
}
