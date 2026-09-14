import '../entities/bitchat_packet.dart';
import '../enums/message_type.dart';
import '../enums/transport_medium.dart';

/// Contextual metadata accompanying an inbound packet dispatched to a feature module.
class PacketContext {
  /// Identifier of the 1-hop link neighbor that delivered this packet.
  final String sourceLinkPeerId;

  /// Underlying transport medium over which the packet arrived.
  final TransportMedium medium;

  /// Estimated number of network hops traversed by the packet.
  final int hops;

  const PacketContext({
    required this.sourceLinkPeerId,
    required this.medium,
    required this.hops,
  });
}

/// Pluggable interface for protocol feature modules (e.g. Chat, Noise E2EE, Couriers, Files).
///
/// Ensures the core mesh engine maintains zero knowledge of application features,
/// adhering strictly to the Open-Closed Principle.
abstract class ProtocolFeatureModule {
  /// Unique identifier for this feature module (e.g. 'public_chat', 'noise_e2ee').
  String get moduleId;

  /// Wire message types processed by this module.
  Set<MessageType> get handledTypes;

  /// Handles an inbound packet delivered to this node.
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context);
}

/// Dynamic registry that routes incoming mesh packets to registered feature modules.
class ProtocolFeatureRegistry {
  final Map<String, ProtocolFeatureModule> _modules = {};
  final Map<int, ProtocolFeatureModule> _typeRoutingTable = {};

  /// Registers a feature module and maps its handled message types.
  void registerModule(ProtocolFeatureModule module) {
    _modules[module.moduleId] = module;
    for (final type in module.handledTypes) {
      _typeRoutingTable[type.rawValue] = module;
    }
  }

  /// Unregisters a feature module and clears its message type mappings.
  void unregisterModule(String moduleId) {
    final module = _modules.remove(moduleId);
    if (module != null) {
      for (final type in module.handledTypes) {
        if (_typeRoutingTable[type.rawValue] == module) {
          _typeRoutingTable.remove(type.rawValue);
        }
      }
    }
  }

  /// Whether a module is registered to process the given message type.
  bool canHandle(MessageType type) => _typeRoutingTable.containsKey(type.rawValue);

  /// Dispatches an inbound packet to the appropriate registered feature module.
  /// Returns `true` if handled, or `false` if no module is registered for this type.
  Future<bool> dispatch(BitchatPacket packet, PacketContext context) async {
    final module = _typeRoutingTable[packet.type.rawValue];
    if (module != null) {
      await module.handleInboundPacket(packet, context);
      return true;
    }
    return false;
  }

  /// Returns an unmodifiable list of currently registered modules.
  List<ProtocolFeatureModule> get registeredModules => List.unmodifiable(_modules.values);

  /// Clears all registered modules.
  void clear() {
    _modules.clear();
    _typeRoutingTable.clear();
  }
}
