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

Widget _wrapWithScale({
  required Widget child,
  double textScale = 1.0,
  Size size = const Size(390, 844),
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    ),
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

    group('3. Color Contrast Ratios (WCAG AA >= 4.5:1)', () {
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
    });

    group(
      '4. 200% Text Scaling Layout Stability (Zero RenderFlex Overflows)',
      () {
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

        testWidgets(
          'AddRestroomLocationScreen layout remains stable at 200% text scale',
          (tester) async {
            await tester.pumpWidget(
              _wrapWithScale(
                textScale: 2.0,
                child: AddRestroomLocationScreen(
                  initialCoordinates: Coordinates(
                    latitude: 14.5839,
                    longitude: 121.0617,
                  ),
                  locationRepository: InMemoryLocationRepository(
                    initialCoordinates: Coordinates(
                      latitude: 14.5839,
                      longitude: 121.0617,
                    ),
                  ),
                  mapBuilder:
                      ({
                        required BuildContext context,
                        required initialCameraPosition,
                        onCameraIdle,
                        onCameraMove,
                        onCameraMoveStarted,
                        onMapCreated,
                      }) {
                        return const SizedBox.expand(
                          child: ColoredBox(color: Colors.grey),
                        );
                      },
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('Pinpoint the restroom'), findsOneWidget);
            expect(find.byType(MapRecenterButton), findsOneWidget);
          },
        );

        testWidgets(
          'AddRestroomFormScreen renders without overflow at 200% text scale (Free & Paid)',
          (tester) async {
            await tester.pumpWidget(
              _wrapWithScale(
                textScale: 2.0,
                child: AddRestroomFormScreen(
                  coordinates: Coordinates(
                    latitude: 14.5839,
                    longitude: 121.0617,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);

            // Switch to Paid to render fee amount and currency layout
            await tester.tap(find.text('Free (Public Access)'));
            await tester.pumpAndSettle();

            await tester.tap(find.text('Paid (Fee Required)').last);
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('Fee Amount *'), findsOneWidget);
            expect(find.text('Currency *'), findsOneWidget);
          },
        );

        testWidgets(
          'DuplicateWarningSheet renders cleanly at 200% text scale',
          (tester) async {
            final candidates = [
              _createCandidate(
                id: 'c1',
                name: 'Grand Shopping Complex East Wing Public Restroom',
                buildingName: 'Grand Shopping Complex East Wing',
                floor: 'Level 3 East Wing Near Cinema',
                accessType: AccessType.paid,
              ),
            ];

            await tester.pumpWidget(
              _wrapWithScale(
                textScale: 2.0,
                child: DuplicateWarningSheet(candidates: candidates),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('Similar restrooms found nearby'), findsOneWidget);
            expect(find.text("No, It's a Different Restroom"), findsOneWidget);
          },
        );
      },
    );
  });
}
