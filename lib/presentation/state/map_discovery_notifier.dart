import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/discovery_result.dart';
import '../../domain/models/geo_bounding_box.dart';
import '../../domain/models/restroom.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../models/restroom_marker_item.dart';
import 'viewport_query_descriptor.dart';

/// Discovery lifecycle status for map querying.
enum DiscoveryStatus {
  /// Initial idle state before first discovery query.
  initial,

  /// Actively querying Firestore for nearby or viewport facilities.
  loading,

  /// Successfully discovered results with 100% geometric and candidate completeness.
  loadedComplete,

  /// Discovered results, but results are partial/degraded due to a safety cap
  /// (e.g. rangeCapExceeded, perRangeLimitExceeded, candidateLimitExceeded, resultCapExceeded).
  loadedDegraded,

  /// Discovered zero facilities in the visible area.
  empty,

  /// Map camera zoom is below minimum or viewport is oversized; query intentionally suppressed.
  suppressed,

  /// Discovery operation encountered an unhandled repository error.
  error,
}

/// Primary application state notifier for map restroom discovery.
///
/// Implements P1.2 Query Orchestration:
/// - Single owner of camera-idle debounce (configurable, default 400ms)
/// - Viewport query equivalence / quantization to prevent duplicate reads
/// - Monotonically increasing request generation token for stale/superseded response protection
/// - Zoom/oversized viewport suppression (zoom < minViewportZoom or ViewportTooLargeException)
/// - Explicit propagation of DiscoveryResult completeness metadata
/// - Restroom marker mapping with stable identity and selection state
class MapDiscoveryNotifier extends ChangeNotifier {
  final RestroomRepository restroomRepository;
  final Duration debounceDuration;

  DiscoveryStatus _status = DiscoveryStatus.initial;
  List<Restroom> _discoveredRestrooms = [];
  Restroom? _selectedRestroom;
  String? _errorMessage;
  String _searchQuery = '';

  // Metadata propagation
  bool _isComplete = true;
  DiscoveryCompletenessReason _completenessReason =
      DiscoveryCompletenessReason.complete;
  int _rangeCount = 0;
  int _candidateCount = 0;

  // Ephemeral query orchestration state
  Timer? _debounceTimer;
  int _activeRequestToken = 0;
  ViewportQueryDescriptor? _lastExecutedDescriptor;
  bool _isDisposed = false;
  bool _selectionIsUserInitiated = false;

  MapDiscoveryNotifier({
    required this.restroomRepository,
    this.debounceDuration = AppConstants.cameraIdleDebounceDuration,
  });

  DiscoveryStatus get status => _status;
  List<Restroom> get discoveredRestrooms => _discoveredRestrooms;
  Restroom? get selectedRestroom => _selectedRestroom;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  bool get isComplete => _isComplete;
  DiscoveryCompletenessReason get completenessReason => _completenessReason;
  int get rangeCount => _rangeCount;
  int get candidateCount => _candidateCount;
  ViewportQueryDescriptor? get lastExecutedDescriptor =>
      _lastExecutedDescriptor;
  bool get selectionIsUserInitiated => _selectionIsUserInitiated;

  bool get isLoading => _status == DiscoveryStatus.loading;
  bool get isEmpty => _status == DiscoveryStatus.empty;
  bool get hasError => _status == DiscoveryStatus.error;
  bool get isSuppressed => _status == DiscoveryStatus.suppressed;
  bool get isDegraded => _status == DiscoveryStatus.loadedDegraded;

  /// Discovered restrooms filtered by in-memory search query.
  List<Restroom> get nearbyRestrooms {
    if (_searchQuery.trim().isEmpty) {
      return _discoveredRestrooms;
    }
    final q = _searchQuery.toLowerCase();
    return _discoveredRestrooms.where((r) {
      return r.name.toLowerCase().contains(q) ||
          (r.buildingName?.toLowerCase().contains(q) ?? false) ||
          (r.landmark?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// Presentation marker items derived from current restrooms and selection state.
  List<RestroomMarkerItem> get markerItems {
    final selectedId = _selectedRestroom?.id;
    return nearbyRestrooms.map((r) {
      return RestroomMarkerItem.fromRestroom(r, isSelected: r.id == selectedId);
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Sets selected restroom as an explicit user-initiated action.
  void selectRestroom(Restroom? restroom) {
    _selectedRestroom = restroom;
    _selectionIsUserInitiated = restroom != null;
    notifyListeners();
  }

  /// Sets selected restroom programmatically (e.g. initial auto-selection).
  void autoSelectRestroom(Restroom? restroom) {
    _selectedRestroom = restroom;
    _selectionIsUserInitiated = false;
    notifyListeners();
  }

  /// Explicitly invalidates any in-flight asynchronous query generation.
  /// Any later completions holding an older token will be safely discarded.
  void _invalidateActiveRequest() {
    _activeRequestToken++;
  }

  /// Called when the map camera begins moving.
  /// Cancels any pending debounce timer and immediately invalidates any in-flight
  /// query so that stale responses cannot commit to the moved map.
  void onCameraMoveStarted() {
    _cancelDebounce();
    _invalidateActiveRequest();
  }

  /// Called during camera movement. Explicitly does NOT trigger any queries.
  void onCameraMove() {
    // Zero-query guard: camera movement frame updates never query Firestore.
  }

  /// Called when map camera becomes idle at a given [bounds] and [zoom].
  ///
  /// Orchestrates debounce, zoom validation, query equivalence, and execution.
  void onCameraIdle({required GeoBoundingBox bounds, required double zoom}) {
    _cancelDebounce();

    if (_isDisposed) return;

    // Immediately handle zoom suppression synchronously so in-flight requests are
    // invalidated without waiting for debounce expiration.
    if (zoom < AppConstants.minViewportZoom) {
      _invalidateActiveRequest();
      _status = DiscoveryStatus.suppressed;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _debounceTimer = Timer(debounceDuration, () {
      if (_isDisposed) return;
      _orchestrateViewportQuery(bounds: bounds, zoom: zoom);
    });
  }

  /// Orchestrates the actual viewport query after debounce.
  Future<void> _orchestrateViewportQuery({
    required GeoBoundingBox bounds,
    required double zoom,
    bool forceRefresh = false,
  }) async {
    // 1. Zoom threshold check: below minViewportZoom, suppress discovery
    // and invalidate any prior in-flight request so it cannot commit later.
    if (zoom < AppConstants.minViewportZoom) {
      _invalidateActiveRequest();
      _status = DiscoveryStatus.suppressed;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    final descriptor = ViewportQueryDescriptor(bounds: bounds, zoom: zoom);

    // 2. Query equivalence check: avoid redundant query if bounds/zoom are effectively identical
    if (!forceRefresh &&
        _lastExecutedDescriptor != null &&
        _lastExecutedDescriptor!.isEffectivelyEquivalentTo(descriptor)) {
      return;
    }

    // 3. Increment request token for stale response protection
    final requestToken = ++_activeRequestToken;

    _status = DiscoveryStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await restroomRepository.getViewportRestrooms(bounds);

      // 4. Stale response check: reject if a newer request was issued,
      // request was invalidated (e.g. by camera movement or suppression), or notifier disposed
      if (_isDisposed || requestToken != _activeRequestToken) {
        return;
      }

      _lastExecutedDescriptor = descriptor;
      _commitDiscoveryResult(result);
    } on ViewportTooLargeException {
      if (_isDisposed || requestToken != _activeRequestToken) return;
      // ViewportTooLargeException is handled as intentional query suppression
      _invalidateActiveRequest();
      _status = DiscoveryStatus.suppressed;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      if (_isDisposed || requestToken != _activeRequestToken) return;
      _status = DiscoveryStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Loads nearby restrooms explicitly (e.g. for initial load, recenter on user, or retry).
  Future<void> loadNearbyRestrooms(
    Coordinates center, {
    double radiusMeters = AppConstants.defaultSearchRadiusMeters,
    bool forceRefresh = false,
  }) async {
    _cancelDebounce();

    final requestToken = ++_activeRequestToken;

    _status = DiscoveryStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await restroomRepository.getNearbyRestrooms(
        center,
        radiusMeters: radiusMeters,
      );

      if (_isDisposed || requestToken != _activeRequestToken) {
        return;
      }

      _commitDiscoveryResult(result);
    } catch (e) {
      if (_isDisposed || requestToken != _activeRequestToken) return;
      _status = DiscoveryStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Explicit refresh / retry hook.
  Future<void> refreshCurrentViewport({
    required GeoBoundingBox bounds,
    required double zoom,
  }) async {
    _cancelDebounce();
    await _orchestrateViewportQuery(
      bounds: bounds,
      zoom: zoom,
      forceRefresh: true,
    );
  }

  /// Commits a successful discovery result into notifier state.
  void _commitDiscoveryResult(DiscoveryResult<Restroom> result) {
    _discoveredRestrooms = result.items;
    _isComplete = result.isComplete;
    _completenessReason = result.completenessReason;
    _rangeCount = result.rangeCount;
    _candidateCount = result.candidateCount;

    if (result.items.isEmpty) {
      _status = DiscoveryStatus.empty;
      _selectedRestroom = null;
      _selectionIsUserInitiated = false;
    } else {
      _status = result.isComplete
          ? DiscoveryStatus.loadedComplete
          : DiscoveryStatus.loadedDegraded;

      // Selection lifecycle enforcement:
      // 1. If currently selected restroom survives in new results: preserve it.
      // 2. If user-selected restroom no longer exists: clear selection (do NOT silently jump to another).
      // 3. If there was no user selection (or initial load) and product UX expects a default card:
      //    auto-select first result.
      if (_selectedRestroom != null) {
        final matchingIndex = result.items.indexWhere(
          (r) => r.id == _selectedRestroom!.id,
        );
        if (matchingIndex != -1) {
          // Update selected reference to refreshed model
          _selectedRestroom = result.items[matchingIndex];
        } else {
          // Vanished restroom: clear selection completely
          _selectedRestroom = null;
          _selectionIsUserInitiated = false;
        }
      } else if (!_selectionIsUserInitiated) {
        // Initial automatic nearest selection
        _selectedRestroom = result.items.first;
      }
    }
    notifyListeners();
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelDebounce();
    super.dispose();
  }
}
