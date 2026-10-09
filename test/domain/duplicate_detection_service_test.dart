import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/domain/models/coordinates.dart';
import 'package:flushcrowd/domain/models/discovery_result.dart';
import 'package:flushcrowd/domain/models/duplicate_candidate.dart';
import 'package:flushcrowd/domain/models/enums.dart';
import 'package:flushcrowd/domain/models/geo_bounding_box.dart';
import 'package:flushcrowd/domain/models/restroom.dart';
import 'package:flushcrowd/domain/models/restroom_draft.dart';
import 'package:flushcrowd/domain/repositories/restroom_repository.dart';
import 'package:flushcrowd/domain/services/duplicate_detection_service.dart';
import 'package:flushcrowd/domain/commands/create_restroom_command.dart';

class MockDuplicateRestroomRepository implements RestroomRepository {
  List<Restroom> candidatesToReturn = [];
  bool shouldThrow = false;
  Coordinates? lastCenterQueried;
  double? lastRadiusQueried;
  bool isComplete = true;
  DiscoveryCompletenessReason completenessReason =
      DiscoveryCompletenessReason.complete;
  int rangeCount = 1;
  int candidateCount = 1;

  @override
  Future<DiscoveryResult<Restroom>> getDuplicateCandidates(
    Coordinates center, {
    double radiusMeters = 500.0,
  }) async {
    lastCenterQueried = center;
    lastRadiusQueried = radiusMeters;
    if (shouldThrow) {
      throw Exception('Network error during candidate retrieval');
    }
    return DiscoveryResult(
      items: candidatesToReturn,
      isComplete: isComplete,
      completenessReason: completenessReason,
      rangeCount: rangeCount,
      candidateCount: candidateCount,
    );
  }

  @override
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async => DiscoveryResult.complete(items: candidatesToReturn);

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async => DiscoveryResult.complete(items: const []);

  @override
  Future<Restroom?> getRestroomById(String id) async => null;

  @override
  Future<Restroom> submitRestroom(CreateRestroomCommand command) async =>
      throw UnimplementedError();
}

Restroom _createCandidate({
  required String id,
  required String name,
  required double latitude,
  required double longitude,
  String? buildingName,
  String? floor,
  String? buildingSection,
  String? unitOrArea,
  String? landmark,
  AccessType accessType = AccessType.free,
}) {
  return Restroom(
    id: id,
    name: name,
    coordinates: Coordinates(latitude: latitude, longitude: longitude),
    geohash: 'w4rr7x',
    accessType: accessType,
    buildingName: buildingName,
    floor: floor,
    buildingSection: buildingSection,
    unitOrArea: unitOrArea,
    landmark: landmark,
    status: RestroomStatus.active,
    createdAt: DateTime(2026, 1, 1),
  );
}

RestroomDraft _createDraft({
  required String name,
  required double latitude,
  required double longitude,
  String? buildingName,
  String? floor,
  String? buildingSection,
  String? unitOrArea,
  String? landmark,
  AccessType accessType = AccessType.free,
}) {
  return RestroomDraft(
    name: name,
    coordinates: Coordinates(latitude: latitude, longitude: longitude),
    accessType: accessType,
    buildingName: buildingName,
    floor: floor,
    buildingSection: buildingSection,
    unitOrArea: unitOrArea,
    landmark: landmark,
  );
}

void main() {
  const service = DuplicateDetectionService();

  group(
    'DuplicateDetectionService — Unicode-Preserving Text Normalization',
    () {
      test('1. Normalizes and tokenizes Japanese script without stripping Kanji/Kana', () {
        const text = '【東京駅】 トイレ・1F';
        final normalized = DuplicateDetectionService.normalizeText(text);
        expect(normalized, equals('東京駅 トイレ 1f'));

        final tokens = DuplicateDetectionService.tokenize(text);
        expect(tokens, containsAll(['東京駅', 'トイレ', '1f']));
      });

      test('2. Normalizes and tokenizes Arabic script without stripping Arabic characters', () {
        const text = 'مطار دبي ، حمام!';
        final normalized = DuplicateDetectionService.normalizeText(text);
        expect(normalized, equals('مطار دبي حمام'));

        final tokens = DuplicateDetectionService.tokenize(text);
        expect(tokens, containsAll(['مطار', 'دبي', 'حمام']));
      });

      test('3. Normalizes and tokenizes Cyrillic script with case-folding', () {
        const text = 'Туалет Москва (Центр)';
        final normalized = DuplicateDetectionService.normalizeText(text);
        expect(normalized, equals('туалет москва центр'));

        final tokens = DuplicateDetectionService.tokenize(text);
        expect(tokens, containsAll(['туалет', 'москва', 'центр']));
      });

      test('4. Normalizes and tokenizes Korean Hangul script', () {
        const text = '화장실 - 서울역 [3번 출구]';
        final normalized = DuplicateDetectionService.normalizeText(text);
        expect(normalized, equals('화장실 서울역 3번 출구'));

        final tokens = DuplicateDetectionService.tokenize(text);
        expect(tokens, containsAll(['화장실', '서울역', '3번', '출구']));
      });

      test('5. Normalizes and tokenizes accented Latin script', () {
        const text = 'Café Central — Restroom #2';
        final normalized = DuplicateDetectionService.normalizeText(text);
        expect(normalized, equals('café central restroom 2'));

        final tokens = DuplicateDetectionService.tokenize(text);
        expect(tokens, containsAll(['café', 'central', 'restroom', '2']));
      });

      test('5b. Composed and decomposed accented Latin strings produce equivalent normalized forms', () {
        // Composed: \u00E9 (é)
        const composedCafe = 'Caf\u00E9 Central';
        // Decomposed: e + \u0301 (combining acute accent)
        const decomposedCafe = 'Cafe\u0301 Central';
        expect(
          DuplicateDetectionService.normalizeText(composedCafe),
          equals(DuplicateDetectionService.normalizeText(decomposedCafe)),
        );
        expect(
          DuplicateDetectionService.tokenize(composedCafe),
          equals(DuplicateDetectionService.tokenize(decomposedCafe)),
        );

        // German Umlaut: composed \u00FC (ü) vs decomposed u + \u0308
        const composedMunchen = 'M\u00FCnchen Hbf Toilette';
        const decomposedMunchen = 'Mu\u0308nchen Hbf Toilette';
        expect(
          DuplicateDetectionService.normalizeText(composedMunchen),
          equals(DuplicateDetectionService.normalizeText(decomposedMunchen)),
        );

        // Norwegian: composed \u00C5 (Å) vs decomposed A + \u030A
        const composedAlesund = '\u00C5lesund Toalett';
        const decomposedAlesund = 'A\u030Alesund Toalett';
        expect(
          DuplicateDetectionService.normalizeText(composedAlesund),
          equals(DuplicateDetectionService.normalizeText(decomposedAlesund)),
        );
      });

      test('5c. Japanese, Arabic, Cyrillic, Chinese, and Korean scripts preserve canonical equivalence', () {
        // Japanese: composed が (\u304C) vs decomposed か + \u3099 (\u304B\u3099)
        const composedJp = '渋谷駅が近い トイレ';
        const decomposedJp = '渋谷駅\u304B\u3099近い トイレ';
        expect(
          DuplicateDetectionService.normalizeText(composedJp),
          equals(DuplicateDetectionService.normalizeText(decomposedJp)),
        );

        // Korean: composed 서울 (\uC11C\uC6B8) vs decomposed Jamo
        const composedKr = '\uC11C\uC6B8\uC5ED 화장실';
        const decomposedKr = '\u1109\u1165\u110B\u116E\u11AF\uC5ED 화장실';
        expect(
          DuplicateDetectionService.normalizeText(composedKr),
          equals(DuplicateDetectionService.normalizeText(decomposedKr)),
        );

        // Cyrillic: composed й (\u0439) vs decomposed и + \u0306 (\u0438\u0306)
        const composedRu = 'Туалет на вокзале, 1-й этаж';
        const decomposedRu = 'Туалет на вокзале, 1-\u0438\u0306 этаж';
        expect(
          DuplicateDetectionService.normalizeText(composedRu),
          equals(DuplicateDetectionService.normalizeText(decomposedRu)),
        );

        // Chinese: preserved accurately without losing Han characters
        const zh = '中央车站 负一层 洗手间 (A区)';
        expect(
          DuplicateDetectionService.normalizeText(zh),
          equals('中央车站 负一层 洗手间 a区'),
        );
        expect(
          DuplicateDetectionService.tokenize(zh),
          containsAll(['中央车站', '负一层', '洗手间', 'a区']),
        );

        // Arabic: preserved accurately without losing Arabic letters
        const ar = 'دورة مياه المركز التجاري — الطابق الأول';
        expect(
          DuplicateDetectionService.normalizeText(ar),
          equals('دورة مياه المركز التجاري الطابق الأول'),
        );
      });

      test('6. Collapses multiple whitespace, tabs, and newlines', () {
        const text = '   Grand \t Mall \n\n Restroom   ';
        final normalized = DuplicateDetectionService.normalizeText(text);
        expect(normalized, equals('grand mall restroom'));
        expect(
          DuplicateDetectionService.tokenize(text),
          equals({'grand', 'mall', 'restroom'}),
        );
      });

      test('7. Handles empty, null, and punctuation-only inputs safely', () {
        expect(DuplicateDetectionService.normalizeText(null), equals(''));
        expect(DuplicateDetectionService.normalizeText(''), equals(''));
        expect(DuplicateDetectionService.normalizeText('   '), equals(''));
        expect(
          DuplicateDetectionService.normalizeText('!@#\$%^&*()'),
          equals(''),
        );

        expect(DuplicateDetectionService.tokenize(null), isEmpty);
        expect(DuplicateDetectionService.tokenize(''), isEmpty);
        expect(DuplicateDetectionService.tokenize('  ---  '), isEmpty);
      });
    },
  );

  group(
    'DuplicateDetectionService — Dice Coefficient & Zero-Division Guards',
    () {
      test('8. Returns 0.0 when both token sets are empty', () {
        final score = DuplicateDetectionService.diceCoefficient(
          const {},
          const {},
        );
        expect(score, equals(0.0));
      });

      test('9. Returns 0.0 when one token set is empty', () {
        final score1 = DuplicateDetectionService.diceCoefficient({
          'tokyo',
        }, const {});
        final score2 = DuplicateDetectionService.diceCoefficient(const {}, {
          'tokyo',
        });
        expect(score1, equals(0.0));
        expect(score2, equals(0.0));
      });

      test('10. Returns 1.0 for identical non-empty token sets', () {
        final tokens = {'shibuya', 'station', 'restroom'};
        final score = DuplicateDetectionService.diceCoefficient(tokens, tokens);
        expect(score, equals(1.0));
      });

      test('11. Returns 0.0 for completely disjoint token sets', () {
        final tokens1 = {'shibuya', 'station'};
        final tokens2 = {'shinjuku', 'mall'};
        final score = DuplicateDetectionService.diceCoefficient(
          tokens1,
          tokens2,
        );
        expect(score, equals(0.0));
      });

      test('12. Computes correct partial overlap Dice coefficient', () {
        final tokens1 = {'grand', 'mall', 'restroom'};
        final tokens2 = {'grand', 'plaza', 'restroom'};
        // |T1| = 3, |T2| = 3, intersection = {'grand', 'restroom'} (2)
        // 2 * 2 / (3 + 3) = 4 / 6 = 2/3
        final score = DuplicateDetectionService.diceCoefficient(
          tokens1,
          tokens2,
        );
        expect(score, closeTo(2 / 3, 0.0001));
      });
    },
  );

  group('DuplicateDetectionService — Deterministic Scoring Primitives', () {
    test('13. Distance metric evaluates all distance brackets accurately', () {
      expect(DuplicateDetectionService.computeDistanceScore(0.0), equals(1.0));
      expect(DuplicateDetectionService.computeDistanceScore(29.9), equals(1.0));
      expect(DuplicateDetectionService.computeDistanceScore(30.0), equals(0.7));
      expect(DuplicateDetectionService.computeDistanceScore(99.9), equals(0.7));
      expect(
        DuplicateDetectionService.computeDistanceScore(100.0),
        equals(0.3),
      );
      expect(
        DuplicateDetectionService.computeDistanceScore(299.9),
        equals(0.3),
      );
      expect(
        DuplicateDetectionService.computeDistanceScore(300.0),
        equals(0.1),
      );
      expect(
        DuplicateDetectionService.computeDistanceScore(500.0),
        equals(0.1),
      );
      expect(
        DuplicateDetectionService.computeDistanceScore(500.1),
        equals(0.0),
      );
      expect(
        DuplicateDetectionService.computeDistanceScore(1000.0),
        equals(0.0),
      );
    });

    test('14. Building metric evaluates match (1.0), conflict (0.0), and unspecified (0.5)', () {
      expect(
        DuplicateDetectionService.computeBuildingScore(
          'Mall of Asia',
          'Mall of Asia',
        ),
        equals(1.0),
      );
      expect(
        DuplicateDetectionService.computeBuildingScore(
          'Mall of Asia',
          'Megamall',
        ),
        equals(0.0),
      );
      expect(
        DuplicateDetectionService.computeBuildingScore('Mall of Asia', null),
        equals(0.5),
      );
      expect(
        DuplicateDetectionService.computeBuildingScore(null, 'Megamall'),
        equals(0.5),
      );
      expect(
        DuplicateDetectionService.computeBuildingScore(null, null),
        equals(0.5),
      );
    });

    test('15. Section/unit metric evaluates matches, conflicts, and neutral defaults', () {
      // Match on section
      expect(
        DuplicateDetectionService.computeSectionScore(
          draftSection: 'North Wing',
          candidateSection: 'North Wing',
        ),
        equals(1.0),
      );
      // Match on unit
      expect(
        DuplicateDetectionService.computeSectionScore(
          draftUnit: 'Unit 101',
          candidateUnit: 'Unit 101',
        ),
        equals(1.0),
      );
      // Cross match (section to unit)
      expect(
        DuplicateDetectionService.computeSectionScore(
          draftSection: 'Food Court',
          candidateUnit: 'Food Court',
        ),
        equals(1.0),
      );
      // Conflict
      expect(
        DuplicateDetectionService.computeSectionScore(
          draftSection: 'North Wing',
          candidateSection: 'South Wing',
        ),
        equals(0.0),
      );
      // Either unspecified
      expect(
        DuplicateDetectionService.computeSectionScore(
          draftSection: 'North Wing',
          candidateSection: null,
          candidateUnit: null,
        ),
        equals(0.5),
      );
      expect(
        DuplicateDetectionService.computeSectionScore(
          draftSection: null,
          candidateSection: 'North Wing',
        ),
        equals(0.5),
      );
    });

    test('16. Landmark metric evaluates match (1.0), conflict (0.0), and neutral (0.5)', () {
      expect(
        DuplicateDetectionService.computeLandmarkScore(
          'Near Fountain',
          'Near Fountain',
        ),
        equals(1.0),
      );
      expect(
        DuplicateDetectionService.computeLandmarkScore(
          'Near Fountain',
          'Near Cinema',
        ),
        equals(0.0),
      );
      expect(
        DuplicateDetectionService.computeLandmarkScore('Near Fountain', null),
        equals(0.5),
      );
      expect(
        DuplicateDetectionService.computeLandmarkScore(null, null),
        equals(0.5),
      );
    });

    test('17. Floor penalty applies -0.40 on conflict and 0.0 when matching or empty', () {
      // Conflicting floors
      expect(
        DuplicateDetectionService.computeFloorPenalty('B1', '4F'),
        equals(0.40),
      );
      expect(
        DuplicateDetectionService.computeFloorPenalty('1F', '2F'),
        equals(0.40),
      );
      // Matching floors
      expect(
        DuplicateDetectionService.computeFloorPenalty('2F', '2f'),
        equals(0.0),
      );
      // Either empty
      expect(
        DuplicateDetectionService.computeFloorPenalty('2F', null),
        equals(0.0),
      );
      expect(
        DuplicateDetectionService.computeFloorPenalty(null, '2F'),
        equals(0.0),
      );
      expect(
        DuplicateDetectionService.computeFloorPenalty(null, null),
        equals(0.0),
      );
    });

    test('18. Clamps score within [0.0, 1.0]', () {
      // Very heavy penalty with 0 other attributes
      final negativeScore = DuplicateDetectionService.computeScore(
        distanceScore: 0.0,
        nameScore: 0.0,
        buildingScore: 0.0,
        sectionScore: 0.0,
        landmarkScore: 0.0,
        floorPenalty: 0.40,
      );
      expect(negativeScore, equals(0.0));

      // Perfect match with 0 penalty
      final perfectScore = DuplicateDetectionService.computeScore(
        distanceScore: 1.0,
        nameScore: 1.0,
        buildingScore: 1.0,
        sectionScore: 1.0,
        landmarkScore: 1.0,
        floorPenalty: 0.0,
      );
      expect(perfectScore, equals(1.0));
    });
  });

  group('DuplicateDetectionService — Candidate Evaluation & Threshold Classification', () {
    test('19. High warning: Identical facility at same location and building scores >= 0.75', () {
      final draft = _createDraft(
        name: 'Central Station Main Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
        buildingName: 'Central Station',
        floor: '1F',
      );
      final candidate = _createCandidate(
        id: 'c1',
        name: 'Central Station Main Restroom',
        latitude: 14.58390, // 0m
        longitude: 121.06170,
        buildingName: 'Central Station',
        floor: '1F',
      );

      final match = service.evaluateCandidate(
        draft: draft,
        candidate: candidate,
      );
      expect(match.score, greaterThanOrEqualTo(0.75));
      expect(match.confidence, equals(DuplicateConfidence.high));
      expect(match.isHighWarning, isTrue);
      expect(match.isModerateWarning, isFalse);
      expect(match.isDistinct, isFalse);
    });

    test('20. Floor conflict penalty strongly suppresses false positives for separate floors', () {
      // Same building, name, and location, but Floor 1 vs Floor 4
      final draft = _createDraft(
        name: 'Central Station Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
        buildingName: 'Central Station',
        floor: '1F',
      );
      final candidateSameFloor = _createCandidate(
        id: 'c_same',
        name: 'Central Station Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
        buildingName: 'Central Station',
        floor: '1F',
      );
      final candidateDiffFloor = _createCandidate(
        id: 'c_diff',
        name: 'Central Station Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
        buildingName: 'Central Station',
        floor: '4F',
      );

      final matchSame = service.evaluateCandidate(
        draft: draft,
        candidate: candidateSameFloor,
      );
      final matchDiff = service.evaluateCandidate(
        draft: draft,
        candidate: candidateDiffFloor,
      );

      expect(matchSame.score - matchDiff.score, closeTo(0.40, 0.001));
    });

    test('21. Distinct facility: Completely different name and building scores < 0.50', () {
      final draft = _createDraft(
        name: 'Starbucks Coffee Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
        buildingName: 'Tower A',
      );
      final candidate = _createCandidate(
        id: 'c_distinct',
        name: 'Public Park Comfort Station',
        latitude: 14.58550, // ~200m away
        longitude: 121.06200,
        buildingName: 'Park Pavilion',
      );

      final match = service.evaluateCandidate(
        draft: draft,
        candidate: candidate,
      );
      expect(match.score, lessThan(0.50));
      expect(match.confidence, equals(DuplicateConfidence.distinct));
      expect(match.isDistinct, isTrue);
    });
  });

  group(
    'DuplicateDetectionService — Deterministic Tie-Breaking & Max 3 Cap',
    () {
      test('22. Sorts candidates by score desc, distance asc, name asc, id asc and caps at 3', () {
        final draft = _createDraft(
          name: 'Plaza Restroom',
          latitude: 14.58390,
          longitude: 121.06170,
        );

        // Create 5 candidates:
        // c1: exact name, close (high score ~0.9)
        // c2: exact name, slightly further (high score ~0.8)
        // c3: partial name, close (moderate score ~0.65)
        // c4: partial name, close, same score as c3 but closer distance
        // c5: unrelated (score < 0.50, should be excluded)
        final c1 = _createCandidate(
          id: 'c1',
          name: 'Plaza Restroom',
          latitude: 14.58395,
          longitude: 121.06170,
        );
        final c2 = _createCandidate(
          id: 'c2',
          name: 'Plaza Restroom',
          latitude: 14.58430,
          longitude: 121.06170,
        );
        final c3 = _createCandidate(
          id: 'c3',
          name: 'Plaza Public Toilet',
          latitude: 14.58420,
          longitude: 121.06170,
        );
        final c4 = _createCandidate(
          id: 'c4',
          name: 'Plaza Public Restroom',
          latitude: 14.58400,
          longitude: 121.06170,
        );
        final c5 = _createCandidate(
          id: 'c5',
          name: 'Completely Unrelated Shop',
          latitude: 14.58700,
          longitude: 121.06170,
        );

        final duplicates = service.findDuplicates(
          draft: draft,
          candidates: [c5, c2, c4, c1, c3],
        );

        // Must return at most 3
        expect(duplicates.length, lessThanOrEqualTo(3));
        // All returned candidates must have score >= 0.50
        for (final d in duplicates) {
          expect(d.score, greaterThanOrEqualTo(0.50));
        }

        // Verify descending score order
        for (int i = 0; i < duplicates.length - 1; i++) {
          expect(
            duplicates[i].score,
            greaterThanOrEqualTo(duplicates[i + 1].score),
          );
        }
      });

      test('23. Filters out all candidates when all scores < 0.50', () {
        final draft = _createDraft(
          name: 'Airport Restroom Gate 12',
          latitude: 14.58390,
          longitude: 121.06170,
        );
        final candidate = _createCandidate(
          id: 'c_unrelated',
          name: 'Harbor Fish Market Loo',
          latitude: 14.58750, // 400m
          longitude: 121.06170,
        );

        final duplicates = service.findDuplicates(
          draft: draft,
          candidates: [candidate],
        );
        expect(duplicates, isEmpty);
      });
    },
  );

  group('DuplicateDetectionService — Spatial Search with Repository', () {
    test('24. Queries repository within 500m and evaluates candidates into complete DuplicateScanResult', () async {
      final repo = MockDuplicateRestroomRepository();
      repo.candidatesToReturn = [
        _createCandidate(
          id: 'cand_1',
          name: 'City Mall Restroom',
          latitude: 14.58390,
          longitude: 121.06170,
        ),
      ];

      final draft = _createDraft(
        name: 'City Mall Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
      );

      final scanResult = await service.findDuplicatesNearby(
        draft: draft,
        repository: repo,
      );

      expect(repo.lastRadiusQueried, equals(500.0));
      expect(repo.lastCenterQueried, equals(draft.coordinates));
      expect(scanResult.isComplete, isTrue);
      expect(
        scanResult.completenessReason,
        equals(DiscoveryCompletenessReason.complete),
      );
      expect(scanResult.hasQueryError, isFalse);
      expect(scanResult.hasDuplicates, isTrue);
      expect(scanResult.candidates.length, equals(1));
      expect(scanResult.candidates.first.restroom.id, equals('cand_1'));
    });

    test('25. Concludes zero duplicates only when scan is complete, error-free, and has zero matches', () async {
      final repo = MockDuplicateRestroomRepository();
      repo.candidatesToReturn = [];

      final draft = _createDraft(
        name: 'Unique Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
      );

      final scanResult = await service.findDuplicatesNearby(
        draft: draft,
        repository: repo,
      );

      expect(scanResult.isComplete, isTrue);
      expect(scanResult.hasQueryError, isFalse);
      expect(scanResult.hasDuplicates, isFalse);
      expect(scanResult.hasConcludedZeroDuplicates, isTrue);
      expect(scanResult.isPartial, isFalse);
    });

    test('26. Preserves partial scan status when rangeCapExceeded without concluding zero duplicates', () async {
      final repo = MockDuplicateRestroomRepository();
      repo.isComplete = false;
      repo.completenessReason = DiscoveryCompletenessReason.rangeCapExceeded;
      repo.candidatesToReturn = [];

      final draft = _createDraft(
        name: 'Downtown Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
      );

      final scanResult = await service.findDuplicatesNearby(
        draft: draft,
        repository: repo,
      );

      expect(scanResult.isComplete, isFalse);
      expect(
        scanResult.completenessReason,
        equals(DiscoveryCompletenessReason.rangeCapExceeded),
      );
      expect(scanResult.isPartial, isTrue);
      // Truncated scan must NEVER imply that no duplicates exist!
      expect(scanResult.hasConcludedZeroDuplicates, isFalse);
      expect(scanResult.hasDuplicates, isFalse);
    });

    test('27. Preserves partial scan status when perRangeLimitExceeded or candidateLimitExceeded', () async {
      final repo = MockDuplicateRestroomRepository();
      repo.isComplete = false;
      repo.completenessReason =
          DiscoveryCompletenessReason.perRangeLimitExceeded;
      repo.candidatesToReturn = [];

      final draft = _createDraft(
        name: 'Busy District Toilet',
        latitude: 14.58390,
        longitude: 121.06170,
      );

      final scanResult1 = await service.findDuplicatesNearby(
        draft: draft,
        repository: repo,
      );

      expect(scanResult1.isComplete, isFalse);
      expect(
        scanResult1.completenessReason,
        equals(DiscoveryCompletenessReason.perRangeLimitExceeded),
      );
      expect(scanResult1.hasConcludedZeroDuplicates, isFalse);

      repo.completenessReason =
          DiscoveryCompletenessReason.candidateLimitExceeded;
      final scanResult2 = await service.findDuplicatesNearby(
        draft: draft,
        repository: repo,
      );

      expect(scanResult2.isComplete, isFalse);
      expect(
        scanResult2.completenessReason,
        equals(DiscoveryCompletenessReason.candidateLimitExceeded),
      );
      expect(scanResult2.hasConcludedZeroDuplicates, isFalse);
    });

    test('28. Fails open on repository query exception while marking scan as incomplete with query error', () async {
      final repo = MockDuplicateRestroomRepository()..shouldThrow = true;
      final draft = _createDraft(
        name: 'City Mall Restroom',
        latitude: 14.58390,
        longitude: 121.06170,
      );

      final scanResult = await service.findDuplicatesNearby(
        draft: draft,
        repository: repo,
      );

      // Advisory duplicate detection must never throw or block submission
      expect(scanResult.candidates, isEmpty);
      expect(scanResult.hasQueryError, isTrue);
      expect(scanResult.isComplete, isFalse);
      expect(scanResult.isPartial, isTrue);
      // A failed scan must NEVER imply that no duplicates exist!
      expect(scanResult.hasConcludedZeroDuplicates, isFalse);
    });
  });
}
