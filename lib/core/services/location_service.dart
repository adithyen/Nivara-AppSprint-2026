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

  /// Checks if hardware GPS / location services are switched on.
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Opens the native device location settings screen.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Stream of hardware location service status changes (e.g. user toggles GPS).
  Stream<ServiceStatus> get serviceStatusStream => Geolocator.getServiceStatusStream();

  /// A single best-effort fix, or null if it fails/permission is missing.
  /// Hard-bounded by Dart timeouts to ensure the UI never deadlocks or buffers.
  Future<Position?> current({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!serviceOn) return null;

      final perm = await ensurePermission()
          .timeout(const Duration(seconds: 3), onTimeout: () => LocationPermission.denied);
      if (!isGranted(perm)) {
        return await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 1), onTimeout: () => null);
      }

      // Fast check for cached position first
      final lastKnown = await Geolocator.getLastKnownPosition()
          .timeout(const Duration(seconds: 1), onTimeout: () => null);

      try {
        final cur = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: timeout,
          ),
        ).timeout(timeout);
        return cur;
      } catch (_) {
        if (lastKnown != null) return lastKnown;
        // Fallback to medium accuracy if high accuracy timed out (e.g. indoors)
        try {
          return await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 2),
            ),
          ).timeout(const Duration(seconds: 2));
        } catch (_) {
          return null;
        }
      }
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 1), onTimeout: () => null);
      } catch (_) {
        return null;
      }
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
