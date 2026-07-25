# Design: #226 — 场景间导航系统实现 (Scene Navigation System Implementation)

> Parent Issue: #226
> Agent: game-plan-agent
> Date: 2026-07-25
> Approach: C — 混合模式（环境引导为主 + 条件性文本辅助）
> Foundation: #221 (Research — Scene Navigation Mechanism, merged PR #258)

---

## 1. Architecture Overview

### 1.1 Current State vs Target State

Issue #226 implements the **remaining components** of the Scene Navigation System on top of the infrastructure already delivered by #221 (PR #258, merged).

**Already built (#221 delivered):**

| Component | Status | Delivered |
|-----------|--------|-----------|
| `scene_title_overlay.gd` | ✅ Complete | Scene title card with fade animations, Chinese display names, route_context |
| `nav_fallback.gd` | ✅ Complete | Height fall detection, stuck detection, fallback loop protection |
| `scene_manager.gd` | ✅ Extended | `trigger_zone_transition()`, `_show_title_overlay()`, NavigationContext handling |
| `exit_zone.gd` | ✅ Extended | `exit_label`, `route_hint` exports, NavigationContext propagation in `_transition()` |
| `game_manager.gd` | ✅ Extended | `navigation_context` dict, `fallback_count` counter |
| `player_controller.gd` | ✅ Extended | `navigate_hint` input (H key), `navigation_hint_requested` signal, `is_navigation_disabled` flag |
| `constants.gd` | ✅ Extended | All navigation constants (NAV_STAY_THRESHOLD, NAV_STUCK_DURATION, etc.) |

**Remaining to implement (#226 scope):**

| Component | Status | Action |
|-----------|--------|--------|
| `navigation_controller.gd` | ❌ New file | Create per-scene navigation orchestrator |
| `scene_base.gd` | ⚠️ Partial | Add `_setup_navigation()`, virtual methods, navigation wiring |
| Scene subclass overrides | ❌ 7 files | Add `_on_condition_text_updated()`, hint text, env guidance |
| Per-scene TSCN config | ❌ 7 scenes | ExitZone placement, environmental lighting, guidance text |
| H-key hint text data | ❌ New resource | Per-scene, per-tone hint text dictionary |

### 1.2 System Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                      NavigationController                       │
│                    (NEW — per-scene child node)                  │
│                                                                  │
│  ┌─────────────────────┐  ┌─────────────────┐  ┌────────────┐  │
│  │ Condition Detection  │  │  H-Key Hint     │  │ Exit Scan  │  │
│  │  • Stay >60s timer   │  │  • Cooldown 8s  │  │ • Nearest  │  │
│  │  • Wrong dir >30s    │  │  • Tone-aware   │  │   ExitZone │  │
│  │  • Stuck detection   │  │    hint text    │  │ • Facing   │  │
│  │  • Height fall check │  │                 │  │   check    │  │
│  └────────┬────────────┘  └────────┬────────┘  └──────┬─────┘  │
│           │                        │                   │        │
└───────────┼────────────────────────┼───────────────────┼────────┘
            │                        │                   │
            ▼                        ▼                   ▼
┌───────────────────────┐  ┌───────────────────┐  ┌────────────────┐
│   SceneBase._ready()  │  │ PlayerController  │  │   ExitZone     │
│  • Wires NavController│  │  • H-key → signal │  │  • exit_label  │
│  • Connects signals   │  │  • navigation_    │  │  • route_hint  │
│  • Calls _setup_nav   │  │    hint_requested │  │  • Navigation- │
│                       │  │                   │  │    Context     │
└───────────────────────┘  └───────────────────┘  └────────────────┘
            │                                                │
            ▼                                                ▼
┌───────────────────────┐                          ┌────────────────┐
│  Scene Subclass .gd   │                          │  GameManager   │
│  • override _on_      │                          │  (autoload)    │
│    condition_text_    │                          │  • navigation_ │
│    updated(hint)      │                          │    context     │
│  • override _show_    │                          │  • fallback_   │
│    navigation_hint()  │                          │    count       │
└───────────────────────┘                          └────────────────┘
```

### 1.3 Component Responsibilities

| Component | Type | Responsibility |
|-----------|------|---------------|
| `NavigationController` | **NEW** (Node) | Per-scene navigation orchestrator. Condition timers (stay >60s, wrong dir >30s), stuck detection, H-key hint routing, nearest-exit scanning |
| `SceneBase` | **MODIFIED** | Add `_setup_navigation()`, `@export scene_title_chinese`, `navigation_controller` @onready, virtual `_show_navigation_hint()`, `_on_condition_text_updated()` |
| Scene subclasses (7) | **MODIFIED** | Override `_on_condition_text_updated()` for per-scene environmental text updates; `_configure_environmental_text()` extended for navigation hints |
| Per-scene TSCN files (7) | **MODIFIED** | ExitZone placement near exits, environmental light sources, guidance text nodes |

---

## 2. New Component — NavigationController (Detailed Design)

### File: `gdscripts/navigation_controller.gd`

### Node Structure
```
NavigationController (Node)
  ├── StayTimer (Timer — 60s one-shot, auto-start)
  ├── HintCooldownTimer (Timer — 8s one-shot)
  └── StuckTimer (float — frame-accumulated, not a Timer node)
```

### Signals
```gdscript
signal navigation_hint_requested(text: String)      # H-key pressed → hint text
signal fallback_triggered(reason: String)            # "fell" or "stuck"
signal condition_text_updated(direction_hint: String) # Stay/wrong-dir triggered text
```

### State Properties
```gdscript
var _stay_triggered: bool = false      # One-shot: stay text already shown
var _wrong_dir_triggered: bool = false  # One-shot: wrong-dir text already shown
var _player: Node = null                # Reference set by SceneBase
var _spawn_point: Vector3 = Vector3.ZERO
var _hint_cooldown: float = 0.0         # Seconds remaining before next H-key hint
var _stuck_timer: float = 0.0           # Frame-accumulated stuck seconds
var _wrong_dir_timer: float = 0.0       # Frame-accumulated wrong-direction seconds
var _stay_timer: float = 0.0            # Frame-accumulated stay seconds
var _last_player_pos: Vector3           # Previous frame position (for velocity calc)
var _is_fallbacking: bool = false       # Guard against re-entrant fallback
```

### Key Methods

```gdscript
func _setup(player: Node, spawn_point: Vector3) -> void
    # Called by SceneBase._setup_navigation()
    # Sets player reference, spawn point, resets all timers and one-shot flags

func _physics_process(delta: float) -> void
    # Every frame (only if _player assigned):
    # 1. If dialogue_active → reset stuck/wrong_dir timers, skip checks
    # 2. _stay_timer += delta
    # 3. Check velocity (from _last_player_pos / delta) → update _stuck_timer
    # 4. Update _last_player_pos
    # 5. If _stay_timer > NAV_STAY_THRESHOLD and not _stay_triggered →
    #      emit condition_text_updated(_get_stay_warning_text())
    #      _stay_triggered = true
    # 6. Check facing direction → update _wrong_dir_timer
    #    If _wrong_dir_timer > NAV_WRONG_DIR_THRESHOLD and not _wrong_dir_triggered →
    #      emit condition_text_updated(_get_wrong_dir_text())
    #      _wrong_dir_triggered = true
    # 7. If _stuck_timer > NAV_STUCK_DURATION → emit fallback_triggered("stuck")
    # 8. If _player.global_position.y < NAV_FALLBACK_Y_THRESHOLD →
    #      emit fallback_triggered("fell")

func _player_velocity() -> Vector3
    # Returns velocity from _last_player_pos delta, or player.velocity if available
    # Used for stuck detection when CharacterBody3D.velocity may be stale

func _check_facing_exit() -> bool
    # Casts ray forward from player to check distance to nearest ExitZone
    # Returns true if facing an ExitZone within 10m
    # Used to reset _wrong_dir_timer when player corrects direction

func _get_nearest_exit_zone() -> Area3D
    # Iterates scene children for ExitZone instances
    # Returns the nearest by distance (or null if none found)

func _handle_hint_key() -> void
    # Called when navigation_hint_requested signal received from PlayerController
    # If _hint_cooldown > 0: return
    # Get tone-aware hint text from _get_hint_text()
    # Emit navigation_hint_requested with text
    # Set _hint_cooldown to NAV_HINT_COOLDOWN

func _get_hint_text() -> String
    # Returns tone-aware hint text based on current scene's tone
    # Queries NarrativeManager._calculate_tone_for_scene() via get_node("/root/NarrativeManager")
    # Uses per-scene HINT_TEXT_TEMPLATES dictionary (defined in NavigationController as const)

func _get_stay_warning_text() -> String
    # Returns scene-specific "you've been here a while" text
    # Falls back to generic: "You've been here a while. / The exit is somewhere."

func _get_wrong_dir_text() -> String
    # Returns scene-specific "face the right direction" text
    # Falls back to generic: "Maybe the other way. / Try turning around."

func _clear_timers() -> void
    # Called when player leaves scene normally (via SceneBase._exit_tree)
    # Resets all timers and one-shot flags
```

### H-Key Hint Text Templates

Defined as a `const` dictionary in NavigationController, keyed by scene_id → tone → hint_text:

```gdscript
const HINT_TEXT_TEMPLATES: Dictionary = {
    "office": {
        "despair":    "The door is ahead. / Go outside. / Nothing else.",
        "low":        "The door. / Still there. / Same as before.",
        "neutral":    "The door is ahead. / Go outside.",
        "buoyant":    "The door. / Outside is waiting. / Come on.",
        "hope":       "The door. / The city is waiting. / Let's go.",
    },
    "lobby": {
        "fear":       "Not that way. / Maybe stay.",
        "uneasy":     "Is this the right way? / Hard to tell.",
        "neutral":    "The stranger points. / That door.",
        "curious":    "That door. / See what's there.",
        "defiant":    "The stranger. / That door. / Keep walking.",
    },
    "convenience_store": {
        "cold":       "Back door glows. / Both ways go.",
        "distant":    "Doesn't matter. / Any direction.",
        "neutral":    "The back door glows. / Keep going.",
        "warm":       "Warm light ahead. / Keep walking.",
        "glowing":    "The light is warm. / Go toward it.",
    },
    "bridge": {
        "tired":      "One more span. / Then rest.",
        "heavy":      "The door is heavy. / Push through.",
        "neutral":    "The other side. / City lights ahead.",
        "hopeful":    "Light ahead. / Come see.",
        "determined": "This way. / No question.",
    },
    "underpass": {
        "despair":    "Keep going. / Nothing else to do.",
        "hollow":     "That way. / Or stay.",
        "neutral":    "The exit light. / Almost there.",
        "resolute":   "This way. / No question.",
        "transcendent": "The exit is there. / You know it.",
    },
    "subway_station": {
        "backward":   "Back. / That's the way.",
        "hesitant":   "Maybe here. / Maybe not.",
        "waiting":    "The bench is dry. / No rush.",
        "forward":    "The train is coming. / Get on.",
    },
}

const GENERIC_HINT: String = "The exit is nearby. / Look around."
```

---

## 3. Existing Component Modifications

### 3.1 SceneBase — Navigation System Wiring

**File:** `gdscripts/scene_base.gd`

| Change | Details |
|--------|---------|
| New `@export` | `scene_title_chinese: String = ""` — Chinese scene name |
| New `@onready` | `navigation_controller: Node = $NavigationController` |
| Modified `_ready()` | Add `_setup_navigation()` call after existing init chain |
| New method | `func _setup_navigation() -> void` — wire NavigationController |
| New virtual method | `func _show_navigation_hint(text: String) -> void` — display hint text |
| New virtual method | `func _on_condition_text_updated(hint: String) -> void` — handle condition triggers |
| Modified `_exit_tree()` | Add navigation state cleanup |

```gdscript
# Modified _ready() — call chain:
func _ready() -> void:
    if scene_manager and scene_manager.has_method("fade_in"):
        scene_manager.fade_in()
    _instantiate_player()
    _configure_environmental_text()
    _configure_ambient_audio()
    _connect_state_signals()
    _setup_navigation()  # NEW
    _restore_dialogue_state()

# New: Wire NavigationController
func _setup_navigation() -> void:
    # Create NavigationController if not present in scene
    var nav := get_node_or_null("NavigationController")
    if not nav:
        nav = preload("res://gdscripts/navigation_controller.gd").new()
        nav.name = "NavigationController"
        add_child.call_deferred(nav)
        # Wait one frame for _ready
        await get_tree().process_frame
    
    nav = get_node_or_null("NavigationController")
    if not nav or not nav.has_method("_setup"):
        return
    
    # Get player reference
    if _player and is_instance_valid(_player):
        nav._setup(_player, _get_player_spawn_position())
    
    # Connect signals
    if nav.has_signal("fallback_triggered"):
        # Route fallback to existing NavFallback or handle directly
        nav.fallback_triggered.connect(_on_player_fell)
    
    if nav.has_signal("navigation_hint_requested"):
        nav.navigation_hint_requested.connect(_show_navigation_hint)
    
    if nav.has_signal("condition_text_updated"):
        nav.condition_text_updated.connect(_on_condition_text_updated)

# New virtual: H-key hint display (override in subclasses)
func _show_navigation_hint(text: String) -> void:
    # Default: print to console
    # Subclasses override with CanvasLayer or Label3D display
    print("[NavHint] ", text)

# New virtual: condition-triggered text (override in subclasses)
func _on_condition_text_updated(hint: String) -> void:
    # Default: no-op
    # Subclasses update environmental text nodes with hint text
    pass
```

### 3.2 Scene Manager — Minor Extension

**File:** `gdscripts/scene_manager.gd`

| Change | Details |
|--------|---------|
| Modified `_show_title_overlay()` | Accept optional `scene_title_chinese` from SceneBase export |

### 3.3 ExitZone — No Changes Needed

Already exports `exit_label` and `route_hint`. No additional changes required.

### 3.4 GameManager — No Changes Needed

`navigation_context` and `fallback_count` already present. No additional changes required.

### 3.5 Scene Subclasses — Per-Scene Navigation Extensions

Each scene subclass (office.gd, lobby.gd, street.gd, store.gd, bridge.gd, underpass.gd, subway_station.gd) needs two new Method overrides and potentially config updates:

#### Pattern: `_on_condition_text_updated(hint)`

```gdscript
# Example: street.gd — override to update environmental text
func _on_condition_text_updated(hint: String) -> void:
    # Temporarily override environmental text with hint
    if graffiti and is_instance_valid(graffiti):
        graffiti.text = hint
        # Revert after 5 seconds to tone-appropriate text
        await get_tree().create_timer(5.0).timeout
        if is_instance_valid(graffiti):
            _set_graffiti_text(_get_tone_for_scene(scene_id))
```

#### Pattern: `_show_navigation_hint(text)`

```gdscript
# Example: street.gd — display hint via CanvasLayer
func _show_navigation_hint(text: String) -> void:
    var hint_label := _get_or_create_hint_label()
    hint_label.text = text
    hint_label.modulate = Color(1, 1, 1, 0)
    var tween := create_tween()
    tween.tween_property(hint_label, "modulate", Color(1, 1, 1, 1), 0.3)
    tween.tween_interval(NAV_HINT_DISPLAY_DURATION)
    tween.tween_property(hint_label, "modulate", Color(1, 1, 1, 0), 0.5)
```

---

## 4. Per-Scene Configuration

### 4.1 ExitZone Placement

Each scene requires ExitZone placement near exits. The `exit_label` and `route_hint` exports should be configured per scene:

| Scene | Exit | ExitZone Position | exit_label | route_hint |
|:-----:|:----:|:-----------------:|:-----------|:-----------|
| office | Main door | Near door Area3D | "街道" | "The door opens to the street." |
| lobby | Side door | Near side door | "街道" | "The street beyond." |
| lobby | Office door (back) | Near office door | "办公室" | "Back where you started." |
| street | Store entrance | Near store door | "便利店" | "Store light glows ahead." |
| store | Back door | Near back exit | "天桥" | "Bridge access. City beyond." |
| store | Street exit | Near street door | "街道" | "Back to the street." |
| bridge | Far end | At far end | "地下通道" | "The underpass." |
| bridge | Near end | At near end | "便利店" | "Back to the store." |
| underpass | Far end | At far end | "地铁站" | "Subway station ahead." |
| underpass | Near end | At near end | "天桥" | "Back to the bridge." |
| subway_station | Platform gate | At gate | — | "Last stop." |

### 4.2 Environmental Guidance Configuration

Per-scene lighting and text guidance:

| Scene | Light Source | Guidance Text | Implementation |
|:-----:|:------------|:--------------|:--------------|
| office | OmniLight3D at door crack | EXIT sign label | Existing `door_trigger` area; add OmniLight3D child |
| lobby | OmniLight3D at side door | Direction text | Existing `exit_trigger` area; add light + text |
| street | OmniLight3D at store entrance | Directional graffiti update | Modify `_set_graffiti_text()` for direction hints |
| store | OmniLight3D at back door (green tint) | Back door text | New text node near back exit |
| bridge | OmniLight3D at far end (warm) | Direction text update | Modify `_set_environment_text()` for direction hints |
| underpass | OmniLight3D at far end (growing) | Exit text | New text node at exit point |
| subway_station | OmniLight3D at platform gate | Gate text update | Modify `_set_environment_text()` for guidance |

### 4.3 Stay/Wrong-Dir Warning Text

| Scene | Stay Warning (>60s) | Wrong Direction (>30s) |
|:-----:|:-------------------:|:----------------------:|
| office | "You've been here a while. / The door is still there." | "The door is behind you. / Turn around." |
| lobby | "The lobby echoes. / You've been standing here." | "That's the wall. / The exit is the other way." |
| street | "Rain keeps falling. / Stores are closed." | "Store is that way. / Or back the way you came." |
| convenience_store | "The hum of the cooler. / You've been browsing long." | "Back door is behind. / Street exit ahead." |
| bridge | "Wind picks up. / The bridge shakes slightly." | "City lights are that way. / Turn." |
| underpass | "Tunnel breathes. / Still." | "Exit light is the other end. / Walk toward it." |
| subway_station | "The platform is empty. / Train hasn't come." | "Gate is behind you. / Platform ahead." |

---

## 5. Data Flow

### 5.1 Scene Transition with Navigation Context (Happy Path)

```
Player walks into ExitZone
  → ExitZone._on_body_entered()
    → ExitZone sets GameManager:
      ├─ target_spawn_point = zone.spawn_point
      └─ navigation_context = {exit_label, route_hint, next_scene_id}
    → ExitZone._transition()
      → SceneManager.trigger_zone_transition(target_scene)
        → SceneManager._show_title_overlay()  [displays scene title card]
        → fade_out (0.5s) [title card visible during fade]
        → change_scene_to_file(target_scene)
        → NEW scene _ready():
          ├─ SceneManager.fade_in() [0.5s — title card remains visible]
          ├─ _instantiate_player() at target_spawn_point
          ├─ _configure_environmental_text()
          ├─ _configure_ambient_audio()
          ├─ _connect_state_signals()
          ├─ _setup_navigation()
          │   ├─ Creates NavigationController child node
          │   ├─ Passes player reference and spawn point
          │   └─ Connects fallback_triggered, navigation_hint_requested, condition_text_updated
          └─ SceneTitleOverlay auto-dismisses after NAV_TITLE_DISPLAY_DURATION
```

### 5.2 H-Key Hint Flow

```
Player presses H
  → PlayerController._input(): "navigate_hint" action detected
    → emit navigation_hint_requested signal
  → NavigationController (connected via _setup_navigation)
    → Check _hint_cooldown > 0? Return
    → Determine tone for current scene (query NarrativeManager)
    → Look up HINT_TEXT_TEMPLATES[scene_id][tone]
    → Fallback: GENERIC_HINT if tone not found
    → Emit navigation_hint_requested(hint_text)
  → SceneBase._show_navigation_hint(hint_text)
    → Scene subclass displays text via CanvasLayer or existing text node
    → Auto-dismiss after NAV_HINT_DISPLAY_DURATION seconds
```

### 5.3 Condition-Triggered Text Flow

```
NavigationController._physics_process() [every frame]:
  ├─ _stay_timer > NAV_STAY_THRESHOLD and not _stay_triggered?
  │     → _stay_triggered = true
  │     → emit condition_text_updated(_get_stay_warning_text())
  │
  ├─ _check_facing_exit() returns false for > NAV_WRONG_DIR_THRESHOLD
  │   and not _wrong_dir_triggered?
  │     → _wrong_dir_triggered = true
  │     → emit condition_text_updated(_get_wrong_dir_text())
  │
  └─ If _check_facing_exit() returns true (player corrects direction):
        → Reset _wrong_dir_timer, _wrong_dir_triggered

SceneBase._on_condition_text_updated(hint):
  → Subclass override updates environmental text node
  → Text auto-reverts after 5 seconds to tone-appropriate text
```

### 5.4 Fallback Flow (delegated to existing NavFallback)

```
NavigationController detects height fall (< -10) OR stuck (>3s near-zero velocity)
  → emit fallback_triggered(reason)
  → SceneBase._on_player_fell(reason) → existing fallback logic:
    → NavFallback._trigger_fallback()
      → Quick fade (0.3s) → teleport to spawn point → fade in (0.3s)
      → Fallback counter protection: 3 max → title_screen.tscn
```

---

## 6. Edge Cases & Error Handling

| Edge Case | Mitigation |
|-----------|------------|
| **Player enters scene from ExitZone spawn — immediate re-trigger** | ExitZone monitoring deferred 0.5s via `await create_timer(0.5)` in _ready() |
| **Player in dialogue when H pressed** | PlayerController blocks `navigate_hint` if `_dialogue_active == true` |
| **Rapid H-key spam** | `_hint_cooldown` (NAV_HINT_COOLDOWN = 8.0s) prevents re-trigger |
| **No ExitZone in scene (e.g., subway_station)** | `_get_nearest_exit_zone()` returns null; wrong-dir detection disabled gracefully |
| **Tone not in HINT_TEXT_TEMPLATES** | Falls back to GENERIC_HINT for unknown tones |
| **NavigationController not yet ready on first frame** | `call_deferred` + `await process_frame` for add_child |
| **SpawnPoint is also broken (fallback loop)** | `fallback_count` ≥ 3 → force title_screen.tscn (already handled by NavFallback) |
| **Player intentionally stands still** | Stuck detection only triggers after 3s near-zero velocity; if player is in dialogue, stuck timer resets |
| **Condition triggers fire on every scene re-entry** | One-shot flags (`_stay_triggered`, `_wrong_dir_triggered`) reset on `_clear_timers()` called by SceneBase._setup_navigation() |
| **Scene loaded without NavigationController** | SceneBase._setup_navigation() auto-creates NavigationController as child; no-op if `enable_navigation` is false |
| **ExitZone placed with empty exit_label** | Title overlay shows scene name from SceneTitleOverlay._get_scene_display_name() as fallback |

---

## 7. File Manifest

### New Files

| File | Purpose |
|------|---------|
| `gdscripts/navigation_controller.gd` | Per-scene navigation orchestrator — condition timers, H-key hint routing, nearest-exit scan |

### Modified Files

| File | Changes |
|------|---------|
| `gdscripts/scene_base.gd` | Add `_setup_navigation()`, `_show_navigation_hint()`, `_on_condition_text_updated()` virtual methods, `@export scene_title_chinese`, navigation signal wiring |
| `gdscripts/office.gd` | Override `_on_condition_text_updated(hint)` — temporarily update window_text; override `_show_navigation_hint(text)` — display hint |
| `gdscripts/lobby.gd` | Override `_on_condition_text_updated(hint)` — update entrance_text; override `_show_navigation_hint(text)` |
| `gdscripts/street.gd` | Override `_on_condition_text_updated(hint)` — update graffiti_text; override `_show_navigation_hint(text)` |
| `gdscripts/store.gd` | Override `_on_condition_text_updated(hint)` — update open_sign; override `_show_navigation_hint(text)` |
| `gdscripts/bridge.gd` | Override `_on_condition_text_updated(hint)` — update environment text nodes; override `_show_navigation_hint(text)` |
| `gdscripts/underpass.gd` | Override `_on_condition_text_updated(hint)` — update graffiti_text/echo_text; override `_show_navigation_hint(text)` |
| `gdscripts/subway_station.gd` | Override `_on_condition_text_updated(hint)` — update environment text; override `_show_navigation_hint(text)` |

### No Changes Needed (already delivered by #221)

- `gdscripts/scene_manager.gd` — trigger_zone_transition(), _show_title_overlay() already implemented
- `gdscripts/exit_zone.gd` — exit_label, route_hint, navigation_context already exported
- `gdscripts/game_manager.gd` — navigation_context, fallback_count already present
- `gdscripts/player_controller.gd` — navigate_hint binding, navigation_hint_requested signal already present
- `gdscripts/nav_fallback.gd` — fallback detection and teleport already implemented
- `gdscripts/scene_title_overlay.gd` — title card CanvasLayer already implemented
- `gdscripts/constants.gd` — navigation constants already defined

---

## 8. Implementation Phases

| Phase | Priority | Components | Files | Estimate |
|:-----:|:--------:|-----------|:-----:|:--------:|
| **Phase 1** | **P0** | `NavigationController` — core: condition timers, hint routing, nearest-exit scan, H-key handling | 1 new file | 1.5 days |
| **Phase 2** | **P0** | `SceneBase` — nav wiring: `_setup_navigation()`, signal connections, virtual methods | 1 modified file | 0.5 day |
| **Phase 3** | **P0** | Scene subclass overrides — `_on_condition_text_updated()`, `_show_navigation_hint()` per scene | 7 modified files | 1 day |
| **Phase 4** | **P0** | Per-scene TSCN config — ExitZone placement, environmental lights, guidance text nodes | 7 scene files | 1 day |

**Total estimate: 4 days (P0: all phases)**

---

## 9. Test Case Descriptions

> Test descriptions only — no runnable test code. These describe scenarios for the implement phase to verify.

### Scenario A: H-Key Navigation Hint (Happy Path)

- **Test A1: H-key shows hint text in office**
  - **Precondition:** Scene = office, player spawned, NavigationController active, tone = neutral
  - **Steps:**
    1. Press H key
    2. Wait up to 0.5s
  - **Expected:** Hint text "The door is ahead. / Go outside." is displayed (via `_show_navigation_hint()`)
  - **Verify:** Hint text visible for ~5 seconds, then auto-fades

- **Test A2: H-key cooldown prevents spam**
  - **Precondition:** Same as A1
  - **Steps:**
    1. Press H → hint appears
    2. Press H again within 8 seconds
  - **Expected:** Second press is ignored (cooldown active)
  - **Verify:** No duplicate hint; timer resets after 8s

- **Test A3: H-key blocked during dialogue**
  - **Precondition:** Dialogue is active
  - **Steps:**
    1. Press H during dialogue
  - **Expected:** H is ignored (PlayerController blocks `navigate_hint` when `_dialogue_active == true`)
  - **Verify:** No navigation_hint_requested signal emitted

- **Test A4: H-key hint text changes with tone**
  - **Precondition:** Scene = office, tone changes from "neutral" to "despair" (via state change)
  - **Steps:**
    1. Press H while tone = neutral → "The door is ahead. / Go outside."
    2. Change state to despair
    3. Press H after cooldown → "The door is ahead. / Go outside. / Nothing else."
  - **Expected:** Hint text reflects current tone
  - **Verify:** Different text output for each tone

### Scenario B: Condition-Triggered Text

- **Test B1: Stay warning triggers at 60s**
  - **Precondition:** Player stands still in any scene, not in dialogue
  - **Steps:**
    1. Wait 60 seconds without moving
  - **Expected:** `condition_text_updated` signal emits with stay-warning text
  - **Verify:** Scene's environmental text node temporarily updated to stay warning
  - **Edge case:** One-shot flag prevents re-trigger on same scene visit

- **Test B2: Wrong-direction trigger at 30s**
  - **Precondition:** Player faces away from nearest ExitZone (>10m or 90° angle)
  - **Steps:**
    1. Face wrong direction for 30 seconds
  - **Expected:** `condition_text_updated` signal emits with wrong-direction text
  - **Verify:** Scene text temporarily updated to wrong-direction hint
  - **Edge case:** Timer resets when player corrects direction (faces exit)

- **Test B3: Dialogue pauses all timers**
  - **Precondition:** Player has been standing for 40 seconds
  - **Steps:**
    1. Enter dialogue
    2. Stay in dialogue for 30 seconds
    3. Exit dialogue
  - **Expected:** Stay timer is at ~40s (not 70s) — dialogue time does not count
  - **Verify:** Condition triggers only fire after 60s of non-dialogue standing

- **Test B4: Scene re-entry resets one-shot flags**
  - **Precondition:** Stay warning already triggered in scene
  - **Steps:**
    1. Leave scene and re-enter
    2. Stand still for 60s again
  - **Expected:** Stay warning fires again (flags reset on scene re-entry)
  - **Verify:** `_stay_triggered` and `_wrong_dir_triggered` are false after `_clear_timers()`

### Scenario C: NavigationController Lifecycle

- **Test C1: NavigationController auto-created**
  - **Precondition:** Scene does not have NavigationController in TSCN
  - **Steps:**
    1. Scene loads
  - **Expected:** SceneBase._setup_navigation() creates NavigationController as child node
  - **Verify:** `$NavigationController` is a valid Node after `_ready()` completes

- **Test C2: NavigationController removed on scene exit**
  - **Precondition:** Scene unloaded normally
  - **Steps:**
    1. Exit scene via ExitZone
  - **Expected:** NavigationController is freed with scene; no orphan nodes
  - **Verify:** No Godot error messages about orphaned nodes

- **Test C3: NavigationController handles missing ExitZone**
  - **Precondition:** Scene has no ExitZone nodes (e.g., subway_station)
  - **Steps:**
    1. Scene loads
    2. H key pressed
  - **Expected:** H-key hint still works (falls back to generic hint text)
  - **Verify:** `_get_nearest_exit_zone()` returns null without errors

### Scenario D: Environmental Guidance Integration

- **Test D1: Scene title card shows Chinese name**
  - **Precondition:** ExitZone triggers transition from street to store
  - **Steps:**
    1. Walk into ExitZone
  - **Expected:** Title card displays "便利店" with route hint "Store light glows ahead."
  - **Verify:** Title card visible during fade-out and fade-in; auto-dismisses after 3s

- **Test D2: Condition text reverts after 5 seconds**
  - **Precondition:** Stay warning triggered, environmental text updated
  - **Steps:**
    1. Wait 5 seconds
  - **Expected:** Text reverts to tone-appropriate environmental text
  - **Verify:** `_on_condition_text_updated()` override's timer reverts correctly

### Scenario E: Edge Case Verification

- **Test E1: Rapid scene re-entry (ExitZone cooldown)**
  - **Precondition:** Office scene, ExitZone near door
  - **Steps:**
    1. Walk through ExitZone → transition starts
    2. Immediately exit back through ExitZone (within 1s)
  - **Expected:** Cooldown prevents re-trigger (1s default)
  - **Verify:** No rapid double-transition

- **Test E2: No crash when ExitZone has empty exit_label**
  - **Precondition:** An ExitZone with `exit_label = ""`
  - **Steps:**
    1. Walk through ExitZone
  - **Expected:** Title card shows scene name from SceneTitleOverlay._get_scene_display_name()
  - **Verify:** Graceful fallback to scene file name

- **Test E3: Stuck detection ignored when player intentionally stands still**
  - **Precondition:** Player standing still (zero velocity)
  - **Steps:**
    1. Wait 4 seconds
  - **Expected:** Stuck timer accumulates but fallback only triggers after 3 consecutive seconds
  - **Verify:** If player moves before 3s, timer resets; no false-positive fallback

- **Test E4: Fallback with fallback_count ≥ 3 forces title screen**
  - **Precondition:** 2 consecutive fallbacks occurred, fallback_count = 2
  - **Steps:**
    1. Trigger third fallback
  - **Expected:** Force load title_screen.tscn
  - **Verify:** `force_title_screen()` is called (already tested via nav_fallback.gd)

---

## 10. Integration Points

| Integration | Component | How |
|-------------|-----------|-----|
| NavigationController → SceneBase | Signal | `fallback_triggered` → `_on_player_fell()` |
| NavigationController → SceneBase | Signal | `navigation_hint_requested` → `_show_navigation_hint()` |
| NavigationController → SceneBase | Signal | `condition_text_updated` → `_on_condition_text_updated()` |
| PlayerController → NavigationController | Signal | `navigation_hint_requested` → `_handle_hint_key()` |
| NarrativeManager → NavigationController | Direct call | `_calculate_tone_for_scene()` for hint text lookup |
| NavigationController → ExitZone | Direct call | `_get_nearest_exit_zone()` iterates scene children |
| SceneBase → GameManager | Property | NavigationContext for title overlay |
| SceneTitleOverlay → SceneManager | Child node | Attached to SceneManager during fade transition |
| NavFallback → GameManager | Property | `fallback_count` for loop protection |
