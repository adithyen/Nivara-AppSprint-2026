# CLAUDE.md — Nivara Project Context

---

## Project Identity

**App Name:** Nivara
**Tagline:** "Your City. Your Proof. Your Voice."
**Type:** Civic intelligence mobile app — AppSprint Solution Challenge 2026
**Platform:** Flutter (Dart), Android-first APK
**Backend:** Supabase (PostgreSQL + PostGIS + Auth + Realtime + Storage + Edge Functions)

> **Framework note (2026-08-08):** The project was originally documented for
> Expo React Native. It is now built in **Flutter** — chosen for a reliable
> single-command release APK (`flutter build apk`), smooth on-device
> performance, and alignment with the AppSprint workshop stack. The Supabase /
> PostgreSQL schema is framework-agnostic and carried over unchanged.

---

## What This App Does (Read This First)

Nivara turns any smartphone into a passive civic watchdog. Core modules:

1. **SensorWatch** — Background accelerometer detects potholes/road damage while
   the user drives. Generates a SHA-256 tamper-proof evidence package from raw
   sensor data (no photo needed). Completely passive.
2. **CivicReport** — Unified complaint management for 19 civic categories. Reports
   auto-submit from SensorWatch or are filed manually with a photo.
3. **LostFound** — Report lost or found items. Auto-matching via category +
   location proximity + time window. Notifies both parties on a match.
4. **CivicMap** — Live MapLibre map of reports + Lost&Found pins (Ola tiles).
5. **Admin (municipal) dashboard** — role-gated queue where staff view reports
   and move them through Acknowledged → In Progress → Resolved.

**What makes it novel:** passive auto-detection, cryptographic tamper-proof
evidence, and civic complaints + Lost&Found on one map.

---

## Architecture Rules (NEVER VIOLATE)

```
FRAMEWORK:  Flutter + Dart (stable channel). Android-first.
ROUTING:    go_router — declarative routes in lib/router.dart (no ad-hoc Navigator spaghetti)
BACKEND:    Supabase ONLY — no Express, no Firebase, no other backend
STATE:      Riverpod (flutter_riverpod) for app state; direct Supabase queries for server state
SENSORS:    sensors_plus ONLY (accelerometer/gyroscope); geolocator for GPS
MAPS:       maplibre_gl with Ola Maps vector tiles + OSM raster fallback — NO Google Maps
CRYPTO:     crypto package (SHA-256) — no hand-rolled hashing
STORAGE:    supabase Storage for photos; shared_preferences / hive only for local queue+cache
MODELS:     All data models in lib/models/ — one file per aggregate, no inline map parsing in widgets
STYLING:    Central ThemeData + reusable widgets in lib/core/widgets — no copy-pasted magic colors
```

---

## File Structure (MUST FOLLOW — feature-first)

```
lib/
  main.dart                 ← bootstrap: load .env, init Supabase, runApp
  router.dart               ← go_router config + auth/role redirect guard
  app.dart                  ← MaterialApp.router + theme

  core/
    theme.dart              ← brand colors, ThemeData (light/dark)
    constants.dart          ← DETECTION_THRESHOLD_G, MIN_SPEED_KMH, DEBOUNCE_M ...
    supabase_client.dart    ← Supabase singleton accessor (ONLY place client is read)
    utils.dart              ← formatDistance, formatDate, haversine
    categorize.dart         ← detection type → report_category mapping
    services/
      sensor_watch_service.dart  ← accelerometer engine
      evidence_engine.dart       ← SHA-256 evidence build + verify
      location_service.dart      ← GPS wrapper (geolocator)
      offline_queue.dart         ← retry queue for offline submissions
      ola_maps_service.dart      ← Ola REST (geocode/places/routing)
    widgets/                ← Button, Card, Badge, etc.

  models/
    report.dart  evidence_package.dart  lf_item.dart  lf_match.dart
    user_profile.dart  confirmation.dart

  features/
    auth/        login_screen.dart  signup_screen.dart  auth_controller.dart
    home/        home_screen.dart
    map/         civic_map.dart  report_pin.dart
    report/      report_form_screen.dart  report_detail_screen.dart  category_grid.dart  evidence_card.dart
    lostfound/   lostfound_hub.dart  report_lost_screen.dart  report_found_screen.dart  match_screen.dart  item_card.dart
    profile/     profile_screen.dart
    admin/       admin_dashboard.dart  admin_queue.dart  admin_report_detail.dart  manage_staff_screen.dart

supabase/
  migrations/0001_init.sql  ← full schema incl. roles/admin (source of truth)
  functions/match-lost-found/  ← Deno Edge Function (optional)
assets/
```

---

## Key Models (Always in lib/models/)

Dart classes mirror the DB. Use `factory X.fromMap(Map<String,dynamic>)` +
`toMap()`; parse enums from the DB string values.

```dart
// EvidencePackage — hashed sensor snapshot (see evidence_engine.dart)
class EvidencePackage {
  final String eventType;           // POTHOLE|SPEED_BREAKER|BAD_ROAD|MANUAL
  final int timestampDevice;
  final double lat, lng, gpsAccuracy, speedKmph, heading, altitude;
  final double accelZPeak, accelZBaseline, gyroX, gyroY, gyroZ;
  final String deviceFingerprint, appVersion;
  String? evidenceHash;             // added last, over sorted-key JSON
}

// Report — a civic complaint
class Report {
  final String id, userId;
  final ReportCategory category;    // enum (19 values)
  final ReportStatus status;        // SUBMITTED|ACKNOWLEDGED|IN_PROGRESS|RESOLVED|CLOSED|DUPLICATE
  final Severity severity;          // LOW|MEDIUM|HIGH|EMERGENCY
  final double lat, lng;
  final String? address, description;
  final List<String>? photoUrls;
  final String source;              // SENSORWATCH|MANUAL
  final EvidencePackage? evidencePackage;
  final String? evidenceHash;
  final int confirmationCount;
  final bool isCommunityVerified;
  final AdminDepartment? assignedDepartment;
  final DateTime createdAt;
}

// LFItem — lost/found entry
class LFItem {
  final String id, userId;
  final String itemType;            // LOST|FOUND
  final LFCategory category;
  final String title, description;
  final double lat, lng;
  final String? locationLabel;
  final DateTime eventDate;
  final String contactMethod;
  final int? rewardAmount;
  final String status;
  final List<String>? photoUrls;
}

// UserProfile — carries the role that gates admin features
class UserProfile {
  final String id;
  final String displayName;
  final UserRole role;              // CITIZEN|ADMIN|SUPERADMIN
  final AdminDepartment? department;
  final String? jurisdictionCity, jurisdictionWard;
  final int civicScore, reportsCount, findsCount;
  bool get isAdmin => role == UserRole.admin || role == UserRole.superadmin;
}
```

See `09_ADMIN_AND_AUTH.md` for the role model and `04_DATABASE_SCHEMA.md` for
the exact column definitions.

---

## Environment Variables (`.env`, loaded via flutter_dotenv)

```
SUPABASE_URL       = from Supabase dashboard → Settings → API
SUPABASE_ANON_KEY  = anon/publishable key (client-safe)
OLA_MAPS_API_KEY   = Ola Maps API key (client key — restrict it in dashboard)
OLA_MAPS_PROJECT_ID= Ola Maps project id
```

Never put the Supabase `service_role` key, the DB password, or the Ola
`client secret` in the app — those are server-side only. Commit `.env.example`
with placeholders only; `.env` is gitignored.

---

## Detection Thresholds (in core/constants.dart)

```dart
const double kDetectionThresholdG = 2.5;  // g-force above baseline to trigger
const double kMinSpeedKmh        = 5;     // ignore detections below this speed
const double kDebounceMeters     = 15;    // min distance between detections
const int    kSensorFreqHz       = 50;    // accelerometer sampling rate
const int    kGpsIntervalMs      = 2000;  // GPS update interval
const int    kBaselineSamples    = 50;    // rolling baseline window
```

---

## Brand Colors (core/theme.dart)

```
primary  #1B6CA8  civic blue
accent   #F5A623  alert amber
success  #27AE60  resolved green
danger   #E74C3C  emergency red
```

Map pin colors by status: SUBMITTED=accent, IN_PROGRESS=primary,
RESOLVED=success, EMERGENCY=danger.

---

## Critical Build Commands

```bash
flutter pub get                 # install dependencies
flutter run                     # run on connected device/emulator
flutter analyze                 # static analysis (run before commit)
dart format .                   # format
flutter build apk --release     # produce the release APK (→ GitHub Releases)
# Supabase schema:
#   paste supabase/migrations/0001_init.sql into the SQL editor, OR
#   supabase db push  (if using the Supabase CLI)
```

---

## Do NOT Do These

- Do NOT add a `server/` or `api/` folder — all backend is Supabase
- Do NOT call REST APIs with raw `http` for app data — use `supabase.from()` /
  RPCs. (`http` is only for Ola Maps geocode/places/routing.)
- Do NOT use Google Maps or `google_maps_flutter` — maps are MapLibre + Ola/OSM
- Do NOT scatter `Supabase.instance.client` reads — go through core/supabase_client.dart
- Do NOT parse Supabase rows inline in widgets — use `Model.fromMap`
- Do NOT trust a client-side isAdmin flag for security — RLS + RPCs enforce it
- Do NOT hardcode coordinates — use GPS or a documented city default
- Do NOT store a raw device ID — always SHA-256 hash the fingerprint
- Do NOT commit `.env`, keys, or the APK signing keystore

---

## Build Priority (hackathon order)

1. Auth + Supabase connection + role routing
2. SensorWatch engine + evidence hash (the "wow")
3. CivicReport form + Supabase insert
4. CivicMap with Ola/OSM + Realtime pins
5. Lost & Found forms + basic match display
6. Admin dashboard: queue + mark-fixed
7. Evidence viewer + confirmation button + home dashboard/stats
8. Polish (only if time remains)

**Demo-first mindset:** a working sensor-detection + evidence-hash demo, plus a
citizen-reports → admin-resolves round trip, beats a polished app with no wow.
