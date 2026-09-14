import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/geohash.dart';
import '../state/peers_notifier.dart';
import '../state/timeline_notifier.dart';
import '../theme/signal_theme.dart';
import '../utils/chat_command.dart';
import '../widgets/message_bubble.dart';
import '../widgets/slash_command_popup.dart';
import 'safety_verification_dialog.dart';

/// Conversation screen displaying ephemeral message history, command input, and safety verification.
class ChatScreen extends ConsumerStatefulWidget {
  final String channelOrPeerId;

  const ChatScreen({super.key, required this.channelOrPeerId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text;
    if (text.startsWith('/')) {
      setState(() => _currentQuery = text);
    } else if (_currentQuery.isNotEmpty) {
      setState(() => _currentQuery = '');
    }
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    ref.read(timelineProvider.notifier).sendUserMessage(
          channelOrPeerId: widget.channelOrPeerId,
          text: text,
        );

    _textController.clear();
    setState(() => _currentQuery = '');

    // Auto-scroll to latest message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectSuggestion(CommandSuggestion suggestion) {
    _textController.text = '${suggestion.command} ';
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );
    setState(() => _currentQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    final timelineState = ref.watch(timelineProvider);
    final messages = timelineState.getMessages(widget.channelOrPeerId);

    final isChannel = widget.channelOrPeerId.startsWith('#');
    final isLocationChannel = isChannel && Geohash.isLocationChannel(widget.channelOrPeerId);

    final peersState = ref.watch(peersProvider);
    final peer = isChannel ? null : peersState.getPeer(widget.channelOrPeerId);
    final displayName = isChannel
        ? widget.channelOrPeerId
        : (peer?.nickname ?? 'peer_${widget.channelOrPeerId.substring(0, 4)}');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: isChannel ? SignalTheme.signalBlueDark : SignalTheme.darkCard,
              child: Icon(
                isLocationChannel
                    ? Icons.place
                    : isChannel
                        ? Icons.tag
                        : Icons.person,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (peer?.isVerified ?? false) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 16, color: SignalTheme.verifiedGreen),
                      ],
                    ],
                  ),
                  Text(
                    isChannel
                        ? (isLocationChannel ? 'Geohash Location Channel' : 'Public Mesh Channel')
                        : 'End-to-End Encrypted (Noise XX)',
                    style: const TextStyle(fontSize: 11, color: SignalTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!isChannel)
            IconButton(
              icon: const Icon(Icons.shield_outlined),
              tooltip: 'Safety Numbers',
              onPressed: () => SafetyVerificationSheet.show(context, widget.channelOrPeerId),
            ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'clear') {
                ref.read(timelineProvider.notifier).clearChannel(widget.channelOrPeerId);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear Timeline'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Message feed
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        isChannel
                            ? 'No messages in $displayName yet.\nSend a message or type /help for commands.'
                            : 'Direct chat with $displayName.\nEnd-to-end encrypted with forward secrecy.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: SignalTheme.textMuted, height: 1.5),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        return MessageBubble(message: messages[index]);
                      },
                    ),
            ),

            // Autocomplete popup
            if (_currentQuery.isNotEmpty)
              SlashCommandPopup(
                query: _currentQuery,
                onSelect: _selectSuggestion,
              ),

            // Composer bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: SignalTheme.darkSurface,
                border: Border(top: BorderSide(color: SignalTheme.darkBorder, width: 0.8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: isChannel
                            ? 'Message $displayName or /command...'
                            : 'Signal message or /command...',
                        filled: true,
                        fillColor: SignalTheme.darkCard,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: SignalTheme.signalBlue,
                    radius: 22,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 19),
                      onPressed: _handleSend,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
