import 'package:equatable/equatable.dart';

import 'restroom.dart';

/// Classification thresholds for duplicate candidates per Phase 2 Section 9.4:
/// - HIGH Duplicate Warning: score >= 0.75
/// - MODERATE Duplicate Warning: score >= 0.50
/// - DISTINCT Facility (No Warning): score < 0.50
enum DuplicateConfidence { high, moderate, distinct }

/// Represents an existing [Restroom] evaluated as a potential duplicate
/// of a new contribution draft.
class DuplicateCandidate extends Equatable
    implements Comparable<DuplicateCandidate> {
  final Restroom restroom;
  final double score;
  final double distanceMeters;

  const DuplicateCandidate({
    required this.restroom,
    required this.score,
    required this.distanceMeters,
  });

  /// Confidence classification according to Section 9.4 thresholds.
  DuplicateConfidence get confidence {
    if (score >= 0.75) return DuplicateConfidence.high;
    if (score >= 0.50) return DuplicateConfidence.moderate;
    return DuplicateConfidence.distinct;
  }

  /// Whether this candidate triggers a high duplicate warning (score >= 0.75).
  bool get isHighWarning => confidence == DuplicateConfidence.high;

  /// Whether this candidate triggers a moderate duplicate warning (score >= 0.50).
  bool get isModerateWarning => confidence == DuplicateConfidence.moderate;

  /// Whether this candidate is considered distinct (< 0.50).
  bool get isDistinct => confidence == DuplicateConfidence.distinct;

  @override
  List<Object?> get props => [restroom, score, distanceMeters];

  @override
  int compareTo(DuplicateCandidate other) {
    // 1. score descending
    final scoreCmp = other.score.compareTo(score);
    if (scoreCmp != 0) return scoreCmp;

    // 2. distance ascending
    final distCmp = distanceMeters.compareTo(other.distanceMeters);
    if (distCmp != 0) return distCmp;

    // 3. normalized name ascending
    final nameCmp = restroom.name.toLowerCase().compareTo(
      other.restroom.name.toLowerCase(),
    );
    if (nameCmp != 0) return nameCmp;

    // 4. restroomId ascending
    return restroom.id.compareTo(other.restroom.id);
  }
}
