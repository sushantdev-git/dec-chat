import 'package:flutter/material.dart';

/// Minimalist design system theme constants and configuration.
class AppTheme {
  // Brand & Accent Colors (Monochrome Crisp Palette)
  static const Color primaryAccent = Color(0xFFFAFAFA); // Crisp Zinc-50 / Pure White
  static const Color onPrimaryAccent = Color(0xFF09090B); // Deep Zinc-950 Black
  static const Color accentSubtle = Color(0x1FFFFFFF); // 12% white fill for chips/badges
  static const Color primaryBlue = primaryAccent; // Backward-compatible alias
  static const Color primaryBlueDark = Color(0xFFE4E4E7); // Zinc-200
  static const Color bleMeshBlue = Color(0xFFE4E4E7); // Crisp Zinc-200 for radio/mesh
  static const Color verifiedGreen = Color(0xFF34D399); // Emerald-400
  static const Color panicRed = Color(0xFFF87171); // Rose-400
  static const Color nostrPurple = Color(0xFFC084FC); // Purple-400

  // Neutral Surfaces (Zinc Palette)
  static const Color darkBackground = Color(0xFF09090B); // Zinc-950
  static const Color darkSurface = Color(0xFF121215); // Layered Surface
  static const Color darkCard = Color(0xFF18181B); // Zinc-900
  static const Color darkCardElevated = Color(0xFF202024);
  static const Color darkBorder = Color(0xFF27272A); // Zinc-800
  static const Color darkBorderSubtle = Color(0x14FFFFFF); // ~8% white hairline

  // Chat Bubbles
  static const Color outgoingBubble = Color(0xFF27272A); // Zinc-800 slate
  static const Color incomingBubble = Color(0xFF18181B); // Zinc-900 card
  static const Color systemBubble = Color(0x0FFFFFFF); // Transparent ghost chip

  // Typography Colors
  static const Color textPrimary = Color(0xFFFAFAFA); // Zinc-50
  static const Color textSecondary = Color(0xFFA1A1AA); // Zinc-400
  static const Color textMuted = Color(0xFF71717A); // Zinc-500

  // Geometry & Radii
  static const double radiusSmall = 10.0;
  static const double radiusMedium = 14.0;
  static const double radiusLarge = 18.0;
  static const double radiusPill = 28.0;

  static const BorderRadius squircleSmall = BorderRadius.all(Radius.circular(radiusSmall));
  static const BorderRadius squircleMedium = BorderRadius.all(Radius.circular(radiusMedium));
  static const BorderRadius squircleLarge = BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(radiusPill));

  /// Builds the clean minimalist dark theme.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        onPrimary: onPrimaryAccent,
        secondary: textSecondary,
        onSecondary: onPrimaryAccent,
        surface: darkSurface,
        onSurface: textPrimary,
        error: panicRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: darkBorderSubtle, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        hintStyle: const TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: const BorderSide(color: darkBorderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: const BorderSide(color: darkBorderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: const BorderSide(color: primaryAccent, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }
}
