import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/enums.dart';

/// State representation for all in-app accessibility preferences.
@immutable
class AccessibilityState {
  final double textScaleFactor;
  final bool highContrast;
  final bool removeAnimations;
  final ColorCorrectionMode colorCorrectionMode;
  final bool hapticsEnabled;
  final bool ignoreRepeatedTaps;
  final double ignoreRepeatDuration;
  final bool voiceAlertsEnabled;

  const AccessibilityState({
    this.textScaleFactor = 1.0,
    this.highContrast = false,
    this.removeAnimations = false,
    this.colorCorrectionMode = ColorCorrectionMode.none,
    this.hapticsEnabled = false,
    this.ignoreRepeatedTaps = false,
    this.ignoreRepeatDuration = 0.30,
    this.voiceAlertsEnabled = false,
  });

  AccessibilityState copyWith({
    double? textScaleFactor,
    bool? highContrast,
    bool? removeAnimations,
    ColorCorrectionMode? colorCorrectionMode,
    bool? hapticsEnabled,
    bool? ignoreRepeatedTaps,
    double? ignoreRepeatDuration,
    bool? voiceAlertsEnabled,
  }) {
    return AccessibilityState(
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      highContrast: highContrast ?? this.highContrast,
      removeAnimations: removeAnimations ?? this.removeAnimations,
      colorCorrectionMode: colorCorrectionMode ?? this.colorCorrectionMode,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      ignoreRepeatedTaps: ignoreRepeatedTaps ?? this.ignoreRepeatedTaps,
      ignoreRepeatDuration: ignoreRepeatDuration ?? this.ignoreRepeatDuration,
      voiceAlertsEnabled: voiceAlertsEnabled ?? this.voiceAlertsEnabled,
    );
  }
}

final accessibilityControllerProvider =
    NotifierProvider<AccessibilityController, AccessibilityState>(
  AccessibilityController.new,
);

class AccessibilityController extends Notifier<AccessibilityState> {
  static const _kTextScale = 'a11y_text_scale';
  static const _kHighContrast = 'a11y_high_contrast';
  static const _kRemoveAnimations = 'a11y_remove_animations';
  static const _kColorCorrection = 'a11y_color_correction';
  static const _kHaptics = 'a11y_haptics';
  static const _kIgnoreRepeated = 'a11y_ignore_repeated';
  static const _kIgnoreRepeatDur = 'a11y_ignore_repeat_dur';
  static const _kVoiceAlerts = 'a11y_voice_alerts';

  // Legacy keys for migration
  static const _kLegacyReduceMotion = 'a11y_reduce_motion';

  @override
  AccessibilityState build() {
    _load();
    return const AccessibilityState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // Migrate legacy reduceMotion → removeAnimations
    bool removeAnim = prefs.getBool(_kRemoveAnimations) ?? false;
    if (!removeAnim && (prefs.getBool(_kLegacyReduceMotion) ?? false)) {
      removeAnim = true;
      await prefs.setBool(_kRemoveAnimations, true);
      await prefs.remove(_kLegacyReduceMotion);
    }

    state = AccessibilityState(
      textScaleFactor: prefs.getDouble(_kTextScale) ?? 1.0,
      highContrast: prefs.getBool(_kHighContrast) ?? false,
      removeAnimations: removeAnim,
      colorCorrectionMode: ColorCorrectionMode.fromWire(
        prefs.getString(_kColorCorrection),
      ),
      hapticsEnabled: prefs.getBool(_kHaptics) ?? false,
      ignoreRepeatedTaps: prefs.getBool(_kIgnoreRepeated) ?? false,
      ignoreRepeatDuration: prefs.getDouble(_kIgnoreRepeatDur) ?? 0.30,
      voiceAlertsEnabled: prefs.getBool(_kVoiceAlerts) ?? false,
    );
  }

  Future<void> setTextScaleFactor(double value) async {
    state = state.copyWith(textScaleFactor: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTextScale, value);
  }

  Future<void> setHighContrast(bool value) async {
    state = state.copyWith(highContrast: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHighContrast, value);
  }

  Future<void> setRemoveAnimations(bool value) async {
    state = state.copyWith(removeAnimations: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemoveAnimations, value);
  }

  Future<void> setColorCorrectionMode(ColorCorrectionMode mode) async {
    state = state.copyWith(colorCorrectionMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kColorCorrection, mode.wire);
  }

  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    if (value) HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHaptics, value);
  }

  Future<void> setIgnoreRepeatedTaps(bool value) async {
    state = state.copyWith(ignoreRepeatedTaps: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIgnoreRepeated, value);
  }

  Future<void> setIgnoreRepeatDuration(double value) async {
    final clamped = (double.parse(value.clamp(0.10, 4.00).toStringAsFixed(2)));
    state = state.copyWith(ignoreRepeatDuration: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kIgnoreRepeatDur, clamped);
  }

  Future<void> setVoiceAlertsEnabled(bool value) async {
    state = state.copyWith(voiceAlertsEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVoiceAlerts, value);
  }
}
