/// App-wide constants for Nivara.
///
/// Detection thresholds drive the SensorWatch engine; map defaults drive
/// CivicMap. Nothing secret lives here — keys are read from `.env`.
library;

// ── Brand ────────────────────────────────────────────────────────────────
const String kAppName = 'Nivara';
const String kAppTagline = 'Your City. Your Proof. Your Voice.';

// ── SensorWatch detection thresholds ───────────────────────────────────────
/// Linear-acceleration jolt (in g, gravity already removed) required to trigger
/// a detection. At rest the sensor reads ~0 g; a pothole/hard shake spikes past
/// this. NOTE: measured on `userAccelerometerEventStream`, so this is an
/// absolute jolt magnitude — there is no rolling baseline to subtract.
const double kDetectionThresholdG = 2.5;

/// Minimum time (ms) between two auto-detections — debounce so one jolt (or one
/// pothole at speed) yields a single report instead of a burst. Replaces the
/// old speed/distance gate, which blocked stationary desk testing.
const int kDetectionCooldownMs = 1500;

/// GPS speeds below this (km/h) are treated as 0. Consumer GPS reports jittery
/// 2–3 km/h "movement" while the phone is at rest; this deadband removes it.
const double kSpeedDeadbandKmh = 3;

/// Settle window (ms) after monitoring starts, during which jolts are ignored
/// so the sensor spin-up transient doesn't fire a bogus detection.
const int kSettleMs = 600;

/// Ignore detections below this speed (km/h). Retained for reference/tuning;
/// the engine no longer hard-gates on it so desk demos work.
const double kMinSpeedKmh = 5;

/// Minimum distance (metres) between two detections — debounce.
const double kDebounceMeters = 15;

/// Accelerometer sampling rate (Hz).
const int kSensorFreqHz = 50;

/// GPS update interval (ms).
const int kGpsIntervalMs = 2000;

/// Rolling window (samples) for the displayed peak / noise-floor readout.
const int kBaselineSamples = 50;

// ── Map defaults ────────────────────────────────────────────────────────────
/// Default map centre: Thiruvananthapuram, Kerala.
const double kDefaultLat = 8.5241;
const double kDefaultLng = 76.9366;
const double kDefaultZoom = 12;

/// Ola Maps vector style. `?api_key=` is appended at runtime by the maps layer.
const String kOlaVectorStyleUrl =
    'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json';

/// OpenStreetMap raster fallback tile template.
const String kOsmRasterTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

// ── Lost & Found matching ───────────────────────────────────────────────────
/// Radius (metres) within which a lost and a found item may match.
const double kLfMatchRadiusMeters = 2000;

/// Time window (days) either side of an item's event date for matching.
const int kLfMatchWindowDays = 14;

// ── Supabase table + bucket names ───────────────────────────────────────────
const String kTableReports = 'reports';
const String kTableProfiles = 'user_profiles';
const String kTableLfItems = 'lf_items';
const String kTableLfMatches = 'lf_matches';
const String kTableConfirmations = 'confirmations';
const String kTableStatusHistory = 'report_status_history';
const String kBucketPhotos = 'complaint-photos';

// ── Demo admin (hackathon) ──────────────────────────────────────────────────
/// A convenience login for judges/testers. The login screen's "Admin" toggle
/// reveals + prefills these, and the sign-in path maps the [kDemoAdminUsername]
/// alias onto the real [kDemoAdminEmail] (Supabase auth is email-based).
///
/// Seed the account once with `supabase/seed_demo_admin.sql`.
const String kDemoAdminUsername = 'admin';
const String kDemoAdminEmail = 'admin@nivara.app';
const String kDemoAdminPassword = 'admin123';
