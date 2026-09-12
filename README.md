# 📱 Nivara — Your City. Your Proof. Your Voice.

<p align="center">
  <img src="assets/banner.jpeg" alt="Nivara AppSprint 2026 Banner" width="100%"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Built%20for-AppSprint%202026-7C3AED?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Challenge%20Track-CivicTech-0D9488?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Framework-Flutter%203.x%20%7C%20Dart%203.12-02569B?style=for-the-badge&logo=flutter"/>
  <img src="https://img.shields.io/badge/Backend-Supabase%20%7C%20PostgreSQL%2015-3ECF8E?style=for-the-badge&logo=supabase"/>
  <img src="https://img.shields.io/badge/AI%20Vision-NVIDIA%20NIM%20%7C%20Llama--3.2--11B-76B900?style=for-the-badge&logo=nvidia"/>
  <img src="https://img.shields.io/badge/Maps-Ola%20Maps%20Vector-E11D48?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Release-v1.0.63%20(Production)-16A34A?style=for-the-badge&logo=android"/>
</p>

<p align="center">
  <b>An autonomous, AI-driven civic intelligence & municipal accountability network.</b><br/>
  Passive pothole detection via cryptographic sensor telemetry, multilingual continuous voice assistance, steady-lock computer vision evidence capture, proximity lost & found handovers, and closed-loop field worker remediation.
</p>

<p align="center">
  <a href="#-apk-download"><strong>📦 Download APK</strong></a> ·
  <a href="#-bonus-point-features-added"><strong>🎁 Bonus Features</strong></a> ·
  <a href="#-key-highlights"><strong>🌟 Key Innovations</strong></a> ·
  <a href="#-solution"><strong>💡 Architecture</strong></a> ·
  <a href="#-features"><strong>✨ Feature Matrix</strong></a> ·
  <a href="#-demo-video"><strong>🎥 Demo Video</strong></a> ·
  <a href="#-installation"><strong>🚀 Quickstart</strong></a>
</p>

---

# 👥 Team Information

## Team Name
`Team Nivara`

## Members

| Name | Role | Contact & Profiles |
|---|---|---|
| **Adithyan H** | Lead Full-Stack Architect, AI & Mobile Systems Engineer | [GitHub](https://github.com/adithyen) · [Email](mailto:adityenh@gmail.com) |

## Challenge Track

- [ ] 📚 EduTech
- [ ] 🏥 HealthTech
- [x] 🏙️ **CivicTech** *(Autonomous Urban Infrastructure Monitoring & Closed-Loop Governance)*
- [ ] 🌾 AgriTech / LocalTech
- [ ] 💡 Open Innovation

---

# 📖 Problem Statement

Urban infrastructure in rapidly expanding cities faces a critical crisis: **broken feedback loops between citizens and municipal authorities.**

### 1. Who Faces This Problem?
* **Everyday Commuters & Pedestrians**: Suffer severe accidents, vehicular damage, and fatal mishaps caused by unmapped potholes, open manholes, and fallen electrical poles.
* **Marginalized & Non-Tech Savvy Citizens**: Citizens who speak regional languages (e.g. Malayalam, Hindi) or cannot type lengthy formal complaints are digitally disenfranchised by complex municipal web portals.
* **Loss Victims & Finders**: Citizens who lose vital identity credentials (Aadhaar, PAN cards, driving licences, passports) face identity theft risks and have no secure, verifiable, proximity-based recovery channel.
* **Municipal Field Crews & Administrators**: City engineers are overwhelmed by duplicates, unverified bogus complaints, zero ground-truth sensor proof, and manual dispatch chaos.

### 2. Why Is This Problem Important?
* **Pothole Fatalities & Economic Loss**: In India alone, over **3,500 lives are lost annually** to road potholes, with millions of rupees in vehicular damage and lost work hours.
* **Bureaucratic Black Holes**: Over **78% of municipal complaints** filed on standard government apps remain unresolved or falsely marked "closed" without verifiable photographic proof of remediation.
* **Identity Fraud Crisis**: Lost official documents reported to physical police stations often take weeks to trace, leaving citizens vulnerable to financial scams.

### 3. What Challenges Exist Currently?
* **Friction & Apathy**: Requiring citizens to pull over, open an app, select categories, type descriptions, and take photos creates enormous friction. Most hazards go unreported.
* **No Tamper-Proof Evidence**: Traditional portals rely on easily spoofable camera uploads without sensor verification or cryptographic integrity.
* **No Closed-Loop Field Work Verification**: Existing apps lack real-time worker dispatch, progress logging, remediation photo proof, and citizen confirmation gates.
* **Total Breakdown in Offline & Low-Connectivity Zones**: Standard apps crash or drop data when traveling through cellular dead zones.

---

# 💡 Solution

**Nivara** (*Sanskrit for "Protection, Shelter, and Resolution"*) transforms any smartphone into a passive, autonomous civic watchdog and establishes a trusted, closed-loop civic accountability network.

```mermaid
graph TD
    subgraph Passive Sensing & Input
        A[In-Transit Commute] -->|50Hz Accelerometer + GPS| B(SensorWatch Engine)
        C[Multilingual Voice] -->|Continuous Speech STT| D(Voice Assistant)
        E[Steady-Lock Camera] -->|NVIDIA NIM Llama-3.2-90B| F(Vision AI Inspection)
    end

    subgraph Cryptographic Verification & Core
        B -->|Vector Jolt > 2.5g| G[SHA-256 Evidence Package Engine]
        D -->|Editable Transcript + Slot Extraction| H[Report Pipeline]
        F -->|BBox + Category Validation| H
        G --> H
    end

    subgraph Closed-Loop Municipal Cloud
        H -->|PostGIS & RLS| I[(Supabase PostgreSQL 15)]
        I -->|Auto-Dispatch| J[Municipal Admin Dashboard]
        J -->|Task Assignment| K[Field Worker Crew]
        K -->|Remediation Note + Photo Proof| I
        I -->|Realtime Trigger| L[Community Verification & Closure]
    end

    subgraph Proximity Network
        M[Lost & Found Match] -->|PostGIS 2km Spatial Window| I
        I -->|Realtime Channel| N[Dynamic Handover Pass: QR + 6-Digit PIN]
    end
```

### Main Workflows & Innovations:
1. **Autonomous Passive Sensing (SensorWatch)**: Runs silently in the background while driving or riding. A high-frequency accelerometer pipeline monitors linear acceleration jolts ($> 2.5g$), filters road noise via adaptive rolling baselines and speed deadbands, and generates a cryptographic **SHA-256 evidence package** containing the exact shock waveform, GPS coordinates, timestamp, and speed.
2. **Continuous Multilingual Voice Assistant**: Natural speech input supporting **Malayalam, Hindi, and English**. Features an editable live transcript box, zero premature speech cutoffs, automated civic category and severity slot extraction, and mandatory photo evidence gating.
3. **Physical Steady-Lock Vision AI**: Powered by **NVIDIA NIM Llama-3.2-90B Vision Instruct**. Automatically fires the camera shutter only when physical phone gyro/accelerometer stability is locked, performing instant bounding-box confirmation and civic categorization.
4. **Mutual Proximity Lost & Found Network**: Connects lost items with found reports within a 2km spatial radius. Protects user identity through a **Dual-Key Handshake**: a dynamic expiring cryptographic QR pass and a 6-digit proximity PIN broadcast over private Supabase Realtime channels.
5. **Closed-Loop 3-Way Governance**: Citizens report issues $\rightarrow$ Municipal Admins assign by department/ward $\rightarrow$ Field Workers remediate with photographic proof $\rightarrow$ Community confirms resolution (requiring 3 independent confirmations before permanent closure).
6. **Resilient Offline-First Architecture**: Intelligent local caching and a background sync manager guarantee that no report, sensor jolt, or vote is ever lost when traveling through offline regions.

---

# ✨ Features & Architectural Matrix

### 🎁 Bonus Point Features Added
* **App Store Publication Link**: `<fill it later>` *(Production APK signed and distributed via GitHub Releases & APK Mirror)*
* **Comprehensive Accessibility Features**:
  * **Screen Reader & TalkBack Semantics**: Every interactive control, status badge, camera HUD overlay, and map layer is equipped with declarative `Semantics(...)` metadata, providing an effortless experience for visually impaired users.
  * **Dynamic Typography & Fluid Font Scaling**: Fluid responsive layouts that adapt cleanly to system-level font scaling and text accessibility configurations without truncation or layout clipping.
  * **High-Contrast Dark Aesthetics (WCAG AAA)**: Precision dark theme (`#0B0F17`, `#162032`) designed with luminous neon accents (`#00FFCC`, `#3ECF8E`, `#F59E0B`), guaranteeing high readability and contrast in direct sunlight or during nighttime transit.
  * **Emil Kowalski Physical Spring Dynamics & Haptics**: Native tactile feedback pulses (`HapticFeedback.mediumImpact()`, `heavyImpact()`) synchronized with camera steady-lock, voice dictation toggle, and form validation, creating a tangible physical interface.
  * **Multilingual Text-to-Speech (TTS) Guidance**: Built-in voice synthesis prompts (`flutter_tts`) that read out hazard verification statuses, emergency instructions, and voice assistant responses in regional languages.
* **Resilient Offline-First Support**:
  * **Zero-Data-Loss Local Queue**: Powered by `OfflineQueueService` with persistent disk storage (`offline_reports_queue.json`) and local media caching.
  * **Optimistic Local Execution**: When reports, photo evidence, sensor telemetry, or community votes are generated in cellular dead zones or transit tunnels, they are cached instantly on-device and displayed optimistically.
  * **Autonomous Background Sync**: As soon as internet connectivity is restored, an autonomous synchronization engine automatically flushes the queue with exponential backoff and retries, preserving original capture timestamps and awarding civic XP retroactively.

---

### 🌐 1. Native Multilingual Experience (App Language)
* **Persistent Tri-Lingual UI**: Seamless one-tap toggle between **English**, **Hindi (`हिंदी`)**, and **Malayalam (`മലയാളം`)** (`AppLanguage.en` / `AppLanguage.hi` / `AppLanguage.ml`) with instant reactive state propagation across all tabs without app restarts.
* **Authentic Regional Terminology**: Complete localization covering all 19 civic hazard categories, severity ratings, forms, community polls, and system dialogs in English, Hindi, and Malayalam.
* **Multilingual AI Processing**: Speech-to-Text (`en-IN`, `hi-IN`, `ml-IN`) and NVIDIA NIM Vision models understand regional vernacular and generate localized titles and descriptions alongside English summaries.
* **Pan-Indian Inclusivity**: Dedicated language portal supporting all 22 recognized official languages of India with native typography and search.

---

### 🏛️ 2. Civic Hazard & Infrastructure Reporting
* **19 Granular Civic Categories**: Roads (Potholes, Broken Footpaths, Open Manholes), Utilities (Street Lights, Damaged Poles, Power Outages, Pipe Leaks, Water Shortage), Sanitation (Garbage Dumps, Blocked Drains, Open Sewage), Environment (Fallen Trees, Waterlogging), and Public Safety (Stray Animals, Encroachments, Public Property Damage, Noise Pollution).
* **Physical SensorWatch Pothole Auto-Detection**:
  * Monitors `userAccelerometerEventStream` at 50Hz with gravity removed by hardware fusion.
  * Linear acceleration spike detection ($\ge 2.5g$) with a 1500ms debounce cooldown and 3 km/h GPS jitter deadband.
  * Generates tamper-proof SHA-256 evidence payload containing raw accelerometer peaks, GPS coordinates, speed, and device metadata.
* **Continuous AI Voice Assistant**:
  * Continuous speech recognition in English, Malayalam (`ml-IN`), and Hindi (`hi-IN`) with real-time waveform visualization.
  * Interactive transcript text box allowing instant typing, editing, and slot correction.
  * Auto-extracts category, severity (`LOW`, `MEDIUM`, `HIGH`, `EMERGENCY`), and landmark location.
  * Contextual photo attachment cards (Hazard Photo Proof for Civic, Item Photo for Lost & Found, Post Image for Community).
* **NVIDIA NIM Vision AI Camera**:
  * Powered by NVIDIA NIM Vision Instruct (Meta Llama-3.2-11B Vision).
  * Real-time physical steady-lock stabilization gate (prevents blurry in-motion photos).
  * **Negative Hazard Detection Guard**: Distinguishes non-civic/indoor scenes (e.g. laptops, study tables, clean rooms) from genuine municipal hazards, alerting users with a clear **"No Civic Hazard Detected"** card and retake prompt instead of forcing false category mappings.
  * On-screen diagnostic console displaying live sensor variance and model inference confidence.

---

### 🗺️ 3. Civic Map & Nearby Municipal Services
* **Interactive Ola Maps Dark Vector Engine**: High-performance vector tile rendering with custom dark styling, spatial clustering, and real-time user location telemetry.
* **Civic Hazard Heatmaps**: Color-coded status pins (Pothole, Sewage, Open Drain, Fallen Tree) with severity indicators and instant bottom-sheet inspection.
* **Nearby Essential Public Services**: Hyperlocal proximity discovery for critical public infrastructure:
  * 🏥 **Emergency Medical Hubs & Hospitals**
  * 👮 **Police Stations & Kiosks**
  * 🚒 **Fire & Disaster Response Stations**
  * 🚻 **Public Restrooms & Toilets**
  * 🚰 **Clean Drinking Water Supply Points**
  * 🚌 **Bus Stops & Public Transit Live Tracking**
* **Emergency SOS Beacon**: One-tap emergency beacon broadcasting coordinates to local contacts with automated turn-by-turn routing via Ola Maps.

---

### ⏳ 4. Activity Timeline (Closed-Loop 6-Stage Governance)
Transparent end-to-end lifecycle tracking for every reported civic hazard:
1. 📝 **Reported**: Instant timestamp and GPS coordinates logged via citizen submission or SensorWatch auto-capture.
2. 🔍 **Under Review**: Municipal admin triage, severity verification, and department assignment.
3. 👷 **Assigned**: Dispatched to certified municipal field crew in the specific ward.
4. 🛠️ **Work in Progress**: Field team acknowledges task and commences on-site remediation.
5. 📸 **Resolved with Photo Proof**: Field worker uploads after-repair photographic proof and completion notes.
6. 🗳️ **Community Confirmed**: Decentralized citizen verification gate requiring 3 independent neighborhood confirmations before permanent case closure.

---

### 🤝 5. Work with Nivara (Volunteer & Worker Portal)
* **Civic Volunteer & Municipal Worker Onboarding**: Dedicated application portal for citizens to register as verified municipal field workers or community volunteers.
* **Multi-Department Skill Profiling**: Road repairs, sanitation, electrical utilities, water supply & plumbing, tree management, and general civic upkeep.
* **Administrative Credential Review**: Municipal admins review applicant credentials, inspect documentation, and assign official municipal roles.
* **Field Worker Task Dashboard**: Location-sorted task queues, remediation checklists, progress notes, and before/after repair photo proof upload.

---

### 🔍 6. Proximity Lost & Found Network
* **PostGIS Spatial Matching**: Automatically pairs opposite-type reports (`LOST` vs. `FOUND`) within a 2,000-metre radius and a 14-day temporal window.
* **Dynamic Handover Pass (QR / PIN Verification)**:
  * Eliminates risky public exchanges with mutual in-person cryptographic verification.
  * Generates a dynamic single-use QR token (`NIVARA-LF-...`) and a random 6-digit PIN.
  * Private Supabase Realtime broadcast channel (`handover:{claimId}`) automatically syncs verification states between claimant and owner.
* **Account & Ownership Transparency**: Prominent context cards explicitly show the report creator vs. the currently logged-in account, active claim status, and direct one-tap navigation to personal listings.

---

### 🗳️ 7. Community Board & Decentralized Governance
* **Neighbourhood Civic Feed**: Verified local announcements, community discussions, and municipal emergency advisories.
* **Anti-Fraud Civic Polls**: Cryptographically secured voter registry preventing duplicate votes; live optimistic vote tallying.
* **Civic Jobs & Volunteer Requests**: Hyperlocal micro-task boards for neighbourhood clean-up drives, volunteer tree planting, and local services.

---

### 🔔 8. Real-Time Cross-Role Notifications
* Native Android notification channels (`civic_alerts`, `work_dispatch`, `community_updates`) with sound and vibration.
* Automated PostgreSQL database triggers for instant cross-role alerts (admin acknowledgment, worker dispatch, work completion proof, and Lost & Found matches).

---

# 📱 Screenshots

> Below is the visual showcase of Nivara across Citizen, Field Worker, and Municipal Admin workflows.

| Screen | Preview | Highlights |
|---|:---:|---|
| **Live Civic Map (Dark Vector)** | <img src="docs/screenshots/01_civic_map.png" width="260" alt="Civic Map Screen"/><br/>`<!-- Placeholder: docs/screenshots/01_civic_map.png -->` | Ola Maps dark vector tiles, category-coded hazard pins, user location marker, and instant report bottom sheet. |
| **SensorWatch Engine Active** | <img src="docs/screenshots/02_sensorwatch_active.png" width="260" alt="SensorWatch Screen"/><br/>`<!-- Placeholder: docs/screenshots/02_sensorwatch_active.png -->` | Real-time 50Hz accelerometer readout, g-force shock meter, speed deadband indicator, and SHA-256 evidence package logger. |
| **AI Voice Assistant (Malayalam/Hindi/English)** | <img src="docs/screenshots/03_voice_assistant.png" width="260" alt="Voice Assistant Screen"/><br/>`<!-- Placeholder: docs/screenshots/03_voice_assistant.png -->` | Continuous speech listening waveform, interactive editable transcript box, auto-detected slot chips, and photo proof gate. |
| **NVIDIA NIM Vision Camera** | <img src="docs/screenshots/04_ai_camera.png" width="260" alt="AI Camera Screen"/><br/>`<!-- Placeholder: docs/screenshots/04_ai_camera.png -->` | Physical steady-lock gyro ring, Llama-3.2-90B inference console, auto-shutter lock, and detected hazard bounding box. |
| **Lost & Found Hub & Proximity Match** | <img src="docs/screenshots/05_lost_found_hub.png" width="260" alt="Lost & Found Hub"/><br/>`<!-- Placeholder: docs/screenshots/05_lost_found_hub.png -->` | Filterable lost/found listings, PostGIS proximity match badge, reward indicators, and high-resolution photo proof gallery. |
| **Handover Pass (Dynamic QR & 6-Digit PIN)** | <img src="docs/screenshots/06_handover_pass.png" width="260" alt="Handover Pass"/><br/>`<!-- Placeholder: docs/screenshots/06_handover_pass.png -->` | Cryptographic QR code, proximity PIN handshake, real-time mutual peer sync, and Account Ownership context card. |
| **Field Worker Task Execution** | <img src="docs/screenshots/07_worker_dashboard.png" width="260" alt="Worker Dashboard"/><br/>`<!-- Placeholder: docs/screenshots/07_worker_dashboard.png -->` | Assigned municipal tasks, GPS route navigation, remediation progress logger, and before/after repair photo proof capture. |
| **Municipal Admin Triage Console** | <img src="docs/screenshots/08_admin_dashboard.png" width="260" alt="Admin Dashboard"/><br/>`<!-- Placeholder: docs/screenshots/08_admin_dashboard.png -->` | City-wide hazard telemetry, departmental worker dispatch, status audit trail, and field staff management. |
| **Community Board & Verified Polls** | <img src="docs/screenshots/09_community_board.png" width="260" alt="Community Board"/><br/>`<!-- Placeholder: docs/screenshots/09_community_board.png -->` | Anti-fraud neighbourhood voting, live percentage bars, community announcements, and local micro-job listings. |
| **Realtime Notification Center** | <img src="docs/screenshots/10_notifications.png" width="260" alt="Notification Center"/><br/>`<!-- Placeholder: docs/screenshots/10_notifications.png -->` | Cross-role push notification history, deep-link routing to reports/handovers, and unread badge synchronization. |

### 📸 Recommended Screenshot Capture Specifications
For optimal presentation when taking screenshots:
1. **Device Profile**: 1080x2400 (20:9 aspect ratio), Android 13/14, Dark Mode enabled.
2. **Location Mock**: Thiruvananthapuram (`8.5241° N, 76.9366° E`) with sample hazards plotted on map.
3. **Storage Location**: Save PNG files directly into `docs/screenshots/` matching the filenames listed in the table above.

---

# 🎥 Demo Video

### 🎬 Video Link
```
https://youtube.com/watch?v=YOUR_DEMO_VIDEO_LINK
<!-- Placeholder: Replace with your 2-minute unlisted YouTube or Google Drive video URL -->
```

### ⏱️ 2-Minute Video Structure & Presentation Guide

| Timestamp | Segment | Visual Action | Narration Script Focus |
|:---:|---|---|---|
| **0:00 – 0:25** | **The Crisis** | Quick montage of hazardous roads, broken lights, and citizen frustration filing complaints that disappear into black holes. | *"Urban roads are failing, complaints disappear into bureaucratic black holes, and lost vital documents lead to identity fraud. Current civic apps demand too much effort and offer zero proof."* |
| **0:25 – 0:50** | **Passive SensorWatch & Vision AI** | Mount phone in car/bike holder. Drive over a pothole; SensorWatch detects $>2.5g$ spike, computes vector magnitude, and seals SHA-256 proof. Then show AI camera steady-lock auto-capturing a hazard. | *"Meet Nivara. With SensorWatch, your phone passively maps road hazards while you drive. Accelerometer spikes trigger cryptographic SHA-256 evidence packages automatically. Or capture hazards with our NVIDIA Llama-3.2-90B Vision AI that steady-locks before shooting."* |
| **0:50 – 1:15** | **Voice Assistant & Proximity L&F** | Open Voice Assistant; speak in Malayalam/Hindi. Text appears in interactive box with auto-detected category chips. Switch to Lost & Found dynamic QR pass & PIN handshake. | *"Voice reporting supports continuous dictation in Malayalam, Hindi, and English with instant slot extraction. And for Lost & Found, our PostGIS proximity engine pairs documents with secure dynamic QR and PIN handshakes."* |
| **1:15 – 1:40** | **3-Way Closed-Loop Dispatch** | Admin dashboard assigns the report to a field worker. Switch to Worker Mode; worker logs note and uploads after-repair photo proof. Citizen receives instant notification and confirms resolution. | *"Nivara closes the loop. Municipal admins dispatch field crews with one tap. Workers upload photographic remediation proof, and citizens verify the fix before it's officially marked resolved."* |
| **1:40 – 2:00** | **Impact & Vision** | Fast fly-over of live Ola Maps civic dashboard, community polls, and offline pending sync. Call to action. | *"Real proof. Zero friction. Total accountability. Nivara turns passive commuters into active guardians. Your City. Your Proof. Your Voice."* |

---

# 📦 APK Download

The production-ready, signed release APK is built and hosted directly on GitHub Releases:

🔗 **[Download Nivara v1.0.60 Release APK (Latest)](https://github.com/adithyen/Nivara-AppSprint-2026/releases/tag/v1.0.60)**

```
Release Version : 1.0.60 (Build 60)
Artifact Name   : app-release.apk
File Size       : ~105.9 MB
Target Platform : Android 7.0+ (API Level 24 to 34)
Architecture    : arm64-v8a, armeabi-v7a, x86_64
Verification    : Fully signed, tree-shaken release build with zero analyzer warnings
```

### Installation Steps:
1. Download `app-release.apk` from the GitHub Release link on your Android device.
2. Tap the downloaded file in your Notification Drawer or Downloads folder.
3. If prompted, allow *"Install from unknown sources"* for your browser or file manager.
4. Launch **Nivara** and grant Location, Camera, and Microphone permissions when requested.

---

# 🛠️ Tech Stack

```
┌────────────────────────────────────────────────────────────────────────┐
│                        NIVARA CLIENT (FLUTTER)                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │  Riverpod 3.4.2  │  │  GoRouter 17.4   │  │  SensorWatch Engine  │  │
│  │ (Reactive State) │  │(Declarative Nav) │  │  (50Hz Accelerometer)│  │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │   MapLibre GL    │  │ Speech_To_Text   │  │ Mobile Scanner + QR  │  │
│  │ (Ola Vector/Dark)│  │ (Multi-Lingual)  │  │ (Proximity Handover) │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTPS / WSS
┌───────────────────────────────────▼────────────────────────────────────┐
│                    CLOUD & AI BACKEND ARCHITECTURE                     │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │               Supabase PostgreSQL 15 + PostGIS                   │  │
│  │  • Row Level Security (RLS) across 10+ core tables               │  │
│  │  • SECURITY DEFINER RPCs for atomic cross-user claim handovers   │  │
│  │  • Realtime WebSocket publication engine for instant sync        │  │
│  │  • Database triggers for automated notification dispatch         │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  ┌─────────────────────────────┐  │
│  │        NVIDIA NIM API           │  │     Ola Maps Platform       │  │
│  │  Meta Llama-3.2-90B Vision      │  │  Custom Dark Vector Style   │  │
│  │  (Zero-shot hazard validation)  │  │  Reverse geocoding & routing│  │
│  └─────────────────────────────────┘  └─────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

| Domain | Technology / Library | Version | Usage |
|---|---|---|---|
| **Core Framework** | **Flutter** | `3.x` | Cross-platform native compilation, 60fps UI |
| **Language** | **Dart** | `^3.12.0` | Strong-mode typing, sound null safety |
| **State Management** | **Flutter Riverpod** | `^3.4.2` | Compile-safe reactive state, async notifiers |
| **Routing** | **GoRouter** | `^17.4.0` | Declarative URL routing, role-based guards |
| **Database & Auth** | **Supabase Flutter** | `^2.17.1` | PostgreSQL 15, PostGIS, Auth, Realtime, Storage |
| **Vision AI** | **NVIDIA NIM API** | `Llama-3.2-90B` | Visual hazard categorization & boundary confidence |
| **Speech Engine** | **Speech to Text** | `^7.0.0` | Multi-locale continuous speech recognition |
| **Speech Synthesis** | **Flutter TTS** | `^4.2.2` | Local voice confirmation and audio prompts |
| **Mapping & GIS** | **MapLibre GL** | `^0.26.2` | Vector map rendering, custom styles, spatial pins |
| **Map Tiles & Geo** | **Ola Maps Platform** | `v1 REST` | Dark vector tiles, geocoding, reverse geocoding |
| **Sensors** | **Sensors Plus** | `^6.1.1` | 50Hz linear accelerometer telemetry |
| **Location & GPS** | **Geolocator** | `^13.0.2` | High-accuracy GPS tracking, speed, bearing |
| **Cryptography** | **Crypto** | `^3.0.6` | SHA-256 evidence package hashing |
| **Camera & Scanning**| **Mobile Scanner** | `^6.0.4` | Dynamic QR code scanning for physical handovers |
| **QR Generation** | **QR Flutter** | `^4.1.0` | Cryptographic QR code generation |
| **Notifications** | **Flutter Local Notifications** | `^22.2.0` | Android heads-up notifications & channels |
| **Bluetooth / BLE** | **Flutter Blue Plus** | `^1.35.4` | BLE proximity adapter state inspection |
| **Local Cache** | **Shared Preferences** | `^2.3.5` | Offline queue, cached credentials, user settings |

---

# 🚀 Installation & Local Setup

### Prerequisites
- **Flutter SDK**: `^3.12.0` or higher ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Android Studio / SDK**: Android SDK 34, Android NDK, command-line tools
- **Java Development Kit**: JDK 17 (recommended for Gradle 8+)
- **Git**: Installed and configured

### 1. Clone Repository
```bash
git clone https://github.com/adithyen/Nivara-AppSprint-2026.git
cd Nivara-AppSprint-2026
```

### 2. Configure Environment Variables
Create a `.env` file in the root of the project (refer to `.env.example`):
```bash
cp .env.example .env
```
Fill in your API credentials:
```properties
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here

# Ola Maps API Configuration
OLA_MAPS_API_KEY=your-ola-maps-api-key
OLA_MAPS_PROJECT_ID=your-ola-project-id
OLA_MAPS_DARK_STYLE_URL=https://api.olamaps.io/tiles/vector/v1/styles/Style1-Dark/style.json

# NVIDIA NIM AI Vision API (Meta Llama-3.2-90B Vision Instruct)
NVIDIA_NIM_API_KEY=nvapi-your-key-here
```

### 3. Apply Database Migrations
Run the SQL scripts in order using the **Supabase Dashboard SQL Editor**:
1. `supabase/migrations/0001_init.sql` *(Tables, Enums, PostGIS, Profiles, Reports)*
2. `supabase/migrations/0002_community.sql` *(Community Board, Polls, Posts)*
3. `supabase/migrations/0002_storage.sql` *(Storage Buckets for Evidence Photos)*
4. `supabase/migrations/0003_lf_realtime.sql` *(Lost & Found Realtime Publications)*
5. `supabase/migrations/0004_lf_contact.sql` *(Contact Masking & Direct Contact)*
6. `supabase/migrations/0005_lf_claims.sql` *(Claim Lifecycle & Handover)*
7. `supabase/migrations/0006_lf_handover_verification.sql` *(QR & PIN Handshake)*
8. `supabase/migrations/0006_staff_worker.sql` *(Municipal Staff & Worker Engine)*
9. `supabase/migrations/0007_lf_private_listings.sql` *(Private / Public Listings)*
10. `supabase/migrations/0007_workers_and_applications.sql` *(Worker Dispatch & Applications)*
11. `supabase/migrations/0010_notifications_system.sql` *(Notification System & Triggers)*
12. `supabase/migrations/0011_fix_confirmation_count_trigger.sql` *(Confirmation Triggers)*
13. `supabase/migrations/0012_fix_lf_claim_status_cast.sql` *(Enum Casting & RLS Update)*

### 4. Install Dependencies
```bash
flutter pub get
```

### 5. Verify Code Quality
```bash
dart analyze
```
*(Expected output: `No issues found!`)*

### 6. Run on Connected Device / Emulator
```bash
flutter run
```

### 7. Compile Standalone Release APK
```bash
flutter build apk --release
```
The optimized APK will be generated at `build/app/outputs/flutter-apk/app-release.apk`.

---

# 📂 Project Structure

```
Nivara-AppSprint-2026/
├── android/                        # Android native configurations, manifest, permissions
│   └── app/src/main/
│       ├── AndroidManifest.xml     # Camera, Mic, GPS, Notification, BLE permissions
│       └── kotlin/in/adithyen/nivara/  # Native Ola MapView platform channel
├── assets/                         # Visual assets, branded banners, application icons
├── docs/                           # Documentation, architecture specs, screenshots
│   └── screenshots/                # Showcase imagery for hackathon review
├── lib/
│   ├── main.dart                   # Bootstrap: load .env, init Supabase, init notifications
│   ├── app.dart                    # MaterialApp.router, light/dark themes, locale setup
│   ├── router.dart                 # Declarative GoRouter configuration & role redirect guards
│   │
│   ├── core/                       # Core shared infrastructure
│   │   ├── constants.dart          # Detection thresholds (2.5g), speed deadbands, table keys
│   │   ├── supabase_client.dart    # Centralized Supabase client singleton
│   │   ├── theme.dart              # Curated dark/light theme tokens, typography, glassmorphism
│   │   ├── utils.dart              # Haversine distance, date formatters, geo helpers
│   │   ├── services/
│   │   │   ├── sensor_watch_service.dart   # 50Hz accelerometer telemetry engine
│   │   │   ├── evidence_engine.dart        # SHA-256 tamper-proof evidence builder
│   │   │   ├── location_service.dart       # GPS geolocator wrapper & jitter filter
│   │   │   ├── offline_sync_service.dart   # Resilient offline queue & sync manager
│   │   │   └── ola_maps_service.dart       # Ola Maps REST & reverse geocoding client
│   │   └── widgets/
│   │       ├── bouncy_tap.dart             # Emil Kowalski physical spring interaction widget
│   │       └── glass_container.dart        # Glassmorphic backdrop blur container
│   │
│   ├── models/                     # Strongly-typed immutable domain models
│   │   ├── enums.dart              # 19 Categories, Severities, Roles, Claim Statuses
│   │   ├── report.dart             # Civic hazard aggregate
│   │   ├── evidence_package.dart   # Cryptographic SHA-256 sensor evidence
│   │   ├── lf_item.dart            # Lost & Found listing aggregate
│   │   ├── lf_claim.dart           # Mutual claim & handover verification state
│   │   └── user_profile.dart       # User profile, role, civic XP score
│   │
│   └── features/                   # Modular feature-first architecture
│       ├── auth/                   # Authentication, phone/email login, role provisioning
│       ├── home/                   # Main citizen dashboard, activity feed, civic score card
│       ├── map/                    # Interactive MapLibre civic map & Ola vector styling
│       ├── report/                 # Report form, category grid, AI camera screen
│       ├── voice/                  # Continuous speech voice assistant with live editable box
│       ├── lostfound/              # L&F hub, PostGIS match viewer, dynamic handover pass
│       ├── worker/                 # Field worker task dispatch, progress notes, photo proof
│       ├── admin/                  # Municipal administration, ward triage, staff management
│       ├── community/              # Neighbourhood discussion board, anti-fraud civic polls
│       ├── notifications/          # Real-time notification center & channel listener
│       └── profile/                # User profile, civic achievements, settings, language
│
└── supabase/
    └── migrations/                 # 13 Versioned PostgreSQL schema migrations
```

---

# 🌟 Key Highlights & Engineering Innovations

### 1. Mathematical SensorWatch Shock Algorithm
Rather than simple threshold checking, Nivara implements a multi-stage DSP filter:
$$\text{Linear Acceleration Magnitude } |a| = \sqrt{a_x^2 + a_y^2 + a_z^2}$$
- **Gravity-Isolated**: Telemetry is sourced directly from `userAccelerometerEventStream` where standard Earth gravity ($9.81 m/s^2$) is mathematically eliminated by hardware sensor fusion.
- **Speed Deadband**: GPS speed below $3.0\text{ km/h}$ is locked to $0\text{ km/h}$ to eliminate stationary jitter.
- **Temporal Debounce**: Once a shock $\ge 2.5g$ is detected, a 1,500ms cooldown window prevents duplicate triggers from multiple axles over the same pothole.
- **SHA-256 Tamper-Proof Packaging**: Every sensor shock produces a cryptographically sealed JSON bundle hashed with SHA-256 containing timestamp, coordinate bounding, peak magnitude, and sample variance.

### 2. Physical Steady-Lock Camera Gate
Blurry photos submitted while walking or driving are the primary cause of automated inspection failures. Nivara solves this at the hardware level:
- Integrates phone gyroscope and accelerometer variances in real time.
- Renders an interactive gyroscopic stability ring around the shutter.
- Only fires the camera when phone angular velocity stays below $0.05\text{ rad/s}$ for consecutive frames, guaranteeing razor-sharp imagery for NVIDIA NIM Llama-3.2-90B visual inference.

### 3. Dual-Key Cryptographic Handover Pass
Lost identity credentials require zero-trust physical return protocols:
- Neither user needs to disclose their home address or real phone number.
- Claimant generates a single-use token: `NIVARA-LF-{CLAIM_ID_PREFIX}-{UUID_HASH}` and a synchronized 6-digit numeric PIN.
- Verification executes over a private, scoped Supabase Realtime channel (`handover:{claimId}`).
- When the owner scans the QR or enters the proximity PIN, the claim is atomically transitioned to `COMPLETED` and both listings are resolved across the city database.

### 4. Zero-Warning Production Engineering
- Strict sound null-safety with Dart 3.12.
- **Zero compiler warnings** and **zero analyzer issues** (`dart analyze` clean).
- Complete offline-first optimistic rendering across reports, claims, and community votes.

---

# 🔮 Future Improvements & Scalability

* [ ] **Automated Municipal Drone Dispatch**: Integrate autonomous drone survey APIs to capture aerial photogrammetry of reported flood zones and landslides.
* [ ] **Public Transit & Bus Telemetry**: Partner with municipal transport corporations to install Nivara SensorWatch background daemons on city buses for continuous, whole-city road quality heatmaps.
* [ ] **Web3 Municipal Remediation Bounty Contracts**: Escrow municipal repair funds in transparent smart contracts that disburse payments to certified contractors only upon validated community confirmation.
* [ ] **Offline Bluetooth Mesh Network**: Allow citizens in zero-cellular disaster areas to relay emergency hazard alerts across peer-to-peer device mesh networks.

---

# 📊 Impact & Social Value

| Dimension | Real-World Civic Impact |
|---|---|
| **Road Safety** | Early, autonomous detection of potholes prevents severe two-wheeler road accidents and saves lives. |
| **Digital Inclusion** | Voice-first reporting in native languages (Malayalam, Hindi) enables illiterate, elderly, and rural citizens to voice grievances without digital barriers. |
| **Municipal Efficiency** | Eliminates duplicate reports through spatial clustering; provides field staff with exact GPS coordinates and photographic evidence. |
| **Fraud Prevention** | Instant proximity recovery of Aadhaar and PAN cards stops identity theft and financial fraud before documents can be misused. |
| **Civic Trust & Transparency** | Replaces bureaucratic silence with verified field remediation photos and citizen confirmation gates, restoring faith in local governance. |

---

# 📜 License

This project is open-source and licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.

---

# 🏆 AppSprint Solution Challenge 2026

Built with ❤️ and extreme engineering dedication during **AppSprint Solution Challenge 2026**.

Organized by:
**App Development IG · muLearn LBSITW**

---

<p align="center">
  <b>Nivara — Your City. Your Proof. Your Voice.</b><br/>
  <i>Empowering citizens, honoring field workers, and transforming urban governance.</i>
</p>
