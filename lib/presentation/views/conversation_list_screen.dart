import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/bitchat_coordinator.dart';
import '../../core/utils/geohash.dart';
import '../state/channels_notifier.dart';
import '../state/identity_state.dart';
import '../state/panic_controller.dart';
import '../state/peers_notifier.dart';
import '../state/timeline_notifier.dart';
import '../theme/signal_theme.dart';
import 'chat_screen.dart';
import 'peer_directory_screen.dart';

/// Main conversation thread list adopting the Signal UI design pattern.
class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  void _showJoinChannelDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: '#');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SignalTheme.darkCard,
        title: const Text('Join Channel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a public channel name or geohash location channel (e.g. #9q8yy):',
              style: TextStyle(fontSize: 13, color: SignalTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '#channel or #9q8yy',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SignalTheme.signalBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty && text != '#') {
                ref.read(channelsProvider.notifier).joinChannel(text);
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(channelOrPeerId: text),
                  ),
                );
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showPanicConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SignalTheme.darkCard,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: SignalTheme.panicRed, size: 26),
            SizedBox(width: 8),
            Text('Emergency Panic Wipe', style: TextStyle(color: SignalTheme.panicRed)),
          ],
        ),
        content: const Text(
          'This will instantaneously zeroize and delete all in-memory message feeds, wipe active peer sessions, and regenerate a fresh ephemeral cryptographic identity. There is no undo.',
          style: TextStyle(fontSize: 13, color: SignalTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SignalTheme.panicRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(panicControllerProvider).executePanicWipe();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Panic wipe completed: all keys and timelines zeroized.'),
                    backgroundColor: SignalTheme.panicRed,
                  ),
                );
              }
            },
            child: const Text('Execute Wipe'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly initialize and activate the BitChat coordinator (radios + relays)
    ref.watch(bitchatCoordinatorProvider);

    final identity = ref.watch(identityProvider);
    final channelsState = ref.watch(channelsProvider);
    final peersState = ref.watch(peersProvider);
    final timelineState = ref.watch(timelineProvider);

    final channels = channelsState.joinedChannels.toList()..sort();
    final directPeerIds = timelineState.messagesByChannel.keys
        .where((k) => !k.startsWith('#'))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: SignalTheme.signalBlue,
              child: Text(
                identity.nickname.isNotEmpty ? identity.nickname[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    identity.nickname,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${identity.peerIdHex.substring(0, 8)} • BLE Mesh Online',
                    style: const TextStyle(fontSize: 11, color: SignalTheme.bleMeshBlue),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency_outlined, color: SignalTheme.panicRed),
            tooltip: 'Emergency Panic Wipe',
            onPressed: () => _showPanicConfirmDialog(context, ref),
          ),
        ],
      ),
      body: ListView(
        children: [
          // Channels Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CHANNELS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: SignalTheme.textMuted,
                  ),
                ),
                InkWell(
                  onTap: () => _showJoinChannelDialog(context, ref),
                  child: const Row(
                    children: [
                      Icon(Icons.add, size: 14, color: SignalTheme.signalBlue),
                      SizedBox(width: 2),
                      Text(
                        'Join',
                        style: TextStyle(fontSize: 12, color: SignalTheme.signalBlue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Channel List
          ...channels.map((ch) {
            final msgs = timelineState.getMessages(ch);
            final lastMsg = msgs.isNotEmpty ? msgs.last : null;
            final isLocation = Geohash.isLocationChannel(ch);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isLocation ? const Color(0xFF1E3A5F) : SignalTheme.darkCard,
                child: Icon(
                  isLocation ? Icons.place : Icons.tag,
                  color: isLocation ? SignalTheme.bleMeshBlue : Colors.white70,
                  size: 20,
                ),
              ),
              title: Text(
                ch,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Text(
                lastMsg != null ? '${lastMsg.senderNickname}: ${lastMsg.content}' : (isLocation ? 'Geohash Location Channel' : 'Public mesh room'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: SignalTheme.textSecondary),
              ),
              trailing: lastMsg != null
                  ? Text(
                      '${lastMsg.timestamp.hour.toString().padLeft(2, '0')}:${lastMsg.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11, color: SignalTheme.textMuted),
                    )
                  : null,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(channelOrPeerId: ch),
                  ),
                );
              },
            );
          }),

          // Direct Messages Header
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 6),
            child: Text(
              'DIRECT MESSAGES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: SignalTheme.textMuted,
              ),
            ),
          ),

          if (directPeerIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Text(
                  'No direct chats yet.\nTap the radar button below to discover nearby peers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SignalTheme.textMuted, fontSize: 13, height: 1.4),
                ),
              ),
            )
          else
            ...directPeerIds.map((peerId) {
              final peer = peersState.getPeer(peerId);
              final nickname = peer?.nickname ?? 'peer_${peerId.substring(0, 4)}';
              final msgs = timelineState.getMessages(peerId);
              final lastMsg = msgs.isNotEmpty ? msgs.last : null;

              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: SignalTheme.darkCard,
                  child: Icon(Icons.lock, size: 18, color: SignalTheme.signalBlue),
                ),
                title: Row(
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (peer?.isVerified ?? false) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 16, color: SignalTheme.verifiedGreen),
                    ],
                  ],
                ),
                subtitle: Text(
                  lastMsg?.content ?? 'Encrypted conversation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: SignalTheme.textSecondary),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(channelOrPeerId: peerId),
                    ),
                  );
                },
              );
            }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: SignalTheme.signalBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.radar),
        label: Text('Peers (${peersState.allPeers.length})'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PeerDirectoryScreen(),
            ),
          );
        },
      ),
    );
  }
}
