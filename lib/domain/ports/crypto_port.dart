import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../entities/bitchat_packet.dart';
import '../entities/identity_key_pair.dart';

/// Abstract port for core asymmetric cryptography, packet signing, and peer ID derivation.
abstract class CryptoPort {
  /// Generates a fresh identity key pair (Curve25519 + Ed25519).
  Future<IdentityKeyPair> generateIdentity({required String nickname});

  /// Derives the 8-byte peer ID from a 32-byte Curve25519 static public key:
  /// First 8 bytes of SHA-256(publicKey).
  Uint8List derivePeerId(Uint8List curve25519PublicKey);

  /// Signs a [BitchatPacket] using the provided [signingKeyPair].
  /// Signs the canonical representation where TTL = 0 and signature is stripped.
  Future<Uint8List> signPacket(BitchatPacket packet, SimpleKeyPair signingKeyPair);

  /// Cryptographically verifies a packet's Ed25519 signature against the sender's public key.
  Future<bool> verifyPacketSignature(BitchatPacket packet, Uint8List ed25519PublicKey);
}
