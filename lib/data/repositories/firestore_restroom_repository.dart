import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../services/firebase/firestore_codec.dart';
import '../services/gis/geohash_service.dart';

/// Cloud Firestore implementation of [RestroomRepository].
///
/// Phase 0 establishes the repository boundary, document operations,
/// and [RestroomFirestoreCodec] integration.
/// Production spatial discovery (geohash candidate expansion and viewport queries)
/// is intentionally deferred to Phase 1.
class FirestoreRestroomRepository implements RestroomRepository {
  final FirebaseFirestore? _firestore;

  FirestoreRestroomRepository({this._firestore});

  CollectionReference<Map<String, dynamic>> get _collection =>
      (_firestore ?? FirebaseFirestore.instance).collection(
        AppConstants.restroomsCollection,
      );

  @override
  Future<List<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    // Phase 1 Scope: Production geohash multi-cell candidate expansion and
    // Firestore spatial range queries are deferred to Phase 1.
    // In Phase 0, use [InMemoryRestroomRepository] for UI testing and preview.
    throw UnsupportedError(
      'Production Firestore spatial discovery is deferred to Phase 1. '
      'Use InMemoryRestroomRepository for Phase 0 UI preview.',
    );
  }

  @override
  Future<List<Restroom>> getViewportRestrooms(GeoBoundingBox bounds) async {
    // Phase 1 Scope: Production viewport bounding queries and clustering
    // are deferred to Phase 1.
    // In Phase 0, use [InMemoryRestroomRepository] for UI testing and preview.
    throw UnsupportedError(
      'Production Firestore viewport discovery is deferred to Phase 1. '
      'Use InMemoryRestroomRepository for Phase 0 UI preview.',
    );
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    final docSnapshot = await _collection.doc(id).get();
    final data = docSnapshot.data();
    if (!docSnapshot.exists || data == null) {
      return null;
    }
    return RestroomFirestoreCodec.fromFirestore(
      data,
      documentId: docSnapshot.id,
    );
  }

  @override
  Future<void> submitRestroom(Restroom restroom) async {
    final data = RestroomFirestoreCodec.toFirestore(restroom);
    // Use server timestamp for creation/update to prevent client clock skew
    data['updatedAt'] = FieldValue.serverTimestamp();
    if (restroom.id.isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await _collection.add(data);
    } else {
      await _collection.doc(restroom.id).set(data, SetOptions(merge: true));
    }
  }
}
