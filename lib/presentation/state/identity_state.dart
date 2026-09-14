import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/identity_key_pair.dart';
import '../../domain/services/panic_zeroization_service.dart';
import '../../infrastructure/services/local_storage_service.dart';

/// State holding local node identity, keys, and display nickname.
class IdentityState {
  final IdentityKeyPair? keyPair;
  final String nickname;
  final String peerIdHex;
  /// Optional phone number for peer discovery (Phase 10).
  final String? phoneNumber;
  final bool isInitialized;

  const IdentityState({
    this.keyPair,
    required this.nickname,
    required this.peerIdHex,
    this.phoneNumber,
    this.isInitialized = false,
  });

  IdentityState copyWith({
    IdentityKeyPair? keyPair,
    String? nickname,
    String? peerIdHex,
    Object? phoneNumber = _sentinel,
    bool? isInitialized,
  }) {
    return IdentityState(
      keyPair: keyPair ?? this.keyPair,
      nickname: nickname ?? this.nickname,
      peerIdHex: peerIdHex ?? this.peerIdHex,
      phoneNumber: phoneNumber == _sentinel ? this.phoneNumber : phoneNumber as String?,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// Sentinel for nullable copyWith
const Object _sentinel = Object();

/// StateNotifier managing local user identity and cryptographic keys.
class IdentityNotifier extends StateNotifier<IdentityState> {
  final LocalStorageService? storageService;

  IdentityNotifier([IdentityState? initial, this.storageService])
      : super(initial ??
            const IdentityState(
              nickname: 'anon_node',
              peerIdHex: '0000000000000000',
              isInitialized: false,
            ));

  /// Initializes with real cryptographic keys asynchronously, restoring from disk if available.
  Future<void> initialize({String? nickname}) async {
    final defaultNickname = state.nickname;

    // 1. Attempt to restore persistent identity from disk
    if (storageService != null) {
      try {
        final saved = await storageService!.loadIdentity();
        if (!mounted) return;
        if (saved != null) {
          final restored = await IdentityKeyPair.fromJson(saved);
          if (!mounted) return;
          final effectiveNickname = nickname ?? restored.nickname;
          final finalPair = effectiveNickname != restored.nickname
              ? await IdentityKeyPair.create(
                  nickname: effectiveNickname,
                  phoneNumber: restored.phoneNumber,
                  noiseKeyPair: restored.noiseKeyPair,
                  signingKeyPair: restored.signingKeyPair,
                )
              : restored;

          if (effectiveNickname != restored.nickname) {
            final json = await finalPair.toJson();
            await storageService!.saveIdentity(json);
          }

          if (!mounted) return;
          state = IdentityState(
            keyPair: finalPair,
            nickname: finalPair.nickname,
            peerIdHex: finalPair.peerIdHex,
            phoneNumber: finalPair.phoneNumber,
            isInitialized: true,
          );
          return;
        }
      } catch (_) {
        // Fall back to generating a fresh identity if disk corrupted
      }
    }

    if (!mounted) return;

    // 2. No saved identity found, generate fresh and persist
    final effectiveNickname = nickname ?? defaultNickname;
    final pair = await IdentityKeyPair.generate(nickname: effectiveNickname);
    if (!mounted) return;

    if (storageService != null) {
      try {
        final json = await pair.toJson();
        await storageService!.saveIdentity(json);
      } catch (_) {}
    }

    if (!mounted) return;
    state = IdentityState(
      keyPair: pair,
      nickname: pair.nickname,
      peerIdHex: pair.peerIdHex,
      phoneNumber: pair.phoneNumber,
      isInitialized: true,
    );
  }

  /// Updates the local user's broadcast nickname and persists change.
  void setNickname(String newNickname) {
    final clean = newNickname.trim();
    if (clean.isEmpty || clean == state.nickname) return;

    if (state.keyPair != null) {
      IdentityKeyPair.create(
        nickname: clean,
        phoneNumber: state.keyPair!.phoneNumber,
        noiseKeyPair: state.keyPair!.noiseKeyPair,
        signingKeyPair: state.keyPair!.signingKeyPair,
      ).then((updatedPair) async {
        if (!mounted) return;
        state = state.copyWith(nickname: clean, keyPair: updatedPair);
        if (storageService != null) {
          try {
            final json = await updatedPair.toJson();
            await storageService!.saveIdentity(json);
          } catch (_) {}
        }
      });
    } else {
      state = state.copyWith(nickname: clean);
    }
  }

  /// Updates the local user's broadcast phone number (opt-in) and persists change.
  /// Pass null or empty string to clear the phone number.
  void setPhoneNumber(String? newPhone) {
    final clean = (newPhone ?? '').trim();
    final effectivePhone = clean.isEmpty ? null : clean;
    if (effectivePhone == state.phoneNumber) return;

    if (state.keyPair != null) {
      IdentityKeyPair.create(
        nickname: state.keyPair!.nickname,
        phoneNumber: effectivePhone,
        noiseKeyPair: state.keyPair!.noiseKeyPair,
        signingKeyPair: state.keyPair!.signingKeyPair,
      ).then((updatedPair) async {
        if (!mounted) return;
        state = state.copyWith(phoneNumber: effectivePhone, keyPair: updatedPair);
        if (storageService != null) {
          try {
            final json = await updatedPair.toJson();
            await storageService!.saveIdentity(json);
          } catch (_) {}
        }
      });
    } else {
      state = state.copyWith(phoneNumber: effectivePhone);
    }
  }

  /// Emergency panic wipe: zeroizes identity, purges disk storage, and generates fresh ephemeral keys.
  Future<void> panicWipe() async {
    if (state.keyPair != null) {
      PanicZeroizationService.scrubBytes(state.keyPair!.peerId);
    }
    if (storageService != null) {
      await storageService!.wipeAll();
    }
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
  final storage = ref.watch(localStorageServiceProvider);
  final notifier = IdentityNotifier(null, storage);
  notifier.initialize();
  return notifier;
});
