import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/peer_model.dart';
import '../theme/app_theme.dart';

/// Cryptographic 60-digit safety number comparison card with in-person verification toggle.
class SafetyNumberCard extends StatelessWidget {
  final PeerModel peer;
  final VoidCallback onToggleVerified;

  const SafetyNumberCard({
    super.key,
    required this.peer,
    required this.onToggleVerified,
  });

  @override
  Widget build(BuildContext context) {
    final safetyNumber = peer.formattedSafetyNumber ??
        '00000 00000 00000 00000 00000 00000 00000 00000 00000 00000 00000 00000';
    final blocks = safetyNumber.split(' ');

    return Card(
      color: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: AppTheme.squircleLarge,
        side: BorderSide(color: AppTheme.darkBorderSubtle, width: 0.8),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  peer.isVerified ? Icons.verified_user : Icons.shield_outlined,
                  color: peer.isVerified ? AppTheme.verifiedGreen : AppTheme.textSecondary,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  'Safety Number with ${peer.nickname}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Compare these numbers in person with your contact to verify that your messages are end-to-end encrypted.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),

            // 60-digit number formatted into 3 columns of 4 rows (12 blocks of 5 digits)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: AppTheme.squircleMedium,
                border: Border.all(color: AppTheme.darkBorderSubtle),
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: blocks.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  return Center(
                    child: Text(
                      blocks[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 15,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // Copy button
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: safetyNumber));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Safety number copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Safety Number'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textPrimary),
            ),
            const Divider(height: 24, color: AppTheme.darkBorderSubtle),

            // Verification toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Mark as Verified',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                peer.isVerified
                    ? 'Cryptographically verified in person'
                    : 'Unverified peer identity',
                style: TextStyle(
                  fontSize: 12,
                  color: peer.isVerified ? AppTheme.verifiedGreen : AppTheme.textSecondary,
                ),
              ),
              activeTrackColor: AppTheme.verifiedGreen,
              value: peer.isVerified,
              onChanged: (_) => onToggleVerified(),
            ),
          ],
        ),
      ),
    );
  }
}
