import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'channels_notifier.dart';
import 'identity_state.dart';
import 'peers_notifier.dart';
import 'timeline_notifier.dart';

/// Coordinator executing an instantaneous unconfirmed emergency panic wipe.
///
/// Features:
/// - Zeroizes in-memory ephemeral message buffers across all channels
/// - Clears discovered peer directories and radio cache
/// - Resets joined channels to standard defaults
/// - Re-generates a fresh ephemeral identity key pair
class PanicController {
  final Ref ref;

  PanicController(this.ref);

  /// Executes the instantaneous panic zeroization wipe without confirmation.
  Future<void> executePanicWipe() async {
    // 1. Wipe timelines
    await ref.read(timelineProvider.notifier).clearAll();

    // 2. Wipe peer cache
    ref.read(peersProvider.notifier).clear();

    // 3. Reset channels
    ref.read(channelsProvider.notifier).clear();

    // 4. Zeroize and regenerate cryptographic keys
    await ref.read(identityProvider.notifier).panicWipe();
  }
}

/// Global provider for the emergency panic wipe controller.
final panicControllerProvider = Provider<PanicController>((ref) {
  return PanicController(ref);
});
