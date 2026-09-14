import '../../core/utils/geohash.dart';

/// Manages BitChat location-based chat channels (e.g. `#9q8yy`),
/// supporting multi-resolution spatial indexing and 9-cell boundary neighborhood coverage.
class LocationChannelService {
  final Set<String> _joinedChannels = {};

  /// Default geohash precision for neighborhood channels (5 chars ~ 4.9 km x 4.9 km).
  static const int defaultPrecision = 5;

  /// Set of currently joined location channels (e.g. `{'#9q8yy', '#dr5ru'}`).
  Set<String> get joinedChannels => Set.unmodifiable(_joinedChannels);

  /// Formats a channel string from GPS [latitude] and [longitude] with specified [precision].
  ///
  /// Precision 5: ~4.9 km (neighborhood)
  /// Precision 6: ~1.2 km (district)
  /// Precision 7: ~152 m (building/street)
  String channelFromCoordinates(
    double latitude,
    double longitude, {
    int precision = defaultPrecision,
  }) {
    final hash = Geohash.encode(latitude, longitude, precision: precision);
    return '#$hash';
  }

  /// Calculates center coordinates and bounding box for a given location [channelName].
  GeohashCoordinates? getChannelBounds(String channelName) {
    final geohash = Geohash.extractGeohash(channelName);
    if (geohash == null) return null;
    return Geohash.decode(geohash);
  }

  /// Returns the center geohash plus all 8 surrounding neighbor geohashes for 9-cell coverage.
  List<String> getCoveringGeohashes(String channelName) {
    final geohash = Geohash.extractGeohash(channelName);
    if (geohash == null) return [];

    return [
      geohash,
      ...Geohash.neighbors(geohash),
    ];
  }

  /// Joins a location channel, returning the set of covering geohashes (9 cells).
  List<String> joinChannel(String channelName) {
    final clean = channelName.trim().toLowerCase();
    if (!Geohash.isLocationChannel(clean)) {
      throw ArgumentError('Invalid location channel name: $channelName. Expected format like #9q8yy');
    }
    _joinedChannels.add(clean);
    return getCoveringGeohashes(clean);
  }

  /// Leaves a location channel.
  bool leaveChannel(String channelName) {
    final clean = channelName.trim().toLowerCase();
    return _joinedChannels.remove(clean);
  }

  /// Checks whether a channel is currently joined.
  bool isJoined(String channelName) {
    return _joinedChannels.contains(channelName.trim().toLowerCase());
  }

  /// Checks whether a given [geohash] matches any joined channel or its 8 surrounding neighbors.
  bool isCoveredByJoinedChannels(String geohash) {
    final clean = geohash.trim().toLowerCase();
    for (final channel in _joinedChannels) {
      final covering = getCoveringGeohashes(channel);
      if (covering.contains(clean)) {
        return true;
      }
    }
    return false;
  }
}
