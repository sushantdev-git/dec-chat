import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/application/bitchat_coordinator.dart';
import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/entities/courier_envelope.dart';
import 'package:grid/domain/entities/identity_key_pair.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/domain/services/feature_registry.dart';
import 'package:grid/infrastructure/adapters/simulated_link_adapter.dart';

class TestChatModule implements ProtocolFeatureModule {
  final List<BitchatPacket> receivedPackets = [];

  @override
  String get moduleId => 'test_chat';

  @override
  Set<MessageType> get handledTypes => {MessageType.message};

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    receivedPackets.add(packet);
  }
}

void main() {
  group('End-to-End Multi-Node Mesh & Courier DTN Integration Tests', () {
    late SimulatedMeshNetwork network;
    late IdentityKeyPair aliceKeys;
    late IdentityKeyPair bobKeys;
    late IdentityKeyPair charlieKeys;

    late SimulatedLinkAdapter aliceAdapter;
    late SimulatedLinkAdapter bobAdapter;
    late SimulatedLinkAdapter charlieAdapter;

    late BitchatCoordinator aliceCoordinator;
    late BitchatCoordinator bobCoordinator;
    late BitchatCoordinator charlieCoordinator;

    late TestChatModule aliceModule;
    late TestChatModule bobModule;
    late TestChatModule charlieModule;

    setUp(() async {
      network = SimulatedMeshNetwork(
        minLatency: const Duration(milliseconds: 1),
        maxLatency: const Duration(milliseconds: 3),
      );

      aliceKeys = await IdentityKeyPair.generate(nickname: 'Alice');
      bobKeys = await IdentityKeyPair.generate(nickname: 'Bob');
      charlieKeys = await IdentityKeyPair.generate(nickname: 'Charlie');

      aliceAdapter = SimulatedLinkAdapter(
        nodeId: aliceKeys.peerIdHex,
        network: network,
      );
      bobAdapter = SimulatedLinkAdapter(
        nodeId: bobKeys.peerIdHex,
        network: network,
      );
      charlieAdapter = SimulatedLinkAdapter(
        nodeId: charlieKeys.peerIdHex,
        network: network,
      );

      aliceCoordinator = BitchatCoordinator(
        localPeerId: aliceKeys.peerId,
        transportPort: aliceAdapter,
        keyPair: aliceKeys,
      );
      bobCoordinator = BitchatCoordinator(
        localPeerId: bobKeys.peerId,
        transportPort: bobAdapter,
        keyPair: bobKeys,
      );
      charlieCoordinator = BitchatCoordinator(
        localPeerId: charlieKeys.peerId,
        transportPort: charlieAdapter,
        keyPair: charlieKeys,
      );

      aliceModule = TestChatModule();
      bobModule = TestChatModule();
      charlieModule = TestChatModule();

      aliceCoordinator.featureRegistry.registerModule(aliceModule);
      bobCoordinator.featureRegistry.registerModule(bobModule);
      charlieCoordinator.featureRegistry.registerModule(charlieModule);

      await aliceCoordinator.start();
      await bobCoordinator.start();
      await charlieCoordinator.start();
    });

    tearDown(() async {
      await aliceCoordinator.stop();
      await bobCoordinator.stop();
      await charlieCoordinator.stop();
      aliceAdapter.dispose();
      bobAdapter.dispose();
      charlieAdapter.dispose();
      network.clear();
    });

    test('Direct 1-Hop Message delivery between Alice and Bob', () async {
      // Establish direct radio link Alice <-> Bob
      network.addLink(aliceKeys.peerIdHex, bobKeys.peerIdHex);

      // Alice sends a directed chat message to Bob
      await aliceCoordinator.meshEngine.sendDirectedPacket(
        recipientId: bobKeys.peerId,
        type: MessageType.message,
        payload: Uint8List.fromList(utf8.encode('Hello Bob from Alice!')),
      );

      // Allow simulated propagation
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bobModule.receivedPackets.length, equals(1));
      final received = bobModule.receivedPackets.first;
      expect(utf8.decode(received.payload), equals('Hello Bob from Alice!'));
      expect(received.senderId, equals(aliceKeys.peerId));
      expect(received.recipientId, equals(bobKeys.peerId));

      // Alice should not receive her own message
      expect(aliceModule.receivedPackets, isEmpty);
    });

    test('Partitioned Delay-Tolerant Networking (DTN) Courier Delivery via Mobile Data Mule', () async {
      // Initial Topology:
      // Alice is in range of Bob. Charlie is isolated (out of radio range).
      network.addLink(aliceKeys.peerIdHex, bobKeys.peerIdHex);

      // Charlie listens for envelopes delivered to him
      final charlieDeliveredCompleter = Completer<CourierEnvelope>();
      final sub = charlieCoordinator.courierService.onEnvelopeDeliveredToUs.listen((env) {
        if (!charlieDeliveredCompleter.isCompleted) {
          charlieDeliveredCompleter.complete(env);
        }
      });

      // 1. Alice creates a sealed courier envelope intended for Charlie (who is unreachable)
      const secretPayloadText = 'Top secret field reconnaissance for Charlie';
      final secretPayload = Uint8List.fromList(utf8.encode(secretPayloadText));

      aliceCoordinator.courierService.enqueue(
        recipientPeerId: charlieKeys.peerId,
        payload: secretPayload,
        hopBudget: 2, // Allows 1 helper forward + final hop
        customEnvelopeId: 'dtn_env_101',
      );

      expect(aliceCoordinator.courierService.pendingEnvelopeCount, equals(1));

      // 2. Alice encounters Bob (the data mule) and sprays/forwards the courier envelope
      await aliceCoordinator.courierService.onPeerDiscovered(bobKeys.peerIdHex);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Bob's coordinator receives the envelope via CourierModule.
      // Since Bob is NOT Charlie, Bob stores it in his outbox to carry.
      expect(bobCoordinator.courierService.pendingEnvelopeCount, equals(1));
      final muleEnvelope = bobCoordinator.courierService.pendingEnvelopes.first;
      expect(muleEnvelope.envelopeId, equals('dtn_env_101'));
      expect(muleEnvelope.recipientPeerIdHex, equals(charlieKeys.peerIdHex));
      expect(muleEnvelope.hopBudget, equals(1)); // Decremented by 1 during forward

      // 3. Topology change: Bob walks away from Alice and approaches Charlie
      network.removeLink(aliceKeys.peerIdHex, bobKeys.peerIdHex);
      network.addLink(bobKeys.peerIdHex, charlieKeys.peerIdHex);

      // 4. Bob discovers Charlie nearby
      await bobCoordinator.courierService.onPeerDiscovered(charlieKeys.peerIdHex);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 5. Charlie successfully receives and decrypts/unpacks the envelope!
      final deliveredEnvelope = await charlieDeliveredCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      expect(deliveredEnvelope.envelopeId, equals('dtn_env_101'));
      expect(deliveredEnvelope.recipientPeerIdHex, equals(charlieKeys.peerIdHex));
      expect(utf8.decode(deliveredEnvelope.payload), equals(secretPayloadText));

      // Bob's outbox is cleared of the delivered envelope
      expect(bobCoordinator.courierService.pendingEnvelopeCount, equals(0));

      await sub.cancel();
    });

    test('Panic Zeroization Pipeline scrubs identity bytes and purges courier outbox', () async {
      // Alice has envelopes in her outbox
      aliceCoordinator.courierService.enqueue(
        recipientPeerId: bobKeys.peerId,
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(aliceCoordinator.courierService.pendingEnvelopeCount, equals(1));
      expect(aliceAdapter.isAvailable, isTrue);

      // Verify Alice's peerId has non-zero bytes initially
      expect(aliceKeys.peerId.any((b) => b != 0), isTrue);

      // Trigger Panic Wipe on Alice's coordinator
      await aliceCoordinator.panicWipe(activeKeyPair: aliceKeys);

      // Courier outbox is completely wiped
      expect(aliceCoordinator.courierService.pendingEnvelopeCount, equals(0));

      // Transport port is stopped
      expect(aliceAdapter.isAvailable, isFalse);

      // PeerId buffer in memory is completely zeroized
      expect(aliceKeys.peerId.every((b) => b == 0), isTrue);
    });
  });
}
