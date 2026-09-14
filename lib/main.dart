import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/theme/signal_theme.dart';
import 'presentation/views/conversation_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: DecChatApp(),
    ),
  );
}

/// DecChat main application entry point adhering to the Signal UI design pattern.
class DecChatApp extends StatelessWidget {
  const DecChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DecChat',
      debugShowCheckedModeBanner: false,
      theme: SignalTheme.darkTheme,
      home: const ConversationListScreen(),
    );
  }
}
