import 'package:equatable/equatable.dart';

import 'enums.dart';

/// Sanitized community verification event.
/// Excludes private contributor UID.
class Verification extends Equatable {
  final String id;
  final String restroomId;
  final VerificationResult result;
  final DateTime? createdAt;

  const Verification({
    required this.id,
    required this.restroomId,
    required this.result,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'restroomId': restroomId,
      'result': result.value,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory Verification.fromMap(Map<String, dynamic> map, {String? documentId}) {
    return Verification(
      id: documentId ?? (map['id'] as String? ?? ''),
      restroomId: map['restroomId'] as String? ?? '',
      result: VerificationResult.fromString(map['result'] as String?),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, restroomId, result, createdAt];
}
