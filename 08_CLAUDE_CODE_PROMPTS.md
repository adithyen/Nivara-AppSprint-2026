> ⚠️ **SUPERSEDED — HISTORICAL REFERENCE (2026-08-08).**
> These session prompts were written for the old **Expo / React Native** build
> (TypeScript, NativeWind, Zustand, Expo Router, react-native-maps). Nivara is now
> **Flutter + Dart** (Riverpod, go_router, maplibre_gl, Ola Maps). Build from
> [`CLAUDE.md`](CLAUDE.md) and [`PROJECT_STATE.md`](PROJECT_STATE.md) instead.
> **Do not follow these prompts as-is.**

# Nivara — Claude Code Prompts
**Use these prompts in order. Each session builds on the previous.**

---

## ⚠️ Before You Start Claude Code

1. Complete the pre-hackathon setup from `05_HACKATHON_ROADMAP.md`
2. Copy `CLAUDE.md` to the root of your Expo project
3. Copy all docs into a `docs/` subfolder in your project
4. Have your Supabase project created with schema already applied
5. Have `.env` file ready with all keys
6. Run `npx expo start` once manually to confirm it works

---

## SESSION 1 — Foundation, Auth, Types, Supabase
*Estimated time: 45–60 minutes*

```
Read CLAUDE.md completely before writing any code. Then read docs/03_TECHNICAL_ARCHITECTURE.md and docs/04_DATABASE_SCHEMA.md.

We are building Nivara — a civic intelligence Expo React Native app. This is a hackathon project; we build for demo quality and speed, not production perfection.

Your tasks for this session:

1. TYPES — Create types/index.ts with ALL types from CLAUDE.md:
   - EvidencePackage, Report, LFItem, UserProfile
   - ReportCategory (union of all 19 categories from PRD)
   - ReportStatus, DetectionType, LFCategory, MatchStatus
   - Add JSDoc comment on each type explaining what it is

2. CONSTANTS — Create lib/constants.ts:
   - DETECTION_THRESHOLD_G = 2.5
   - MIN_SPEED_KMH = 5
   - DEBOUNCE_METERS = 15
   - SENSOR_FREQ_HZ = 50
   - GPS_INTERVAL_MS = 2000
   - BASELINE_SAMPLES = 50
   - REPORT_CATEGORIES array with { id, label, icon, color } for all 19 categories
   - LF_CATEGORIES array with { id, label, icon } for all 13 categories

3. SUPABASE CLIENT — Create lib/supabase.ts:
   - Import createClient from @supabase/supabase-js
   - Read URL and ANON_KEY from EXPO_PUBLIC_ env vars
   - Export single supabase client instance (singleton pattern)
   - Export Database TypeScript types (or use 'any' for hackathon speed)

4. STORE — Create store/index.ts using Zustand:
   - user: UserProfile | null
   - sensorWatchEnabled: boolean
   - setSensorWatchEnabled: (v: boolean) => void
   - detectionLog: EvidencePackage[] (last 20 detections)
   - addDetection: (pkg: EvidencePackage) => void
   - mapPins: Report[] (cached map data)
   - setMapPins: (pins: Report[]) => void

5. UTILS — Create lib/utils.ts:
   - formatDistance(meters: number): string → "2.4 km" or "340 m"
   - formatDate(dateStr: string): string → "12 Jul, 2:34 PM"
   - haversineKm(lat1, lng1, lat2, lng2): number
   - cn(...classes: string[]): string (clsx equivalent for NativeWind)
   - truncate(text: string, maxLen: number): string

6. AUTH — Create app/(auth)/login.tsx:
   - Full-screen dark background with Nivara logo (use Text emoji 🛡️ as logo placeholder)
   - App name "Nivara" in large white text
   - Tagline "Your City. Your Proof. Your Voice." in smaller text
   - [Sign in with Google] button using Supabase Google OAuth
   - [Continue with Email] link (navigate to signup for hackathon — just Google matters)
   - Handle auth state: if already logged in, navigate to /(tabs)/

7. ROOT LAYOUT — Update app/_layout.tsx:
   - Check Supabase session on mount
   - If no session → redirect to /(auth)/login
   - If session → redirect to /(tabs)/
   - Wrap with ThemeProvider for dark mode (use Appearance API)
   - Show splash/loading screen while checking auth

8. TAB LAYOUT — Create app/(tabs)/_layout.tsx:
   - 5 tabs: Home (🏠), Map (🗺️), Report (+), Lost/Found (🔍), Profile (👤)
   - Report tab is center tab, larger, highlighted in brand primary blue
   - NativeWind classes for tab bar styling
   - Hide tab bar when keyboard is open

9. STUB SCREENS — Create stub screens for all 5 tabs (just Text placeholder):
   - app/(tabs)/index.tsx → "Home Dashboard (coming soon)"
   - app/(tabs)/map.tsx → "Civic Map (coming soon)"
   - app/(tabs)/report.tsx → "Quick Report (coming soon)"
   - app/(tabs)/lostfound.tsx → "Lost & Found (coming soon)"
   - app/(tabs)/profile.tsx → "Profile (coming soon)"

After completing all tasks, run: npx tsc --noEmit
Fix any TypeScript errors before ending this session.
```

---

## SESSION 2 — SensorWatch Engine + Evidence Hash
*The core "wow" feature. Most important session.*

```
Read CLAUDE.md. We are continuing Nivara (Expo React Native + Supabase + NativeWind hackathon app).

Your tasks for this session:

1. LOCATION SERVICE — Create services/LocationService.ts:
   - requestPermissionsAsync(): Promise<boolean>
   - getCurrentLocation(): Promise<{lat, lng, accuracy, altitude, speed, heading}>
   - startWatching(callback): void — subscribe to GPS updates every 2s
   - stopWatching(): void
   - getNTPTime(): Promise<number> — fetch time from worldtimeapi.org/api/ip for NTP sync
     (fallback: return Date.now() if network fails)
   - reverseGeocode(lat, lng): Promise<string> — use expo-location's reverseGeocodeAsync,
     return formatted string like "MG Road, Thiruvananthapuram"

2. EVIDENCE ENGINE — Create services/EvidenceEngine.ts:
   Implement the full evidence package system from docs/03_TECHNICAL_ARCHITECTURE.md:
   
   - getDeviceFingerprint(): Promise<string>
     Use expo-application's androidId (or getInstallationTimeAsync for iOS)
     SHA-256 hash it with salt "nivara_v1_" — NEVER store raw device ID
   
   - generateEvidencePackage(detection: RawDetection): Promise<EvidencePackage>
     Collect all fields: event_type, timestamp_device, timestamp_ntp, lat, lng,
     gps_accuracy, altitude, speed_kmph, heading, accel_z_peak, accel_z_baseline,
     gyro_x, gyro_y, gyro_z, device_fingerprint, app_version
     
     Compute SHA-256:
     - Sort all keys alphabetically
     - JSON.stringify the sorted object (deterministic)
     - expo-crypto: Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, json)
     - Attach as evidence_hash
   
   - verifyHash(pkg: EvidencePackage): Promise<boolean>
     Reconstruct the hash from all fields except evidence_hash
     Compare with stored hash — return true if matching
   
   - formatHashDisplay(hash: string): string
     Return "SHA256: " + first 8 chars + "..." + last 8 chars for display

3. SENSOR WATCH SERVICE — Create services/SensorWatchService.ts:
   This is the CORE technical feature — implement carefully:
   
   State:
   - isRunning: boolean
   - rollingBaseline: number[] (last BASELINE_SAMPLES Z readings)
   - lastDetectionLocation: {lat, lng} | null
   - currentGyroscope: {x, y, z}
   
   Methods:
   - start(): Subscribe to Accelerometer at SENSOR_FREQ_HZ
     Subscribe to Gyroscope at SENSOR_FREQ_HZ
     Subscribe to GPS via LocationService (every 2s)
     Store subscriptions for cleanup
   
   - stop(): Unsubscribe all, clear state
   
   - onAccelerometerData({x, y, z}):
     Push z to rollingBaseline (limit to BASELINE_SAMPLES)
     baseline = mean(rollingBaseline)
     peak = Math.abs(z - baseline)
     
     IF peak > DETECTION_THRESHOLD_G AND currentSpeed > MIN_SPEED_KMH:
       IF distanceFromLastDetection > DEBOUNCE_METERS:
         classifyAndReport(peak, baseline, z)
   
   - classifyAndReport(peak, baseline, rawZ):
     Classify: peak > 2.5 + duration < 500ms = POTHOLE
     Determine detection type
     Get current GPS location
     Call EvidenceEngine.generateEvidencePackage()
     Emit 'detection' event with full EvidencePackage
     Update lastDetectionLocation
     Save to AsyncStorage detection log
   
   Pattern: implement as class with EventEmitter (use mitt library or Node EventEmitter)

4. useSensorWatch HOOK — Create hooks/useSensorWatch.ts:
   - Wraps SensorWatchService
   - Returns: { isEnabled, toggle, latestDetection, detectionLog }
   - When detection fires: update Zustand detectionLog
   - Show banner via state (pendingDetection)
   - toggle(): start or stop SensorWatchService; update Zustand
   - Request location permissions before starting

5. HOME SCREEN — Update app/(tabs)/index.tsx:
   - SensorWatch card:
     Large prominent card with toggle switch
     When ON: animated pulsing green dot + "Monitoring road quality..."
     When OFF: gray + "Tap to start passive monitoring"
   - Detection log section:
     Last 3 detections with type, location, time ago, "View Proof" link
   - When detection fires:
     Banner slides down from top:
     "🚧 Pothole detected · MG Road · [Report Now] [Dismiss]"
     Banner auto-dismisses after 6 seconds
     Haptic: Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)
   - Zustand: read detectionLog, sensorWatchEnabled

6. EVIDENCE VIEWER SCREEN — Create complaint/evidence/[id].tsx:
   - Show full EvidencePackage in a "proof document" style
   - Header: "🔐 Tamper-Proof Evidence"
   - Fields displayed in card rows: GPS coordinates, speed, acceleration peak,
     baseline, device fingerprint (truncated), timestamp
   - Hash section at bottom: styled like a certificate
     "Evidence Hash"
     [monospace hash string] — [Copy] button
   - Green checkmark: "✓ Hash verified — this evidence has not been tampered with"
   - Call verifyHash() on mount; show verification result

After all tasks, run: npx tsc --noEmit and fix errors.
Test: walk with phone, simulate bump by tapping desk → detection should fire → banner appears.
```

---

## SESSION 3 — Complaint Form, Map, Supabase Integration

```
Read CLAUDE.md. Continuing Nivara. Sessions 1-2 done: auth, types, sensor engine, evidence system.

Your tasks:

1. COMPLAINT FORM — Create app/complaint/new.tsx:
   Pre-fill from navigation params: { evidencePackage?, preCategory?, preLat?, preLng? }
   
   Form fields:
   A) Category grid: 3×4 grid of TouchableOpacity tiles
      Each tile: category icon (emoji) + label + background color
      Use REPORT_CATEGORIES from constants.ts
      Selected = highlighted with primary blue border
   
   B) Location section:
      Show map preview (MapView, small, ~150px height, not interactive)
      Current GPS auto-detected, displayed as address string
      [Change Location] → open fullscreen map picker (draggable pin)
   
   C) Severity picker: Low / Medium / High / Emergency (segmented control style)
      Auto-estimated from accel_z_peak if from SensorWatch
   
   D) Description: TextInput, multiline, max 200 chars, optional
      Placeholder: "Optional: add more details..."
   
   E) Photos: horizontal scrollable row
      [+ Add Photo] chip → expo-image-picker
      Max 3 photos, shown as thumbnails with ✕ to remove
      Upload to Supabase Storage bucket 'complaint-photos'
      Path: {userId}/{reportId}/{index}.jpg
   
   F) Evidence badge (if from SensorWatch):
      Blue card: "🔐 Tamper-proof evidence attached"
      Shows hash (truncated) + "View full proof" link
   
   Submit button: "Submit Report" — primary blue, full width
   On submit:
   - Validate: category and location required
   - Upload photos first, get URLs
   - Insert into reports table via Supabase
   - Navigate to complaint/[id] on success
   - Show error toast on failure

2. COMPLAINT DETAIL — Create app/complaint/[id].tsx:
   Fetch report by ID from Supabase
   Display: category badge, status badge, severity, address, description, photos
   Evidence section: if evidence_package exists, show "View Proof" → navigates to evidence screen
   Confirmation section: count + [Confirm this too] button
   Map: small non-interactive preview showing pin location
   Share button: copy deep link to this report

3. MAP SCREEN — Create app/(tabs)/map.tsx:
   Full-screen MapView (react-native-maps)
   Initial region: user's GPS location, delta 0.05
   
   Fetch reports: Supabase query with lat/lng bounding box of current map view
   Plot pins: custom markers with category-colored dots
   
   Supabase Realtime subscription:
   Channel 'civic-reports', event INSERT on reports table
   New report → animate new pin appearing on map
   
   Tap pin → BottomSheet (react-native-gesture-handler or custom):
   Category badge + title
   Address, time ago
   Confirmation count ✓
   Status badge
   [Confirm] button (calls insert into confirmations)
   [View Details] → navigate to complaint/[id]
   
   Top controls (absolute positioned):
   Category filter chips: [All] [Roads] [Sanitation] [Lights] [Water]
   Toggling a filter re-queries Supabase with category filter
   
   [Near Me] FAB button: bottom-right, animates map to user location

4. OFFLINE QUEUE — Create services/OfflineQueue.ts:
   On complaint submit, if no network:
   - Save to AsyncStorage queue: key 'offline_reports', value: Report[]
   - Show toast: "No internet. Report saved. Will submit automatically when connected."
   
   NetInfo subscription:
   - When network restored: flush queue → submit all pending reports
   - Show toast: "X pending reports submitted"

5. HOOKS — Create:
   hooks/useReports.ts:
   - createReport(data: CreateReportInput): Promise<Report>
   - getReportById(id: string): Promise<Report>
   - getMyReports(): Promise<Report[]>
   - getNearbyReports(lat, lng, radiusKm): Promise<Report[]>
   - addConfirmation(reportId: string): Promise<void>
   
   hooks/useLocation.ts:
   - currentLocation: {lat, lng, address} | null
   - isLoading: boolean
   - requestPermissionAndStart(): Promise<void>
   - reverseGeocode(lat, lng): Promise<string>

After all tasks:
- npx tsc --noEmit
- Test: submit a complaint from SensorWatch detection → appears on map on another device/tab
- Test: submit manually → map shows it live
```

---

## SESSION 4 — Lost & Found + Match System

```
Read CLAUDE.md. Continuing Nivara. Sessions 1-3 done: auth, sensors, evidence, complaints, map.
Now building the Lost & Found module.

Your tasks:

1. LOST/FOUND HUB — Update app/(tabs)/lostfound.tsx:
   Top tabs: [Lost Items] [Found Items] [Matches]
   Each tab shows a scrollable list of LFItem cards
   
   LFItem card: category icon + title + distance from user + days ago + status badge
   Tap card → navigate to lostfound/[id].tsx (detail view — stub for now)
   
   FAB: + button → action sheet:
   [Report Something I Lost] → navigate to lostfound/report-lost.tsx
   [Report Something I Found] → navigate to lostfound/report-found.tsx

2. REPORT LOST FORM — Create app/lostfound/report-lost.tsx:
   Fields:
   - Category: horizontal scroll icon picker (all 13 LF categories)
   - Title: TextInput "e.g. Blue iPhone 14 Pro"
   - Description: TextInput multiline "Include unique identifiers — last 4 digits of Aadhaar, scratches etc."
   - Last seen location: map picker (drag pin)
   - Last seen date: DateTimePicker (expo date picker or simple date input)
   - Photo: optional, single photo
   - Contact method: [In-App Only ✓] [Show Phone Number] [Show WhatsApp]
   - If phone/whatsapp: phone number input
   - Reward (optional): TextInput "₹ ___" — "Offering a reward encourages returns"
   
   Privacy notice: "⚠️ Do not include your full Aadhaar number — describe last 4 digits only"
   
   Submit → insert into lf_items with item_type='LOST'
   On success: show "Posted! We'll notify you if someone finds it." → navigate back

3. REPORT FOUND FORM — Create app/lostfound/report-found.tsx:
   Fields (similar but adapted for found items):
   - Category: same picker
   - Title: "What did you find? e.g. Wallet with ID cards"
   - Description: "Describe it enough to verify ownership"
   - Where found: map picker
   - When found: date picker
   - Photo: strongly encouraged — show "Add photo to help verify ownership" prompt
   - What you'll do with it: [Keeping safe at home] [Dropped at police station] [Still at location]
   - Contact: same as lost form
   
   Privacy note: "Location will show as approximate (within 500m) to protect your safety"
   
   Submit → insert into lf_items with item_type='FOUND'
   Supabase Edge Function triggers → runs match algorithm
   Show: "Posted! We'll notify you if there's a match."

4. MATCH DETAIL — Create app/lostfound/match/[id].tsx:
   Side-by-side comparison:
   Left card (YOUR ITEM): category, title, description, date, distance
   Right card (POTENTIAL MATCH): same fields
   
   Match score bar: "82% match likelihood" with colored bar
   
   Buttons:
   [✓ Yes, this looks like mine!] → update match status → reveal contact
   [✗ Not my item] → dismiss match
   
   After mutual confirmation:
   Show contact details as per each party's preference
   "🎉 Match confirmed! Here's how to connect:"
   [WhatsApp] [Call] [In-App Message (stub)]

5. HOOKS — Create hooks/useLostFound.ts:
   - reportLost(data: CreateLFItemInput): Promise<LFItem>
   - reportFound(data: CreateLFItemInput): Promise<LFItem>
   - getNearbyItems(lat, lng, type, radiusKm): Promise<LFItem[]>
   - getMyItems(): Promise<LFItem[]>
   - getMyMatches(): Promise<LFMatch[]>
   - confirmMatch(matchId): Promise<void>
   - rejectMatch(matchId): Promise<void>

6. SUPABASE REALTIME FOR MATCHES:
   In useLostFound hook, subscribe to lf_matches table filtered by user's item IDs
   When new match arrives: update local state + show in-app banner:
   "🔍 Potential match found for your [item]! Check the Matches tab."

7. ADD LF PINS TO MAP — Update app/(tabs)/map.tsx:
   Add toggle: [Civic Issues ✓] [Lost & Found ✓]
   LF pins: different style (magnifying glass emoji marker)
   Lost item pin = amber
   Found item pin = green
   Tap LF pin → bottom sheet with item summary + [View Match] button

After all tasks:
- npx tsc --noEmit  
- End-to-end test: report lost item → report found item same category nearby →
  match appears in Matches tab → confirm match → contact revealed
```

---

## SESSION 5 — Home Dashboard, Polish, Demo Data

```
Read CLAUDE.md. Continuing Nivara. Sessions 1-4 done. Now: home dashboard, polish, demo data.

Your tasks:

1. HOME DASHBOARD — Build full app/(tabs)/index.tsx:
   
   HEADER: "Good morning, [firstName] 👋" + Nivara logo
   
   SENSORWATCH CARD (most prominent):
   When ON:
     Green pulsing animated dot (Animated API: opacity 1↔0.3 loop)
     "🛡️ Monitoring road quality..."
     "Last detection: 2 minutes ago · MG Road" (from detectionLog)
     [Stop Monitoring] button
   When OFF:
     Large [Start SensorWatch] button with description
     "Passive road monitoring — no action needed"
   
   STATS ROW (3 equal cards):
   [My Reports: 7] [Confirmations: 23] [Score: 145 pts]
   
   NEARBY ISSUES (horizontal scroll):
   "⚠️ Issues near you" heading + count badge
   3 report cards showing closest unresolved issues
   Each: category icon + distance + time + confirm count
   
   RECENT DETECTIONS (vertical list):
   Last 3 auto-detections from detectionLog
   Each: type + location + time + [View Proof] + [Report] if not yet reported
   
   NEIGHBORHOOD SCORE:
   Card showing "Ward 45 Health: C+" with explanation
   "Based on 14 open issues in your ward"

2. PROFILE SCREEN — Build app/(tabs)/profile.tsx:
   User avatar (initials if no photo) + display name + city
   
   Score card:
   "CivicScore: 145" + progress bar to next level
   Level badge: "Street Watcher 🔦"
   
   Stats grid:
   Reports filed | Confirmations | Lost items recovered | Detections
   
   Badges section (horizontal scroll):
   Show earned badges with locked state for unearned
   Road Watcher (10 reports) · Street Hero (50) · Finder (match confirmed)
   
   My Reports section: recent 5 reports with status
   My LF Items section: recent 5 items with status
   
   [Sign Out] button at bottom

3. UI COMPONENTS — Build shared components/ui/:
   
   Badge.tsx: colored pill badge with text
   Props: label, variant ('success'|'warning'|'danger'|'info'|'default')
   
   Card.tsx: rounded white card with shadow
   Props: children, className (for NativeWind extension)
   
   Button.tsx: primary, secondary, outline variants
   Props: label, onPress, variant, loading, icon, size
   Show ActivityIndicator when loading=true, disable press
   
   CategoryIcon.tsx: given category string, return emoji + color
   
   StatCard.tsx: number + label in a small card

4. SEED DEMO DATA — Create scripts/seed.ts:
   This is for the hackathon demo — pre-populate realistic data:
   
   Reports (30 total):
   - 10 POTHOLE reports clustered near a real intersection in your demo city
   - 5 GARBAGE reports
   - 5 STREET_LIGHT reports  
   - 3 WATERLOGGING reports
   - 5 OPEN_MANHOLE reports
   - 2 FALLEN_TREE reports
   - Mix of statuses: 20 SUBMITTED, 5 IN_PROGRESS, 5 RESOLVED
   - 3 reports with is_community_verified=true (10+ confirmations)
   
   Sensor detections (50):
   - Random detections along 3 streets near demo city
   - Creates road quality heatmap effect
   
   LF Items (6):
   - 2 LOST: Aadhaar card + iPhone
   - 2 FOUND: Aadhaar card (matching!) + wallet
   - 1 match already created between lost Aadhaar + found Aadhaar
   - 1 LOST pet (no match — still searching)
   
   Demo user: pre-give 145 civic score points
   
   To run: npx ts-node scripts/seed.ts (add ts-node to devDependencies)

5. ANIMATIONS:
   New map pin appearing: scale from 0 to 1 + spring using Animated API
   SensorWatch detection banner: slide in from top with spring
   Match notification: slide in from bottom
   Tab press: subtle scale feedback on icons

6. FINAL TYPE CHECK AND LINT:
   npx tsc --noEmit
   Fix ALL TypeScript errors
   Ensure no 'any' types where avoidable
   Remove all console.log statements (replace with conditional __DEV__ checks)

After all tasks, do a full end-to-end demo test:
  1. Start SensorWatch → walk with phone → detection fires → banner shows → tap Report
  2. Form pre-filled → submit → pin appears on map tab
  3. Go to Lost & Found → Matches tab → pre-seeded match shown
  4. Tap match → confirm → contact revealed
  5. Profile shows updated score
The app should be demo-ready after this session.
```

---

## SESSION 6 — Final Polish + Demo Optimization (If Time Allows)

```
Read CLAUDE.md. Continuing Nivara. App is functionally complete. This session is polish + demo optimization.

Tasks (do in priority order, stop when time runs out):

PRIORITY 1 — Demo Reliability:
[ ] Add error boundaries on every screen (show user-friendly error, not crash)
[ ] Add loading skeletons on map, home, LF list (use animated shimmer)
[ ] Empty states on all lists: illustrated + clear call-to-action
[ ] Network error handling: retry buttons everywhere a fetch can fail
[ ] Test on actual Android phone (not just simulator) — fix any device-specific issues

PRIORITY 2 — Evidence Feature Polish:
[ ] Evidence screen: make it look like an official document
    - Add "Issued by Nivara v1.0" footer
    - Display all coordinates to 6 decimal places
    - Show verification animation: 3 spinning rings → green checkmark
    - "If this hash is presented in court: it cannot be denied" explanatory text

PRIORITY 3 — Map Polish:
[ ] Road quality overlay: show gradient on pre-driven streets
    Color: green (#27AE60) for good, yellow (#F5A623) for fair, red (#E74C3C) for bad
[ ] Cluster animation: pins cluster and uncluster smoothly on zoom
[ ] My location indicator: pulsing blue dot (react-native-maps built-in)

PRIORITY 4 — Onboarding:
[ ] After login, show 3-screen intro carousel:
    Screen 1: "Drive normally. We do the work." (SensorWatch)
    Screen 2: "Your report. Tamper-proof forever." (Evidence)
    Screen 3: "Lost something? The city helps." (Lost & Found)
[ ] Store 'onboarding_complete' in AsyncStorage

PRIORITY 5 — Performance:
[ ] Memoize expensive map queries with useMemo
[ ] FlatList keyExtractor on all lists
[ ] Image lazy loading for complaint photos
[ ] Reduce re-renders: check with React DevTools

Do not go past 1 hour on any single priority if the hackathon ends soon.
Demo-quality is the goal, not production-quality.
```

---

## Quick Reference: Supabase Queries to Use

```typescript
// Get nearby reports (within 5km)
const { data: reports } = await supabase
  .from('reports')
  .select('*')
  .eq('status', 'SUBMITTED')
  .gte('lat', lat - 0.045)
  .lte('lat', lat + 0.045)
  .gte('lng', lng - 0.045)
  .lte('lng', lng + 0.045)
  .order('created_at', { ascending: false })
  .limit(50);

// Insert report
const { data, error } = await supabase
  .from('reports')
  .insert({ ...reportData, user_id: user.id })
  .select()
  .single();

// Add confirmation
await supabase.from('confirmations')
  .insert({ report_id: reportId, user_id: userId, type: 'CONFIRM' });

// Get LF items
const { data } = await supabase
  .from('lf_items')
  .select('*')
  .eq('status', 'ACTIVE')
  .eq('item_type', 'FOUND')
  .order('created_at', { ascending: false });

// Realtime subscription
const channel = supabase
  .channel('map-updates')
  .on('postgres_changes', {
    event: 'INSERT', schema: 'public', table: 'reports'
  }, (payload) => {
    addPin(payload.new as Report);
  })
  .subscribe();
```
