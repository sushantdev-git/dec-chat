import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/chat_command.dart';

/// Floating autocompletion overlay displayed when user types a slash command prefix ('/').
class SlashCommandPopup extends StatelessWidget {
  final String query;
  final ValueChanged<CommandSuggestion> onSelect;

  const SlashCommandPopup({
    super.key,
    required this.query,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final suggestions = ChatCommand.getSuggestions(query);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.darkCardElevated,
        borderRadius: AppTheme.squircleLarge,
        border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => Divider(
          color: Colors.white.withValues(alpha: 0.05),
          height: 1,
        ),
        itemBuilder: (context, index) {
          final item = suggestions[index];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSubtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                    ),
                    child: Text(
                      item.command,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.syntax,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          item.description,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
