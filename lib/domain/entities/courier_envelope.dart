import 'dart:convert';
import 'dart:typed_data';

import '../../core/utils/binary_reader.dart';
import '../../core/utils/binary_writer.dart';

/// Represents a sealed store-and-forward bundle carried by intermediate mobile nodes
/// across delay-tolerant offline partitions (BitChat packet type `0x04: courierEnvelope`).
class CourierEnvelope {
  /// Unique 16-character identifier for this envelope.
  final String envelopeId;

  /// 8-byte destination peer ID.
  final Uint8List recipientPeerId;

  /// 8-byte origin peer ID.
  final Uint8List senderPeerId;

  /// Creation timestamp in milliseconds since epoch.
  final int creationTimestamp;

  /// Expiry deadline timestamp in milliseconds since epoch.
  final int expiryTimestamp;

  /// Remaining maximum forwarding hops allowed before delivery or discard.
  final int hopBudget;

  /// Sealed end-to-end encrypted message payload (opaque to intermediate courier nodes).
  final Uint8List payload;

  const CourierEnvelope({
    required this.envelopeId,
    required this.recipientPeerId,
    required this.senderPeerId,
    required this.creationTimestamp,
    required this.expiryTimestamp,
    required this.hopBudget,
    required this.payload,
  });

  /// 16-character lowercase hex representation of the recipient peer ID.
  String get recipientPeerIdHex =>
      recipientPeerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// 16-character lowercase hex representation of the sender peer ID.
  String get senderPeerIdHex =>
      senderPeerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Whether this envelope has exceeded its time-to-live deadline.
  bool isExpired({DateTime? currentTime}) {
    final now = (currentTime ?? DateTime.now()).millisecondsSinceEpoch;
    return now >= expiryTimestamp;
  }

  /// Creates a copy of this envelope with decremented [hopBudget] for forwarding to another courier.
  CourierEnvelope decrementHop() {
    return CourierEnvelope(
      envelopeId: envelopeId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      creationTimestamp: creationTimestamp,
      expiryTimestamp: expiryTimestamp,
      hopBudget: hopBudget > 0 ? hopBudget - 1 : 0,
      payload: payload,
    );
  }

  /// Encodes this envelope into big-endian wire binary format.
  Uint8List toBinary() {
    final idBytes = Uint8List.fromList(utf8.encode(envelopeId));
    final writer = BinaryWriter();

    writer.writeUint8(idBytes.length);
    writer.writeBytes(idBytes);
    writer.writeBytes(recipientPeerId);
    writer.writeBytes(senderPeerId);
    writer.writeUint64(creationTimestamp);
    writer.writeUint64(expiryTimestamp);
    writer.writeUint8(hopBudget);
    writer.writeUint32(payload.length);
    writer.writeBytes(payload);

    return writer.toBytes();
  }

  /// Decodes a binary payload into a [CourierEnvelope].
  static CourierEnvelope fromBinary(Uint8List bytes) {
    final reader = BinaryReader(bytes);

    final idLen = reader.readUint8();
    final idBytes = reader.readBytes(idLen);
    final id = utf8.decode(idBytes);

    final recipient = reader.readBytes(8);
    final sender = reader.readBytes(8);
    final created = reader.readUint64();
    final expiry = reader.readUint64();
    final hops = reader.readUint8();
    final payloadLen = reader.readUint32();
    final payload = reader.readBytes(payloadLen);

    return CourierEnvelope(
      envelopeId: id,
      recipientPeerId: recipient,
      senderPeerId: sender,
      creationTimestamp: created,
      expiryTimestamp: expiry,
      hopBudget: hops,
      payload: payload,
    );
  }
}
