import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Stable, privacy-preserving device + build identifiers for evidence packages.
///
/// The device fingerprint is a **SHA-256 hash** of a few stable hardware
/// attributes — never the raw device ID (per the project's crypto rule). Both
/// values are resolved once and cached for the process lifetime.
abstract final class DeviceIdentity {
  static String? _fingerprint;
  static String? _appVersion;

  /// SHA-256 over stable device attributes. Falls back to a constant on
  /// unsupported platforms (e.g. under unit tests) so callers never throw.
  static Future<String> fingerprint() async {
    if (_fingerprint != null) return _fingerprint!;
    String raw;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      raw = [
        info.id,
        info.model,
        info.device,
        info.brand,
        info.fingerprint,
      ].join('|');
    } catch (_) {
      raw = 'nivara-unknown-device';
    }
    _fingerprint = sha256.convert(utf8.encode(raw)).toString();
    return _fingerprint!;
  }

  /// App version + build number, e.g. `1.0.0+1`.
  static Future<String> appVersion() async {
    if (_appVersion != null) return _appVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = '1.0.0';
    }
    return _appVersion!;
  }
}
