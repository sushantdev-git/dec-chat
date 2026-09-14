import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/utils/geohash.dart';
import '../../domain/entities/nostr_event.dart';
import '../../domain/enums/nostr_kind.dart';
import '../../domain/enums/transport_medium.dart';
import '../../domain/ports/transport_port.dart';

/// Factory signature for instantiating WebSocket channels, enabling dependency injection for testing.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// Concrete [TransportPort] adapter implementing Nostr WebSocket relay transport (NIP-01).
///
/// Features:
/// - Multi-relay management and automatic reconnection with backoff
/// - BitChat packet wrapping over NIP-16 ephemeral carriers (kind 20000 / 20001)
/// - Geohash location channel subscriptions (`#g`) with automatic 8-neighbor spatial cell coverage
/// - Tagged directed message routing (`#p`)
/// - Transparent conversion between Nostr carrier events and [TransportPacketEvent]
class NostrRelayAdapter implements TransportPort {
  final List<String> relayUrls;
  final String localPubkeyHex;
  final WebSocketChannelFactory _channelFactory;
  final Duration reconnectDelay;

  final Map<String, WebSocketChannel> _relays = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Set<String> _locationChannels = {};

  final StreamController<TransportPacketEvent> _incomingController =
      StreamController<TransportPacketEvent>.broadcast();

  bool _isRunning = false;

  NostrRelayAdapter({
    required this.relayUrls,
    required this.localPubkeyHex,
    WebSocketChannelFactory? channelFactory,
    this.reconnectDelay = const Duration(seconds: 5),
  }) : _channelFactory = channelFactory ?? ((uri) => WebSocketChannel.connect(uri));

  @override
  TransportMedium get medium => TransportMedium.nostr;

  @override
  Stream<TransportPacketEvent> get incomingPackets => _incomingController.stream;

  @override
  List<String> get connectedPeerIds => _relays.keys.toList();

  @override
  bool get isAvailable => _isRunning && _relays.isNotEmpty;

  /// Set of currently subscribed geohash location channels.
  Set<String> get activeLocationChannels => Set.unmodifiable(_locationChannels);

  @override
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    for (final url in relayUrls) {
      _connectToRelay(url);
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;

    // Cancel all pending reconnect timers
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();

    // Close all subscriptions and channels gracefully
    for (final entry in _relays.entries) {
      final url = entry.key;
      final channel = entry.value;

      try {
        _closeSubscriptionsForRelay(channel);
        channel.sink.close();
      } catch (_) {}

      await _subscriptions[url]?.cancel();
    }

    _subscriptions.clear();
    _relays.clear();
  }

  void _connectToRelay(String url) {
    if (!_isRunning) return;

    try {
      final uri = Uri.parse(url);
      final channel = _channelFactory(uri);
      _relays[url] = channel;

      channel.ready.then((_) {}, onError: (error) {
        _handleRelayFailure(url, error);
      });

      final subscription = channel.stream.listen(
        (message) => _handleIncomingRelayMessage(url, message),
        onError: (error) => _handleRelayFailure(url, error),
        onDone: () => _handleRelayDisconnection(url),
        cancelOnError: true,
      );

      _subscriptions[url] = subscription;

      // Immediately register BitChat protocol subscriptions on this relay
      _sendInitialSubscriptions(channel);
    } catch (error) {
      _handleRelayFailure(url, error);
    }
  }

  void _handleIncomingRelayMessage(String relayUrl, dynamic rawMessage) {
    try {
      final text = rawMessage is String ? rawMessage : utf8.decode(rawMessage as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is! List || decoded.isEmpty) return;

      final messageType = decoded[0] as String;
      if (messageType == 'EVENT') {
        if (decoded.length >= 3 && decoded[2] is Map<String, dynamic>) {
          final eventMap = decoded[2] as Map<String, dynamic>;
          _processInboundEvent(eventMap);
        }
      }
    } catch (_) {
      // Silently ignore corrupted or non-standard relay messages
    }
  }

  void _processInboundEvent(Map<String, dynamic> eventMap) {
    final event = NostrEvent.fromJson(eventMap);

    // Drop our own echoed events
    if (event.pubkey.toLowerCase() == localPubkeyHex.toLowerCase()) {
      return;
    }

    final packetBytes = event.bitchatPacketBytes;
    if (packetBytes != null && packetBytes.isNotEmpty) {
      if (!_incomingController.isClosed) {
        _incomingController.add(TransportPacketEvent(
          packetBytes: packetBytes,
          sourcePeerId: event.pubkey,
          medium: TransportMedium.nostr,
          rssi: null,
        ));
      }
    }
  }

  void _handleRelayFailure(String url, dynamic error) {
    _cleanupRelay(url);
    _scheduleReconnect(url);
  }

  void _handleRelayDisconnection(String url) {
    _cleanupRelay(url);
    _scheduleReconnect(url);
  }

  void _cleanupRelay(String url) {
    _subscriptions[url]?.cancel();
    _subscriptions.remove(url);
    try {
      _relays[url]?.sink.close();
    } catch (_) {}
    _relays.remove(url);
  }

  void _scheduleReconnect(String url) {
    if (!_isRunning) return;
    _reconnectTimers[url]?.cancel();
    _reconnectTimers[url] = Timer(reconnectDelay, () {
      if (_isRunning && !_relays.containsKey(url)) {
        _connectToRelay(url);
      }
    });
  }

  void _sendInitialSubscriptions(WebSocketChannel channel) {
    // 1. Mesh flooding carrier subscription
    final meshReq = jsonEncode([
      'REQ',
      'bitchat_mesh',
      {
        'kinds': [
          NostrKind.ephemeralCarrier.rawValue,
          NostrKind.locationBroadcast.rawValue,
          NostrKind.textNote.rawValue,
        ],
        '#t': ['bitchat_mesh'],
      },
    ]);
    _sendSafe(channel, meshReq);

    // 2. Directed messages addressed to our local public key
    final directReq = jsonEncode([
      'REQ',
      'bitchat_direct',
      {
        'kinds': [
          NostrKind.ephemeralCarrier.rawValue,
          NostrKind.locationBroadcast.rawValue,
          NostrKind.encryptedDirectMessage.rawValue,
        ],
        '#p': [localPubkeyHex.toLowerCase()],
      },
    ]);
    _sendSafe(channel, directReq);

    // 3. Any already-active location channel subscriptions
    for (final geohash in _locationChannels) {
      _sendGeohashSubscription(channel, geohash);
    }
  }

  void _sendGeohashSubscription(WebSocketChannel channel, String geohash) {
    final geoReq = jsonEncode([
      'REQ',
      'bitchat_geo_$geohash',
      {
        'kinds': [
          NostrKind.ephemeralCarrier.rawValue,
          NostrKind.locationBroadcast.rawValue,
          NostrKind.textNote.rawValue,
        ],
        '#g': [geohash.toLowerCase()],
      },
    ]);
    _sendSafe(channel, geoReq);
  }

  void _closeSubscriptionsForRelay(WebSocketChannel channel) {
    _sendSafe(channel, jsonEncode(['CLOSE', 'bitchat_mesh']));
    _sendSafe(channel, jsonEncode(['CLOSE', 'bitchat_direct']));
    for (final geohash in _locationChannels) {
      _sendSafe(channel, jsonEncode(['CLOSE', 'bitchat_geo_$geohash']));
    }
  }

  void _sendSafe(WebSocketChannel channel, String message) {
    try {
      channel.sink.add(message);
    } catch (_) {}
  }

  void _broadcastToAllRelays(String message) {
    for (final channel in _relays.values) {
      _sendSafe(channel, message);
    }
  }

  @override
  Future<void> sendBroadcast(Uint8List packetBytes) async {
    final event = NostrEvent.fromPacketBytes(
      packetBytes: packetBytes,
      pubkeyHex: localPubkeyHex,
      kind: NostrKind.ephemeralCarrier.rawValue,
    );
    final payload = jsonEncode(['EVENT', event.toJson()]);
    _broadcastToAllRelays(payload);
  }

  @override
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes) async {
    final event = NostrEvent.fromPacketBytes(
      packetBytes: packetBytes,
      pubkeyHex: localPubkeyHex,
      recipientPubkeyHex: targetPeerId,
      kind: NostrKind.ephemeralCarrier.rawValue,
    );
    final payload = jsonEncode(['EVENT', event.toJson()]);
    _broadcastToAllRelays(payload);
  }

  /// Broadcasts a packet tagged with a specific [geohash] location channel.
  Future<void> sendLocationBroadcast(String geohash, Uint8List packetBytes) async {
    final event = NostrEvent.fromPacketBytes(
      packetBytes: packetBytes,
      pubkeyHex: localPubkeyHex,
      geohash: geohash,
      kind: NostrKind.locationBroadcast.rawValue,
    );
    final payload = jsonEncode(['EVENT', event.toJson()]);
    _broadcastToAllRelays(payload);
  }

  /// Subscribes to a location channel geohash and optionally its 8 adjacent neighbors.
  void subscribeLocationChannel(String geohash, {bool includeNeighbors = true}) {
    final clean = geohash.trim().toLowerCase();
    final targets = <String>{clean};

    if (includeNeighbors) {
      targets.addAll(Geohash.neighbors(clean));
    }

    final newHashes = targets.difference(_locationChannels);
    _locationChannels.addAll(targets);

    for (final hash in newHashes) {
      for (final channel in _relays.values) {
        _sendGeohashSubscription(channel, hash);
      }
    }
  }

  /// Unsubscribes from a location channel geohash and optionally its 8 adjacent neighbors.
  void unsubscribeLocationChannel(String geohash, {bool includeNeighbors = true}) {
    final clean = geohash.trim().toLowerCase();
    final targets = <String>{clean};

    if (includeNeighbors) {
      targets.addAll(Geohash.neighbors(clean));
    }

    _locationChannels.removeAll(targets);

    for (final hash in targets) {
      final closeFrame = jsonEncode(['CLOSE', 'bitchat_geo_$hash']);
      _broadcastToAllRelays(closeFrame);
    }
  }

  /// Disposes resources and permanently closes stream controllers.
  Future<void> dispose() async {
    await stop();
    await _incomingController.close();
  }
}
