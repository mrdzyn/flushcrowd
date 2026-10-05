import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/restroom_marker_item.dart';

/// Adapts presentation [RestroomMarkerItem]s to Google Maps [Marker] and [ClusterManager] objects.
///
/// Ensures:
/// - One marker per restroom ID with stable identity
/// - Visual differentiation for selected markers
/// - Standard integration with Google Maps native marker clustering via [ClusterManager]
/// - Cluster tap expands the camera without arbitrarily selecting an individual restroom
class MapMarkerAdapter {
  MapMarkerAdapter._();

  static const String restroomClusterManagerId = 'restrooms_cluster_manager';

  /// Builds a [ClusterManager] configured for restroom markers.
  static ClusterManager buildClusterManager({
    required void Function(Cluster cluster) onClusterTap,
  }) {
    return ClusterManager(
      clusterManagerId: const ClusterManagerId(restroomClusterManagerId),
      onClusterTap: onClusterTap,
    );
  }

  /// Adapts a list of [RestroomMarkerItem]s into a Set of Google Maps [Marker]s.
  ///
  /// Each marker is associated with the given [clusterManagerId] (if enabled).
  static Set<Marker> adaptMarkers({
    required List<RestroomMarkerItem> items,
    required void Function(String restroomId) onMarkerTap,
    ClusterManagerId? clusterManagerId = const ClusterManagerId(
      restroomClusterManagerId,
    ),
  }) {
    final markerMap = <MarkerId, Marker>{};

    for (final item in items) {
      final markerId = MarkerId(item.id);
      if (markerMap.containsKey(markerId)) {
        continue; // Strictly enforce stable 1:1 marker per restroom ID
      }
      markerMap[markerId] = Marker(
        markerId: markerId,
        clusterManagerId: clusterManagerId,
        position: LatLng(item.coordinates.latitude, item.coordinates.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          item.isSelected
              ? BitmapDescriptor.hueAzure
              : BitmapDescriptor.hueBlue,
        ),
        infoWindow: InfoWindow(
          title: item.name,
          snippet: item.floor != null
              ? '${item.floor} · Rating: ${item.averageRating ?? "-"}'
              : null,
        ),
        onTap: () => onMarkerTap(item.id),
      );
    }

    return markerMap.values.toSet();
  }
}
