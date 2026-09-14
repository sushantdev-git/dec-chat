import '../entities/bitchat_packet.dart';
import '../enums/message_type.dart';
import 'feature_registry.dart';

/// Callback invoked when a chat message packet is received.
typedef InboundMessageHandler = void Function(
  BitchatPacket packet,
  PacketContext context,
);

/// Protocol feature module routing `MessageType.message` packets to the timeline.
class ChatMessageModule implements ProtocolFeatureModule {
  final InboundMessageHandler onMessage;

  ChatMessageModule(this.onMessage);

  @override
  String get moduleId => 'chat_messages';

  @override
  Set<MessageType> get handledTypes => {MessageType.message};

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    onMessage(packet, context);
  }
}
