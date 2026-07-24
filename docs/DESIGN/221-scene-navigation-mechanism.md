# Design: #221 — 场景间导航机制设计 (Scene Navigation Mechanism Design)

> Parent Issue: #221
> Agent: plan-agent
> Date: 2026-07-25
> Approach: C — 混合模式（环境引导为主 + 条件性文本辅助）

---

## 1. Architecture Overview

### 1.1 Design Philosophy

The navigation system follows the Borgesian constraint (B1) — **no explicit arrows, minimaps, or meta-game hints**. Default state is pure environmental guidance. Text assistance only activates under specific conditions (player stuck >60s, wrong direction >30s, or pressing H).

Three-layer expression (L1/L2/L3) is maintained throughout:
- **L1 (Literal):** Scene title cards, ExitZone prompt labels, H-key hint text
- **L2 (Suggestive):** Environmental lighting, NPC posture, environmental text updates
- **L3 (Symbolic):** Rain direction, light quality shifts, hallucination-integrated visual cues

### 1.2 System Architecture Diagram

```
                          ┌─────────────────────────┐
                          │    NavigationController  │
                          │   (新建, 每个场景子节点)   │
                          ├─────────────────────────┤
                          │  • _player_stay_timer    │
                          │  • _wrong_dir_timer      │
                          │  • _stuck_timer          │
                          │  • _last_player_pos      │
                          │  • _fallback_count       │
                          └──────┬──────────────────┘
                                 │
          ┌──────────────────────┼──────────────────────┐
          │                      │                      │
          ▼                      ▼                      ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ SceneTitleOverlay │  │ NavFallback      │  │ ConditionDetector│
│ (新建 CanvasLayer) │  │ (新建 Node)       │  │ (内置于 NavCtrl)  │
├──────────────────┤  ├──────────────────┤  ├──────────────────┤
│ • 场景切换时显示   │  │ • 高度检测(< -10) │  │ • 停留>60s 检测   │
│ • 场景名 + 路线    │  │ • 速度异常检测     │  │ • 错误方向>30s    │
│ • 中/英双语标题    │  │ • H 键临时卡住提示 │  │ • 按 H 键提示     │
│ • 淡入/淡出 0.5s  │  │ • 回退循环防护     │  │ • 卡住检测        │
└──────────────────┘  └──────────────────┘  └──────────────────┘
                                 │
                                 ▼
                    ┌──────────────────────────┐
                    │    Environmental Config   │
                    │   (各场景 SceneBase 子类)   │
                    ├──────────────────────────┤
                    │  • 出口方向光源引导        │
                    │  • 环境文本方向暗示         │
                    │  • NPC 朝向/姿态引导       │
                    │  • 条件触发时文本切换       │
                    └──────────────────────────┘
```

### 1.3 Component Responsibilities

| Component | Type | Responsibility |
|-----------|------|---------------|
| `NavigationController` | 新建 (Node) | Per-scene navigation orchestrator. Attaches to scene root. Manages condition timers, fallback detection, hint key routing. |
| `SceneTitleOverlay` | 新建 (CanvasLayer) | Scene-title card shown during fade transitions. Displays scene name + route context text. Auto-fades with the SceneManager curtain. |
| `NavFallback` | 新建 (Node) | Detects player falling out of bounds or getting stuck. Relocates to SpawnPoint. Fallback counter prevents loops. |
| `ConditionDetector` | 内置 NavigationController | Tracks player stay duration, facing direction, velocity anomalies. Triggers environmental text updates or H-key hint availability. |
| `SceneBase` | 已有 (修改) | Extended to wire NavigationController in `_ready()`. New virtual methods for navigation context. |
| `SceneManager` | 已有 (修改) | Extended: `trigger_zone_transition()` (called by ExitZone), title-card injection during fade. |
| `ExitZone` | 已有 (修改) | Extended: `exit_label` property, route hint metadata carried into NavigationContext. |
| `GameManager` | 已有 (修改) | Added `navigation_context` state, `fallback_count` counter. |

---

## 2. New Components — Detailed Design

### 2.1 NavigationController (新建)

**File:** `gdscripts/navigation_controller.gd`

Attached as a child of each scene root. Manages all navigation-related runtime logic for a single scene.

#### Signals

```gdscript
signal navigation_hint_requested(text: String)    # H-key hint text
signal fallback_triggered(reason: String)           # "fell" or "stuck"
signal condition_text_updated(direction_hint: String)  # Condition-triggered text change
signal environmental_hint_changed(type: String)     # "light_direction", "text_update"
```

#### State Properties

```gdscript
var _stay_timer: float = 0.0          # Seconds player has been in scene
var _wrong_dir_timer: float = 0.0     # Seconds facing wrong direction
var _stuck_timer: float = 0.0         # Seconds with near-zero velocity (non-dialogue)
var _last_player_pos: Vector3          # Previous frame position
var _last_player_direction: Vector3    # Previous frame facing direction
var _hint_cooldown: float = 0.0        # Cooldown between H-key hints
var _hint_key_pressed: bool = false    # Whether H was pressed this frame
var _wrong_dir_triggered: bool = false # Whether wrong-dir text was already shown
var _stay_triggered: bool = false      # Whether stay text was already shown
var _fallback_count: int = 0           # Consecutive fallbacks this scene visit
```

#### Key Methods

```gdscript
func _setup(input_map_hint_key: String = "navigate_hint") -> void
    # Register H-key input binding. Connect to PlayerController signals.
    # Called by SceneBase._ready() before _instantiate_player().

func _physics_process(delta: float) -> void
    # Every frame:
    # 1. If dialogue_active → reset all timers, return
    # 2. Update _stay_timer += delta
    # 3. Check player velocity → update _stuck_timer
    # 4. Check player facing direction → update _wrong_dir_timer
    # 5. If _stay_timer > 60.0 and not _stay_triggered → emit environment update
    # 6. If _wrong_dir_timer > 30.0 and not _wrong_dir_triggered → emit text update
    # 7. If _stuck_timer > 3.0 → trigger fallback("stuck")
    # 8. Check Y position < -10 → trigger fallback("fell")

func _input(event: InputEvent) -> void
    # If event is H-key press → emit navigation_hint_requested with scene hint text

func get_exit_hint_text() -> String
    # Returns route-aware hint text based on NarrativeManager's tone determination.
    # Described in Section 5.

func get_stay_warning_text() -> String
    # Returns the text shown when player has stayed >60s.

func get_wrong_dir_text() -> String
    # Returns the text shown when player faces wrong direction >30s.

func _check_facing_exit() -> bool
    # Raycasts forward from player. If ExitZone is forward within 10m, return true.
    # Used to determine if player's direction is "wrong".

func get_nearest_exit_direction() -> Vector3
    # Scans scene for ExitZone children. Returns direction to nearest exit.
```

#### Input Map Registration

```gdscript
func _register_hint_key() -> void:
    if not InputMap.has_action("navigate_hint"):
        InputMap.add_action("navigate_hint")
    # Clear existing bindings, add H key
    var existing = InputMap.action_get_events("navigate_hint")
    for e in existing:
        InputMap.action_erase_event("navigate_hint", e)
    var ev := InputEventKey.new()
    ev.keycode = KEY_H
    InputMap.action_add_event("navigate_hint", ev)
```

---

### 2.2 SceneTitleOverlay (新建)

**File:** `gdscripts/scene_title_overlay.gd`

A CanvasLayer that displays a scene-title card during fade transitions. Uses the same fade animation pipeline as the FadeCurtain (ColorRect modulate).

#### Node Structure

```
SceneTitleOverlay (CanvasLayer)
├── ColorRect (full-screen, black, modulate.a = 1.0 during fade)
├── TitleLabel (Label — scene name, centered)
├── SubtitleLabel (Label — route context / tone text)
└── AnimationPlayer (fade_in_title, fade_out_title animations)
```

#### Configuration

```gdscript
var scene_id: String = ""              # Set by SceneManager before display
var route_context: String = ""         # Route-aware subtitle text
var display_duration: float = 3.0      # How long title stays visible
var _title_animation_player: AnimationPlayer
```

#### Title Card Content per Scene

Each scene has a Chinese name + route-aware subtitle:

| Scene ID | Chinese Name | Route A (Keep Walking) | Route B (Turn Back) | Route C (Stay) |
|:--------:|:------------:|:---------------------:|:-------------------:|:--------------:|
| office | 办公室 | First step. / The door waits. | Last look. / The window calls. | A pause. / No rush. |
| lobby | 大厅 | The stranger gestures. / Forward. | Turn back? / The stranger's gaze. | Wait. / Watch the rain. |
| convenience_store | 便利店 | Warm light ahead. / Keep walking. | The clerk looks away. / Wrong light. | Stay a while. / The hum settles. |
| bridge | 天桥 | City lights ahead. / One more span. | The bridge goes nowhere. / Turn. | The middle is fine. / Stop here. |
| underpass | 地下通道 | Exit light glows. / Almost there. | Familiar echoes. / Going back. | The tunnel breathes. / No need to rush. |
| subway_station | 地铁站 | The last train. / Choose. | The platform is empty. / Was it always? | The bench is dry. / Wait for nothing. |

All text follows Hemingway constraint: ≤25 chars/sentence, ≤3 sentences/node.

#### Integration with SceneManager Fade Pipeline

```
SceneManager.trigger_scene_change():
  → transition_in_progress = true
  → _fade_curtain fade_out animation starts (0.5s)
  → SceneTitleOverlay show() — title card fades in during curtain fade
  → await _fade_anim.animation_finished
  → change_scene_to_file(target_scene)
  → New scene's SceneManager._setup_fade_curtain()
  → _fade_curtain fade_in animation starts (0.5s)
  → SceneTitleOverlay hide() after display_duration (3.0s)
  → transition_in_progress = false
```

The title overlay is attached to the **old** scene before the transition, so it persists visually during the scene file swap. It self-destructs after display.

---

### 2.3 NavFallback (新建)

**File:** `gdscripts/nav_fallback.gd`

Handles player falling out of bounds or getting stuck in geometry.

#### Detection Methods

| Detection | Condition | Action |
|-----------|-----------|--------|
| Height fall | `player.global_position.y < -10.0` | Fallback teleport |
| Stuck in geometry | `velocity.length() < 0.01` for 3s continuous (non-dialogue) | Fallback teleport |
| Fallback loop protection | 3 consecutive fallbacks within same scene visit | Force reload to title_screen.tscn |

#### Fallback Sequence

```
NavFallback._trigger_fallback(reason: String):
  → var gm = get_node_or_null("/root/GameManager")
  → gm.fallback_count += 1
  → if gm.fallback_count >= 3: → force_title_screen()
  → var sm = get_parent().get_node_or_null("SceneManager")
  → sm.fade_out(0.3)  # Quick fade
  → await sm.fade_completed
  → player.global_position = spawn_point
  → player.velocity = Vector3.ZERO
  → reset all timers on NavigationController
  → Show fallback text (on H-key press or auto-dismiss)
  → sm.fade_in(0.3)
  → After 3s: clear fallback text

fallback_text_examples:
  "fell" → "…刚才有些恍惚？/ 我已经站在这里了。"
  "stuck" → "……/ 这路有点不对劲。/ 换一边走。"
```

All fallback text adheres to Hemingway constraint: ≤25 chars/sentence, ≤3 sentences.

---

## 3. Existing Component Modifications

### 3.1 SceneBase — Extended

```gdscript
# New exports
@export var enable_navigation: bool = true          # Toggle navigation system per-scene
@export var scene_title_chinese: String = ""        # Chinese scene name

# New @onready
@onready var navigation_controller: Node = $NavigationController

# Modified _ready()
func _ready() -> void:
    if scene_manager and scene_manager.has_method("fade_in"):
        scene_manager.fade_in()
    _instantiate_player()
    _configure_environmental_text()
    _configure_ambient_audio()
    _restore_dialogue_state()
    _connect_state_signals()
    _setup_navigation()  # NEW

# New method
func _setup_navigation() -> void:
    if not enable_navigation:
        return
    # Create NavigationController if not already in scene
    var nav := get_node_or_null("NavigationController")
    if not nav:
        nav = load("res://gdscripts/navigation_controller.gd").new()
        nav.name = "NavigationController"
        add_child(nav)
    # Pass scene context
    nav.set("scene_id", scene_id)
    nav.set("spawn_point", _get_player_spawn_position())
    # Connect signals
    if nav.has_signal("fallback_triggered"):
        nav.fallback_triggered.connect(_on_player_fell)
    if nav.has_signal("navigation_hint_requested"):
        nav.navigation_hint_requested.connect(_show_navigation_hint)
    if nav.has_signal("condition_text_updated"):
        nav.condition_text_updated.connect(_on_condition_text_updated)

# New virtual method
func _show_navigation_hint(text: String) -> void:
    # Display hint text via CanvasLayer overlay or TextComponentBase
    # Uses existing UI system. Default: log to console.
    # Subclasses override to show in a scene-appropriate way.
    pass

# New virtual method
func _on_condition_text_updated(hint: String) -> void:
    # Called when player stays >60s or wrong direction >30s.
    # Subclasses update environmental text nodes.
    pass
```

### 3.2 SceneManager — Extended

```gdscript
# New method: called by ExitZone._transition()
func trigger_zone_transition(target_scene: String, fade_duration: float = 0.5) -> void:
    if transition_in_progress:
        return
    if target_scene.is_empty() or not FileAccess.file_exists(target_scene):
        push_error("SceneManager: Invalid target scene: ", target_scene)
        return
    transition_in_progress = true
    var gm := get_node_or_null("/root/GameManager")
    if gm:
        gm.set("transition_in_progress", true)
    transition_started.emit(target_scene)

    # Get zone context for title card
    var exit_zone = _get_calling_exit_zone()
    if exit_zone and gm:
        gm.set("navigation_context", {
            "exit_label": exit_zone.get("exit_label", ""),
            "route_hint": exit_zone.get("route_hint", ""),
            "next_scene_id": target_scene.get_file().get_basename()
        })

    # Persist dialogue state
    _persist_dialogue_state()

    # Show title overlay
    _show_title_overlay(target_scene)

    # Fade out
    _fade_anim.play("fade_out", -1, 1.0, false)
    await _fade_anim.animation_finished

    # Change scene
    var err: int = get_tree().change_scene_to_file(target_scene)
    if err != OK:
        push_error("SceneManager: Failed to change to scene: ", target_scene)
        transition_in_progress = false
        if gm:
            gm.set("transition_in_progress", false)
        return

# New helper
func _get_calling_exit_zone() -> Node:
    # Walk the call stack or use a stored reference.
    # Alternative: ExitZone sets a var on GameManager before calling.

func _show_title_overlay(target_scene: String) -> void:
    var scene_id = target_scene.get_file().get_basename()
    var gm := get_node_or_null("/root/GameManager")
    var context = gm.get("navigation_context", {}) if gm else {}
    var title_overlay = load("res://gdscripts/scene_title_overlay.gd").new()
    title_overlay.scene_id = scene_id
    title_overlay.route_context = context.get("route_hint", "")
    add_child(title_overlay)
    title_overlay.show_title()
```

### 3.3 ExitZone — Extended

```gdscript
# New exports
@export var exit_label: String = ""          # Scene name for title card (e.g., "街道")
@export var route_hint: String = ""          # Route context text (e.g., "Keep walking")

# Modified _transition()
func _transition() -> void:
    # ... existing validation ...
    var gm := get_node_or_null("/root/GameManager")
    if gm:
        gm.set("target_spawn_point", spawn_point)
        gm.set("navigation_context", {
            "exit_label": exit_label,
            "route_hint": route_hint,
            "next_scene_id": target_scene.get_file().get_basename()
        })
    var sm := get_parent().get_node_or_null("SceneManager")
    if sm and sm.has_method("trigger_zone_transition"):
        sm.trigger_zone_transition(target_scene)
```

### 3.4 GameManager — Extended

```gdscript
# New properties (added to existing)
var navigation_context: Dictionary = {}          # {exit_label, route_hint, next_scene_id}
var fallback_count: int = 0                      # Consecutive fallbacks in current scene

# Extended reset()
func reset() -> void:
    # ... existing reset ...
    navigation_context = {}
    fallback_count = 0
```

### 3.5 PlayerController — Extended

```gdscript
# New properties
var is_navigation_disabled: bool = false  # Set true during transitions

# Add H-key input in _input()
func _input(event: InputEvent) -> void:
    # ... existing input handling ...
    if event.is_action_pressed("navigate_hint") and not _dialogue_active:
        _request_navigation_hint()

# New signal
signal navigation_hint_requested()

func _request_navigation_hint() -> void:
    navigation_hint_requested.emit()
```

---

## 4. NavigationContext Data Flow

### 4.1 Scene Transition Flow (Full)

```
1. Player walks into ExitZone
2. ExitZone._on_body_entered()
   └─ ExitZone sets GameManager:
      ├─ target_spawn_point = spawn_point
      └─ navigation_context = {
           exit_label: "街道",
           route_hint: "Keep walking — the light ahead.",
           next_scene_id: "street"
         }
3. ExitZone → SceneManager.trigger_zone_transition(target_scene)
4. SceneManager:
   ├─ Persists dialogue state
   ├─ Creates SceneTitleOverlay with exit_label + route_hint
   ├─ Starts fade_out animation (0.5s)
   │   └─ SceneTitleOverlay fades in during curtain opacity rise
   ├─ await animation_finished
   ├─ change_scene_to_file(street.tscn)
5. New scene (street) _ready():
   ├─ SceneBase._ready()
   │   ├─ SceneManager.fade_in()
   │   ├─ _instantiate_player() at target_spawn_point
   │   ├─ _configure_environmental_text()
   │   ├─ _configure_ambient_audio()
   │   ├─ _restore_dialogue_state()
   │   └─ _setup_navigation()
   └─ SceneTitleOverlay from old scene auto-hides after display_duration
```

### 4.2 Fallback Flow

```
NavigationController._physics_process():
  ├─ Detects player.y < -10.0 → emit "fell" fallback
  └─ OR detects velocity < 0.01 for 3s → emit "stuck" fallback
  
NavFallback._trigger_fallback(reason):
  ├─ increment fallback_count in GameManager
  ├─ if fallback_count >= 3 → force title_screen.tscn
  ├─ fade_out (0.3s quick fade)
  ├─ teleport player to spawn_point
  ├─ reset player velocity
  ├─ fade_in (0.3s)
  └─ NavigationController resets all timers
```

### 4.3 Condition-Triggered Text Flow

```
NavigationController._physics_process():
  ├─ If _stay_timer > 60.0 and not _stay_triggered:
  │   ├─ _stay_triggered = true
  │   └─ emit condition_text_updated(stay_warning_text)
  ├─ If _wrong_dir_timer > 30.0 and not _wrong_dir_triggered:
  │   ├─ _wrong_dir_triggered = true
  │   └─ emit condition_text_updated(wrong_dir_text)
  └─ If player re-enters correct direction area:
      ├─ Reset _wrong_dir_timer, _wrong_dir_triggered
      └─ Emit direction_corrected signal

SceneBase._on_condition_text_updated(hint):
  └─ Update scene's environmental text nodes with new hint text
```

### 4.4 H-Key Hint Flow

```
PlayerController._input():
  └─ H key pressed → emit navigation_hint_requested signal
  
NavigationController (connected to signal):
  ├─ If _hint_cooldown > 0: return
  ├─ Set _hint_cooldown = 5.0  # 5s between hints
  └─ Emit navigation_hint_requested(scene_hint_text)

SceneBase._show_navigation_hint(text):
  └─ Display via CanvasLayer overlay (semi-transparent, bottom-center)
     Auto-dismiss after 4.0 seconds
```

---

## 5. Route-Aware Navigation Text

### 5.1 Route Determination

Route is determined by `NarrativeManager.determine_ending()` at subway_station, but the **hint text** during navigation is driven by the current scene's tone (from `SCENE_TONES`) rather than the final route. This allows navigation text to evolve with the player's emotional state even before the route is finalized.

### 5.2 Tone-to-Navigation-Text Mapping

Each tone maps to a navigation "push" direction:

| Tone | Navigation Style | Example (en) | Example (zh) |
|------|-----------------|-------------|-------------|
| despair | Pushing forward | "Keep going. / Nothing else to do." | "走。/ 只能往前走。" |
| low | Directional, muted | "That way. / Or stay." | "那边。/ 或者留下。" |
| neutral | Factual | "Door is behind you. / Street is ahead." | "门在身后。/ 街道在前。" |
| buoyant | Encouraging forward | "Light ahead. / Come see." | "前方有光。/ 来看看。" |
| hopeful | Warm forward | "Almost there. / The city awaits." | "快到了。/ 城市在等。" |
| fear | Warning / hesitant | "Not that way. / Maybe stay." | "别那边。/ 也许留下。" |
| uneasy | Questioning | "Is this the right way? / Hard to tell." | "是这边吗？/ 说不准。" |
| cold | Detached, options | "Both ways go. / Choose." | "都能走。/ 选一个。" |
| distant | Withdrawn | "Doesn't matter. / Any direction." | "无所谓。/ 哪里都一样。" |
| tired | Weary forward | "One more street. / Then rest." | "再一条街。/ 就能休息。" |
| heavy | Weighted forward | "The door is heavy. / Push through." | "门很沉。/ 推过去。" |
| resolute | Determined | "This way. / No question." | "这边。/ 不用想。" |
| transcendent | Certain | "The exit is there. / You know it." | "出口就在那里。/ 你知道的。" |
| waiting | Neutral, static | "The bench is dry. / No rush." | "长凳是干的。/ 不急。" |
| backward | Returning | "Back. / That's the way." | "回去。/ 那是路。" |
| hesitant | Ambivalent | "Maybe here. / Maybe not." | "也许这里。/ 也许不是。" |
| forward | Pushing end | "The train is coming. / Get on." | "列车来了。/ 上去。" |

### 5.3 Scene-Specific Hint Text Templates

Hint text for each scene is determined at design time using the H-key hint system. Each scene has 3 variants (one per route archetype):

| Scene | Route A (Keep Walking) | Route B (Turn Back) | Route C (Stay) |
|:-----:|:---------------------:|:-------------------:|:--------------:|
| office | "The door is ahead. / Go outside." | "The window is behind you. / Stay." | "The chair is warm. / Wait." |
| lobby | "The stranger points. / That door." | "Go back through the door. / Leave." | "Watch the rain. / No rush." |
| convenience_store | "The back door glows. / Keep going." | "The street door. / Go back out." | "The bench is near. / Sit." |
| bridge | "The other side. / City lights." | "Turn around. / Go back." | "The railing. / Stop here." |
| underpass | "The exit light. / Almost there." | "Familiar echoes. / Go back." | "The wall is dry. / Rest here." |
| subway_station | "The platform. / Train is here." | "The platform. / Empty." | "The bench. / Wait." |

---

## 6. Scene Environmental Guidance Configuration

### 6.1 Per-Scene Guidance Design

Each scene requires environmental modifications to guide the player toward exits:

| Scene | Exit(s) | Light Guidance | Environmental Text | NPC/Other |
|:-----:|:-------:|:--------------:|:------------------:|:---------:|
| office | Main door | Door crack light glow (OmniLight3D) | EXIT sign above door, "The door is slightly ajar" | — |
| lobby | Side door (forward), Office door (back) | Side door: warm light leakage; Office door: cooler back-light | "The stranger's umbrella drips near the door" | Stranger facing side door |
| convenience_store | Back door, Street exit | Back door: green exit light; Street exit: cool street light seepage | "EXIT sign flickers above the back door" | Clerk glances at exit |
| bridge | Far end (forward), Near end (back) | Far end: city skyline glow; Near end: street lamp | "The bridge stretches into the dark" | — |
| underpass | Both ends | Entrance: shrinking light circle; Exit: growing light circle | "Echoes shift at each end" | — |
| subway_station | Platform, Exit | Platform lights flicker; Exit sign at concourse | "The train sign reads: no destination" | Stranger at platform edge |

### 6.2 Implementation Pattern

Each scene's `_configure_environmental_text()` is extended to accept condition-triggered updates:

```gdscript
# Example: street.gd
func _configure_environmental_text() -> void:
    var tone: String = _get_tone_for_scene(scene_id)
    _set_hint_text(tone)

func _set_hint_text(tone: String) -> void:
    match tone:
        "cold":
            hint_text.text = "City lights blur. / Keep walking."
        "warm":
            hint_text.text = "Store light glows. / Warmth ahead."
        # ... etc.

# NEW: condition-triggered override
func _on_condition_text_updated(hint: String) -> void:
    # Override hint text temporarily
    hint_text.text = hint
    # Auto-revert after 5 seconds
    await get_tree().create_timer(5.0).timeout
    _set_hint_text(_get_tone_for_scene(scene_id))
```

---

## 7. Edge Cases & Mitigations

| Edge Case | Mitigation |
|-----------|------------|
| **Player exits zone immediately after entering** | ExitZone cooldown (1s default) prevents rapid re-trigger. NavigationController timers reset on scene re-entry. |
| **Multiple exits in one scene** | NavigationController scans all ExitZone children. Nearest exit determines "wrong direction" check. |
| **Player in dialogue when stuck/fell** | Stuck detection checks `_dialogue_active` and resets timer. Falls are detected regardless. |
| **Fade-out + title card on very slow systems** | Title card uses same AnimationPlayer pipeline — guaranteed to synchronize with fade opacity. |
| **H key conflicts with godot_dialogue_manager** | `navigate_hint` action only processed when `_dialogue_active == false`. |
| **Fallback loop (SpawnPoint also broken)** | `fallback_count` in GameManager tracks consecutive fallbacks. At 3, force-load title_screen.tscn. |
| **Player facing exit but timer still counts** | `_check_facing_exit()` raycast returns true → reset `_wrong_dir_timer`. |
| **Player stands still intentionally** | Stuck detection only triggers if velocity < 0.01 for 3s AND player is not in dialogue AND stay timer > 10s (grace period for deliberate stillness). |
| **Condition triggers fire repeatedly** | One-shot flags (`_stay_triggered`, `_wrong_dir_triggered`) prevent re-trigger until scene re-entry. |

---

## 8. Constants & Configuration

### 8.1 New Constants in `constants.gd`

```gdscript
# Navigation System Constants
const NAV_STAY_THRESHOLD: float = 60.0         # Seconds before stay warning
const NAV_WRONG_DIR_THRESHOLD: float = 30.0    # Seconds before wrong-dir warning
const NAV_STUCK_VELOCITY_THRESHOLD: float = 0.01  # m/s
const NAV_STUCK_DURATION: float = 3.0          # Seconds stuck before fallback
const NAV_HINT_COOLDOWN: float = 5.0           # Seconds between H-key hints
const NAV_HINT_DISPLAY_DURATION: float = 4.0   # Seconds hint text stays visible
const NAV_TITLE_DISPLAY_DURATION: float = 3.0  # Seconds title card stays visible
const NAV_FALLBACK_Y_THRESHOLD: float = -10.0  # Y position triggers fall detection
const NAV_FALLBACK_MAX: int = 3                # Max consecutive fallbacks before title screen
const NAV_FALLBACK_FADE_DURATION: float = 0.3  # Quick fallback fade duration
```

### 8.2 Navigation Input Actions

```gdscript
# Added to InputMap setup in PlayerController
"navigate_hint": KEY_H        # Hint key
```

---

## 9. File Manifest

### New Files

| File | Purpose |
|------|---------|
| `gdscripts/navigation_controller.gd` | Per-scene navigation orchestrator — timers, detection, hint routing |
| `gdscripts/scene_title_overlay.gd` | Scene title card CanvasLayer for fade transitions |
| `gdscripts/nav_fallback.gd` | Fallback detection and teleport logic |
| `references/scene-flow-diagrams.md` | ASCII route sequence reference |

### Modified Files

| File | Changes |
|------|---------|
| `gdscripts/scene_base.gd` | Add `_setup_navigation()`, navigation virtual methods, `@export scene_title_chinese` |
| `gdscripts/scene_manager.gd` | Add `trigger_zone_transition()`, `_show_title_overlay()` |
| `gdscripts/exit_zone.gd` | Add `exit_label`, `route_hint` exports; propagate NavigationContext |
| `gdscripts/game_manager.gd` | Add `navigation_context`, `fallback_count` properties |
| `gdscripts/player_controller.gd` | Add `navigate_hint` input binding, `navigation_hint_requested` signal |
| `gdscripts/constants.gd` | Add navigation system constants |
| `scenes/*/*.tscn` (8 scenes) | Add ExitZone placement, environmental guidance (lights, text, NPC) |

### New Scene-Specific Script Overrides

Each scene subclass should override `_on_condition_text_updated()` and `configure_environmental_text()`:

- `gdscripts/office.gd` — Office door light, EXIT sign text
- `gdscripts/lobby.gd` — Stranger posture, lobby exit light
- `gdscripts/store.gd` — Back door green light, street sounds
- `gdscripts/street.gd` — Store light glow, street lamp directions
- `gdscripts/bridge.gd` — City skyline glow, bridge navigation
- `gdscripts/underpass.gd` — Exit light, echo direction
- `gdscripts/subway_station.gd` — Platform lights, Stranger position

---

## 10. Integration Points

| Integration | Component | How |
|-------------|-----------|-----|
| SceneManager fade pipeline | SceneTitleOverlay | Title overlay attaches during fade, synchronizes with curtain opacity |
| NarrativeManager tone | NavigationController | Hint text queries `_get_tone_for_scene()` for route-aware content |
| ExitZone | NavigationController | NavigationController scans ExitZones for nearest-exit detection |
| PlayerController input | NavigationController | H-key action processed via `_input()` and `navigation_hint_requested` signal |
| GameManager state | All | NavigationContext carried through GameManager across scenes |
| StateSystem state | NavigationController | Hint text uses current state for tone-derived content |
| Hallucination engine | NavigationController (future) | High hallucination levels could distort hint text or light guidance |

---

## 11. Implementation Phases

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | **P0 (MVP Required)** | SceneTitleOverlay, NavFallback, scene_manager extended, game_manager extended | 2 days |
| Phase 2 | **P0 (MVP Required)** | Per-scene ExitZone placement, environmental guidance (lights, text), scene_base extended | 1.5 days |
| Phase 3 | **P1 (MVP Recommended)** | NavigationController (stay/wrong-dir detection), H-key hint text, condition_text_updated | 1.5 days |
| Phase 4 | P2 (Post-MVP) | Route-aware navigation text differentiation, per-tone hint text tables | 1 day |

**Total Estimate:** ~6 days (P0+P1: ~5 days, P2: ~1 day)
