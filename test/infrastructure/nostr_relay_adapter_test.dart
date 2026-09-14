import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/entities/nostr_event.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/domain/enums/nostr_kind.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/infrastructure/adapters/nostr_relay_adapter.dart';
import 'package:grid/infrastructure/codecs/binary_protocol_codec.dart';

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

void main() {
  group('NostrRelayAdapter Transport & Location Channels', () {
    const localPubkey = '1111111111111111111111111111111111111111111111111111111111111111';
    const peerPubkey = '2222222222222222222222222222222222222222222222222222222222222222';
    const relayUrl = 'wss://relay.example.com';

    late MockWebSocketChannel mockChannel;
    late NostrRelayAdapter adapter;

    setUp(() {
      mockChannel = MockWebSocketChannel();
      adapter = NostrRelayAdapter(
        relayUrls: [relayUrl],
        localPubkeyHex: localPubkey,
        channelFactory: (_) => mockChannel,
        reconnectDelay: const Duration(milliseconds: 50),
      );
    });

    tearDown(() async {
      await adapter.stop();
    });

    test('starts and sends initial BitChat subscriptions', () async {
      await adapter.start();

      expect(adapter.isAvailable, isTrue);
      expect(adapter.connectedPeerIds, contains(relayUrl));

      // Check initial subscriptions sent to the relay
      final sentJsonList = mockChannel.sentMessages.map((m) => jsonDecode(m as String)).toList();
      expect(sentJsonList.length, equals(2));

      // 1. Mesh subscription
      expect(sentJsonList[0][0], equals('REQ'));
      expect(sentJsonList[0][1], equals('bitchat_mesh'));
      expect(sentJsonList[0][2]['#t'], contains('bitchat_mesh'));

      // 2. Directed messages subscription
      expect(sentJsonList[1][0], equals('REQ'));
      expect(sentJsonList[1][1], equals('bitchat_direct'));
      expect(sentJsonList[1][2]['#p'], contains(localPubkey));
    });

    test('sendBroadcast wraps packet in ephemeral carrier and sends EVENT frame', () async {
      await adapter.start();
      mockChannel.sentMessages.clear();

      final packet = BitchatPacket(
        type: MessageType.announce,
        ttl: 7,
        timestamp: 1600000000000,
        senderId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        recipientId: null,
        payload: Uint8List.fromList([99, 100]),
      );
      final rawBytes = BinaryProtocolCodec.encode(packet)!;

      await adapter.sendBroadcast(rawBytes);

      expect(mockChannel.sentMessages.length, equals(1));
      final frame = jsonDecode(mockChannel.sentMessages.first as String) as List;
      expect(frame[0], equals('EVENT'));

      final eventMap = frame[1] as Map<String, dynamic>;
      expect(eventMap['kind'], equals(NostrKind.ephemeralCarrier.rawValue));
      expect(eventMap['pubkey'], equals(localPubkey));

      final tags = (eventMap['tags'] as List).cast<List>();
      expect(tags.any((t) => t[0] == 't' && t[1] == 'bitchat_mesh'), isTrue);

      final contentBytes = base64Decode(eventMap['content'] as String);
      expect(contentBytes, equals(rawBytes));
    });

    test('sendDirected wraps packet with recipient pubkey tag', () async {
      await adapter.start();
      mockChannel.sentMessages.clear();

      final packetBytes = Uint8List.fromList([42, 43, 44]);
      await adapter.sendDirected(peerPubkey, packetBytes);

      expect(mockChannel.sentMessages.length, equals(1));
      final frame = jsonDecode(mockChannel.sentMessages.first as String) as List;
      final eventMap = frame[1] as Map<String, dynamic>;

      final tags = (eventMap['tags'] as List).cast<List>();
      expect(tags.any((t) => t[0] == 'p' && t[1] == peerPubkey), isTrue);
    });

    test('sendLocationBroadcast tags geohash and uses locationBroadcast kind', () async {
      await adapter.start();
      mockChannel.sentMessages.clear();

      final packetBytes = Uint8List.fromList([1, 2, 3]);
      await adapter.sendLocationBroadcast('9q8yy', packetBytes);

      expect(mockChannel.sentMessages.length, equals(1));
      final frame = jsonDecode(mockChannel.sentMessages.first as String) as List;
      final eventMap = frame[1] as Map<String, dynamic>;

      expect(eventMap['kind'], equals(NostrKind.locationBroadcast.rawValue));
      final tags = (eventMap['tags'] as List).cast<List>();
      expect(tags.any((t) => t[0] == 'g' && t[1] == '9q8yy'), isTrue);
    });

    test('subscribeLocationChannel subscribes to 9 spatial cells (center + 8 neighbors)', () async {
      await adapter.start();
      mockChannel.sentMessages.clear();

      adapter.subscribeLocationChannel('9q8yy', includeNeighbors: true);

      // 1 center + 8 neighbors = 9 subscriptions sent
      expect(adapter.activeLocationChannels.length, equals(9));
      expect(adapter.activeLocationChannels.contains('9q8yy'), isTrue);
      expect(mockChannel.sentMessages.length, equals(9));

      // Unsubscribe closes all 9 cells
      mockChannel.sentMessages.clear();
      adapter.unsubscribeLocationChannel('9q8yy', includeNeighbors: true);

      expect(adapter.activeLocationChannels.isEmpty, isTrue);
      expect(mockChannel.sentMessages.length, equals(9));
      for (final msg in mockChannel.sentMessages) {
        final frame = jsonDecode(msg as String) as List;
        expect(frame[0], equals('CLOSE'));
      }
    });

    test('processes inbound EVENT frame and emits TransportPacketEvent', () async {
      await adapter.start();

      final inboundPackets = <Uint8List>[];
      final subscription = adapter.incomingPackets.listen((event) {
        expect(event.medium, equals(TransportMedium.nostr));
        expect(event.sourcePeerId, equals(peerPubkey));
        inboundPackets.add(event.packetBytes);
      });

      final originalPayload = Uint8List.fromList([7, 8, 9, 10]);
      final peerEvent = NostrEvent.fromPacketBytes(
        packetBytes: originalPayload,
        pubkeyHex: peerPubkey,
      );

      final inboundFrame = jsonEncode(['EVENT', 'bitchat_mesh', peerEvent.toJson()]);
      mockChannel.controller.add(inboundFrame);

      await Future.delayed(const Duration(milliseconds: 20));
      expect(inboundPackets.length, equals(1));
      expect(inboundPackets.first, equals(originalPayload));

      await subscription.cancel();
    });

    test('drops inbound EVENT frames originating from local public key (echo suppression)', () async {
      await adapter.start();

      var receivedCount = 0;
      final subscription = adapter.incomingPackets.listen((_) => receivedCount++);

      final echoEvent = NostrEvent.fromPacketBytes(
        packetBytes: Uint8List.fromList([1, 2, 3]),
        pubkeyHex: localPubkey, // Same as local pubkey
      );

      final echoFrame = jsonEncode(['EVENT', 'bitchat_mesh', echoEvent.toJson()]);
      mockChannel.controller.add(echoFrame);

      await Future.delayed(const Duration(milliseconds: 20));
      expect(receivedCount, equals(0));

      await subscription.cancel();
    });
  });
}
