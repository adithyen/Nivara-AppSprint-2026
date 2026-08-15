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

/// Central theme factory configuring both Dark and Light experiences with dynamic accent color seeding.
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
      primary: seed,
      secondary: NivaraColors.primaryBlue,
      tertiary: NivaraColors.accent,
      error: NivaraColors.danger,
      surface: isDark ? NivaraColors.canvasDark : NivaraColors.surfaceLight,
      surfaceContainerHigh: isDark ? NivaraColors.cardDark : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF0D131A) : const Color(0xFFF0F4F8),
      surfaceContainer: isDark ? const Color(0xFF131A24) : const Color(0xFFE8EEF5),
      onSurface: isDark ? Colors.white : const Color(0xFF111827),
      onSurfaceVariant: isDark ? const Color(0xFF9EABB8) : const Color(0xFF6B7280),
    );

    final onPrimary = ThemeData.estimateBrightnessForColor(seed) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? NivaraColors.canvasDark : NivaraColors.surfaceLight,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? NivaraColors.canvasDark : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF111827),
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : const Color(0xFF111827),
        ),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF111827),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: onPrimary,
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
        fillColor: isDark ? NivaraColors.cardDark : const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: seed,
            width: 1.8,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: TextStyle(
          color: isDark ? Colors.white70 : const Color(0xFF4B5563),
          fontSize: 13.5,
        ),
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : const Color(0xFF9CA3AF),
          fontSize: 13.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? NivaraColors.cardDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE5E7EB),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
