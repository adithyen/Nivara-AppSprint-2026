---
name: impeccable
description: >-
  Applies the Impeccable Engineering & Design Standards across projects.
  Enforces 2026-level state-of-the-art UI/UX aesthetics (glassmorphism, micro-animations,
  modern dark mode, cohesive typography), robust software architecture, defensive error
  handling, offline-first reliability, zero-warning quality gates, and automated verification.
---

# Impeccable Engineering & Design Standards (2026 Edition)

The **IMPECCABLE** skill establishes a high-craftsmanship standard for building software that wows users visually while maintaining flawless architectural integrity, resiliency, and performance.

---

## The 4 Pillars of Impeccability

```
   ┌─────────────────────────────────────────────────────────────┐
   │                     IMPECCABLE STANDARDS                    │
   ├──────────────┬──────────────┬──────────────┬────────────────┤
   │  Aesthetics  │ Architecture │  Resilience  │ Quality Gates  │
   │  & 2026 UX   │   & Purity   │   & Offline  │ & Zero Defects │
   └──────────────┴──────────────┴──────────────┴────────────────┘
```

---

## 1. Aesthetic Excellence & 2026 UI/UX Design

Never produce plain, bland, or "year 2000 MVP" interfaces. Treat every screen like a flagship consumer product.

### Design Principles:
1. **Glassmorphism & Depth**:
   - Use multi-layered dark themes (e.g., `#090D12` base, `#131A22` glass panels with `BackdropFilter(18-20px blur)`).
   - Add subtle translucent glowing borders (`color.withValues(alpha: 0.15 - 0.5)`).
   - Use soft elevation drop shadows for floating panels and FABs.
2. **Dynamic Accents & Palettes**:
   - Avoid standard primary colors. Use curated neon/emerald (`#00E676`), electric cyan (`#00B0FF`), amber warning (`#FFB300`), and crimson alert (`#FF5252`).
   - Use linear gradients on primary CTA buttons and status badges.
3. **Fluid Micro-Interactions**:
   - Smooth spring animations for state changes (e.g., bouncing pins, expandable drawers, pulsing status chips).
   - Instant visual feedback on touch/drag gestures.
4. **Cognitive Clarity in User Flows**:
   - Break complex or multi-question forms into clean, progressive steps (e.g., dedicated searchable category selector that transitions immediately to the details form).
   - Always display clear breadcrumb badges with `(Change)` buttons for pre-selected items.

---

## 2. Architectural Purity & Code Hygiene

1. **Separation of Concerns**:
   - Keep UI views declarative and thin.
   - Encapsulate business logic, database queries, and REST/SDK APIs into dedicated, singleton services (e.g., `LocationService`, `OfflineQueueService`, `OlaMapsService`).
2. **Platform & Native Bridges**:
   - For native SDK integration (Android `.aar` / iOS `.framework`), use clean `PlatformView` wrappers and MethodChannels with strongly-typed arguments.
   - Provide graceful fallback mechanisms if native dependencies or network conditions are unavailable.
3. **Dead Code Elimination**:
   - Regularly purge unused imports, dead variables, unreachable code, and debug print spam.

---

## 3. Offline-First & Realtime Resilience

1. **Optimistic & Offline Persistence**:
   - When network calls fail or device is offline, gracefully enqueue actions to local storage (e.g., `SharedPreferences` + local file caching).
   - Automatically drain and retry queued submissions when connectivity resumes.
2. **Defensive Data Handling**:
   - Guard against null fields, malformed API responses, and database schema drifts.
   - Use safe parsing blocks (`fromMap` / `fromJson`) so a single corrupted record never crashes an entire list or map view.

---

## 4. Quality Gates & Release Discipline

1. **Zero-Warning Linter Rule**:
   - Run `flutter analyze` (or project equivalent) before every build.
   - Code must pass with **0 errors and 0 warnings**.
2. **Rigorous Build Verification**:
   - Build release packages (`flutter build apk --release`, `npm run build`, etc.) to verify all native dependencies, Gradle configs, and assets link properly.
3. **Atomic Semantic Versioning & Rollbacks**:
   - Strictly increment version numbers (`version: 1.0.X+X`).
   - Tag every verified release with `git tag -a v1.0.X -m "..."` and push to GitHub so clean rollbacks (`git reset --hard v1.0.X`) are always possible.
4. **Walkthrough Documentation**:
   - Maintain a comprehensive `walkthrough.md` artifact summarizing visual changes, technical additions, and verification steps.

---

## How to Trigger & Use IMPECCABLE

You can activate this skill whenever you want to:
- **Redesign UI/UX**: Transform basic screens into sleek 2026-level glassmorphic interfaces.
- **Audit & Polish Codebase**: Run zero-warning quality passes, fix memory leaks, and optimize responsiveness.
- **Prepare a Flagship Release**: Execute end-to-end verification, create tagged checkpoints, and assemble production bundles.

Prompt examples:
- *"Apply IMPECCABLE standards to redesign the home screen."*
- *"Audit the project using IMPECCABLE quality gates."*
- *"Build and release the next version following IMPECCABLE guidelines."*
