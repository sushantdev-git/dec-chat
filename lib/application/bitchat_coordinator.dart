import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/identity_key_pair.dart';
import '../domain/ports/transport_port.dart';
import '../domain/services/courier_module.dart';
import '../domain/services/courier_service.dart';
import '../domain/services/feature_registry.dart';
import '../domain/services/mesh_engine.dart';
import '../domain/services/noise_session_manager.dart';
import '../domain/services/panic_zeroization_service.dart';
import '../domain/services/seen_packet_cache.dart';
import '../infrastructure/adapters/native_ble_link_adapter.dart';
import '../presentation/state/identity_state.dart';

/// Master coordinator tying together the full DecChat stack:
/// - Cryptographic identity & Noise sessions
/// - Controlled flooding MeshEngine
/// - Store-and-forward Courier DTN engine
/// - Dual-transport radio links
/// - Panic zeroization pipeline
class BitchatCoordinator {
  final Uint8List localPeerId;
  final TransportPort transportPort;
  final ProtocolFeatureRegistry featureRegistry;
  final SeenPacketCache seenCache;
  final IdentityKeyPair? keyPair;
  late final MeshEngine meshEngine;
  late final CourierService courierService;
  late final NoiseSessionManager? noiseSessionManager;
  late final PanicZeroizationService panicZeroizationService;

  bool _isStarted = false;

  BitchatCoordinator({
    required this.localPeerId,
    required this.transportPort,
    ProtocolFeatureRegistry? featureRegistry,
    SeenPacketCache? seenCache,
    this.keyPair,
  })  : featureRegistry = featureRegistry ?? ProtocolFeatureRegistry(),
        seenCache = seenCache ?? SeenPacketCache() {
    courierService = CourierService(
      localPeerId: localPeerId,
      transportPort: transportPort,
    );

    noiseSessionManager = keyPair != null
        ? NoiseSessionManager(localIdentity: keyPair!)
        : null;

    panicZeroizationService = PanicZeroizationService(
      transportPort: transportPort,
      courierService: courierService,
      seenPacketCache: this.seenCache,
      noiseSessionManager: noiseSessionManager,
    );

    meshEngine = MeshEngine(
      localPeerId: localPeerId,
      transportPort: transportPort,
      featureRegistry: this.featureRegistry,
      seenCache: this.seenCache,
    );

    // Register Courier DTN module into feature registry
    this.featureRegistry.registerModule(CourierModule(courierService));
  }

  bool get isStarted => _isStarted;

  /// Starts the mesh engine, transport ports, and periodic background tasks.
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;
    await meshEngine.start();
  }

  /// Stops all radio links, mesh routines, and subscriptions.
  Future<void> stop() async {
    _isStarted = false;
    await meshEngine.stop();
    await courierService.dispose();
  }

  /// Executes an unconfirmed emergency panic wipe across all layers.
  Future<void> panicWipe({IdentityKeyPair? activeKeyPair}) async {
    await stop();
    await panicZeroizationService.executeZeroization(activeKeyPair: activeKeyPair);
  }
}

/// Global provider for the transport port (defaults to NativeBleLinkAdapter).
final transportPortProvider = Provider<TransportPort>((ref) {
  return NativeBleLinkAdapter();
});

/// Global provider for the BitchatCoordinator.
final bitchatCoordinatorProvider = Provider<BitchatCoordinator?>((ref) {
  final identity = ref.watch(identityProvider);
  if (!identity.isInitialized || identity.keyPair == null) {
    return null;
  }

  final transport = ref.watch(transportPortProvider);
  final coordinator = BitchatCoordinator(
    localPeerId: identity.keyPair!.peerId,
    transportPort: transport,
    keyPair: identity.keyPair,
  );
  ref.onDispose(() {
    coordinator.stop();
  });
  return coordinator;
});
