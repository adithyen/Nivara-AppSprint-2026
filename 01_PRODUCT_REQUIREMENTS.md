# Nivara — Product Requirements Document (PRD)
**Version:** 1.0 | **Type:** 2-Day Hackathon Build | **Last Updated:** July 2026

---

## 1. Problem Statement

India's civic complaint system is broken by friction. A citizen who sees a pothole must:
stop their vehicle → unlock their phone → open the right app → take a geo-tagged photo → fill a form → pick a category → submit → never know what happened next.

Result: most civic issues go unreported. Those that are reported often lack verifiable evidence, letting officials dismiss or delay them indefinitely. Lost items — ID cards, wallets, phones — have no coordinated public platform to recover them.

**Nivara eliminates all friction** through passive sensor-based detection, cryptographic evidence generation, and a unified platform that combines civic complaints, community verification, and lost & found.

---

## 2. Target Users

| User | Role | Need |
|------|------|------|
| **Daily Commuter** (Adithyan, 21) | Reports issues passively while commuting | Zero-friction; app works while phone is in pocket |
| **Concerned Resident** | Reports specific issues near home | Quick manual report; status tracking |
| **Lost Item Owner** | Lost Aadhaar / wallet | Fast platform to reach finder |
| **Good Samaritan** | Found someone's item | Easy way to return without exchanging personal details |
| **Municipality Official** (future) | Manages incoming complaints | Dashboard with priority queue and evidence |

---

## 3. Module 1 — SensorWatch (Passive Auto-Detection)

### 3.1 Pothole & Road Anomaly Detection

| ID | Requirement |
|----|-------------|
| SW-001 | Background accelerometer monitoring when SensorWatch is enabled by user |
| SW-002 | Detect pothole: Z-axis (vertical) acceleration spike exceeding configurable threshold (default: 2.5g above baseline) while GPS speed > 5 kmph |
| SW-003 | Detect speed breaker (gentler, longer profile vs sharp pothole spike) and label separately |
| SW-004 | Detect bad road patch: sustained elevated vibration over 50m+ stretch |
| SW-005 | Fuse: accelerometer + gyroscope + GPS speed + heading for each detection event |
| SW-006 | Capture GPS coordinates at moment of detection (< 2-second lag) |
| SW-007 | Ignore events at speed < 5 kmph (speed bumps in slow traffic, stepping over things) — configurable |
| SW-008 | Debounce: suppress repeated detections within 15 meters of previous detection |
| SW-009 | Battery-efficient polling: 50Hz accelerometer sampling, GPS every 2 seconds while SensorWatch active |

### 3.2 Tamper-Proof Evidence Package

| ID | Requirement |
|----|-------------|
| SW-010 | Generate evidence package for every detection: `{event_type, timestamp_device, timestamp_ntp, lat, lng, gps_accuracy, speed_kmph, heading, accel_z_peak, accel_z_baseline, gyro_x, gyro_y, gyro_z, device_fingerprint}` |
| SW-011 | `device_fingerprint` = SHA-256 of (expo unique device ID + app installation ID) — never raw hardware ID |
| SW-012 | `evidence_hash` = SHA-256 of JSON-stringified evidence package (deterministic field ordering) |
| SW-013 | Store evidence package + hash locally before any network call |
| SW-014 | On report submission, server stores evidence package and independently recomputes + verifies hash |
| SW-015 | Return server-signed receipt: `{report_id, server_received_at, submitted_hash, server_verified: true}` |
| SW-016 | Display evidence package to user: "Your tamper-proof proof" screen showing all fields + hash |
| SW-017 | Road quality score: average peak-to-noise ratio over a driven stretch → generates segment score (A/B/C/D/F) |

### 3.3 SensorWatch UX

| ID | Requirement |
|----|-------------|
| SW-018 | Home screen toggle: "SensorWatch ON/OFF" with sensor status indicator |
| SW-019 | When detection occurs: subtle haptic + small banner "Pothole detected near MG Road. Report? [Yes] [Dismiss]" |
| SW-020 | "Yes" → pre-fills report form with all sensor data + location; user adds optional note and submits |
| SW-021 | "Dismiss" → evidence still stored locally for 24h if user changes mind |
| SW-022 | Detection log: list of all auto-detected events with map, timestamp, action taken |
| SW-023 | Manual threshold calibration: "Recalibrate for my vehicle" — walk/drive normally for 10s to set baseline |

---

## 4. Module 2 — CivicReport (Complaint Management)

### 4.1 Complaint Categories

```
ROADS
  Pothole (auto-detected OR manual)
  Broken footpath / pavement
  Missing / damaged road sign
  Faded road markings
  Open manhole / uncovered drain
  Fallen tree / branch blocking road
  Flooded road / waterlogging
  Illegal speed breaker (not by municipality)

SANITATION
  Garbage overflow / overflowing bin
  Illegal dumping / waste
  Blocked stormwater drain
  Sewage overflow on road
  Dead animal on road

STREET LIGHTS & ELECTRICITY
  Street light not working
  Damaged / leaning light pole
  Sparking / dangerous electrical wire
  Illegal electricity connection
  Power outage (street-level infrastructure)

WATER SUPPLY
  Water supply disruption
  Pipe burst / leaking
  Water contamination / dirty water
  Unauthorized water connection

PUBLIC PROPERTY
  Damaged bench / bus shelter
  Vandalized public property
  Broken public toilet
  Encroachment on footpath / public space
  Illegal hoarding / advertisement

ANIMALS
  Stray dog menace (aggressive)
  Cattle on road (traffic hazard)
  Dead animal requiring disposal

NOISE & POLLUTION
  Excessive construction noise (odd hours)
  Loudspeaker / DJ noise violation
  Industrial smoke / visible air pollution
  Burning of waste

OTHER CIVIC
  Any issue not in above categories
```

### 4.2 Complaint Submission

| ID | Requirement |
|----|-------------|
| CR-001 | Quick-report button always visible on home screen and map |
| CR-002 | Category selection: icon grid (3×4) for fast selection |
| CR-003 | Location: auto-GPS (default) OR drag-pin on map OR type address |
| CR-004 | Photo: optional (1-3 photos); camera or gallery |
| CR-005 | Description: optional short text (140 chars) |
| CR-006 | Auto-populated from SensorWatch: category, location, sensor evidence pre-filled |
| CR-007 | Severity: auto-estimated from sensor peak / user can override (Low / Medium / High / Emergency) |
| CR-008 | Submit time < 30 seconds for SensorWatch-originated reports |
| CR-009 | Offline queue: if no internet, store locally and auto-submit when connected |

### 4.3 Complaint Tracking

| ID | Requirement |
|----|-------------|
| CR-010 | Status: Submitted → Acknowledged → In Progress → Resolved → Closed |
| CR-011 | "My Complaints" screen: all user's reports with status timeline |
| CR-012 | Push notification on status change |
| CR-013 | Expected resolution time shown based on category (roads: 7 days, streetlights: 3 days, etc.) |
| CR-014 | Share complaint: copy link → deep-links to complaint on map |
| CR-015 | Evidence attached: "View proof" button shows tamper-proof evidence package |

---

## 5. Module 3 — LostFound

### 5.1 Lost Item Report

| ID | Requirement |
|----|-------------|
| LF-001 | Report lost: category, title, description, last-seen date, last-seen location (map pin), contact preference (phone / WhatsApp / in-app message only) |
| LF-002 | Categories: Aadhaar Card · PAN Card · Driving Licence · Passport · Other Document · Mobile Phone · Wallet / Purse · Keys · Bag / Backpack · Jewellery · Pet · Vehicle · Other |
| LF-003 | Photo of item (optional but increases match chance) |
| LF-004 | Reward offered (optional): "Offering ₹500 for return" |
| LF-005 | Active for 30 days; auto-expire with option to extend |
| LF-006 | Identity verification note: "Do not share your full Aadhaar number publicly — describe last 4 digits only" |

### 5.2 Found Item Report

| ID | Requirement |
|----|-------------|
| LF-007 | Report found: category, description, where found (map), when found, what you'll do with it (keep safe / drop at police / other) |
| LF-008 | Contact preference: phone / in-app only (protect finder's privacy) |
| LF-009 | Photo of found item (important for matching) |
| LF-010 | Location shown as "within 500m of [area]" not exact coordinates (safety) |

### 5.3 Smart Matching

| ID | Requirement |
|----|-------------|
| LF-011 | Auto-match trigger: when new found item is reported, run matching against all active lost items |
| LF-012 | Match criteria: same category (required) + location proximity ≤ 2km + time proximity ≤ 7 days |
| LF-013 | Match score: category (40%) + distance (30%) + time proximity (20%) + keyword overlap in description (10%) |
| LF-014 | If match score > 70%: send push notification to BOTH parties: "We found a potential match!" |
| LF-015 | Match review screen: show both reports side-by-side; users can "Confirm match" or "Not my item" |
| LF-016 | On mutual confirmation: reveal contact details as chosen by each party |
| LF-017 | Handover confirmation: "Item returned ✓" — mark both as resolved; award CivicScore points |

---

## 6. Module 4 — CivicMap

| ID | Requirement |
|----|-------------|
| MAP-001 | Full-screen map as a core tab |
| MAP-002 | Civic complaints shown as color-coded pins by category |
| MAP-003 | Lost & Found items shown as distinct pin style |
| MAP-004 | Heatmap layer toggle: density of unresolved issues |
| MAP-005 | Cluster pins at low zoom; expand at high zoom |
| MAP-006 | Tap pin → bottom sheet: issue summary, age, confirmation count, status |
| MAP-007 | Filter bar: category checkboxes, date range, status (Open / Resolved) |
| MAP-008 | "Near me" auto-center on user location |
| MAP-009 | Auto-refresh via Supabase Realtime (new pins appear without reload) |
| MAP-010 | Road quality overlay: color-coded streets from SensorWatch road scoring data |

---

## 7. Module 5 — Community Verify

| ID | Requirement |
|----|-------------|
| CV-001 | Every complaint card has "I confirm this too" button |
| CV-002 | Tap → adds user's GPS-stamped confirmation to the report |
| CV-003 | Confirmation count shown on pin and card |
| CV-004 | Threshold: 5+ confirmations → report status changes to "Community Verified" → triggers notification to reporter |
| CV-005 | Auto-escalation trigger: 10+ confirmations → create escalated version of report (for municipality dashboard) |
| CV-006 | "This is now fixed" button → with optional photo → moves to resolution verification queue |
| CV-007 | 3+ "fixed" confirmations → changes status to Resolved |
| CV-008 | Prevent double-confirmation: one user = one confirmation per report |
| CV-009 | Prevent self-confirmation: report creator cannot confirm their own report |

---

## 8. Module 6 — CivicScore

| Action | Points |
|--------|--------|
| Submit civic complaint | +10 |
| Complaint confirmed by community | +5 per confirmation received (max +50) |
| Complaint marked resolved | +20 |
| Confirm another person's report | +5 |
| Report a found item | +15 |
| Successful lost-found match | +50 (both parties) |
| Item returned confirmed | +30 |
| Consecutive days active | +2/day streak |

| ID | Requirement |
|----|-------------|
| CS-001 | Points displayed on profile screen with level badge |
| CS-002 | Ward leaderboard: top 10 reporters in user's 5km area |
| CS-003 | City leaderboard: weekly reset |
| CS-004 | Badges: Road Watcher (10 pothole reports), Street Hero (50 reports), Community Champion (100 confirmations), Finder (5 lost-found matches) |
| CS-005 | Neighborhood Health Score: ward-level score derived from open vs resolved issue ratio |
| CS-006 | Share score card: "I've reported 23 civic issues in Trivandrum this month" |

---

## 9. Non-Functional Requirements

| Category | Requirement |
|----------|-------------|
| Performance | SensorWatch detection latency < 2s from event to pin on map |
| Battery | SensorWatch background mode < 3% per hour (50Hz poll, coalesced GPS) |
| Offline | Complaint submission queued offline; map uses cached tiles |
| Privacy | GPS coordinates fuzzy by ±50m for Lost & Found finder location |
| Security | Evidence hash server-verified; no raw device ID stored |
| Accessibility | Large tap targets; color-blind-safe category colors; font scaling |
| Platform | Android 10+ primary; iOS 14+ secondary; hackathon demo on Android |

---

## 10. Hackathon MVP Scope (What to Build in 2 Days)

```
MUST BUILD (Day 1–2):
  ✅ Auth (Google Sign-In via Supabase)
  ✅ SensorWatch: accelerometer detection + evidence hash
  ✅ Manual civic complaint form (top 3 categories: Roads, Sanitation, Lights)
  ✅ Map with live pins (Supabase Realtime)
  ✅ Lost & Found: report lost + report found + basic match display
  ✅ Community verify: confirm button + count

DEMO-ONLY (pre-seeded data):
  ⚡ Community auto-escalation (show with pre-seeded 10 confirmations)
  ⚡ Road quality scoring map overlay (show on pre-driven route)
  ⚡ Municipality dashboard (static mockup slide)

SKIP FOR HACKATHON:
  ❌ Push notifications (too long to configure)
  ❌ Full status tracking pipeline
  ❌ CivicScore leaderboard (show static version)
  ❌ Barometer waterlogging detection
```
