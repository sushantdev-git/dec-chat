import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/theme/app_theme.dart';
import 'presentation/views/conversation_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: GridApp(),
    ),
  );
}

/// Grid main application entry point adhering to minimalist design.
class GridApp extends StatelessWidget {
  const GridApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grid',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const ConversationListScreen(),
    );
  }
}
