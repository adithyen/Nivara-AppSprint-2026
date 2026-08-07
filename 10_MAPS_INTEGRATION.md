# Nivara — Maps Integration (Ola Maps + OSM fallback)
**Version:** 1.0 | **Added:** 2026-08-08

Nivara's map moved off Google Maps. It now renders **Ola Maps vector tiles**
through MapLibre, with **OpenStreetMap raster tiles as an automatic fallback**
when Ola is unreachable or a key is missing. This document is the source of
truth for the map layer; it replaces the Google Maps references in the older
architecture doc.

---

## 1. Why this stack

- **Ola Maps** is an India-first map provider (better local road/place data than
  Google in many Indian wards) with a generous free tier and simple API-key auth.
- It serves **MapLibre-compatible vector tiles** via a style URL, so we use the
  open-source `maplibre_gl` Flutter plugin — no proprietary SDK, no Google
  billing account, no Play Services dependency.
- **OSM raster fallback** guarantees the map still draws during the demo even if
  Ola rate-limits or the network is flaky. Losing the map on stage is not an
  option.

> Rendering choice: **vector tiles via MapLibre** (confirmed with the owner).
> This needs a Flutter *dev/release build* — it does **not** run in a hosted
> Expo-Go-style client. Since we build a real APK with `flutter build apk`,
> that's fine.

---

## 2. Packages

```yaml
# pubspec.yaml (excerpt)
dependencies:
  maplibre_gl: ^0.20.0        # vector tile rendering (MapLibre GL Native)
  geolocator: ^12.0.0         # device GPS (see 03_TECHNICAL_ARCHITECTURE)
  http: ^1.2.0                # Ola REST calls (geocode/places/routing)
  flutter_dotenv: ^5.1.0      # load EXPO_PUBLIC_* style env keys
```

Android: `maplibre_gl` needs `minSdkVersion 21+` and the INTERNET permission
(already required). No API key goes in `AndroidManifest.xml` — the Ola key is
passed at runtime in the style URL / request headers.

---

## 3. Environment variables

```
# .env  (NEVER commit real values — see .env.example)
OLA_MAPS_API_KEY   = <ola api key>
OLA_MAPS_PROJECT_ID= <ola project id>
# OSM fallback needs no key.
```

The Google key (`EXPO_PUBLIC_GOOGLE_MAPS_KEY`) is **removed** and no longer
referenced anywhere.

---

## 4. Style URLs / endpoints

Ola Maps base host: `https://api.olamaps.io`

| Purpose            | Endpoint (append `?api_key=$OLA_MAPS_API_KEY`)                                  |
|--------------------|---------------------------------------------------------------------------------|
| Vector style JSON  | `/tiles/vector/v1/styles/default-light-standard/style.json`                     |
| Reverse geocode    | `/places/v1/reverse-geocode?latlng=<lat>,<lng>`                                 |
| Forward geocode    | `/places/v1/geocode?address=<urlencoded>`                                       |
| Autocomplete       | `/places/v1/autocomplete?input=<query>`                                         |
| Directions         | `/routing/v1/directions?origin=<lat,lng>&destination=<lat,lng>`                 |

OSM fallback raster tiles (no key): `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
(set a proper User-Agent; respect the OSM tile usage policy — fine for a demo).

> Ola occasionally revises style-slug names. If the default style 404s, list
> available styles at `/tiles/vector/v1/styles.json?api_key=...` and pick one.

---

## 5. Map widget contract (Flutter)

`lib/features/map/civic_map.dart` should expose a `CivicMap` widget that:

1. Builds a runtime style: try the **Ola style URL**; on load error, swap to an
   inline MapLibre style whose only source is the **OSM raster** tiles.
2. Centers on the user's current location (`geolocator`), else a city default.
3. Adds report pins from Supabase as a **symbol layer**, colored by status
   (submitted=amber, in-progress=blue, resolved=green, emergency=red).
4. Subscribes to Supabase Realtime `reports` inserts/updates and updates symbols
   live (< 300ms).
5. Exposes filter props (category, status, distance) and a "near me" recenter.

```dart
// Sketch — the actual file lives under lib/features/map/
final olaStyle =
  'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json'
  '?api_key=${dotenv.env['OLA_MAPS_API_KEY']}';

const osmFallbackStyle = '''
{ "version": 8,
  "sources": { "osm": {
    "type": "raster", "tileSize": 256,
    "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"] } },
  "layers": [ { "id": "osm", "type": "raster", "source": "osm" } ] }
''';

MaplibreMap(
  styleString: olaStyle,             // fallback swapped in on onStyleLoadError
  myLocationEnabled: true,
  initialCameraPosition: const CameraPosition(
    target: LatLng(8.5241, 76.9366), // Thiruvananthapuram default
    zoom: 12,
  ),
  onMapCreated: (c) => _controller = c,
  onStyleLoadedCallback: _addReportSymbols,
);
```

A thin `OlaMapsService` in `lib/core/services/` wraps the REST endpoints
(reverse-geocode an address for a new report, autocomplete a Lost&Found
location) so screens never build URLs by hand.

---

## 6. Fallback logic

```
try Ola style URL
  ├─ style loads → use Ola vector tiles ✔
  └─ onStyleLoadError / timeout
        └─ setState → rebuild MaplibreMap with osmFallbackStyle (raster) ✔
REST calls (geocode/places): call Ola; on non-200 or timeout,
  degrade gracefully — a report can still be saved with lat/lng and a
  blank address rather than blocking submission.
```

Never hard-fail a user action because a map/geocode call failed; the raw
`lat`/`lng` from GPS is always enough to store the report.

---

## 7. Security notes

- The Ola API key is a **client key**; it will ship inside the APK. Restrict it
  in the Ola dashboard (allowed package name / referrers, rate caps) so a leaked
  key can't be abused. Do **not** reuse the client secret in the app — the
  `clientsecret` is for server-to-server token exchange only and must stay
  server-side.
- Keep the real key in `.env` (gitignored). Commit only `.env.example` with
  placeholder names — the AppSprint rules forbid committing secrets to a public
  repo.
