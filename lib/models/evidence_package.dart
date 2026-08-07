import '../core/utils.dart';
import 'enums.dart';

/// A tamper-evident snapshot of the sensor + GPS state at the moment of a
/// detection. Serialized to `reports.evidence_package` (JSONB).
///
/// The [evidenceHash] is a SHA-256 over the **sorted-key** JSON of
/// [toHashableMap] — computed and verified by `core/services/evidence_engine.dart`,
/// never hand-rolled here.
class EvidencePackage {
  final DetectionType eventType;
  final int timestampDevice;

  final double lat;
  final double lng;
  final double gpsAccuracy;
  final double speedKmph;
  final double heading;
  final double altitude;

  final double accelZPeak;
  final double accelZBaseline;
  final double gyroX;
  final double gyroY;
  final double gyroZ;

  final String deviceFingerprint;
  final String appVersion;

  /// Added last, after hashing. Null until the engine seals the package.
  String? evidenceHash;

  EvidencePackage({
    required this.eventType,
    required this.timestampDevice,
    required this.lat,
    required this.lng,
    required this.gpsAccuracy,
    required this.speedKmph,
    required this.heading,
    required this.altitude,
    required this.accelZPeak,
    required this.accelZBaseline,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.deviceFingerprint,
    required this.appVersion,
    this.evidenceHash,
  });

  /// The canonical payload that gets hashed. Excludes [evidenceHash] itself.
  /// Key order here is irrelevant — the engine sorts keys before hashing.
  Map<String, dynamic> toHashableMap() => {
        'event_type': eventType.wire,
        'timestamp_device': timestampDevice,
        'lat': lat,
        'lng': lng,
        'gps_accuracy': gpsAccuracy,
        'speed_kmph': speedKmph,
        'heading': heading,
        'altitude': altitude,
        'accel_z_peak': accelZPeak,
        'accel_z_baseline': accelZBaseline,
        'gyro_x': gyroX,
        'gyro_y': gyroY,
        'gyro_z': gyroZ,
        'device_fingerprint': deviceFingerprint,
        'app_version': appVersion,
      };

  /// Full map for storage — includes the hash once sealed.
  Map<String, dynamic> toMap() => {
        ...toHashableMap(),
        if (evidenceHash != null) 'evidence_hash': evidenceHash,
      };

  factory EvidencePackage.fromMap(Map<String, dynamic> map) => EvidencePackage(
        eventType:
            DetectionType.fromWire(map['event_type'] as String?) ??
                DetectionType.manual,
        timestampDevice: toInt(map['timestamp_device']),
        lat: toDouble(map['lat']),
        lng: toDouble(map['lng']),
        gpsAccuracy: toDouble(map['gps_accuracy']),
        speedKmph: toDouble(map['speed_kmph']),
        heading: toDouble(map['heading']),
        altitude: toDouble(map['altitude']),
        accelZPeak: toDouble(map['accel_z_peak']),
        accelZBaseline: toDouble(map['accel_z_baseline']),
        gyroX: toDouble(map['gyro_x']),
        gyroY: toDouble(map['gyro_y']),
        gyroZ: toDouble(map['gyro_z']),
        deviceFingerprint: (map['device_fingerprint'] as String?) ?? '',
        appVersion: (map['app_version'] as String?) ?? '',
        evidenceHash: map['evidence_hash'] as String?,
      );
}
