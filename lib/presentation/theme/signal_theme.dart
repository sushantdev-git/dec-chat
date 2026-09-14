import 'package:flutter/material.dart';

/// Signal UI design system theme constants and configuration.
class SignalTheme {
  // Brand & Accent Colors
  static const Color signalBlue = Color(0xFF2C6BED);
  static const Color signalBlueDark = Color(0xFF1E4DB7);
  static const Color verifiedGreen = Color(0xFF22C55E);
  static const Color panicRed = Color(0xFFEF4444);
  static const Color bleMeshBlue = Color(0xFF38BDF8);
  static const Color nostrPurple = Color(0xFFA855F7);

  // Backgrounds & Surfaces
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkCard = Color(0xFF252525);
  static const Color darkBorder = Color(0xFF333333);

  // Chat Bubbles
  static const Color outgoingBubble = Color(0xFF2C6BED);
  static const Color incomingBubble = Color(0xFF2A2A2A);
  static const Color systemBubble = Color(0xFF1F2937);

  // Text Colors
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  /// Builds the high-contrast Material 3 Dark theme matching the Signal privacy design pattern.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: signalBlue,
        onPrimary: Colors.white,
        secondary: bleMeshBlue,
        onSecondary: Colors.black,
        surface: darkSurface,
        onSurface: textPrimary,
        error: panicRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: darkBorder, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        hintStyle: const TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: signalBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }
}
