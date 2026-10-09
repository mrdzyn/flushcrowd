import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/restroom.dart';

/// Explicit presentation intent to focus and center the discovery map on a specific
/// restroom facility and optionally open its preview sheet.
class MapFocusIntent extends Equatable {
  final Restroom restroom;
  final double zoom;
  final bool openPreview;
  final int token;

  const MapFocusIntent({
    required this.restroom,
    this.zoom = AppConstants.defaultZoomLevel,
    this.openPreview = true,
    required this.token,
  });

  @override
  List<Object?> get props => [restroom.id, zoom, openPreview, token];
}
