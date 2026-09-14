import '../../domain/entities/identity_key_pair.dart';
import '../../domain/enums/transport_medium.dart';

/// Presentation model representing a discovered or connected peer on the network.
class PeerModel {
  final String peerId;
  final String nickname;
  final String? noisePublicKey;
  final String? signingPublicKey;
  final int? rssi;
  final int hops;
  final DateTime lastSeen;
  final bool isDirectNeighbor;
  final bool isVerified;
  final TransportMedium medium;
  final String? safetyNumber;

  const PeerModel({
    required this.peerId,
    required this.nickname,
    this.noisePublicKey,
    this.signingPublicKey,
    this.rssi,
    this.hops = 0,
    required this.lastSeen,
    this.isDirectNeighbor = true,
    this.isVerified = false,
    this.medium = TransportMedium.bleMesh,
    this.safetyNumber,
  });

  /// Formats the safety number into 12 blocks of 5 digits if available.
  String? get formattedSafetyNumber {
    if (safetyNumber == null) return null;
    return IdentityKeyPair.formatSafetyNumber(safetyNumber!);
  }

  /// Truncated 8-character peer identifier for UI badges.
  String get shortPeerId =>
      peerId.length > 8 ? peerId.substring(0, 8) : peerId;

  /// User-friendly signal quality indicator.
  String get signalQuality {
    if (rssi == null) return 'Internet / Relay';
    if (rssi! >= -60) return 'Excellent';
    if (rssi! >= -75) return 'Good';
    if (rssi! >= -85) return 'Fair';
    return 'Weak';
  }

  PeerModel copyWith({
    String? peerId,
    String? nickname,
    String? noisePublicKey,
    String? signingPublicKey,
    int? rssi,
    int? hops,
    DateTime? lastSeen,
    bool? isDirectNeighbor,
    bool? isVerified,
    TransportMedium? medium,
    String? safetyNumber,
  }) {
    return PeerModel(
      peerId: peerId ?? this.peerId,
      nickname: nickname ?? this.nickname,
      noisePublicKey: noisePublicKey ?? this.noisePublicKey,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      rssi: rssi ?? this.rssi,
      hops: hops ?? this.hops,
      lastSeen: lastSeen ?? this.lastSeen,
      isDirectNeighbor: isDirectNeighbor ?? this.isDirectNeighbor,
      isVerified: isVerified ?? this.isVerified,
      medium: medium ?? this.medium,
      safetyNumber: safetyNumber ?? this.safetyNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerModel && runtimeType == other.runtimeType && peerId == other.peerId;

  @override
  int get hashCode => peerId.hashCode;
}
