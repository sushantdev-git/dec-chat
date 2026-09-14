import 'dart:typed_data';
import '../../infrastructure/codecs/announcement_codec.dart';
import '../entities/bitchat_packet.dart';
import '../enums/message_type.dart';
import 'feature_registry.dart';

/// Callback invoked when a validated peer presence announcement packet is received.
typedef PeerAnnouncementHandler = void Function(
  AnnouncementPayload payload,
  Uint8List senderPeerId,
  PacketContext context,
);

/// Protocol feature module routing `MessageType.announce` packets to the peer directory.
class AnnouncementModule implements ProtocolFeatureModule {
  final PeerAnnouncementHandler onAnnouncement;

  AnnouncementModule(this.onAnnouncement);

  @override
  String get moduleId => 'peer_announcements';

  @override
  Set<MessageType> get handledTypes => {MessageType.announce};

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    try {
      final announcement = AnnouncementCodec.decode(packet.payload);
      if (announcement != null) {
        onAnnouncement(announcement, packet.senderId, context);
      }
    } catch (_) {
      // Discard malformed announcements safely
    }
  }
}
