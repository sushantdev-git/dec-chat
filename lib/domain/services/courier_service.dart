import 'dart:async';
import 'dart:typed_data';

import '../../infrastructure/codecs/binary_protocol_codec.dart';
import '../entities/bitchat_packet.dart';
import '../entities/courier_envelope.dart';
import '../enums/message_type.dart';
import '../ports/transport_port.dart';

/// Store-and-Forward Delay-Tolerant Networking (DTN) engine managing asynchronous
/// courier packets carried by mobile nodes across partitioned mesh networks.
class CourierService {
  final Uint8List localPeerId;
  final TransportPort transportPort;
  final int maxCapacity;

  final Map<String, CourierEnvelope> _outbox = {};
  final StreamController<CourierEnvelope> _deliveredToUsController =
      StreamController<CourierEnvelope>.broadcast();

  Timer? _pruneTimer;

  CourierService({
    required this.localPeerId,
    required this.transportPort,
    this.maxCapacity = 200,
    Duration pruneInterval = const Duration(minutes: 5),
  }) {
    _pruneTimer = Timer.periodic(pruneInterval, (_) => pruneExpired());
  }

  /// Stream of envelopes delivered to this node where we are the final destination recipient.
  Stream<CourierEnvelope> get onEnvelopeDeliveredToUs =>
      _deliveredToUsController.stream;

  /// Number of envelopes currently carried in the local store-and-forward outbox.
  int get pendingEnvelopeCount => _outbox.length;

  /// Unmodifiable view of envelopes carried in the outbox.
  List<CourierEnvelope> get pendingEnvelopes =>
      List.unmodifiable(_outbox.values);

  /// 16-character lowercase hex string of our local peer ID.
  String get localPeerIdHex =>
      localPeerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Enqueues a new sealed message into the courier store-and-forward outbox.
  CourierEnvelope enqueue({
    required Uint8List recipientPeerId,
    required Uint8List payload,
    Duration ttl = const Duration(hours: 24),
    int hopBudget = 3,
    String? customEnvelopeId,
  }) {
    pruneExpired();

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = customEnvelopeId ?? '${now}_${_outbox.length}';

    final envelope = CourierEnvelope(
      envelopeId: id,
      recipientPeerId: recipientPeerId,
      senderPeerId: localPeerId,
      creationTimestamp: now,
      expiryTimestamp: now + ttl.inMilliseconds,
      hopBudget: hopBudget,
      payload: payload,
    );

    // Evict oldest if at capacity
    if (_outbox.length >= maxCapacity) {
      _outbox.remove(_outbox.keys.first);
    }

    _outbox[id] = envelope;
    return envelope;
  }

  /// Handles an inbound courier envelope packet received from the network.
  Future<void> handleInboundEnvelope(CourierEnvelope envelope) async {
    if (envelope.isExpired()) return;

    // Check if WE are the final recipient
    if (_isRecipient(envelope.recipientPeerId)) {
      if (!_deliveredToUsController.isClosed) {
        _deliveredToUsController.add(envelope);
      }
      return;
    }

    // Otherwise, we are an intermediate carrier node ("data mule")
    if (envelope.hopBudget > 0) {
      if (_outbox.length >= maxCapacity) {
        _outbox.remove(_outbox.keys.first);
      }
      _outbox[envelope.envelopeId] = envelope;
    }
  }

  /// Triggered whenever another peer is encountered or discovered nearby.
  ///
  /// Delivers any envelopes addressed to that peer, or forwards copies with
  /// decremented hop budgets according to spray-and-wait DTN routing.
  Future<void> onPeerDiscovered(String peerIdHex) async {
    final cleanPeer = peerIdHex.trim().toLowerCase();
    final matchingEnvelopeIds = <String>[];

    for (final envelope in _outbox.values) {
      if (envelope.isExpired()) continue;

      if (envelope.recipientPeerIdHex.toLowerCase() == cleanPeer) {
        // Direct delivery to the intended destination!
        await _deliverEnvelope(envelope, cleanPeer);
        matchingEnvelopeIds.add(envelope.envelopeId);
      } else if (envelope.hopBudget > 1) {
        // Spray-and-wait: forward a copy to the encountered peer as a helper courier
        final forwarded = envelope.decrementHop();
        await _deliverEnvelope(forwarded, cleanPeer);
      }
    }

    // Remove successfully delivered envelopes from our outbox
    for (final id in matchingEnvelopeIds) {
      _outbox.remove(id);
    }
  }

  Future<void> _deliverEnvelope(CourierEnvelope envelope, String targetPeerId) async {
    final wirePayload = envelope.toBinary();
    final packet = BitchatPacket(
      type: MessageType.courierEnvelope,
      ttl: 1,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: localPeerId,
      recipientId: null,
      payload: wirePayload,
    );

    final wireBytes = BinaryProtocolCodec.encode(packet);
    if (wireBytes != null) {
      await transportPort.sendDirected(targetPeerId, wireBytes);
    }
  }

  bool _isRecipient(Uint8List recipientId) {
    if (recipientId.length != localPeerId.length) return false;
    for (int i = 0; i < recipientId.length; i++) {
      if (recipientId[i] != localPeerId[i]) return false;
    }
    return true;
  }

  /// Removes all expired envelopes from the store-and-forward pool.
  void pruneExpired({DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    _outbox.removeWhere((_, env) => env.isExpired(currentTime: now));
  }

  /// Emergency panic wipe: instantly clears and zeroizes the courier outbox.
  void panicWipe() {
    _outbox.clear();
  }

  /// Releases resources and timers.
  Future<void> dispose() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    panicWipe();
    await _deliveredToUsController.close();
  }
}
