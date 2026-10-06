import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/discovery_result.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/geo_bounding_box.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../services/gis/geohash_service.dart';
import '../services/gis/haversine.dart';

/// In-memory implementation of RestroomRepository.
/// Useful for unit testing, widget tests, and offline development.
class InMemoryRestroomRepository implements RestroomRepository {
  final List<Restroom> _storage = [];
  final Map<String, Map<String, dynamic>> _contributions = {};
  final AuthRepository? authRepository;

  InMemoryRestroomRepository({
    List<Restroom>? initialData,
    Map<String, Map<String, dynamic>>? initialContributions,
    this.authRepository,
  }) {
    if (initialData != null) {
      _storage.addAll(initialData);
    } else {
      _seedSampleData();
    }
    if (initialContributions != null) {
      _contributions.addAll(initialContributions);
    }
  }

  List<Restroom> get storage => List.unmodifiable(_storage);
  Map<String, Map<String, dynamic>> get contributions =>
      Map.unmodifiable(_contributions);

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
  Future<DiscoveryResult<Restroom>> getNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = AppConstants.defaultSearchRadiusMeters,
  }) async {
    if (radiusMeters <= 0 ||
        radiusMeters.isNaN ||
        radiusMeters > AppConstants.maxSearchRadiusMeters) {
      throw InvalidRadiusException(
        'Search radius must be positive and not exceed ${AppConstants.maxSearchRadiusMeters} meters. Received: $radiusMeters',
      );
    }

    final results = _storage.where((r) {
      if (r.status != RestroomStatus.active &&
          r.status != RestroomStatus.unverified) {
        return false;
      }
      final dist = Haversine.distanceInMeters(center, r.coordinates);
      return dist <= radiusMeters;
    }).toList();

    // Sort nearest first, then by ID
    results.sort((a, b) {
      final distA = Haversine.distanceInMeters(center, a.coordinates);
      final distB = Haversine.distanceInMeters(center, b.coordinates);
      final cmp = distA.compareTo(distB);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });

    List<Restroom> finalResults = results;
    bool resultCapHit = false;
    if (results.length > AppConstants.maxDiscoveryResults) {
      resultCapHit = true;
      finalResults = results.sublist(0, AppConstants.maxDiscoveryResults);
    }

    return DiscoveryResult(
      items: finalResults,
      isComplete: !resultCapHit,
      completenessReason: resultCapHit
          ? DiscoveryCompletenessReason.resultCapExceeded
          : DiscoveryCompletenessReason.complete,
      rangeCount: 1,
      candidateCount: results.length,
    );
  }

  @override
  Future<DiscoveryResult<Restroom>> getViewportRestrooms(
    GeoBoundingBox bounds,
  ) async {
    final latSpan = bounds.latitudeSpan;
    final lngSpan = bounds.longitudeSpan;

    if (latSpan > AppConstants.maxViewportLatitudeSpan ||
        lngSpan > AppConstants.maxViewportLongitudeSpan) {
      throw const ViewportTooLargeException(
        'Visible area exceeds safety bounds. Zoom in to discover restrooms.',
      );
    }

    final results = _storage.where((r) {
      if (r.status != RestroomStatus.active &&
          r.status != RestroomStatus.unverified) {
        return false;
      }
      return bounds.contains(r.coordinates);
    }).toList();

    results.sort((a, b) => a.id.compareTo(b.id));

    List<Restroom> finalResults = results;
    bool resultCapHit = false;
    if (results.length > AppConstants.maxDiscoveryResults) {
      resultCapHit = true;
      finalResults = results.sublist(0, AppConstants.maxDiscoveryResults);
    }

    return DiscoveryResult(
      items: finalResults,
      isComplete: !resultCapHit,
      completenessReason: resultCapHit
          ? DiscoveryCompletenessReason.resultCapExceeded
          : DiscoveryCompletenessReason.complete,
      rangeCount: 1,
      candidateCount: results.length,
    );
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
  Future<Restroom> submitRestroom(CreateRestroomCommand command) async {
    if (authRepository != null && authRepository!.currentUserId == null) {
      throw const UnauthenticatedException();
    }
    final uid = authRepository?.currentUserId ?? 'mock_uid_123';

    final normalized = command.draft.normalized();
    final errors = normalized.validate();
    if (errors.isNotEmpty) {
      throw RepositoryException(
        'Cannot submit invalid restroom draft: ${errors.join(', ')}',
        'invalid-draft',
      );
    }

    final existingRestroomIndex = _storage.indexWhere(
      (r) => r.id == command.restroomId,
    );
    final existingContribution =
        _contributions['restroom_${command.restroomId}'];

    // Ambiguous commit reconciliation logic
    if (existingRestroomIndex != -1 && existingContribution != null) {
      return _storage[existingRestroomIndex];
    } else if (existingRestroomIndex != -1 || existingContribution != null) {
      throw const SubmissionInvariantException(
        'Invariant violation: only one document of the atomic restroom pair exists.',
      );
    }

    final geohash = GeohashService.encode(normalized.coordinates);
    final now = DateTime.now();

    final restroom = Restroom(
      id: command.restroomId,
      name: normalized.name,
      coordinates: normalized.coordinates,
      geohash: geohash,
      countryCode: normalized.countryCode,
      region: normalized.region,
      city: normalized.city,
      buildingName: normalized.buildingName,
      buildingSection: normalized.buildingSection,
      floor: normalized.floor,
      unitOrArea: normalized.unitOrArea,
      landmark: normalized.landmark,
      directionsNote: normalized.directionsNote,
      accessInstructions: normalized.accessInstructions,
      accessType: normalized.accessType,
      feeAmount: normalized.feeAmount,
      feeCurrency: normalized.feeCurrency,
      male: normalized.male,
      female: normalized.female,
      allGender: normalized.allGender,
      pwdAccessible: normalized.pwdAccessible.toNullableBool(),
      babyChanging: normalized.babyChanging.toNullableBool(),
      hasBidet: normalized.hasBidet.toNullableBool(),
      hasToiletPaper: normalized.hasToiletPaper.toNullableBool(),
      hasSoap: normalized.hasSoap.toNullableBool(),
      hasHandDryer: normalized.hasHandDryer.toNullableBool(),
      averageRating: 0.0,
      ratingCount: 0,
      verificationCount: 0,
      negativeVerificationCount: 0,
      lastVerifiedAt: null,
      status: RestroomStatus.unverified,
      createdAt: now,
      updatedAt: now,
    );

    _storage.add(restroom);
    _contributions['restroom_${command.restroomId}'] = {
      'id': 'restroom_${command.restroomId}',
      'contributionType': 'restroom',
      'resourceId': command.restroomId,
      'restroomId': command.restroomId,
      'userUid': uid,
      'moderationState': 'pending',
      'createdAt': now,
      'updatedAt': now,
    };

    return restroom;
  }
}
