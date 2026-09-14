import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/services/feature_registry.dart';
import 'package:grid/domain/services/mesh_engine.dart';
import 'package:grid/domain/services/seen_packet_cache.dart';
import 'package:grid/infrastructure/adapters/simulated_link_adapter.dart';
import 'package:grid/infrastructure/codecs/binary_protocol_codec.dart';

/// Test feature module that captures inbound packets for test assertions.
class MockChatFeatureModule implements ProtocolFeatureModule {
  @override
  final String moduleId;
  @override
  final Set<MessageType> handledTypes;

  final List<BitchatPacket> receivedPackets = [];
  final List<PacketContext> receivedContexts = [];

  MockChatFeatureModule({
    this.moduleId = 'mock_chat',
    Set<MessageType>? handledTypes,
  }) : handledTypes = handledTypes ?? {MessageType.message};

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    receivedPackets.add(packet);
    receivedContexts.add(context);
  }

  void clear() {
    receivedPackets.clear();
    receivedContexts.clear();
  }
}

void main() {
  group('SeenPacketCache (Deduplication LRU)', () {
    test('marks new packets and identifies duplicates within TTL', () {
      final cache = SeenPacketCache(capacity: 5, ttl: const Duration(minutes: 5));

      expect(cache.checkAndAdd('packet_1'), isTrue);
      expect(cache.checkAndAdd('packet_2'), isTrue);
      expect(cache.size, 2);

      // Duplicate detection
      expect(cache.checkAndAdd('packet_1'), isFalse);
      expect(cache.checkAndAdd('packet_2'), isFalse);
      expect(cache.size, 2);
    });

    test('evicts oldest entries when capacity is exceeded', () {
      final cache = SeenPacketCache(capacity: 3, ttl: const Duration(minutes: 5));

      cache.checkAndAdd('p1');
      cache.checkAndAdd('p2');
      cache.checkAndAdd('p3');
      expect(cache.size, 3);

      // Adding 4th entry evicts oldest (p1)
      cache.checkAndAdd('p4');
      expect(cache.size, 3);
      expect(cache.contains('p1'), isFalse);
      expect(cache.contains('p2'), isTrue);
      expect(cache.contains('p4'), isTrue);
    });

    test('prunes expired entries based on TTL', () {
      final cache = SeenPacketCache(capacity: 10, ttl: const Duration(seconds: 10));
      final baseTime = DateTime(2026, 1, 1, 12, 0, 0);

      cache.checkAndAdd('p1', currentTime: baseTime);
      expect(cache.contains('p1', currentTime: baseTime), isTrue);

      // 15 seconds later -> expired
      final futureTime = baseTime.add(const Duration(seconds: 15));
      expect(cache.contains('p1', currentTime: futureTime), isFalse);
      expect(cache.checkAndAdd('p1', currentTime: futureTime), isTrue,
          reason: 'Expired packet should be treated as fresh');
    });
  });

  group('ProtocolFeatureRegistry', () {
    test('routes handled message types to corresponding modules', () async {
      final registry = ProtocolFeatureRegistry();
      final chatModule = MockChatFeatureModule(handledTypes: {MessageType.message});
      registry.registerModule(chatModule);

      expect(registry.canHandle(MessageType.message), isTrue);
      expect(registry.canHandle(MessageType.noiseEncrypted), isFalse);

      final packet = BitchatPacket(
        type: MessageType.message,
        ttl: 7,
        timestamp: 1718000000000,
        senderId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        payload: Uint8List.fromList(utf8.encode('Hello World')),
      );

      const context = PacketContext(
        sourceLinkPeerId: 'peer_abc',
        medium: TransportMedium.simulated,
        hops: 2,
      );

      final handled = await registry.dispatch(packet, context);
      expect(handled, isTrue);
      expect(chatModule.receivedPackets.length, 1);
      expect(utf8.decode(chatModule.receivedPackets.first.payload), 'Hello World');
    });

    test('forward-compatibility: gracefully skips unhandled message types', () async {
      final registry = ProtocolFeatureRegistry();
      final packet = BitchatPacket(
        type: MessageType.fromRaw(0xFE), // Unknown future type
        ttl: 7,
        timestamp: 1718000000000,
        senderId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        payload: Uint8List(0),
      );

      const context = PacketContext(
        sourceLinkPeerId: 'peer_xyz',
        medium: TransportMedium.simulated,
        hops: 1,
      );

      final handled = await registry.dispatch(packet, context);
      expect(handled, isFalse);
    });
  });

  group('MeshEngine Routing Rules & Controlled Flooding', () {
    test('TTL clamping caps broadcast TTL to 5 when peer density >= 6', () async {
      final network = SimulatedMeshNetwork();
      final localPeerId = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1]);
      final adapter = SimulatedLinkAdapter(nodeId: 'node_1', network: network);
      final registry = ProtocolFeatureRegistry();

      final engine = MeshEngine(
        localPeerId: localPeerId,
        transportPort: adapter,
        featureRegistry: registry,
        clampedTtl: 5,
        highDensityThreshold: 6,
        minJitter: const Duration(milliseconds: 1),
        maxJitter: const Duration(milliseconds: 2),
      );

      await engine.start();

      // Connect 6 neighbors to node_1 (dense cluster)
      for (int i = 2; i <= 7; i++) {
        final neighborAdapter = SimulatedLinkAdapter(nodeId: 'node_$i', network: network);
        await neighborAdapter.start();
        network.addLink('node_1', 'node_$i');
      }

      // Deliver inbound packet with incoming TTL = 7 from node_2
      final inboundPacket = BitchatPacket(
        type: MessageType.message,
        ttl: 7,
        timestamp: 1000,
        senderId: Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]),
        payload: Uint8List.fromList(utf8.encode('Dense broadcast')),
      );

      // Intercept relayed packet at node_3
      final node3Adapter = network.getNode('node_3')!;
      final completer = Completer<BitchatPacket>();
      final sub = node3Adapter.incomingPackets.listen((event) {
        final decoded = BinaryProtocolCodec.decode(event.packetBytes);
        if (decoded != null && !completer.isCompleted) completer.complete(decoded);
      });

      // Deliver inbound to node_1 from node_2
      final encodedInbound = BinaryProtocolCodec.encode(inboundPacket)!;
      adapter.deliverInbound(encodedInbound, 'node_2');

      final relayed = await completer.future.timeout(const Duration(seconds: 1));
      // In high density (6 neighbors), TTL 7 clamped to 5!
      expect(relayed.ttl, 5);

      await engine.stop();
      await sub.cancel();
    });

    test('packet originating from local node is not relayed back (no echo)', () async {
      final network = SimulatedMeshNetwork();
      final localPeerId = Uint8List.fromList([1, 1, 1, 1, 1, 1, 1, 1]);
      final adapter = SimulatedLinkAdapter(nodeId: 'node_local', network: network);
      final registry = ProtocolFeatureRegistry();

      final engine = MeshEngine(
        localPeerId: localPeerId,
        transportPort: adapter,
        featureRegistry: registry,
      );

      await engine.start();

      final ownPacket = BitchatPacket(
        type: MessageType.message,
        ttl: 5,
        timestamp: 2000,
        senderId: localPeerId, // Originated by self!
        payload: Uint8List.fromList(utf8.encode('Echo check')),
      );

      // Deliver it as if echoed back from neighbor
      final encodedOwn = BinaryProtocolCodec.encode(ownPacket)!;
      adapter.deliverInbound(encodedOwn, 'node_neighbor');

      await Future.delayed(const Duration(milliseconds: 20));
      expect(engine.pendingRelayCount, 0);
      await engine.stop();
    });
  });

  group('10-Node Virtual Mesh Network Simulation', () {
    test('Scenario A: 10-node linear chain multi-hop delivery (1 -> 2 -> ... -> 10)', () async {
      final network = SimulatedMeshNetwork(
        minLatency: const Duration(milliseconds: 1),
        maxLatency: const Duration(milliseconds: 4),
      );

      final List<MeshEngine> engines = [];
      final List<MockChatFeatureModule> modules = [];
      final List<String> nodeIds = List.generate(10, (i) => 'node_${i + 1}');

      // Instantiate 10 nodes
      for (int i = 0; i < 10; i++) {
        final peerId = Uint8List.fromList(List.filled(8, i + 1));
        final adapter = SimulatedLinkAdapter(nodeId: nodeIds[i], network: network);
        final registry = ProtocolFeatureRegistry();
        final module = MockChatFeatureModule();
        registry.registerModule(module);

        final engine = MeshEngine(
          localPeerId: peerId,
          transportPort: adapter,
          featureRegistry: registry,
          minJitter: const Duration(milliseconds: 2),
          maxJitter: const Duration(milliseconds: 5),
        );

        engines.add(engine);
        modules.add(module);
        await engine.start();
      }

      // Configure linear topology: 1 <-> 2 <-> 3 <-> 4 <-> 5 <-> 6 <-> 7 <-> 8 <-> 9 <-> 10
      network.createLineTopology(nodeIds);

      // Node 1 originates a broadcast chat message
      const testMessage = 'Hello 10-hop mesh!';
      await engines[0].sendBroadcastPacket(
        type: MessageType.message,
        payload: Uint8List.fromList(utf8.encode(testMessage)),
      );

      // Wait for propagation through the 9 hops
      // 9 hops * ~5ms = ~45ms; allow up to 600ms for jitter and propagation
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify delivery at intermediate and destination nodes
      // Node 1 (originator): shouldn't deliver to self via feature module because it was outbound
      expect(modules[0].receivedPackets.length, 0);

      // Node 2 (direct neighbor)
      expect(modules[1].receivedPackets.length, 1);
      expect(utf8.decode(modules[1].receivedPackets.first.payload), testMessage);
      expect(modules[1].receivedContexts.first.hops, 0);

      // Node 5 (3 relays away)
      expect(modules[4].receivedPackets.length, 1);
      expect(utf8.decode(modules[4].receivedPackets.first.payload), testMessage);
      expect(modules[4].receivedContexts.first.hops, 3);

      // Node 8 (6 relays away, final hop before TTL exhaustion)
      expect(modules[7].receivedPackets.length, 1);
      expect(utf8.decode(modules[7].receivedPackets.first.payload), testMessage);
      expect(modules[7].receivedContexts.first.hops, 6);
      expect(modules[7].receivedPackets.first.ttl, 1);

      // Node 9 & 10: TTL is exhausted at Node 8 (TTL=1 cannot relay), so never reached!
      expect(modules[8].receivedPackets.length, 0,
          reason: 'TTL=7 properly exhausted after 6 relays (Node 8)');
      expect(modules[9].receivedPackets.length, 0,
          reason: 'Node 10 is beyond TTL reach in 10-hop line');

      // Cleanup
      for (final engine in engines) {
        await engine.stop();
      }
    });

    test('Scenario B: Ring topology deduplication prevents infinite relay loops', () async {
      final network = SimulatedMeshNetwork(
        minLatency: const Duration(milliseconds: 1),
        maxLatency: const Duration(milliseconds: 3),
      );

      final List<MeshEngine> engines = [];
      final List<MockChatFeatureModule> modules = [];
      final List<String> nodeIds = List.generate(6, (i) => 'ring_node_${i + 1}');

      for (int i = 0; i < 6; i++) {
        final peerId = Uint8List.fromList(List.filled(8, i + 10));
        final adapter = SimulatedLinkAdapter(nodeId: nodeIds[i], network: network);
        final registry = ProtocolFeatureRegistry();
        final module = MockChatFeatureModule();
        registry.registerModule(module);

        final engine = MeshEngine(
          localPeerId: peerId,
          transportPort: adapter,
          featureRegistry: registry,
          minJitter: const Duration(milliseconds: 2),
          maxJitter: const Duration(milliseconds: 6),
        );

        engines.add(engine);
        modules.add(module);
        await engine.start();
      }

      // Configure Ring: 1 <-> 2 <-> 3 <-> 4 <-> 5 <-> 6 <-> 1
      network.createRingTopology(nodeIds);

      // Node 1 originates broadcast
      await engines[0].sendBroadcastPacket(
        type: MessageType.message,
        payload: Uint8List.fromList(utf8.encode('Ring message')),
      );

      // Allow plenty of time for messages to circulate around the ring
      await Future.delayed(const Duration(milliseconds: 300));

      // In a circular mesh, without deduplication, packets would loop forever!
      // Verify that every node received the packet EXACTLY ONCE:
      for (int i = 1; i < 6; i++) {
        expect(modules[i].receivedPackets.length, 1,
            reason: 'Node ${i + 1} must receive ring packet exactly once due to deduplication');
      }

      // Verify all engines settled to 0 pending relays
      for (final engine in engines) {
        expect(engine.pendingRelayCount, 0);
      }

      for (final engine in engines) {
        await engine.stop();
      }
    });

    test('Scenario C: Directed delivery stops relaying once destination is reached', () async {
      final network = SimulatedMeshNetwork(
        minLatency: const Duration(milliseconds: 1),
        maxLatency: const Duration(milliseconds: 3),
      );

      final List<MeshEngine> engines = [];
      final List<MockChatFeatureModule> modules = [];
      final List<String> nodeIds = ['src_1', 'relay_2', 'relay_3', 'dest_4', 'past_5'];

      for (int i = 0; i < 5; i++) {
        final peerId = Uint8List.fromList(List.filled(8, i + 20));
        final adapter = SimulatedLinkAdapter(nodeId: nodeIds[i], network: network);
        final registry = ProtocolFeatureRegistry();
        final module = MockChatFeatureModule();
        registry.registerModule(module);

        final engine = MeshEngine(
          localPeerId: peerId,
          transportPort: adapter,
          featureRegistry: registry,
          minJitter: const Duration(milliseconds: 2),
          maxJitter: const Duration(milliseconds: 4),
        );

        engines.add(engine);
        modules.add(module);
        await engine.start();
      }

      // Line: src_1 <-> relay_2 <-> relay_3 <-> dest_4 <-> past_5
      network.createLineTopology(nodeIds);

      final destPeerId = engines[3].localPeerId;

      // Send directed packet to dest_4
      await engines[0].sendDirectedPacket(
        recipientId: destPeerId,
        type: MessageType.message,
        payload: Uint8List.fromList(utf8.encode('Private for dest_4 only')),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Intermediate relays (relay_2 and relay_3) did NOT dispatch to their own feature modules
      // because recipientId does not match them!
      expect(modules[1].receivedPackets.length, 0);
      expect(modules[2].receivedPackets.length, 0);

      // Destination node dest_4 received it!
      expect(modules[3].receivedPackets.length, 1);
      expect(utf8.decode(modules[3].receivedPackets.first.payload), 'Private for dest_4 only');

      // past_5 must NOT receive it because dest_4 stopped the relay upon arrival!
      expect(modules[4].receivedPackets.length, 0,
          reason: 'Target destination must not forward directed packets further');

      for (final engine in engines) {
        await engine.stop();
      }
    });
  });
}
