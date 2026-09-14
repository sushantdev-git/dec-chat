import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

import '../../infrastructure/codecs/binary_protocol_codec.dart';
import '../enums/nostr_kind.dart';
import 'bitchat_packet.dart';

/// Nostr protocol event implementing NIP-01 data specification and canonical serialization,
/// extended with transparent carrier embedding for BitChat binary mesh packets.
class NostrEvent {
  /// 32-byte lowercase hex SHA-256 digest of the serialized event data.
  final String id;

  /// 32-byte lowercase hex public key of the event creator.
  final String pubkey;

  /// Unix timestamp in seconds.
  final int createdAt;

  /// Event kind code (NIP-01, NIP-04, NIP-28, NIP-16).
  final int kind;

  /// List of event tags (e.g. `[["p", "<pubkey>"], ["t", "bitchat_mesh"], ["g", "9q8yy"]]`).
  final List<List<String>> tags;

  /// Arbitrary string content (or Base64-encoded BitChat packet payload).
  final String content;

  /// 64-byte lowercase hex signature.
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// Computes the canonical NIP-01 serialized JSON string:
  /// `[0, <pubkey>, <created_at>, <kind>, <tags>, <content>]`
  static String serializeForId(
    String pubkey,
    int createdAt,
    int kind,
    List<List<String>> tags,
    String content,
  ) {
    return jsonEncode([
      0,
      pubkey.toLowerCase(),
      createdAt,
      kind,
      tags,
      content,
    ]);
  }

  /// Computes the 32-byte lowercase hex SHA-256 event ID according to NIP-01.
  static String computeId(
    String pubkey,
    int createdAt,
    int kind,
    List<List<String>> tags,
    String content,
  ) {
    final serialized = serializeForId(pubkey, createdAt, kind, tags, content);
    final digest = crypto.sha256.convert(utf8.encode(serialized));
    return digest.toString();
  }

  /// Factory constructor that automatically computes the canonical [id] if not specified.
  factory NostrEvent.create({
    required String pubkey,
    int? createdAt,
    int kind = 1,
    List<List<String>>? tags,
    required String content,
    String? sig,
    String? id,
  }) {
    final timestamp = createdAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final sanitizedTags = tags ?? <List<String>>[];
    final calculatedId = id ?? computeId(pubkey, timestamp, kind, sanitizedTags, content);
    // Use dummy hex signature if omitted (64-byte hex = 128 chars)
    final signature = sig ?? '0' * 128;

    return NostrEvent(
      id: calculatedId,
      pubkey: pubkey.toLowerCase(),
      createdAt: timestamp,
      kind: kind,
      tags: sanitizedTags,
      content: content,
      sig: signature,
    );
  }

  /// Wraps a binary [BitchatPacket] into a Nostr carrier event (NIP-16 ephemeral or standard).
  factory NostrEvent.fromBitchatPacket({
    required BitchatPacket packet,
    required String pubkeyHex,
    String? recipientPubkeyHex,
    String? geohash,
    int? kind,
    String? sigHex,
  }) {
    final wireBytes = BinaryProtocolCodec.encode(packet);
    if (wireBytes == null) {
      throw ArgumentError('Failed to encode BitchatPacket to binary');
    }
    return NostrEvent.fromPacketBytes(
      packetBytes: wireBytes,
      pubkeyHex: pubkeyHex,
      recipientPubkeyHex: recipientPubkeyHex,
      geohash: geohash,
      kind: kind,
      sigHex: sigHex,
    );
  }

  /// Wraps raw BitChat packet wire bytes into a Nostr carrier event.
  factory NostrEvent.fromPacketBytes({
    required Uint8List packetBytes,
    required String pubkeyHex,
    String? recipientPubkeyHex,
    String? geohash,
    int? kind,
    String? sigHex,
  }) {
    final tags = <List<String>>[
      ['t', 'bitchat_mesh'],
      ['bitchat', '1.0'],
    ];

    if (recipientPubkeyHex != null && recipientPubkeyHex.isNotEmpty) {
      tags.add(['p', recipientPubkeyHex.toLowerCase()]);
    }

    if (geohash != null && geohash.isNotEmpty) {
      tags.add(['g', geohash.toLowerCase()]);
    }

    final content = base64Encode(packetBytes);
    final eventKind = kind ?? NostrKind.ephemeralCarrier.rawValue;

    return NostrEvent.create(
      pubkey: pubkeyHex,
      kind: eventKind,
      tags: tags,
      content: content,
      sig: sigHex,
    );
  }

  /// Deserializes a Nostr event from a JSON map conforming to NIP-01.
  factory NostrEvent.fromJson(Map<String, dynamic> map) {
    final rawTags = map['tags'] as List<dynamic>? ?? [];
    final tags = rawTags.map((tag) {
      if (tag is List) {
        return tag.map((item) => item.toString()).toList();
      }
      return <String>[];
    }).toList();

    return NostrEvent(
      id: (map['id'] as String? ?? '').toLowerCase(),
      pubkey: (map['pubkey'] as String? ?? '').toLowerCase(),
      createdAt: (map['created_at'] as num? ?? 0).toInt(),
      kind: (map['kind'] as num? ?? 1).toInt(),
      tags: tags,
      content: map['content'] as String? ?? '',
      sig: (map['sig'] as String? ?? '').toLowerCase(),
    );
  }

  /// Serializes the Nostr event to a JSON map conforming to NIP-01.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }

  /// Verifies whether the event [id] matches the canonical SHA-256 hash.
  bool get isValidId {
    final calculated = computeId(pubkey, createdAt, kind, tags, content);
    return id.toLowerCase() == calculated.toLowerCase();
  }

  /// Whether this event is a BitChat mesh packet carrier.
  bool get isBitchatPacket {
    for (final tag in tags) {
      if (tag.length >= 2) {
        if (tag[0] == 't' && tag[1] == 'bitchat_mesh') return true;
        if (tag[0] == 'bitchat') return true;
      }
    }
    return false;
  }

  /// Returns the first tag value matching [tagName], or null if not found.
  String? getFirstTagValue(String tagName) {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == tagName) {
        return tag[1];
      }
    }
    return null;
  }

  /// Returns all values for tags with the given [tagName].
  List<String> getTagValues(String tagName) {
    final values = <String>[];
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == tagName) {
        values.add(tag[1]);
      }
    }
    return values;
  }

  /// The target recipient public key tag (`p`), if present.
  String? get recipientPubkey => getFirstTagValue('p');

  /// The geographic channel tag (`g`), if present.
  String? get geohash => getFirstTagValue('g');

  /// Attempts to extract and decode raw BitChat packet bytes from [content].
  Uint8List? get bitchatPacketBytes {
    if (!isBitchatPacket && getFirstTagValue('g') == null) {
      return null;
    }
    try {
      return Uint8List.fromList(base64Decode(content));
    } catch (_) {
      return null;
    }
  }

  /// Attempts to decode the enclosed BitChat wire packet.
  BitchatPacket? toBitchatPacket() {
    final bytes = bitchatPacketBytes;
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return BinaryProtocolCodec.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'NostrEvent(id: ${id.length >= 8 ? id.substring(0, 8) : id}, kind: $kind, pubkey: ${pubkey.length >= 8 ? pubkey.substring(0, 8) : pubkey})';
}
