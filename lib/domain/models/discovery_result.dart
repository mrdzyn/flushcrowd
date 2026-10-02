import 'package:equatable/equatable.dart';

/// Explicit completeness status and metadata for discovery queries.
enum DiscoveryCompletenessReason {
  /// Discovery query completed normally with all matching facilities returned.
  complete,

  /// Full coverage of the query geometry exceeded the maximum allowable query range cap.
  rangeCapExceeded,

  /// A range query document read limit was reached, potentially leaving matching facilities unread.
  perRangeLimitExceeded,

  /// The candidate document budget was exhausted during discovery.
  candidateLimitExceeded,

  /// The maximum discovery result cap was reached; additional results were truncated.
  resultCapExceeded,
}

/// Domain discovery container returning items along with explicit completeness status.
///
/// Prevents truncated or capped query results from silently appearing complete to the UI.
class DiscoveryResult<T> extends Equatable {
  final List<T> items;
  final bool isComplete;
  final DiscoveryCompletenessReason completenessReason;
  final int rangeCount;
  final int candidateCount;

  const DiscoveryResult({
    required this.items,
    this.isComplete = true,
    this.completenessReason = DiscoveryCompletenessReason.complete,
    this.rangeCount = 0,
    this.candidateCount = 0,
  });

  /// Factory constructor for a completely discovered result.
  factory DiscoveryResult.complete({
    required List<T> items,
    int rangeCount = 0,
    int candidateCount = 0,
  }) {
    return DiscoveryResult(
      items: items,
      isComplete: true,
      completenessReason: DiscoveryCompletenessReason.complete,
      rangeCount: rangeCount,
      candidateCount: candidateCount,
    );
  }

  /// Factory constructor for a partially discovered result with an explicit reason.
  factory DiscoveryResult.partial({
    required List<T> items,
    required DiscoveryCompletenessReason reason,
    int rangeCount = 0,
    int candidateCount = 0,
  }) {
    return DiscoveryResult(
      items: items,
      isComplete: false,
      completenessReason: reason,
      rangeCount: rangeCount,
      candidateCount: candidateCount,
    );
  }

  @override
  List<Object?> get props => [
    items,
    isComplete,
    completenessReason,
    rangeCount,
    candidateCount,
  ];

  @override
  String toString() =>
      'DiscoveryResult(items: ${items.length}, isComplete: $isComplete, reason: $completenessReason, ranges: $rangeCount, candidates: $candidateCount)';
}
