import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:grid/domain/entities/nostr_event.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/domain/services/message_router.dart';
import 'package:grid/infrastructure/adapters/nostr_relay_adapter.dart';

class MockWebSocketSink implements WebSocketSink {
  final MockWebSocketChannel channel;
  final Completer<void> _doneCompleter = Completer<void>();

  MockWebSocketSink(this.channel);

  @override
  void add(dynamic data) {
    channel.sentMessages.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    return Future.value();
  }

  @override
  Future<void> get done => _doneCompleter.future;
}

class MockWebSocketChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final StreamController<dynamic> controller = StreamController<dynamic>.broadcast();
  final List<dynamic> sentMessages = [];
  late final MockWebSocketSink _sink;

  MockWebSocketChannel() {
    _sink = MockWebSocketSink(this);
  }

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();
}

class MockBleTransport implements TransportPort {
  final StreamController<TransportPacketEvent> incomingController =
      StreamController<TransportPacketEvent>.broadcast();
  final List<Uint8List> broadcastsSent = [];
  final List<MapEntry<String, Uint8List>> directedSent = [];

  List<String> mockConnectedPeers = ['ble_peer_1', 'ble_peer_2'];
  bool _available = false;
  bool wasStarted = false;
  bool wasStopped = false;

  @override
  TransportMedium get medium => TransportMedium.bleMesh;

  @override
  Stream<TransportPacketEvent> get incomingPackets => incomingController.stream;

  @override
  List<String> get connectedPeerIds => List.unmodifiable(mockConnectedPeers);

  @override
  bool get isAvailable => _available;

  @override
  Future<void> start() async {
    _available = true;
    wasStarted = true;
  }

  bool wasScanStarted = false;

  @override
  Future<void> startScan() async {
    wasScanStarted = true;
  }

  @override
  Future<void> stop() async {
    wasStopped = true;
  }

  @override
  Future<void> sendBroadcast(Uint8List packetBytes) async {
    broadcastsSent.add(packetBytes);
  }

  @override
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes) async {
    directedSent.add(MapEntry(targetPeerId, packetBytes));
  }
}

void main() {
  group('MessageRouter Dual-Transport Routing & Deduplication', () {
    const localPubkey = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const remotePeerPubkey = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    late MockBleTransport mockBle;
    late MockWebSocketChannel mockWs;
    late NostrRelayAdapter nostrAdapter;
    late MessageRouter router;

    setUp(() async {
      mockBle = MockBleTransport();
      mockWs = MockWebSocketChannel();
      nostrAdapter = NostrRelayAdapter(
        relayUrls: ['wss://relay.test.io'],
        localPubkeyHex: localPubkey,
        channelFactory: (_) => mockWs,
      );

      router = MessageRouter(
        bleTransport: mockBle,
        nostrTransport: nostrAdapter,
        policy: RoutingPolicy.adaptive,
      );

      await router.start();
    });

    tearDown(() async {
      await router.stop();
    });

    test('starts underlying BLE and Nostr transports and aggregates connected peers', () {
      expect(mockBle.wasStarted, isTrue);
      expect(nostrAdapter.isAvailable, isTrue);
      expect(router.isAvailable, isTrue);

      final peers = router.connectedPeerIds;
      expect(peers, contains('ble_peer_1'));
      expect(peers, contains('ble_peer_2'));
      expect(peers, contains('wss://relay.test.io'));
    });

    test('deduplicates identical packet arriving from BLE first then Nostr', () async {
      final receivedPackets = <TransportPacketEvent>[];
      final sub = router.incomingPackets.listen(receivedPackets.add);

      final packetBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      // 1. First arrival via BLE
      mockBle.incomingController.add(TransportPacketEvent(
        packetBytes: packetBytes,
        sourcePeerId: 'ble_peer_1',
        medium: TransportMedium.bleMesh,
      ));

      await Future.delayed(const Duration(milliseconds: 20));
      expect(receivedPackets.length, equals(1));
      expect(receivedPackets.first.medium, equals(TransportMedium.bleMesh));

      // 2. Second arrival via Nostr with the exact same bytes
      final peerEvent = NostrEvent.fromPacketBytes(
        packetBytes: packetBytes,
        pubkeyHex: remotePeerPubkey,
      );
      final inboundFrame = jsonEncode(['EVENT', 'bitchat_mesh', peerEvent.toJson()]);
      mockWs.controller.add(inboundFrame);

      await Future.delayed(const Duration(milliseconds: 20));
      // Cross-transport deduplication should have suppressed the second copy!
      expect(receivedPackets.length, equals(1));

      // 3. Different packet arrives via Nostr
      final differentBytes = Uint8List.fromList([99, 100, 101]);
      final diffEvent = NostrEvent.fromPacketBytes(
        packetBytes: differentBytes,
        pubkeyHex: remotePeerPubkey,
      );
      mockWs.controller.add(jsonEncode(['EVENT', 'bitchat_mesh', diffEvent.toJson()]));

      await Future.delayed(const Duration(milliseconds: 20));
      expect(receivedPackets.length, equals(2));
      expect(receivedPackets[1].packetBytes, equals(differentBytes));
      expect(receivedPackets[1].medium, equals(TransportMedium.nostr));

      await sub.cancel();
    });

    test('adaptive policy routes directed message to BLE if peer is connected', () async {
      final packetBytes = Uint8List.fromList([10, 20, 30]);
      mockWs.sentMessages.clear();

      // 'ble_peer_1' is in mockConnectedPeers
      await router.sendDirected('ble_peer_1', packetBytes);

      expect(mockBle.directedSent.length, equals(1));
      expect(mockBle.directedSent.first.key, equals('ble_peer_1'));
      // Should NOT have sent over Nostr since peer was directly connected on BLE
      expect(mockWs.sentMessages.isEmpty, isTrue);
    });

    test('adaptive policy falls back to Nostr if directed peer is not connected on BLE', () async {
      final packetBytes = Uint8List.fromList([10, 20, 30]);
      mockWs.sentMessages.clear();

      // remotePeerPubkey is NOT in mockBle.connectedPeerIds
      await router.sendDirected(remotePeerPubkey, packetBytes);

      // BLE was skipped
      expect(mockBle.directedSent.isEmpty, isTrue);
      // Nostr fallback was utilized
      expect(mockWs.sentMessages.length, equals(1));
      final frame = jsonDecode(mockWs.sentMessages.first as String) as List;
      expect(frame[0], equals('EVENT'));
      final eventMap = frame[1] as Map<String, dynamic>;
      final tags = (eventMap['tags'] as List).cast<List>();
      expect(tags.any((t) => t[0] == 'p' && t[1] == remotePeerPubkey), isTrue);
    });

    test('adaptive policy dual-publishes broadcast to BLE and Nostr', () async {
      final packetBytes = Uint8List.fromList([55, 66]);
      mockWs.sentMessages.clear();

      await router.sendBroadcast(packetBytes);

      // Sent to BLE
      expect(mockBle.broadcastsSent.length, equals(1));
      expect(mockBle.broadcastsSent.first, equals(packetBytes));

      // Also sent to Nostr mesh
      expect(mockWs.sentMessages.length, equals(1));
      final frame = jsonDecode(mockWs.sentMessages.first as String) as List;
      expect(frame[0], equals('EVENT'));
    });

    test('location message routes to BLE and Nostr with geohash tag', () async {
      final packetBytes = Uint8List.fromList([11, 22, 33]);
      mockWs.sentMessages.clear();

      await router.sendLocationMessage('#9q8yy', packetBytes);

      // Local BLE broadcast
      expect(mockBle.broadcastsSent.length, equals(1));
      expect(mockBle.broadcastsSent.first, equals(packetBytes));

      // Nostr geohash broadcast
      expect(mockWs.sentMessages.length, equals(1));
      final frame = jsonDecode(mockWs.sentMessages.first as String) as List;
      final eventMap = frame[1] as Map<String, dynamic>;
      final tags = (eventMap['tags'] as List).cast<List>();
      expect(tags.any((t) => t[0] == 'g' && t[1] == '9q8yy'), isTrue);
    });

    test('switching routing policies strictly confines transmission mediums', () async {
      final packetBytes = Uint8List.fromList([77, 88]);

      // 1. bleOnly
      router.policy = RoutingPolicy.bleOnly;
      mockBle.broadcastsSent.clear();
      mockWs.sentMessages.clear();

      await router.sendBroadcast(packetBytes);
      expect(mockBle.broadcastsSent.length, equals(1));
      expect(mockWs.sentMessages.isEmpty, isTrue);

      // 2. nostrOnly
      router.policy = RoutingPolicy.nostrOnly;
      mockBle.broadcastsSent.clear();
      mockWs.sentMessages.clear();

      await router.sendBroadcast(packetBytes);
      expect(mockBle.broadcastsSent.isEmpty, isTrue);
      expect(mockWs.sentMessages.length, equals(1));
    });

    test('joining and leaving location channel propagates 9-cell subscriptions to Nostr', () {
      mockWs.sentMessages.clear();

      router.joinLocationChannel('#9q8yy');
      expect(router.locationService.isJoined('#9q8yy'), isTrue);
      expect(nostrAdapter.activeLocationChannels.length, equals(9));
      expect(mockWs.sentMessages.length, equals(9));

      mockWs.sentMessages.clear();
      router.leaveLocationChannel('#9q8yy');
      expect(router.locationService.isJoined('#9q8yy'), isFalse);
      expect(nostrAdapter.activeLocationChannels.isEmpty, isTrue);
      expect(mockWs.sentMessages.length, equals(9));
    });

    test('startScan triggers active BLE scanning and clears deduplication cache', () async {
      await router.start();
      router.seenCache.checkAndAdd('cached_packet_hash');
      expect(router.seenCache.size, equals(1));

      expect(mockBle.wasScanStarted, isFalse);
      await router.startScan();
      expect(mockBle.wasScanStarted, isTrue);
      expect(router.seenCache.size, equals(0));
    });
  });
}
