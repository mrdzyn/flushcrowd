import 'package:equatable/equatable.dart';

import '../../domain/models/geo_bounding_box.dart';

/// Value object representing an effective map viewport query.
///
/// Captures ephemeral geometry and zoom buckets to determine whether
/// a subsequent camera idle event represents an effectively identical query,
/// preventing redundant Firestore reads.
class ViewportQueryDescriptor extends Equatable {
  final GeoBoundingBox bounds;
  final double zoom;

  /// Tolerance in degrees for latitude and longitude (~11 meters at equator).
  static const double coordinateToleranceDegrees = 0.0001;

  /// Tolerance for zoom level to avoid re-querying on sub-pixel micro-zooms.
  static const double zoomTolerance = 0.1;

  const ViewportQueryDescriptor({required this.bounds, required this.zoom});

  /// Determines whether [other] is effectively equivalent to this descriptor
  /// within quantized coordinate and zoom tolerances.
  bool isEffectivelyEquivalentTo(ViewportQueryDescriptor other) {
    final zoomDiff = (zoom - other.zoom).abs();
    if (zoomDiff > zoomTolerance) return false;

    final swLatDiff =
        (bounds.southWest.latitude - other.bounds.southWest.latitude).abs();
    final swLngDiff =
        (bounds.southWest.longitude - other.bounds.southWest.longitude).abs();
    final neLatDiff =
        (bounds.northEast.latitude - other.bounds.northEast.latitude).abs();
    final neLngDiff =
        (bounds.northEast.longitude - other.bounds.northEast.longitude).abs();

    return swLatDiff <= coordinateToleranceDegrees &&
        swLngDiff <= coordinateToleranceDegrees &&
        neLatDiff <= coordinateToleranceDegrees &&
        neLngDiff <= coordinateToleranceDegrees;
  }

  @override
  List<Object?> get props => [
    bounds,
    (zoom * 10).round() / 10, // Quantized to 0.1
  ];

  @override
  String toString() =>
      'ViewportQueryDescriptor(bounds: $bounds, zoom: ${zoom.toStringAsFixed(1)})';
}
