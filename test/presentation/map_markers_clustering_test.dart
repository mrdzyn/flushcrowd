import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/discovery_result.dart';
import 'package:looradar/domain/models/restroom.dart';
import 'package:looradar/presentation/components/map/map_marker_adapter.dart';
import 'package:looradar/presentation/models/restroom_marker_item.dart';
import 'package:looradar/presentation/state/map_discovery_notifier.dart';

import 'map_discovery_notifier_test.dart';

void main() {
  group('Map Markers and Clustering Adapter', () {
    test(
      'adapts restroom models to markers with stable ID and coordinates',
      () {
        final restroom1 = Restroom(
          id: 'rr_1',
          name: 'Restroom One',
          coordinates: Coordinates(latitude: 14.5843, longitude: 121.0568),
          geohash: 'wdw4fq',
          floor: '2F',
          averageRating: 4.5,
        );
        final restroom2 = Restroom(
          id: 'rr_2',
          name: 'Restroom Two',
          coordinates: Coordinates(latitude: 14.5850, longitude: 121.0575),
          geohash: 'wdw4fr',
        );

        final items = [
          RestroomMarkerItem.fromRestroom(restroom1, isSelected: false),
          RestroomMarkerItem.fromRestroom(restroom2, isSelected: true),
        ];

        final markers = MapMarkerAdapter.adaptMarkers(
          items: items,
          onMarkerTap: (_) {},
        );

        expect(markers.length, 2);

        final marker1 = markers.firstWhere((m) => m.markerId.value == 'rr_1');
        expect(marker1.position.latitude, 14.5843);
        expect(marker1.position.longitude, 121.0568);
        expect(marker1.infoWindow.title, 'Restroom One');
        expect(marker1.infoWindow.snippet, '2F · Rating: 4.5');
        expect(
          marker1.clusterManagerId?.value,
          MapMarkerAdapter.restroomClusterManagerId,
        );

        final marker2 = markers.firstWhere((m) => m.markerId.value == 'rr_2');
        expect(marker2.position.latitude, 14.5850);
        expect(marker2.position.longitude, 121.0575);
        expect(marker2.infoWindow.snippet, null);
      },
    );

    test('marker tap triggers selection callback with restroom ID', () {
      String? tappedId;
      final item = RestroomMarkerItem(
        id: 'rr_target',
        coordinates: Coordinates(latitude: 14.5843, longitude: 121.0568),
        name: 'Target Restroom',
      );

      final markers = MapMarkerAdapter.adaptMarkers(
        items: [item],
        onMarkerTap: (id) => tappedId = id,
      );

      expect(markers.length, 1);
      final marker = markers.first;
      marker.onTap?.call();
      expect(tappedId, 'rr_target');
    });

    test('cluster manager expands cluster region without arbitrarily selecting a restroom', () {
      bool clusterTapped = false;
      Cluster? capturedCluster;

      final clusterManager = MapMarkerAdapter.buildClusterManager(
        onClusterTap: (cluster) {
          clusterTapped = true;
          capturedCluster = cluster;
        },
      );

      expect(
        clusterManager.clusterManagerId.value,
        MapMarkerAdapter.restroomClusterManagerId,
      );

      final fakeCluster = Cluster(
        const ClusterManagerId(MapMarkerAdapter.restroomClusterManagerId),
        const [
          MarkerId('rr_1'),
          MarkerId('rr_2'),
          MarkerId('rr_3'),
          MarkerId('rr_4'),
          MarkerId('rr_5'),
        ],
        position: const LatLng(14.5840, 121.0560),
        bounds: LatLngBounds(
          southwest: const LatLng(14.5830, 121.0550),
          northeast: const LatLng(14.5850, 121.0570),
        ),
      );

      clusterManager.onClusterTap?.call(fakeCluster);
      expect(clusterTapped, isTrue);
      expect(capturedCluster?.count, 5);
      expect(capturedCluster?.markerIds.length, 5);
    });

    test('marker items in MapDiscoveryNotifier reflect selected state and update on selection', () async {
      final fakeRepo = FakeRestroomRepository();
      final notifier = MapDiscoveryNotifier(restroomRepository: fakeRepo);

      final r1 = Restroom(
        id: 'rr_1',
        name: 'Restroom One',
        coordinates: Coordinates(latitude: 14.5843, longitude: 121.0568),
        geohash: 'wdw4fq',
      );
      final r2 = Restroom(
        id: 'rr_2',
        name: 'Restroom Two',
        coordinates: Coordinates(latitude: 14.5850, longitude: 121.0575),
        geohash: 'wdw4fr',
      );

      fakeRepo.nearbyResultToReturn = DiscoveryResult.complete(items: [r1, r2]);
      await notifier.loadNearbyRestrooms(
        Coordinates(latitude: 14.5840, longitude: 121.0560),
      );

      expect(notifier.markerItems.length, 2);
      expect(
        notifier.markerItems.firstWhere((m) => m.id == 'rr_1').isSelected,
        isTrue,
      );
      expect(
        notifier.markerItems.firstWhere((m) => m.id == 'rr_2').isSelected,
        isFalse,
      );

      notifier.selectRestroom(r2);
      expect(
        notifier.markerItems.firstWhere((m) => m.id == 'rr_1').isSelected,
        isFalse,
      );
      expect(
        notifier.markerItems.firstWhere((m) => m.id == 'rr_2').isSelected,
        isTrue,
      );
    });

    test('stable marker identity: duplicate restroom IDs do not create duplicate markers', () {
      final item1 = RestroomMarkerItem(
        id: 'rr_duplicate',
        coordinates: Coordinates(latitude: 14.5843, longitude: 121.0568),
        name: 'Restroom Dup',
      );
      final item2 = RestroomMarkerItem(
        id: 'rr_duplicate',
        coordinates: Coordinates(latitude: 14.5843, longitude: 121.0568),
        name: 'Restroom Dup',
      );

      final markers = MapMarkerAdapter.adaptMarkers(
        items: [item1, item2],
        onMarkerTap: (_) {},
      );

      // Set deduplicates markers by markerId
      expect(markers.length, 1);
    });
  });
}
