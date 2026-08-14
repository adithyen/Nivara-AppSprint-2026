---
name: taste
description: >-
  Cultivates exceptional visual taste, sophisticated typography, visual hierarchy,
  color refinement, spatial rhythm, and editorial restraint. Use to elevate UI/UX
  from generic functional layouts to world-class, premium, and distinctive design.
---

# Taste & Design Craftsmanship Standard

The **Taste** skill is about intentionality, typographic hierarchy, optical alignment, micro-contrast, and aesthetic discernment. It ensures software feels crafted by world-class product designers rather than built from cookie-cutter component libraries.

---

## 1. Visual Hierarchy & Typographic Rhythm

1. **Typographic Scale & Contrast**:
   - Establish high-contrast typographic pairings (bold display numbers, crisp medium subtitles, subtle low-opacity metadata).
   - Use monospace numbers for live telemetries, coordinates, metrics, and timestamps (`fontFamily: 'monospace'` / tabular figures) to eliminate jitter.
2. **Whitespace & Spatial Harmony**:
   - Use consistent 4px/8px baseline grid rules: `8, 12, 16, 20, 24, 32, 48`.
   - Generous breathing room around focal points; tight, disciplined grouping for related data units.
3. **Optical Balance**:
   - Align elements to their optical center rather than purely mathematical bounds (e.g., iconography offsets, text baseline alignment).

---

## 2. Color Mastery & Surface Architecture

1. **Curated Non-Generic Palettes**:
   - Never use default saturated primaries (`#0000FF`, `#FF0000`).
   - Use curated dark surfaces: `#080C10` (deep canvas), `#10161E` (glass cards), `#16202C` (elevated controls).
   - Dynamic accent lights: Neon Emerald (`#00E676`), Cyber Cyan (`#00B0FF`), Amber Pulse (`#FFB300`), Electric Crimson (`#FF5252`).
2. **Layered Depth & Translucency**:
   - Multi-layer glassmorphic containers with 16-24px Gaussian blur (`BackdropFilter`).
   - Hairline borders with gradient opacity (`0.12 - 0.4`) that define edges without harsh outlines.
   - Diffuse, colored glow shadows (`blurRadius: 16-24`, `spreadRadius: 1-2`) for key interactive targets.

---

## 3. Component Elegance

1. **Card Architecture**:
   - Large modern border radii (`18px - 26px`).
   - Integrated status badges with glowing indicator dots and muted background pills.
2. **Inputs & Controls**:
   - Floating search capsules with icon anchors, instant clearing, and frosted dropdowns.
   - Segmented buttons and pills with smooth pill-sliding selection.
3. **Editorial Density**:
   - Present complex data clearly without overwhelming the user.
   - Use progressive disclosure: show the immediate actionable details first, provide one-tap depth for advanced inspectors.
