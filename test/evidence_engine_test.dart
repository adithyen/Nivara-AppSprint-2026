// Unit tests for the tamper-evidence core and the pure SensorWatch classifiers.
//
// These are pure-Dart (no Flutter binding, no device) — they lock down that the
// SHA-256 sealing is deterministic, order-independent, and detects any change to
// a hashed field. This is the security claim behind the whole "wow" feature, so
// it's the part most worth a regression test.

import 'package:flutter_test/flutter_test.dart';

import 'package:nivara/core/services/evidence_engine.dart';
import 'package:nivara/core/services/sensor_watch_service.dart';
import 'package:nivara/models/enums.dart';
import 'package:nivara/models/evidence_package.dart';

EvidencePackage _sample({
  DetectionType type = DetectionType.pothole,
  int ts = 1723101000000,
  double lat = 8.5241,
  double lng = 76.9366,
  double peak = 4.6,
}) => EvidencePackage(
  eventType: type,
  timestampDevice: ts,
  lat: lat,
  lng: lng,
  gpsAccuracy: 5,
  speedKmph: 32,
  heading: 180,
  altitude: 12,
  accelZPeak: peak,
  accelZBaseline: 1.02,
  gyroX: 0.1,
  gyroY: 0.2,
  gyroZ: 0.3,
  deviceFingerprint: 'a' * 64,
  appVersion: '1.0.0+1',
);

void main() {
  group('EvidenceEngine.computeHash', () {
    test('is a 64-char hex SHA-256 string', () {
      final h = EvidenceEngine.computeHash(_sample());
      expect(h, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('is deterministic for identical inputs', () {
      expect(
        EvidenceEngine.computeHash(_sample()),
        EvidenceEngine.computeHash(_sample()),
      );
    });

    test('ignores map insertion order (canonical JSON)', () {
      // canonicalJson must sort keys, so two maps with the same content but
      // different insertion order hash identically.
      final a = EvidenceEngine.canonicalJson({'b': 1, 'a': 2, 'c': 3});
      final b = EvidenceEngine.canonicalJson({'c': 3, 'a': 2, 'b': 1});
      expect(a, b);
    });

    test('changes when any hashed field changes', () {
      final base = EvidenceEngine.computeHash(_sample());
      expect(EvidenceEngine.computeHash(_sample(lat: 8.5242)), isNot(base));
      expect(EvidenceEngine.computeHash(_sample(peak: 4.7)), isNot(base));
      expect(
        EvidenceEngine.computeHash(_sample(ts: 1723101000001)),
        isNot(base),
      );
      expect(
        EvidenceEngine.computeHash(_sample(type: DetectionType.speedBreaker)),
        isNot(base),
      );
    });
  });

  group('EvidenceEngine.seal / verify', () {
    test('seal writes the hash and verify accepts it', () {
      final pkg = EvidenceEngine.seal(_sample());
      expect(pkg.evidenceHash, isNotNull);
      expect(EvidenceEngine.verify(pkg), isTrue);
    });

    test('verify rejects an unsealed package', () {
      expect(EvidenceEngine.verify(_sample()), isFalse);
    });

    test('verify rejects a tampered package', () {
      final pkg = EvidenceEngine.seal(_sample());
      // Someone edits the location after sealing but keeps the old hash.
      final forged = EvidencePackage(
        eventType: pkg.eventType,
        timestampDevice: pkg.timestampDevice,
        lat: 0, // <-- moved
        lng: 0,
        gpsAccuracy: pkg.gpsAccuracy,
        speedKmph: pkg.speedKmph,
        heading: pkg.heading,
        altitude: pkg.altitude,
        accelZPeak: pkg.accelZPeak,
        accelZBaseline: pkg.accelZBaseline,
        gyroX: pkg.gyroX,
        gyroY: pkg.gyroY,
        gyroZ: pkg.gyroZ,
        deviceFingerprint: pkg.deviceFingerprint,
        appVersion: pkg.appVersion,
        evidenceHash: pkg.evidenceHash, // stale hash
      );
      expect(EvidenceEngine.verify(forged), isFalse);
    });

    test('round-trips through toMap/fromMap and still verifies', () {
      final sealed = EvidenceEngine.seal(_sample());
      final restored = EvidencePackage.fromMap(sealed.toMap());
      expect(restored.evidenceHash, sealed.evidenceHash);
      expect(EvidenceEngine.verify(restored), isTrue);
    });
  });

  group('classifyImpact thresholds', () {
    test('maps g-force bands to detection types', () {
      expect(classifyImpact(5.0), DetectionType.pothole);
      expect(classifyImpact(4.5), DetectionType.pothole);
      expect(classifyImpact(3.2), DetectionType.speedBreaker);
      expect(classifyImpact(3.0), DetectionType.speedBreaker);
      expect(classifyImpact(2.6), DetectionType.badRoad);
    });
  });
}
