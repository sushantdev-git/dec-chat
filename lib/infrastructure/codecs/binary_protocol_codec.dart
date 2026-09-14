import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/binary_reader.dart';
import '../../core/utils/binary_writer.dart';
import '../../core/utils/message_padding.dart';
import '../../domain/entities/bitchat_packet.dart';
import '../../domain/enums/message_type.dart';

/// Low-level binary encoding and decoding for BitChat protocol messages.
/// 100% compliant with BitChat v1 (14-byte) and v2 (16-byte) wire specifications.
class BinaryProtocolCodec {
  static const int v1HeaderSize = 14;
  static const int v2HeaderSize = 16;
  static const int senderIdSize = 8;
  static const int recipientIdSize = 8;
  static const int signatureSize = 64;

  /// Compression threshold: payloads above 256 bytes may be compressed.
  static const int compressionThresholdBytes = 256;

  /// Encodes a [BitchatPacket] into its wire binary representation.
  static Uint8List? encode(BitchatPacket packet, {bool padding = true}) {
    final version = packet.version;
    if (version != 1 && version != 2) return null;

    Uint8List payload = packet.payload;
    bool isCompressed = false;
    int? originalPayloadSize;

    // Optional compression for payloads > 256 bytes
    if (packet.isCompressed || (payload.length > compressionThresholdBytes)) {
      try {
        final compressed = Uint8List.fromList(zlib.encode(payload));
        if (compressed.length < payload.length) {
          originalPayloadSize = payload.length;
          payload = compressed;
          isCompressed = true;
        }
      } catch (_) {
        // Fallback to uncompressed payload on error
      }
    }

    final lengthFieldBytes = version == 2 ? 4 : 2;
    final originalSizeFieldBytes = isCompressed ? lengthFieldBytes : 0;
    final payloadDataSize = payload.length + originalSizeFieldBytes;

    if (version == 1 && payloadDataSize > 0xFFFF) return null;
    if (version == 2 && payloadDataSize > 0xFFFFFFFF) return null;

    // Route handling (v2+ only)
    final route = (version >= 2) ? (packet.route ?? []) : <Uint8List>[];
    final hasRoute = route.isNotEmpty && version >= 2;
    if (route.length > 255) return null;

    final writer = BinaryWriter(initialCapacity: 128 + payloadDataSize);

    // 1. Header (Fixed 14 or 16 bytes)
    writer.writeUint8(version);
    writer.writeUint8(packet.type.rawValue);
    writer.writeUint8(packet.ttl);
    writer.writeUint64(packet.timestamp);

    // Flags
    int flags = 0;
    if (packet.hasRecipient) flags |= BitchatPacket.flagHasRecipient;
    if (packet.hasSignature) flags |= BitchatPacket.flagHasSignature;
    if (isCompressed) flags |= BitchatPacket.flagIsCompressed;
    if (hasRoute) flags |= BitchatPacket.flagHasRoute;
    if (packet.isRSR) flags |= BitchatPacket.flagIsRSR;
    writer.writeUint8(flags);

    // Payload length
    if (version == 2) {
      writer.writeUint32(payloadDataSize);
    } else {
      writer.writeUint16(payloadDataSize);
    }

    // 2. Sender ID (8 bytes)
    final senderBytes = _padOrTruncate(packet.senderId, senderIdSize);
    writer.writeBytes(senderBytes);

    // 3. Recipient ID (8 bytes, optional)
    if (packet.hasRecipient) {
      final recipientBytes = _padOrTruncate(packet.recipientId!, recipientIdSize);
      writer.writeBytes(recipientBytes);
    }

    // 4. Route (v2 only, optional)
    if (hasRoute) {
      writer.writeUint8(route.length);
      for (final hop in route) {
        writer.writeBytes(_padOrTruncate(hop, senderIdSize));
      }
    }

    // 5. Compression original length (if compressed)
    if (isCompressed && originalPayloadSize != null) {
      if (version == 2) {
        writer.writeUint32(originalPayloadSize);
      } else {
        writer.writeUint16(originalPayloadSize);
      }
    }

    // 6. Payload data
    writer.writeBytes(payload);

    // 7. Signature (64 bytes, optional)
    if (packet.hasSignature) {
      final sigBytes = _padOrTruncate(packet.signature!, signatureSize);
      writer.writeBytes(sigBytes);
    }

    final encoded = writer.toBytes();

    // Noise packets are padded for privacy
    if (padding && packet.type.isEncrypted) {
      final targetBlock = MessagePadding.optimalBlockSize(encoded.length);
      return MessagePadding.pad(encoded, targetBlock);
    }

    return encoded;
  }

  /// Decodes raw wire bytes into a [BitchatPacket].
  /// Handles both padded and unpadded frames.
  static BitchatPacket? decode(Uint8List raw) {
    // Try decoding raw bytes first
    final direct = _decodeCore(raw);
    if (direct != null) return direct;

    // Try decoding with PKCS#7 padding stripped
    final unpadded = MessagePadding.unpad(raw);
    if (unpadded.length != raw.length) {
      return _decodeCore(unpadded);
    }

    return null;
  }

  static BitchatPacket? _decodeCore(Uint8List bytes) {
    if (bytes.length < v1HeaderSize + senderIdSize) return null;

    final reader = BinaryReader(bytes);
    try {
      final version = reader.readUint8();
      if (version != 1 && version != 2) return null;

      final headerSize = version == 2 ? v2HeaderSize : v1HeaderSize;
      final minRequired = headerSize + senderIdSize;
      if (bytes.length < minRequired) return null;

      final typeRaw = reader.readUint8();
      final type = MessageType.fromRaw(typeRaw);
      final ttl = reader.readUint8();
      final timestamp = reader.readUint64();
      final flags = reader.readUint8();

      final hasRecipient = (flags & BitchatPacket.flagHasRecipient) != 0;
      final hasSignature = (flags & BitchatPacket.flagHasSignature) != 0;
      final isCompressed = (flags & BitchatPacket.flagIsCompressed) != 0;
      final hasRoute = (version >= 2) && ((flags & BitchatPacket.flagHasRoute) != 0);
      final isRSR = (flags & BitchatPacket.flagIsRSR) != 0;

      final int payloadLength = version == 2 ? reader.readUint32() : reader.readUint16();
      if (payloadLength < 0) return null;

      final senderId = reader.readBytes(senderIdSize);

      Uint8List? recipientId;
      if (hasRecipient) {
        recipientId = reader.readBytes(recipientIdSize);
      }

      List<Uint8List>? route;
      if (hasRoute) {
        final hopCount = reader.readUint8();
        final hops = <Uint8List>[];
        for (int i = 0; i < hopCount; i++) {
          hops.add(reader.readBytes(senderIdSize));
        }
        route = hops;
      }

      Uint8List payload;
      final lengthFieldBytes = version == 2 ? 4 : 2;

      if (isCompressed) {
        if (payloadLength < lengthFieldBytes) return null;
        final originalSize = version == 2 ? reader.readUint32() : reader.readUint16();
        final compressedSize = payloadLength - lengthFieldBytes;
        if (compressedSize <= 0) return null;

        final compressedBytes = reader.readBytes(compressedSize);
        try {
          final decompressed = Uint8List.fromList(zlib.decode(compressedBytes));
          if (decompressed.length != originalSize) return null;
          payload = decompressed;
        } catch (_) {
          return null; // Decompression failure
        }
      } else {
        payload = reader.readBytes(payloadLength);
      }

      Uint8List? signature;
      if (hasSignature) {
        signature = reader.readBytes(signatureSize);
      }

      return BitchatPacket(
        version: version,
        type: type,
        ttl: ttl,
        timestamp: timestamp,
        senderId: senderId,
        recipientId: recipientId,
        route: route,
        payload: payload,
        signature: signature,
        isCompressed: isCompressed,
        isRSR: isRSR,
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _padOrTruncate(Uint8List src, int targetLength) {
    if (src.length == targetLength) return src;
    if (src.length > targetLength) return src.sublist(0, targetLength);
    final result = Uint8List(targetLength);
    result.setRange(0, src.length, src);
    return result;
  }
}
