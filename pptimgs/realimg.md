# 📸 Real Screenshot Placement & Capture Guide (`realimg.md`)

This guide specifies the exact real-world in-app screenshots needed across the **Nivara** presentation slides. If you prefer to showcase real mobile interface captures (or if your AI presentation tool works best with mobile mockups), capture the screens following the instructions below.

---

## 📱 Global Recommended Capture Settings
* **Device / Emulator**: Pixel 7 / Pixel 8 or modern Android device (1080x2400 resolution, 20:9 ratio).
* **Theme**: Dark Mode enabled (System Dark / Nivara High-Contrast Dark `#0B0F17`).
* **Coordinates**: Thiruvananthapuram (`8.5241° N, 76.9366° E`) or your local city.
* **Saving Directory**: Save captured PNG files directly into `pptimgs/` with the designated filenames below.

---

## 🖼️ Slide-by-Slide Screenshot Specifications

### Slide 4: Project Objectives & Scope
* **Filename**: `pptimgs/real_slide_04_home_overview.png`
* **Screen Route**: `/home` (Home Tab)
* **What to Show**:
  - Top AppBar showing the Nivara brand, Civic Score badge (`240 XP`), and quick notification bell.
  - Active quick-action cards: *Report Hazard*, *SensorWatch Passive Guard*, and *Lost & Found Proximity*.
  - Recent live activity feed displaying real-time city updates.
* **Why it matters**: Demonstrates the unified citizen dashboard where all project objectives converge into one friction-free hub.

---

### Slide 7: Continuous Multilingual Voice Assistant
* **Filename**: `pptimgs/real_slide_07_voice_assistant_sheet.png`
* **Screen Route**: Bottom Sheet opened from Floating Mic Button on Home or Pulse tab.
* **What to Show**:
  - Glowing sound visualizer orb actively pulsing.
  - **Live Editable Transcript Box** showing spoken regional text (e.g. Malayalam: `"റോഡിൽ വലിയൊരു കുഴിയുണ്ട്, വെള്ളം കെട്ടിക്കിടക്കുന്നു"` or Hindi: `"सड़क पर बहुत बड़ा गड्ढा है और पानी भरा हुआ है"`).
  - Auto-extracted slot chips below the transcript:
    - `[ 🕳️ POTHOLE ]`
    - `[ ⚠️ HIGH SEVERITY ]`
    - `[ 📍 Near City Metro ]`
  - Action buttons: *1-Tap Submit* and *Open in Form*.
* **Why it matters**: Visually proves zero-typing, continuous multilingual voice recognition and automatic slot extraction.

---

### Slide 9: Proximity Lost & Found Network & Dual-Key Handover
* **Filename**: `pptimgs/real_slide_09_handover_pass_qr_pin.png`
* **Screen Route**: `/lostfound/detail` $\rightarrow$ Tap **"Generate Handover Pass"**
* **What to Show**:
  - The dynamic cryptographic **Handover Pass**.
  - High-contrast scannable QR Code (`NIVARA-LF-xxxx`).
  - Large bold **6-Digit Verification PIN** (e.g., `8 4 9 2 1 0`).
  - Ownership Transparency Card: *"Listing created by: Sarah M. (Claimant)"* with security shield icon.
  - Real-time peer connection status: *"Waiting for Finder verification..."*.
* **Why it matters**: Shows the exact dual-key cryptographic handshake that prevents fraud and protects citizen identity during item recovery.

---

### Slide 10: Closed-Loop Municipal Governance & Worker Remediation
* **Filename**: `pptimgs/real_slide_10_worker_dashboard_proof.png`
* **Screen Route**: `/worker` (Municipal Field Worker Shell)
* **What to Show**:
  - Field Worker Task Queue sorted by proximity and departmental urgency.
  - An expanded active task (e.g., *"Open Drain & Manhole Repair — Ward 14"*).
  - Remediation Progress Checklist with on-site worker notes.
  - Split before/after photo attachment card showing the uploaded repair proof photo.
  - Green button: *"Mark Remediation Completed & Submit for Citizen Confirmation"*.
* **Why it matters**: Demonstrates the missing link in modern governance: field staff accountability backed by physical photographic evidence.

---

### Slide 11: Pulse Tab, Live Ola Maps & Community Board
* **Filename**: `pptimgs/real_slide_11_pulse_and_olamaps.png`
* **Screen Route**: `/pulse` (Pulse Tab) & `/map` (Civic Map Tab)
* **What to Show**:
  - **Option A (Pulse Tab with Live GPS Auto-Reload)**:
    - Neighborhood live status counter cards (Active Hazards: `14`, Resolved Today: `6`, Field Workers Active: `8`).
    - Turn-on-location prompt card if GPS was off, auto-refreshing live metrics immediately upon GPS activation.
  - **Option B (Ola Maps Dark Vector View)**:
    - High-performance dark vector map tiles.
    - Category-coded neon pins (Potholes in amber, sewage in purple, open hazards in red).
    - Bottom preview sheet showing hazard title, distance (e.g. `240 m away`), and verification status.
* **Why it matters**: Shows hyper-local awareness, real-time spatial telemetry, and dynamic map rendering via Ola Maps vector engine.

---

### Slide 12: Technology Stack & Hardware Biometric Security
* **Filename**: `pptimgs/real_slide_12_biometric_lock_screen.png`
* **Screen Route**: App Launch / App Resume with Biometric Lock Enabled
* **What to Show**:
  - The sleek, high-security **Nivara Biometric Lock Shield**.
  - System fingerprint / face recognition prompt overlay.
  - Fallback button: *"Use Device PIN / Pattern"*.
  - Dark glassmorphic background with subtitle: *"Nivara is locked for your security"*.
* **Why it matters**: Proves enterprise-grade hardware biometric security protecting sensitive municipal dispatch logs and citizen identity claims.

---

### Slide 13: Accessibility, Taste & Regional Inclusivity
* **Filename**: `pptimgs/real_slide_13_language_accessibility.png`
* **Screen Route**: `/settings/language` or `/settings/accessibility`
* **What to Show**:
  - Interactive language switcher showing instant one-tap switching between **English**, **हिंदी (Hindi)**, and **മലയാളം (Malayalam)**.
  - High-contrast WCAG AAA dark interface with luminous neon highlights.
  - Accessibility settings: Text-to-Speech (TTS) voice readout toggle, dynamic font scaling preview, and haptic feedback toggles.
* **Why it matters**: Highlights that Nivara is built from day one for every Indian citizen, regardless of tech literacy or visual abilities.

---

## 📋 Summary Table of All Presentation Assets

| Slide # | Slide Topic | Primary Visual in `pptimgs/` | Real Screenshot Reference in `realimg.md` |
|:---:|---|---|---|
| **Slide 1** | Title & Overview | `01_hero_civic_network.png` *(AI 3D Hero)* | App Icon / Banner (`assets/banner.jpeg`) |
| **Slide 2** | The Urban Crisis | `02_urban_crisis_infographic.png` *(Editorial Infographic)* | Photo montage of Indian road potholes |
| **Slide 3** | The Nivara Solution | `03_solution_overview.png` *(3 Pillars Diagram)* | 3-in-1 app montage |
| **Slide 4** | Project Objectives | `03_solution_overview.png` *(or real)* | `real_slide_04_home_overview.png` |
| **Slide 5** | System Architecture | `05_system_architecture.png` *(4-Tier Architectural Diagram)* | Architecture flowchart |
| **Slide 6** | SensorWatch Telemetry | `06_sensorwatch_telemetry.png` *(50Hz Waveform & SHA-256)* | Live SensorWatch screen with 50Hz readout |
| **Slide 7** | Multilingual Voice AI | `03_solution_overview.png` *(Voice Pillar)* | `real_slide_07_voice_assistant_sheet.png` |
| **Slide 8** | Steady-Lock Vision AI | `08_steady_lock_vision_ai.png` *(HUD Gyro Camera)* | Live Vision AI Camera Viewfinder |
| **Slide 9** | Proximity Lost & Found | `01_hero_civic_network.png` *(Security Shield)* | `real_slide_09_handover_pass_qr_pin.png` |
| **Slide 10** | Closed-Loop Governance | `03_solution_overview.png` *(Pillar 3: Worker)* | `real_slide_10_worker_dashboard_proof.png` |
| **Slide 11** | Pulse Tab & Ola Maps | `01_hero_civic_network.png` *(Map Radar)* | `real_slide_11_pulse_and_olamaps.png` |
| **Slide 12** | Tech Stack & Security | `05_system_architecture.png` | `real_slide_12_biometric_lock_screen.png` |
| **Slide 13** | Accessibility & Taste | `03_solution_overview.png` *(Multilingual)* | `real_slide_13_language_accessibility.png` |
| **Slide 14** | Future Roadmap & Conclusion| `01_hero_civic_network.png` *(Futuristic City)* | Final Team / APK QR code slide |
