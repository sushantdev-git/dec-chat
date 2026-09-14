import 'dart:typed_data';
import '../enums/transport_medium.dart';

/// Event payload emitted whenever a raw wire packet is received by a transport link.
class TransportPacketEvent {
  /// Raw binary packet payload as received over the wire.
  final Uint8List packetBytes;

  /// Identifier of the immediate 1-hop link peer that transmitted this packet to us.
  final String sourcePeerId;

  /// Transport medium over which the packet arrived.
  final TransportMedium medium;

  /// Optional radio Received Signal Strength Indicator (RSSI) in dBm.
  final int? rssi;

  const TransportPacketEvent({
    required this.packetBytes,
    required this.sourcePeerId,
    required this.medium,
    this.rssi,
  });
}

/// Abstract port representing an underlying physical or simulated radio link layer.
///
/// Decouples the core mesh routing engine from specific platform radio implementations
/// (BLE, Nostr, Wi-Fi Direct, Headless Simulator).
abstract class TransportPort {
  /// The specific medium implemented by this adapter.
  TransportMedium get medium;

  /// Continuous stream of inbound raw packets received from 1-hop link neighbors.
  Stream<TransportPacketEvent> get incomingPackets;

  /// Broadcasts a packet payload to all connected 1-hop neighbors within radio range.
  Future<void> sendBroadcast(Uint8List packetBytes);

  /// Transmits a directed packet payload to a specific 1-hop link peer.
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes);

  /// List of currently connected or reachable 1-hop peer identifiers.
  List<String> get connectedPeerIds;

  /// Whether this transport medium is currently powered on and operational.
  bool get isAvailable;

  /// Initializes and activates the radio link.
  Future<void> start();

  /// Gracefully tears down the radio link and releases resources.
  Future<void> stop();
}
