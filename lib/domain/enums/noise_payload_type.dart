/// Inner payload types encapsulated within a decrypted [MessageType.noiseEncrypted] packet (0x11).
///
/// When an encrypted transport payload is decrypted, its first byte indicates the specific
/// application payload format.
class NoisePayloadType {
  final int rawValue;
  final String name;

  const NoisePayloadType._(this.rawValue, this.name);

  // Direct 1-to-1 messaging
  static const NoisePayloadType privateMessage = NoisePayloadType._(0x01, 'privateMessage');
  static const NoisePayloadType readReceipt = NoisePayloadType._(0x02, 'readReceipt');
  static const NoisePayloadType delivered = NoisePayloadType._(0x03, 'delivered');

  // Group messaging
  static const NoisePayloadType groupInvite = NoisePayloadType._(0x06, 'groupInvite');
  static const NoisePayloadType groupKeyUpdate = NoisePayloadType._(0x07, 'groupKeyUpdate');

  // Media & Streaming
  static const NoisePayloadType voiceFrame = NoisePayloadType._(0x08, 'voiceFrame');

  // In-person verification & Web-of-trust
  static const NoisePayloadType verifyChallenge = NoisePayloadType._(0x10, 'verifyChallenge');
  static const NoisePayloadType verifyResponse = NoisePayloadType._(0x11, 'verifyResponse');
  static const NoisePayloadType vouch = NoisePayloadType._(0x12, 'vouch');

  // Private file transfer & state
  static const NoisePayloadType privateFile = NoisePayloadType._(0x20, 'privateFile');
  static const NoisePayloadType authenticatedPeerState =
      NoisePayloadType._(0x21, 'authenticatedPeerState');

  static const List<NoisePayloadType> knownValues = [
    privateMessage,
    readReceipt,
    delivered,
    groupInvite,
    groupKeyUpdate,
    voiceFrame,
    verifyChallenge,
    verifyResponse,
    vouch,
    privateFile,
    authenticatedPeerState,
  ];

  /// Resolves a raw byte value to a [NoisePayloadType].
  /// Forward-compatible: maps unknown types to a descriptive instance without throwing.
  factory NoisePayloadType.fromRaw(int value) {
    for (final type in knownValues) {
      if (type.rawValue == value) return type;
    }
    return NoisePayloadType._(value, 'unknown_0x${value.toRadixString(16).padLeft(2, '0')}');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoisePayloadType &&
          runtimeType == other.runtimeType &&
          rawValue == other.rawValue;

  @override
  int get hashCode => rawValue.hashCode;

  @override
  String toString() => 'NoisePayloadType($name, 0x${rawValue.toRadixString(16).padLeft(2, '0')})';
}
