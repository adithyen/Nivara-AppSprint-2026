# Nivara — Project State / Handoff
**Last updated:** 2026-08-08

Quick-start context for continuing the build in Claude Code (CLI). Read
`CLAUDE.md` first (it holds the architecture rules); this file is the "where we
are / what's next" snapshot.

---

## Locked decisions
- **Framework:** Flutter (Dart), Android-first. Final deliverable = release APK.
- **Backend:** Supabase (Postgres + PostGIS + Auth + Realtime + Storage).
- **Maps:** `maplibre_gl` + Ola Maps vector tiles, OSM raster fallback. No Google.
- **Auth:** one app, role-gated — CITIZEN / ADMIN / SUPERADMIN.
- **State:** Riverpod. **Routing:** go_router.

## Done so far
- `supabase/migrations/0001_init.sql` — full schema incl. roles, admin "mark
  fixed" flow, status-history audit, RLS, RPCs (`admin_set_report_status`,
  `set_user_role`), auto profile-creation trigger, Realtime publication.
- `09_ADMIN_AND_AUTH.md` — role model, sign-in/elevation flow, permissions matrix.
- `10_MAPS_INTEGRATION.md` — Ola + OSM setup, endpoints, fallback logic.
- `CLAUDE.md` — rewritten for Flutter (guardrails, file layout, models, thresholds).
- `.env.example` + hardened `.gitignore` (secrets never committed).
- Older docs (`03_`, `04_`, `00_`) have banners pointing to the above.
- **Flutter app scaffolded** (`flutter create .`, org `com.nivara`, package
  `nivara`). Android configured: INTERNET + location perms, `minSdk 24`, core
  library desugaring; `.env` bundled as a Flutter asset.
- **core/** — `constants.dart`, `theme.dart` (brand palette + M3), `utils.dart`
  (haversine/format/parse helpers), `supabase_client.dart` (single client
  accessor), `categorize.dart` (detection → category).
- **models/** — `enums.dart` (all DB enums, wire↔label) + `user_profile`,
  `report`, `evidence_package`, `lf_item`, `lf_match`, `confirmation`
  (`fromMap`/`toInsertMap`, schema-accurate).
- **Auth + role routing** — `main.dart` (env → Supabase init → ProviderScope),
  `app.dart` (MaterialApp.router), `router.dart` (go_router + role redirect
  guard), `features/auth/` (AuthController AsyncNotifier, login, signup, splash),
  citizen `home` + `admin` landing stubs.
- `flutter analyze` → **clean**; `flutter test` → **6/6 pass** (enum mapping,
  Report.fromMap, haversine).

## Not started yet (build order)
1. SensorWatch service + EvidenceEngine (sensors_plus, geolocator, crypto SHA-256).
2. CivicReport (form, category grid, photo, Supabase insert, feed, detail, evidence card).
3. CivicMap (MapLibre + Ola/OSM, report pins, Realtime updates, filters).
4. Lost & Found (report lost/found, `find_nearby_items` RPC, match display).
5. Admin dashboard (queue, filters, report detail, `admin_set_report_status`).
6. Home dashboard/stats, community confirm button, polish.

## Your to-dos (need your machine / accounts)
- ✅ `.env` created locally with the four client-safe keys (gitignored).
- ✅ `0001_init.sql` run in Supabase.
- ✅ Email confirmation turned OFF (Auth → Providers → Email).
- **Run `supabase/seed_demo_admin.sql`** once in the SQL editor — seeds a demo
  administrator. Testers sign in via the login screen's "Admin" toggle with
  `username: admin` / `password: admin123` (stored as `admin@nivara.app`;
  the app maps the alias). Regular sign-ups are CITIZEN.
- Realtime is enabled by the migration; confirm in dashboard if needed.

## Demo admin
- One built-in admin, seeded by `supabase/seed_demo_admin.sql` (SUPERADMIN,
  GENERAL dept = sees all). Login screen has a Citizen/Admin toggle that
  reveals + prefills the credentials. Alias/email/password live in
  `core/constants.dart` (`kDemoAdmin*`).

## Key packages to add (pubspec)
`supabase_flutter`, `flutter_riverpod`, `go_router`, `sensors_plus`,
`geolocator`, `crypto`, `maplibre_gl`, `image_picker`, `http`, `flutter_dotenv`,
`shared_preferences`, `intl`, `flutter_local_notifications`,
`device_info_plus`, `package_info_plus`.

## Notes
- MapLibre vector tiles require a real device/emulator build (not a web preview).
- Never ship service_role key, DB password, or Ola client secret in the app.
