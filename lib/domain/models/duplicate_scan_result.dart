import 'package:equatable/equatable.dart';

import 'discovery_result.dart';
import 'duplicate_candidate.dart';

/// Represents the result of a bounded spatial duplicate scan across geohash ranges,
/// preserving explicit completeness metadata and query failure information.
///
/// Ensures truncated, capped, or failed scans never falsely imply that "no duplicates exist".
class DuplicateScanResult extends Equatable {
  /// Evaluated duplicate candidates (filtered by score >= 0.50, ordered deterministically, max 3).
  final List<DuplicateCandidate> candidates;

  /// Whether the underlying spatial candidate discovery completed without hitting safety limits.
  final bool isComplete;

  /// Explicit reason if the scan was incomplete/truncated.
  final DiscoveryCompletenessReason completenessReason;

  /// Number of geohash ranges queried.
  final int rangeCount;

  /// Number of raw candidate documents retrieved before deduplication and filtering.
  final int candidateCount;

  /// Whether the underlying repository query threw an error (fail-open advisory scan).
  final bool hasQueryError;

  /// Optional diagnostic error message if the query failed.
  final String? errorMessage;

  const DuplicateScanResult({
    required this.candidates,
    this.isComplete = true,
    this.completenessReason = DiscoveryCompletenessReason.complete,
    this.rangeCount = 0,
    this.candidateCount = 0,
    this.hasQueryError = false,
    this.errorMessage,
  });

  /// Factory for a successful, complete duplicate scan.
  factory DuplicateScanResult.complete({
    required List<DuplicateCandidate> candidates,
    int rangeCount = 0,
    int candidateCount = 0,
  }) {
    return DuplicateScanResult(
      candidates: candidates,
      isComplete: true,
      completenessReason: DiscoveryCompletenessReason.complete,
      rangeCount: rangeCount,
      candidateCount: candidateCount,
      hasQueryError: false,
    );
  }

  /// Factory for a partial/truncated scan that hit a safety limit.
  factory DuplicateScanResult.partial({
    required List<DuplicateCandidate> candidates,
    required DiscoveryCompletenessReason reason,
    int rangeCount = 0,
    int candidateCount = 0,
  }) {
    return DuplicateScanResult(
      candidates: candidates,
      isComplete: false,
      completenessReason: reason,
      rangeCount: rangeCount,
      candidateCount: candidateCount,
      hasQueryError: false,
    );
  }

  /// Factory for a failed scan that failed open to avoid blocking contribution.
  factory DuplicateScanResult.failedOpen({String? errorMessage}) {
    return DuplicateScanResult(
      candidates: const [],
      isComplete: false,
      completenessReason: DiscoveryCompletenessReason.rangeCapExceeded,
      hasQueryError: true,
      errorMessage: errorMessage,
    );
  }

  /// Whether any duplicate candidate warning is present.
  bool get hasDuplicates => candidates.isNotEmpty;

  /// Whether the scan was incomplete due to safety caps or a query error.
  bool get isPartial => !isComplete || hasQueryError;

  /// True ONLY when the scan was completely evaluated with 100% geometric/candidate
  /// coverage and zero duplicate candidates were found.
  ///
  /// Invariant: A partial or failed scan NEVER implies "no duplicates exist".
  bool get hasConcludedZeroDuplicates =>
      isComplete && !hasQueryError && candidates.isEmpty;

  @override
  List<Object?> get props => [
    candidates,
    isComplete,
    completenessReason,
    rangeCount,
    candidateCount,
    hasQueryError,
    errorMessage,
  ];
}
