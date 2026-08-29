import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// State representation for all in-app accessibility preferences.
@immutable
class AccessibilityState {
  final bool reduceMotion;
  final double textScaleFactor;
  final bool highContrast;
  final bool colorBlindAssistance;
  final bool hapticsEnabled;
  final bool screenReaderAnnouncements;

  const AccessibilityState({
    this.reduceMotion = false,
    this.textScaleFactor = 1.0,
    this.highContrast = false,
    this.colorBlindAssistance = false,
    this.hapticsEnabled = true,
    this.screenReaderAnnouncements = true,
  });

  AccessibilityState copyWith({
    bool? reduceMotion,
    double? textScaleFactor,
    bool? highContrast,
    bool? colorBlindAssistance,
    bool? hapticsEnabled,
    bool? screenReaderAnnouncements,
  }) {
    return AccessibilityState(
      reduceMotion: reduceMotion ?? this.reduceMotion,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      highContrast: highContrast ?? this.highContrast,
      colorBlindAssistance: colorBlindAssistance ?? this.colorBlindAssistance,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      screenReaderAnnouncements:
          screenReaderAnnouncements ?? this.screenReaderAnnouncements,
    );
  }
}

final accessibilityControllerProvider =
    NotifierProvider<AccessibilityController, AccessibilityState>(
  AccessibilityController.new,
);

class AccessibilityController extends Notifier<AccessibilityState> {
  static const _kReduceMotion = 'a11y_reduce_motion';
  static const _kTextScale = 'a11y_text_scale';
  static const _kHighContrast = 'a11y_high_contrast';
  static const _kColorBlind = 'a11y_color_blind';
  static const _kHaptics = 'a11y_haptics';
  static const _kAnnounce = 'a11y_announce';

  @override
  AccessibilityState build() {
    _load();
    return const AccessibilityState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AccessibilityState(
      reduceMotion: prefs.getBool(_kReduceMotion) ?? false,
      textScaleFactor: prefs.getDouble(_kTextScale) ?? 1.0,
      highContrast: prefs.getBool(_kHighContrast) ?? false,
      colorBlindAssistance: prefs.getBool(_kColorBlind) ?? false,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? true,
      screenReaderAnnouncements: prefs.getBool(_kAnnounce) ?? true,
    );
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReduceMotion, value);
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

  Future<void> setColorBlindAssistance(bool value) async {
    state = state.copyWith(colorBlindAssistance: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kColorBlind, value);
  }

  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHaptics, value);
  }

  Future<void> setScreenReaderAnnouncements(bool value) async {
    state = state.copyWith(screenReaderAnnouncements: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnnounce, value);
  }
}
