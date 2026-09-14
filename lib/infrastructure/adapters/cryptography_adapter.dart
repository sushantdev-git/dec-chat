import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../../domain/entities/bitchat_packet.dart';
import '../../domain/entities/identity_key_pair.dart';
import '../../domain/ports/crypto_port.dart';
import '../codecs/binary_protocol_codec.dart';

/// Concrete implementation of [CryptoPort] using `package:cryptography`.
class CryptographyAdapter implements CryptoPort {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();

  @override
  Future<IdentityKeyPair> generateIdentity({required String nickname}) async {
    final noiseKeyPair = await _x25519.newKeyPair();
    final signingKeyPair = await _ed25519.newKeyPair();

    return IdentityKeyPair.create(
      nickname: nickname,
      noiseKeyPair: noiseKeyPair,
      signingKeyPair: signingKeyPair,
    );
  }

  @override
  Uint8List derivePeerId(Uint8List curve25519PublicKey) {
    final digest = crypto.sha256.convert(curve25519PublicKey).bytes;
    return Uint8List.fromList(digest.sublist(0, 8));
  }

  @override
  Future<Uint8List> signPacket(BitchatPacket packet, SimpleKeyPair signingKeyPair) async {
    // 1. Create unforgeable canonical representation with TTL=0 and no signature
    final canonicalPacket = packet.copyForSigning();
    final canonicalBytes = BinaryProtocolCodec.encode(canonicalPacket, padding: false);
    if (canonicalBytes == null) {
      throw StateError('Failed to serialize canonical packet for signing');
    }

    // 2. Compute 64-byte Ed25519 signature
    final sig = await _ed25519.sign(canonicalBytes, keyPair: signingKeyPair);
    return Uint8List.fromList(sig.bytes);
  }

  @override
  Future<bool> verifyPacketSignature(BitchatPacket packet, Uint8List ed25519PublicKey) async {
    final sig = packet.signature;
    if (sig == null || sig.length != 64) {
      return false;
    }

    final canonicalPacket = packet.copyForSigning();
    final canonicalBytes = BinaryProtocolCodec.encode(canonicalPacket, padding: false);
    if (canonicalBytes == null) return false;

    try {
      final signatureObj = Signature(
        sig,
        publicKey: SimplePublicKey(ed25519PublicKey, type: KeyPairType.ed25519),
      );
      return await _ed25519.verify(canonicalBytes, signature: signatureObj);
    } catch (_) {
      return false;
    }
  }
}
