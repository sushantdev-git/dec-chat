import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:dec_chat/application/bitchat_coordinator.dart';
import 'package:dec_chat/domain/entities/bitchat_packet.dart';
import 'package:dec_chat/domain/entities/identity_key_pair.dart';
import 'package:dec_chat/domain/enums/message_type.dart';
import 'package:dec_chat/domain/enums/transport_medium.dart';
import 'package:dec_chat/domain/services/announcement_module.dart';
import 'package:dec_chat/domain/services/chat_message_module.dart';
import 'package:dec_chat/domain/services/feature_registry.dart';
import 'package:dec_chat/infrastructure/adapters/simulated_link_adapter.dart';
import 'package:dec_chat/infrastructure/codecs/announcement_codec.dart';

void main() {
  group('AnnouncementModule Unit Tests', () {
    test('handles only MessageType.announce', () {
      final module = AnnouncementModule((_, __, ___) {});
      expect(module.handledTypes, equals({MessageType.announce}));
      expect(module.moduleId, equals('peer_announcements'));
    });

    test('decodes valid announcement payload and invokes callback', () async {
      AnnouncementPayload? receivedPayload;
      Uint8List? receivedSenderId;
      PacketContext? receivedContext;

      final module = AnnouncementModule((payload, senderId, context) {
        receivedPayload = payload;
        receivedSenderId = senderId;
        receivedContext = context;
      });

      final originalPayload = AnnouncementPayload(
        nickname: 'AliceNode',
        noisePublicKey: Uint8List.fromList(List.filled(32, 1)),
        signingPublicKey: Uint8List.fromList(List.filled(32, 2)),
      );
      final encodedBytes = AnnouncementCodec.encode(originalPayload)!;

      final senderPeerId = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44]);
      final packet = BitchatPacket(
        type: MessageType.announce,
        ttl: 7,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        senderId: senderPeerId,
        payload: encodedBytes,
      );
      const context = PacketContext(
        sourceLinkPeerId: 'simulated_peer',
        medium: TransportMedium.bleMesh,
        hops: 1,
      );

      await module.handleInboundPacket(packet, context);

      expect(receivedPayload, isNotNull);
      expect(receivedPayload!.nickname, equals('AliceNode'));
      expect(receivedPayload!.noisePublicKey, equals(originalPayload.noisePublicKey));
      expect(receivedPayload!.signingPublicKey, equals(originalPayload.signingPublicKey));
      expect(receivedSenderId, equals(senderPeerId));
      expect(receivedContext!.hops, equals(1));
      expect(receivedContext!.medium, equals(TransportMedium.bleMesh));
    });

    test('silently discards malformed announcement payloads without throwing', () async {
      bool called = false;
      final module = AnnouncementModule((_, __, ___) {
        called = true;
      });

      final packet = BitchatPacket(
        type: MessageType.announce,
        ttl: 7,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        senderId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        payload: Uint8List.fromList([0xFF, 0xFF]), // Invalid / truncated data
      );
      const context = PacketContext(
        sourceLinkPeerId: 'peer',
        medium: TransportMedium.bleMesh,
        hops: 0,
      );

      await expectLater(module.handleInboundPacket(packet, context), completes);
      expect(called, isFalse);
    });
  });

  group('ChatMessageModule Unit Tests', () {
    test('handles only MessageType.message', () {
      final module = ChatMessageModule((_, __) {});
      expect(module.handledTypes, equals({MessageType.message}));
      expect(module.moduleId, equals('chat_messages'));
    });

    test('dispatches valid message packets to inbound handler', () async {
      BitchatPacket? receivedPacket;
      PacketContext? receivedContext;

      final module = ChatMessageModule((packet, context) {
        receivedPacket = packet;
        receivedContext = context;
      });

      final packet = BitchatPacket(
        type: MessageType.message,
        ttl: 5,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        senderId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        payload: Uint8List.fromList(utf8.encode('Hello World')),
      );
      const context = PacketContext(
        sourceLinkPeerId: 'radio_link_1',
        medium: TransportMedium.nostr,
        hops: 2,
      );

      await module.handleInboundPacket(packet, context);

      expect(receivedPacket, isNotNull);
      expect(utf8.decode(receivedPacket!.payload), equals('Hello World'));
      expect(receivedContext!.medium, equals(TransportMedium.nostr));
      expect(receivedContext!.hops, equals(2));
    });
  });

  group('BitchatCoordinator Presence Announcement Integration Tests', () {
    late SimulatedMeshNetwork network;
    late IdentityKeyPair aliceKeys;
    late IdentityKeyPair bobKeys;
    late SimulatedLinkAdapter aliceAdapter;
    late SimulatedLinkAdapter bobAdapter;
    late BitchatCoordinator aliceCoordinator;
    late BitchatCoordinator bobCoordinator;

    late Completer<AnnouncementPayload> bobReceivedAnnouncement;
    late Completer<BitchatPacket> bobReceivedMessage;

    setUp(() async {
      network = SimulatedMeshNetwork(
        minLatency: const Duration(milliseconds: 1),
        maxLatency: const Duration(milliseconds: 2),
      );

      aliceKeys = await IdentityKeyPair.generate(nickname: 'Alice');
      bobKeys = await IdentityKeyPair.generate(nickname: 'Bob');

      aliceAdapter = SimulatedLinkAdapter(nodeId: aliceKeys.peerIdHex, network: network);
      bobAdapter = SimulatedLinkAdapter(nodeId: bobKeys.peerIdHex, network: network);

      bobReceivedAnnouncement = Completer<AnnouncementPayload>();
      bobReceivedMessage = Completer<BitchatPacket>();

      aliceCoordinator = BitchatCoordinator(
        localPeerId: aliceKeys.peerId,
        transportPort: aliceAdapter,
        keyPair: aliceKeys,
      );

      bobCoordinator = BitchatCoordinator(
        localPeerId: bobKeys.peerId,
        transportPort: bobAdapter,
        keyPair: bobKeys,
        onAnnouncementReceived: (payload, senderId, context) {
          if (!bobReceivedAnnouncement.isCompleted) {
            bobReceivedAnnouncement.complete(payload);
          }
        },
        onMessageReceived: (packet, context) {
          if (!bobReceivedMessage.isCompleted) {
            bobReceivedMessage.complete(packet);
          }
        },
      );

      await aliceCoordinator.start();
      await bobCoordinator.start();

      network.addLink(aliceKeys.peerIdHex, bobKeys.peerIdHex);
    });

    tearDown(() async {
      await aliceCoordinator.stop();
      await bobCoordinator.stop();
      aliceAdapter.dispose();
      bobAdapter.dispose();
      network.clear();
    });

    test('Alice broadcasts presence and Bob discovers Alice with nickname and keys', () async {
      // Alice broadcasts presence
      await aliceCoordinator.broadcastPresence();

      final announcement = await bobReceivedAnnouncement.future.timeout(
        const Duration(seconds: 2),
      );

      expect(announcement.nickname, equals('Alice'));
      expect(announcement.noisePublicKey, equals(aliceKeys.noisePublicKeyBytes));
      expect(announcement.signingPublicKey, equals(aliceKeys.signingPublicKeyBytes));
    });

    test('Alice sends chat message packet and Bob receives it via onMessageReceived', () async {
      await aliceCoordinator.meshEngine.sendBroadcastPacket(
        type: MessageType.message,
        payload: Uint8List.fromList(utf8.encode('Live mesh message')),
      );

      final packet = await bobReceivedMessage.future.timeout(
        const Duration(seconds: 2),
      );

      expect(utf8.decode(packet.payload), equals('Live mesh message'));
      expect(packet.senderId, equals(aliceKeys.peerId));
    });
  });
}
