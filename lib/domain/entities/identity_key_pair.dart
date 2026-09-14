import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Represents a node's long-term cryptographic identity.
/// BitChat uses dual asymmetric key pairs:
/// 1. Curve25519 (X25519) key pair for Noise Protocol Diffie-Hellman key agreement.
/// 2. Ed25519 key pair for packet authentication and digital signatures.
class IdentityKeyPair {
  /// Local nickname for presence announcements.
  final String nickname;

  /// Curve25519 static key pair for Noise key agreement.
  final SimpleKeyPair noiseKeyPair;

  /// Curve25519 static public key (32 bytes).
  final SimplePublicKey noisePublicKey;

  /// Ed25519 key pair for digital signatures.
  final SimpleKeyPair signingKeyPair;

  /// Ed25519 public key for signature verification (32 bytes).
  final SimplePublicKey signingPublicKey;

  /// 8-byte persistent peer ID derived from SHA-256(noisePublicKey)[0..8].
  final Uint8List peerId;

  /// Human-readable hex fingerprint of the full SHA-256 hash (Safety Number).
  final String fingerprint;

  IdentityKeyPair({
    required this.nickname,
    required this.noiseKeyPair,
    required this.noisePublicKey,
    required this.signingKeyPair,
    required this.signingPublicKey,
    required this.peerId,
    required this.fingerprint,
  });

  /// Factory method to construct an [IdentityKeyPair] and derive the 8-byte peer ID
  /// and SHA-256 fingerprint matching the BitChat specification.
  static Future<IdentityKeyPair> create({
    required String nickname,
    required SimpleKeyPair noiseKeyPair,
    required SimpleKeyPair signingKeyPair,
  }) async {
    final noisePub = await noiseKeyPair.extractPublicKey();
    final signingPub = await signingKeyPair.extractPublicKey();

    final sha256Digest = crypto.sha256.convert(noisePub.bytes).bytes;
    final peerId = Uint8List.fromList(sha256Digest.sublist(0, 8));
    final fingerprint = sha256Digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return IdentityKeyPair(
      nickname: nickname,
      noiseKeyPair: noiseKeyPair,
      noisePublicKey: noisePub,
      signingKeyPair: signingKeyPair,
      signingPublicKey: signingPub,
      peerId: peerId,
      fingerprint: fingerprint,
    );
  }

  /// Generates a brand new identity with secure random keys.
  static Future<IdentityKeyPair> generate({required String nickname}) async {
    final x25519 = X25519();
    final ed25519 = Ed25519();

    final noiseKey = await x25519.newKeyPair();
    final signingKey = await ed25519.newKeyPair();

    return create(
      nickname: nickname,
      noiseKeyPair: noiseKey,
      signingKeyPair: signingKey,
    );
  }

  /// Serializes private key seeds and metadata to JSON for persistent storage across app restarts.
  Future<Map<String, dynamic>> toJson() async {
    final noisePriv = await noiseKeyPair.extractPrivateKeyBytes();
    final signingPriv = await signingKeyPair.extractPrivateKeyBytes();
    return {
      'version': 1,
      'nickname': nickname,
      'noisePrivateKey': noisePriv,
      'signingPrivateKey': signingPriv,
    };
  }

  /// Reconstructs the exact same persistent IdentityKeyPair from stored private seeds.
  static Future<IdentityKeyPair> fromJson(Map<String, dynamic> json) async {
    final nickname = json['nickname'] as String? ?? 'anon_node';
    final noisePriv = _parseBytes(json['noisePrivateKey']);
    final signingPriv = _parseBytes(json['signingPrivateKey']);

    final x25519 = X25519();
    final ed25519 = Ed25519();

    final noiseKey = await x25519.newKeyPairFromSeed(noisePriv);
    final signingKey = await ed25519.newKeyPairFromSeed(signingPriv);

    return create(
      nickname: nickname,
      noiseKeyPair: noiseKey,
      signingKeyPair: signingKey,
    );
  }

  static List<int> _parseBytes(dynamic value) {
    if (value is List) {
      return value.cast<int>();
    } else if (value is String) {
      if (value.length % 2 == 0 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
        final bytes = <int>[];
        for (int i = 0; i < value.length; i += 2) {
          bytes.add(int.parse(value.substring(i, i + 2), radix: 16));
        }
        return bytes;
      }
    }
    throw ArgumentError('Invalid byte representation: $value');
  }

  /// Formats the fingerprint into Signal-style formatted safety numbers (e.g. groups of 5 digits).
  String get formattedSafetyNumber {
    final clean = fingerprint.toUpperCase();
    final chunks = <String>[];
    for (int i = 0; i < clean.length; i += 4) {
      chunks.add(clean.substring(i, (i + 4 < clean.length) ? i + 4 : clean.length));
    }
    return chunks.join(' ');
  }

  /// 8-byte persistent peer ID encoded as a 16-character lowercase hex string.
  String get peerIdHex =>
      peerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Formats a raw string into 12 blocks of 5 digits separated by spaces.
  static String formatSafetyNumber(String digits) {
    final clean = digits.replaceAll(RegExp(r'\s+'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i += 5) {
      if (i > 0) buffer.write(' ');
      buffer.write(clean.substring(i, (i + 5 < clean.length) ? i + 5 : clean.length));
    }
    return buffer.toString();
  }

  Uint8List get noisePublicKeyBytes => Uint8List.fromList(noisePublicKey.bytes);
  Uint8List get signingPublicKeyBytes => Uint8List.fromList(signingPublicKey.bytes);

  /// Computes a symmetric Signal-style 60-digit safety number between local identity
  /// and a remote peer's Noise public key.
  /// Formatted into twelve 5-digit groups separated by spaces.
  String computeSafetyNumber(Uint8List remoteNoisePublicKeyBytes) {
    final localKey = noisePublicKeyBytes;
    final List<int> sortedKeys;
    if (_compareBytes(localKey, remoteNoisePublicKeyBytes) <= 0) {
      sortedKeys = [...localKey, ...remoteNoisePublicKeyBytes];
    } else {
      sortedKeys = [...remoteNoisePublicKeyBytes, ...localKey];
    }

    final digest = crypto.sha512.convert(sortedKeys).bytes;

    final buffer = StringBuffer();
    for (int i = 0; i < 12; i++) {
      final offset = (i * 4) % (digest.length - 4);
      final value = ByteData.sublistView(Uint8List.fromList(digest)).getUint32(offset, Endian.big) % 100000;
      if (i > 0) buffer.write(' ');
      buffer.write(value.toString().padLeft(5, '0'));
    }
    return buffer.toString();
  }

  static int _compareBytes(Uint8List a, Uint8List b) {
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }
}
