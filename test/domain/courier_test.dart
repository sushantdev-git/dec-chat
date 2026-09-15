import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/domain/entities/courier_envelope.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/domain/services/courier_service.dart';

class MockCourierTransport implements TransportPort {
  final List<MapEntry<String, Uint8List>> sentDirectedPackets = [];

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
  Future<void> startScan() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> sendBroadcast(Uint8List packetBytes) async {}

  @override
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes) async {
    sentDirectedPackets.add(MapEntry(targetPeerId, packetBytes));
  }
}

void main() {
  group('CourierEnvelope Serialization & DTN Invariants', () {
    test('round-trips CourierEnvelope through wire binary format', () {
      final recipient = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final sender = Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]);
      final payload = Uint8List.fromList([10, 20, 30, 40, 50]);

      final original = CourierEnvelope(
        envelopeId: 'env_test_1234',
        recipientPeerId: recipient,
        senderPeerId: sender,
        creationTimestamp: 1600000000000,
        expiryTimestamp: 1600086400000,
        hopBudget: 3,
        payload: payload,
      );

      final bytes = original.toBinary();
      final decoded = CourierEnvelope.fromBinary(bytes);

      expect(decoded.envelopeId, equals(original.envelopeId));
      expect(decoded.recipientPeerId, equals(recipient));
      expect(decoded.senderPeerId, equals(sender));
      expect(decoded.creationTimestamp, equals(original.creationTimestamp));
      expect(decoded.expiryTimestamp, equals(original.expiryTimestamp));
      expect(decoded.hopBudget, equals(3));
      expect(decoded.payload, equals(payload));
    });

    test('checks expiry deadline correctly', () {
      final envelope = CourierEnvelope(
        envelopeId: 'env_exp',
        recipientPeerId: Uint8List(8),
        senderPeerId: Uint8List(8),
        creationTimestamp: 1000,
        expiryTimestamp: 5000,
        hopBudget: 2,
        payload: Uint8List(0),
      );

      expect(envelope.isExpired(currentTime: DateTime.fromMillisecondsSinceEpoch(4000)), isFalse);
      expect(envelope.isExpired(currentTime: DateTime.fromMillisecondsSinceEpoch(5000)), isTrue);
      expect(envelope.isExpired(currentTime: DateTime.fromMillisecondsSinceEpoch(6000)), isTrue);
    });

    test('decrements hop budget for data-mule forwarding', () {
      final envelope = CourierEnvelope(
        envelopeId: 'env_hop',
        recipientPeerId: Uint8List(8),
        senderPeerId: Uint8List(8),
        creationTimestamp: 1000,
        expiryTimestamp: 5000,
        hopBudget: 3,
        payload: Uint8List(4),
      );

      final forwarded = envelope.decrementHop();
      expect(forwarded.hopBudget, equals(2));
      expect(forwarded.decrementHop().hopBudget, equals(1));
      expect(forwarded.decrementHop().decrementHop().hopBudget, equals(0));
      expect(forwarded.decrementHop().decrementHop().decrementHop().hopBudget, equals(0)); // Non-negative
    });
  });

  group('CourierService Store-and-Forward Outbox & Delivery', () {
    final aliceId = Uint8List.fromList([0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA]);
    final bobId = Uint8List.fromList([0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB]);
    final charlieId = Uint8List.fromList([0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC]);

    const bobHex = 'bbbbbbbbbbbbbbbb';

    late MockCourierTransport mockTransport;
    late CourierService service;

    setUp(() {
      mockTransport = MockCourierTransport();
      service = CourierService(
        localPeerId: aliceId,
        transportPort: mockTransport,
        maxCapacity: 3,
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('enqueues messages and bounds capacity by evicting oldest', () {
      service.enqueue(recipientPeerId: bobId, payload: Uint8List.fromList([1]));
      service.enqueue(recipientPeerId: bobId, payload: Uint8List.fromList([2]));
      service.enqueue(recipientPeerId: bobId, payload: Uint8List.fromList([3]));
      expect(service.pendingEnvelopeCount, equals(3));

      // Adding 4th envelope evicts the oldest (capacity = 3)
      service.enqueue(recipientPeerId: bobId, payload: Uint8List.fromList([4]));
      expect(service.pendingEnvelopeCount, equals(3));
    });

    test('delivers envelope directly when target peer is encountered', () async {
      final payload = Uint8List.fromList([99, 100, 101]);
      service.enqueue(
        recipientPeerId: bobId,
        payload: payload,
        customEnvelopeId: 'env_bob',
      );

      expect(service.pendingEnvelopeCount, equals(1));

      // Alice encounters Bob!
      await service.onPeerDiscovered(bobHex);

      // Successfully transmitted to Bob!
      expect(mockTransport.sentDirectedPackets.length, equals(1));
      expect(mockTransport.sentDirectedPackets.first.key, equals(bobHex));

      // Envelope removed from outbox after direct delivery
      expect(service.pendingEnvelopeCount, equals(0));
    });

    test('forwards copies to intermediate couriers (spray-and-wait) when budget > 1', () async {
      service.enqueue(
        recipientPeerId: charlieId,
        payload: Uint8List.fromList([42]),
        hopBudget: 3,
        customEnvelopeId: 'env_for_charlie',
      );

      // Alice encounters Bob (not Charlie)
      await service.onPeerDiscovered(bobHex);

      // Envelope was relayed to Bob as a helper courier
      expect(mockTransport.sentDirectedPackets.length, equals(1));
      expect(mockTransport.sentDirectedPackets.first.key, equals(bobHex));

      // Alice still retains the envelope until delivered to Charlie
      expect(service.pendingEnvelopeCount, equals(1));
    });

    test('inbound envelope addressed to us triggers onEnvelopeDeliveredToUs', () async {
      final receivedEnvelopes = <CourierEnvelope>[];
      final sub = service.onEnvelopeDeliveredToUs.listen(receivedEnvelopes.add);

      final envelopeForAlice = CourierEnvelope(
        envelopeId: 'for_alice',
        recipientPeerId: aliceId, // Addressed to Alice
        senderPeerId: bobId,
        creationTimestamp: 1000,
        expiryTimestamp: DateTime.now().millisecondsSinceEpoch + 100000,
        hopBudget: 2,
        payload: Uint8List.fromList([7, 8, 9]),
      );

      await service.handleInboundEnvelope(envelopeForAlice);

      expect(receivedEnvelopes.length, equals(1));
      expect(receivedEnvelopes.first.envelopeId, equals('for_alice'));
      // Not stored in outbox because it was for us
      expect(service.pendingEnvelopeCount, equals(0));

      await sub.cancel();
    });

    test('inbound envelope addressed to someone else is stored to courier forward', () async {
      final envelopeForCharlie = CourierEnvelope(
        envelopeId: 'for_charlie',
        recipientPeerId: charlieId, // Addressed to Charlie (not Alice)
        senderPeerId: bobId,
        creationTimestamp: 1000,
        expiryTimestamp: DateTime.now().millisecondsSinceEpoch + 100000,
        hopBudget: 2,
        payload: Uint8List.fromList([7, 8, 9]),
      );

      await service.handleInboundEnvelope(envelopeForCharlie);

      // Stored in Alice's outbox to act as courier!
      expect(service.pendingEnvelopeCount, equals(1));
    });

    test('panic wipe completely clears courier outbox', () {
      service.enqueue(recipientPeerId: bobId, payload: Uint8List.fromList([1]));
      service.enqueue(recipientPeerId: charlieId, payload: Uint8List.fromList([2]));
      expect(service.pendingEnvelopeCount, equals(2));

      service.panicWipe();
      expect(service.pendingEnvelopeCount, equals(0));
    });
  });
}
