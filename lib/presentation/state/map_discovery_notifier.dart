import 'package:flutter/foundation.dart';

import '../../domain/models/coordinates.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/restroom_repository.dart';

enum DiscoveryStatus { initial, loading, loaded, empty, error }

/// State notifier for map restroom discovery.
class MapDiscoveryNotifier extends ChangeNotifier {
  final RestroomRepository _restroomRepository;

  DiscoveryStatus _status = DiscoveryStatus.initial;
  List<Restroom> _nearbyRestrooms = [];
  Restroom? _selectedRestroom;
  String? _errorMessage;
  String _searchQuery = '';

  MapDiscoveryNotifier({required this._restroomRepository});

  DiscoveryStatus get status => _status;
  List<Restroom> get nearbyRestrooms {
    if (_searchQuery.trim().isEmpty) {
      return _nearbyRestrooms;
    }
    final q = _searchQuery.toLowerCase();
    return _nearbyRestrooms.where((r) {
      return r.name.toLowerCase().contains(q) ||
          (r.buildingName?.toLowerCase().contains(q) ?? false) ||
          (r.landmark?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Restroom? get selectedRestroom => _selectedRestroom;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  bool get isLoading => _status == DiscoveryStatus.loading;
  bool get isEmpty => _status == DiscoveryStatus.empty;
  bool get hasError => _status == DiscoveryStatus.error;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectRestroom(Restroom? restroom) {
    _selectedRestroom = restroom;
    notifyListeners();
  }

  Future<void> loadNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = 1500.0,
  }) async {
    _status = DiscoveryStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final restrooms = await _restroomRepository.getNearbyRestrooms(
        center,
        radiusMeters: radiusMeters,
      );

      _nearbyRestrooms = restrooms;
      if (restrooms.isEmpty) {
        _status = DiscoveryStatus.empty;
        _selectedRestroom = null;
      } else {
        _status = DiscoveryStatus.loaded;
        // Default select the nearest restroom
        _selectedRestroom ??= restrooms.first;
      }
    } catch (e) {
      _status = DiscoveryStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }
}
