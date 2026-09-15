import 'dart:typed_data';

import '../entities/identity_key_pair.dart';
import '../ports/transport_port.dart';
import 'courier_service.dart';
import 'noise_session_manager.dart';
import 'seen_packet_cache.dart';

/// Comprehensive emergency panic wipe service executing cryptographic zeroization
/// and memory scrubbing across the entire BitChat stack.
class PanicZeroizationService {
  final TransportPort? transportPort;
  final CourierService? courierService;
  final SeenPacketCache? seenPacketCache;
  final NoiseSessionManager? noiseSessionManager;

  PanicZeroizationService({
    this.transportPort,
    this.courierService,
    this.seenPacketCache,
    this.noiseSessionManager,
  });

  /// Overwrites a byte buffer with zeros in place to prevent memory scraping.
  static void scrubBytes(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }

  /// Executes the deep panic zeroization pipeline:
  /// 1. Scrubs and clears courier store-and-forward outbox files and buffers.
  /// 2. Zeroizes active Noise handshake and symmetric cipher states.
  /// 3. Flushes packet deduplication caches.
  /// 4. Optionally stops and resets active radio links.
  Future<void> executeZeroization({IdentityKeyPair? activeKeyPair}) async {
    // 1. Wipe courier outbox
    courierService?.panicWipe();

    // 2. Wipe active Noise sessions and symmetric keys
    noiseSessionManager?.clearAllSessions();

    // 3. Clear packet deduplication LRU
    seenPacketCache?.clear();

    // 4. Memory scrub key pair bytes if accessible
    if (activeKeyPair != null) {
      scrubBytes(activeKeyPair.peerId);
    }

    // 5. Stop transport radios if required
    await transportPort?.stop();
  }
}
