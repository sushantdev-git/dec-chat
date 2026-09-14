import '../entities/bitchat_packet.dart';
import '../entities/courier_envelope.dart';
import '../enums/message_type.dart';
import 'courier_service.dart';
import 'feature_registry.dart';

/// Protocol feature module routing `MessageType.courierEnvelope` packets to the [CourierService].
class CourierModule implements ProtocolFeatureModule {
  final CourierService courierService;

  CourierModule(this.courierService);

  @override
  String get moduleId => 'courier_dtn';

  @override
  Set<MessageType> get handledTypes => {MessageType.courierEnvelope};

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    try {
      final envelope = CourierEnvelope.fromBinary(packet.payload);
      await courierService.handleInboundEnvelope(envelope);
    } catch (_) {
      // Ignore malformed envelopes safely
    }
  }
}
