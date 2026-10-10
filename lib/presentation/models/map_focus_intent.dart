import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/restroom.dart';

/// Explicit presentation intent to focus and center the discovery map on a specific
/// restroom facility and optionally open its preview sheet.
class MapFocusIntent extends Equatable {
  final Coordinates coordinates;
  final Restroom? restroom;
  final String? targetRestroomId;
  final String? facilityName;
  final double zoom;
  final bool openPreview;
  final int token;
  final bool forceRefresh;

  const MapFocusIntent({
    required this.coordinates,
    this.restroom,
    this.targetRestroomId,
    this.facilityName,
    this.zoom = AppConstants.defaultZoomLevel,
    this.openPreview = true,
    required this.token,
    this.forceRefresh = false,
  });

  @override
  List<Object?> get props => [
    coordinates,
    restroom?.id,
    targetRestroomId,
    facilityName,
    zoom,
    openPreview,
    token,
    forceRefresh,
  ];
}
