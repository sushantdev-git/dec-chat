import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

import 'package:dec_chat/domain/entities/bitchat_packet.dart';
import 'package:dec_chat/domain/entities/identity_key_pair.dart';
import 'package:dec_chat/domain/enums/message_type.dart';
import 'package:dec_chat/domain/enums/noise_payload_type.dart';
import 'package:dec_chat/domain/services/noise_cipher_state.dart';
import 'package:dec_chat/domain/services/noise_handshake_state.dart';
import 'package:dec_chat/domain/services/noise_session_manager.dart';
import 'package:dec_chat/domain/services/noise_symmetric_state.dart';
import 'package:dec_chat/infrastructure/adapters/cryptography_adapter.dart';

void main() {
  group('IdentityKeyPair & Safety Numbers', () {
    final adapter = CryptographyAdapter();

    test('generates dual keys and derives correct 8-byte peer ID', () async {
      final IdentityKeyPair identity = await adapter.generateIdentity(nickname: 'Alice');

      expect(identity.nickname, 'Alice');
      expect(identity.peerId.length, 8);
      expect(identity.noisePublicKeyBytes.length, 32);
      expect(identity.signingPublicKeyBytes.length, 32);

      // Verify peer ID matches first 8 bytes of SHA-256(noisePublicKey)
      final expectedPeerId = adapter.derivePeerId(identity.noisePublicKeyBytes);
      expect(identity.peerId, orderedEquals(expectedPeerId));
    });

    test('computes symmetric Signal-style safety numbers', () async {
      final alice = await adapter.generateIdentity(nickname: 'Alice');
      final bob = await adapter.generateIdentity(nickname: 'Bob');

      final aliceSafetyNumber = alice.computeSafetyNumber(bob.noisePublicKeyBytes);
      final bobSafetyNumber = bob.computeSafetyNumber(alice.noisePublicKeyBytes);

      // Safety number must be identical regardless of who computes it
      expect(aliceSafetyNumber, bobSafetyNumber);

      // Must be 12 groups of 5 digits separated by spaces (total 60 digits + 11 spaces = 71 chars)
      expect(aliceSafetyNumber.length, 71);
      final groups = aliceSafetyNumber.split(' ');
      expect(groups.length, 12);
      for (final group in groups) {
        expect(group.length, 5);
        expect(int.tryParse(group), isNotNull);
      }

      // Safety number with another peer should be different
      final eve = await adapter.generateIdentity(nickname: 'Eve');
      final aliceEveSafetyNumber = alice.computeSafetyNumber(eve.noisePublicKeyBytes);
      expect(aliceSafetyNumber, isNot(equals(aliceEveSafetyNumber)));
    });
  });

  group('Canonical Packet Signing & Verification', () {
    final adapter = CryptographyAdapter();

    test('signs canonical packet and verifies successfully', () async {
      final alice = await adapter.generateIdentity(nickname: 'Alice');
      final payload = Uint8List.fromList(utf8.encode('Hello mesh'));

      final packet = BitchatPacket(
        type: MessageType.message,
        ttl: 7,
        timestamp: 1718000000000,
        senderId: alice.peerId,
        payload: payload,
      );

      final signature = await adapter.signPacket(packet, alice.signingKeyPair);
      final signedPacket = packet.copyWith(
        signature: signature,
      );

      final isValid = await adapter.verifyPacketSignature(
        signedPacket,
        alice.signingPublicKeyBytes,
      );
      expect(isValid, isTrue);
    });

    test('signature remains valid when TTL is decremented in transit (canonical TTL=0)', () async {
      final alice = await adapter.generateIdentity(nickname: 'Alice');
      final payload = Uint8List.fromList(utf8.encode('Hop hop'));

      final originalPacket = BitchatPacket(
        type: MessageType.message,
        ttl: 7,
        timestamp: 1718000000000,
        senderId: alice.peerId,
        payload: payload,
      );

      final signature = await adapter.signPacket(originalPacket, alice.signingKeyPair);
      final signedPacket = originalPacket.copyWith(
        signature: signature,
      );

      // Simulate packet relayed across 3 mesh hops (TTL 7 -> 6 -> 5 -> 4)
      final relayedPacket = signedPacket.copyWith(ttl: 4);

      final isValid = await adapter.verifyPacketSignature(
        relayedPacket,
        alice.signingPublicKeyBytes,
      );
      expect(isValid, isTrue, reason: 'TTL decrement must not invalidate canonical signature');
    });

    test('tampering with packet payload causes signature verification to fail', () async {
      final alice = await adapter.generateIdentity(nickname: 'Alice');
      final payload = Uint8List.fromList(utf8.encode('Legit message'));

      final packet = BitchatPacket(
        type: MessageType.message,
        ttl: 7,
        timestamp: 1718000000000,
        senderId: alice.peerId,
        payload: payload,
      );

      final signature = await adapter.signPacket(packet, alice.signingKeyPair);
      final signedPacket = packet.copyWith(
        signature: signature,
      );

      // Attacker tampers with payload
      final tamperedPacket = signedPacket.copyWith(
        payload: Uint8List.fromList(utf8.encode('Tampered message!')),
      );

      final isValid = await adapter.verifyPacketSignature(
        tamperedPacket,
        alice.signingPublicKeyBytes,
      );
      expect(isValid, isFalse);
    });
  });

  group('NoiseCipherState & Sliding-Window Replay Protection', () {
    test('encrypts and decrypts with extracted wire nonce', () async {
      final rawKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final secretKey = SecretKey(rawKey);

      final senderCipher = NoiseCipherState(key: secretKey, useExtractedNonce: true);
      final receiverCipher = NoiseCipherState(key: secretKey, useExtractedNonce: true);

      final plaintext = Uint8List.fromList(utf8.encode('Secret P2P communication'));
      final ciphertext = await senderCipher.encrypt(plaintext);

      // Ciphertext must have 4-byte nonce + plaintext + 16-byte Poly1305 tag
      expect(ciphertext.length, 4 + plaintext.length + 16);

      final decrypted = await receiverCipher.decrypt(ciphertext);
      expect(decrypted, orderedEquals(plaintext));
    });

    test('rejects replay attacks with identical nonce', () async {
      final rawKey = Uint8List.fromList(List.generate(32, (i) => 42));
      final secretKey = SecretKey(rawKey);

      final sender = NoiseCipherState(key: secretKey, useExtractedNonce: true);
      final receiver = NoiseCipherState(key: secretKey, useExtractedNonce: true);

      final payload = Uint8List.fromList(utf8.encode('Don’t replay me'));
      final ciphertext = await sender.encrypt(payload);

      // First decrypt succeeds
      final decrypted = await receiver.decrypt(ciphertext);
      expect(decrypted, orderedEquals(payload));

      // Immediate replayed transmission with identical nonce must be rejected
      expect(
        () async => await receiver.decrypt(ciphertext),
        throwsA(isA<StateError>()),
      );
    });

    test('sliding-window accepts out-of-order packets but rejects packets older than 1024', () async {
      final rawKey = Uint8List.fromList(List.generate(32, (i) => 7));
      final secretKey = SecretKey(rawKey);

      final sender = NoiseCipherState(key: secretKey, useExtractedNonce: true);
      final receiver = NoiseCipherState(key: secretKey, useExtractedNonce: true);

      // Encrypt 5 packets: nonces 0, 1, 2, 3, 4
      final p0 = await sender.encrypt(Uint8List.fromList([0]));
      final p1 = await sender.encrypt(Uint8List.fromList([1]));
      final p2 = await sender.encrypt(Uint8List.fromList([2]));
      final p3 = await sender.encrypt(Uint8List.fromList([3]));
      final p4 = await sender.encrypt(Uint8List.fromList([4]));

      // Arrive out of order: 2, 4, 1, 3, 0
      expect((await receiver.decrypt(p2))[0], 2);
      expect((await receiver.decrypt(p4))[0], 4);
      expect((await receiver.decrypt(p1))[0], 1);
      expect((await receiver.decrypt(p3))[0], 3);
      expect((await receiver.decrypt(p0))[0], 0);

      // Any replay must now fail
      expect(() async => await receiver.decrypt(p2), throwsA(isA<StateError>()));
      expect(() async => await receiver.decrypt(p4), throwsA(isA<StateError>()));
    });
  });

  group('NoiseSymmetricState', () {
    test('initializes with protocol name and updates hash', () {
      final state = NoiseSymmetricState.initialize('Noise_XX_25519_ChaChaPoly_SHA256');
      expect(state.h.length, 32);
      expect(state.ck.length, 32);
      expect(state.cipherState.hasKey, isFalse);

      state.mixHash(Uint8List.fromList([1, 2, 3]));
      expect(state.h, isNot(equals(state.ck)));
    });

    test('mixKey sets up cipher state and encryptAndHash / decryptAndHash between peers', () async {
      final sender = NoiseSymmetricState.initialize('Noise_XX_25519_ChaChaPoly_SHA256');
      final receiver = NoiseSymmetricState.initialize('Noise_XX_25519_ChaChaPoly_SHA256');

      final key = Uint8List.fromList(List.filled(32, 1));
      sender.mixKey(key);
      receiver.mixKey(key);
      expect(sender.cipherState.hasKey, isTrue);
      expect(receiver.cipherState.hasKey, isTrue);

      final plaintext = Uint8List.fromList(utf8.encode('Noise Secret'));
      final ciphertext = await sender.encryptAndHash(plaintext);
      // Plaintext length (12) + Poly1305 MAC tag (16) = 28
      expect(ciphertext.length, plaintext.length + 16);

      final decrypted = await receiver.decryptAndHash(ciphertext);
      expect(decrypted, orderedEquals(plaintext));
      expect(sender.h, orderedEquals(receiver.h));
    });
  });

  group('Noise_XX Handshake & Transport Cryptography', () {
    final adapter = CryptographyAdapter();

    test('performs full 3-step Noise_XX handshake and establishes bidirectional cipher', () async {
      final aliceIdentity = await adapter.generateIdentity(nickname: 'Alice');
      final bobIdentity = await adapter.generateIdentity(nickname: 'Bob');

      final aliceHandshake = NoiseHandshakeState(
        role: NoiseRole.initiator,
        localStaticKeyPair: aliceIdentity.noiseKeyPair,
      );

      final bobHandshake = NoiseHandshakeState(
        role: NoiseRole.responder,
        localStaticKeyPair: bobIdentity.noiseKeyPair,
      );

      // Step 1: Alice -> Bob (e)
      final msg1 = await aliceHandshake.writeMessage(
        payload: Uint8List.fromList(utf8.encode('AliceInit')),
      );
      final bobPayload1 = await bobHandshake.readMessage(msg1);
      expect(utf8.decode(bobPayload1), 'AliceInit');

      // Step 2: Bob -> Alice (e, ee, s, es)
      final msg2 = await bobHandshake.writeMessage(
        payload: Uint8List.fromList(utf8.encode('BobResp')),
      );
      final alicePayload2 = await aliceHandshake.readMessage(msg2);
      expect(utf8.decode(alicePayload2), 'BobResp');

      // Step 3: Alice -> Bob (s, se)
      final msg3 = await aliceHandshake.writeMessage(
        payload: Uint8List.fromList(utf8.encode('AliceFinal')),
      );
      final bobPayload3 = await bobHandshake.readMessage(msg3);
      expect(utf8.decode(bobPayload3), 'AliceFinal');

      // Both handshakes must now be completed
      expect(aliceHandshake.isComplete, isTrue);
      expect(bobHandshake.isComplete, isTrue);

      final aliceResult = aliceHandshake.finishHandshake();
      final bobResult = bobHandshake.finishHandshake();

      // Handshake hashes must match perfectly
      expect(aliceResult.handshakeHash, orderedEquals(bobResult.handshakeHash));

      // Authenticated static keys must match
      expect(aliceResult.remoteStaticPublicKey, orderedEquals(bobIdentity.noisePublicKeyBytes));
      expect(bobResult.remoteStaticPublicKey, orderedEquals(aliceIdentity.noisePublicKeyBytes));

      // Test bidirectional transport encryption
      final msgFromAlice = Uint8List.fromList(utf8.encode('Hey Bob, this is encrypted!'));
      final cipherFromAlice = await aliceResult.sendCipher.encrypt(msgFromAlice);
      final decryptedByBob = await bobResult.receiveCipher.decrypt(cipherFromAlice);
      expect(decryptedByBob, orderedEquals(msgFromAlice));

      final msgFromBob = Uint8List.fromList(utf8.encode('Hey Alice, received loud and clear!'));
      final cipherFromBob = await bobResult.sendCipher.encrypt(msgFromBob);
      final decryptedByAlice = await aliceResult.receiveCipher.decrypt(cipherFromBob);
      expect(decryptedByAlice, orderedEquals(msgFromBob));
    });
  });

  group('NoiseSessionManager & End-to-End Sessions', () {
    final adapter = CryptographyAdapter();

    test('coordinates complete session lifecycle between two nodes', () async {
      final aliceIdentity = await adapter.generateIdentity(nickname: 'Alice');
      final bobIdentity = await adapter.generateIdentity(nickname: 'Bob');

      final aliceManager = NoiseSessionManager(localIdentity: aliceIdentity);
      final bobManager = NoiseSessionManager(localIdentity: bobIdentity);

      // 1. Alice initiates handshake to Bob
      final step1Bytes = await aliceManager.initiateHandshake(bobIdentity.peerId);
      expect(aliceManager.hasSession(bobIdentity.peerId), isFalse);

      // 2. Bob handles step 1, produces step 2 response
      final bobResult1 = await bobManager.handleIncomingHandshakeMessage(
        aliceIdentity.peerId,
        step1Bytes,
      );
      expect(bobResult1.isSessionEstablished, isFalse);
      expect(bobResult1.responsePayload, isNotNull);

      // 3. Alice handles step 2 response, produces step 3 response and establishes session
      final aliceResult2 = await aliceManager.handleIncomingHandshakeMessage(
        bobIdentity.peerId,
        bobResult1.responsePayload!,
      );
      expect(aliceResult2.isSessionEstablished, isTrue);
      expect(aliceResult2.responsePayload, isNotNull);
      expect(aliceManager.hasSession(bobIdentity.peerId), isTrue);

      // 4. Bob handles step 3 response and establishes session
      final bobResult3 = await bobManager.handleIncomingHandshakeMessage(
        aliceIdentity.peerId,
        aliceResult2.responsePayload!,
      );
      expect(bobResult3.isSessionEstablished, isTrue);
      expect(bobResult3.responsePayload, isNull);
      expect(bobManager.hasSession(aliceIdentity.peerId), isTrue);

      // 5. Exchange application messages with PKCS#7 privacy padding
      final secretChatMessage = Uint8List.fromList(utf8.encode('Confidential Signal message'));
      final encryptedBytes = await aliceManager.encryptPayload(
        bobIdentity.peerId,
        secretChatMessage,
      );

      // Padded size should match bucket (256 bytes)
      expect(encryptedBytes.length, greaterThanOrEqualTo(256));

      final decryptedMessage = await bobManager.decryptPayload(
        aliceIdentity.peerId,
        encryptedBytes,
      );
      expect(utf8.decode(decryptedMessage), 'Confidential Signal message');

      // 6. Test emergency panic wipe
      aliceManager.clearAllSessions();
      expect(aliceManager.hasSession(bobIdentity.peerId), isFalse);
      expect(
        () async => await aliceManager.encryptPayload(bobIdentity.peerId, secretChatMessage),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('NoisePayloadType', () {
    test('resolves known types and preserves unknown types gracefully', () {
      expect(NoisePayloadType.fromRaw(0x01), NoisePayloadType.privateMessage);
      expect(NoisePayloadType.fromRaw(0x02), NoisePayloadType.readReceipt);
      expect(NoisePayloadType.fromRaw(0x10), NoisePayloadType.verifyChallenge);

      final unknown = NoisePayloadType.fromRaw(0xFE);
      expect(unknown.rawValue, 0xFE);
      expect(unknown.name, 'unknown_0xfe');
    });
  });
}
