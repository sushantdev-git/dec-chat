import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/bitchat_coordinator.dart';
import '../../core/utils/geohash.dart';
import '../state/channels_notifier.dart';
import '../state/identity_state.dart';
import '../state/panic_controller.dart';
import '../state/peers_notifier.dart';
import '../state/timeline_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/edit_profile_sheet.dart';
import 'chat_screen.dart';
import 'peer_directory_screen.dart';

/// Main conversation thread list adopting a clean minimalist design.
class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  void _showJoinChannelDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: '#');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCardElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: AppTheme.squircleLarge,
          side: BorderSide(color: AppTheme.darkBorderSubtle, width: 0.8),
        ),
        title: const Text(
          'Join Channel',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a public channel name or geohash location channel (e.g. #9q8yy):',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
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
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        backgroundColor: AppTheme.darkCardElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: AppTheme.squircleLarge,
          side: BorderSide(color: AppTheme.darkBorderSubtle, width: 0.8),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.panicRed, size: 24),
            SizedBox(width: 8),
            Text('Emergency Panic Wipe', style: TextStyle(color: AppTheme.panicRed, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will instantaneously zeroize and delete all in-memory message feeds, wipe active peer sessions, and regenerate a fresh ephemeral cryptographic identity. There is no undo.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.panicRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(panicControllerProvider).executePanicWipe();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Panic wipe completed: all keys and timelines zeroized.'),
                    backgroundColor: AppTheme.panicRed,
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
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => EditProfileSheet.show(context),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: AppTheme.squircleMedium,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    identity.nickname.isNotEmpty ? identity.nickname[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            identity.nickname,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 12, color: AppTheme.textMuted),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppTheme.verifiedGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${identity.peerIdHex.substring(0, 8)} • BLE Mesh Online',
                          style: const TextStyle(fontSize: 11, color: AppTheme.bleMeshBlue),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.textPrimary),
            tooltip: 'Search peers',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PeerDirectoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.emergency_outlined, color: AppTheme.panicRed),
            tooltip: 'Emergency Panic Wipe',
            onPressed: () => _showPanicConfirmDialog(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          // Channels Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CHANNELS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppTheme.textMuted,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showJoinChannelDialog(context, ref),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 14, color: AppTheme.bleMeshBlue),
                        SizedBox(width: 2),
                        Text(
                          'Join',
                          style: TextStyle(fontSize: 12, color: AppTheme.bleMeshBlue, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isLocation ? const Color(0xFF132B45) : AppTheme.darkCard,
                  borderRadius: AppTheme.squircleMedium,
                  border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                ),
                child: Icon(
                  isLocation ? Icons.place : Icons.tag,
                  color: isLocation ? AppTheme.bleMeshBlue : AppTheme.textSecondary,
                  size: 20,
                ),
              ),
              title: Text(
                ch,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              subtitle: Text(
                lastMsg != null
                    ? '${lastMsg.senderNickname}: ${lastMsg.content}'
                    : (isLocation ? 'Geohash Location Channel' : 'Public mesh room'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              trailing: lastMsg != null
                  ? Text(
                      '${lastMsg.timestamp.hour.toString().padLeft(2, '0')}:${lastMsg.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
            padding: EdgeInsets.fromLTRB(16, 22, 16, 6),
            child: Text(
              'DIRECT MESSAGES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppTheme.textMuted,
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
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: AppTheme.squircleMedium,
                    border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                  ),
                  child: const Icon(Icons.lock, size: 18, color: AppTheme.primaryBlue),
                ),
                title: Row(
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (peer?.isVerified ?? false) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 15, color: AppTheme.verifiedGreen),
                    ],
                  ],
                ),
                subtitle: Text(
                  lastMsg?.content ?? 'Encrypted conversation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const RoundedRectangleBorder(borderRadius: AppTheme.pill),
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
