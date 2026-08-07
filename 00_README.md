# Nivara — Documentation Suite
### "Your City. Your Proof. Your Voice."
**2-Day Hackathon Build | Civic Intelligence Platform**

---

## The Pitch (60 seconds)

> *"Every existing civic app in India asks you to stop, photograph, fill a form, and submit.
> Nivara asks you to do nothing. Drive over a pothole — we auto-detect it, generate
> tamper-proof cryptographic evidence, and put it on a live map. No photo. No form.
> Just proof. And while we're at it — it's also India's first civic app that integrates
> Lost & Found with complaint management on one map."*

**What makes it nationally novel:**

| Feature | Existing Indian Apps | Nivara |
|---------|---------------------|--------|
| Pothole detection | Manual photo required | **Passive accelerometer — hands-free** |
| Evidence quality | Photo (can be staged) | **Crypto hash of sensor data — unfakeable** |
| Scope | City-specific, single-category | **Multi-category + Lost & Found** |
| Verification | Official only | **Community-verified + crowdsourced** |
| User effort | Stop → photo → form → submit | **Drive as normal → one tap to confirm** |

---

## Document Suite

| # | Document | Description |
|---|----------|-------------|
| 01 | [Product Requirements (PRD)](./01_PRODUCT_REQUIREMENTS.md) | All modules, features, user stories |
| 02 | [Workflow Document](./02_WORKFLOW.md) | All user flows and system pipelines |
| 03 | [Technical Architecture](./03_TECHNICAL_ARCHITECTURE.md) | Stack, sensor pipeline, crypto system |
| 04 | [Database Schema](./04_DATABASE_SCHEMA.md) | Supabase/PostgreSQL tables |
| 05 | [Hackathon Roadmap](./05_HACKATHON_ROADMAP.md) | Hour-by-hour 2-day build plan |
| 06 | [API Integration Guide](./06_API_INTEGRATION_GUIDE.md) | Expo sensors, maps, Supabase, hashing |
| 07 | [CLAUDE.md](./CLAUDE.md) | Claude Code project context file |
| 08 | [Claude Code Prompts](./08_CLAUDE_CODE_PROMPTS.md) | Session prompts to build the app |

---

## App Modules Summary

```
MODULE 1 — SENSORWATCH (The Wow Feature)
  └─ Background accelerometer monitors while you drive/walk
  └─ Z-axis spike > threshold + GPS speed > 5 kmph = pothole detected
  └─ Generates tamper-proof evidence package (SHA-256 hash)
  └─ Distinguishes pothole vs speed breaker vs bad road via pattern
  └─ Road quality score auto-generated per street driven

MODULE 2 — CIVICREPORT (Complaint Management)
  └─ 10 categories: Roads · Sanitation · Street Lights · Water · Power ·
     Encroachment · Animals · Noise · Public Property · Other
  └─ One-tap report from SensorWatch detection
  └─ Manual report with photo + GPS + description
  └─ Auto-route to relevant authority (BBMP / municipality / KSEB etc.)
  └─ Status tracker: Submitted → Acknowledged → In Progress → Resolved
  └─ Push notification on status change

MODULE 3 — LOSTFOUND (India's First Civic Lost & Found)
  └─ Report lost: category, description, last-seen location, contact
  └─ Report found: category, description, where found, contact
  └─ Smart auto-match: category + location proximity + time window
  └─ Instant notification when a match is found
  └─ Items: Documents · Electronics · Keys · Wallets · Vehicles · Pets · Other
  └─ Handover confirmation flow

MODULE 4 — CIVICMAP (Live Community Map)
  └─ Real-time heatmap: red = problem areas, green = clear
  └─ Filter by category, date, status, distance
  └─ Community reports layered with Lost & Found pins
  └─ "Near me" (500m) widget on home screen

MODULE 5 — COMMUNITY VERIFY
  └─ "I confirm this too" — tap to add your voice to a report
  └─ 5+ confirmations → auto-escalate to municipality
  └─ "This is fixed" → mark resolved (with optional photo proof)
  └─ Report credibility score based on confirmations

MODULE 6 — CIVICSCORE (Gamification)
  └─ Points: report (+10), verify (+5), resolved (+20), lost-found match (+50)
  └─ Ward leaderboard + city leaderboard
  └─ Badges: Road Watcher · Street Hero · Community Champion · Finder
  └─ Neighborhood Health Score for your ward
```

---

## Tech Stack

> **Stack updated 2026-08-08:** built in **Flutter** (not Expo RN), maps via
> **Ola Maps + OSM** (not Google). See `CLAUDE.md`, `09_ADMIN_AND_AUTH.md`,
> `10_MAPS_INTEGRATION.md`.

| Layer | Technology | Why |
|-------|-----------|-----|
| Mobile | Flutter (Dart) | Reliable single-command release APK; smooth on-device; workshop stack |
| Navigation | go_router | Declarative, guarded routes for auth + admin roles |
| State | Riverpod | Testable app state; server state via direct Supabase queries |
| Backend | Supabase | Zero backend code; instant auth; Realtime built-in |
| Database | PostgreSQL (Supabase) | Spatial queries (PostGIS); jsonb for sensor data |
| Maps | maplibre_gl + Ola Maps (OSM fallback) | India-first tiles, open renderer, no Google billing |
| Sensors | sensors_plus | Accelerometer, gyroscope |
| Location | geolocator | Foreground + background GPS |
| Crypto | crypto (Dart) | SHA-256 evidence hashing |
| Camera | image_picker | Photos for complaints |
| Notifications | flutter_local_notifications | Status updates + lost-found matches |
| Hosting | Supabase (all-in-one) | No separate backend server needed |

---

## Hackathon Differentiators (Judge Talking Points)

1. **"Zero user friction"** — passive detection while you just live your life
2. **"Court-admissible-grade evidence"** — SHA-256 hash of raw sensor data is harder to fake than a photo
3. **"Scale from day one"** — every phone is a civic sensor; 150M+ smartphones in India become the world's largest road monitoring network overnight
4. **"Lost & Found + Civic = never done before"** — most civic apps ignore Lost & Found entirely despite it being a major pain point
5. **"Community verification = self-cleaning data"** — false reports get ignored; real ones get amplified

---

## Demo Flow for Presentation

```
60-second live demo:
1. [Phone on table] "I'm driving to college."
2. [Walk briskly over a bump with phone] → app auto-detects → map pin drops
3. "That just happened. No photo. No form. Look —"
4. [Show evidence screen] "SHA-256 hash. Timestamp. GPS. Speed. Can't be faked."
5. [Tap Confirm] "Report submitted. Now watch what happens when 5 people confirm it."
6. [Pre-seeded demo: 5 confirmations] → "It auto-escalates to BBMP."
7. "Now — my friend just lost their Aadhaar near this spot last week."
8. [Show Lost & Found] "We matched it to a card found 200m away. It's already reunited."
9. "This is Nivara. Your city. Your proof. Your voice."
```
