import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized manager for Native Biometric App Lock with device passcode fallback.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const String _kEnabledKey = 'nivara_app_lock_enabled';
  static const String _kPromptedKey = 'nivara_app_lock_prompted';

  final LocalAuthentication _auth = LocalAuthentication();

  /// Flag indicating that an external browser auth flow (like Google OAuth) is active.
  /// When true, the app lifecycle should not lock the app when backgrounded.
  bool isExternalAuthInProgress = false;

  /// Whether device hardware supports biometric or device-credential security.
  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException catch (e) {
      debugPrint('[AppLockService] canAuthenticate error: $e');
      return false;
    }
  }

  /// Get list of available hardware biometrics on device (e.g. fingerprint, face).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      debugPrint('[AppLockService] getAvailableBiometrics error: $e');
      return [];
    }
  }

  /// Whether the user has enabled App Lock in settings.
  Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  /// Save App Lock enabled status.
  Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, enabled);
  }

  /// Whether fresh app open prompt has already been shown.
  Future<bool> hasBeenPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPromptedKey) ?? false;
  }

  /// Mark the first-run prompt as completed.
  Future<void> markPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPromptedKey, true);
  }

  /// Cancels any active or hanging authentication session.
  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (e) {
      debugPrint('[AppLockService] stopAuthentication error: $e');
    }
  }

  /// Prompt native biometric / phone passcode authentication.
  /// Uses [biometricOnly: false] to allow phone password/PIN/pattern as failsafe.
  Future<bool> authenticate({String? localizedReason}) async {
    try {
      final isAvailable = await canAuthenticate();
      if (!isAvailable) {
        debugPrint('[AppLockService] Device security hardware unavailable');
        return true;
      }

      // Stop any stale or lingering native prompts before initiating
      await stopAuthentication();

      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason ?? 'Verify your biometric or phone passcode to access Nivara',
        biometricOnly: false, // Allows device PIN/passcode/pattern as failsafe
        persistAcrossBackgrounding: false, // Critical: prevent deadlock when system dialogs overlay
        sensitiveTransaction: true,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint('[AppLockService] Authentication timed out');
          return false;
        },
      );
      return authenticated;
    } on PlatformException catch (e) {
      debugPrint('[AppLockService] Authentication PlatformException: $e');
      return false;
    } catch (e) {
      debugPrint('[AppLockService] Authentication unexpected error: $e');
      return false;
    }
  }
}
