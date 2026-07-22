# Tasks: #49 — Text Component Library

> Parent Issue: #49
> Priority: high
> Estimated: 1–2 weeks

---

## Overview

Implement a reusable Text Component Library for 3D environmental text. Create `TextVariantData` Resource class, `TextComponentBase.gd` extending `LoFiText3D` with state-driven API, 4 component scripts + `.tscn` scenes (RainText, NeonSign, PuddleText, LamppostText), and 12 `.tres` variant files. Reference DESIGN doc at `docs/DESIGN/49-text-component-library.md`.

---

## Phase 1: Core Infrastructure (P0)

| Step | File | Change | Dependencies | Priority |
|------|------|--------|-------------|----------|
| 1.1 | `gdscripts/text_variant_data.gd` | **New** — `TextVariantData` Resource class with 7 exported fields (text, emissive_color, emissive_strength, pixel_factor, color_bits, scanline_intensity, fragment_text) | None | P0 |
| 1.2 | `gdscripts/text_component_base.gd` | **New** — `TextComponentBase` extending `res://gdscripts/lo_fi_text_3d.gd` with `set_state_tier()`, `set_tone()`, `set_text_variant()` API, signal wiring to StateSystem/NarrativeManager | 1.1 | P0 |
| 1.3 | `scenes/components/` | **New** — Directory for all component scenes | None | P0 |
| 1.4 | Regression: existing tests still pass | Verify `test_lo_fi_text_3d.gd` and `test_narrative_architecture.gd` not broken | 1.1, 1.2 | P0 |

---

## Phase 2: Component Scripts (P0)

| Step | File | Change | Dependencies | Priority |
|------|------|--------|-------------|----------|
| 2.1 | `gdscripts/rain_text.gd` | **New** — `RainText` extending `TextComponentBase`, hope-axis mapping, despair deep layer (fragmentation) | 1.2 | P0 |
| 2.2 | `gdscripts/neon_sign.gd` | **New** — `NeonSign` extending `TextComponentBase`, conviction-axis mapping, low-conviction flicker deep layer | 1.2 | P0 |
| 2.3 | `gdscripts/puddle_text.gd` | **New** — `PuddleText` extending `TextComponentBase`, hope-axis mapping, despair unreadable deep layer | 1.2 | P0 |
| 2.4 | `gdscripts/lamppost_text.gd` | **New** — `LamppostText` extending `TextComponentBase`, will-axis mapping, low-will color shift deep layer | 1.2 | P0 |

---

## Phase 3: Scene Files & Resources (P1)

| Step | File | Change | Dependencies | Priority |
|------|------|--------|-------------|----------|
| 3.1 | `scenes/components/rain_text.tscn` | **New** — Label3D scene with RainText script, billboard enabled, cool blue emissive defaults | 2.1 | P1 |
| 3.2 | `scenes/components/neon_sign.tscn` | **New** — Label3D scene with NeonSign script, billboard enabled, warm amber emissive defaults (strength 2.0) | 2.2 | P1 |
| 3.3 | `scenes/components/puddle_text.tscn` | **New** — Label3D scene with PuddleText script, flat/angled orientation, muted reflection defaults | 2.3 | P1 |
| 3.4 | `scenes/components/lamppost_text.tscn` | **New** — Label3D scene with LamppostText script, billboard enabled, warm yellow emissive defaults | 2.4 | P1 |
| 3.5 | `scenes/components/variants/` | **New** — Directory for `.tres` variant files | None | P1 |
| 3.6 | Create 12 `.tres` variant files | 3 tiers × 4 components: shallow/middle/deep for rain/neon/puddle/lamppost | 1.1 | P1 |

---

## Phase 4: Tests & Validation (P1)

| Step | File | Change | Dependencies | Priority |
|------|------|--------|-------------|----------|
| 4.1 | `tests/test_text_component_library.gd` | **New** — Tests for tier→variant mapping, signal wiring, tone overrides, fragment text switching, graceful degradation | 1.2 | P1 |
| 4.2 | Variant data edge cases | Verify empty array fallback, out-of-bounds clamping, empty fragment_text behavior | 4.1 | P1 |
| 4.3 | Deep layer verification (AC3) | Verify fragment_text activates at extreme state values for all 4 components | 4.1 | P1 |

---

## Dependency Graph

```
Phase 1 ──────────────────
├─ 1.1 (TextVariantData) ───────────┐
├─ 1.2 (TextComponentBase) ←── 1.1 ─┤
├─ 1.3 (components dir)              │
└─ 1.4 (regression) ──── 1.1, 1.2 ──┤
                                     │
Phase 2 ──────────────────           │
├─ 2.1 (RainText)    ←── 1.2        │
├─ 2.2 (NeonSign)    ←── 1.2        │
├─ 2.3 (PuddleText)  ←── 1.2        │
└─ 2.4 (LamppostText) ←── 1.2       │
                                     │
Phase 3 ──────────────────           │
├─ 3.1 (rain_text.tscn)   ←── 2.1   │
├─ 3.2 (neon_sign.tscn)   ←── 2.2   │
├─ 3.3 (puddle_text.tscn) ←── 2.3   │
├─ 3.4 (lamppost_text.tscn) ←── 2.4 │
├─ 3.5 (variants dir)                │
└─ 3.6 (12 .tres files)     ←── 1.1 │
                                     │
Phase 4 ──────────────────           │
├─ 4.1 (test script) ←── 1.2        │
├─ 4.2 (edge cases)   ←── 4.1       │
└─ 4.3 (AC3 verify)   ←── 4.1       │
                                     │
All done ────────────────────────────┘
```

---

## Milestones

| Milestone | Tasks | Done When |
|-----------|-------|-----------|
| M1 — Core infrastructure | 1.1, 1.2, 1.3 | `TextComponentBase` compiles and maps tiers |
| M2 — All component scripts | 2.1–2.4 | All 4 scripts pass GDScript parser |
| M3 — All scenes + resources | 3.1–3.6 | All 4 `.tscn` files + 12 `.tres` files created |
| M4 — Release candidate | 4.1–4.3 | All tests pass in `godot --headless` |

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| `Array[Resource]` export buggy in Godot 4.7 | Medium | Low | Fallback to exported `Dictionary` with same API surface |
| `.tres` files not tracked properly in VCS | Medium | Low | `.tres` is plain text; verify with `git diff` on first commit |
| Scene refactoring scope creep (6 scenes) | High | Medium | Explicitly defer to Issues #55, #58, #59; this issue creates the library only |
| Fragment text balance (too aggressive) | Low | Medium | Keep `fragment_text ≤ 80%` of original length per PRD failure path |

---

## Summary: Changed Files

| File | Change Type | Est. Lines |
|------|-------------|-----------|
| `gdscripts/text_variant_data.gd` | **New** | +25 |
| `gdscripts/text_component_base.gd` | **New** | +120 |
| `gdscripts/rain_text.gd` | **New** | +25 |
| `gdscripts/neon_sign.gd` | **New** | +25 |
| `gdscripts/puddle_text.gd` | **New** | +25 |
| `gdscripts/lamppost_text.gd` | **New** | +25 |
| `scenes/components/rain_text.tscn` | **New** | +30 |
| `scenes/components/neon_sign.tscn` | **New** | +30 |
| `scenes/components/puddle_text.tscn` | **New** | +30 |
| `scenes/components/lamppost_text.tscn` | **New** | +30 |
| `scenes/components/variants/rain_text_shallow.tres` | **New** | +10 |
| `scenes/components/variants/rain_text_middle.tres` | **New** | +10 |
| `scenes/components/variants/rain_text_deep.tres` | **New** | +10 |
| `scenes/components/variants/neon_sign_shallow.tres` | **New** | +10 |
| `scenes/components/variants/neon_sign_middle.tres` | **New** | +10 |
| `scenes/components/variants/neon_sign_deep.tres` | **New** | +10 |
| `scenes/components/variants/puddle_text_shallow.tres` | **New** | +10 |
| `scenes/components/variants/puddle_text_middle.tres` | **New** | +10 |
| `scenes/components/variants/puddle_text_deep.tres` | **New** | +10 |
| `scenes/components/variants/lamppost_text_shallow.tres` | **New** | +10 |
| `scenes/components/variants/lamppost_text_middle.tres` | **New** | +10 |
| `scenes/components/variants/lamppost_text_deep.tres` | **New** | +10 |
| `tests/test_text_component_library.gd` | **New** | +150 |
| `docs/DESIGN/49-text-component-library.md` | **New** | +250 |
| `docs/TASKS/49-text-component-library.md` | **New** | +120 |
