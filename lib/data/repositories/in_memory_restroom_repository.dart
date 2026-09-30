import '../../domain/models/coordinates.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../services/gis/geohash_service.dart';
import '../services/gis/haversine.dart';

/// In-memory implementation of RestroomRepository.
/// Useful for unit testing, widget tests, and offline development.
class InMemoryRestroomRepository implements RestroomRepository {
  final List<Restroom> _storage = [];

  InMemoryRestroomRepository({List<Restroom>? initialData}) {
    if (initialData != null) {
      _storage.addAll(initialData);
    } else {
      _seedSampleData();
    }
  }

  void _seedSampleData() {
    // Seed representative sample restrooms from canonical UX reference
    // (e.g. SM Megamall Building A, Ortigas Center)
    final smMegamall = Restroom(
      id: 'restroom_sm_megamall_a',
      name: 'SM Megamall - Building A',
      coordinates: Coordinates(latitude: 14.5843, longitude: 121.0568),
      geohash: GeohashService.encode(
        Coordinates(latitude: 14.5843, longitude: 121.0568),
      ),
      countryCode: 'PH',
      region: 'NCR',
      city: 'Mandaluyong',
      buildingName: 'SM Megamall',
      buildingSection: 'Building A',
      floor: '3F',
      landmark: 'Near Toy Kingdom',
      directionsNote: 'Located at the end of the hallway beside Toy Kingdom. Turn right after the escalator.',
      accessType: AccessType.free,
      male: true,
      female: true,
      allGender: false,
      pwdAccessible: true,
      babyChanging: true,
      hasBidet: true,
      hasToiletPaper: true,
      hasSoap: true,
      hasHandDryer: true,
      averageRating: 4.6,
      ratingCount: 128,
      verificationCount: 42,
      lastVerifiedAt: DateTime.now().subtract(const Duration(days: 2)),
      status: RestroomStatus.active,
      createdAt: DateTime.now().subtract(const Duration(days: 60)),
    );

    final shangriLa = Restroom(
      id: 'restroom_shangri_la',
      name: 'Shangri-La Plaza - Main Wing',
      coordinates: Coordinates(latitude: 14.5818, longitude: 121.0558),
      geohash: GeohashService.encode(
        Coordinates(latitude: 14.5818, longitude: 121.0558),
      ),
      countryCode: 'PH',
      region: 'NCR',
      city: 'Mandaluyong',
      buildingName: 'Shangri-La Plaza',
      buildingSection: 'Main Wing',
      floor: '4F',
      landmark: 'Near Cinema 1',
      directionsNote: 'Beside the ticket booth on the fourth floor.',
      accessType: AccessType.free,
      male: true,
      female: true,
      pwdAccessible: true,
      babyChanging: true,
      hasBidet: true,
      hasToiletPaper: true,
      hasSoap: true,
      averageRating: 4.8,
      ratingCount: 89,
      verificationCount: 30,
      lastVerifiedAt: DateTime.now().subtract(const Duration(days: 1)),
      status: RestroomStatus.active,
      createdAt: DateTime.now().subtract(const Duration(days: 90)),
    );

    final thePodium = Restroom(
      id: 'restroom_the_podium',
      name: 'The Podium - Level 2 Restroom',
      coordinates: Coordinates(latitude: 14.5857, longitude: 121.0592),
      geohash: GeohashService.encode(
        Coordinates(latitude: 14.5857, longitude: 121.0592),
      ),
      countryCode: 'PH',
      region: 'NCR',
      city: 'Mandaluyong',
      buildingName: 'The Podium',
      floor: '2F',
      landmark: 'Across Marketplace',
      directionsNote: 'Next to elevator lobby B.',
      accessType: AccessType.free,
      male: true,
      female: true,
      allGender: true,
      pwdAccessible: true,
      babyChanging: false,
      hasBidet: true,
      hasToiletPaper: true,
      hasSoap: true,
      averageRating: 4.7,
      ratingCount: 65,
      verificationCount: 22,
      lastVerifiedAt: DateTime.now().subtract(const Duration(days: 4)),
      status: RestroomStatus.active,
      createdAt: DateTime.now().subtract(const Duration(days: 45)),
    );

    _storage.addAll([smMegamall, shangriLa, thePodium]);
  }

  @override
  Future<List<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    final results = _storage.where((r) {
      if (r.status != RestroomStatus.active &&
          r.status != RestroomStatus.unverified) {
        return false;
      }
      final dist = Haversine.distanceInMeters(center, r.coordinates);
      return dist <= radiusMeters;
    }).toList();

    // Sort nearest first
    results.sort((a, b) {
      final distA = Haversine.distanceInMeters(center, a.coordinates);
      final distB = Haversine.distanceInMeters(center, b.coordinates);
      return distA.compareTo(distB);
    });

    return results;
  }

  @override
  Future<List<Restroom>> getViewportRestrooms(GeoBoundingBox bounds) async {
    return _storage.where((r) {
      if (r.status != RestroomStatus.active &&
          r.status != RestroomStatus.unverified) {
        return false;
      }
      return bounds.contains(r.coordinates);
    }).toList();
  }

  @override
  Future<Restroom?> getRestroomById(String id) async {
    try {
      return _storage.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> submitRestroom(Restroom restroom) async {
    _storage.removeWhere((r) => r.id == restroom.id);
    _storage.add(restroom);
  }
}
