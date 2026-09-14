import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/geohash.dart';
import '../state/identity_state.dart';
import '../state/peers_notifier.dart';
import '../state/timeline_notifier.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
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

    // Intercept profile commands before they reach the timeline
    if (ChatCommand.isCommand(text)) {
      final cmd = ChatCommand.parse(text);

      if (cmd.type == ChatCommandType.nick) {
        if (cmd.errorMessage != null) {
          _showSystemMessage(cmd.errorMessage!);
        } else if (cmd.argument != null && cmd.argument!.isNotEmpty) {
          ref.read(identityProvider.notifier).setNickname(cmd.argument!);
          _showSystemMessage('Nickname changed to "${cmd.argument}"');
        }
        _textController.clear();
        setState(() => _currentQuery = '');
        return;
      }

      if (cmd.type == ChatCommandType.phone) {
        if (cmd.errorMessage != null) {
          _showSystemMessage(cmd.errorMessage!);
        } else {
          final phone = cmd.argument ?? '';
          ref.read(identityProvider.notifier).setPhoneNumber(phone.isEmpty ? null : phone);
          _showSystemMessage(
            phone.isEmpty ? 'Phone number cleared.' : 'Phone number set to "$phone"',
          );
        }
        _textController.clear();
        setState(() => _currentQuery = '');
        return;
      }
    }

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

  void _showSystemMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.primaryBlueDark,
        duration: const Duration(seconds: 3),
      ),
    );
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
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isChannel ? AppTheme.primaryBlueDark : AppTheme.darkCardElevated,
                borderRadius: AppTheme.squircleMedium,
                border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
              ),
              child: Icon(
                isLocationChannel
                    ? Icons.place
                    : isChannel
                        ? Icons.tag
                        : Icons.person,
                size: 19,
                color: Colors.white,
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
                          displayName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (peer?.isVerified ?? false) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.verified, size: 15, color: AppTheme.verifiedGreen),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isChannel
                        ? (isLocationChannel ? 'Geohash Location Channel' : 'Public Mesh Channel')
                        : 'End-to-End Encrypted (Noise XX)',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
                        style: const TextStyle(color: AppTheme.textMuted, height: 1.5),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final prevMsg = index > 0 ? messages[index - 1] : null;
                        final nextMsg = index < messages.length - 1 ? messages[index + 1] : null;

                        bool isSameSender(ChatMessage a, ChatMessage? b) {
                          if (b == null || b.isSystem || a.isSystem) return false;
                          if (a.isOutgoing != b.isOutgoing) return false;
                          if (!a.isOutgoing && a.senderId != b.senderId) return false;
                          return a.timestamp.difference(b.timestamp).abs().inMinutes < 2;
                        }

                        final isPrevSame = isSameSender(msg, prevMsg);
                        final isNextSame = isSameSender(msg, nextMsg);

                        final BubblePosition position;
                        if (!isPrevSame && !isNextSame) {
                          position = BubblePosition.single;
                        } else if (!isPrevSame && isNextSame) {
                          position = BubblePosition.first;
                        } else if (isPrevSame && isNextSame) {
                          position = BubblePosition.middle;
                        } else {
                          position = BubblePosition.last;
                        }

                        return MessageBubble(
                          message: msg,
                          position: position,
                          showHeader: !isPrevSame,
                        );
                      },
                    ),
            ),

            // Autocomplete popup
            if (_currentQuery.isNotEmpty)
              SlashCommandPopup(
                query: _currentQuery,
                onSelect: _selectSuggestion,
              ),

            // Floating Capsule Composer
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: AppTheme.pill,
                  border: Border.all(color: AppTheme.darkBorderSubtle, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: 5,
                        style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText: isChannel
                              ? 'Message $displayName or /command...'
                              : 'Message or /command...',
                          hintStyle: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        ),
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 6),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _textController,
                        builder: (_, val, __) {
                          final hasText = val.text.trim().isNotEmpty;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _handleSend,
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: hasText ? AppTheme.primaryBlue : AppTheme.darkBorder,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.send,
                                  color: hasText ? Colors.white : AppTheme.textMuted,
                                  size: 16,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
