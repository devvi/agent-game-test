# DESIGN: #147 — Basic UI — Title Screen + Start Prompt

> Parent Issue: #147
> Agent: plan-agent
> Date: 2026-07-23
> Depth: light

---

## 1. Architecture Overview

### Core Idea

Add a **CanvasLayer-based title screen** (Approach A from PRD) that displays the game title "Urban Night Walker" with an atmospheric dark gradient background and a pulsing "Press Space to Start" prompt. The title screen is a child of `main.tscn` and blocks scene loading until the player presses Space/Enter, which triggers a `SceneManager` fade transition to `office.tscn`.

### Data Flow

```
Game Launch → main.tscn loads
    │
    ├──► Main._ready()
    │        │
    │        ├──► Connect StateSystem, StatusBar, DialogueDisplay3D (unchanged)
    │        ├──► TitleScreen starts pulsing animation on StartPrompt
    │        └──► NO call to _load_starting_scene() — deferred until start
    │
    ├──► Player presses Space/Enter
    │        │
    │        ├──► TitleScreen._input() detects ui_accept / dialogue_select
    │        ├──► TitleScreen emits start_requested(fade_duration)
    │        └──► Main._on_start_requested(fade_duration)
    │
    ├──► Main._on_start_requested()
    │        │
    │        ├──► SceneManager.trigger_scene_change("res://scenes/office/office.tscn")
    │        │        │
    │        │        ├──► Fade out (0.5s)
    │        │        ├──► change_scene_to_file("res://scenes/office/office.tscn")
    │        │        └──► Office scene's SceneManager handles fade-in
    │        │
    │        └──► main.tscn (including TitleScreen) is fully unloaded
    │
    └──► Office scene loads normally
             │
             ├──► SceneBase._ready() instantiates PlayerController
             ├──► StatusBar persists (autoload, re-instantiated via main.tscn)
             └──► Game loop begins
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Title screen approach | CanvasLayer (2D Control nodes) | Simplest, most reliable approach in Godot 4.7; reuses StatusBar's CanvasLayer pattern (layer 128+); no 3D scene overhead |
| CanvasLayer layer | 129 (above StatusBar layer 128) | Ensures title screen renders on top of all other UI; StatusBar naturally becomes visible after scene change |
| Transition API | Existing SceneManager.trigger_scene_change() | No new transition system needed; fade-out/in is already built and tested for dialogue-driven scene changes |
| Start input | Space or Enter (ui_accept / dialogue_select actions) | Reuses existing Input Map actions; consistent with Godot UI conventions |
| Background | ColorRect with GradientTexture2D (vertical dark gradient) | Zero asset overhead; pure colour; can be upgraded to ShaderMaterial later for rain/animated effects |
| Title text | Control Label with pixel font | Label3D cannot exist in CanvasLayer; using same `.fnt` asset as LoFiText3D preserves visual consistency |
| Start animation | modulate tween (0.4 → 1.0 → 0.4, ~2s period, ease-in-out loop) | Simple, reliable, no shader needed; creates clear "interactable" signal |
| Skip timer | None — player must deliberately press Space | Meets AC requirement: start is a deliberate action, not a skip mechanic |
| Title screen lifecycle | Child of main.tscn | Loaded at game start, fully unloaded when main.tscn is replaced by office.tscn |

### Scene Hierarchy (post-change)

```
Main (Node3D) — scenes/main.tscn
├── Camera3D
├── WorldLabel (Label3D) — visible=false (debug)
├── UI (CanvasLayer)
│   └── Overlay (Control)
├── Dialogue (CanvasLayer)
│   └── DialoguePanel — existing dialogue panel
├── Dialogue3D (Node3D) — existing DialogueDisplay3D
├── DialogueDebug (CanvasLayer) — existing debug overlay
├── StatusBar (CanvasLayer) — layer=128, existing
├── SceneManager (Node) — existing
├── TitleScreen (CanvasLayer) — NEW: layer=129, script=TitleScreen
│   ├── Background (ColorRect) — full-screen anchor, GradientTexture2D
│   ├── TitleLabel (Label) — "Urban Night Walker", pixel font, amber
│   ├── SubtitleLabel (Label) — "都市夜行者", pixel font, muted silver
│   └── StartPrompt (Label) — "Press Space to Start", pulsing modulate
```

---

## 2. New Files

### New Script: `gdscripts/title_screen.gd`

Title screen CanvasLayer controller. Extends CanvasLayer, handles input and pulsing animation.

```gdscript
extends CanvasLayer
class_name TitleScreen

# --- Signals ---
signal start_requested(fade_duration: float)

# --- Exports ---
@export var title_string: String = "Urban Night Walker"
@export var subtitle_string: String = "都市夜行者"
@export var prompt_string: String = "Press Space to Start"
@export var fade_duration: float = 0.5

# --- Color Constants (Hopper Palette) ---
const TITLE_COLOR := Color("#FFB000")        # Warm amber
const SUBTITLE_COLOR := Color("#B8B8B8")     # Muted silver
const PROMPT_COLOR := Color("#888888")       # Dim grey
const BG_COLOR_TOP := Color("#050510")       # Very dark blue-black
const BG_COLOR_BOTTOM := Color("#1a1a2e")    # Dark night blue

# --- Node References ---
@onready var _background: ColorRect = $Background
@onready var _title_label: Label = $TitleLabel
@onready var _subtitle_label: Label = $SubtitleLabel
@onready var _prompt_label: Label = $StartPrompt

# --- Lifecycle ---
func _ready() -> void:
    _configure_labels()
    _configure_background()
    _start_pulse_tween()

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept") or event.is_action_pressed("dialogue_select"):
        emit_signal("start_requested", fade_duration)
        set_process_input(false)  # Prevent double-fire during fade
        get_viewport().set_input_as_handled()

# --- Configuration ---
func _configure_labels() -> void:
    _title_label.text = title_string
    _title_label.add_theme_color_override("font_color", TITLE_COLOR)
    _apply_font_scaling()

    _subtitle_label.text = subtitle_string
    _subtitle_label.add_theme_color_override("font_color", SUBTITLE_COLOR)

    _prompt_label.text = prompt_string
    _prompt_label.add_theme_color_override("font_color", PROMPT_COLOR)

func _configure_background() -> void:
    var gradient := GradientTexture2D.new()
    var g := Gradient.new()
    g.colors = PackedColorArray([BG_COLOR_TOP, BG_COLOR_BOTTOM])
    gradient.gradient = g
    gradient.fill = GradientTexture2D.FILL_LINEAR
    gradient.fill_from = Vector2(0.5, 0.0)
    gradient.fill_to = Vector2(0.5, 1.0)
    _background.texture = gradient

func _apply_font_scaling() -> void:
    var ui_config := get_node_or_null("/root/UIConfig")
    if ui_config != null and ui_config.has_method("recalculate"):
        ui_config.recalculate()
        # UIConfig scaling applied via theme overrides

# --- Pulsing Animation ---
func _start_pulse_tween() -> void:
    var tween := create_tween()
    tween.set_loops()
    tween.tween_property(_prompt_label, "modulate:a", 0.4, 1.0)
    tween.tween_property(_prompt_label, "modulate:a", 1.0, 1.0)
```

**Key design points:**
- `signal start_requested(fade_duration: float)` — decouples title screen from scene loading logic
- `_input()` detects both `ui_accept` (Enter) and `dialogue_select` (Space) — covers both standard UI and game-specific actions
- `set_process_input(false)` after first press prevents double-fire during fade animation
- Pulsing tween uses `create_tween()` with `set_loops()` for infinite ping-pong
- Background uses `GradientTexture2D` with `Gradient` resource — created in code to avoid external resource dependencies
- `UIConfig` integration is optional — font scaling is applied if the autoload exists

### New Scene: `scenes/ui/title_screen.tscn`

CanvasLayer scene with the TitleScreen script attached. Layer = 129 (above StatusBar's layer 128).

```tscn
[gd_scene load_steps=1 format=3]

[ext_resource type="Script" path="res://gdscripts/title_screen.gd"]

[node name="TitleScreen" type="CanvasLayer"]
layer = 129
script = ExtResource("...")

[node name="Background" type="ColorRect" parent="."]
anchors_preset = 0  # Full rect
anchor_left = 0.0
anchor_top = 0.0
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2  # MOUSE_FILTER_IGNORE

[node name="TitleLabel" type="Label" parent="."]
anchors_preset = 8  # Center-top
anchor_left = 0.5
anchor_top = 0.35
anchor_right = 0.5
anchor_bottom = 0.35
offset_left = -300
offset_top = -60
offset_right = 300
offset_bottom = 0
horizontal_alignment = 1  # CENTER
vertical_alignment = 1    # CENTER
theme_override_fonts/font = ExtResource("...")  # pixel_font.tres
theme_override_font_sizes/font_size = 48

[node name="SubtitleLabel" type="Label" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.45
anchor_right = 0.5
anchor_bottom = 0.45
offset_left = -200
offset_top = -30
offset_right = 200
offset_bottom = 0
horizontal_alignment = 1
vertical_alignment = 1
theme_override_fonts/font = ExtResource("...")
theme_override_font_sizes/font_size = 32

[node name="StartPrompt" type="Label" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.6
anchor_right = 0.5
anchor_bottom = 0.6
offset_left = -150
offset_top = -20
offset_right = 150
offset_bottom = 0
horizontal_alignment = 1
vertical_alignment = 1
theme_override_fonts/font = ExtResource("...")
theme_override_font_sizes/font_size = 18
```

**Layout breakdown:**
| Node | Anchor | Offset | Rationale |
|------|--------|--------|-----------|
| Background | Full rect (0,0,1,1) | 0 all sides | Covers entire viewport regardless of aspect ratio |
| TitleLabel | Center-top h=0.5, v=0.35 | -300,-60 → 300,0 | 600px wide, positioned at 35% from top (upper-third rule) |
| SubtitleLabel | Center-top h=0.5, v=0.45 | -200,-30 → 200,0 | 400px wide, 10% below title |
| StartPrompt | Center-top h=0.5, v=0.6 | -150,-20 → 150,0 | 300px wide, positioned at 60% from top (lower-third area) |

---

## 3. Modified Files

### Modified Scene: `scenes/main.tscn`

Add the TitleScreen instance as a child of the root node:

```tscn
[node name="TitleScreen" parent="." instance=ExtResource("...")]  # title_screen.tscn
```

The existing StatusBar remains at layer 128; TitleScreen is at layer 129.

### Modified Script: `gdscripts/main.gd`

**Changes to `_ready()`:**
- Remove `call_deferred("_load_starting_scene")` — do NOT call scene load at startup
- Keep all existing signal connections (StateSystem, StatusBar, DialogueDisplay3D)
- Add TitleScreen signal connection:
```gdscript
@onready var title_screen: CanvasLayer = $TitleScreen

func _ready() -> void:
    # ... all existing signal connections remain ...
    
    # Connect title screen start signal
    if title_screen != null and title_screen.has_signal("start_requested"):
        title_screen.start_requested.connect(_on_title_start_requested)
    
    # REMOVED: call_deferred("_load_starting_scene")
```

**New handler method:**
```gdscript
func _on_title_start_requested(fade_duration: float) -> void:
    if scene_manager != null and is_instance_valid(scene_manager):
        scene_manager.trigger_scene_change("res://scenes/office/office.tscn", fade_duration)
    else:
        get_tree().change_scene_to_file("res://scenes/office/office.tscn")
```

**Keep `_load_starting_scene()` as a fallback method:**
```gdscript
func _load_starting_scene() -> void:
    get_tree().change_scene_to_file("res://scenes/office/office.tscn")
```

### Resource / Config Changes

**Autoload & Input Map:** No changes needed.

---

## 4. API Contracts

### Signal Connections

| Source | Signal | Target | Handler | Purpose |
|--------|--------|--------|---------|---------|
| `TitleScreen` | `start_requested(fade_duration)` | `Main` | `_on_title_start_requested(fade_duration)` | Player pressed Space — trigger scene transition |
| `StateSystem` | `state_changed(Dictionary)` | `StatusBar` | `_on_state_changed(Dictionary)` | Existing — status bar updates |
| `StateSystem` | `state_changed(Dictionary)` | `Main` | `_on_state_changed(Dictionary)` | Existing — debug/log |

### Method Call Chains

```
TitleScreen._ready()
    ├── _configure_labels()      — set text, colors, font
    ├── _configure_background()  — set GradientTexture2D
    └── _start_pulse_tween()     — start pulsing modulate animation

TitleScreen._input(event)
    ├── is_action_pressed("ui_accept" or "dialogue_select")
    ├── emit_signal("start_requested", fade_duration)
    ├── set_process_input(false)
    └── get_viewport().set_input_as_handled()

Main._on_title_start_requested(fade_duration)
    ├── (if SceneManager exists)
    │   └── scene_manager.trigger_scene_change("res://scenes/office/office.tscn", fade_duration)
    └── (else — fallback)
        └── get_tree().change_scene_to_file("res://scenes/office/office.tscn")
```

### Input Action Contracts

| Action | Key | Handled By | Stage |
|--------|-----|------------|-------|
| `ui_accept` | Enter | `TitleScreen._input()` | Title screen visible |
| `dialogue_select` | Space | `TitleScreen._input()` | Title screen visible |
| All other actions | — | Main._input() (unchanged) | Title screen visible (no game scene loaded) |
| All actions | — | Office scene handlers | After scene change (TitleScreen unloaded) |

**Input conflict analysis:**
- Title screen consumes Space/Enter via `get_viewport().set_input_as_handled()`
- `Main._input()` still receives other events (arrow keys) but they have no visible effect since no scene is loaded
- After `change_scene_to_file()`, the TitleScreen and Main nodes are fully unloaded
- The office scene's own input handling takes over cleanly

---

## 5. Test Case Descriptions

All test case descriptions — implement agent writes runnable tests.

### Test File: `tests/test_title_screen.gd`

Headless-capable unit tests for TitleScreen logic (scene-required tests marked separately).

### Normal Path Tests (>=2)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC1 | Title screen shows on launch | Game launches, main.tscn loads, TitleScreen is visible | TitleLabel text == "Urban Night Walker", SubtitleLabel text == "都市夜行者", StartPrompt text == "Press Space to Start" | `assert(title_screen._title_label.text == "Urban Night Walker")`, `assert(title_screen._subtitle_label.text == "都市夜行者")`, `assert(title_screen._prompt_label.text == "Press Space to Start")` |
| TC2 | Pressing Space emits start_requested signal | TitleScreen visible, simulate `ui_accept` action press | `start_requested` signal emitted with `fade_duration == 0.5` | Connect test listener, `assert(signal_received)` and `assert(fade_duration == 0.5)` |
| TC3 | StartPrompt pulsing animation starts on _ready | TitleScreen._ready() called | StartPrompt modulate.a oscillates between ~0.4 and ~1.0 over time | After 1.5s: `assert(start_prompt.modulate.a < 1.0)` changed from initial value |

### Boundary / Edge Case Tests (>=3)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC4 | Pressing Enter also triggers start | Simulate `dialogue_select` action press (Space key) | `start_requested` emitted (same handler handles both `ui_accept` and `dialogue_select`) | `assert(signal_received)`, `assert(fade_duration == 0.5)` |
| TC5 | Double Space press does not double-emit | Press Space twice rapidly | `start_requested` emitted only once | `assert(signal_count == 1)` |
| TC6 | Space press after start does nothing (graceful) | Press Space, wait 0.1s, press Space again | Second press ignored — `set_process_input(false)` after first emission | `assert(signal_count == 1)` |
| TC7 | Gradient background renders correctly | TitleScreen._ready() called | Background ColorRect has `texture` of type `GradientTexture2D`, with correct top/bottom colors | `assert(background.texture is GradientTexture2D)`, colors match `BG_COLOR_TOP` / `BG_COLOR_BOTTOM` |
| TC8 | Very long or short window sizes | Simulate aspect ratios: 21:9 (2560x1080), 4:3 (1440x1080), 16:10 (1920x1200) | Labels remain centered, no text clipped outside label bounds | Visual inspection OR `assert(label_position_ratio ≈ target)` within tolerance |
| TC9 | UIConfig missing gracefully degrades | TitleScreen._ready() with no `/root/UIConfig` autoload | No crash, falls back to base font sizes (48/32/18) | `assert(no errors)` |

### Failure Path Tests (>=1)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC10 | SceneManager unavailable at start | Main._on_title_start_requested() called when `scene_manager == null` | Falls back to `get_tree().change_scene_to_file()` directly — no crash, scene transition occurs | `assert(scene changed)` — office.tscn becomes current scene |
| TC11 | GradientTexture2D creation fails | Simulated failure in _configure_background() | Background ColorRect has no texture, uses solid `color` fallback | `assert(background.texture == null)` — still functional |
| TC12 | TitleScreen node missing from main.tscn | Main._ready() when `$TitleScreen` returns null | Graceful — no crash; Main falls back to call `_load_starting_scene()` | `assert(scene changed)` — office.tscn loads directly (current behavior) |
| TC13 | Input handled during fade transition | Press Space while SceneManager is already fading | Second press ignored because `set_process_input(false)` was set | `assert(signal_count == 1)`, `assert(transition_in_progress == true)` |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Title screen display | ✅ (TC1) | >=2 (TC7, TC8) | ✅ (TC11, TC12) |
| Start input handling | ✅ (TC2, TC3) | >=2 (TC4, TC5, TC6) | ✅ (TC13) |
| Scene transition | ✅ (TC2) | >=1 (TC5) | ✅ (TC10) |
| UIConfig integration | — | ✅ (TC9) | ✅ (TC9) |

---

## 6. Files Changed

### New Files

| Layer | File | Change | Est. Lines |
|-------|------|--------|-----------|
| Script (New) | `gdscripts/title_screen.gd` | New CanvasLayer controller: display, animation, input | +120 |
| Scene (New) | `scenes/ui/title_screen.tscn` | New scene: Background ColorRect, TitleLabel, SubtitleLabel, StartPrompt | +40 |

### Modified Files

| Layer | File | Change | Est. Lines |
|-------|------|--------|-----------|
| Script (Mod) | `gdscripts/main.gd` | Remove `call_deferred("_load_starting_scene")`, add TitleScreen @onready + signal connection + handler | +/-15 |
| Scene (Mod) | `scenes/main.tscn` | Add TitleScreen instance as child of root node | +3 |
| Test (New) | `tests/test_title_screen.gd` | Test descriptions for title screen display and input (implement agent fills in) | +80 |

**Total estimated: ~258 lines**

---

## 7. Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI approach | A: CanvasLayer Title Screen | Per PRD recommendation — simplest, most reliable, reuses existing CanvasLayer pattern |
| CanvasLayer layer | 129 (above StatusBar at 128) | Ensures title screen renders on top; StatusBar becomes visible naturally after scene change |
| Start input | Space AND Enter (ui_accept + dialogue_select) | Maximum accessibility; both GamePad A-button (ui_accept) and keyboard Space (dialogue_select) work |
| Pulse animation | modulate alpha tween, 2s period, ease-in-out | Simple, reliable, no shader overhead; visually communicates "interactable" |
| Title text format | English primary + Chinese subtitle | Game title is bilingual; both are displayed to establish the game's bilingual identity |
| Background | Code-constructed GradientTexture2D | No external resource dependency; falls back to solid color if gradient fails |
| Scene loading fallback | Yes (Main._load_starting_scene() kept) | If TitleScreen is missing, game still boots to office.tscn — graceful degradation |
| Font integration | Optional UIConfig query | If UIConfig exists, font scales responsively; if not, hardcoded sizes work fine |
| Skip timer | None | Player must deliberately press Space — meets AC requirement |

---

## 8. Verification Checklist

- [ ] Title screen displays on game launch: "Urban Night Walker" title, "都市夜行者" subtitle, "Press Space to Start" prompt
- [ ] Title screen has dark gradient background (dark blue-black to night blue)
- [ ] StartPrompt text pulses (modulate alpha 0.4 -> 1.0 -> 0.4, ~2s cycle)
- [ ] Pressing Space triggers `start_requested` signal emission
- [ ] Pressing Enter also triggers start (ui_accept action)
- [ ] Rapid double-press emits start_requested only once (no double-fire)
- [ ] `Main._on_title_start_requested()` calls `SceneManager.trigger_scene_change()` or fallback
- [ ] Scene transitions: fade-out (0.5s) -> office.tscn loads -> fade-in (0.5s)
- [ ] Title screen is fully unloaded after scene change (no leftover labels or CanvasLayer)
- [ ] StatusBar appears correctly after scene change (was behind TitleScreen at layer 128, now visible)
- [ ] All existing input handling (dialogue, player movement) works in office scene — no interference
- [ ] Title screen degrades gracefully if SceneManager is unavailable (falls back to direct scene load)
- [ ] Title screen degrades gracefully if TitleScreen node is missing from main.tscn (falls back to direct scene load)
- [ ] Title screen degrades gracefully if UIConfig is missing (hardcoded font sizes)
- [ ] No new input map actions added — existing `ui_accept` and `dialogue_select` reused
- [ ] No new autoload registrations needed
- [ ] Existing `test_dialogue_engine.gd` and `test_game_state.gd` tests still pass (regression check)
