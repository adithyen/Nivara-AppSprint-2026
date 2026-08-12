import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-controllable appearance settings — theme mode + accent colour —
/// persisted with [SharedPreferences] so they survive restarts.
///
/// [sharedPreferencesProvider] is overridden in `main.dart` with the instance
/// loaded at boot, which lets [SettingsController.build] read the saved values
/// synchronously (no loading flash on the very first frame).

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() with the loaded '
    'SharedPreferences instance.',
  ),
);

/// A brand-tinted accent the user can pick. The chosen colour seeds the whole
/// [ColorScheme] (buttons, app bar, chips, selection) — the app is no longer
/// "blue only".
enum AppAccent {
  civicBlue('Civic Blue', 0xFF1B6CA8),
  teal('Teal', 0xFF0E8388),
  indigo('Indigo', 0xFF3F51B5),
  violet('Violet', 0xFF7B4BC4),
  magenta('Magenta', 0xFFC2185B),
  emerald('Emerald', 0xFF1E8E5A),
  sunset('Sunset', 0xFFE8590C),
  crimson('Crimson', 0xFFC0392B);

  const AppAccent(this.label, this.colorValue);
  final String label;
  final int colorValue;

  Color get color => Color(colorValue);

  static AppAccent fromName(String? name) => values.firstWhere(
    (e) => e.name == name,
    orElse: () => AppAccent.civicBlue,
  );
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.accent = AppAccent.civicBlue,
  });

  final ThemeMode themeMode;
  final AppAccent accent;

  AppSettings copyWith({ThemeMode? themeMode, AppAccent? accent}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
      );
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  static const _kThemeMode = 'settings.themeMode';
  static const _kAccent = 'settings.accent';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() => AppSettings(
    themeMode: _themeModeFromName(_prefs.getString(_kThemeMode)),
    accent: AppAccent.fromName(_prefs.getString(_kAccent)),
  );

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setAccent(AppAccent accent) async {
    state = state.copyWith(accent: accent);
    await _prefs.setString(_kAccent, accent.name);
  }
}

ThemeMode _themeModeFromName(String? name) => switch (name) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Human label for the theme-mode segmented control.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
  ThemeMode.system => 'System',
};
