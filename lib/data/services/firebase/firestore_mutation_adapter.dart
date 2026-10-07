import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';

/// Represents a raw document retrieved from Cloud Firestore during point reads,
/// preserving the [documentId] and the raw [data] payload without mutating the payload map.
class FirestoreDocumentData {
  final String documentId;
  final Map<String, dynamic> data;

  const FirestoreDocumentData({required this.documentId, required this.data});
}

/// Narrow abstraction over Firestore batch mutation and point-read execution
/// to enable clean, deterministic testing of production submission and reconciliation
/// without mocking static methods or requiring emulator infrastructure for simple unit runs.
abstract class FirestoreMutationAdapter {
  /// Commits a pair of public restroom and private contribution documents
  /// atomically in a single write batch.
  Future<void> commitRestroomSubmissionBatch({
    required String restroomId,
    required Map<String, dynamic> publicData,
    required String contributionId,
    required Map<String, dynamic> contributionData,
  });

  /// Reads a public restroom document by its ID, or returns null if not found.
  Future<FirestoreDocumentData?> getPublicRestroom(String restroomId);

  /// Reads a private contribution document by its ID, or returns null if not found.
  Future<FirestoreDocumentData?> getPrivateContribution(String contributionId);
}

/// Production implementation using standard FirebaseFirestore.
class ProductionFirestoreMutationAdapter implements FirestoreMutationAdapter {
  final FirebaseFirestore? _explicitFirestore;

  ProductionFirestoreMutationAdapter([FirebaseFirestore? firestore])
    : _explicitFirestore = firestore;

  FirebaseFirestore get _firestore =>
      _explicitFirestore ?? FirebaseFirestore.instance;

  @override
  Future<void> commitRestroomSubmissionBatch({
    required String restroomId,
    required Map<String, dynamic> publicData,
    required String contributionId,
    required Map<String, dynamic> contributionData,
  }) async {
    final batch = _firestore.batch();
    final restroomRef = _firestore
        .collection(AppConstants.restroomsCollection)
        .doc(restroomId);
    final contributionRef = _firestore
        .collection('contributions')
        .doc(contributionId);

    batch.set(restroomRef, publicData);
    batch.set(contributionRef, contributionData);

    await batch.commit();
  }

  @override
  Future<FirestoreDocumentData?> getPublicRestroom(String restroomId) async {
    final docSnapshot = await _firestore
        .collection(AppConstants.restroomsCollection)
        .doc(restroomId)
        .get();
    final data = docSnapshot.data();
    if (!docSnapshot.exists || data == null) {
      return null;
    }
    return FirestoreDocumentData(
      documentId: docSnapshot.id,
      data: Map<String, dynamic>.from(data),
    );
  }

  @override
  Future<FirestoreDocumentData?> getPrivateContribution(
    String contributionId,
  ) async {
    final docSnapshot = await _firestore
        .collection('contributions')
        .doc(contributionId)
        .get();
    final data = docSnapshot.data();
    if (!docSnapshot.exists || data == null) {
      return null;
    }
    return FirestoreDocumentData(
      documentId: docSnapshot.id,
      data: Map<String, dynamic>.from(data),
    );
  }
}
