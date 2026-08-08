import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/evidence_package.dart';

/// The tamper-evidence core: turns an [EvidencePackage] into a SHA-256 hash
/// and verifies it later.
///
/// The hash is taken over the **canonical** JSON of [EvidencePackage.toHashableMap]
/// — keys sorted recursively so the byte string is deterministic regardless of
/// map insertion order. Sealing writes that hash onto the package; verifying
/// recomputes it and compares. Any change to a hashed field (lat, peak g,
/// timestamp, …) yields a different hash, so tampering is detectable.
///
/// Pure Dart by design (crypto + dart:convert only) — no Flutter/plugin
/// imports — so it runs under `flutter test` without a device.
abstract final class EvidenceEngine {
  /// Deterministic JSON: every map's keys sorted, compact separators.
  static String canonicalJson(Map<String, dynamic> map) =>
      jsonEncode(_sorted(map));

  static dynamic _sorted(dynamic value) {
    if (value is Map) {
      final out = SplayTreeMap<String, dynamic>();
      value.forEach((k, v) => out[k.toString()] = _sorted(v));
      return out;
    }
    if (value is List) return value.map(_sorted).toList();
    return value;
  }

  /// SHA-256 (hex) over the canonical JSON of the package's hashable fields.
  static String computeHash(EvidencePackage pkg) {
    final bytes = utf8.encode(canonicalJson(pkg.toHashableMap()));
    return sha256.convert(bytes).toString();
  }

  /// Computes the hash and writes it onto [pkg]. Returns the same instance so
  /// callers can chain. This is the last step before a package is stored.
  static EvidencePackage seal(EvidencePackage pkg) =>
      pkg..evidenceHash = computeHash(pkg);

  /// True only if the package is sealed and its stored hash still matches a
  /// fresh recomputation. Returns false for an unsealed or altered package.
  static bool verify(EvidencePackage pkg) {
    final stored = pkg.evidenceHash;
    if (stored == null || stored.isEmpty) return false;
    return computeHash(pkg) == stored;
  }
}
