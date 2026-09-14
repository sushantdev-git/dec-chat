/// Represents wire-level message types for BitChat protocol packets.
/// Designed for forward-compatibility: unknown future packet types
/// are mapped to [MessageType.unknown] so they can still be safely
/// routed, deduplicated, and relayed across the mesh without breaking.
class MessageType {
  final int rawValue;
  final String name;

  const MessageType._(this.rawValue, this.name);

  // Public messages (unencrypted)
  static const MessageType announce = MessageType._(0x01, 'announce');
  static const MessageType message = MessageType._(0x02, 'message');
  static const MessageType leave = MessageType._(0x03, 'leave');
  static const MessageType courierEnvelope = MessageType._(0x04, 'courierEnvelope');
  static const MessageType requestSync = MessageType._(0x21, 'requestSync');

  // Noise protocol encryption
  static const MessageType noiseHandshake = MessageType._(0x10, 'noiseHandshake');
  static const MessageType noiseEncrypted = MessageType._(0x11, 'noiseEncrypted');

  // Fragmentation & media
  static const MessageType fragment = MessageType._(0x20, 'fragment');
  static const MessageType fileTransfer = MessageType._(0x22, 'fileTransfer');
  static const MessageType boardPost = MessageType._(0x23, 'boardPost');
  static const MessageType prekeyBundle = MessageType._(0x24, 'prekeyBundle');
  static const MessageType groupMessage = MessageType._(0x25, 'groupMessage');

  // Diagnostics & carriers
  static const MessageType ping = MessageType._(0x26, 'ping');
  static const MessageType pong = MessageType._(0x27, 'pong');
  static const MessageType nostrCarrier = MessageType._(0x28, 'nostrCarrier');
  static const MessageType voiceFrame = MessageType._(0x29, 'voiceFrame');
  static const MessageType announceV2 = MessageType._(0x2C, 'announceV2');

  static const List<MessageType> knownValues = [
    announce,
    message,
    leave,
    courierEnvelope,
    requestSync,
    noiseHandshake,
    noiseEncrypted,
    fragment,
    fileTransfer,
    boardPost,
    prekeyBundle,
    groupMessage,
    ping,
    pong,
    nostrCarrier,
    voiceFrame,
    announceV2,
  ];

  /// Resolves a raw byte value to a [MessageType].
  /// If unknown, returns a custom [MessageType] preserving the rawValue.
  factory MessageType.fromRaw(int value) {
    for (final type in knownValues) {
      if (type.rawValue == value) return type;
    }
    return MessageType._(value, 'unknown_0x${value.toRadixString(16).padLeft(2, '0')}');
  }

  bool get isEncrypted => this == noiseHandshake || this == noiseEncrypted;
  bool get isFragment => this == fragment;
  bool get isAnnounce => this == announce || this == announceV2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageType &&
          runtimeType == other.runtimeType &&
          rawValue == other.rawValue;

  @override
  int get hashCode => rawValue.hashCode;

  @override
  String toString() => 'MessageType($name, 0x${rawValue.toRadixString(16).padLeft(2, '0')})';
}
