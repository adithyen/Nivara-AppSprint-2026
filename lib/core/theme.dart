import 'package:flutter/material.dart';

/// Nivara brand palette + Material 3 theme.
///
/// Never hardcode these hex values in widgets — reference [NivaraColors] or the
/// `Theme.of(context).colorScheme` roles instead.
abstract final class NivaraColors {
  static const Color primary = Color(0xFF1B6CA8); // civic blue
  static const Color accent = Color(0xFFF5A623); // alert amber
  static const Color success = Color(0xFF27AE60); // resolved green
  static const Color danger = Color(0xFFE74C3C); // emergency red

  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceDark = Color(0xFF121517);
}

/// Central theme factory. `NivaraTheme.light` / `.dark` feed [MaterialApp].
abstract final class NivaraTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: NivaraColors.primary,
      brightness: brightness,
      primary: NivaraColors.primary,
      secondary: NivaraColors.accent,
      error: NivaraColors.danger,
      surface: isDark ? NivaraColors.surfaceDark : NivaraColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: NivaraColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
      ),
    );
  }
}
