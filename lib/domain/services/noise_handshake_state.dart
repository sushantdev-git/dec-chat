import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

import 'noise_cipher_state.dart';
import 'noise_symmetric_state.dart';

/// Role played in a Noise handshake exchange.
enum NoiseRole {
  initiator,
  responder,
}

/// Status of the Noise handshake state machine.
enum NoiseHandshakeStatus {
  notStarted,
  inProgress,
  completed,
  failed,
}

/// Result of a successfully completed Noise handshake.
class NoiseHandshakeResult {
  final NoiseCipherState sendCipher;
  final NoiseCipherState receiveCipher;
  final Uint8List remoteStaticPublicKey;
  final Uint8List handshakeHash;

  const NoiseHandshakeResult({
    required this.sendCipher,
    required this.receiveCipher,
    required this.remoteStaticPublicKey,
    required this.handshakeHash,
  });
}

/// Implements the Noise_XX_25519_ChaChaPoly_SHA256 handshake state machine.
///
/// Handshake Pattern:
/// ```text
/// Noise_XX(s, rs):
///   -> e
///   <- e, ee, s, es
///   -> s, se
/// ```
///
/// Provides mutual authentication, static key concealment (transmitted encrypted),
/// and forward secrecy.
class NoiseHandshakeState {
  static const String protocolName = 'Noise_XX_25519_ChaChaPoly_SHA256';

  final NoiseRole role;
  final SimpleKeyPair localStaticKeyPair;
  final NoiseSymmetricState symmetricState;
  final X25519 _x25519 = X25519();

  SimpleKeyPair? _localEphemeralKeyPair;
  Uint8List? _remoteEphemeralPublicKey;
  Uint8List? _remoteStaticPublicKey;

  int _messageIndex = 0;
  NoiseHandshakeStatus _status = NoiseHandshakeStatus.notStarted;

  NoiseHandshakeState({
    required this.role,
    required this.localStaticKeyPair,
    Uint8List? prologue,
  }) : symmetricState = NoiseSymmetricState.initialize(protocolName) {
    if (prologue != null && prologue.isNotEmpty) {
      symmetricState.mixHash(prologue);
    }
  }

  bool get isInitiator => role == NoiseRole.initiator;
  bool get isComplete => _messageIndex == 3 && _status == NoiseHandshakeStatus.completed;
  NoiseHandshakeStatus get status => _status;
  int get currentStep => _messageIndex + 1; // 1-indexed step (1, 2, or 3)
  Uint8List? get remoteStaticPublicKey => _remoteStaticPublicKey;

  /// Writes the next handshake message in the Noise_XX pattern.
  ///
  /// - Step 1 (Initiator -> Responder): `e`, unencrypted payload
  /// - Step 2 (Responder -> Initiator): `e`, `ee`, `s` (encrypted), `es`, encrypted payload
  /// - Step 3 (Initiator -> Responder): `s` (encrypted), `se`, encrypted payload
  Future<Uint8List> writeMessage({Uint8List? payload}) async {
    final payloadBytes = payload ?? Uint8List(0);

    if (isInitiator) {
      if (_messageIndex == 0) {
        // Step 1: -> e
        _status = NoiseHandshakeStatus.inProgress;
        _localEphemeralKeyPair = await _x25519.newKeyPair();
        final localEphemeralPub = Uint8List.fromList(
          (await _localEphemeralKeyPair!.extractPublicKey()).bytes,
        );
        symmetricState.mixHash(localEphemeralPub);

        final encryptedPayload = await symmetricState.encryptAndHash(payloadBytes);
        final message = Uint8List(localEphemeralPub.length + encryptedPayload.length);
        message.setRange(0, localEphemeralPub.length, localEphemeralPub);
        message.setRange(localEphemeralPub.length, message.length, encryptedPayload);

        _messageIndex = 1;
        return message;
      } else if (_messageIndex == 2) {
        // Step 3: -> s, se
        final localStaticPub = Uint8List.fromList(
          (await localStaticKeyPair.extractPublicKey()).bytes,
        );
        final encryptedStatic = await symmetricState.encryptAndHash(localStaticPub);

        final seSecret = await _dh(localStaticKeyPair, _remoteEphemeralPublicKey!);
        symmetricState.mixKey(seSecret);

        final encryptedPayload = await symmetricState.encryptAndHash(payloadBytes);
        final message = Uint8List(encryptedStatic.length + encryptedPayload.length);
        message.setRange(0, encryptedStatic.length, encryptedStatic);
        message.setRange(encryptedStatic.length, message.length, encryptedPayload);

        _messageIndex = 3;
        _status = NoiseHandshakeStatus.completed;
        return message;
      } else {
        throw StateError('Initiator cannot write message at step index $_messageIndex');
      }
    } else {
      // Responder
      if (_messageIndex == 1) {
        // Step 2: <- e, ee, s, es
        _localEphemeralKeyPair = await _x25519.newKeyPair();
        final localEphemeralPub = Uint8List.fromList(
          (await _localEphemeralKeyPair!.extractPublicKey()).bytes,
        );
        symmetricState.mixHash(localEphemeralPub);

        // ee
        final eeSecret = await _dh(_localEphemeralKeyPair!, _remoteEphemeralPublicKey!);
        symmetricState.mixKey(eeSecret);

        // s (encrypted)
        final localStaticPub = Uint8List.fromList(
          (await localStaticKeyPair.extractPublicKey()).bytes,
        );
        final encryptedStatic = await symmetricState.encryptAndHash(localStaticPub);

        // es (Responder: DH(s, re))
        final esSecret = await _dh(localStaticKeyPair, _remoteEphemeralPublicKey!);
        symmetricState.mixKey(esSecret);

        final encryptedPayload = await symmetricState.encryptAndHash(payloadBytes);
        final totalLength = localEphemeralPub.length + encryptedStatic.length + encryptedPayload.length;
        final message = Uint8List(totalLength);
        int offset = 0;

        message.setRange(offset, offset + localEphemeralPub.length, localEphemeralPub);
        offset += localEphemeralPub.length;

        message.setRange(offset, offset + encryptedStatic.length, encryptedStatic);
        offset += encryptedStatic.length;

        message.setRange(offset, offset + encryptedPayload.length, encryptedPayload);

        _messageIndex = 2;
        return message;
      } else {
        throw StateError('Responder cannot write message at step index $_messageIndex');
      }
    }
  }

  /// Reads and processes an incoming handshake message in the Noise_XX pattern.
  ///
  /// Returns the decrypted message payload carried by the handshake step.
  Future<Uint8List> readMessage(Uint8List message) async {
    try {
      if (isInitiator) {
        if (_messageIndex == 1) {
          // Step 2 (reading from Responder): <- e, ee, s, es
          // Message layout: [32B ephemeral key] [48B encrypted static key] [N bytes payload]
          if (message.length < 32 + 48) {
            throw const FormatException('Noise step 2 message too short');
          }

          _remoteEphemeralPublicKey = Uint8List.fromList(message.sublist(0, 32));
          symmetricState.mixHash(_remoteEphemeralPublicKey!);

          // ee
          final eeSecret = await _dh(_localEphemeralKeyPair!, _remoteEphemeralPublicKey!);
          symmetricState.mixKey(eeSecret);

          // s
          final encStatic = Uint8List.fromList(message.sublist(32, 80));
          _remoteStaticPublicKey = await symmetricState.decryptAndHash(encStatic);

          // es (Initiator: DH(e, rs))
          final esSecret = await _dh(_localEphemeralKeyPair!, _remoteStaticPublicKey!);
          symmetricState.mixKey(esSecret);

          final encPayload = Uint8List.fromList(message.sublist(80));
          final payload = await symmetricState.decryptAndHash(encPayload);

          _messageIndex = 2;
          return payload;
        } else {
          throw StateError('Initiator cannot read message at step index $_messageIndex');
        }
      } else {
        // Responder
        if (_messageIndex == 0) {
          // Step 1 (reading from Initiator): -> e
          // Message layout: [32B ephemeral key] [N bytes payload]
          if (message.length < 32) {
            throw const FormatException('Noise step 1 message too short');
          }

          _status = NoiseHandshakeStatus.inProgress;
          _remoteEphemeralPublicKey = Uint8List.fromList(message.sublist(0, 32));
          symmetricState.mixHash(_remoteEphemeralPublicKey!);

          final encPayload = Uint8List.fromList(message.sublist(32));
          final payload = await symmetricState.decryptAndHash(encPayload);

          _messageIndex = 1;
          return payload;
        } else if (_messageIndex == 2) {
          // Step 3 (reading from Initiator): -> s, se
          // Message layout: [48B encrypted static key] [N bytes payload]
          if (message.length < 48) {
            throw const FormatException('Noise step 3 message too short');
          }

          // s
          final encStatic = Uint8List.fromList(message.sublist(0, 48));
          _remoteStaticPublicKey = await symmetricState.decryptAndHash(encStatic);

          // se (Responder: DH(e, rs))
          final seSecret = await _dh(_localEphemeralKeyPair!, _remoteStaticPublicKey!);
          symmetricState.mixKey(seSecret);

          final encPayload = Uint8List.fromList(message.sublist(48));
          final payload = await symmetricState.decryptAndHash(encPayload);

          _messageIndex = 3;
          _status = NoiseHandshakeStatus.completed;
          return payload;
        } else {
          throw StateError('Responder cannot read message at step index $_messageIndex');
        }
      }
    } catch (_) {
      _status = NoiseHandshakeStatus.failed;
      rethrow;
    }
  }

  /// Finalizes the handshake after step 3 completes, splitting the symmetric state
  /// into bidirectional transport ciphers.
  NoiseHandshakeResult finishHandshake() {
    if (!isComplete) {
      throw StateError('Cannot finalize incomplete handshake (current status: $_status)');
    }
    final remoteStatic = _remoteStaticPublicKey;
    if (remoteStatic == null) {
      throw StateError('Remote static public key is missing upon handshake completion');
    }

    final splitCiphers = symmetricState.split(isInitiator: isInitiator);

    return NoiseHandshakeResult(
      sendCipher: splitCiphers.sendCipher,
      receiveCipher: splitCiphers.receiveCipher,
      remoteStaticPublicKey: remoteStatic,
      handshakeHash: Uint8List.fromList(symmetricState.h),
    );
  }

  /// Computes Diffie-Hellman shared secret between local keypair and remote public key.
  Future<Uint8List> _dh(SimpleKeyPair localKeyPair, Uint8List remotePublicKeyBytes) async {
    final remoteKey = SimplePublicKey(remotePublicKeyBytes, type: KeyPairType.x25519);
    final secret = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remoteKey,
    );
    final bytes = await secret.extractBytes();
    return Uint8List.fromList(bytes);
  }
}
