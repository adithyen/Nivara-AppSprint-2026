---
name: emil-motion
description: >-
  Implements Emil Kowalski-inspired motion design principles: physical spring dynamics,
  tactile micro-interactions, spatial continuity, layout transitions, staggered entrances,
  and organic gesture feedback to make apps feel physical, alive, and responsive.
---

# Emil Kowalski Motion Design System (Spring & Tactile Physics)

This skill brings world-class interaction design and physical motion principles into the product. Animations should never feel like arbitrary timers (`linear`, generic `easeIn`); they must behave like physical objects with mass, momentum, and elasticity.

---

## 1. Core Motion Physics Principles

1. **Spring-Based Natural Transitions**:
   - Use organic spring curves with slight overshoot (`Curves.easeOutBack`, `Curves.easeOutCubic`, `Curves.fastOutSlowIn`).
   - Duration rules:
     - Micro-interactions (taps, toggles, icon flips): `120ms - 200ms`
     - Card expansions & sheet slide-ins: `280ms - 380ms`
     - Screen page routes & spatial transitions: `320ms - 450ms`

2. **Tactile Tap Physics (Scale Dips & Haptics)**:
   - On tap down (`onPointerDown` / `onTapDown`): Scale down to `0.96 - 0.97` with `HapticFeedback.selectionClick()`.
   - On release: Snap back to `1.0` with natural spring bounce.
   - Applies to: primary action buttons, grid tiles, landmark pills, map pins, and cards.

3. **Spatial Continuity & Shared Layouts**:
   - Elements don't pop in out of nowhere; they originate from where the user triggered them.
   - Expanding cards should smoothly interpolate size, corner radius, and opacity.

4. **Staggered Orchestrated Entrances**:
   - List items and dashboard grids animate in with a micro-stagger (`25ms - 40ms` interval delay).
   - Combine vertical slide (`Offset(0, 16) -> Offset.zero`) + alpha fade (`0.0 -> 1.0`).

5. **Gesture-Driven Elasticity**:
   - Bottom sheets and floating modals must follow finger velocity.
   - Dismissible items have rubber-band resistance when pulled beyond boundaries.

---

## 2. Motion Component Recipes

- **`BouncyTapWrapper`**: Wraps any widget to give it a physical spring scale dip + haptic pulse on touch.
- **`StaggeredFadeSlide`**: Smooth staggered entrance for lists and grids.
- **`PulsingGlowBadge`**: Continuous subtle ambient breathing effect for active indicators (e.g., live sensor watch, realtime map pins).
- **`AnimatedPinDrop`**: Dynamic elevation bounce and shadow contraction when dragging map pickers.
