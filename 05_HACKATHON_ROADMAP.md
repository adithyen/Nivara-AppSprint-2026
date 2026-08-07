> ⚠️ **SUPERSEDED — HISTORICAL REFERENCE (2026-08-08).**
> This hour-by-hour plan targets the old **Expo / React Native + Google Maps**
> stack. Nivara is now **Flutter + Supabase + Ola Maps (OSM fallback)**. For the
> current build order and status see [`PROJECT_STATE.md`](PROJECT_STATE.md); for
> guardrails see [`CLAUDE.md`](CLAUDE.md). **Do not build from this file.**

# Nivara — Hackathon Roadmap (Hour-by-Hour)
**2-Day Build Plan | Every hour counts**

---

## Pre-Hackathon Setup (Night Before)

Do this the evening before the hackathon starts. **Don't waste morning hours on setup.**

```bash
# 1. Install Expo CLI
npm install -g expo-cli eas-cli

# 2. Create project
npx create-expo-app@latest nivara --template tabs
cd nivara

# 3. Install all dependencies
npx expo install expo-sensors expo-location expo-crypto expo-device \
  expo-application expo-image-picker expo-notifications \
  expo-background-fetch expo-task-manager \
  @supabase/supabase-js @react-native-async-storage/async-storage \
  @react-native-community/netinfo react-native-maps \
  nativewind react-native-reanimated react-native-gesture-handler \
  zustand date-fns

# 4. Create Supabase project (supabase.com)
#    Run schema from 04_DATABASE_SCHEMA.md in SQL Editor
#    Enable Google Auth
#    Note: SUPABASE_URL and SUPABASE_ANON_KEY

# 5. Set up .env
echo "EXPO_PUBLIC_SUPABASE_URL=https://xxx.supabase.co" > .env
echo "EXPO_PUBLIC_SUPABASE_ANON_KEY=eyJ..." >> .env
echo "EXPO_PUBLIC_GOOGLE_MAPS_KEY=AIza..." >> .env

# 6. Test on phone: expo start → scan QR with Expo Go
# 7. Seed 20-30 demo reports into Supabase (run seed.sql)
```

---

## DAY 1 (12 Hours)

### Hour 1–2: Foundation
```
[ ] Set up Expo Router: (auth)/ and (tabs)/ groups
[ ] lib/supabase.ts: client singleton
[ ] types/index.ts: Report, LFItem, EvidencePackage, UserProfile
[ ] Zustand store: useAppStore (user, sensorWatchEnabled)
[ ] Login screen: Supabase Google OAuth
[ ] Auth middleware: redirect to login if no session
[ ] Bottom tab navigator: Home | Map | Report | Found/Lost | Profile
[ ] NativeWind configured: tailwind.config.js + babel.config.js
CHECKPOINT: Open app → see bottom tabs → tap Login → Google auth works
```

### Hour 3–4: SensorWatch Engine
```
[ ] services/SensorWatchService.ts:
    - Accelerometer subscription at 50Hz
    - Rolling baseline calculation (50 samples)
    - Threshold detection (Z-axis > 2.5g above baseline)
    - GPS speed check (> 5 kmph to filter out walking bumps)
    - Debounce: 15 meter minimum between detections
    - EventEmitter pattern: emits 'detection' event

[ ] services/EvidenceEngine.ts:
    - generateEvidencePackage(): collects all sensor data
    - Compute SHA-256 hash via expo-crypto
    - Returns full evidence package

[ ] Home screen: SensorWatch toggle ON/OFF
[ ] Banner notification when detection triggers:
    "🚧 Pothole detected near [location]. Report?"
    [Yes, Report] [Dismiss]

CHECKPOINT: Walk briskly, tap phone on desk → detection fires → banner appears
```

### Hour 5–6: Complaint Form + Supabase Insert
```
[ ] app/complaint/new.tsx:
    - Category grid (12 icons, 3×4 layout)
    - Location: auto-GPS (show address from reverse geocode)
    - Description: optional TextInput
    - Severity picker
    - Photo picker (expo-image-picker → upload to Supabase Storage)
    - Submit → POST to Supabase reports table

[ ] From SensorWatch: pre-fill category=POTHOLE, location, evidence_package
[ ] hooks/useReports.ts: createReport(), getMyReports()
[ ] After submit: navigate to complaint detail showing evidence hash

CHECKPOINT: Tap [Yes, Report] → form pre-filled → submit → see report in Supabase
```

### Hour 7–8: Live Map
```
[ ] app/(tabs)/map.tsx: react-native-maps MapView
[ ] Fetch all ACTIVE reports near user (PostGIS radius query)
[ ] Plot colored pins by category:
    ROADS = red, SANITATION = brown, LIGHTS = yellow, other = gray
[ ] Supabase Realtime: subscribe to reports table →
    new pin appears without refresh
[ ] Tap pin → bottom sheet: title, category badge, confirmation count,
    [Confirm this too] button, [View Evidence] button (if sensor-detected)
[ ] Map filter: category toggle chips at top
[ ] "Near Me" button: re-center on user GPS

CHECKPOINT: Submit report → map pin appears live on teammate's phone
```

### Hour 9–10: Lost & Found
```
[ ] app/(tabs)/lostfound.tsx:
    - Tabs: [Lost] [Found] [Matches]
    - List of active items near user (radius 5km)
    - Item card: category icon, title, distance, days ago

[ ] app/lostfound/report-lost.tsx:
    - Category picker, title, description, photo
    - Map pin: last seen location
    - Contact method selector
    - Reward amount (optional)

[ ] app/lostfound/report-found.tsx:
    - Same fields + where found
    - "Location displayed as approximate (±500m) to protect privacy"

[ ] Supabase insert for both forms
[ ] Match list: query lf_matches where user's item is involved
[ ] match/[id].tsx: side-by-side comparison, [Confirm Match] button

CHECKPOINT: Report a lost wallet → report a found wallet 1km away → 
            match appears in Matches tab
```

### Hour 11–12: Evidence Viewer + Day 1 Polish
```
[ ] complaint/[id].tsx:
    - Full report detail
    - Evidence card: shows all sensor fields + hash
    - "Hash: SHA256: abc123..." displayed in monospace
    - Copy hash button
    - Confirmation count + Confirm button
    - Photo carousel if photos attached

[ ] Fix any crashes found during Day 1 testing
[ ] Add seed data: 25 pre-existing reports on map
[ ] Add seed data: 5 LF items (3 lost, 2 found) with a pre-created match
[ ] Test full flow end-to-end: detect → report → map → evidence → verify

END OF DAY 1: Core flow working. Sensor detection → tamper-proof report → live map → lost & found
```

---

## DAY 2 (12 Hours)

### Hour 1–2: Community Verification + CivicScore
```
[ ] Confirm button → INSERT into confirmations table
[ ] RLS check: can't confirm own report, can't double-confirm
[ ] Trigger fires → confirmation_count updates on report
[ ] UI: confirmation_count shown on pin and card
[ ] "Community Verified ✓" badge when count ≥ 5 (use pre-seeded demo data)
[ ] Score ledger: add score_events INSERT on each action
[ ] Profile screen: show total civic score, level badge
[ ] Simple leaderboard: top 5 reporters in city (static for demo)
```

### Hour 3–4: Home Dashboard
```
[ ] app/(tabs)/index.tsx — home screen:
    - "Good morning, [name]" header
    - SensorWatch toggle card (big, prominent)
    - Recent detections log: last 5 auto-detections with status
    - Stats: [Reports This Week] [Confirmations Given] [My Score]
    - "Near Me" widget: 3 closest unresolved civic issues
    - Quick actions: [Report Issue] [Report Found Item] [Lost Something]
    - Neighborhood health score: ward-level color badge
```

### Hour 5–6: Map Polish + Road Quality Overlay
```
[ ] Road quality heatmap overlay:
    - Use sensor_detections + road_quality_grid materialized view
    - Color-code driven streets: green=good, yellow=fair, red=bad
    - Toggle: "Road Quality Mode" on map
    - For demo: pre-seed 50 detections along 3 streets near demo location

[ ] Lost & Found pins on map:
    - Different pin style (magnifying glass icon)
    - Filter toggle: show/hide LF pins separately from civic pins

[ ] Cluster view: at zoom < 12, cluster nearby pins with count badge
```

### Hour 7–8: UI Polish + Animations
```
[ ] Loading skeletons on all list screens
[ ] Empty states: illustrated SVG + call-to-action button
[ ] Haptic feedback: heavy impact on detection; light on button press
[ ] Animated detection banner: slide in from top, auto-dismiss 5s
[ ] Category icons: custom SVG icons (or lucide-react-native)
[ ] Color scheme: Nivara brand colors:
    Primary: #1B6CA8 (civic blue)
    Accent:  #F5A623 (alert amber)
    Success: #27AE60 (resolved green)
    Danger:  #E74C3C (emergency red)
[ ] Dark mode: NativeWind dark: prefix variants
[ ] Smooth map pin animation: spring enter when new pin added
[ ] Bottom sheet: react-native-gesture-handler DraggableBottomSheet
```

### Hour 9–10: Demo Script + Mock Data
```
[ ] Seed script: insert realistic demo data
    - 30 reports across demo city (various categories + statuses)
    - 5 LF items with 1 confirmed match
    - 2 pre-verified reports (5+ confirmations) to show escalation
    - Road quality data on 3 specific streets

[ ] Demo account: create demo@nivara.app test account
[ ] Pre-record fallback: screen recording of full demo in case
    live demo has connectivity issues
[ ] Test: SensorWatch sensitivity calibrated for demo room floor walk
[ ] Print: A4 "evidence package" paper showing hash → for physical demo prop
[ ] Badge collection: create 3 achievements showing on profile
```

### Hour 11–12: Final Testing + Presentation Prep
```
[ ] End-to-end test: full demo flow 5 times
[ ] Fix any last-minute crashes
[ ] Optimize: disable logs in production mode
[ ] README for judges: QR code to Expo Go build
[ ] Talking points card (index card):
    1. "No existing Indian app auto-detects potholes passively"
    2. "SHA-256 hash — if the evidence is tampered, hash breaks"
    3. "Lost & Found + civic = never done before in India"
    4. "150M smartphones → world's largest road monitoring network"
    5. "Scale: zero marginal cost per new user"
```

---

## Demo Script (Practice This)

```
[60-second condensed version]

"Watch this. I'm going to put my phone in my pocket and walk normally."
[Walk over a bump or tap phone rhythmically]
"Look — pothole auto-detected. No photo. No form. Just proof."

[Show evidence screen]
"This SHA-256 hash is a fingerprint of the sensor readings, GPS, and timestamp.
If anyone modifies even one digit, the hash breaks. It's court-grade evidence."

[Tap Report → submits in 3 seconds]
[Switch to map on teammate's phone]
"My teammate's map — that pin just appeared. Real-time."

[Switch to Lost & Found]
"Last week I lost my Aadhaar near this area."
[Show pre-seeded match]
"Someone found it 400 meters away and reported it.
Nivara matched them. The Aadhaar is already back."

[Show leaderboard]
"The top reporter in this ward reported 43 civic issues this month.
That person is a hero. Nivara makes heroes visible."

"We are Nivara. Every phone is a sensor. Every citizen is a watchdog."
```

---

## If You Run Out of Time (Priority Order)

```
P1 — MUST HAVE FOR DEMO:
  ✅ SensorWatch detection (the wow)
  ✅ Evidence hash display
  ✅ Map with real-time pins
  ✅ Lost & Found with match

P2 — NICE TO HAVE:
  ⚡ Community verification button
  ⚡ Road quality overlay
  ⚡ Profile + score

P3 — SKIP IF NEEDED:
  ❌ Animations and polish
  ❌ Dark mode
  ❌ Edge cases and error handling
```
