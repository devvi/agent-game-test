# DESIGN: #53 — UI System — Hopper-Style Minimal UI

> Parent Issue: #53
> Agent: plan-agent
> Date: 2026-07-23
> Depth: standard

---

## 1. Architecture Overview

### Core Idea

Add a **minimal Hopper-style UI** layer to the game: a thin CanvasLayer-based status bar showing hope/despair state, and responsive layout for the existing 3D dialogue display. This implements **Approach A (Hybrid 3D/2D UI)** from the PRD — the status bar is a non-diegetic 2D overlay (appropriate for a HUD element), while dialogue text remains in 3D world space (aligned with the GDD's diegetic text direction). A new **UIConfig** singleton provides responsive layout parameters that both 2D and 3D UI components query.

### Data Flow

```
StateSystem.state_changed(state: Dictionary)
    │
    ├──► StatusBar._on_state_changed(state)
    │        │
    │        ├──► compute fill_level from hope_despair (-10..+10 → 0.0..1.0)
    │        ├──► kill active tween (compaction)
    │        ├──► tween _bar_fill.size.x from current → target ratio * bar_max_width
    │        └──► tween _indicator.position.x to match fill level
    │
    ├──► (existing) NarrativeManager / SceneBase for world feedback
    └──► (existing) debug print/log

get_tree().root.size_changed
    │
    └──► UIConfig.recalculate()
         │
         ├──► auto_font_scale = clamp(viewport_size.y / BASE_RESOLUTION.y, 0.5, 2.0)
         ├──► choice_spacing = 0.25 * auto_font_scale
         └──► (future) status_bar_height = auto_font_scale * 4.0

DialogueDisplay3D (listens to choice/node signals)
    │
    ├──► on_node_changed(): apply UIConfig.auto_font_scale to speaker + dialogue text
    ├──► on_choices_available(): apply UIConfig.choice_spacing to vertical positioning
    └──► (choice order: choices float ABOVE dialogue text — reversed Y-offset)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Status bar rendering | CanvasLayer (2D Control nodes) | HUD elements are non-diegetic; Godot's Control + anchor system handles every aspect ratio automatically |
| Responsive layout | UIConfig singleton (autoload) | Single source of truth for all responsive parameters; both 2D and 3D code query the same values |
| Choice label order | Above dialogue text | PRD AC1 requires "choice list appears as 3D floating labels vertically arranged above dialogue text" |
| Font scaling | Clamped ratio: viewport_height / 1080, [0.5, 2.0] | Prevents text from being unreadably small (phone-like) or huge (low res); 0.5–2.0 range is safe for all supported aspect ratios |
| Status bar animation | Smooth tween (0.3s) with compaction | Player gets visual feedback on state change; rapid changes skip intermediate animations for responsiveness |
| Status bar labels | Label (Control) with pixel font | Label3D cannot be placed in CanvasLayer; plain Label with the same `.fnt` asset preserves visual consistency |
| Status bar visibility | Always-on, no toggle in MVP | Minimalist Hopper-style UI is persistent; toggle can be added as post-MVP accessibility feature |
| State direction mapping | hope_despair -10 → fill_ratio 0.0 (despair left), +10 → 1.0 (hope right) | The gradient runs amber (hope) → dark blue (despair); bar fill represents the current balance position |

### Scene Hierarchy (post-change)

```
Main (Node3D)
├── Camera3D
├── UI (CanvasLayer)
├── StatusBar (CanvasLayer) — NEW: StatusBar script, layer=128
│   ├── Background (ColorRect) — semi-transparent dark, full bar width
│   ├── FillBar (ColorRect) — gradient tinted, left-anchored
│   ├── Indicator (ColorRect) — bright dot at current position
│   ├── HopeLabel (Label) — pixel font, "HOPE", top-left
│   └── DespairLabel (Label) — pixel font, "DESPAIR", top-right
├── Dialogue (CanvasLayer)
│   └── DialoguePanel (Panel) — existing 2D fallback, hidden by default
├── Dialogue3D (Node3D) — existing DialogueDisplay3D script
│   ├── SpeakerLabel (LoFiText3D)
│   ├── DialogueText (LoFiText3D)
│   ├── ChoiceContainer (Node3D)
│   │   ├── Choice0 (LoFiText3D)
│   │   ├── Choice1 (LoFiText3D)
│   │   ├── Choice2 (LoFiText3D)
│   │   └── Choice3 (LoFiText3D)
│   └── ContinuePrompt (LoFiText3D)
└── DialogueDebug (CanvasLayer)
```

---

## 2. Node / Scene Tree Layer

### New Scene: `scenes/ui/status_bar.tscn`

A CanvasLayer scene with the StatusBar script attached. Layer = 128 (above world, below debug overlays).

```
StatusBar (CanvasLayer) — layer=128, script: StatusBar
│
├── Background (ColorRect)
│   ├── anchors: center-bottom, size: (0.6 * viewport_width, 4px)
│   ├── color: #1a1a2e (alpha 0.6)
│   └── corner radius: subtle rounding via theme
│
├── FillBar (ColorRect)
│   ├── anchors: left-center of Background
│   ├── width: (hope_despair ratio) * bar_max_width
│   ├── color gradient: sample from HOPE_COLOR → DESPAIR_COLOR based on ratio
│   └── height: same as Background
│
├── Indicator (ColorRect)
│   ├── size: 6×6px, square (or small circle via custom drawing)
│   ├── color: #FFFFFF (white / bright amber)
│   ├── position.x: synchronised with FillBar right edge
│   └── anchored vertically centre of bar
│
├── HopeLabel (Label)
│   ├── text: "HOPE"
│   ├── font: pixel_font.tres (same as LoFiText3D)
│   ├── font_size: 10px (small, consistent with thin bar aesthetic)
│   ├── position: above-left of Background
│   └── modulate: amber #FFB000
│
└── DespairLabel (Label)
    ├── text: "DESPAIR"
    ├── font: pixel_font.tres
    ├── font_size: 10px
    ├── position: above-right of Background
    └── modulate: dark blue #2A2A4A
```

**Positioning logic (in script `_ready()` or `_process()`):**

```gdscript
# Anchored to bottom-center in script:
var viewport_size := get_viewport().get_visible_rect().size
var bar_width := viewport_size.x * bar_width_ratio  # 0.6
var bar_height := bar_height_px  # 4.0 at 1080p, scaled by UIConfig

# Background positioned manually since CanvasLayer lacks anchor-based layout
# in older Godot 4.x patterns — position from bottom-center
var bg_rect := _bg
bg_rect.size = Vector2(bar_width, bar_height)
bg_rect.position = Vector2(
    (viewport_size.x - bar_width) / 2.0,
    viewport_size.y - bar_height - margin_bottom
)
```

### Existing Scene Changes: `scenes/main.tscn`

Add a new CanvasLayer child:

```
[node name="StatusBar" type="CanvasLayer" parent="."]
layer = 128
script = ExtResource("res://gdscripts/status_bar.gd")
```

Remove (or comment out) the `WorldLabel` (Label3D debug text) node — the status bar replaces it. Keep it as a hidden debug toggle if desired.

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/ui_config.gd` (Autoload Singleton)

A singleton (autoload) for responsive layout parameters. No scene dependency — instantiable in `--script` tests.

```gdscript
extends Node
class_name UIConfig

const BASE_RESOLUTION := Vector2(1920, 1080)
const MIN_FONT_SCALE := 0.5
const MAX_FONT_SCALE := 2.0
const BASE_CHOICE_SPACING := 0.25
const MIN_CHOICE_SPACING := 0.12
const MAX_CHOICE_SPACING := 0.5

var auto_font_scale: float = 1.0
var choice_spacing: float = 0.25
var status_bar_height: float = 4.0
var last_viewport_size: Vector2 = Vector2(1920, 1080)

func _ready() -> void:
    if is_instance_valid(get_viewport()):
        get_viewport().size_changed.connect(_on_viewport_size_changed)
    recalculate()

func recalculate() -> void:
    var viewport := get_viewport()
    if not is_instance_valid(viewport):
        return
    var size := viewport.get_visible_rect().size
    if size == Vector2.ZERO:
        return
    last_viewport_size = size
    var ratio := size.y / BASE_RESOLUTION.y
    auto_font_scale = clampf(ratio, MIN_FONT_SCALE, MAX_FONT_SCALE)
    choice_spacing = clampf(BASE_CHOICE_SPACING * auto_font_scale, MIN_CHOICE_SPACING, MAX_CHOICE_SPACING)
    status_bar_height = 4.0 * auto_font_scale

func _on_viewport_size_changed() -> void:
    recalculate()
```

**Key formulas:**

| Parameter | Formula | Clamp |
|-----------|---------|-------|
| `auto_font_scale` | `viewport_height / 1080` | [0.5, 2.0] |
| `choice_spacing` | `0.25 * auto_font_scale` | [0.12, 0.5] |
| `status_bar_height` | `4.0 * auto_font_scale` | [2.0, 8.0] |

### New Script: `gdscripts/status_bar.gd`

CanvasLayer controller for the hope/despair status bar.

```gdscript
extends CanvasLayer
class_name StatusBar

# --- Exports ---
@export var bar_width_ratio: float = 0.6
@export var bar_height_px: float = 4.0
@export var tween_duration: float = 0.3
@export var margin_bottom: float = 8.0  # pixels from screen bottom edge

# --- Color Constants ---
const HOPE_COLOR := Color("#FFB000")       # Amber
const DESPAIR_COLOR := Color("#2A2A4A")     # Dark blue
const BG_COLOR := Color("#1a1a2e", 0.6)     # Semi-transparent dark
const INDICATOR_COLOR := Color("#FFD700")   # Bright gold for indicator dot
const NEUTRAL_COLOR := Color("#808080")     # Grey centre point

# --- Node References (@onready) ---
@onready var _bg: ColorRect = $Background
@onready var _bar_fill: ColorRect = $FillBar
@onready var _indicator: ColorRect = $Indicator
@onready var _hope_label: Label = $HopeLabel
@onready var _despair_label: Label = $DespairLabel
@onready var _tween: Tween

# --- Internal State ---
var _current_ratio: float = 0.5  # 0.0 = max despair, 1.0 = max hope
var _bar_max_width: float = 0.0

# --- Lifecycle ---
func _ready() -> void:
    _tween = Tween.new()
    add_child(_tween)
    _update_layout()
    _update_bar(0.5)  # Start neutral

func _on_state_changed(state: Dictionary) -> void:
    # Expects state.hope_despair: int in range -10..+10
    var hope_despair: float = state.get("hope_despair", 0)
    # Map -10..+10 → 0.0..1.0
    var ratio: float = (hope_despair + 10.0) / 20.0
    ratio = clampf(ratio, 0.0, 1.0)
    _update_bar(ratio)

func _update_bar(target_ratio: float) -> void:
    # Kill any active tween for compaction (rapid state changes)
    if _tween.is_running():
        _tween.kill()

    # Recalculate bar width in case viewport changed
    _update_layout()

    # Interpolate fill bar width
    var target_width: float = target_ratio * _bar_max_width
    var current_width: float = _bar_fill.size.x
    var indicator_x: float = _indicator.position.x

    _tween.tween_property(_bar_fill, "size:x", target_width, tween_duration) \
         .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
    _tween.parallel().tween_property(_indicator, "position:x",
        target_width - _indicator.size.x / 2.0, tween_duration) \
         .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

    # Update fill bar to gradient midpoint based on ratio
    var fill_color: Color = HOPE_COLOR.lerp(DESPAIR_COLOR, target_ratio)
    _bar_fill.color = fill_color

    _current_ratio = target_ratio

func _update_layout() -> void:
    var viewport_size := get_viewport().get_visible_rect().size
    var bar_width := viewport_size.x * bar_width_ratio
    _bar_max_width = bar_width

    # UIConfig scaling (if available)
    var ui_config := get_node_or_null("/root/UIConfig") as UIConfig
    var scale_factor: float = 1.0
    if ui_config != null:
        scale_factor = ui_config.auto_font_scale

    var bar_height := bar_height_px * scale_factor
    var bar_x := (viewport_size.x - bar_width) / 2.0
    var bar_y := viewport_size.y - bar_height - margin_bottom

    _bg.position = Vector2(bar_x, bar_y)
    _bg.size = Vector2(bar_width, bar_height)

    _bar_fill.position = Vector2(bar_x, bar_y)
    _bar_fill.size = Vector2(_current_ratio * bar_width, bar_height)

    _indicator.size = Vector2(bar_height * 1.5, bar_height * 1.5)
    _indicator.position = Vector2(
        bar_x + (_current_ratio * bar_width) - _indicator.size.x / 2.0,
        bar_y - (_indicator.size.y - bar_height) / 2.0
    )

    _hope_label.position = Vector2(bar_x, bar_y - _hope_label.size.y - 2)
    _despair_label.position = Vector2(
        bar_x + bar_width - _despair_label.size.x,
        bar_y - _despair_label.size.y - 2
    )
```

### Modified Script: `gdscripts/dialogue_display_3d.gd`

**New imports / references:**
```gdscript
# In _ready():
var ui_config := get_node_or_null("/root/UIConfig") as UIConfig
if ui_config != null:
    ui_config.recalculate()  # ensure latest values
```

**Modifications to `show_choices_immediate()` (or equivalent):**
```gdscript
# Apply responsive choice_spacing from UIConfig
var spacing: float = UIConfig.choice_spacing if UIConfig else 0.25
for i in range(_current_choices.size()):
    var label: LoFiText3D = _choice_labels[i]
    # Choice labels positioned above dialogue text => negative Y offset
    label.position.y = -(i + 1) * spacing - 0.1  # -0.1 base offset from dialogue text Y
```

**Modifications to `on_node_changed()`:**
```gdscript
# Apply responsive font scaling
var scale_factor: float = UIConfig.auto_font_scale if UIConfig else 1.0
# If LoFiText3D supports pixel_size:
dialogue_text.pixel_size = base_pixel_size * scale_factor
speaker_label.pixel_size = base_speaker_pixel_size * scale_factor
```

**Choice order reversal:**
- Change Y-offset sign: choices positioned **above** dialogue text (negative Y relative to root) instead of below (positive Y).
- Dialogue text remains at its existing Y position (e.g., `y=0.4`).
- Speaker label stays highest (e.g., `y=0.8`).

### Modified Script: `gdscripts/main.gd`

**New `@onready` declarations:**
```gdscript
@onready var status_bar: CanvasLayer = $StatusBar
@onready var ui_config: Node = get_node("/root/UIConfig")
```

**New signal connections in `_ready()`:**
```gdscript
# Connect status bar to state changes
state_system.state_changed.connect(status_bar._on_state_changed)

# Connect viewport size changes (also handled by UIConfig._ready)
get_tree().root.size_changed.connect(_on_viewport_size_changed)
```

**New handler:**
```gdscript
func _on_viewport_size_changed() -> void:
    if ui_config != null and is_instance_valid(ui_config):
        ui_config.recalculate()
    # StatusBar._update_layout() will be called on next state change or
    # on its own via _process if we add periodic layout refresh
```

**Remove debug world_label:**
```gdscript
# Remove or comment out:
# label_3d.text = "Hope: %d  Despair: %d" % [hope, despair]
```

---

## 4. Resource / Config Layer

### Autoload Registration (`project.godot`)

Add under `[autoload]`:

```
UIConfig="*res://gdscripts/ui_config.gd"
```

### Status Bar Visual Parameters

| Property | Value | Notes |
|----------|-------|-------|
| Bar background color | `#1a1a2e`, alpha 0.6 | Semi-transparent dark matches Hopper night palette |
| Hope color (left) | `#FFB000` (amber) | Same amber as dialogue focus highlight |
| Despair color (right) | `#2A2A4A` (dark blue) | Cool-dark counterpoint to warm amber |
| Indicator color | `#FFD700` (bright gold) | Slightly brighter than hope for visibility |
| Bar height (1080p) | 4px | Thin, non-intrusive |
| Bar width | 60% of viewport | Centered, leaves breathing room on sides |
| Font | `assets/fonts/pixel_font.tres` | Same pixel font as LoFiText3D labels |
| Font size | 10px | Small enough to not distract, readable |
| Tween duration | 0.3s | Fast enough to feel responsive, slow enough to perceive |
| Tween easing | EASE_OUT + TRANS_SINE | Smooth deceleration feels natural |
| CanvasLayer | 128 | Above world, below debug overlays |

### Status Bar Animation States

| State | Bar Fill | Indicator | Color |
|-------|----------|-----------|-------|
| Neutral (0) | Centered (50% fill) | Midpoint | Greyish-amber |
| Low hope (+3) | ~65% fill | Right of centre | Amber-leaning |
| Max hope (+10) | 100% fill | Far right | Full amber |
| Low despair (-3) | ~35% fill | Left of centre | Blue-leaning |
| Max despair (-10) | 0% fill | Far left | Full dark blue |

### Emissive Ping Effect (Optional, Design Decision)

**Decision:** Do NOT implement a pulse/glow effect on the status bar for MVP.
- Adds visual noise to an intentionally minimal UI
- The smooth tween already provides clear feedback
- Can be added post-MVP if playtesting shows players miss state changes

---

## 5. Asset / Visual Layer

### Status Bar Visual Design

```
┌─ HOPE ───────────────────────────── DESPAIR ─┐
│ ████████████████████████████████████░░░░░░░░░ │
│                     ●                         │
└───────────────────────────────────────────────┘

   ←────── 60% viewport width ──────→
   ←── amber/gold fill ──→←── dark blue ──→
```

- The fill bar represents the hope/despair balance as a single gradient strip
- The indicator dot shows the exact current value position
- Labels are placed above the bar ends for context
- Bar is 4px tall at 1080p, scaling proportionally via UIConfig

### Label Visual Treatment

- **HopeLabel:** `#FFB000` (amber) modulate, pixel font, 10px
- **DespairLabel:** `#2A2A4A` (dark blue) modulate, pixel font, 10px
- Same font asset as LoFiText3D ensures visual consistency across 2D and 3D rendering contexts

### Consistent Palette Across UI

| Element | Color | Where Defined |
|---------|-------|---------------|
| Dialogue focus highlight | `#FFB000` (amber) | LoFiText3D emissive_color |
| Status bar hope side | `#FFB000` (amber) | StatusBar.HOPE_COLOR |
| Status bar despair side | `#2A2A4A` (dark blue) | StatusBar.DESPAIR_COLOR |
| Status bar background | `#1a1a2e` (alpha 0.6) | StatusBar.BG_COLOR |
| Speaker label emissive | `#FFB000` | DialogueDisplay3D |
| Dialogue text | `#FFFFFF` | DialogueDisplay3D |
| Choice focused | `#FFB000` emissive | DialogueDisplay3D |
| Choice dimmed | no emissive, grey tint | DialogueDisplay3D |

---

## 6. Input / UI Layer

### No New Input Map Actions

The UI system does not add any new keyboard bindings. Existing actions remain:

| Action | Key | Purpose |
|--------|-----|---------|
| `dialogue_up` | Arrow Up | Navigate choice focus |
| `dialogue_down` | Arrow Down | Navigate choice focus |
| `dialogue_select` | Enter/Space | Select choice |
| 1–4 (direct) | Number keys | Direct choice selection |

### Status Bar Interaction

- The status bar is **display-only** — no click or hover interaction
- No toggle/hide keybind in MVP
- Future: Tab to toggle HUD visibility (accessibility pattern)

### Dialogue Input Behavior with Status Bar

- Status bar occupies the bottom ~3% of screen space at 1080p (4px bar + 8px margin + ~12px labels)
- DialogueDisplay3D positions text high enough (NPC head height area) that projected 3D text never overlaps the status bar
- This is guaranteed by:
  1. DialogueDisplay3D being positioned at NPC head height (above camera view's bottom edge)
  2. Choice labels appearing above dialogue text (negative Y), pushing them even higher
  3. The status bar being anchored to the screen bottom in CanvasLayer space

---

## 7. Test Layer

All test case descriptions — implement agent writes runnable tests.

### Test File: `tests/test_ui_config.gd`

Tests for responsive layout calculations (pure logic, no scene required).

### Normal Path Tests (≥2)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| C1 | Font scale at base resolution | Create UIConfig, simulate viewport 1920×1080, call `recalculate()` | `auto_font_scale == 1.0`, `choice_spacing == 0.25` | `assert(auto_font_scale == 1.0)`, `assert(choice_spacing == 0.25)` |
| C2 | Font scale at larger resolution | Simulate viewport 2560×1440, call `recalculate()` | `auto_font_scale == 1440/1080 ≈ 1.333`, `choice_spacing ≈ 0.333` | `assert(abs(auto_font_scale - 1.333) < 0.001)`, `assert(abs(choice_spacing - 0.333) < 0.001)` |
| C3 | Status bar hope_despair mapping | Call `_update_bar(0.75)` with ratio 0.75 (hope_leaning) | FillBar width == 75% of max bar width, indicator positioned at 75% | `assert(_bar_fill.size.x == _bar_max_width * 0.75)` |

### Boundary / Edge Case Tests (≥3)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| C4 | Font scale clamp: tiny viewport | Simulate 800×600 (ratio = 0.556) | `auto_font_scale == 0.5` (clamped to min) | `assert(auto_font_scale == 0.5)` |
| C5 | Font scale clamp: huge viewport | Simulate 3840×2160 (ratio = 2.0) | `auto_font_scale == 2.0` (at max clamp) | `assert(auto_font_scale == 2.0)` |
| C6 | Font scale clamp: extreme viewport | Simulate 7680×4320 (ratio = 4.0) | `auto_font_scale == 2.0` (clamped to max) | `assert(auto_font_scale == 2.0)` |
| C7 | Choice spacing clamp: tiny viewport | `auto_font_scale = 0.5`, call `recalculate()` | `choice_spacing == 0.125` | `assert(choice_spacing >= 0.12)` |
| C8 | Status bar max despair | `hope_despair = -10`, call `_on_state_changed({hope_despair: -10})` | `_current_ratio == 0.0`, fill width == 0 | `assert(_current_ratio == 0.0)` |
| C9 | Status bar max hope | `hope_despair = +10`, call `_on_state_changed({hope_despair: 10})` | `_current_ratio == 1.0`, fill width == max | `assert(_current_ratio == 1.0)` |
| C10 | Rapid state changes (compaction) | Call `_update_bar(0.3)`, then immediately `_update_bar(0.7)` | Only the second animation runs; first is killed | `assert(_bar_fill.size.x targets 0.7 * max_width)`, `assert(no duplicate tweens)` |

### Failure Path Tests (≥1)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| C11 | UIConfig.get_node() returns null | DialogueDisplay3D._ready() when UIConfig not registered | No crash, falls back to hardcoded defaults | `assert(dialogue_text.pixel_size == default)`, no error |
| C12 | Status bar with no StateSystem | StatusBar._ready() with no state_changed connection | Neutral position (50%), no crash | `assert(_current_ratio == 0.5)` |
| C13 | state_changed with missing key | Call `_on_state_changed({})` — no `hope_despair` key | Returns default 0 (neutral), no crash | `assert(_current_ratio == 0.5)` |
| C14 | state_changed with out-of-range value | Call `_on_state_changed({hope_despair: -20})` | Clamped to 0.0 (min), no overflow | `assert(_current_ratio == 0.0)` |

### Integration Test Descriptions

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| C15 | Dialogue + status bar coexistence | Trigger dialogue (F9) while status bar shows non-neutral state | Status bar visible, does not overlap 3D dialogue text | Visual inspection OR screen-space bound check |
| C16 | Viewport resize during dialogue | Resize window from 1920×1080 to 2560×1440 while dialogue is active | UIConfig recalculates; next dialogue node gets new font size and spacing | `assert(auto_font_scale ≈ 1.333)` after resize |
| C17 | Window minimized and restored | Minimize then restore window | `size_changed` fires, `recalculate()` runs, layout updates | No stale/incorrect bar position |
| C18 | State change during dialogue | Player is in dialogue with 3 choices, `state_changed` fires (despair increases) | Status bar animates while dialogue continues; no visual glitch | Status bar completes animation; dialogue labels unaffected |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| UIConfig responsive formulas | ✅ (C1, C2) | ≥3 (C4, C5, C6, C7) | ✅ (C11) |
| Status bar fill/animation | ✅ (C3) | ≥2 (C8, C9, C10) | ✅ (C12, C13, C14) |
| Dialogue display modifications | ✅ (dialogue #52 tests already cover T1-T3) | ✅ (existing T4-T10) | ✅ (existing T11-T13) |
| Integration: UI + dialogue | — | ≥1 (C15) | ✅ (C16, C17, C18) |

---

## 8. Files Changed (per-layer summary)

### New Files

| Layer | File | Change | Est. Lines |
|-------|------|--------|-----------|
| Script (New) | `gdscripts/ui_config.gd` | New autoload singleton: responsive layout parameters, recalculate() | +50 |
| Script (New) | `gdscripts/status_bar.gd` | New CanvasLayer controller: bar fill, indicator, animation, layout | +140 |
| Scene (New) | `scenes/ui/status_bar.tscn` | New scene: Background, FillBar, Indicator, HopeLabel, DespairLabel | +30 |
| Test (New) | `tests/test_ui_config.gd` | Test descriptions for responsive layout | +80 |
| Test (New) | `tests/test_ui_status_bar.gd` | Test descriptions for status bar | +100 |

### Modified Files

| Layer | File | Change | Est. Lines |
|-------|------|--------|-----------|
| Script (Mod) | `gdscripts/dialogue_display_3d.gd` | Add UIConfig reference, apply auto_font_scale to labels, reverse choice Y-offset, apply responsive choice_spacing | ±20 |
| Script (Mod) | `gdscripts/main.gd` | Add StatusBar @onready, connect state_changed + size_changed signals, remove debug world_label update | ±15 |
| Scene (Mod) | `scenes/main.tscn` | Add StatusBar (CanvasLayer) as child, remove/comment WorldLabel | ±5 |
| Config | `project.godot` | Add UIConfig autoload registration | +2 |

**Total estimated: ~440 lines**

---

## 9. Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI approach | A: Hybrid 3D/2D (CanvasLayer status bar + 3D dialogue) | Per PRD recommendation — status bar is non-diegetic HUD, dialogue is diegetic world element |
| Status bar rendering | CanvasLayer (2D Control) | Reliable, performant, handles aspect ratios natively; battle-tested Godot pattern |
| Responsive mechanism | UIConfig autoload singleton | Single query point for all responsive params; both 2D and 3D code use same values |
| Font scale formula | `viewport_height / 1080`, clamped [0.5, 2.0] | Proportional to vertical resolution; clamp prevents extremes |
| Choice order | Above dialogue text (negative Y offset) | Per AC1: "choice list appears as 3D floating labels above dialogue text" |
| Status bar labels | Label (Control) with pixel font | Label3D cannot go in CanvasLayer; same font preserves visual consistency |
| Animation compaction | Kill active tween on new state change | Prevents animation queue buildup during rapid state changes |
| Emissive ping | No (deferred) | Keeps MVP minimal; can be added as visual polish later |
| Status bar toggle | No toggle in MVP | Always-on; toggle is an accessibility post-MVP feature |
| Status bar height | 4px at 1080p, scaled via UIConfig | Thin enough to be non-intrusive, thick enough to read at a glance |
| Choice spacing scaling | Proportional to auto_font_scale | Ensures visual spacing remains consistent across resolutions |
| State direction mapping | -10→0.0 (left/despair), +10→1.0 (right/hope) | Intuitive: more hope = more amber fill; matches the gradient left→right |

---

## 10. Verification Checklist

- [ ] `UIConfig.recalculate()` computes correct `auto_font_scale` from viewport height
- [ ] `UIConfig.recalculate()` clamps font scale to [0.5, 2.0]
- [ ] `UIConfig.choice_spacing` scales proportionally and respects clamp bounds
- [ ] `StatusBar._on_state_changed()` maps `hope_despair` (-10..+10) to fill ratio (0.0..1.0) correctly
- [ ] Status bar animates smoothly on state change with 0.3s tween
- [ ] Rapid state changes cause animation compaction (old tween killed)
- [ ] Status bar renders at correct position (bottom-center) at multiple resolutions
- [ ] Status bar labels ("HOPE", "DESPAIR") use pixel font matching 3D text
- [ ] Status bar at extreme values: max hope (100% fill), max despair (0% fill)
- [ ] Status bar degrades gracefully when UIConfig is missing (stays at neutral)
- [ ] Status bar degrades gracefully when StateSystem is missing (stays at neutral)
- [ ] DialogueDisplay3D applies `UIConfig.auto_font_scale` to speaker and dialogue text font sizes
- [ ] Dialogue choices float **above** dialogue text (negative Y offset, per AC1)
- [ ] Dialogue choice spacing scales with `UIConfig.choice_spacing`
- [ ] 3D dialogue text does not overlap status bar area at any supported aspect ratio (16:9, 16:10, 21:9, 4:3)
- [ ] DialogueDisplay3D falls back to hardcoded defaults when UIConfig is unavailable
- [ ] No new input map actions needed — existing keyboard navigation works unchanged
- [ ] Existing `test_dialogue_engine.gd` and `test_game_state.gd` tests still pass (regression check)
- [ ] No breaking changes to existing scenes or dialogue data format
