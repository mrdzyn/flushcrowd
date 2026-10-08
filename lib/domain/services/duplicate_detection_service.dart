import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../data/services/gis/haversine.dart';
import '../models/duplicate_candidate.dart';
import '../models/duplicate_scan_result.dart';
import '../models/restroom.dart';
import '../models/restroom_draft.dart';
import '../repositories/restroom_repository.dart';

/// Bounded Duplicate Detection Engine for Phase 2 Milestone P2.4.
///
/// Implements:
/// - Unicode-preserving text normalization for global scripts (Section 9.2)
/// - Deterministic multi-attribute scoring model (Section 9.3)
/// - Classification thresholds (High >= 0.75, Moderate >= 0.50, Distinct < 0.50) (Section 9.4)
/// - Deterministic tie-breaking and top 3 candidate warnings cap (Section 9.4)
/// - Strictly advisory spatial candidate evaluation (Section 9.1 & 9.5)
class DuplicateDetectionService {
  const DuplicateDetectionService();

  // Strip Unicode punctuation and symbols while preserving letters and numbers across scripts
  static final RegExp _punctuationAndSymbolsRegExp = RegExp(
    r'[\p{P}\p{S}]',
    unicode: true,
  );

  // Match consecutive whitespace
  static final RegExp _whitespaceRegExp = RegExp(r'\s+', unicode: true);

  /// Normalizes input text while preserving letters and numbers in all global scripts
  /// (Japanese, Arabic, Cyrillic, Korean, Chinese, accented Latin, etc.).
  ///
  /// Algorithm:
  /// 1. Trim leading and trailing whitespace.
  /// 2. Lowercase / case-fold where supported.
  /// 3. Canonical Unicode normalization (NFC composed representation).
  /// 4. Strip Unicode punctuation and symbols `[\p{P}\p{S}]` while preserving `[\p{L}\p{N}]`.
  /// 5. Collapse consecutive whitespace into a single space.
  static String normalizeText(String? input) {
    if (input == null) return '';
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    // 1. Lowercase / case-fold
    final lower = trimmed.toLowerCase();

    // 2. Canonical Unicode normalization (NFC)
    final canonical = unorm.nfc(lower);

    // 3. Strip Unicode punctuation and symbols while preserving letters and numbers across scripts
    final stripped = canonical.replaceAll(_punctuationAndSymbolsRegExp, ' ');

    // 4. Collapse consecutive whitespace into a single space
    final collapsed = stripped.replaceAll(_whitespaceRegExp, ' ').trim();
    return collapsed;
  }

  /// Tokenizes normalized text on whitespace into a set of unique non-empty tokens.
  static Set<String> tokenize(String? input) {
    final normalized = normalizeText(input);
    if (normalized.isEmpty) return const {};
    return normalized
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  /// Computes the Dice coefficient between two token sets:
  /// (2 * |T1 ∩ T2|) / (|T1| + |T2|).
  ///
  /// Includes explicit zero-denominator and empty-set guards:
  /// - If both token sets are empty: returns 0.0
  /// - If either token set is empty: returns 0.0
  /// - If (|T1| + |T2| == 0): returns 0.0
  static double diceCoefficient(Set<String> tokens1, Set<String> tokens2) {
    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;
    final totalTokens = tokens1.length + tokens2.length;
    if (totalTokens == 0) return 0.0;

    final intersectionCount = tokens1.intersection(tokens2).length;
    return (2.0 * intersectionCount) / totalTokens;
  }

  /// Evaluates distance similarity score (S_dist) per Section 9.3:
  /// - D < 30m: 1.0
  /// - 30m <= D < 100m: 0.7
  /// - 100m <= D < 300m: 0.3
  /// - 300m <= D <= 500m: 0.1
  /// - > 500m: 0.0
  static double computeDistanceScore(double distanceMeters) {
    if (distanceMeters < 30.0) {
      return 1.0;
    } else if (distanceMeters < 100.0) {
      return 0.7;
    } else if (distanceMeters < 300.0) {
      return 0.3;
    } else if (distanceMeters <= 500.0) {
      return 0.1;
    } else {
      return 0.0;
    }
  }

  /// Evaluates building context similarity score (S_building) per Section 9.3:
  /// - Both non-empty and match: 1.0
  /// - Both non-empty and conflict: 0.0
  /// - Either unspecified/empty: 0.5 (neutral)
  static double computeBuildingScore(
    String? draftBuilding,
    String? candidateBuilding,
  ) {
    final normD = normalizeText(draftBuilding);
    final normC = normalizeText(candidateBuilding);
    if (normD.isEmpty || normC.isEmpty) {
      return 0.5;
    }
    return normD == normC ? 1.0 : 0.0;
  }

  /// Evaluates building section or unit score (S_section) per Section 9.3:
  /// - Match on buildingSection or unitOrArea: 1.0
  /// - Either unspecified: 0.5
  /// - Conflicting: 0.0
  static double computeSectionScore({
    String? draftSection,
    String? draftUnit,
    String? candidateSection,
    String? candidateUnit,
  }) {
    final normDraftSec = normalizeText(draftSection);
    final normDraftUnit = normalizeText(draftUnit);
    final normCandSec = normalizeText(candidateSection);
    final normCandUnit = normalizeText(candidateUnit);

    final hasDraft = normDraftSec.isNotEmpty || normDraftUnit.isNotEmpty;
    final hasCandidate = normCandSec.isNotEmpty || normCandUnit.isNotEmpty;

    if (!hasDraft || !hasCandidate) {
      return 0.5;
    }

    final matches =
        (normDraftSec.isNotEmpty &&
            (normDraftSec == normCandSec || normDraftSec == normCandUnit)) ||
        (normDraftUnit.isNotEmpty &&
            (normDraftUnit == normCandUnit || normDraftUnit == normCandSec));

    return matches ? 1.0 : 0.0;
  }

  /// Evaluates landmark similarity score (S_landmark) per Section 9.3:
  /// - Match on landmark: 1.0
  /// - Either unspecified: 0.5
  /// - Conflicting: 0.0
  static double computeLandmarkScore(
    String? draftLandmark,
    String? candidateLandmark,
  ) {
    final normD = normalizeText(draftLandmark);
    final normC = normalizeText(candidateLandmark);
    if (normD.isEmpty || normC.isEmpty) {
      return 0.5;
    }
    return normD == normC ? 1.0 : 0.0;
  }

  /// Evaluates floor conflict penalty (P_floor) per Section 9.3:
  /// - If both have non-empty normalized floor and they conflict (e.g. "B1" vs "4F"): 0.40
  /// - Otherwise (either empty or both match): 0.0
  static double computeFloorPenalty(
    String? draftFloor,
    String? candidateFloor,
  ) {
    final normD = normalizeText(draftFloor);
    final normC = normalizeText(candidateFloor);
    if (normD.isNotEmpty && normC.isNotEmpty && normD != normC) {
      return 0.40;
    }
    return 0.0;
  }

  /// Computes authoritative raw composite score per Section 9.3 formula:
  /// rawScore = (0.40 * S_dist) + (0.30 * S_name) + (0.15 * S_building)
  ///          + (0.10 * S_section) + (0.05 * S_landmark) - P_floor
  static double computeRawScore({
    required double distanceScore,
    required double nameScore,
    required double buildingScore,
    required double sectionScore,
    required double landmarkScore,
    required double floorPenalty,
  }) {
    return (0.40 * distanceScore) +
        (0.30 * nameScore) +
        (0.15 * buildingScore) +
        (0.10 * sectionScore) +
        (0.05 * landmarkScore) -
        floorPenalty;
  }

  /// Clamps raw score to valid probability range [0.0, 1.0].
  static double computeScore({
    required double distanceScore,
    required double nameScore,
    required double buildingScore,
    required double sectionScore,
    required double landmarkScore,
    required double floorPenalty,
  }) {
    final raw = computeRawScore(
      distanceScore: distanceScore,
      nameScore: nameScore,
      buildingScore: buildingScore,
      sectionScore: sectionScore,
      landmarkScore: landmarkScore,
      floorPenalty: floorPenalty,
    );
    return raw.clamp(0.0, 1.0);
  }

  /// Evaluates a single candidate facility against a contribution draft.
  DuplicateCandidate evaluateCandidate({
    required RestroomDraft draft,
    required Restroom candidate,
  }) {
    final distanceMeters = Haversine.distanceInMeters(
      draft.coordinates,
      candidate.coordinates,
    );

    final distanceScore = computeDistanceScore(distanceMeters);
    final nameScore = diceCoefficient(
      tokenize(draft.name),
      tokenize(candidate.name),
    );
    final buildingScore = computeBuildingScore(
      draft.buildingName,
      candidate.buildingName,
    );
    final sectionScore = computeSectionScore(
      draftSection: draft.buildingSection,
      draftUnit: draft.unitOrArea,
      candidateSection: candidate.buildingSection,
      candidateUnit: candidate.unitOrArea,
    );
    final landmarkScore = computeLandmarkScore(
      draft.landmark,
      candidate.landmark,
    );
    final floorPenalty = computeFloorPenalty(draft.floor, candidate.floor);

    final score = computeScore(
      distanceScore: distanceScore,
      nameScore: nameScore,
      buildingScore: buildingScore,
      sectionScore: sectionScore,
      landmarkScore: landmarkScore,
      floorPenalty: floorPenalty,
    );

    return DuplicateCandidate(
      restroom: candidate,
      score: score,
      distanceMeters: distanceMeters,
    );
  }

  /// Evaluates multiple candidates, filters by score >= 0.50 (Section 9.4),
  /// sorts using deterministic tie-breaking:
  /// 1. score descending
  /// 2. distance ascending
  /// 3. normalized name ascending
  /// 4. restroomId ascending
  ///
  /// Returns at most the top 3 candidates.
  List<DuplicateCandidate> findDuplicates({
    required RestroomDraft draft,
    required List<Restroom> candidates,
  }) {
    final matches = <DuplicateCandidate>[];
    for (final candidate in candidates) {
      final evaluated = evaluateCandidate(draft: draft, candidate: candidate);
      if (evaluated.score >= 0.50) {
        matches.add(evaluated);
      }
    }

    matches.sort((a, b) {
      // 1. score descending
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;

      // 2. distance ascending
      final distCmp = a.distanceMeters.compareTo(b.distanceMeters);
      if (distCmp != 0) return distCmp;

      // 3. normalized name ascending
      final nameA = normalizeText(a.restroom.name);
      final nameB = normalizeText(b.restroom.name);
      final nameCmp = nameA.compareTo(nameB);
      if (nameCmp != 0) return nameCmp;

      // 4. restroomId ascending
      return a.restroom.id.compareTo(b.restroom.id);
    });

    return matches.take(3).toList();
  }

  /// Queries nearby candidates using the bounded spatial query on [repository]
  /// and returns a [DuplicateScanResult] preserving completeness metadata and evaluated candidates.
  ///
  /// Since duplicate detection is strictly advisory, any query failure fails open
  /// returning [DuplicateScanResult.failedOpen] without blocking the contribution workflow.
  Future<DuplicateScanResult> findDuplicatesNearby({
    required RestroomDraft draft,
    required RestroomRepository repository,
    double radiusMeters = 500.0,
  }) async {
    try {
      final discovery = await repository.getDuplicateCandidates(
        draft.coordinates,
        radiusMeters: radiusMeters,
      );
      final evaluated = findDuplicates(
        draft: draft,
        candidates: discovery.items,
      );
      return DuplicateScanResult(
        candidates: evaluated,
        isComplete: discovery.isComplete,
        completenessReason: discovery.completenessReason,
        rangeCount: discovery.rangeCount,
        candidateCount: discovery.candidateCount,
      );
    } catch (e) {
      // Advisory scan: fail open so user is never blocked,
      // but explicitly preserve query failure state.
      return DuplicateScanResult.failedOpen(errorMessage: e.toString());
    }
  }
}
