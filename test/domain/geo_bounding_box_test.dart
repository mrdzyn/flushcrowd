import 'package:flutter_test/flutter_test.dart';
import 'package:looradar/domain/models/coordinates.dart';
import 'package:looradar/domain/models/geo_bounding_box.dart';

void main() {
  group('GeoBoundingBox Model & Antimeridian Support', () {
    test('normal viewport correctly checks containment', () {
      final box = GeoBoundingBox(
        southWest: Coordinates(latitude: 10.0, longitude: 20.0),
        northEast: Coordinates(latitude: 15.0, longitude: 25.0),
      );

      expect(box.crossesAntimeridian, isFalse);
      expect(box.latitudeSpan, 5.0);
      expect(box.longitudeSpan, 5.0);

      // Inside point
      expect(
        box.contains(Coordinates(latitude: 12.0, longitude: 22.0)),
        isTrue,
      );

      // Outside latitude
      expect(
        box.contains(Coordinates(latitude: 9.0, longitude: 22.0)),
        isFalse,
      );
      expect(
        box.contains(Coordinates(latitude: 16.0, longitude: 22.0)),
        isFalse,
      );

      // Outside longitude
      expect(
        box.contains(Coordinates(latitude: 12.0, longitude: 19.0)),
        isFalse,
      );
      expect(
        box.contains(Coordinates(latitude: 12.0, longitude: 26.0)),
        isFalse,
      );
    });

    test('antimeridian-crossing viewport correctly checks containment', () {
      // Viewport crossing 180° / -180° meridian: from 170°E to -170°W (190°E)
      final crossingBox = GeoBoundingBox(
        southWest: Coordinates(latitude: -20.0, longitude: 170.0),
        northEast: Coordinates(latitude: -10.0, longitude: -170.0),
      );

      expect(crossingBox.crossesAntimeridian, isTrue);
      expect(crossingBox.latitudeSpan, 10.0);
      expect(
        crossingBox.longitudeSpan,
        20.0,
      ); // 10° on east + 10° on west = 20°

      // Inside eastern hemisphere (+179.5°)
      expect(
        crossingBox.contains(Coordinates(latitude: -15.0, longitude: 179.5)),
        isTrue,
      );

      // Inside western hemisphere (-179.5°)
      expect(
        crossingBox.contains(Coordinates(latitude: -15.0, longitude: -179.5)),
        isTrue,
      );

      // Exactly on borders
      expect(
        crossingBox.contains(Coordinates(latitude: -15.0, longitude: 170.0)),
        isTrue,
      );
      expect(
        crossingBox.contains(Coordinates(latitude: -15.0, longitude: -170.0)),
        isTrue,
      );

      // Excluded: Prime meridian / 0°
      expect(
        crossingBox.contains(Coordinates(latitude: -15.0, longitude: 0.0)),
        isFalse,
      );

      // Excluded: Longitudes between -170° and +170°
      expect(
        crossingBox.contains(Coordinates(latitude: -15.0, longitude: 165.0)),
        isFalse,
      );
      expect(
        crossingBox.contains(Coordinates(latitude: -15.0, longitude: -165.0)),
        isFalse,
      );

      // Outside latitude
      expect(
        crossingBox.contains(Coordinates(latitude: 5.0, longitude: 179.0)),
        isFalse,
      );
    });
  });
}
