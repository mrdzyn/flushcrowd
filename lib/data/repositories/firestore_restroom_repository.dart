import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../services/gis/geohash_service.dart';
import '../services/gis/haversine.dart';

/// Cloud Firestore implementation of [RestroomRepository].
/// Encapsulates geohash range queries and exact Haversine distance filtering.
class FirestoreRestroomRepository implements RestroomRepository {
  final FirebaseFirestore _firestore;

  FirestoreRestroomRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(AppConstants.restroomsCollection);

  @override
  Future<List<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    final prefixes = GeohashService.getCandidatePrefixes(center, radiusMeters);
    final List<Restroom> candidates = [];

    for (final prefix in prefixes) {
      final querySnapshot = await _collection
          .where('geohash', isGreaterThanOrEqualTo: prefix)
          .where('geohash', isLessThanOrEqualTo: '$prefix~')
          .limit(100)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final restroom = Restroom.fromMap(data, documentId: doc.id);
        if (restroom.status == RestroomStatus.active ||
            restroom.status == RestroomStatus.unverified) {
          candidates.add(restroom);
        }
      }
    }

    // Exact Haversine distance post-filtering and sorting
    final inRange = candidates.where((r) {
      final distance = Haversine.distanceInMeters(center, r.coordinates);
      return distance <= radiusMeters;
    }).toList();

    inRange.sort((a, b) {
      final distA = Haversine.distanceInMeters(center, a.coordinates);
      final distB = Haversine.distanceInMeters(center, b.coordinates);
      return distA.compareTo(distB);
    });

    return inRange;
  }

  @override
  Future<List<Restroom>> getViewportRestrooms(GeoBoundingBox bounds) async {
    // For viewport discovery, retrieve candidate active listings within bounding box
    final querySnapshot = await _collection
        .where('status', isEqualTo: RestroomStatus.active.value)
        .limit(150)
        .get();

    final List<Restroom> results = [];
    for (final doc in querySnapshot.docs) {
      final restroom = Restroom.fromMap(doc.data(), documentId: doc.id);
      if (bounds.contains(restroom.coordinates)) {
        results.add(restroom);
      }
    }
    return results;
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    final docSnapshot = await _collection.doc(id).get();
    if (!docSnapshot.exists || docSnapshot.data() == null) {
      return null;
    }
    return Restroom.fromMap(docSnapshot.data()!, documentId: docSnapshot.id);
  }

  @override
  Future<void> submitRestroom(Restroom restroom) async {
    final data = restroom.toMap();
    // Use server timestamp for creation/update
    data['updatedAt'] = FieldValue.serverTimestamp();
    if (restroom.id.isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await _collection.add(data);
    } else {
      await _collection.doc(restroom.id).set(data, SetOptions(merge: true));
    }
  }
}
