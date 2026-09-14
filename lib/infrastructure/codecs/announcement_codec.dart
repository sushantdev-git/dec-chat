import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import '../../core/utils/binary_reader.dart';
import '../../core/utils/binary_writer.dart';

/// Decoded representation of a BitChat peer presence announcement packet.
class AnnouncementPayload {
  final String nickname;
  final Uint8List noisePublicKey;
  final Uint8List signingPublicKey;
  final List<Uint8List>? directNeighbors;
  final int? capabilities;
  final String? bridgeGeohash;
  /// Optional phone number shared by the peer (Phase 10). Null if not set.
  final String? phoneNumber;

  const AnnouncementPayload({
    required this.nickname,
    required this.noisePublicKey,
    required this.signingPublicKey,
    this.directNeighbors,
    this.capabilities,
    this.bridgeGeohash,
    this.phoneNumber,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final eq = const ListEquality().equals;
    return other is AnnouncementPayload &&
        other.nickname == nickname &&
        eq(other.noisePublicKey, noisePublicKey) &&
        eq(other.signingPublicKey, signingPublicKey) &&
        other.capabilities == capabilities &&
        other.bridgeGeohash == bridgeGeohash &&
        other.phoneNumber == phoneNumber;
  }

  @override
  int get hashCode => Object.hash(
        nickname,
        const ListEquality().hash(noisePublicKey),
        const ListEquality().hash(signingPublicKey),
        capabilities,
        bridgeGeohash,
        phoneNumber,
      );
}

/// TLV encoder and decoder for BitChat peer presence announcements.
/// Forward-compatible: safely ignores unknown future TLV tags without crashing.
class AnnouncementCodec {
  static const int tlvNickname = 0x01;
  static const int tlvNoisePublicKey = 0x02;
  static const int tlvSigningPublicKey = 0x03;
  static const int tlvDirectNeighbors = 0x04;
  static const int tlvCapabilities = 0x05;
  static const int tlvBridgeGeohash = 0x06;
  // Phase 10: optional phone number (opt-in, privacy-preserving)
  static const int tlvPhoneNumber = 0x07;

  /// Encodes an [AnnouncementPayload] into binary TLV format.
  static Uint8List? encode(AnnouncementPayload announcement) {
    final writer = BinaryWriter(initialCapacity: 128);

    // 1. Nickname TLV
    final nickBytes = utf8.encode(announcement.nickname);
    if (nickBytes.length > 255) return null;
    writer.writeUint8(tlvNickname);
    writer.writeUint8(nickBytes.length);
    writer.writeBytes(nickBytes);

    // 2. Noise Public Key TLV (Curve25519)
    if (announcement.noisePublicKey.length > 255) return null;
    writer.writeUint8(tlvNoisePublicKey);
    writer.writeUint8(announcement.noisePublicKey.length);
    writer.writeBytes(announcement.noisePublicKey);

    // 3. Signing Public Key TLV (Ed25519)
    if (announcement.signingPublicKey.length > 255) return null;
    writer.writeUint8(tlvSigningPublicKey);
    writer.writeUint8(announcement.signingPublicKey.length);
    writer.writeBytes(announcement.signingPublicKey);

    // 4. Direct Neighbors TLV (Optional, sequence of 8-byte IDs)
    if (announcement.directNeighbors != null && announcement.directNeighbors!.isNotEmpty) {
      final neighbors = announcement.directNeighbors!;
      final totalBytes = neighbors.length * 8;
      if (totalBytes <= 255) {
        writer.writeUint8(tlvDirectNeighbors);
        writer.writeUint8(totalBytes);
        for (final n in neighbors) {
          final hop = n.length >= 8 ? n.sublist(0, 8) : Uint8List(8)..setRange(0, n.length, n);
          writer.writeBytes(hop);
        }
      }
    }

    // 5. Capabilities TLV (Optional 4-byte bitmask)
    if (announcement.capabilities != null) {
      writer.writeUint8(tlvCapabilities);
      writer.writeUint8(4);
      writer.writeUint32(announcement.capabilities!);
    }

    // 6. Bridge Geohash TLV (Optional string)
    if (announcement.bridgeGeohash != null) {
      final geohashBytes = utf8.encode(announcement.bridgeGeohash!);
      if (geohashBytes.length <= 255) {
        writer.writeUint8(tlvBridgeGeohash);
        writer.writeUint8(geohashBytes.length);
        writer.writeBytes(geohashBytes);
      }
    }

    // 7. Phone Number TLV (Optional, opt-in only — Phase 10)
    if (announcement.phoneNumber != null && announcement.phoneNumber!.isNotEmpty) {
      final phoneBytes = utf8.encode(announcement.phoneNumber!);
      if (phoneBytes.length <= 20) {
        writer.writeUint8(tlvPhoneNumber);
        writer.writeUint8(phoneBytes.length);
        writer.writeBytes(phoneBytes);
      }
    }

    return writer.toBytes();
  }

  /// Decodes binary TLV data into an [AnnouncementPayload].
  /// Resiliently skips unknown TLV types for future protocol extensibility.
  static AnnouncementPayload? decode(Uint8List bytes) {
    if (bytes.isEmpty) return null;

    final reader = BinaryReader(bytes);
    String? nickname;
    Uint8List? noisePublicKey;
    Uint8List? signingPublicKey;
    List<Uint8List>? directNeighbors;
    int? capabilities;
    String? bridgeGeohash;
    String? phoneNumber;

    try {
      while (!reader.isAtEnd) {
        if (reader.remaining < 2) break;

        final tag = reader.readUint8();
        final length = reader.readUint8();
        if (reader.remaining < length) break;

        final valBytes = reader.readBytes(length);

        switch (tag) {
          case tlvNickname:
            nickname = utf8.decode(valBytes, allowMalformed: true);
            break;
          case tlvNoisePublicKey:
            noisePublicKey = valBytes;
            break;
          case tlvSigningPublicKey:
            signingPublicKey = valBytes;
            break;
          case tlvDirectNeighbors:
            final count = length ~/ 8;
            final neighbors = <Uint8List>[];
            for (int i = 0; i < count; i++) {
              neighbors.add(valBytes.sublist(i * 8, (i + 1) * 8));
            }
            directNeighbors = neighbors;
            break;
          case tlvCapabilities:
            if (length >= 4) {
              capabilities = ByteData.sublistView(valBytes).getUint32(0, Endian.big);
            }
            break;
          case tlvBridgeGeohash:
            bridgeGeohash = utf8.decode(valBytes, allowMalformed: true);
            break;
          case tlvPhoneNumber:
            phoneNumber = utf8.decode(valBytes, allowMalformed: true);
            break;
          default:
            // Unknown TLV tag: safely ignored for future forward-compatibility!
            break;
        }
      }

      // Mandatory fields
      if (nickname == null || noisePublicKey == null || signingPublicKey == null) {
        return null;
      }

      return AnnouncementPayload(
        nickname: nickname,
        noisePublicKey: noisePublicKey,
        signingPublicKey: signingPublicKey,
        directNeighbors: directNeighbors,
        capabilities: capabilities,
        bridgeGeohash: bridgeGeohash,
        phoneNumber: phoneNumber,
      );
    } catch (_) {
      return null;
    }
  }
}
