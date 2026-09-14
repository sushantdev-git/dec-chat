import 'dart:typed_data';
import 'package:collection/collection.dart';
import '../enums/message_type.dart';

/// The core protocol packet structure for all BitChat mesh network communication.
/// Encapsulates routing metadata (TTL, hops, routes), sender/recipient identities,
/// payload data, and cryptographic signatures.
class BitchatPacket {
  /// Protocol wire version (1 = 14-byte header / 2-byte len, 2 = 16-byte header / 4-byte len).
  final int version;

  /// Wire message type.
  final MessageType type;

  /// Hop limit. Decremented by each relay node.
  final int ttl;

  /// Unix timestamp in milliseconds (64-bit integer).
  final int timestamp;

  /// 8-byte persistent sender peer ID (derived from Curve25519 static key fingerprint).
  final Uint8List senderId;

  /// Optional 8-byte destination peer ID. Present if [hasRecipient] flag is set.
  final Uint8List? recipientId;

  /// Optional list of 8-byte peer IDs representing an explicit source route.
  final List<Uint8List>? route;

  /// Packet payload bytes (may be compressed or encrypted).
  final Uint8List payload;

  /// Optional 64-byte Ed25519 signature over the packet (calculated with TTL = 0).
  final Uint8List? signature;

  /// Whether this packet payload is compressed (zlib/deflate).
  final bool isCompressed;

  /// Reverse Source Route flag.
  final bool isRSR;

  const BitchatPacket({
    required this.type,
    required this.senderId,
    required this.timestamp,
    required this.payload,
    this.version = 1,
    this.ttl = 7,
    this.recipientId,
    this.route,
    this.signature,
    this.isCompressed = false,
    this.isRSR = false,
  });

  /// Bitmask flags
  static const int flagHasRecipient = 0x01;
  static const int flagHasSignature = 0x02;
  static const int flagIsCompressed = 0x04;
  static const int flagHasRoute = 0x08;
  static const int flagIsRSR = 0x10;

  bool get hasRecipient => recipientId != null && recipientId!.isNotEmpty;
  bool get hasSignature => signature != null && signature!.isNotEmpty;
  bool get hasRoute => route != null && route!.isNotEmpty;

  /// Calculates the flags bitmask byte for this packet.
  int get flags {
    int f = 0;
    if (hasRecipient) f |= flagHasRecipient;
    if (hasSignature) f |= flagHasSignature;
    if (isCompressed) f |= flagIsCompressed;
    if (hasRoute) f |= flagHasRoute;
    if (isRSR) f |= flagIsRSR;
    return f;
  }

  /// Creates a copy of this packet prepared for signature calculation or verification.
  /// Matches BitChat specification: TTL is forced to 0, signature is omitted, and
  /// mutable RSR flag is set to false because TTL and RSR mutate during multi-hop relay.
  BitchatPacket copyForSigning() {
    return BitchatPacket(
      version: version,
      type: type,
      ttl: 0,
      timestamp: timestamp,
      senderId: senderId,
      recipientId: recipientId,
      route: route,
      payload: payload,
      signature: null,
      isCompressed: isCompressed,
      isRSR: false,
    );
  }

  /// Creates a copy of this packet with modified fields.
  BitchatPacket copyWith({
    int? version,
    MessageType? type,
    int? ttl,
    int? timestamp,
    Uint8List? senderId,
    Uint8List? recipientId,
    List<Uint8List>? route,
    Uint8List? payload,
    Uint8List? signature,
    bool? isCompressed,
    bool? isRSR,
  }) {
    return BitchatPacket(
      version: version ?? this.version,
      type: type ?? this.type,
      ttl: ttl ?? this.ttl,
      timestamp: timestamp ?? this.timestamp,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      route: route ?? this.route,
      payload: payload ?? this.payload,
      signature: signature ?? this.signature,
      isCompressed: isCompressed ?? this.isCompressed,
      isRSR: isRSR ?? this.isRSR,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final eq = const ListEquality().equals;
    return other is BitchatPacket &&
        other.version == version &&
        other.type == type &&
        other.ttl == ttl &&
        other.timestamp == timestamp &&
        eq(other.senderId, senderId) &&
        eq(other.recipientId, recipientId) &&
        eq(other.payload, payload) &&
        eq(other.signature, signature) &&
        other.isCompressed == isCompressed &&
        other.isRSR == isRSR;
  }

  @override
  int get hashCode => Object.hash(
        version,
        type,
        ttl,
        timestamp,
        const ListEquality().hash(senderId),
        const ListEquality().hash(recipientId),
        const ListEquality().hash(payload),
        isCompressed,
        isRSR,
      );

  @override
  String toString() {
    return 'BitchatPacket(v$version, type: ${type.name}, ttl: $ttl, sender: ${senderId.length}B, payload: ${payload.length}B, flags: 0x${flags.toRadixString(16)})';
  }
}
