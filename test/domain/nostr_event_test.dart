import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dec_chat/domain/entities/bitchat_packet.dart';
import 'package:dec_chat/domain/entities/nostr_event.dart';
import 'package:dec_chat/domain/enums/message_type.dart';
import 'package:dec_chat/domain/enums/nostr_kind.dart';

void main() {
  group('NostrEvent NIP-01 Protocol & Carrier', () {
    final testPubkey = 'a' * 64;

    test('computes canonical NIP-01 event ID via SHA-256', () {
      const createdAt = 1600000000;
      const kind = 1;
      final tags = [
        ['t', 'bitchat_mesh'],
      ];
      const content = 'Hello Nostr Mesh';

      final expectedJson = jsonEncode([0, testPubkey, createdAt, kind, tags, content]);
      final expectedId = crypto.sha256.convert(utf8.encode(expectedJson)).toString();

      final event = NostrEvent.create(
        pubkey: testPubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
      );

      expect(event.id, equals(expectedId));
      expect(event.isValidId, isTrue);
    });

    test('detects tampered event ID as invalid', () {
      final event = NostrEvent.create(
        pubkey: testPubkey,
        createdAt: 1600000000,
        content: 'Original Content',
      );

      expect(event.isValidId, isTrue);

      final tamperedEvent = NostrEvent(
        id: event.id,
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: 'Tampered Content',
        sig: event.sig,
      );

      expect(tamperedEvent.isValidId, isFalse);
    });

    test('round-trips BitchatPacket through Nostr carrier event', () {
      final senderId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final payload = Uint8List.fromList(utf8.encode('Encrypted Mesh Message'));

      final packet = BitchatPacket(
        type: MessageType.announce,
        ttl: 7,
        timestamp: 1600000000000,
        senderId: senderId,
        recipientId: null,
        payload: payload,
      );

      final nostrEvent = NostrEvent.fromBitchatPacket(
        packet: packet,
        pubkeyHex: testPubkey,
      );

      expect(nostrEvent.isBitchatPacket, isTrue);
      expect(nostrEvent.kind, equals(NostrKind.ephemeralCarrier.rawValue));
      expect(nostrEvent.isValidId, isTrue);

      // Unpack packet from Nostr event
      final decodedPacket = nostrEvent.toBitchatPacket();
      expect(decodedPacket, isNotNull);
      expect(decodedPacket!.type, equals(MessageType.announce));
      expect(decodedPacket.senderId, equals(senderId));
      expect(decodedPacket.payload, equals(payload));
    });

    test('embeds and extracts geohash location channel tags correctly', () {
      final packetBytes = Uint8List.fromList([10, 20, 30, 40]);
      final event = NostrEvent.fromPacketBytes(
        packetBytes: packetBytes,
        pubkeyHex: testPubkey,
        geohash: '9q8yy',
      );

      expect(event.geohash, equals('9q8yy'));
      expect(event.getFirstTagValue('g'), equals('9q8yy'));
      expect(event.bitchatPacketBytes, equals(packetBytes));
    });

    test('embeds and extracts recipient public key tags correctly', () {
      final recipientPubkey = 'b' * 64;
      final packetBytes = Uint8List.fromList([50, 60, 70, 80]);
      final event = NostrEvent.fromPacketBytes(
        packetBytes: packetBytes,
        pubkeyHex: testPubkey,
        recipientPubkeyHex: recipientPubkey,
      );

      expect(event.recipientPubkey, equals(recipientPubkey));
      expect(event.bitchatPacketBytes, equals(packetBytes));
    });

    test('serializes and deserializes to/from NIP-01 JSON map', () {
      final original = NostrEvent.create(
        pubkey: testPubkey,
        createdAt: 1670000000,
        kind: NostrKind.locationBroadcast.rawValue,
        tags: [
          ['g', '9q8yy'],
          ['t', 'bitchat_mesh'],
        ],
        content: 'test-payload-base64',
      );

      final jsonMap = original.toJson();
      final reconstructed = NostrEvent.fromJson(jsonMap);

      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.pubkey, equals(original.pubkey));
      expect(reconstructed.createdAt, equals(original.createdAt));
      expect(reconstructed.kind, equals(original.kind));
      expect(reconstructed.tags, equals(original.tags));
      expect(reconstructed.content, equals(original.content));
      expect(reconstructed.sig, equals(original.sig));
    });
  });
}
