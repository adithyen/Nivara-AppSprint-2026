import 'package:flutter/material.dart';

/// Nivara 2026 Flagship Cyber-Civic Design Palette.
///
/// Curated non-generic tokens combining deep void dark surfaces,
/// frosted glass containers, and vibrant neon accents.
abstract final class NivaraColors {
  // Brand Accents
  static const Color primary = Color(0xFF00E676); // Neon Emerald
  static const Color primaryBlue = Color(0xFF00B0FF); // Cyber Cyan
  static const Color accent = Color(0xFFFFB300); // Amber Pulse
  static const Color success = Color(0xFF00E676); // Resolved Emerald
  static const Color danger = Color(0xFFFF5252); // Emergency Rose
  static const Color warning = Color(0xFFFF9100); // Warning Orange
  static const Color purple = Color(0xFF7C4DFF); // Civic Badge Purple

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient alertGradient = LinearGradient(
    colors: [Color(0xFFFF5252), Color(0xFFFF9100)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Surface Tokens
  static const Color canvasDark = Color(0xFF080C10); // Deepest background
  static const Color cardDark = Color(0xFF10161E); // Standard glass card base
  static const Color surfaceGlass = Color(0xFF131A24); // Frosted overlay base
  static const Color elevatedDark = Color(0xFF182230); // Elevated control base
  static const Color strokeDark = Color(0x24FFFFFF); // Hairline border

  // Light fallback (for contrast references)
  static const Color surfaceLight = Color(0xFFF6F8FB);
}

/// Central theme factory configuring the entire Material 3 dark experience.
abstract final class NivaraTheme {
  static ThemeData light([Color seed = NivaraColors.primary]) =>
      _build(Brightness.light, seed);
  static ThemeData dark([Color seed = NivaraColors.primary]) =>
      _build(Brightness.dark, seed);

  static ThemeData _build(Brightness brightness, Color seed) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: NivaraColors.primary,
      secondary: NivaraColors.primaryBlue,
      tertiary: NivaraColors.accent,
      error: NivaraColors.danger,
      surface: isDark ? NivaraColors.canvasDark : NivaraColors.surfaceLight,
      surfaceContainerHigh: isDark ? NivaraColors.cardDark : Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? NivaraColors.canvasDark : NivaraColors.surfaceLight,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? NivaraColors.canvasDark : Colors.white,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NivaraColors.primary,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? NivaraColors.cardDark : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: NivaraColors.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 13.5,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 13.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? NivaraColors.cardDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
    );
  }
}
