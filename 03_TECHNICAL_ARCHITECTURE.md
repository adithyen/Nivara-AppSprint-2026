> ⚠️ **SUPERSEDED — HISTORICAL REFERENCE (2026-08-08).**
> This document describes the original **Expo / React Native + Google Maps**
> design. Nivara is now built in **Flutter + Supabase + Ola Maps (OSM fallback)**
> with role-based auth. **Do not build from this file.** Current sources of truth:
> [`CLAUDE.md`](CLAUDE.md) (stack/guardrails) ·
> [`10_MAPS_INTEGRATION.md`](10_MAPS_INTEGRATION.md) (maps) ·
> [`09_ADMIN_AND_AUTH.md`](09_ADMIN_AND_AUTH.md) (roles/admin) ·
> [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) (schema) ·
> [`PROJECT_STATE.md`](PROJECT_STATE.md) (status/build order).
> Still conceptually valid: the sensor-detection pipeline and SHA-256 evidence
> design — the Dart implementation mirrors it.

# Nivara — Technical Architecture
**Version:** 1.0 | **Last Updated:** July 2026

> ⚠️ **PARTIALLY SUPERSEDED (2026-08-08).** This document describes the original
> **Expo React Native** stack. The project is now built in **Flutter** — for the
> current stack, file layout, models, and thresholds see **`CLAUDE.md`**; for
> maps see **`10_MAPS_INTEGRATION.md`** (Ola + OSM, not Google); for auth/roles
> see **`09_ADMIN_AND_AUTH.md`**; for the schema see **`supabase/migrations/0001_init.sql`**.
> The sections below on the *sensor pipeline, evidence-hash algorithm, detection
> classification, matching score, and Realtime concepts* remain valid — port the
> logic to Dart. Treat the TypeScript/Expo code samples as pseudocode.

---

## 1. System Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                   NIVARA APP (Expo React Native)                    │
│                                                                     │
│  ┌──────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ Sensor Layer │  │   App Layer     │  │     UI Layer        │  │
│  │              │  │                 │  │                     │  │
│  │ Accelerometer│  │ SensorWatchSvc  │  │ Expo Router screens │  │
│  │ Gyroscope    │  │ EvidenceEngine  │  │ react-native-maps   │  │
│  │ GPS Location │  │ MatchingEngine  │  │ Animated / Reanimated│ │
│  │ Barometer    │  │ OfflineQueue    │  │ NativeWind styles   │  │
│  └──────┬───────┘  └────────┬────────┘  └─────────────────────┘  │
│         │                   │                                       │
│  ┌──────▼───────────────────▼──────────────────────────────────┐  │
│  │              Supabase Client (@supabase/supabase-js)          │  │
│  └─────────────────────────────┬───────────────────────────────┘  │
└─────────────────────────────────┼─────────────────────────────────┘
                                  │
              ┌───────────────────▼─────────────────────────────────┐
              │                  SUPABASE                            │
              │                                                       │
              │  PostgreSQL DB  ·  Auth  ·  Storage  ·  Realtime    │
              │  Edge Functions (for matching + escalation)          │
              └─────────────────────────────────────────────────────┘
```

---

## 2. Tech Stack — Full Decisions

### Expo React Native (not bare RN, not Flutter)

Expo is chosen for a 2-day hackathon because:
- `expo-sensors` gives accelerometer/gyroscope/barometer with **zero native setup**
- `expo-location` gives background GPS
- `expo-crypto` gives SHA-256 hashing
- `expo-image-picker` gives camera
- `expo-notifications` gives push (if time permits)
- Builds run on any phone instantly via **Expo Go** (no APK needed for demo)
- **Expo Router** (file-based) — same mental model as Next.js App Router

### Supabase (Zero backend server)

Every "backend" feature is handled by Supabase:
- **Auth**: Google OAuth + email
- **Database**: PostgreSQL with PostGIS for spatial queries
- **Realtime**: live map pin updates (< 300ms latency)
- **Storage**: complaint photos
- **Edge Functions**: lost-found matching algorithm (Deno runtime)
- **RLS**: each user sees only their own private data + all public civic reports

### NativeWind (Tailwind for React Native)

Same class names as web Tailwind — zero new CSS syntax to learn.

---

## 3. Project Structure

```
nivara/
├── app/                           ← Expo Router (file = route)
│   ├── (auth)/
│   │   ├── login.tsx
│   │   └── signup.tsx
│   ├── (tabs)/
│   │   ├── _layout.tsx            ← Bottom tab navigator
│   │   ├── index.tsx              ← Home / Dashboard
│   │   ├── map.tsx                ← CivicMap
│   │   ├── report.tsx             ← Quick report
│   │   ├── lostfound.tsx          ← Lost & Found hub
│   │   └── profile.tsx            ← Score + my reports
│   ├── complaint/
│   │   ├── new.tsx                ← Full complaint form
│   │   └── [id].tsx               ← Complaint detail + evidence
│   ├── lostfound/
│   │   ├── report-lost.tsx
│   │   ├── report-found.tsx
│   │   └── match/[id].tsx         ← Match review screen
│   └── _layout.tsx
│
├── services/
│   ├── SensorWatchService.ts      ← Accelerometer monitoring
│   ├── EvidenceEngine.ts          ← Hash generation + verification
│   ├── LocationService.ts         ← GPS wrapper
│   ├── OfflineQueue.ts            ← Store + retry when online
│   └── MatchingService.ts         ← Lost-found matching logic (local)
│
├── lib/
│   ├── supabase.ts                ← Supabase client singleton
│   ├── categorize.ts              ← Detection → civic category
│   ├── constants.ts               ← Thresholds, timeouts, categories
│   └── utils.ts                   ← formatDistance, formatDate etc.
│
├── hooks/
│   ├── useSensorWatch.ts
│   ├── useReports.ts
│   ├── useLostFound.ts
│   └── useLocation.ts
│
├── components/
│   ├── map/
│   │   ├── CivicMap.tsx
│   │   ├── ReportPin.tsx
│   │   └── LostFoundPin.tsx
│   ├── report/
│   │   ├── QuickReportSheet.tsx
│   │   ├── EvidenceCard.tsx
│   │   └── CategoryGrid.tsx
│   ├── lostfound/
│   │   ├── ItemCard.tsx
│   │   └── MatchCard.tsx
│   └── ui/
│       ├── Button.tsx
│       ├── Card.tsx
│       └── Badge.tsx
│
├── types/
│   └── index.ts
│
├── supabase/
│   ├── migrations/
│   │   └── 001_initial.sql
│   └── functions/
│       └── match-lost-found/
│           └── index.ts           ← Deno Edge Function
│
├── assets/
│   └── icons/                     ← Category icons (SVG)
│
├── CLAUDE.md
├── app.json
└── package.json
```

---

## 4. Sensor Detection Pipeline

```
BACKGROUND THREAD (every 20ms at 50Hz):
┌─────────────────────────────────────────────────────────┐
│  Accelerometer.addListener(({ x, y, z }) => {           │
│    rollingBaseline.push(z);                             │
│    if (rollingBaseline.length > 50) rollingBaseline.shift(); │
│    const baseline = mean(rollingBaseline);              │
│    const peak = Math.abs(z - baseline);                 │
│    if (peak > THRESHOLD && gpsSpeed > 5) {              │
│      debounce(triggerDetection, 15_METERS)              │
│    }                                                    │
│  })                                                     │
└─────────────────────────────────────────────────────────┘
         │
         ▼
DETECTION TRIGGERED:
  snapshot = {
    accel_z_peak: peak,
    accel_z_baseline: baseline,
    gyro: currentGyroscope,
    location: await Location.getCurrentPositionAsync(),
    speed_kmph: gpsSpeed * 3.6,
    heading: gpsHeading,
    timestamp_device: Date.now(),
    timestamp_ntp: await getNTPTime(),
  }
         │
         ▼
EVIDENCE ENGINE:
  const payload = JSON.stringify(snapshot, Object.keys(snapshot).sort())
  const hash = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    payload
  )
  evidencePackage = { ...snapshot, evidence_hash: hash }
         │
         ▼
STORE LOCALLY (AsyncStorage):
  detectionLog.push({ ...evidencePackage, reported: false })
         │
         ▼
TRIGGER UI:
  notify SensorWatchContext → show banner to user
```

### Detection Pattern Classification

```typescript
// How to tell pothole vs speed breaker vs bad road:

// POTHOLE: single sharp spike, Z-axis, < 500ms duration
//   Peak > 2.5g, duration < 0.5s
//   Pattern: spike → trough → return

// SPEED BREAKER (official): gradual sine-wave shape, 1-3s duration
//   Both wheels involved: front spike then back spike ~1.5s apart at 30kmph
//   Pattern: up-ramp → peak → down-ramp

// BAD ROAD PATCH: sustained elevated RMS over 50+ meters
//   Continuous elevated noise, no single sharp peak
//   Pattern: high variance sustained over time

function classifyEvent(samples: AccelSample[]): EventType {
  const duration = samples[samples.length-1].t - samples[0].t;
  const peak = Math.max(...samples.map(s => Math.abs(s.z - s.baseline)));
  const rms = Math.sqrt(samples.reduce((sum, s) => sum + s.z*s.z, 0) / samples.length);
  const doublePeak = detectDoublePeak(samples, 1.5);

  if (peak > 2.5 && duration < 500) return 'POTHOLE';
  if (doublePeak && duration > 800 && duration < 3000) return 'SPEED_BREAKER';
  if (rms > 1.2 && duration > 2000) return 'BAD_ROAD';
  return 'UNKNOWN';
}
```

---

## 5. Evidence Hash System

```typescript
// services/EvidenceEngine.ts
import * as Crypto from 'expo-crypto';
import * as Device from 'expo-device';
import * as Application from 'expo-application';

interface EvidencePackage {
  event_type: 'POTHOLE' | 'SPEED_BREAKER' | 'BAD_ROAD' | 'MANUAL';
  timestamp_device: number;
  timestamp_ntp?: number;
  lat: number;
  lng: number;
  gps_accuracy: number;
  altitude: number;
  speed_kmph: number;
  heading: number;
  accel_z_peak: number;
  accel_z_baseline: number;
  gyro_x: number;
  gyro_y: number;
  gyro_z: number;
  device_fingerprint: string;
  app_version: string;
  evidence_hash?: string; // added last
}

export class EvidenceEngine {
  private static deviceFingerprint: string | null = null;

  static async getDeviceFingerprint(): Promise<string> {
    if (this.deviceFingerprint) return this.deviceFingerprint;
    
    const deviceId = await Application.getAndroidId() ?? 'unknown';
    const installId = Application.androidId ?? 'unknown';
    const salt = 'nivara_v1_' + (await Application.getInstallationTimeAsync());
    
    this.deviceFingerprint = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      `${deviceId}:${installId}:${salt}`
    );
    return this.deviceFingerprint;
  }

  static async generateEvidencePackage(
    detection: Omit<EvidencePackage, 'device_fingerprint' | 'app_version' | 'evidence_hash'>
  ): Promise<EvidencePackage> {
    const pkg: EvidencePackage = {
      ...detection,
      device_fingerprint: await this.getDeviceFingerprint(),
      app_version: Application.nativeApplicationVersion ?? '1.0.0',
    };

    // Deterministic JSON: sort keys alphabetically
    const sortedKeys = Object.keys(pkg).sort();
    const deterministicJSON = JSON.stringify(
      Object.fromEntries(sortedKeys.map(k => [k, pkg[k as keyof typeof pkg]]))
    );

    pkg.evidence_hash = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      deterministicJSON
    );

    return pkg;
  }

  static async verifyHash(pkg: EvidencePackage): Promise<boolean> {
    const { evidence_hash, ...rest } = pkg;
    const sortedKeys = Object.keys(rest).sort();
    const deterministicJSON = JSON.stringify(
      Object.fromEntries(sortedKeys.map(k => [k, rest[k as keyof typeof rest]]))
    );
    const recomputed = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      deterministicJSON
    );
    return recomputed === evidence_hash;
  }
}
```

---

## 6. Supabase Realtime Map Updates

```typescript
// When a new complaint is submitted anywhere near the user:
const subscription = supabase
  .channel('civic-reports')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'reports',
    filter: `city=eq.${userCity}`,
  }, (payload) => {
    const newReport = payload.new as Report;
    // Add pin to map state instantly
    setMapPins(prev => [...prev, newReport]);
  })
  .subscribe();

// Lost & Found matches (user-specific):
const matchSub = supabase
  .channel(`matches-${userId}`)
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'lf_matches',
    filter: `notified_user_id=eq.${userId}`,
  }, (payload) => {
    showMatchNotification(payload.new);
  })
  .subscribe();
```

---

## 7. Lost-Found Matching (Supabase Edge Function)

```typescript
// supabase/functions/match-lost-found/index.ts (Deno)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  const { newItem } = await req.json();
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const searchType = newItem.item_type === 'LOST' ? 'FOUND' : 'LOST';

  // Find potential matches: same category + within 2km + within 7 days
  const { data: candidates } = await supabase.rpc('find_nearby_items', {
    p_lat: newItem.lat,
    p_lng: newItem.lng,
    p_radius_km: 2,
    p_category: newItem.category,
    p_item_type: searchType,
    p_within_days: 7,
  });

  for (const candidate of candidates ?? []) {
    const score = computeMatchScore(newItem, candidate);
    if (score > 70) {
      // Create match record + notify both users
      await supabase.from('lf_matches').insert({
        lost_item_id: newItem.item_type === 'LOST' ? newItem.id : candidate.id,
        found_item_id: newItem.item_type === 'FOUND' ? newItem.id : candidate.id,
        match_score: score,
        status: 'PENDING',
      });
      // Notify via Supabase Realtime (triggers in-app notification)
    }
  }
  return new Response(JSON.stringify({ matched: candidates?.length }));
});

function computeMatchScore(a: LFItem, b: LFItem): number {
  let score = 0;
  if (a.category === b.category) score += 40;
  const distKm = haversineKm(a.lat, a.lng, b.lat, b.lng);
  score += Math.max(0, 30 - distKm * 15); // 30 pts at 0km, 0 pts at 2km
  const daysDiff = Math.abs(a.event_date.getTime() - b.event_date.getTime()) / 86400000;
  score += Math.max(0, 20 - daysDiff * 3);  // 20 pts at same day, 0 pts at 7 days
  score += keywordOverlap(a.description, b.description) * 10;
  return Math.round(score);
}
```

---

## 8. Full Dependency List (`package.json`)

```json
{
  "dependencies": {
    "expo": "~51.x",
    "expo-router": "~3.x",
    "react": "18.x",
    "react-native": "0.74.x",

    "@supabase/supabase-js": "^2.x",

    "expo-sensors": "~13.x",
    "expo-location": "~17.x",
    "expo-crypto": "~13.x",
    "expo-device": "~6.x",
    "expo-application": "~5.x",
    "expo-image-picker": "~15.x",
    "expo-notifications": "~0.28.x",
    "expo-background-fetch": "~12.x",
    "expo-task-manager": "~11.x",

    "react-native-maps": "^1.14.x",

    "@react-native-async-storage/async-storage": "^1.x",
    "@react-native-community/netinfo": "^11.x",

    "nativewind": "^4.x",
    "react-native-reanimated": "^3.x",
    "react-native-gesture-handler": "^2.x",

    "zustand": "^4.x",
    "date-fns": "^3.x",
    "clsx": "^2.x"
  },
  "devDependencies": {
    "typescript": "^5.x",
    "@types/react": "^18.x",
    "tailwindcss": "^3.x",
    "babel-plugin-module-resolver": "^5.x"
  }
}
```
