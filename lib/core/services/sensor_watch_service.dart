import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/enums.dart';
import '../../models/evidence_package.dart';
import '../constants.dart';
import 'device_identity.dart';
import 'evidence_engine.dart';
import 'location_service.dart';

/// m/s² per g — converts a linear-acceleration magnitude to g.
const double _gravity = 9.80665;

/// One passive detection: a jolt past the threshold, already sealed into a
/// tamper-evident [EvidencePackage].
class SensorDetection {
  SensorDetection({
    required this.type,
    required this.gAboveBaseline,
    required this.evidence,
    required this.at,
  });

  final DetectionType type;

  /// Jolt magnitude in g (linear acceleration; gravity already removed).
  final double gAboveBaseline;
  final EvidencePackage evidence;
  final DateTime at;
}

/// Live readout pushed to the UI while monitoring.
class SensorSnapshot {
  const SensorSnapshot({
    required this.monitoring,
    required this.currentG,
    required this.peakG,
    required this.speedKmph,
    required this.detectionCount,
    required this.hasFix,
    required this.warmingUp,
  });

  final bool monitoring;

  /// Live jolt magnitude in g (≈0 at rest, spikes on impact).
  final double currentG;

  /// Largest jolt seen since monitoring started, in g.
  final double peakG;
  final double speedKmph;
  final int detectionCount;
  final bool hasFix;
  final bool warmingUp;

  /// The value the impact meter renders — the live jolt (never negative).
  double get impactG => currentG < 0 ? 0 : currentG;

  factory SensorSnapshot.idle() => const SensorSnapshot(
    monitoring: false,
    currentG: 0,
    peakG: 0,
    speedKmph: 0,
    detectionCount: 0,
    hasFix: false,
    warmingUp: true,
  );
}

enum StartResult { started, startedWithoutLocation, alreadyRunning }

/// Classifies a jolt (linear-accel g) into a civic detection type. Pure, so
/// it's unit-testable without sensors.
DetectionType classifyImpact(double joltG) {
  if (joltG >= 4.5) return DetectionType.pothole;
  if (joltG >= 3.0) return DetectionType.speedBreaker;
  return DetectionType.badRoad; // uneven / rough surface
}

/// Passive detection engine. Reads **linear acceleration** (gravity removed by
/// the OS via [userAccelerometerEventStream]) so the phone reads ~0 g at rest
/// and a jolt shows its true magnitude. A detection fires the instant a jolt
/// clears [kDetectionThresholdG]; a [kDetectionCooldownMs] debounce stops one
/// impact from producing a burst. Works stationary (desk shake) and while
/// driving — there is no speed gate.
class SensorWatchService {
  SensorWatchService({LocationService location = const LocationService()})
    // ignore: prefer_initializing_formals — public param name intentional for DI
    : _location = location;

  final LocationService _location;

  final ValueNotifier<SensorSnapshot> snapshot = ValueNotifier(
    SensorSnapshot.idle(),
  );

  final _detections = StreamController<SensorDetection>.broadcast();
  Stream<SensorDetection> get detections => _detections.stream;

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<Position>? _posSub;

  double _currentG = 0;
  double _peakG = 0;
  double _noiseFloorG = 0; // light EMA of the jolt magnitude (~0 at rest)
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;
  Position? _pos;
  int _count = 0;
  bool _sealing = false;
  int _lastEmitMs = 0;
  int _lastFireMs = 0;
  int _startMs = 0;

  bool get isMonitoring => _accelSub != null;

  /// Live GPS speed in km/h, deadbanded — sub-[kSpeedDeadbandKmh] jitter while
  /// at rest reads as 0. (True inertial speed needs GPS; the accelerometer only
  /// gives acceleration, and integrating it drifts badly, so we clean GPS here.)
  double get _speedKmh {
    if (_pos == null) return 0;
    final s = LocationService.msToKmh(_pos!.speed);
    return s < kSpeedDeadbandKmh ? 0 : s;
  }

  bool get _warmingUp =>
      isMonitoring &&
      DateTime.now().millisecondsSinceEpoch - _startMs < kSettleMs;

  Future<StartResult> start() async {
    if (isMonitoring) return StartResult.alreadyRunning;

    _peakG = 0;
    _noiseFloorG = 0;
    _startMs = DateTime.now().millisecondsSinceEpoch;

    final perm = await _location.ensurePermission();
    final hasLocation = _location.isGranted(perm);
    if (hasLocation) {
      _posSub = _location.stream().listen((p) {
        _pos = p;
        _emit(force: true);
      }, onError: (_) {});
    }

    final period = Duration(microseconds: (1000000 / kSensorFreqHz).round());
    _gyroSub = gyroscopeEventStream(samplingPeriod: period).listen((e) {
      _gyroX = e.x;
      _gyroY = e.y;
      _gyroZ = e.z;
    }, onError: (_) {});
    // Linear acceleration — gravity already removed, so rest ≈ 0 g.
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: period,
    ).listen(_onAccel, onError: (_) {});

    _emit(force: true);
    return hasLocation
        ? StartResult.started
        : StartResult.startedWithoutLocation;
  }

  Future<void> stop() async {
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _posSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _posSub = null;
    _currentG = 0;
    _emit(force: true);
  }

  void _onAccel(UserAccelerometerEvent e) {
    // Magnitude of linear acceleration in g. At rest this is ~0.02 g (noise);
    // a pothole or a hard shake spikes well past kDetectionThresholdG.
    final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / _gravity;
    _currentG = g;
    if (g > _peakG) _peakG = g;
    // Slow EMA → a stable noise-floor estimate for the evidence package.
    _noiseFloorG = _noiseFloorG == 0 ? g : _noiseFloorG * 0.98 + g * 0.02;

    _emit();

    if (_warmingUp) return; // skip the sensor spin-up transient
    if (g < kDetectionThresholdG) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFireMs < kDetectionCooldownMs) return; // debounce a burst
    _fire(g, synthetic: false);
  }

  /// Demo helper: fire a detection on demand (bypasses the settle + cooldown
  /// gates) so the evidence flow can be shown at a desk without driving.
  Future<void> simulateImpact({double joltG = 3.8}) =>
      _fire(joltG, synthetic: true);

  Future<void> _fire(double joltG, {required bool synthetic}) async {
    if (_sealing) return;
    _sealing = true;
    _lastFireMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final type = classifyImpact(joltG);
      final lat = _pos?.latitude ?? kDefaultLat;
      final lng = _pos?.longitude ?? kDefaultLng;

      final pkg = EvidenceEngine.seal(
        EvidencePackage(
          eventType: type,
          timestampDevice: DateTime.now().millisecondsSinceEpoch,
          lat: lat,
          lng: lng,
          gpsAccuracy: _pos?.accuracy ?? 0,
          speedKmph: _speedKmh,
          heading: _pos?.heading ?? 0,
          altitude: _pos?.altitude ?? 0,
          accelZPeak: joltG,
          accelZBaseline: synthetic ? 0 : _noiseFloorG,
          gyroX: _gyroX,
          gyroY: _gyroY,
          gyroZ: _gyroZ,
          deviceFingerprint: await DeviceIdentity.fingerprint(),
          appVersion: await DeviceIdentity.appVersion(),
        ),
      );

      _count++;
      _detections.add(
        SensorDetection(
          type: type,
          gAboveBaseline: joltG,
          evidence: pkg,
          at: DateTime.now(),
        ),
      );
      _emit(force: true);
    } finally {
      _sealing = false;
    }
  }

  /// Pushes a snapshot to [snapshot]. Throttled to ~10 Hz for accel spam;
  /// [force] bypasses the throttle for state changes and detections.
  void _emit({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastEmitMs < 90) return;
    _lastEmitMs = now;
    snapshot.value = SensorSnapshot(
      monitoring: isMonitoring,
      currentG: _currentG,
      peakG: _peakG,
      speedKmph: _speedKmh,
      detectionCount: _count,
      hasFix: _pos != null,
      warmingUp: _warmingUp,
    );
  }

  void dispose() {
    stop();
    _detections.close();
    snapshot.dispose();
  }
}

/// App-wide singleton engine.
final sensorWatchServiceProvider = Provider<SensorWatchService>((ref) {
  final svc = SensorWatchService();
  ref.onDispose(svc.dispose);
  return svc;
});
