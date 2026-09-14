import 'package:flutter/material.dart';

void main() {
  runApp(const DecChatApp());
}

class DecChatApp extends StatelessWidget {
  const DecChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DecChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C6BED), // Signal Blue
          brightness: Brightness.dark,
        ),
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'DecChat Mesh Messenger',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
