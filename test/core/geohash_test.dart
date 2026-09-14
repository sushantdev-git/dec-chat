import 'package:flutter_test/flutter_test.dart';
import 'package:dec_chat/core/utils/geohash.dart';

void main() {
  group('Geohash Base-32 Spatial Indexing', () {
    test('encodes known geographic coordinates correctly', () {
      // San Francisco (approx 37.7749, -122.4194) -> 9q8yy
      final sfHash = Geohash.encode(37.7749, -122.4194, precision: 5);
      expect(sfHash.startsWith('9q8yy'), isTrue);
      final sfCoords = Geohash.decode(sfHash);
      expect(sfCoords.latitude, closeTo(37.7749, 0.05));
      expect(sfCoords.longitude, closeTo(-122.4194, 0.05));

      // London (approx 51.5074, -0.1278) -> gcpvj
      final londonHash = Geohash.encode(51.5074, -0.1278, precision: 5);
      expect(londonHash.startsWith('gcpvj'), isTrue);
      final londonCoords = Geohash.decode(londonHash);
      expect(londonCoords.latitude, closeTo(51.5074, 0.05));
      expect(londonCoords.longitude, closeTo(-0.1278, 0.05));

      // Tokyo (approx 35.6762, 139.6503)
      final tokyoHash = Geohash.encode(35.6762, 139.6503, precision: 5);
      final tokyoCoords = Geohash.decode(tokyoHash);
      expect(tokyoCoords.latitude, closeTo(35.6762, 0.05));
      expect(tokyoCoords.longitude, closeTo(139.6503, 0.05));

      // Sydney (approx -33.8688, 151.2093)
      final sydneyHash = Geohash.encode(-33.8688, 151.2093, precision: 5);
      final sydneyCoords = Geohash.decode(sydneyHash);
      expect(sydneyCoords.latitude, closeTo(-33.8688, 0.05));
      expect(sydneyCoords.longitude, closeTo(151.2093, 0.05));
    });

    test('decodes geohash back to coordinates within bounding box bounds', () {
      const hash = '9q8yy';
      final coords = Geohash.decode(hash);

      expect(coords.latitude, inInclusiveRange(coords.minLatitude, coords.maxLatitude));
      expect(coords.longitude, inInclusiveRange(coords.minLongitude, coords.maxLongitude));
      expect(coords.latitude, closeTo(37.79, 0.05));
      expect(coords.longitude, closeTo(-122.41, 0.05));
      expect(coords.latitudeSpan, greaterThan(0));
      expect(coords.longitudeSpan, greaterThan(0));
    });

    test('throws FormatException on invalid geohash strings', () {
      expect(() => Geohash.decode(''), throwsFormatException);
      expect(() => Geohash.decode('invalid!chars'), throwsFormatException);
      expect(() => Geohash.decode('123a'), throwsFormatException); // 'a' is not in base32 alphabet
    });

    test('throws ArgumentError on non-positive precision', () {
      expect(() => Geohash.encode(0, 0, precision: 0), throwsArgumentError);
      expect(() => Geohash.encode(0, 0, precision: -1), throwsArgumentError);
    });

    test('calculates adjacent neighbor geohashes in all 8 cardinal directions', () {
      const center = '9q8yy';
      final north = Geohash.adjacent(center, GeohashDirection.north);
      final south = Geohash.adjacent(center, GeohashDirection.south);
      final east = Geohash.adjacent(center, GeohashDirection.east);
      final west = Geohash.adjacent(center, GeohashDirection.west);

      expect(north, isNot(equals(center)));
      expect(south, isNot(equals(center)));
      expect(east, isNot(equals(center)));
      expect(west, isNot(equals(center)));

      final allNeighbors = Geohash.neighbors(center);
      expect(allNeighbors.length, equals(8));
      expect(allNeighbors.toSet().length, equals(8)); // All 8 neighbors are distinct
      expect(allNeighbors.contains(center), isFalse);
    });

    test('validates location channel naming convention and extraction', () {
      expect(Geohash.isLocationChannel('#9q8yy'), isTrue);
      expect(Geohash.isLocationChannel('#gcpvj'), isTrue);
      expect(Geohash.isLocationChannel('#9q8yypqr'), isTrue);

      // Invalid location channels
      expect(Geohash.isLocationChannel('9q8yy'), isFalse); // Missing '#'
      expect(Geohash.isLocationChannel('#global'), isFalse); // 'l', 'o' not in base32 alphabet
      expect(Geohash.isLocationChannel('#12'), isFalse); // Too short (< 3)
      expect(Geohash.isLocationChannel('#1234567890'), isFalse); // Too long (> 9)

      // Extraction
      expect(Geohash.extractGeohash('#9q8yy'), equals('9q8yy'));
      expect(Geohash.extractGeohash('#9Q8YY'), equals('9q8yy'));
      expect(Geohash.extractGeohash('#global'), isNull);
    });
  });
}
