import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/domain/entities/identity_key_pair.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/domain/services/courier_service.dart';
import 'package:grid/domain/services/noise_session_manager.dart';
import 'package:grid/domain/services/panic_zeroization_service.dart';

class MockPanicTransport implements TransportPort {
  bool wasStopped = false;

  @override
  TransportMedium get medium => TransportMedium.simulated;

  @override
  Stream<TransportPacketEvent> get incomingPackets => const Stream.empty();

  @override
  List<String> get connectedPeerIds => [];

  @override
  bool get isAvailable => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    wasStopped = true;
  }

  @override
  Future<void> sendBroadcast(Uint8List packetBytes) async {}

  @override
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes) async {}
}

void main() {
  group('PanicZeroizationService Deep Scrubbing & Zeroization', () {
    test('scrubBytes overwrites byte buffer with zeroes in place', () {
      final secretBytes = Uint8List.fromList([1, 2, 3, 4, 5, 255, 128, 64]);
      expect(secretBytes.any((b) => b != 0), isTrue);

      PanicZeroizationService.scrubBytes(secretBytes);

      expect(secretBytes.every((b) => b == 0), isTrue);
    });

    test('executeZeroization clears courier outbox, active sessions, and stops radio', () async {
      final localKeyPair = await IdentityKeyPair.generate(nickname: 'Alice');
      final remoteKeyPair = await IdentityKeyPair.generate(nickname: 'Bob');

      final transport = MockPanicTransport();
      final courier = CourierService(
        localPeerId: localKeyPair.peerId,
        transportPort: transport,
      );

      // Enqueue courier messages
      courier.enqueue(
        recipientPeerId: remoteKeyPair.peerId,
        payload: Uint8List.fromList([1, 2, 3]),
      );
      expect(courier.pendingEnvelopeCount, equals(1));

      final noiseManager = NoiseSessionManager(localIdentity: localKeyPair);
      // Start a handshake
      await noiseManager.initiateHandshake(remoteKeyPair.peerId);

      final service = PanicZeroizationService(
        transportPort: transport,
        courierService: courier,
        noiseSessionManager: noiseManager,
      );

      // Execute Panic Wipe
      await service.executeZeroization(activeKeyPair: localKeyPair);

      // 1. Courier outbox wiped
      expect(courier.pendingEnvelopeCount, equals(0));

      // 2. Radio stopped
      expect(transport.wasStopped, isTrue);

      // 3. Local peer ID scrubbed to zero
      expect(localKeyPair.peerId.every((b) => b == 0), isTrue);

      await courier.dispose();
    });
  });
}
