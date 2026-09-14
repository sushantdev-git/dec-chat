import 'package:flutter_test/flutter_test.dart';
import 'package:dec_chat/domain/services/location_channel_service.dart';

void main() {
  group('LocationChannelService Spatial Channel Management', () {
    late LocationChannelService service;

    setUp(() {
      service = LocationChannelService();
    });

    test('generates channel name from GPS coordinates with configurable precision', () {
      final channel5 = service.channelFromCoordinates(37.7749, -122.4194, precision: 5);
      expect(channel5.startsWith('#9q8yy'), isTrue);
      expect(channel5.length, equals(6)); // '#' + 5 chars

      final channel7 = service.channelFromCoordinates(37.7749, -122.4194, precision: 7);
      expect(channel7.length, equals(8)); // '#' + 7 chars
      expect(channel7.startsWith(channel5), isTrue);
    });

    test('retrieves channel bounding box bounds and center coordinates', () {
      final bounds = service.getChannelBounds('#9q8yy');
      expect(bounds, isNotNull);
      expect(bounds!.latitude, closeTo(37.79, 0.05));
      expect(bounds.longitude, closeTo(-122.41, 0.05));
      expect(bounds.latitudeSpan, greaterThan(0));
      expect(bounds.longitudeSpan, greaterThan(0));

      // Returns null for invalid channel
      expect(service.getChannelBounds('#invalid!channel'), isNull);
    });

    test('returns 9 covering geohashes (1 center + 8 neighbors)', () {
      final covering = service.getCoveringGeohashes('#9q8yy');
      expect(covering.length, equals(9));
      expect(covering[0], equals('9q8yy'));
      expect(covering.toSet().length, equals(9)); // All 9 are unique
    });

    test('manages join and leave lifecycle with validation', () {
      expect(service.isJoined('#9q8yy'), isFalse);

      final covering = service.joinChannel('#9q8yy');
      expect(covering.length, equals(9));
      expect(service.isJoined('#9q8yy'), isTrue);
      expect(service.joinedChannels.contains('#9q8yy'), isTrue);

      // Throws on invalid channel
      expect(() => service.joinChannel('#global'), throwsArgumentError);
      expect(() => service.joinChannel('9q8yy'), throwsArgumentError);

      final left = service.leaveChannel('#9q8yy');
      expect(left, isTrue);
      expect(service.isJoined('#9q8yy'), isFalse);
      expect(service.joinedChannels.isEmpty, isTrue);
    });

    test('isCoveredByJoinedChannels correctly matches center and neighbor cells', () {
      service.joinChannel('#9q8yy');

      // Center cell is covered
      expect(service.isCoveredByJoinedChannels('9q8yy'), isTrue);

      // All 8 neighbor cells are covered
      final covering = service.getCoveringGeohashes('#9q8yy');
      for (final hash in covering) {
        expect(service.isCoveredByJoinedChannels(hash), isTrue);
      }

      // Distant geohashes (e.g. London 'gcpvj') are NOT covered
      expect(service.isCoveredByJoinedChannels('gcpvj'), isFalse);
    });
  });
}
