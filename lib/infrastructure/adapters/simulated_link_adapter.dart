import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../domain/enums/transport_medium.dart';
import '../../domain/ports/transport_port.dart';

/// In-memory headless virtual radio medium coordinating multi-node mesh simulations.
///
/// Supports arbitrary network topologies (line, star, ring, clusters), configurable
/// transmission latency, and packet loss emulation.
class SimulatedMeshNetwork {
  final Map<String, SimulatedLinkAdapter> _nodes = {};
  final Map<String, Set<String>> _adjacency = {};

  final Duration minLatency;
  final Duration maxLatency;
  final double packetLossRate;
  final Random _random;

  SimulatedMeshNetwork({
    this.minLatency = const Duration(milliseconds: 2),
    this.maxLatency = const Duration(milliseconds: 10),
    this.packetLossRate = 0.0,
    Random? random,
  }) : _random = random ?? Random();

  /// Registers an adapter node into the virtual radio environment.
  void registerNode(SimulatedLinkAdapter node) {
    _nodes[node.nodeId] = node;
    _adjacency.putIfAbsent(node.nodeId, () => <String>{});
  }

  /// Looks up a registered adapter by node identifier.
  SimulatedLinkAdapter? getNode(String nodeId) => _nodes[nodeId];

  /// Removes an adapter node and tears down its wireless links.
  void unregisterNode(String nodeId) {
    _nodes.remove(nodeId);
    _adjacency.remove(nodeId);
    for (final neighbors in _adjacency.values) {
      neighbors.remove(nodeId);
    }
  }

  /// Creates a bidirectional radio link between two nodes.
  void addLink(String nodeA, String nodeB) {
    _adjacency.putIfAbsent(nodeA, () => <String>{}).add(nodeB);
    _adjacency.putIfAbsent(nodeB, () => <String>{}).add(nodeA);
  }

  /// Removes a radio link between two nodes.
  void removeLink(String nodeA, String nodeB) {
    _adjacency[nodeA]?.remove(nodeB);
    _adjacency[nodeB]?.remove(nodeA);
  }

  /// Configures a multi-hop linear radio topology: A <-> B <-> C <-> D ...
  void createLineTopology(List<String> nodeIds) {
    for (int i = 0; i < nodeIds.length - 1; i++) {
      addLink(nodeIds[i], nodeIds[i + 1]);
    }
  }

  /// Configures a fully-connected mesh where all nodes are in direct 1-hop range of each other.
  void createFullMesh(List<String> nodeIds) {
    for (int i = 0; i < nodeIds.length; i++) {
      for (int j = i + 1; j < nodeIds.length; j++) {
        addLink(nodeIds[i], nodeIds[j]);
      }
    }
  }

  /// Configures a ring topology: Node 0 <-> Node 1 <-> ... <-> Node N-1 <-> Node 0.
  void createRingTopology(List<String> nodeIds) {
    createLineTopology(nodeIds);
    if (nodeIds.length > 2) {
      addLink(nodeIds.first, nodeIds.last);
    }
  }

  /// Retrieves list of adjacent 1-hop neighbor identifiers within radio range.
  List<String> getNeighbors(String nodeId) =>
      List.unmodifiable(_adjacency[nodeId] ?? const <String>[]);

  /// Simulates radio broadcast: delivers packet to all 1-hop adjacent neighbors.
  Future<void> routeBroadcast({
    required String sourceNodeId,
    required Uint8List packetBytes,
  }) async {
    final neighbors = _adjacency[sourceNodeId] ?? <String>{};
    for (final neighborId in neighbors) {
      _dispatchPacket(sourceNodeId, neighborId, packetBytes);
    }
  }

  /// Simulates directed unicast transmission: delivers packet to a specific 1-hop neighbor.
  Future<void> routeDirected({
    required String sourceNodeId,
    required String targetNodeId,
    required Uint8List packetBytes,
  }) async {
    final neighbors = _adjacency[sourceNodeId] ?? <String>{};
    if (neighbors.contains(targetNodeId)) {
      _dispatchPacket(sourceNodeId, targetNodeId, packetBytes);
    }
  }

  void _dispatchPacket(String fromNodeId, String toNodeId, Uint8List packetBytes) {
    // Emulate packet loss
    if (packetLossRate > 0.0 && _random.nextDouble() < packetLossRate) {
      return; // Dropped
    }

    final targetNode = _nodes[toNodeId];
    if (targetNode == null || !targetNode.isAvailable) {
      return;
    }

    // Emulate radio propagation delay
    final latencyMs = minLatency.inMilliseconds +
        _random.nextInt(max(1, maxLatency.inMilliseconds - minLatency.inMilliseconds));

    Timer(Duration(milliseconds: latencyMs), () {
      if (targetNode.isAvailable) {
        targetNode.deliverInbound(packetBytes, fromNodeId);
      }
    });
  }

  /// Clears all nodes and links.
  void clear() {
    _nodes.clear();
    _adjacency.clear();
  }
}

/// Concrete in-memory implementation of [TransportPort] for virtual mesh simulations.
class SimulatedLinkAdapter implements TransportPort {
  final String nodeId;
  final SimulatedMeshNetwork network;

  final StreamController<TransportPacketEvent> _incomingController =
      StreamController<TransportPacketEvent>.broadcast();

  bool _isAvailable = false;

  SimulatedLinkAdapter({
    required this.nodeId,
    required this.network,
  }) {
    network.registerNode(this);
  }

  @override
  TransportMedium get medium => TransportMedium.simulated;

  @override
  Stream<TransportPacketEvent> get incomingPackets => _incomingController.stream;

  @override
  bool get isAvailable => _isAvailable;

  @override
  List<String> get connectedPeerIds => network.getNeighbors(nodeId);

  @override
  Future<void> start() async {
    _isAvailable = true;
  }

  @override
  Future<void> startScan() async {
    _isAvailable = true;
  }

  @override
  Future<void> stop() async {
    _isAvailable = false;
  }

  @override
  Future<void> sendBroadcast(Uint8List packetBytes) async {
    if (!_isAvailable) return;
    await network.routeBroadcast(
      sourceNodeId: nodeId,
      packetBytes: packetBytes,
    );
  }

  @override
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes) async {
    if (!_isAvailable) return;
    await network.routeDirected(
      sourceNodeId: nodeId,
      targetNodeId: targetPeerId,
      packetBytes: packetBytes,
    );
  }

  /// Delivers an inbound packet payload received from a simulated neighbor.
  void deliverInbound(Uint8List packetBytes, String fromNodeId) {
    if (!_isAvailable || _incomingController.isClosed) return;

    _incomingController.add(
      TransportPacketEvent(
        packetBytes: packetBytes,
        sourcePeerId: fromNodeId,
        medium: TransportMedium.simulated,
        rssi: -55,
      ),
    );
  }

  /// Destroys the adapter and closes the stream.
  void dispose() {
    stop();
    network.unregisterNode(nodeId);
    _incomingController.close();
  }
}
