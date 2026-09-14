import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/identity_key_pair.dart';

/// State holding local node identity, keys, and display nickname.
class IdentityState {
  final IdentityKeyPair? keyPair;
  final String nickname;
  final String peerIdHex;
  final bool isInitialized;

  const IdentityState({
    this.keyPair,
    required this.nickname,
    required this.peerIdHex,
    this.isInitialized = false,
  });

  IdentityState copyWith({
    IdentityKeyPair? keyPair,
    String? nickname,
    String? peerIdHex,
    bool? isInitialized,
  }) {
    return IdentityState(
      keyPair: keyPair ?? this.keyPair,
      nickname: nickname ?? this.nickname,
      peerIdHex: peerIdHex ?? this.peerIdHex,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// StateNotifier managing local user identity and cryptographic keys.
class IdentityNotifier extends StateNotifier<IdentityState> {
  IdentityNotifier([IdentityState? initial])
      : super(initial ??
            const IdentityState(
              nickname: 'anon_node',
              peerIdHex: '0000000000000000',
              isInitialized: false,
            ));

  /// Initializes with real cryptographic keys asynchronously.
  Future<void> initialize({String? nickname}) async {
    final effectiveNickname = nickname ?? state.nickname;
    final pair = await IdentityKeyPair.generate(nickname: effectiveNickname);
    if (!mounted) return;
    state = IdentityState(
      keyPair: pair,
      nickname: pair.nickname,
      peerIdHex: pair.peerIdHex,
      isInitialized: true,
    );
  }

  /// Updates the local user's broadcast nickname.
  void setNickname(String newNickname) {
    final clean = newNickname.trim();
    if (clean.isNotEmpty) {
      state = state.copyWith(nickname: clean);
    }
  }

  /// Emergency panic wipe: zeroizes identity and generates a brand new ephemeral key pair.
  Future<void> panicWipe() async {
    final freshKeyPair = await IdentityKeyPair.generate(
      nickname: 'anon_${DateTime.now().millisecondsSinceEpoch % 10000}',
    );
    if (!mounted) return;
    state = IdentityState(
      keyPair: freshKeyPair,
      nickname: freshKeyPair.nickname,
      peerIdHex: freshKeyPair.peerIdHex,
      isInitialized: true,
    );
  }
}

/// Global provider for the local node identity.
final identityProvider = StateNotifierProvider<IdentityNotifier, IdentityState>((ref) {
  final notifier = IdentityNotifier();
  notifier.initialize();
  return notifier;
});
