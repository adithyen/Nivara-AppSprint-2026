import 'package:geolocator/geolocator.dart';

/// Thin wrapper over `geolocator`: permission handling, a one-shot fix, and a
/// position stream tuned for SensorWatch (high accuracy, no distance filter so
/// speed keeps updating while driving).
class LocationService {
  const LocationService();

  /// Ensures location services are on and permission is granted — requesting
  /// it if needed. Returns the resolved permission; check it with [isGranted].
  Future<LocationPermission> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermission.denied;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm;
  }

  bool isGranted(LocationPermission p) =>
      p == LocationPermission.always || p == LocationPermission.whileInUse;

  /// A single best-effort fix, or null if it fails/permission is missing.
  Future<Position?> current() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }

  /// Continuous position updates (lat/lng/speed/heading) for live monitoring.
  Stream<Position> stream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

  /// m/s → km/h. geolocator reports a negative speed when it's unknown.
  static double msToKmh(double ms) => ms <= 0 ? 0 : ms * 3.6;
}
