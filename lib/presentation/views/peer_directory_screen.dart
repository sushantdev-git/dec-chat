import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/identity_state.dart';
import '../state/peers_notifier.dart';
import '../theme/signal_theme.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/transport_badge.dart';
import 'chat_screen.dart';
import 'safety_verification_dialog.dart';

/// Screen listing active discovered mesh peers with signal meters, hop counts, and safety statuses.
/// Supports live search by nickname, phone number, or peer ID prefix.
class PeerDirectoryScreen extends ConsumerStatefulWidget {
  const PeerDirectoryScreen({super.key});

  @override
  ConsumerState<PeerDirectoryScreen> createState() => _PeerDirectoryScreenState();
}

class _PeerDirectoryScreenState extends ConsumerState<PeerDirectoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isPhoneMatch(peer) {
    if (_query.isEmpty || peer.phoneNumber == null) return false;
    final queryDigits = _query.replaceAll(RegExp(r'[^\d]'), '');
    final peerDigits = peer.phoneNumber!.replaceAll(RegExp(r'[^\d]'), '');
    if (queryDigits.isNotEmpty && peerDigits.contains(queryDigits)) return true;
    final q = _query.toLowerCase();
    if (peer.phoneNumber!.toLowerCase().contains(q)) return true;
    return false;
  }

  /// Returns true if the peer matches the current search query.
  /// Matches on nickname prefix, phone number (digits-only substring), or peer ID prefix.
  bool _matches(peer) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    // 1. Nickname (case-insensitive prefix)
    if (peer.nickname.toLowerCase().contains(q)) return true;
    // 2. Peer ID (prefix)
    if (peer.peerId.toLowerCase().startsWith(q)) return true;
    // 3. Phone number — compare digits only so "+91 98765" matches "9198765"
    if (_isPhoneMatch(peer)) return true;
    return false;
  }

  void _copyId(BuildContext context, String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Peer ID copied to clipboard'),
        backgroundColor: SignalTheme.signalBlueDark,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProvider);
    final peersState = ref.watch(peersProvider);
    final allPeers = peersState.allPeers;
    final filtered = allPeers.where(_matches).toList();

    // Format peer ID as groups of 4: C0E6 4DED E5F6 0718
    String formatId(String hex) {
      final upper = hex.toUpperCase();
      final buf = StringBuffer();
      for (int i = 0; i < upper.length; i++) {
        if (i > 0 && i % 4 == 0) buf.write(' ');
        buf.write(upper[i]);
      }
      return buf.toString();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovered Peers'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Your Identity Card ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SignalTheme.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SignalTheme.signalBlueDark.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: SignalTheme.signalBlueDark,
                  child: Text(
                    identity.nickname.isNotEmpty ? identity.nickname[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              identity.nickname,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: SignalTheme.textPrimary,
                              ),
                            ),
                          ),
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
                      const SizedBox(height: 4),
                      // Formatted peer ID with copy button
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatId(identity.peerIdHex),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: SignalTheme.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _copyId(context, identity.peerIdHex),
                            child: const Tooltip(
                              message: 'Copy peer ID',
                              child: Icon(Icons.copy, size: 14, color: SignalTheme.textMuted),
                            ),
                          ),
                        ],
                      ),
                      // Phone number (if set)
                      if (identity.phoneNumber != null && identity.phoneNumber!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 12, color: SignalTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              identity.phoneNumber!,
                              style: const TextStyle(fontSize: 12, color: SignalTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Edit profile button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20, color: SignalTheme.textSecondary),
                  tooltip: 'Edit profile',
                  onPressed: () => EditProfileSheet.show(context),
                ),
              ],
            ),
          ),

          // ── Search Bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or peer ID…',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20, color: SignalTheme.textSecondary),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: SignalTheme.textSecondary),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: SignalTheme.darkCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: SignalTheme.darkBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: SignalTheme.darkBorder),
                ),
              ),
            ),
          ),

          // ── Nearby Nodes ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                const Expanded(
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
                if (_query.isNotEmpty)
                  Text(
                    '${filtered.length} of ${allPeers.length}',
                    style: const TextStyle(fontSize: 11, color: SignalTheme.textMuted),
                  ),
              ],
            ),
          ),

          if (allPeers.isEmpty)
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
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Center(
                child: Text(
                  'No peers match "$_query"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: SignalTheme.textSecondary, height: 1.5),
                ),
              ),
            )
          else
            ...filtered.map((peer) {
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
                  _isPhoneMatch(peer)
                      ? 'Phone match'
                      : (peer.isDirectNeighbor ? 'Nearby' : '${peer.hops}-hop relay'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _isPhoneMatch(peer) ? SignalTheme.signalBlue : SignalTheme.textSecondary,
                  ),
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
