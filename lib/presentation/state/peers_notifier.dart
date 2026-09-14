import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/enums/transport_medium.dart';
import '../models/peer_model.dart';

/// State holding all discovered and verified peers on the network.
class PeersState {
  final Map<String, PeerModel> peers;

  const PeersState({this.peers = const {}});

  List<PeerModel> get allPeers => peers.values.toList()
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  List<PeerModel> get directPeers =>
      peers.values.where((p) => p.isDirectNeighbor).toList();

  List<PeerModel> get verifiedPeers =>
      peers.values.where((p) => p.isVerified).toList();

  PeerModel? getPeer(String peerId) => peers[peerId.toLowerCase()];

  PeersState copyWith({Map<String, PeerModel>? peers}) {
    return PeersState(peers: peers ?? this.peers);
  }
}

/// StateNotifier managing peer discovery, signal strengths, and safety verification.
class PeersNotifier extends StateNotifier<PeersState> {
  PeersNotifier([PeersState? initial]) : super(initial ?? const PeersState());

  /// Updates or registers a peer presence announcement.
  void updatePresence({
    required String peerId,
    required String nickname,
    String? noisePublicKey,
    String? signingPublicKey,
    int? rssi,
    int hops = 0,
    TransportMedium medium = TransportMedium.bleMesh,
    String? safetyNumber,
  }) {
    final cleanId = peerId.toLowerCase();
    final existing = state.peers[cleanId];

    final updated = PeerModel(
      peerId: cleanId,
      nickname: nickname.trim().isNotEmpty ? nickname : (existing?.nickname ?? cleanId.substring(0, 8)),
      noisePublicKey: noisePublicKey ?? existing?.noisePublicKey,
      signingPublicKey: signingPublicKey ?? existing?.signingPublicKey,
      rssi: rssi ?? existing?.rssi,
      hops: hops,
      lastSeen: DateTime.now(),
      isDirectNeighbor: hops == 0,
      isVerified: existing?.isVerified ?? false,
      medium: medium,
      safetyNumber: safetyNumber ?? existing?.safetyNumber,
    );

    final newMap = Map<String, PeerModel>.from(state.peers);
    newMap[cleanId] = updated;
    state = state.copyWith(peers: newMap);
  }

  /// Toggles whether a peer is marked as cryptographically verified via safety numbers.
  void toggleVerification(String peerId) {
    final cleanId = peerId.toLowerCase();
    final existing = state.peers[cleanId];
    if (existing == null) return;

    final updated = existing.copyWith(isVerified: !existing.isVerified);
    final newMap = Map<String, PeerModel>.from(state.peers);
    newMap[cleanId] = updated;
    state = state.copyWith(peers: newMap);
  }

  /// Emergency panic wipe: clears all discovered peers from volatile memory.
  void clear() {
    state = const PeersState(peers: {});
  }
}

/// Global provider for network peers.
final peersProvider = StateNotifierProvider<PeersNotifier, PeersState>((ref) {
  return PeersNotifier();
});
