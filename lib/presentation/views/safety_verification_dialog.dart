import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/peer_model.dart';
import '../state/peers_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/safety_number_card.dart';

/// Modal bottom sheet presenting peer safety numbers and in-person cryptographic verification.
class SafetyVerificationSheet extends ConsumerWidget {
  final String peerId;

  const SafetyVerificationSheet({super.key, required this.peerId});

  static void show(BuildContext context, String peerId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafetyVerificationSheet(peerId: peerId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peersState = ref.watch(peersProvider);
    final peer = peersState.getPeer(peerId) ??
        PeerModel(
          peerId: peerId,
          nickname: 'peer_${peerId.length > 4 ? peerId.substring(0, 4) : peerId}',
          lastSeen: DateTime.now(),
        );

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.darkCardElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 14,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          SafetyNumberCard(
            peer: peer,
            onToggleVerified: () {
              ref.read(peersProvider.notifier).toggleVerification(peerId);
            },
          ),
        ],
      ),
    );
  }
}
