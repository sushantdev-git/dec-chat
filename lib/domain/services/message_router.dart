import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

import '../../core/utils/geohash.dart';
import '../../infrastructure/adapters/nostr_relay_adapter.dart';
import '../enums/transport_medium.dart';
import '../ports/transport_port.dart';
import 'location_channel_service.dart';
import 'seen_packet_cache.dart';

/// Routing policies dictating how messages are arbitrated between BLE mesh and Nostr relays.
enum RoutingPolicy {
  /// Intelligently routes based on peer proximity:
  /// - Direct peers reachable on BLE mesh use BLE.
  /// - Remote or unreachable peers fall back to Nostr internet relays.
  /// - Location channels and broadcasts are dispatched across both mediums for maximum reach.
  adaptive,

  /// Pure offline mode: routes exclusively across BLE radio mesh links.
  bleOnly,

  /// Pure internet mode: routes exclusively through Nostr WebSocket relays.
  nostrOnly,

  /// Redundant high-reliability mode: concurrently transmits across both mediums.
  dual,
}

/// Dual-transport coordinator implementing [TransportPort] to bridge local BLE mesh radios
/// and global Nostr internet relays.
///
/// Features:
/// - Seamless policy switching ([RoutingPolicy.adaptive], [RoutingPolicy.bleOnly], etc.)
/// - Automatic inbound deduplication via [SeenPacketCache] to suppress echoes between BLE and Nostr
/// - Geohash location channel routing (`#9q8yy`) with 9-cell spatial coverage
/// - Transparent fallback from BLE to Nostr for distant peers
class MessageRouter implements TransportPort {
  final TransportPort bleTransport;
  final NostrRelayAdapter nostrTransport;
  final LocationChannelService locationService;
  final SeenPacketCache seenCache;

  RoutingPolicy policy;

  final StreamController<TransportPacketEvent> _incomingController =
      StreamController<TransportPacketEvent>.broadcast();

  StreamSubscription<TransportPacketEvent>? _bleSubscription;
  StreamSubscription<TransportPacketEvent>? _nostrSubscription;

  bool _isRunning = false;

  MessageRouter({
    required this.bleTransport,
    required this.nostrTransport,
    LocationChannelService? locationService,
    SeenPacketCache? seenCache,
    this.policy = RoutingPolicy.adaptive,
  })  : locationService = locationService ?? LocationChannelService(),
        seenCache = seenCache ?? SeenPacketCache();

  @override
  TransportMedium get medium => TransportMedium.bleMesh;

  @override
  Stream<TransportPacketEvent> get incomingPackets => _incomingController.stream;

  @override
  List<String> get connectedPeerIds {
    final peers = <String>{
      ...bleTransport.connectedPeerIds,
      ...nostrTransport.connectedPeerIds,
    };
    return peers.toList();
  }

  @override
  bool get isAvailable => bleTransport.isAvailable || nostrTransport.isAvailable;

  bool get isRunning => _isRunning;

  @override
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    if (!bleTransport.isAvailable) {
      await bleTransport.start();
    }
    if (!nostrTransport.isAvailable) {
      await nostrTransport.start();
    }

    _bleSubscription = bleTransport.incomingPackets.listen(
      _handleInboundPacket,
      onError: (err) {},
    );

    _nostrSubscription = nostrTransport.incomingPackets.listen(
      _handleInboundPacket,
      onError: (err) {},
    );
  }

  @override
  Future<void> startScan() async {
    if (!_isRunning) {
      await start();
    }
    seenCache.clear();
    await bleTransport.startScan();
  }

  @override
  Future<void> stop() async {
    _isRunning = false;

    await _bleSubscription?.cancel();
    _bleSubscription = null;

    await _nostrSubscription?.cancel();
    _nostrSubscription = null;

    seenCache.clear();

    await bleTransport.stop();
    await nostrTransport.stop();
  }

  /// Deduplicates and emits inbound packets from either transport medium.
  void _handleInboundPacket(TransportPacketEvent event) {
    final packetHash = _computePacketHash(event.packetBytes);

    // If packet is a duplicate (checkAndAdd returns false), suppress it
    final isNew = seenCache.checkAndAdd(packetHash);
    if (!isNew) {
      return;
    }

    if (!_incomingController.isClosed) {
      _incomingController.add(event);
    }
  }

  /// Computes a deterministic 16-byte hex hash of the packet payload for cross-medium deduplication.
  String _computePacketHash(Uint8List packetBytes) {
    final digest = crypto.sha256.convert(packetBytes).bytes;
    return digest
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  Future<void> sendBroadcast(Uint8List packetBytes) async {
    switch (policy) {
      case RoutingPolicy.bleOnly:
        if (bleTransport.isAvailable) {
          await bleTransport.sendBroadcast(packetBytes).catchError((_) {});
        }
        break;

      case RoutingPolicy.nostrOnly:
        if (nostrTransport.isAvailable) {
          await nostrTransport.sendBroadcast(packetBytes).catchError((_) {});
        }
        break;

      case RoutingPolicy.dual:
        final futures = <Future<void>>[];
        if (bleTransport.isAvailable) {
          futures.add(bleTransport.sendBroadcast(packetBytes).catchError((_) {}));
        }
        if (nostrTransport.isAvailable) {
          futures.add(nostrTransport.sendBroadcast(packetBytes).catchError((_) {}));
        }
        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }
        break;

      case RoutingPolicy.adaptive:
        final futures = <Future<void>>[];
        if (bleTransport.isAvailable) {
          futures.add(bleTransport.sendBroadcast(packetBytes).catchError((_) {}));
        }
        if (nostrTransport.isAvailable) {
          futures.add(nostrTransport.sendBroadcast(packetBytes).catchError((_) {}));
        }
        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }
        break;
    }
  }

  @override
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes) async {
    switch (policy) {
      case RoutingPolicy.bleOnly:
        if (bleTransport.isAvailable) {
          await bleTransport.sendDirected(targetPeerId, packetBytes).catchError((_) {});
        }
        break;

      case RoutingPolicy.nostrOnly:
        if (nostrTransport.isAvailable) {
          await nostrTransport.sendDirected(targetPeerId, packetBytes).catchError((_) {});
        }
        break;

      case RoutingPolicy.dual:
        final futures = <Future<void>>[];
        if (bleTransport.isAvailable) {
          futures.add(bleTransport.sendDirected(targetPeerId, packetBytes).catchError((_) {}));
        }
        if (nostrTransport.isAvailable) {
          futures.add(nostrTransport.sendDirected(targetPeerId, packetBytes).catchError((_) {}));
        }
        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }
        break;

      case RoutingPolicy.adaptive:
        if (bleTransport.connectedPeerIds.contains(targetPeerId)) {
          if (bleTransport.isAvailable) {
            await bleTransport.sendDirected(targetPeerId, packetBytes).catchError((_) {});
          }
        } else if (nostrTransport.isAvailable) {
          await nostrTransport.sendDirected(targetPeerId, packetBytes).catchError((_) {});
        } else if (bleTransport.isAvailable) {
          await bleTransport.sendDirected(targetPeerId, packetBytes).catchError((_) {});
        }
        break;
    }
  }

  /// Sends a packet to a specific location channel (e.g. `#9q8yy`),
  /// broadcasting to nearby local BLE peers and publishing to the Nostr geohash tag.
  Future<void> sendLocationMessage(String channelName, Uint8List packetBytes) async {
    final geohash = Geohash.extractGeohash(channelName);

    switch (policy) {
      case RoutingPolicy.bleOnly:
        if (bleTransport.isAvailable) {
          await bleTransport.sendBroadcast(packetBytes).catchError((_) {});
        }
        break;

      case RoutingPolicy.nostrOnly:
        if (nostrTransport.isAvailable) {
          if (geohash != null) {
            await nostrTransport.sendLocationBroadcast(geohash, packetBytes).catchError((_) {});
          } else {
            await nostrTransport.sendBroadcast(packetBytes).catchError((_) {});
          }
        }
        break;

      case RoutingPolicy.dual:
      case RoutingPolicy.adaptive:
        final futures = <Future<void>>[];
        if (bleTransport.isAvailable) {
          futures.add(bleTransport.sendBroadcast(packetBytes).catchError((_) {}));
        }
        if (nostrTransport.isAvailable) {
          if (geohash != null) {
            futures.add(nostrTransport.sendLocationBroadcast(geohash, packetBytes).catchError((_) {}));
          } else {
            futures.add(nostrTransport.sendBroadcast(packetBytes).catchError((_) {}));
          }
        }
        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }
        break;
    }
  }

  /// Joins a location channel by subscribing to its geohash and 8 neighbor cells on Nostr.
  void joinLocationChannel(String channelName, {bool includeNeighbors = true}) {
    final geohashes = locationService.joinChannel(channelName);
    final centerGeohash = geohashes.first;
    nostrTransport.subscribeLocationChannel(centerGeohash, includeNeighbors: includeNeighbors);
  }

  /// Leaves a location channel and closes its subscriptions on Nostr.
  void leaveLocationChannel(String channelName, {bool includeNeighbors = true}) {
    final geohash = Geohash.extractGeohash(channelName);
    if (geohash != null) {
      locationService.leaveChannel(channelName);
      nostrTransport.unsubscribeLocationChannel(geohash, includeNeighbors: includeNeighbors);
    }
  }

  /// Permanently disposes the router and closes streams.
  Future<void> dispose() async {
    await stop();
    await _incomingController.close();
  }
}
