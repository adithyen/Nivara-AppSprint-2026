import 'package:flutter/services.dart';

/// Service to interact with Android Native ShortcutManager / Home Screen Widget.
class ShortcutService {
  ShortcutService._();
  static final ShortcutService instance = ShortcutService._();

  static const _channel = MethodChannel('com.nivara.app/shortcuts');

  /// Requests the Android launcher to pin the 1-Tap "SensorWatch Drive" shortcut to the home screen.
  Future<bool> pinSensorWatchShortcut() async {
    try {
      final res = await _channel.invokeMethod<bool>('pinSensorWatchShortcut');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if the app was launched with a shortcut intent.
  Future<String?> getInitialShortcutRoute() async {
    try {
      return await _channel.invokeMethod<String?>('getInitialShortcutRoute');
    } catch (_) {
      return null;
    }
  }

  /// Sets up listener for shortcut triggers when app is already open.
  void setShortcutListener(void Function(String route) onRoute) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShortcutTriggered' && call.arguments is String) {
        onRoute(call.arguments as String);
      }
    });
  }
}
