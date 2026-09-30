import 'package:equatable/equatable.dart';

import 'enums.dart';

/// Private report submission for facility issues and moderation.
class RestroomReport extends Equatable {
  final String id;
  final String restroomId;
  final ReportReason reason;
  final String? notes;
  final ReportStatus status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const RestroomReport({
    required this.id,
    required this.restroomId,
    required this.reason,
    this.notes,
    this.status = ReportStatus.pending,
    this.createdAt,
    this.resolvedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'restroomId': restroomId,
      'reason': reason.value,
      'notes': notes,
      'status': status.value,
      'createdAt': createdAt?.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
    };
  }

  factory RestroomReport.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    return RestroomReport(
      id: documentId ?? (map['id'] as String? ?? ''),
      restroomId: map['restroomId'] as String? ?? '',
      reason: ReportReason.fromString(map['reason'] as String?),
      notes: map['notes'] as String?,
      status: ReportStatus.fromString(map['status'] as String?),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      resolvedAt: map['resolvedAt'] != null
          ? DateTime.tryParse(map['resolvedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, restroomId, reason, status, createdAt];
}
