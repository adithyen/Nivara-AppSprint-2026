import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/enums.dart';
import '../../models/evidence_package.dart';
import '../constants.dart';
import '../utils.dart';
import 'device_identity.dart';
import 'evidence_engine.dart';
import 'location_service.dart';

/// m/s² — converts an acceleration magnitude to g (≈1.0 at rest).
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
  final double gAboveBaseline;
  final EvidencePackage evidence;
  final DateTime at;
}

/// Live readout pushed to the UI while monitoring.
class SensorSnapshot {
  const SensorSnapshot({
    required this.monitoring,
    required this.currentG,
    required this.baselineG,
    required this.speedKmph,
    required this.detectionCount,
    required this.hasFix,
    required this.warmingUp,
  });

  final bool monitoring;
  final double currentG;
  final double baselineG;
  final double speedKmph;
  final int detectionCount;
  final bool hasFix;
  final bool warmingUp;

  double get impactG {
    final d = currentG - baselineG;
    return d < 0 ? 0 : d;
  }

  factory SensorSnapshot.idle() => const SensorSnapshot(
        monitoring: false,
        currentG: 1,
        baselineG: 1,
        speedKmph: 0,
        detectionCount: 0,
        hasFix: false,
        warmingUp: true,
      );
}

enum StartResult { started, startedWithoutLocation, alreadyRunning }

/// Classifies a jolt (g above baseline) into a civic detection type. Pure, so
/// it's unit-testable without sensors.
DetectionType classifyImpact(double gAboveBaseline) {
  if (gAboveBaseline >= 4.5) return DetectionType.pothole;
  if (gAboveBaseline >= 3.0) return DetectionType.speedBreaker;
  return DetectionType.badRoad;
}

/// Passive accelerometer engine. Holds a rolling g-force baseline and emits a
/// sealed [SensorDetection] when a jolt clears [kDetectionThresholdG] above it
/// — gated by [kMinSpeedKmh] and [kDebounceMeters] so phone handling and
/// repeated samples over one pothole don't spam reports.
class SensorWatchService {
  SensorWatchService({LocationService location = const LocationService()})
      // ignore: prefer_initializing_formals — public param name intentional for DI
      : _location = location;

  final LocationService _location;

  final ValueNotifier<SensorSnapshot> snapshot =
      ValueNotifier(SensorSnapshot.idle());

  final _detections = StreamController<SensorDetection>.broadcast();
  Stream<SensorDetection> get detections => _detections.stream;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<Position>? _posSub;

  final Queue<double> _window = Queue<double>();
  double _sum = 0;
  double _baselineG = 1;
  double _currentG = 1;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;
  Position? _pos;
  double? _lastLat, _lastLng;
  int _count = 0;
  bool _sealing = false;
  int _lastEmitMs = 0;

  bool get isMonitoring => _accelSub != null;

  Future<StartResult> start() async {
    if (isMonitoring) return StartResult.alreadyRunning;

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
    _accelSub = accelerometerEventStream(samplingPeriod: period)
        .listen(_onAccel, onError: (_) {});

    _emit(force: true);
    return hasLocation ? StartResult.started : StartResult.startedWithoutLocation;
  }

  Future<void> stop() async {
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _posSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _posSub = null;
    _window.clear();
    _sum = 0;
    _emit(force: true);
  }

  void _onAccel(AccelerometerEvent e) {
    final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / _gravity;
    _currentG = g;

    _window.addLast(g);
    _sum += g;
    if (_window.length > kBaselineSamples) _sum -= _window.removeFirst();
    _baselineG = _sum / _window.length;

    _emit();

    // Only trust a spike once the baseline window is full.
    if (_window.length >= kBaselineSamples &&
        g - _baselineG >= kDetectionThresholdG) {
      _fire(g - _baselineG, synthetic: false);
    }
  }

  /// Demo helper: fire a detection on demand, bypassing the speed/debounce
  /// gates, so the evidence flow can be shown at a desk without driving.
  Future<void> simulateImpact({double gAboveBaseline = 3.8}) =>
      _fire(gAboveBaseline, synthetic: true);

  Future<void> _fire(double impact, {required bool synthetic}) async {
    if (_sealing) return;
    final speed = _pos != null ? LocationService.msToKmh(_pos!.speed) : 0.0;

    if (!synthetic) {
      if (speed < kMinSpeedKmh) return; // filter phone handling at rest
      if (_lastLat != null && _pos != null) {
        final moved = haversineMeters(
            _lastLat!, _lastLng!, _pos!.latitude, _pos!.longitude);
        if (moved < kDebounceMeters) return; // same pothole, already logged
      }
    }

    _sealing = true;
    try {
      final type = classifyImpact(impact);
      final lat = _pos?.latitude ?? kDefaultLat;
      final lng = _pos?.longitude ?? kDefaultLng;

      final pkg = EvidenceEngine.seal(EvidencePackage(
        eventType: type,
        timestampDevice: DateTime.now().millisecondsSinceEpoch,
        lat: lat,
        lng: lng,
        gpsAccuracy: _pos?.accuracy ?? 0,
        speedKmph: speed,
        heading: _pos?.heading ?? 0,
        altitude: _pos?.altitude ?? 0,
        accelZPeak: _baselineG + impact,
        accelZBaseline: _baselineG,
        gyroX: _gyroX,
        gyroY: _gyroY,
        gyroZ: _gyroZ,
        deviceFingerprint: await DeviceIdentity.fingerprint(),
        appVersion: await DeviceIdentity.appVersion(),
      ));

      _count++;
      _lastLat = lat;
      _lastLng = lng;
      _detections.add(SensorDetection(
        type: type,
        gAboveBaseline: impact,
        evidence: pkg,
        at: DateTime.now(),
      ));
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
    final speed = _pos != null ? LocationService.msToKmh(_pos!.speed) : 0.0;
    snapshot.value = SensorSnapshot(
      monitoring: isMonitoring,
      currentG: _currentG,
      baselineG: _baselineG,
      speedKmph: speed,
      detectionCount: _count,
      hasFix: _pos != null,
      warmingUp: isMonitoring && _window.length < kBaselineSamples,
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
