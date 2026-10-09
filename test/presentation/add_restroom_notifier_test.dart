import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/restroom_draft.dart';
import 'package:flushcrowd/presentation/state/add_restroom_notifier.dart';
import 'package:flushcrowd/presentation/state/restroom_id_generator.dart';

class DeterministicRestroomIdGenerator implements RestroomIdGenerator {
  int calls = 0;
  final String prefix;

  DeterministicRestroomIdGenerator({this.prefix = 'test_id_'});

  @override
  String generate() {
    calls++;
    return '$prefix$calls';
  }
}

void main() {
  final testCoords = Coordinates(latitude: 14.5839, longitude: 121.0617);

  group('AddRestroomNotifier — Presentation State & Validation', () {
    test('1. initial amenities = unknown', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);

      expect(notifier.pwdAccessible, equals(TriStateAmenity.unknown));
      expect(notifier.babyChanging, equals(TriStateAmenity.unknown));
      expect(notifier.hasBidet, equals(TriStateAmenity.unknown));
      expect(notifier.hasToiletPaper, equals(TriStateAmenity.unknown));
      expect(notifier.hasSoap, equals(TriStateAmenity.unknown));
      expect(notifier.hasHandDryer, equals(TriStateAmenity.unknown));
    });

    test('2. initial stall values = null', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);

      expect(notifier.male, isNull);
      expect(notifier.female, isNull);
      expect(notifier.allGender, isNull);
    });

    test('3. builds draft with confirmed P2.2 coordinates', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);
      notifier.setName('Metro Station Restroom');

      final draft = notifier.buildDraft();

      expect(draft.coordinates, equals(testCoords));
      expect(draft.coordinates.latitude, equals(14.5839));
      expect(draft.coordinates.longitude, equals(121.0617));
      expect(draft.name, equals('Metro Station Restroom'));
      expect(draft.accessType, equals(AccessType.free));
    });

    test('4. normalization trims text', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);
      notifier.setName('   Central Mall Restroom   ');
      notifier.setBuildingName('  Main Building  ');
      notifier.setFloor('  2F  ');
      notifier.setBuildingSection('  East Wing  ');
      notifier.setUnitOrArea('  Unit 201  ');
      notifier.setLandmark('  Near elevators  ');
      notifier.setDirectionsNote('  Down the hall on right  ');
      notifier.setAccessInstructions('  Ask staff for code  ');

      final draft = notifier.buildDraft();
      final normalized = draft.normalized();

      expect(normalized.name, equals('Central Mall Restroom'));
      expect(normalized.buildingName, equals('Main Building'));
      expect(normalized.floor, equals('2F'));
      expect(normalized.buildingSection, equals('East Wing'));
      expect(normalized.unitOrArea, equals('Unit 201'));
      expect(normalized.landmark, equals('Near elevators'));
      expect(normalized.directionsNote, equals('Down the hall on right'));
      expect(normalized.accessInstructions, equals('Ask staff for code'));
    });

    test('5. whitespace-only optionals become null', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);
      notifier.setName('Valid Restroom');
      notifier.setBuildingName('   ');
      notifier.setFloor('\t\n');
      notifier.setBuildingSection('   ');
      notifier.setUnitOrArea(' ');
      notifier.setLandmark('   ');
      notifier.setDirectionsNote('   ');
      notifier.setAccessInstructions('   ');

      final draft = notifier.buildDraft();
      final normalized = draft.normalized();

      expect(normalized.buildingName, isNull);
      expect(normalized.floor, isNull);
      expect(normalized.buildingSection, isNull);
      expect(normalized.unitOrArea, isNull);
      expect(normalized.landmark, isNull);
      expect(normalized.directionsNote, isNull);
      expect(normalized.accessInstructions, isNull);
    });

    test('6. country and currency normalization behavior', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);
      notifier.setName('Airport Restroom');
      notifier.setAccessType(AccessType.paid);
      notifier.setFeeAmountText('15.50');
      notifier.setFeeCurrency('  usd  ');
      notifier.setCountryCode('  ph  ');

      final draft = notifier.buildDraft();
      final normalized = draft.normalized();

      expect(normalized.feeCurrency, equals('USD'));
      expect(normalized.countryCode, equals('PH'));
      expect(normalized.feeAmount, equals(15.50));
    });

    test('7. invalid form exposes validation errors', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);
      // Empty name is invalid
      final success = notifier.validateAndPrepare();

      expect(success, isFalse);
      expect(notifier.errors, isNotEmpty);
      expect(notifier.nameError, isNotNull);
      expect(notifier.nameError, contains('Facility name is required'));
      expect(notifier.isValidated, isTrue);
      expect(notifier.preparedCommand, isNull);
    });

    test('8. invalid form does not allocate ID', () {
      final generator = DeterministicRestroomIdGenerator();
      final notifier = AddRestroomNotifier(
        coordinates: testCoords,
        idGenerator: generator,
      );

      final success = notifier.validateAndPrepare();

      expect(success, isFalse);
      expect(generator.calls, equals(0));
      expect(notifier.allocatedRestroomId, isNull);
      expect(notifier.preparedCommand, isNull);
    });

    test('9. first valid preparation allocates exactly one ID', () {
      final generator = DeterministicRestroomIdGenerator();
      final notifier = AddRestroomNotifier(
        coordinates: testCoords,
        idGenerator: generator,
      );
      notifier.setName('City Park Restroom');

      final success = notifier.validateAndPrepare();

      expect(success, isTrue);
      expect(generator.calls, equals(1));
      expect(notifier.allocatedRestroomId, equals('test_id_1'));
      expect(notifier.preparedCommand, isNotNull);
      expect(notifier.preparedCommand!.restroomId, equals('test_id_1'));
      expect(
        notifier.preparedCommand!.draft.name,
        equals('City Park Restroom'),
      );
    });

    test('10. repeated validation/preparation reuses same ID', () {
      final generator = DeterministicRestroomIdGenerator();
      final notifier = AddRestroomNotifier(
        coordinates: testCoords,
        idGenerator: generator,
      );
      notifier.setName('City Park Restroom');

      notifier.validateAndPrepare();
      final firstId = notifier.allocatedRestroomId;

      // Repeat validation without changing fields
      final secondSuccess = notifier.validateAndPrepare();

      expect(secondSuccess, isTrue);
      expect(generator.calls, equals(1)); // Still only 1 generation
      expect(notifier.allocatedRestroomId, equals(firstId));
      expect(notifier.preparedCommand!.restroomId, equals(firstId));
    });

    test('11. editing after ID allocation retains same ID', () {
      final generator = DeterministicRestroomIdGenerator();
      final notifier = AddRestroomNotifier(
        coordinates: testCoords,
        idGenerator: generator,
      );
      notifier.setName('Initial Name');

      notifier.validateAndPrepare();
      final originalId = notifier.allocatedRestroomId;
      expect(originalId, equals('test_id_1'));

      // Modify a form field
      notifier.setName('Updated Name After Allocation');
      expect(notifier.allocatedRestroomId, equals(originalId));

      // Re-validate and prepare
      final success = notifier.validateAndPrepare();
      expect(success, isTrue);
      expect(generator.calls, equals(1)); // No new ID generated
      expect(notifier.allocatedRestroomId, equals(originalId));
      expect(
        notifier.preparedCommand!.draft.name,
        equals('Updated Name After Allocation'),
      );
      expect(notifier.preparedCommand!.restroomId, equals(originalId));
    });

    test('12. new notifier/session receives a new ID', () {
      final generator = DeterministicRestroomIdGenerator();
      final notifier1 = AddRestroomNotifier(
        coordinates: testCoords,
        idGenerator: generator,
      );
      notifier1.setName('First Facility');
      notifier1.validateAndPrepare();

      expect(notifier1.allocatedRestroomId, equals('test_id_1'));

      // Completely new session
      final notifier2 = AddRestroomNotifier(
        coordinates: testCoords,
        idGenerator: generator,
      );
      notifier2.setName('Second Facility');
      notifier2.validateAndPrepare();

      expect(notifier2.allocatedRestroomId, equals('test_id_2'));
      expect(generator.calls, equals(2));
    });

    test('13. non-paid normalized command contains no stale fee fields', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);
      notifier.setName('Paid then Free Restroom');

      // Set to paid initially
      notifier.setAccessType(AccessType.paid);
      notifier.setFeeAmountText('50');
      notifier.setFeeCurrency('PHP');

      // Switch back to free
      notifier.setAccessType(AccessType.free);

      final success = notifier.validateAndPrepare();
      expect(success, isTrue);

      final command = notifier.preparedCommand!;
      expect(command.draft.accessType, equals(AccessType.free));
      expect(command.draft.feeAmount, isNull);
      expect(command.draft.feeCurrency, isNull);
    });

    test('14. prepared command contains normalized draft and stable ID', () {
      final generator = DeterministicRestroomIdGenerator(prefix: 'stable_');
      final notifier = AddRestroomNotifier(
        coordinates: testCoords,
        idGenerator: generator,
      );
      notifier.setName('  Community Restroom  ');
      notifier.setAccessType(AccessType.customerOnly);
      notifier.setPwdAccessible(TriStateAmenity.yes);
      notifier.setHasBidet(TriStateAmenity.yes);
      notifier.setMale(true);
      notifier.setFemale(true);

      final success = notifier.validateAndPrepare();
      expect(success, isTrue);

      final command = notifier.preparedCommand;
      expect(command, isA<CreateRestroomCommand>());
      expect(command!.restroomId, equals('stable_1'));
      expect(command.draft.name, equals('Community Restroom'));
      expect(command.draft.accessType, equals(AccessType.customerOnly));
      expect(command.draft.pwdAccessible, equals(TriStateAmenity.yes));
      expect(command.draft.hasBidet, equals(TriStateAmenity.yes));
      expect(command.draft.male, isTrue);
      expect(command.draft.female, isTrue);
      expect(command.draft.allGender, isNull);
      expect(command.draft.babyChanging, equals(TriStateAmenity.unknown));
    });

    test('15. zero repository submission calls occur in P2.3 notifier', () {
      final notifier = AddRestroomNotifier(coordinates: testCoords);
      notifier.setName('Validation Only Restroom');

      final success = notifier.validateAndPrepare();
      expect(success, isTrue);
      // Notifier has no dependency on RestroomRepository or persistence
      expect(notifier.preparedCommand, isNotNull);
    });

    test('16. when initialized with initialCommand, pre-populates all fields and preserves stable restroomId across validation', () {
      final idGen = DeterministicRestroomIdGenerator(prefix: 'unused_gen_');
      final originalDraft = RestroomDraft(
        coordinates: testCoords,
        name: 'Preserved Draft Restroom',
        accessType: AccessType.customerOnly,
        buildingName: 'Tower A',
        floor: '3F',
        buildingSection: 'North Hall',
        unitOrArea: 'Unit 301',
        landmark: 'By the stairs',
        directionsNote: 'Walk past lobby',
        accessInstructions: 'Key with manager',
        male: true,
        female: true,
        allGender: false,
        pwdAccessible: TriStateAmenity.yes,
        babyChanging: TriStateAmenity.no,
        hasBidet: TriStateAmenity.yes,
        hasToiletPaper: TriStateAmenity.yes,
        hasSoap: TriStateAmenity.yes,
        hasHandDryer: TriStateAmenity.no,
        feeAmount: 50.0,
        feeCurrency: 'PHP',
      );
      final initialCommand = CreateRestroomCommand(
        restroomId: 'stable_preserved_id_99',
        draft: originalDraft,
      );

      final notifier = AddRestroomNotifier(
        coordinates: testCoords,
        initialCommand: initialCommand,
        idGenerator: idGen,
      );

      // Verify all fields are pre-populated from initialCommand
      expect(notifier.name, equals('Preserved Draft Restroom'));
      expect(notifier.accessType, equals(AccessType.customerOnly));
      expect(notifier.buildingName, equals('Tower A'));
      expect(notifier.floor, equals('3F'));
      expect(notifier.buildingSection, equals('North Hall'));
      expect(notifier.unitOrArea, equals('Unit 301'));
      expect(notifier.landmark, equals('By the stairs'));
      expect(notifier.directionsNote, equals('Walk past lobby'));
      expect(notifier.accessInstructions, equals('Key with manager'));
      expect(notifier.male, isTrue);
      expect(notifier.female, isTrue);
      expect(notifier.allGender, isFalse);
      expect(notifier.pwdAccessible, equals(TriStateAmenity.yes));
      expect(notifier.babyChanging, equals(TriStateAmenity.no));
      expect(notifier.hasBidet, equals(TriStateAmenity.yes));
      expect(notifier.hasToiletPaper, equals(TriStateAmenity.yes));
      expect(notifier.hasSoap, equals(TriStateAmenity.yes));
      expect(notifier.hasHandDryer, equals(TriStateAmenity.no));
      expect(notifier.feeAmountText, equals('50.0'));
      expect(notifier.feeCurrency, equals('PHP'));

      // Validate and prepare
      final success = notifier.validateAndPrepare();
      expect(success, isTrue);

      final prepared = notifier.preparedCommand;
      expect(prepared, isNotNull);
      // Crucial invariant: ID is exactly the original ID, generator was never touched
      expect(prepared!.restroomId, equals('stable_preserved_id_99'));
      expect(idGen.calls, equals(0));
      expect(prepared.draft.name, equals('Preserved Draft Restroom'));
      expect(prepared.draft.buildingName, equals('Tower A'));
    });
  });
}
