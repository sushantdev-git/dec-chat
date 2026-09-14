import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/identity_state.dart';
import '../state/peers_notifier.dart';
import '../theme/signal_theme.dart';
import '../widgets/transport_badge.dart';
import 'chat_screen.dart';
import 'safety_verification_dialog.dart';

/// Screen listing active discovered mesh peers with signal meters, hop counts, and safety statuses.
class PeerDirectoryScreen extends ConsumerWidget {
  const PeerDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider);
    final peersState = ref.watch(peersProvider);
    final peers = peersState.allPeers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovered Peers'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Local Node Identity Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SignalTheme.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SignalTheme.darkBorder),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: SignalTheme.signalBlueDark,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            identity.nickname,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: SignalTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: SignalTheme.signalBlue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(fontSize: 10, color: SignalTheme.bleMeshBlue),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'ID: ${identity.peerIdHex.substring(0, 8)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: SignalTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'NEARBY NODES IN RADIO RANGE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: SignalTheme.textMuted,
              ),
            ),
          ),

          if (peers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Center(
                child: Text(
                  'No mesh peers discovered yet.\nPeers within Bluetooth Low Energy radio range (~30m) or Nostr internet relays will appear here automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SignalTheme.textSecondary, height: 1.5),
                ),
              ),
            )
          else
            ...peers.map((peer) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: SignalTheme.darkCard,
                  child: Icon(
                    peer.isDirectNeighbor ? Icons.bluetooth : Icons.router,
                    color: SignalTheme.bleMeshBlue,
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      peer.nickname,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (peer.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 16, color: SignalTheme.verifiedGreen),
                    ],
                    const SizedBox(width: 8),
                    TransportBadge(medium: peer.medium, isCompact: true),
                  ],
                ),
                subtitle: Text(
                  '${peer.isDirectNeighbor ? '1-hop direct' : '${peer.hops}-hops'} • ${peer.signalQuality}',
                  style: const TextStyle(fontSize: 12, color: SignalTheme.textSecondary),
                ),
                trailing: IconButton(
                  icon: Icon(
                    peer.isVerified ? Icons.verified_user : Icons.shield_outlined,
                    color: peer.isVerified ? SignalTheme.verifiedGreen : SignalTheme.textSecondary,
                  ),
                  tooltip: 'Safety Numbers',
                  onPressed: () => SafetyVerificationSheet.show(context, peer.peerId),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(channelOrPeerId: peer.peerId),
                    ),
                  );
                },
              );
            }),
        ],
      ),
    );
  }
}
