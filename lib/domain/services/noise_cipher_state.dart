import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Manages symmetric encryption state for Noise protocol sessions.
/// Handles ChaCha20-Poly1305 AEAD encryption with automatic 64-bit nonce management
/// and sliding-window replay protection matching the BitChat specification.
class NoiseCipherState {
  static const int nonceSizeBytes = 4;
  static const int replayWindowSize = 1024;
  static const int replayWindowBytes = replayWindowSize ~/ 8; // 128 bytes

  final Chacha20 _chacha = Chacha20.poly1305Aead();

  SecretKey? _key;
  int _nonce = 0;
  final bool useExtractedNonce;

  int _highestReceivedNonce = 0;
  final Uint8List _replayWindow = Uint8List(replayWindowBytes);

  NoiseCipherState({SecretKey? key, this.useExtractedNonce = false}) : _key = key;

  bool get hasKey => _key != null;
  int get currentNonce => _nonce;

  /// Initializes or replaces the symmetric key and resets the outbound nonce counter.
  void initializeKey(SecretKey key) {
    _key = key;
    _nonce = 0;
  }

  /// Encrypts plaintext with ChaCha20-Poly1305 AEAD and increments the nonce.
  Future<Uint8List> encrypt(Uint8List plaintext, {Uint8List? associatedData}) async {
    final key = _key;
    if (key == null) {
      throw StateError('Uninitialized cipher state: key is null');
    }

    if (_nonce >= 0xFFFFFFFF) {
      throw StateError('Nonce limit exceeded for 32-bit wire representation');
    }

    final current = _nonce;

    // BitChat 12-byte nonce: 4 bytes zero + 8-byte little-endian nonce
    final nonceBytes = Uint8List(12);
    ByteData.sublistView(nonceBytes).setUint64(4, current, Endian.little);

    final secretBox = await _chacha.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonceBytes,
      aad: associatedData ?? Uint8List(0),
    );

    _nonce += 1;

    final ciphertext = secretBox.cipherText;
    final tag = secretBox.mac.bytes;

    if (useExtractedNonce) {
      // Combined wire payload: <4-byte big-endian nonce><ciphertext><16-byte tag>
      final combined = Uint8List(nonceSizeBytes + ciphertext.length + tag.length);
      final bd = ByteData.sublistView(combined);
      bd.setUint32(0, current, Endian.big);
      combined.setRange(nonceSizeBytes, nonceSizeBytes + ciphertext.length, ciphertext);
      combined.setRange(nonceSizeBytes + ciphertext.length, combined.length, tag);
      return combined;
    } else {
      // Handshake payload: <ciphertext><16-byte tag>
      final combined = Uint8List(ciphertext.length + tag.length);
      combined.setRange(0, ciphertext.length, ciphertext);
      combined.setRange(ciphertext.length, combined.length, tag);
      return combined;
    }
  }

  /// Decrypts ciphertext with ChaCha20-Poly1305 AEAD.
  /// Validates sliding-window replay protection when [useExtractedNonce] is true.
  Future<Uint8List> decrypt(Uint8List combinedPayload, {Uint8List? associatedData}) async {
    final key = _key;
    if (key == null) {
      throw StateError('Uninitialized cipher state: key is null');
    }

    if (useExtractedNonce) {
      if (combinedPayload.length < nonceSizeBytes + 16) {
        throw const FormatException('Ciphertext payload too short for extracted nonce');
      }

      final extractedNonce = ByteData.sublistView(combinedPayload).getUint32(0, Endian.big);

      // Replay protection check
      if (!_isValidNonce(extractedNonce)) {
        throw StateError('Replay attack detected: nonce $extractedNonce rejected');
      }

      final payloadWithoutNonce = combinedPayload.sublist(nonceSizeBytes);
      final ctLen = payloadWithoutNonce.length - 16;
      final ciphertext = Uint8List.fromList(payloadWithoutNonce.sublist(0, ctLen));
      final tag = Uint8List.fromList(payloadWithoutNonce.sublist(ctLen));

      final nonceBytes = Uint8List(12);
      ByteData.sublistView(nonceBytes).setUint64(4, extractedNonce, Endian.little);

      final secretBox = SecretBox(ciphertext, nonce: nonceBytes, mac: Mac(tag));
      final plaintext = await _chacha.decrypt(
        secretBox,
        secretKey: key,
        aad: associatedData ?? Uint8List(0),
      );

      // Mark nonce as successfully seen only after authenticated decryption
      _markNonceAsSeen(extractedNonce);
      return Uint8List.fromList(plaintext);
    } else {
      if (combinedPayload.length < 16) {
        throw const FormatException('Ciphertext too short to contain tag');
      }

      final ctLen = combinedPayload.length - 16;
      final ciphertext = Uint8List.fromList(combinedPayload.sublist(0, ctLen));
      final tag = Uint8List.fromList(combinedPayload.sublist(ctLen));

      final nonceBytes = Uint8List(12);
      ByteData.sublistView(nonceBytes).setUint64(4, _nonce, Endian.little);

      final secretBox = SecretBox(ciphertext, nonce: nonceBytes, mac: Mac(tag));
      final plaintext = await _chacha.decrypt(
        secretBox,
        secretKey: key,
        aad: associatedData ?? Uint8List(0),
      );

      _nonce += 1;
      return Uint8List.fromList(plaintext);
    }
  }

  bool _isValidNonce(int receivedNonce) {
    if (_highestReceivedNonce >= replayWindowSize &&
        receivedNonce <= _highestReceivedNonce - replayWindowSize) {
      return false; // Outside window, too old
    }

    if (receivedNonce > _highestReceivedNonce) {
      return true; // Newer nonce
    }

    final offset = _highestReceivedNonce - receivedNonce;
    final byteIndex = offset ~/ 8;
    final bitIndex = offset % 8;

    return (_replayWindow[byteIndex] & (1 << bitIndex)) == 0;
  }

  void _markNonceAsSeen(int receivedNonce) {
    if (receivedNonce > _highestReceivedNonce) {
      final shift = receivedNonce - _highestReceivedNonce;
      if (shift >= replayWindowSize) {
        _replayWindow.fillRange(0, replayWindowBytes, 0);
      } else {
        final byteShift = shift ~/ 8;
        final bitShift = shift % 8;
        for (int i = replayWindowBytes - 1; i >= 0; i--) {
          int newByte = 0;
          final src = i - byteShift;
          if (src >= 0) {
            newByte = (_replayWindow[src] << bitShift) & 0xFF;
            if (src > 0 && bitShift != 0) {
              newByte |= (_replayWindow[src - 1] >> (8 - bitShift));
            }
          }
          _replayWindow[i] = newByte;
        }
      }
      _highestReceivedNonce = receivedNonce;
      _replayWindow[0] |= 1;
    } else {
      final offset = _highestReceivedNonce - receivedNonce;
      final byteIndex = offset ~/ 8;
      final bitIndex = offset % 8;
      _replayWindow[byteIndex] |= (1 << bitIndex);
    }
  }

  /// Securely zeroizes sensitive key material and resets nonces.
  void clearSensitiveData() {
    _key = null;
    _nonce = 0;
    _highestReceivedNonce = 0;
    _replayWindow.fillRange(0, replayWindowBytes, 0);
  }
}
