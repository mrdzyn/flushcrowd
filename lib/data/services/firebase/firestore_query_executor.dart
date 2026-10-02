import 'package:cloud_firestore/cloud_firestore.dart';

/// Narrow abstraction over Firestore range querying to enable clean,
/// deterministic unit and emulator testing without mocking static methods.
abstract class FirestoreQueryExecutor {
  /// Queries documents in [collectionPath] where the field [field] is between
  /// [startAt] and [endAt], with a maximum limit of [limit] documents.
  Future<List<Map<String, dynamic>>> queryRange({
    required String collectionPath,
    required String field,
    required String startAt,
    required String endAt,
    required int limit,
  });
}

/// Production implementation using standard FirebaseFirestore.
class ProductionFirestoreQueryExecutor implements FirestoreQueryExecutor {
  final FirebaseFirestore? _explicitFirestore;

  ProductionFirestoreQueryExecutor([FirebaseFirestore? firestore])
    : _explicitFirestore = firestore;

  FirebaseFirestore get _firestore =>
      _explicitFirestore ?? FirebaseFirestore.instance;

  @override
  Future<List<Map<String, dynamic>>> queryRange({
    required String collectionPath,
    required String field,
    required String startAt,
    required String endAt,
    required int limit,
  }) async {
    final querySnapshot = await _firestore
        .collection(collectionPath)
        .where(field, isGreaterThanOrEqualTo: startAt)
        .where(field, isLessThanOrEqualTo: endAt)
        .limit(limit)
        .get();

    return querySnapshot.docs.map((doc) {
      final map = Map<String, dynamic>.from(doc.data());
      map['id'] = doc.id;
      return map;
    }).toList();
  }
}
