import 'package:equatable/equatable.dart';

/// Represents a sanitized public rating and review for a restroom.
/// Does NOT contain user UID or contributor identity in public domain representations.
class Rating extends Equatable {
  final String id;
  final String restroomId;
  final double overall;
  final double? cleanliness;
  final double? supplies;
  final double? accessibility;
  final double? privacy;
  final String? comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Rating({
    required this.id,
    required this.restroomId,
    required this.overall,
    this.cleanliness,
    this.supplies,
    this.accessibility,
    this.privacy,
    this.comment,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'restroomId': restroomId,
      'overall': overall,
      'cleanliness': cleanliness,
      'supplies': supplies,
      'accessibility': accessibility,
      'privacy': privacy,
      'comment': comment,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory Rating.fromMap(Map<String, dynamic> map, {String? documentId}) {
    return Rating(
      id: documentId ?? (map['id'] as String? ?? ''),
      restroomId: map['restroomId'] as String? ?? '',
      overall: (map['overall'] as num?)?.toDouble() ?? 0.0,
      cleanliness: (map['cleanliness'] as num?)?.toDouble(),
      supplies: (map['supplies'] as num?)?.toDouble(),
      accessibility: (map['accessibility'] as num?)?.toDouble(),
      privacy: (map['privacy'] as num?)?.toDouble(),
      comment: map['comment'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, restroomId, overall, comment, createdAt];
}
