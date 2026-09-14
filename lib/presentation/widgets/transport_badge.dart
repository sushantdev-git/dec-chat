import 'package:flutter/material.dart';
import '../../domain/enums/transport_medium.dart';
import '../theme/app_theme.dart';

/// Visual pill badge indicating whether a packet arrived via offline BLE Mesh or Nostr relays.
class TransportBadge extends StatelessWidget {
  final TransportMedium medium;
  final int? rssi;
  final bool isCompact;

  const TransportBadge({
    super.key,
    required this.medium,
    this.rssi,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String label;
    final Color color;

    switch (medium) {
      case TransportMedium.bleMesh:
        icon = Icons.bluetooth;
        label = rssi != null ? 'BLE $rssi dBm' : 'BLE Mesh';
        color = AppTheme.bleMeshBlue;
        break;
      case TransportMedium.nostr:
        icon = Icons.public;
        label = 'Nostr';
        color = AppTheme.nostrPurple;
        break;
      case TransportMedium.lan:
        icon = Icons.wifi;
        label = 'LAN';
        color = AppTheme.verifiedGreen;
        break;
      case TransportMedium.simulated:
        icon = Icons.memory;
        label = 'Simulated';
        color = Colors.orange;
        break;
    }

    if (isCompact) {
      return Icon(icon, size: 14, color: color);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
