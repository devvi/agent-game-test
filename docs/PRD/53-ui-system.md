# Research: UI System — Hopper-Style Minimal UI

> Parent Issue: #53
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project currently has these UI-adjacent components:

1. **DialogueDisplay3D** (`gdscripts/dialogue_display_3d.gd`) — A `Node3D` controller that manages LoFiText3D nodes for speaker labels, dialogue text, and up to 4 choice labels in 3D world space. Supports keyboard navigation (arrow up/down), emissive focus highlighting (amber), tweened fade-out, and a reveal delay before choices appear.

2. **Main entry script** (`gdscripts/main.gd`) — Has dialogue input handling wired (F9 triggers test dialogue, Arrow Up/Down for choice navigation, Enter/Space for selection, 1–4 for direct pick). Has a `world_label` (Label3D) showing a debug status string `"Hope: 100  Despair: 0"`.

3. **StateSystem** (`gdscripts/state_system.gd`) — Manages `hope_despair` (bipolar -10 to +10), `conviction` (0–10), `will` (0–10). Emits `state_changed(state: Dictionary)`.

4. **LoFiText3D** (`gdscripts/lo_fi_text_3d.gd`) — Extends Label3D with lo-fi shader parameters (pixel_factor, color_bits, scanline_intensity, emissive_color, emissive_strength). Billboard mode available.

5. **DialoguePanel** (`scenes/dialogue/dialogue_panel.tscn`) — 2D CanvasLayer-based Panel with SpeakerLabel, RichTextLabel, and ChoiceContainer (VBoxContainer). Used as fallback/debug view.

**What does NOT exist yet:**

- **No status bar** — No persistent hope/despair indicator visible during gameplay. The `world_label` is a debug-only Label3D, not a styled UI element. Players have no way to see their emotional state without checking a debug readout.
- **No responsive layout** — DialogueDisplay3D choice labels use fixed `choice_spacing = 0.25` (world units). Font size is not scaled relative to viewport. At different aspect ratios (16:9, 16:10, 21:9), text may clip, overlap, or become unreadably small/large.
- **No Hopper styling** — The debug status bar has no visual styling. There is no thin-bar metaphor, no color-coded hope/despair gradient, and no diegetic integration.
- **No aspect-ratio-aware 3D text sizing** — Label3D `pixel_size` and font size are static. At 1920×1080 the text reads well, but at 2560×1440 or 1920×1200 the same settings may cause clipping or readability issues.
- **No screen-edge awareness** — The 3D dialogue display has no mechanism to reposition itself if the camera moves such that text would project off-screen.

### Expected Behavior

The UI system should provide:

1. **3D floating choice labels** (AC1) — Choice list appears as 3D floating labels vertically arranged above the dialogue text. Uses existing DialogueDisplay3D infrastructure with improved positioning to ensure choices float visually above (not below) the dialogue text in world space.

2. **Hope/despair status bar** (AC2) — A thin, non-intrusive bar at the bottom edge of the screen showing the player's current hope/despair state. Should use a visual metaphor (color gradient, fill level, or minimal text indicator) consistent with the Hopper aesthetic.

3. **Responsive text layout** (AC3) — No overlapping or clipped text at any supported aspect ratio. Font size, choice spacing, and status bar positioning adapt to viewport dimensions automatically.

### User Scenarios

- **Scenario A (Dialogue with choices):** Player approaches the Bartender NPC. Dialogue text appears as a 3D billboarded LoFiText3D label above the NPC. Three choices float below as individual LoFiText3D labels, with the first highlighted in amber. Player navigates with Arrow Down and selects with Enter. The choice labels are vertically spaced far enough apart that even at 21:9 ultra-wide, they don't overlap with each other or the dialogue text.

- **Scenario B (Status awareness):** Player has been making choices that increase despair. At the bottom of the screen, a thin bar (approximately 4px tall in screen space) shows a gradient from amber (hope) at the left to dark blue (despair) at the right. The bar's fill level shifts rightward as despair increases — a subtle, non-intrusive indicator that the player can check at a glance.

- **Scenario C (Aspect ratio change):** Player resizes the window from 1920×1080 to 2560×1440. The status bar's screen-edge anchor keeps it at the bottom center. The 3D choice labels, when projected to screen space, maintain consistent relative sizing — effectively visible but not dominating the view. No text is clipped or overlapping.

- **Frequency:** Status bar is persistent (every frame). Choice list appears during every NPC interaction (5+ NPCs across 7+ scenes).

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built feature-by-feature: first the 3D text rendering system (Issue #44), then the narrative architecture (Issue #45), dialogue engine (Issue #46), GameState (Issue #47), text component library (Issue #49), dialogue runtime + visual (Issue #52). The UI system was intentionally deferred because:

1. **Dialogue display came first** — Issue #52 delivered the 3D dialogue display (DialogueDisplay3D) as the primary visual layer for NPC conversations. The UI system extends this with a status bar and responsive layout, but the choice-list mechanics already exist.

2. **Status bar requires GameState integration** — Issue #47 (GameState System) needed to be stable before a status bar could meaningfully display hope/despair values. The initial `world_label` in `main.gd` was a stopgap.

3. **Aspect ratio testing requires a working 3D scene** — Without a full 3D scene (streets, interiors), testing responsive 3D text layout was premature. Now that scenes exist (Issues #55, #58), responsive layout can be tested in-context.

### Why Change Now?

1. **Player feedback loop closure** — Without a status bar, the player has no real-time awareness of their emotional state. The entire game loop (choices → state change → world feedback) loses impact because the middle step (state change awareness) is invisible.

2. **Dialogue system completeness** — Issue #52 delivered 3D dialogue display with choice navigation. The UI system adds the missing HUD layer and layout hardening needed for AC compliance.

3. **Scene construction in progress** — Scenes are being built (Issues #55, #58, #59) that feature NPC interactions. The UI system must be ready to overlay status information consistently across all scenes.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static typing) |
| Renderer | `forward_plus` with Glow pass enabled |
| Resolution | 1920×1080, Allow HiDPI |
| Theme | Edward Hopper urban night — warm/amber on dark/cool backgrounds |
| Text rendering | LoFiText3D (Label3D + lo-fi shader) |
| Dialogue display | DialogueDisplay3D (Node3D) with signal-driven updates |
| Status system | StateSystem (hope_despair -10..+10, conviction 0..10, will 0..10) |
| Choice display | Up to 4 choice labels, emissive focus highlight |
| Input | Keyboard-only (Arrow Up/Down, Enter/Space, 1–4) |
| Platform | macOS / Linux |
| Performance budget | CRPG — no physics/action; ~3-8 text elements + 1 status bar per scene |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/status_bar.gd` | Status Bar Controller | **New** — CanvasLayer-based thin bar showing hope/despair |
| `scenes/ui/status_bar.tscn` | Status Bar Scene | **New** — Scene with Control nodes for the status bar |
| `gdscripts/ui_config.gd` | UI Config Singleton | **New** — Responsive layout parameters accessible from both 2D and 3D |
| `gdscripts/dialogue_display_3d.gd` | 3D Dialogue Display | **Extended** — Add aspect-ratio-aware font scaling, reposition choice labels above dialogue text |
| `gdscripts/main.gd` | Main Entry | **Extended** — Instantiate status bar, connect to StateSystem signals, pass viewport size changes |
| `scenes/main.tscn` | Main Scene | **Extended** — Add StatusBar node (CanvasLayer) |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/state_system.gd` | State System | Must emit `state_changed` with normalized hope_despair values for status bar fill |
| `gdscripts/lo_fi_text_3d.gd` | Lo-Fi 3D Text | May need `auto_font_scale` method exposed for responsive sizing |
| `scenes/dialogue/dialogue_panel.tscn` | 2D Dialogue Panel | Status bar should be visible even when 2D panel is shown (debug mode) |
| `docs/GAME_DESIGN/03-UI.md` | GDD | Should document UI system architecture and status bar design |
| `tests/test_ui_system.gd` (new) | Tests | **New** — Tests for responsive layout calculations, status bar value mapping |

### Data Flow Impact

```
StateSystem.state_changed(state)
    │
    ├──► StatusBar._on_state_changed(state)
    │        │
    │        ├──► compute fill_level from hope_despair (-10..+10 → 0.0..1.0)
    │        ├──► choose color tint (amber→dark blue gradient)
    │        └──► update bar fill width via Control.size.x interpolation
    │
    └──► (existing) NarrativeManager / SceneBase for world feedback

Viewport.size_changed()
    │
    ├──► UIConfig.recalculate()
    │        ├──► compute auto_font_scale_factor from base_resolution / current_resolution
    │        ├──► compute choice_y_spacing from viewport height / expected visible range
    │        └──► store new values as singleton properties
    │
    └──► DialogueDisplay3D
            │
            ├──► on_choices_available(): apply UIConfig.choice_spacing + font_scale
            ├──► on_node_changed(): apply UIConfig.font_scale to dialogue text
            └──► reposition text above choice labels (y-offset)
```

### Documents to Update

- [x] **This output:** `docs/PRD/53-ui-system.md`
- [ ] `docs/DESIGN/53-ui-system.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/03-UI.md` — New GDD chapter for UI system architecture
- [ ] `docs/GAME_DESIGN/INDEX.md` — Update index

---

## 4. Solution Comparison

### Approach A: Hybrid 3D/2D UI — CanvasLayer Status Bar + 3D Dialogue Display (Modified)

**Description:**

Keep the dialogue display in 3D world space (existing DialogueDisplay3D) while adding a **2D CanvasLayer status bar** for the hope/despair indicator. The status bar is a thin Control node anchored to the bottom center of the screen.

**Status Bar Design:**
- A thin `ColorRect` (4–6px effective screen height) running across the bottom ~60% of the screen width
- Left half: amber (hope) with fill level decreasing as despair rises
- Right half: dark blue-gray (despair) with fill level increasing as despair rises
- A slider indicator (bright amber dot) showing the current hope_despair position
- Label3D text above the bar showing "HOPE" and "DESPAIR" labels in lo-fi pixel font
- Anchored to screen bottom via CanvasLayer layout

**Dialogue Display Modifications:**
- Swap choice vertical order: choices float **above** dialogue text (per AC1: "choice list appears as 3D floating labels above dialogue text")
- Apply `UIConfig.auto_font_scale` to all LoFiText3D labels based on viewport size ratio
- Scale `choice_spacing` proportionally to viewport height
- Position DialogueDisplay3D root relative to both NPC origin and camera viewport bounds

**Pros:**
- Status bar uses Godot's proven 2D Control layout system with anchors — handles aspect ratio changes natively
- No camera parenting or frustum math needed for the status bar
- 2D status bar is performant (single Control node, no 3D render passes)
- DialogueDisplay3D stays in 3D space as designed — maintains diegetic feel for conversation text
- CanvasLayer ensures status bar always renders on top of 3D world, never occluded
- Easy to theme with Hopper palette using Godot StyleBox

**Cons:**
- Mix of 2D and 3D rendering contexts — status bar and dialogue text use different fonts/shaders
- Status bar is non-diegetic (floating over the world) — breaks immersion slightly
- Must ensure status bar doesn't overlap with 3D dialogue text when both are visible
- Two sets of styling rules (Control themes vs Label3D shader params)

**Risk:** Low — CanvasLayer HUD is a standard Godot pattern. The mixing concern is mitigated by the status bar being a thin strip at the screen edge, visually distinct from 3D world text.

**Effort:** 3 files (status bar scene + script + UIConfig singleton) + modifications to DialogueDisplay3D ≈ 200 lines

---

### Approach B: Fully Diegetic 3D UI — Camera-Attached Status Bar + 3D Dialogue Display

**Description:**

Place the status bar in 3D world space as a child of the Camera3D node, positioned at the bottom edge of the camera frustum. Use a `ColorRect` in a SubViewport, projected onto a Sprite3D, or use a custom MeshInstance3D with a gradient material.

**Status Bar Design:**
- A flat quad (MeshInstance3D with QuadMesh) positioned at the camera's near-plane bottom edge
- ShaderMaterial with a horizontal gradient: left=amber, right=dark blue
- The gradient's midpoint shifts based on hope_despair value
- Billboard mode disabled — always appears at the same position in the camera view

**Dialogue Display Modifications:**
- Same as Approach A (auto-scaling, order swap)
- Additionally, DialogueDisplay3D root position must account for screen bounds to prevent off-screen projection
- Could use `camera.unproject_position()` to check projected coordinates

**Pros:**
- Fully diegetic — all UI elements exist in 3D space, no 2D overlay break
- Consistent rendering pipeline (all elements use `forward_plus` with LoFi shader)
- Status bar can have lo-fi aesthetic (pixelation, scanlines) matching the rest of the game
- No CanvasLayer ordering concerns — z-sorting is natural

**Cons:**
- Camera parenting is fragile — any camera shake, rotation, or transition breaks the status bar positioning
- Must recalculate frustum-bottom position on every `_process()` if camera moves
- SubViewport or 3D mesh for a gradient bar is over-engineered (more nodes, more draw calls)
- Status bar may clip with 3D world geometry at certain camera angles (e.g., looking up at a tall building)
- Harder to theme and iterate — no StyleBox, no Control properties
- Higher complexity for a simple 2D indicator

**Risk:** Medium-High — camera-child approach is fragile and the 3D status bar can be occluded by world geometry, making it partially invisible at certain angles.

**Effort:** 4 files (3D status bar script + material + scene + UIConfig) + camera integration + DialogueDisplay3D modifications ≈ 300 lines

---

### Approach C: Fully 2D CanvasLayer UI — Status Bar + 2D Choice Overlay

**Description:**

Move both the status bar and choice list into a CanvasLayer overlay. The choice list would be rendered as 2D Control nodes (Labels) positioned over the 3D viewport. The lo-fi aesthetic would be applied as a shader on the CanvasLayer.

**Status Bar Design:**
- Same as Approach A — ColorRect bar anchored to bottom

**Choice List Design:**
- A VBoxContainer with Label nodes, positioned at the center-bottom of the screen (above the status bar)
- Labels styled to match the lo-fi pixel font
- Focus highlight via theme colors
- Same keyboard navigation as 3D version

**Pros:**
- Unified rendering — all UI in 2D, one styling system
- Simplest responsive layout — Control nodes with anchors handle all aspect ratios
- No 3D positioning concerns — no off-screen clipping
- Mouse/click support works for free
- Most performant (no 3D text nodes)

**Cons:**
- **Design contradiction:** The GDD (01-OVERVIEW.md) establishes that text should be in 3D space as diegetic elements. A 2D overlay for dialogue choices contradicts this direction.
- Loses lo-fi 3D text treatment — 2D labels don't get the Label3D pixelation/emissive shader unless duplicated
- Breaking immersion — a floating 2D dialogue panel is a traditional UI approach that the project intentionally avoided
- Does not reuse the existing DialogueDisplay3D implementation (waste of Issue #52 work)
- The game's Hopper aesthetic relies on text being part of the 3D environment

**Risk:** Low-Medium technically, but high from a design consistency perspective.

**Effort:** 2 files (2 scenes + 1 script) + CanvasLayer theming ≈ 150 lines

---

### Comparison Summary

| Dimension | A: Hybrid 3D/2D | B: Full 3D Diegetic | C: Full 2D |
|-----------|-----------------|---------------------|------------|
| Design consistency (GDD) | ★★★★☆ | ★★★★★ | ★★☆☆☆ |
| Implementation ease | ★★★★★ | ★★☆☆☆ | ★★★★☆ |
| Responsive layout | ★★★★★ | ★★★☆☆ | ★★★★★ |
| Reuses existing work | ★★★★★ | ★★★★☆ | ★☆☆☆☆ |
| Performance | ★★★★★ | ★★★★☆ | ★★★★★ |
| Immersion | ★★★★☆ | ★★★★★ | ★★☆☆☆ |
| Maintenance burden | ★★★★☆ | ★★★☆☆ | ★★★★★ |
| Godot 4.7 idiomatic | ★★★★★ | ★★☆☆☆ | ★★★★★ |

### Recommendation

→ **Approach A (Hybrid 3D/2D UI)** because:

1. **Diegetic separation is natural** — Dialogue text floating in 3D space above an NPC is a diegetic element (part of the game world). A status bar at the screen edge is a non-diegetic HUD element. These have different design requirements and should use different rendering paths. The GDD mandates 3D text for **in-world** elements; a status bar is not an in-world element.

2. **CanvasLayer reliability** — Godot's CanvasLayer + Control node system is battle-tested for HUD elements. Anchors and containers handle every aspect ratio automatically. A 3D-camera-child approach (Approach B) would re-implement basic HUD functionality poorly.

3. **Minimal rework of Issue #52** — DialogueDisplay3D already works. The modifications needed (choice order swap, font scaling) are incremental changes, not a rewrite.

4. **Performance proportionality** — A status bar is a single `ColorRect` with a gradient shader → 1 draw call. The 3D dialogue display handles 4–6 LoFiText3D nodes, which is well within budget. Approach B would add unnecessary 3D geometry rendering.

5. **Incremental adoption** — The status bar can be implemented and tested independently of the dialogue system. It only depends on `StateSystem.state_changed` signals.

**Status Bar Visual Design (Hopper-inspired):**
- Thin horizontal bar (4px at 1080p, scaled proportionally)
- Width: ~60% of viewport width, centered
- Background: semi-transparent dark (#1a1a2e with 60% alpha)
- Fill: horizontal gradient — left edge warm amber (#FFB000), right edge cool dark blue (#2A2A4A)
- Indicator: bright amber dot at current hope_despair position
- Labels: "HOPE" in small pixel font above left side, "DESPAIR" above right side
- Fade: bar is always visible but very subtle (low alpha when no state change recently)
- Transitions: smooth tween (0.5s) on fill level changes

**Mitigation for 2D/3D mix:**
- Use the same pixel font (`.fnt` asset) for status bar labels and 3D text
- Use the same color palette (Hopper amber/cool-dark values) in both the 2D theme and 3D LoFiText3D parameters
- Apply a subtle lo-fi overlay as a CanvasLayer shader (optional — only if the 2D text looks too clean compared to 3D text)

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Game start:** Status bar appears at bottom of screen showing neutral position (hope_despair = 0.0). Fill level is centered. Dot is at midpoint.
2. **State change during gameplay:** Player makes a choice that applies `hop_despair: -2`. `state_changed` fires. Status bar animates its fill level and dot position leftward over 0.5 seconds.
3. **Dialogue triggered:** Player presses F9 (test) or interacts with NPC. DialogueDisplay3D shows text and choices. Status bar remains visible but does not overlap dialogue text.
4. **Choice navigation:** Arrow Up/Down cycles through 3D choice labels. Each label is vertically spaced by `UIConfig.choice_spacing` which scales with viewport height. No labels clip at screen edges.
5. **Aspect ratio change:** Player resizes window. `UIConfig.recalculate()` runs. On the next dialogue node, font sizes and choice spacing are updated. Status bar re-anchors automatically.
6. **Dialogue ends:** DialogueDisplay3D fades out. Status bar remains visible.

### Edge Cases

1. **Status bar at extreme values:** hope_despair = -10 (max despair) → fill level fully right (despair side). Dot at far right. hope_despair = +10 (max hope) → fill level fully left. Dot at far left. No visual overflow.
2. **Rapid state changes:** Multiple `state_changed` signals in quick succession (e.g., from a complex effect chain). Status bar should use last-value-wins, not queue animations. A running tween should be killed and a new one started.
3. **Status bar visibility during dialogue:** With 3D dialogue text visible, the status bar should remain below the projected position of the lowest dialogue element. Mitigation: DialogueDisplay3D's Y-offset should push text upward enough that the bottom ~8% of screen space is reserved for the status bar.
4. **Zero choices available:** DialogueRunner still emits `choices_available([])`. DialogueDisplay3D shows ContinuePrompt instead of choice labels. Status bar unaffected.
5. **Window minimized / re-shown:** `size_changed` fires on window restore. `UIConfig.recalculate()` runs and updates responsive parameters. No stale layout.
6. **Very wide aspect ratio (21:9):** Status bar width is clamped to 60% of viewport width, centered. Dialogue choice spacing is calculated from viewport height (not width), so vertical spacing remains comfortable.
7. **Very narrow aspect ratio (4:3):** Font scale factor may need to decrease to avoid clipping. UIConfig should have a minimum font scale floor.

### Failure Paths

1. **StateSystem not available:** Status bar gracefully degrades to neutral position (centered). Logs warning.
2. **UIConfig not initialized:** DialogueDisplay3D falls back to hardcoded default values (current behavior — choice_spacing = 0.25, no font scaling). Not a crash.
3. **Status bar theme resource missing:** If custom StyleBox or font resources fail to load, fall back to default ColorRect with no labels. Still functional.
4. **Rapid dialogue start/stop:** If dialogue starts and ends before status bar updates, the bar simply shows the last known state. No crash.
5. **Camera moves far from NPC during dialogue:** Billboard text follows camera. Status bar (CanvasLayer) is unaffected by camera position.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #52 — Dialogue Engine Runtime + Visual Presentation | **Completed** — DialogueDisplay3D, HemingwayEnforcer, input handling all exist | Low — stable, tested |
| Issue #47 — GameState System | **Completed** — StateSystem autoload with hope_despair, conviction, will | Low — `state_changed` signal exists |
| Issue #44 — Lo-Fi 3D Text Rendering | **Completed** — LoFiText3D, shader, pixel font all exist | Low — stable, tested |
| Issue #49 — Text Component Library | **In-flux** — TextComponentBase, TextVariantData exist; component scenes pending | Low — not required for UI system; can use LoFiText3D directly |
| Godot 4.7 CanvasLayer + Control | Stable | Low — mature API |
| Pixel font (.fnt) | Existing | Low — `assets/fonts/pixel_font.*` exists |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #54 — NPC Framework | Medium — NPC interaction flow benefits from visible status update feedback |
| Issue #57 — MVP Playtest | Medium — playtesters need to see their emotional state |
| Scene polish (all scenes) | Low — status bar should be consistent across all scenes |

### Preparation Needed

- [ ] Define UIConfig singleton (`gdscripts/ui_config.gd`) with responsive layout parameters
- [ ] Design status bar color gradient in Hopper palette: amber (#FFB000) → dark blue (#2A2A4A)
- [ ] Verify `StateSystem.state_changed` signal frequency — ensure no more than ~10 updates/second to avoid animation thrash
- [ ] Create `scenes/ui/` directory for UI scene files
- [ ] Define minimum/maximum font scale factors to prevent text from becoming unreadable at extreme resolutions

---

## 7. Spike / Experiment (Optional — depth/standard only)

> Section 7 is optional for `depth/standard`. The following key design decisions inform the Plan phase.

### Key Design Decisions Already Resolved

1. **Status bar path:** CanvasLayer (2D overlay) — chosen in recommendation above
2. **Choice list path:** 3D world space (existing DialogueDisplay3D) — per GDD and Issue #52
3. **Responsive layout mechanism:** Singleton UIConfig with `recalculate()` triggered by viewport size changes
4. **Choice order:** Choices float **above** dialogue text (per AC1)
5. **Status bar layout:** Thin bar, bottom-center, 60% viewport width, horizontal gradient

### Open Questions for Plan Phase

1. **Status bar animation:** Should the bar animate smoothly on every state change, or use a discrete step animation (e.g., only move when hope_despair crosses a state boundary)? Smooth animation is more informative but may feel twitchy with rapid state changes. A compromise: smooth tween with a 0.3s duration, but skip animation if another change arrives within 0.1s (animation compaction).

2. **Emissive ping effect:** When hope_despair changes significantly (crosses a state boundary, e.g., from Neutral to Low), should the status bar briefly glow/pulse to draw the player's attention? This would increase feedback clarity at the cost of potential visual noise. Suggestion: subtle pulse only on state boundary crossing, not on every tick.

3. **Text component reuse:** The status bar labels ("HOPE", "DESPAIR") could use LoFiText3D (placed in CanvasLayer via a Control→Label3D bridge) or plain Label nodes with the pixel font. The Plan agent should determine if Label3D can be used inside a CanvasLayer environment, or if a plain Label with pixel font is sufficient and visually consistent.

4. **Screen-space reservation:** How should DialogueDisplay3D guarantee that 3D text doesn't overlap the status bar area? Options: (a) calculate the Y-offset of the lowest 3D text element, clamp it above the status bar's screen-space Y; (b) ensure choices always appear above dialogue text, and the dialogue text is high enough above the NPC that its projected position is safely above the status bar. Option (b) is simpler — the NPC conversation default position puts text at head height, well above the status bar area.

5. **Status bar visibility toggle:** Should there be a keybind or option to toggle status bar visibility? For a minimalist Hopper-style UI, persistent always-on is preferred — but a toggle (e.g., Tab to show/hide) is a common accessibility pattern.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The project currently has a working 3D dialogue display (DialogueDisplay3D — Issue #52) and a StateSystem with `state_changed` signals (Issue #47). The UI System (Issue #53) adds two major pieces:

1. **Status bar** — A CanvasLayer-based thin bar at the screen bottom showing hope/despair via a horizontal gradient fill with an indicator dot. The bar `ColorRect` is updated via `StateSystem.state_changed` signals, interpolating the hope_despair (-10..+10) value to a 0.0–1.0 fill ratio. The bar uses the Hopper palette: amber (#FFB000) at the hope end, dark blue (#2A2A4A) at the despair end.

2. **Responsive dialogue display** — The existing DialogueDisplay3D is extended with:
   - Choice label order reversed so choices float **above** dialogue text (AC1)
   - `UIConfig.auto_font_scale` applied to all LoFiText3D font sizes based on viewport ratio
   - `UIConfig.choice_spacing` scaling proportionally to viewport height
   - Font scale floor/clamp to prevent unreadable extremes

### Files to Create

1. **`gdscripts/ui_config.gd`** — Singleton (autoload) for responsive layout:
   - `const BASE_RESOLUTION := Vector2(1920, 1080)`
   - `var auto_font_scale: float = 1.0`
   - `var choice_spacing: float = 0.25`
   - `func recalculate() -> void` — called on `get_tree().root.size_changed`
   - Formula: `auto_font_scale = clamp(viewport_size.y / BASE_RESOLUTION.y, 0.5, 2.0)`
   - Formula: `choice_spacing = 0.25 * auto_font_scale`

2. **`gdscripts/status_bar.gd`** — Status bar controller:
   - Extends `CanvasLayer`
   - Export: `@export var bar_width_ratio: float = 0.6`
   - Export: `@export var bar_height_px: float = 4.0`
   - Node references: `_bar_fill: ColorRect`, `_indicator: ColorRect`, `_bg: ColorRect`, `_hope_label: Label`, `_despair_label: Label`
   - `func _on_state_changed(state: Dictionary)` — update bar fill + position
   - `func _update_bar(hope_despair: float)` — interpolate fill width, move indicator
   - Internal color constants: `HOPE_COLOR = Color("#FFB000")`, `DESPAIR_COLOR = Color("#2A2A4A")`, `BG_COLOR = Color("#1a1a2e", 0.6)`

3. **`scenes/ui/status_bar.tscn`** — CanvasLayer scene:
   - Root: CanvasLayer (StatusBar script), layer = 128 (above world, below debug overlays)
   - Children:
     - `Background` — ColorRect, full bar width, semi-transparent dark
     - `FillBar` — ColorRect, left-aligned, width = hope_despair ratio * bar width
     - `Indicator` — ColorRect (small square or circle), positioned at current value
     - `HopeLabel` — Label with pixel font, "HOPE" text, top-left
     - `DespairLabel` — Label with pixel font, "DESPAIR" text, top-right

### Modifications to Existing Files

1. **`gdscripts/dialogue_display_3d.gd`**:
   - In `_ready()`: load `UIConfig` (via `get_node("/root/UIConfig")` or autoload direct reference)
   - In `show_choices_immediate()`: apply `UIConfig.choice_spacing` to vertical positioning
   - In `on_node_changed()`: apply `UIConfig.auto_font_scale` to speaker/dialogue text font sizes
   - Change choice label Y-offset calculation so choices are positioned **above** the dialogue text (negative Y instead of positive)

2. **`gdscripts/main.gd`**:
   - Add `@onready var status_bar: Node = $StatusBar`
   - Connect `state_system.state_changed` to `status_bar._on_state_changed`
   - Connect `get_tree().root.size_changed` to `_on_viewport_size_changed()` (which calls `UIConfig.recalculate()`)
   - Remove the debug `world_label` status text (replaced by proper status bar)

3. **`scenes/main.tscn`**:
   - Add `StatusBar` (CanvasLayer) as a child of the root
   - Remove `WorldLabel` (Label3D debug text) — or keep as debug toggle

4. **Project Settings > Autoload**:
   - Add `UIConfig` as a singleton (autoload) with `gdscripts/ui_config.gd`

### Key Risks

1. **Label3D in CanvasLayer edge case:** If labels are needed inside the status bar, Label3D nodes are not CanvasItem children and cannot be placed directly in a CanvasLayer. The status bar should use plain `Label` nodes (Control) with the pixel font for "HOPE"/"DESPAIR" text. These can be themed to match the lo-fi aesthetic via reduced font size and the pixel font asset.

2. **Choice text overlapping at 16:10 aspect ratio:** The existing `choice_spacing = 0.25` was designed for 1920×1080. At 1920×1200 (16:10, 11% taller), 3D text projected to screen is smaller, so spacing may appear excessive. The UIConfig scaling formula must account for this: spacing should scale with viewport height but also consider the pixel font's natural size.

3. **Status bar aesthetic mismatch:** A 2D CanvasLayer bar may look too clean compared to the lo-fi 3D text. Mitigations: use the same pixel font, keep the bar very thin and transparent (subdued), and optionally apply a subtle pixelation shader to the CanvasLayer.

4. **Camera unprojection for collision avoidance:** If the NPC is very close to the camera, 3D dialogue text might fill too much of the screen and overlap the status bar. The simple mitigation: ensure DialogueDisplay3D positioning includes a Y-offset that pushes text upward proportionally to camera proximity. A more robust approach (optional for Plan phase) uses `camera.unproject_position()` to check projected bounds.

### Design Decisions for Plan Agent

1. Status bar uses **CanvasLayer (2D)**, not 3D — simpler, more reliable, appropriate for non-diegetic HUD
2. Choice labels float **above** dialogue text (swap current Y-offset direction)
3. Responsive layout via **UIConfig autoload singleton** with `recalculate()` on viewport `size_changed`
4. Font scale factor based on `viewport_height / 1080`, clamped to [0.5, 2.0]
5. Choice spacing scales proportionally to font scale factor
6. Status bar uses **Label nodes** (not Label3D) for status text, with the same pixel font as 3D text
7. Smooth tween (0.3–0.5s) for status bar transitions, with animation compaction for rapid changes
8. No status bar visibility toggle in MVP — always-on minimal HUD
