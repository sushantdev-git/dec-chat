import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'noise_cipher_state.dart';

/// Implements the Noise Protocol framework SymmetricState abstraction.
///
/// Encapsulates a [NoiseCipherState] along with the chaining key (ck)
/// and handshake hash (h), maintaining cryptographic state transitions across
/// handshake patterns.
class NoiseSymmetricState {
  static const int hashLength = 32;

  late NoiseCipherState cipherState;
  late Uint8List ck;
  late Uint8List h;

  NoiseSymmetricState.initialize(String protocolName) {
    _initializeSymmetric(protocolName);
  }

  void _initializeSymmetric(String protocolName) {
    final nameBytes = utf8.encode(protocolName);
    if (nameBytes.length <= hashLength) {
      h = Uint8List(hashLength);
      h.setRange(0, nameBytes.length, nameBytes);
    } else {
      h = Uint8List.fromList(crypto.sha256.convert(nameBytes).bytes);
    }
    ck = Uint8List.fromList(h);
    cipherState = NoiseCipherState(useExtractedNonce: false);
  }

  /// Mixes data into the running handshake hash `h = SHA256(h || data)`.
  void mixHash(Uint8List data) {
    final combined = Uint8List(h.length + data.length);
    combined.setRange(0, h.length, h);
    combined.setRange(h.length, combined.length, data);
    h = Uint8List.fromList(crypto.sha256.convert(combined).bytes);
  }

  /// Mixes input key material into the chaining key and updates the cipher key:
  /// `(ck, temp_k) = HKDF(ck, inputKeyMaterial, 2)`
  void mixKey(Uint8List inputKeyMaterial) {
    final outputs = _hkdf(ck, inputKeyMaterial, 2);
    ck = outputs[0];
    cipherState.initializeKey(SecretKey(outputs[1]));
  }

  /// Mixes key and hash for PSK token patterns:
  /// `(ck, temp_h, temp_k) = HKDF(ck, inputKeyMaterial, 3)`
  void mixKeyAndHash(Uint8List inputKeyMaterial) {
    final outputs = _hkdf(ck, inputKeyMaterial, 3);
    ck = outputs[0];
    mixHash(outputs[1]);
    cipherState.initializeKey(SecretKey(outputs[2]));
  }

  /// Encrypts plaintext with associated data `h`, updates `h` with ciphertext, and returns ciphertext.
  /// If the cipher has no key yet, plaintext is unencrypted and `mixHash(plaintext)` is called.
  Future<Uint8List> encryptAndHash(Uint8List plaintext) async {
    if (cipherState.hasKey) {
      final ciphertext = await cipherState.encrypt(plaintext, associatedData: h);
      mixHash(ciphertext);
      return ciphertext;
    } else {
      mixHash(plaintext);
      return plaintext;
    }
  }

  /// Decrypts ciphertext with associated data `h`, updates `h` with ciphertext, and returns plaintext.
  /// If the cipher has no key yet, ciphertext is unencrypted and `mixHash(ciphertext)` is called.
  Future<Uint8List> decryptAndHash(Uint8List ciphertext) async {
    if (cipherState.hasKey) {
      final plaintext = await cipherState.decrypt(ciphertext, associatedData: h);
      mixHash(ciphertext);
      return plaintext;
    } else {
      mixHash(ciphertext);
      return ciphertext;
    }
  }

  /// Splits the symmetric state into two independent transport [NoiseCipherState] instances
  /// with extracted nonce support enabled:
  /// `(k1, k2) = HKDF(ck, zerolen, 2)`
  ///
  /// Returns `(sendCipher, receiveCipher)` tailored to whether this node was the initiator.
  ({NoiseCipherState sendCipher, NoiseCipherState receiveCipher}) split({
    required bool isInitiator,
  }) {
    final outputs = _hkdf(ck, Uint8List(0), 2);
    final c1 = NoiseCipherState(key: SecretKey(outputs[0]), useExtractedNonce: true);
    final c2 = NoiseCipherState(key: SecretKey(outputs[1]), useExtractedNonce: true);

    if (isInitiator) {
      return (sendCipher: c1, receiveCipher: c2);
    } else {
      return (sendCipher: c2, receiveCipher: c1);
    }
  }

  /// Internal Noise RFC-compliant HKDF implementation using HMAC-SHA256.
  List<Uint8List> _hkdf(Uint8List chainingKey, Uint8List ikm, int numOutputs) {
    // 1. Extract: PRK = HMAC-Hash(chainingKey, ikm)
    final hmacExtract = crypto.Hmac(crypto.sha256, chainingKey);
    final prk = hmacExtract.convert(ikm).bytes;

    // 2. Expand:
    // output1 = HMAC-Hash(PRK, 0x01)
    // output2 = HMAC-Hash(PRK, output1 || 0x02)
    // output3 = HMAC-Hash(PRK, output2 || 0x03)
    final hmacExpand = crypto.Hmac(crypto.sha256, prk);

    final out1 = Uint8List.fromList(hmacExpand.convert([0x01]).bytes);
    if (numOutputs == 1) return [out1];

    final in2 = Uint8List(out1.length + 1);
    in2.setRange(0, out1.length, out1);
    in2[out1.length] = 0x02;
    final out2 = Uint8List.fromList(hmacExpand.convert(in2).bytes);
    if (numOutputs == 2) return [out1, out2];

    final in3 = Uint8List(out2.length + 1);
    in3.setRange(0, out2.length, out2);
    in3[out2.length] = 0x03;
    final out3 = Uint8List.fromList(hmacExpand.convert(in3).bytes);
    return [out1, out2, out3];
  }

  /// Zeroizes sensitive cryptographic material.
  void clear() {
    ck.fillRange(0, ck.length, 0);
    h.fillRange(0, h.length, 0);
    cipherState.clearSensitiveData();
  }
}
