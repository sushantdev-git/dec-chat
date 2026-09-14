import '../../domain/entities/identity_key_pair.dart';
import '../../domain/enums/transport_medium.dart';

/// Presentation model representing a discovered or connected peer on the network.
class PeerModel {
  final String peerId;
  final String nickname;
  /// Optional phone number broadcast by the peer (Phase 10). Null if not set by peer.
  final String? phoneNumber;
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
    this.phoneNumber,
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

  /// Serializes peer info to Map for local disk persistence.
  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'nickname': nickname,
    'phoneNumber': phoneNumber,
    'noisePublicKey': noisePublicKey,
    'signingPublicKey': signingPublicKey,
    'rssi': rssi,
    'hops': hops,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
    'isDirectNeighbor': isDirectNeighbor,
    'isVerified': isVerified,
    'medium': medium.name,
    'safetyNumber': safetyNumber,
  };

  /// Restores peer info from persistent Map.
  factory PeerModel.fromJson(Map<String, dynamic> json) {
    return PeerModel(
      peerId: json['peerId'] as String,
      nickname: json['nickname'] as String? ?? 'peer',
      phoneNumber: json['phoneNumber'] as String?,
      noisePublicKey: json['noisePublicKey'] as String?,
      signingPublicKey: json['signingPublicKey'] as String?,
      rssi: json['rssi'] as int?,
      hops: json['hops'] as int? ?? 0,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int? ?? 0),
      isDirectNeighbor: json['isDirectNeighbor'] as bool? ?? true,
      isVerified: json['isVerified'] as bool? ?? false,
      medium: TransportMedium.values.firstWhere(
        (m) => m.name == json['medium'],
        orElse: () => TransportMedium.bleMesh,
      ),
      safetyNumber: json['safetyNumber'] as String?,
    );
  }

  /// Formats the safety number into 12 blocks of 5 digits if available.
  String? get formattedSafetyNumber {
    if (safetyNumber == null) return null;
    return IdentityKeyPair.formatSafetyNumber(safetyNumber!);
  }

  /// Truncated 8-character peer identifier for UI badges.
  String get shortPeerId =>
      peerId.length > 8 ? peerId.substring(0, 8) : peerId;

  /// Digits-only version of phone number for search matching (strips spaces, dashes, +).
  String? get phoneDigits =>
      phoneNumber?.replaceAll(RegExp(r'[^\d]'), '');

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
    Object? phoneNumber = _peerSentinel,
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
      phoneNumber: phoneNumber == _peerSentinel ? this.phoneNumber : phoneNumber as String?,
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

const Object _peerSentinel = Object();
