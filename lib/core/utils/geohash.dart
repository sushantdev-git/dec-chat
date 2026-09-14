/// Represents geographic coordinates with bounding box precision.
class GeohashCoordinates {
  final double latitude;
  final double longitude;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  const GeohashCoordinates({
    required this.latitude,
    required this.longitude,
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  double get latitudeSpan => maxLatitude - minLatitude;
  double get longitudeSpan => maxLongitude - minLongitude;

  @override
  String toString() => 'GeohashCoordinates(lat: $latitude, lon: $longitude)';
}

/// Geographic cardinal directions for neighboring geohash queries.
enum GeohashDirection {
  north,
  south,
  east,
  west,
  northEast,
  northWest,
  southEast,
  southWest,
}

/// Pure Dart Geohash base-32 encoder, decoder, and neighbor adjacency calculator.
///
/// Implements Morton Z-order curve spatial indexing for BitChat location channels (e.g. `#9q8yy`).
class Geohash {
  static const String base32Alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';
  static final RegExp _validGeohashRegex = RegExp(r'^[0123456789bcdefghjkmnpqrstuvwxyz]+$');

  /// Encodes [latitude] and [longitude] into a geohash string with the specified [precision].
  ///
  /// Default precision 5 corresponds to approximately 4.9 km × 4.9 km (neighborhood level).
  static String encode(double latitude, double longitude, {int precision = 5}) {
    if (precision <= 0) {
      throw ArgumentError.value(precision, 'precision', 'Precision must be positive');
    }

    double minLat = -90.0, maxLat = 90.0;
    double minLon = -180.0, maxLon = 180.0;

    final buffer = StringBuffer();
    bool isLongitude = true;
    int bitIndex = 0;
    int charValue = 0;

    while (buffer.length < precision) {
      if (isLongitude) {
        final mid = (minLon + maxLon) / 2.0;
        if (longitude >= mid) {
          charValue = (charValue << 1) | 1;
          minLon = mid;
        } else {
          charValue = (charValue << 1) | 0;
          maxLon = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2.0;
        if (latitude >= mid) {
          charValue = (charValue << 1) | 1;
          minLat = mid;
        } else {
          charValue = (charValue << 1) | 0;
          maxLat = mid;
        }
      }

      isLongitude = !isLongitude;
      bitIndex++;

      if (bitIndex == 5) {
        buffer.write(base32Alphabet[charValue]);
        bitIndex = 0;
        charValue = 0;
      }
    }

    return buffer.toString();
  }

  /// Decodes a [geohash] string into center coordinates and bounding box bounds.
  static GeohashCoordinates decode(String geohash) {
    final clean = geohash.trim().toLowerCase();
    if (clean.isEmpty || !_validGeohashRegex.hasMatch(clean)) {
      throw FormatException('Invalid geohash string: $geohash');
    }

    double minLat = -90.0, maxLat = 90.0;
    double minLon = -180.0, maxLon = 180.0;
    bool isLongitude = true;

    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      final charIndex = base32Alphabet.indexOf(char);
      if (charIndex == -1) {
        throw FormatException('Invalid character "$char" in geohash');
      }

      for (int bit = 4; bit >= 0; bit--) {
        final bitValue = (charIndex >> bit) & 1;
        if (isLongitude) {
          final mid = (minLon + maxLon) / 2.0;
          if (bitValue == 1) {
            minLon = mid;
          } else {
            maxLon = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2.0;
          if (bitValue == 1) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isLongitude = !isLongitude;
      }
    }

    final centerLat = (minLat + maxLat) / 2.0;
    final centerLon = (minLon + maxLon) / 2.0;

    return GeohashCoordinates(
      latitude: centerLat,
      longitude: centerLon,
      minLatitude: minLat,
      maxLatitude: maxLat,
      minLongitude: minLon,
      maxLongitude: maxLon,
    );
  }

  /// Calculates the neighboring geohash in the specified cardinal [direction].
  static String adjacent(String geohash, GeohashDirection direction) {
    final coords = decode(geohash);
    final latSpan = coords.latitudeSpan;
    final lonSpan = coords.longitudeSpan;

    double targetLat = coords.latitude;
    double targetLon = coords.longitude;

    switch (direction) {
      case GeohashDirection.north:
        targetLat += latSpan;
        break;
      case GeohashDirection.south:
        targetLat -= latSpan;
        break;
      case GeohashDirection.east:
        targetLon += lonSpan;
        break;
      case GeohashDirection.west:
        targetLon -= lonSpan;
        break;
      case GeohashDirection.northEast:
        targetLat += latSpan;
        targetLon += lonSpan;
        break;
      case GeohashDirection.northWest:
        targetLat += latSpan;
        targetLon -= lonSpan;
        break;
      case GeohashDirection.southEast:
        targetLat -= latSpan;
        targetLon += lonSpan;
        break;
      case GeohashDirection.southWest:
        targetLat -= latSpan;
        targetLon -= lonSpan;
        break;
    }

    // Clamp coordinates to valid ranges with spherical wrap-around
    if (targetLat > 90.0) targetLat = 90.0;
    if (targetLat < -90.0) targetLat = -90.0;
    while (targetLon > 180.0) {
      targetLon -= 360.0;
    }
    while (targetLon < -180.0) {
      targetLon += 360.0;
    }

    return encode(targetLat, targetLon, precision: geohash.length);
  }

  /// Returns all 8 surrounding neighboring geohashes.
  static List<String> neighbors(String geohash) {
    return [
      adjacent(geohash, GeohashDirection.north),
      adjacent(geohash, GeohashDirection.northEast),
      adjacent(geohash, GeohashDirection.east),
      adjacent(geohash, GeohashDirection.southEast),
      adjacent(geohash, GeohashDirection.south),
      adjacent(geohash, GeohashDirection.southWest),
      adjacent(geohash, GeohashDirection.west),
      adjacent(geohash, GeohashDirection.northWest),
    ];
  }

  /// Reserved protocol channel names that are not geohashes.
  static const Set<String> reservedChannels = {
    '#mesh',
    '#general',
    '#broadcast',
    '#all',
  };

  /// Validates whether a channel name is a valid location channel (e.g. `#9q8yy`).
  static bool isLocationChannel(String channelName) {
    final clean = channelName.trim().toLowerCase();
    if (reservedChannels.contains(clean)) return false;
    if (!clean.startsWith('#')) return false;
    final hashPart = clean.substring(1);
    if (hashPart.length < 3 || hashPart.length > 9) return false;
    return _validGeohashRegex.hasMatch(hashPart);
  }

  /// Extracts the lowercase geohash string from a channel name (e.g. `#9q8yy` -> `9q8yy`).
  static String? extractGeohash(String channelName) {
    if (!isLocationChannel(channelName)) return null;
    return channelName.trim().substring(1).toLowerCase();
  }
}
