import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../theme/signal_theme.dart';
import 'transport_badge.dart';

/// Signal-style chat bubble supporting E2EE lock indicators, transport badges, and delivery states.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _buildSystemBubble(context);
    }

    final isOutgoing = message.isOutgoing;
    final bubbleColor = isOutgoing ? SignalTheme.outgoingBubble : SignalTheme.incomingBubble;
    final align = isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isOutgoing ? const Radius.circular(16) : const Radius.circular(4),
      bottomRight: isOutgoing ? const Radius.circular(4) : const Radius.circular(16),
    );

    final timeString = '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isOutgoing) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.senderNickname,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: SignalTheme.bleMeshBlue,
                        ),
                      ),
                      const SizedBox(width: 6),
                      TransportBadge(medium: message.medium, isCompact: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  message.content,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    color: SignalTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEncrypted) ...[
                      const Icon(Icons.lock, size: 12, color: Colors.white70),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      timeString,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white60,
                      ),
                    ),
                    if (isOutgoing) ...[
                      const SizedBox(width: 4),
                      _buildDeliveryIcon(message.deliveryStatus),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemBubble(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: SignalTheme.systemBubble,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: SignalTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryIcon(MessageDeliveryStatus status) {
    switch (status) {
      case MessageDeliveryStatus.sending:
        return const Icon(Icons.access_time, size: 12, color: Colors.white60);
      case MessageDeliveryStatus.sent:
        return const Icon(Icons.done, size: 13, color: Colors.white70);
      case MessageDeliveryStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: Colors.white);
      case MessageDeliveryStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: SignalTheme.panicRed);
    }
  }
}
