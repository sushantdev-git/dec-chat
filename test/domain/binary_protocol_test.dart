import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:dec_chat/core/utils/binary_reader.dart';
import 'package:dec_chat/core/utils/binary_writer.dart';
import 'package:dec_chat/core/utils/message_padding.dart';
import 'package:dec_chat/domain/entities/bitchat_packet.dart';
import 'package:dec_chat/domain/enums/message_type.dart';
import 'package:dec_chat/infrastructure/codecs/announcement_codec.dart';
import 'package:dec_chat/infrastructure/codecs/binary_protocol_codec.dart';
import 'package:dec_chat/infrastructure/codecs/fragment_codec.dart';

void main() {
  group('BinaryReader & BinaryWriter', () {
    test('round-trips integer primitives in big-endian network byte order', () {
      final writer = BinaryWriter();
      writer.writeUint8(0x42);
      writer.writeUint16(0x1234);
      writer.writeUint32(0x89ABCDEF);
      writer.writeUint64(0x0123456789ABCDEF);
      writer.writeBytes([1, 2, 3, 4]);

      final bytes = writer.toBytes();
      expect(bytes.length, equals(1 + 2 + 4 + 8 + 4));

      final reader = BinaryReader(bytes);
      expect(reader.readUint8(), equals(0x42));
      expect(reader.readUint16(), equals(0x1234));
      expect(reader.readUint32(), equals(0x89ABCDEF));
      expect(reader.readUint64(), equals(0x0123456789ABCDEF));
      expect(reader.readBytes(4), equals(Uint8List.fromList([1, 2, 3, 4])));
      expect(reader.isAtEnd, isTrue);
    });

    test('throws FormatException when reading past buffer length', () {
      final reader = BinaryReader(Uint8List.fromList([1, 2]));
      reader.readUint16();
      expect(() => reader.readUint8(), throwsFormatException);
    });
  });

  group('MessageType Forward-Compatibility', () {
    test('resolves known types correctly', () {
      expect(MessageType.fromRaw(0x01), equals(MessageType.announce));
      expect(MessageType.fromRaw(0x02), equals(MessageType.message));
      expect(MessageType.fromRaw(0x10), equals(MessageType.noiseHandshake));
      expect(MessageType.fromRaw(0x11), equals(MessageType.noiseEncrypted));
      expect(MessageType.fromRaw(0x20), equals(MessageType.fragment));
    });

    test('gracefully captures unknown future types without crashing', () {
      final futureType = MessageType.fromRaw(0x7F);
      expect(futureType.rawValue, equals(0x7F));
      expect(futureType.name, contains('unknown_0x7f'));
    });
  });

  group('MessagePadding (PKCS#7)', () {
    test('pads to target bucket size with matching pad bytes', () {
      final data = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final padded = MessagePadding.pad(data, 6);
      expect(padded.length, equals(6));
      expect(padded, equals(Uint8List.fromList([0xAA, 0xBB, 0xCC, 3, 3, 3])));

      final unpadded = MessagePadding.unpad(padded);
      expect(unpadded, equals(data));
    });

    test('returns original data if padding is corrupted or invalid', () {
      final corrupted = Uint8List.fromList([0xAA, 0xBB, 0xCC, 3, 2, 3]);
      expect(MessagePadding.unpad(corrupted), equals(corrupted));
    });
  });

  group('BitchatPacket & BinaryProtocolCodec', () {
    final senderId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final recipientId = Uint8List.fromList([9, 10, 11, 12, 13, 14, 15, 16]);

    test('encodes and decodes v1 public message packet', () {
      final payload = Uint8List.fromList(utf8.encode('Hello decentralized world!'));
      final packet = BitchatPacket(
        version: 1,
        type: MessageType.message,
        ttl: 7,
        timestamp: 1726300000000,
        senderId: senderId,
        payload: payload,
      );

      final encoded = BinaryProtocolCodec.encode(packet, padding: false);
      expect(encoded, isNotNull);

      final decoded = BinaryProtocolCodec.decode(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.version, equals(1));
      expect(decoded.type, equals(MessageType.message));
      expect(decoded.ttl, equals(7));
      expect(decoded.timestamp, equals(1726300000000));
      expect(decoded.senderId, equals(senderId));
      expect(decoded.recipientId, isNull);
      expect(decoded.payload, equals(payload));
      expect(decoded.hasSignature, isFalse);
    });

    test('encodes and decodes directed packet with recipient and signature', () {
      final payload = Uint8List.fromList([10, 20, 30, 40]);
      final signature = Uint8List(64)..fillRange(0, 64, 0xEE);

      final packet = BitchatPacket(
        version: 1,
        type: MessageType.message,
        ttl: 5,
        timestamp: 1726300000000,
        senderId: senderId,
        recipientId: recipientId,
        signature: signature,
        payload: payload,
      );

      final encoded = BinaryProtocolCodec.encode(packet, padding: false);
      expect(encoded, isNotNull);

      final decoded = BinaryProtocolCodec.decode(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.hasRecipient, isTrue);
      expect(decoded.recipientId, equals(recipientId));
      expect(decoded.hasSignature, isTrue);
      expect(decoded.signature, equals(signature));
      expect(decoded.payload, equals(payload));
    });

    test('encodes and decodes v2 packet with explicit source route', () {
      final hop1 = Uint8List.fromList([1, 1, 1, 1, 1, 1, 1, 1]);
      final hop2 = Uint8List.fromList([2, 2, 2, 2, 2, 2, 2, 2]);
      final payload = Uint8List.fromList([99, 98, 97]);

      final packet = BitchatPacket(
        version: 2,
        type: MessageType.message,
        ttl: 6,
        timestamp: 1726300000000,
        senderId: senderId,
        route: [hop1, hop2],
        payload: payload,
      );

      final encoded = BinaryProtocolCodec.encode(packet, padding: false);
      expect(encoded, isNotNull);

      final decoded = BinaryProtocolCodec.decode(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.version, equals(2));
      expect(decoded.hasRoute, isTrue);
      expect(decoded.route!.length, equals(2));
      expect(decoded.route![0], equals(hop1));
      expect(decoded.route![1], equals(hop2));
    });

    test('handles padded noise encrypted packets', () {
      final payload = Uint8List.fromList(List.generate(100, (i) => i));
      final packet = BitchatPacket(
        version: 1,
        type: MessageType.noiseEncrypted,
        ttl: 7,
        timestamp: 1726300000000,
        senderId: senderId,
        payload: payload,
      );

      // Padded encoding
      final encodedPadded = BinaryProtocolCodec.encode(packet, padding: true);
      expect(encodedPadded, isNotNull);
      // Verify padded to standard block size (256 bytes)
      expect(encodedPadded!.length, equals(256));

      // Decode successfully recovers packet
      final decoded = BinaryProtocolCodec.decode(encodedPadded);
      expect(decoded, isNotNull);
      expect(decoded!.type, equals(MessageType.noiseEncrypted));
      expect(decoded.payload, equals(payload));
    });

    test('forwards unknown message types seamlessly', () {
      final unknownType = MessageType.fromRaw(0x44);
      final payload = Uint8List.fromList([1, 2, 3]);

      final packet = BitchatPacket(
        version: 1,
        type: unknownType,
        ttl: 7,
        timestamp: 1726300000000,
        senderId: senderId,
        payload: payload,
      );

      final encoded = BinaryProtocolCodec.encode(packet, padding: false);
      final decoded = BinaryProtocolCodec.decode(encoded!);

      expect(decoded, isNotNull);
      expect(decoded!.type.rawValue, equals(0x44));
      expect(decoded.payload, equals(payload));
    });

    test('copyForSigning produces unforgeable buffer with TTL=0 and stripped signature', () {
      final signature = Uint8List(64)..fillRange(0, 64, 0xEE);
      final packet = BitchatPacket(
        version: 1,
        type: MessageType.message,
        ttl: 5,
        timestamp: 1726300000000,
        senderId: senderId,
        payload: Uint8List.fromList([1, 2, 3]),
        signature: signature,
        isRSR: true,
      );

      final signingCopy = packet.copyForSigning();
      expect(signingCopy.ttl, equals(0));
      expect(signingCopy.signature, isNull);
      expect(signingCopy.isRSR, isFalse);
      expect(signingCopy.hasSignature, isFalse);
    });
  });

  group('AnnouncementCodec (TLV)', () {
    test('encodes and decodes full announcement payload', () {
      final noiseKey = Uint8List(32)..fillRange(0, 32, 0x01);
      final signingKey = Uint8List(32)..fillRange(0, 32, 0x02);
      final neighbor1 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final neighbor2 = Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]);

      final announcement = AnnouncementPayload(
        nickname: 'Alice',
        noisePublicKey: noiseKey,
        signingPublicKey: signingKey,
        directNeighbors: [neighbor1, neighbor2],
        capabilities: 0x00000007,
        bridgeGeohash: '9q8yy',
      );

      final encoded = AnnouncementCodec.encode(announcement);
      expect(encoded, isNotNull);

      final decoded = AnnouncementCodec.decode(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.nickname, equals('Alice'));
      expect(decoded.noisePublicKey, equals(noiseKey));
      expect(decoded.signingPublicKey, equals(signingKey));
      expect(decoded.directNeighbors!.length, equals(2));
      expect(decoded.directNeighbors![0], equals(neighbor1));
      expect(decoded.directNeighbors![1], equals(neighbor2));
      expect(decoded.capabilities, equals(0x00000007));
      expect(decoded.bridgeGeohash, equals('9q8yy'));
    });

    test('resiliently ignores unknown TLV tags without parse failure', () {
      final noiseKey = Uint8List(32)..fillRange(0, 32, 0x01);
      final signingKey = Uint8List(32)..fillRange(0, 32, 0x02);

      final announcement = AnnouncementPayload(
        nickname: 'Bob',
        noisePublicKey: noiseKey,
        signingPublicKey: signingKey,
      );

      final originalEncoded = AnnouncementCodec.encode(announcement)!;

      // Inject a synthetic unknown TLV tag (Tag 0x99, Length 3, Value [1,2,3])
      final withUnknownTag = Uint8List.fromList([
        ...originalEncoded,
        0x99, 3, 1, 2, 3,
      ]);

      final decoded = AnnouncementCodec.decode(withUnknownTag);
      expect(decoded, isNotNull);
      expect(decoded!.nickname, equals('Bob'));
      expect(decoded.noisePublicKey, equals(noiseKey));
      expect(decoded.signingPublicKey, equals(signingKey));
    });
  });

  group('FragmentCodec', () {
    test('slices large payload and decodes fragments', () {
      final largeData = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final fragmentId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final fragments = FragmentCodec.slice(largeData, fragmentId: fragmentId, maxChunkSize: 469);
      // 1000 bytes with 469 chunk size should produce 3 fragments (469 + 469 + 62)
      expect(fragments.length, equals(3));
      expect(fragments[0].index, equals(0));
      expect(fragments[0].total, equals(3));
      expect(fragments[1].index, equals(1));
      expect(fragments[2].index, equals(2));

      // Encode and decode each fragment
      final reassembledBytes = <int>[];
      for (final frag in fragments) {
        final wireBytes = FragmentCodec.encode(frag);
        final decodedFrag = FragmentCodec.decode(wireBytes);
        expect(decodedFrag, isNotNull);
        expect(decodedFrag!.fragmentId, equals(fragmentId));
        expect(decodedFrag.index, equals(frag.index));
        expect(decodedFrag.total, equals(frag.total));
        reassembledBytes.addAll(decodedFrag.chunk);
      }

      expect(Uint8List.fromList(reassembledBytes), equals(largeData));
    });
  });
}
