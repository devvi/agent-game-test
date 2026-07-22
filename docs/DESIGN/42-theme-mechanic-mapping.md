# Design: #42 — Theme-Mechanic Mapping

> Parent Issue: #42
> Agent: plan-agent
> Date: 2026-07-22

---

## 1. Architecture Overview

### Core Idea

Define a bidirectional mapping matrix between three core themes (despair, hope, identity anxiety) and five game mechanics (dialogue-as-check, worldview filter, rainy night pressure, 3-month clock, tri-axis slider). Each mapping pair receives a harmony score (1–5) and a documented mapping chain that traces from "thematic intent" through "mechanic action" to "player perception." The matrix serves as the authoritative lookup table for all downstream implementation issues (#2 narrative architecture, #4 state-world feedback, #10 GameState system).

### Data Flow

```
Theme Intent (design layer)
    │
    ▼
Mapping Matrix (this doc — DESIGN/42)
    │
    ├──► Dialogue-As-Check    → dialogue_engine.gd reads hope/conviction → branches
    ├──► Worldview Filter      → scene_text module switches description templates
    ├──► Rainy Night Pressure  → rain_intensity = f(conviction, game_time) → forced shelter
    ├──► 3-Month Clock         → clock_manager.gd tracks days → deadline events
    └──► Tri-Axis Slider       → state_system.gd broadcasts state_changed → UI + narrative
            │
            ▼
    GameManager (Autoload) state_changed signal
            │
            ├──► Scene text module   → worldview_controller.gd
            ├──► Dialogue engine     → dialogue_engine.gd
            ├──► Weather system      → rain_controller.gd
            └──► HUD                 → state_display.gd
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach | Bidirectional Mapping Matrix (Approach C) with narrative supplements (Approach A) | Matrix provides all 24+ mapping pairs, harmony scores (AC2), and elimination candidates (AC3) in one view |
| Mapping granularity | Theme sub-component level (8 sub-components × 5 mechanics) | Finer than "theme → mechanic" — allows quantifying which *aspect* of a theme maps to which mechanic |
| Priority tiers | P0/P1/P2 from matrix | P0 mappings (dialogue + tri-axis + worldview filter) are the minimal viable thematic engine |
| Signal broadcast | GameManager as central Autoload broadcasting `state_changed` | All downstream modules (world, dialogue, weather) observe the same signal — no N-to-N wiring |
| Validation gate | Mapping chains verified in playtest (±1 harmony score tolerance) | Scores are designer estimates — empirical playtest is the binding source of truth |

---

## 2. Node / Scene Tree Layer

### New Scene: `scenes/dialogue/dialogue_panel.tscn`

- **Root:** `Panel` (Control node)
- **Children:**
  - `RichTextLabel` — NPC dialogue text (state-aware template)
  - `VBoxContainer` → `OptionButton[]` — player choice buttons (2–4 options)
  - `Label` — speaker name
- **Script:** `gdscripts/dialogue_engine.gd`
- **Signal Connections:**
  - `OptionButton.pressed` → `dialogue_engine.gd._on_choice_selected(choice_id: int)`
  - `dialogue_engine.gd.choice_made` → `GameManager.state_changed` (indirect, via state_system)

### New Scene: `scenes/hud/state_display.tscn`

- **Root:** `Panel` (Control node)
- **Children:**
  - `ProgressBar` (Hope) — range 0–10, label "希望"
  - `ProgressBar` (Conviction) — range 0–10, label "信念"
  - `ProgressBar` (Will) — range 0–10, label "意志"
  - `Label` — Game day counter
- **Script:** `gdscripts/state_display.gd`
- **Signal Connections:**
  - `GameManager.state_changed` → `state_display.gd._on_state_changed(state: Dictionary)`

### New Scene: `scenes/weather/rain_overlay.tscn`

- **Root:** `ColorRect` (with transparent black background)
- **Children:**
  - `GPUParticles2D` — rain particles, intensity controlled by shader parameter
  - `AudioStreamPlayer2D` — rain ambient sound
- **Script:** `gdscripts/rain_controller.gd`
- **Signal Connections:**
  - `GameManager.state_changed` → `rain_controller.gd._on_state_changed(state: Dictionary)`

### Existing Scene Modifications: `scenes/main.tscn`

- Add `CanvasLayer` child for dialogue_panel (rendered on top)
- Add `CanvasLayer` child for state_display (HUD)
- Add `CanvasLayer` child for rain_overlay (ambient weather on top of world, below HUD)

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/state_system.gd`

**Extends:** `Node` (intended as Autoload alongside GameManager, or merged into GameManager)

**Purpose:** Manages the tri-axis slider values and broadcasts state changes.

```gdscript
extends Node

# --- Signals ---
signal state_changed(state: Dictionary)

# --- State Fields ---
var hope: float = 5.0       # 0–10, 5=neutral
var conviction: float = 5.0 # 0–10, 5=neutral
var will: float = 5.0       # 0–10, 5=neutral

# --- Public API ---
func apply_choice(effect: Dictionary) -> void:
    # effect = {hope: 0.5, conviction: -1.0, will: 0.0}
    hope = clamp(hope + effect.get("hope", 0.0), 0.0, 10.0)
    conviction = clamp(conviction + effect.get("conviction", 0.0), 0.0, 10.0)
    will = clamp(will + effect.get("will", 0.0), 0.0, 10.0)
    state_changed.emit(get_state())

func get_state() -> Dictionary:
    return {"hope": hope, "conviction": conviction, "will": will}

func reset() -> void:
    hope = 5.0
    conviction = 5.0
    will = 5.0
    state_changed.emit(get_state())
```

**Mapping Chains Served:**
- M2/M5/M7: Dialogue choices call `apply_choice()` → `state_changed` signal
- M3: `conviction` decrease (from choices) = self-doubt increase
- M7: dual-condition branch checks `conviction >= 6 AND hope >= 5`

### New Script: `gdscripts/dialogue_engine.gd`

**Extends:** `Control` (attached to dialogue_panel.tscn)

**Purpose:** Loads dialogue data from resource files, checks state preconditions for branch selection, emits choice effects.

```gdscript
extends Control

signal dialogue_started(node_id: String)
signal dialogue_ended()
signal choice_made(choice_id: String, effect: Dictionary)

@onready var state_system: Node = %GameManager  # Autoload reference

var current_node: Dictionary = {}
var dialogue_data: Dictionary = {}  # loaded from .tres resource

func start_dialogue(node_id: String) -> void:
    dialogue_data = load("res://resources/dialogue/%s.tres" % node_id)
    current_node = dialogue_data.entry_node
    _display_node(current_node)

func _display_node(node: Dictionary) -> void:
    # node = {text: String, branches: Array[Dictionary]}
    # Each branch = {condition: Callable|Null, text: String, next_id: String, effect: Dictionary}
    var visible_branches = []
    for branch in node.get("branches", []):
        if branch.has("condition") and branch.condition != null:
            if branch.condition.call(state_system.get_state()):
                visible_branches.append(branch)
            else:
                continue
        else:
            visible_branches.append(branch)
    # Render visible_branches as OptionButtons
    _render_choices(visible_branches)

func _on_choice_selected(choice_id: int) -> void:
    var choice = current_node.branches[choice_id]
    if not choice.effect.is_empty():
        state_system.apply_choice(choice.effect)
        choice_made.emit(choice.id, choice.effect)
    if choice.has("next_id"):
        current_node = dialogue_data.nodes[choice.next_id]
        _display_node(current_node)
    else:
        dialogue_ended.emit()
```

**Mapping Chains Served:**
- M2/M7: Dialogue branches conditioned on `hope` / `conviction` thresholds
- M3/M5: Choice effects modify tri-axis values via `state_system.apply_choice()`
- M1: Dialogue text template selection influenced by state

### New Script: `gdscripts/worldview_controller.gd`

**Extends:** `Node`

**Purpose:** Listens to `state_changed` and selects environment description templates based on hope/conviction values.

```gdscript
extends Node

signal world_text_changed(prefix: String)  # "冷/灰色调" or "暖色"

@onready var state_system: Node = %GameManager

func _ready() -> void:
    state_system.state_changed.connect(_on_state_changed)

func _on_state_changed(state: Dictionary) -> void:
    var tone = _calculate_tone(state.hope, state.conviction)
    world_text_changed.emit(tone)

func _calculate_tone(hope: float, conviction: float) -> String:
    # Returns description template prefix
    if hope <= 3.0:
        return "despair"     # "便利店的灯刺眼又苍白"
    elif hope >= 7.0:
        return "hope"        # "早晨的阳光透过窗帘"
    else:
        return "neutral"     # standard description
```

**Mapping Chains Served:**
- M1: Low hope → worldview filter shifts to cold/gray → player perceives "the world reflects my despair"
- M8: Conviction influences NPC attitude descriptions

### New Script: `gdscripts/rain_controller.gd`

**Extends:** `Node` (attached to rain_overlay.tscn)

**Purpose:** Maps conviction value to rain intensity using `rain_intensity = f(conviction, game_time)`. Triggers forced shelter scene when intensity exceeds threshold.

```gdscript
extends Node

signal forced_shelter_triggered()

const RAIN_CHECK_INTERVAL: float = 30.0  # seconds
const SHELTER_THRESHOLD: float = 7.0

@onready var state_system: Node = %GameManager
@onready var particles: GPUParticles2D = $GPUParticles2D

var rain_intensity: float = 0.0

func _ready() -> void:
    state_system.state_changed.connect(_on_state_changed)
    var timer := Timer.new()
    timer.wait_time = RAIN_CHECK_INTERVAL
    timer.timeout.connect(_check_rain)
    add_child(timer)
    timer.start()

func _on_state_changed(state: Dictionary) -> void:
    # Rain intensity inversely proportional to conviction
    rain_intensity = clamp((10.0 - state.conviction) / 10.0, 0.0, 1.0)
    particles.amount_ratio = rain_intensity

func _check_rain() -> void:
    if rain_intensity >= SHELTER_THRESHOLD / 10.0:
        forced_shelter_triggered.emit()
```

**Mapping Chains Served:**
- M4: Low conviction → high rain intensity → forced shelter → player feels abandoned by the world

### New Script: `gdscripts/clock_manager.gd`

**Extends:** `Node`

**Purpose:** Tracks in-game days consumed by dialogue interactions; triggers deadline events when approaching 90-day limit.

```gdscript
extends Node

signal day_passed(day: int, remaining: int)
signal deadline_approaching(days_left: int)
signal deadline_reached()

const MAX_DAYS: int = 90

var current_day: int = 0

func consume_days(amount: int = 1) -> void:
    current_day += amount
    var remaining = MAX_DAYS - current_day
    day_passed.emit(current_day, remaining)
    
    if current_day >= MAX_DAYS:
        deadline_reached.emit()
    elif remaining <= 14:
        deadline_approaching.emit(remaining)

func reset() -> void:
    current_day = 0
```

**Mapping Chains Served:**
- M6: Each dialogue choice consumes 1–3 days → time pressure → despair accumulation

### Existing Script Modifications: `gdscripts/game_manager.gd`

- Add Autoload references: `state_system`, `dialogue_engine`, `worldview_controller`, `rain_controller`, `clock_manager`
- Expose `state_changed` signal (or delegate to state_system)
- Route `state_changed` to all downstream modules
- Add `_ready()` initialization that seeds random state and calls `reset()` on all subsystems

---

## 4. Resource / Config Layer

### New Resource Type: `DialogueData`

```
resources/dialogue/
  ├── npc_001.tres       # 便利店老板
  ├── npc_002.tres       # 同行开发者
  ├── npc_003.tres       # 知心NPC
  └── ...
```

Each `.tres` resource is a custom `Resource` subclass:

```gdscript
class_name DialogueData extends Resource

@export var id: String
@export var entry_node_id: String
@export var nodes: Dictionary  # {node_id: DialogueNode}
```

```gdscript
class_name DialogueNode extends Resource

@export var text: String
@export var branches: Array[DialogueBranch]
```

```gdscript
class_name DialogueBranch extends Resource

@export var id: String
@export var text: String         # Choice button text
@export var next_node_id: String
@export var effect: Dictionary   # {hope: 0.5, conviction: -1.0, will: 0.0}
# condition is defined in code via a function reference at runtime
```

### New Constants: `gdscripts/constants.gd` (new file)

```gdscript
extends Node

# Theme-Mechanic Priority Tiers
const PRIORITY_P0: Array[String] = ["dialogue_check", "worldview_filter", "triaxis_slider"]
const PRIORITY_P1: Array[String] = ["rainy_night"]
const PRIORITY_P2: Array[String] = ["three_month_clock"]

# State Limits
const STATE_MIN: float = 0.0
const STATE_MAX: float = 10.0
const STATE_NEUTRAL: float = 5.0
const STATE_HIGH: float = 7.0
const STATE_LOW: float = 3.0

# Thresholds
const CONVICTION_SHELTER_THRESHOLD: float = 3.0  # below this → forced shelter
const HOPE_COLD_TONE_THRESHOLD: float = 3.0      # below this → cold worldview
const HOPE_WARM_TONE_THRESHOLD: float = 7.0      # above this → warm worldview
const DIALOGUE_MAX_DAYS_COST: int = 3
const CLOCK_DEADLINE_DAYS: int = 90
```

### Project Configuration: `project.godot`

- Add Autoload entries:
  - `GameManager` → `res://gdscripts/game_manager.gd`
  - `StateSystem` → `res://gdscripts/state_system.gd` (or merged into GameManager)
  - `ClockManager` → `res://gdscripts/clock_manager.gd` (or merged into GameManager)
- Add Input Map actions (none new for this phase — dialogue uses UI button clicks, not keyboard binds)

---

## 5. Asset / Visual Layer

### Rain Particles

- Create rain particle texture in `assets/weather/rain_drop.png` (simple thin white line)
- GPUParticles2D configuration:
  - Amount: 1000
  - Lifetime: 0.8s
  - Speed: (0, 400)–(50, 600)
  - Amount Ratio: 0.0–1.0 (controlled by rain_controller.gd)

### Dialog Panel Theme

- `assets/themes/dialogue_theme.tres` — `Theme` resource with font, colors
- Panel background: semi-transparent black (60% opacity)
- NPC name label: white bold
- Player options: light gray, hover → white

### State Display Icons

- `assets/icons/hope_icon.png` — rising sun
- `assets/icons/conviction_icon.png` — anchor/compass
- `assets/icons/will_icon.png` — flame

---

## 6. Input / UI Layer

### Dialogue System UI

- Dialogue panel overlays main scene when `dialogue_engine.start_dialogue()` is called
- `RichTextLabel` shows NPC text with typewriter animation
- Player choices appear after text completes (0.5s delay)
- Click/tap to advance text (skip typewriter)
- Keyboard shortcuts: 1–4 to select choices, Escape to close (if available)

### State Display HUD

- Three horizontal `ProgressBar` bars aligned top-right
- Color-coded: Hope = green, Conviction = blue, Will = yellow
- Day counter (top-left, small text): "Day 23 / 90"
- Rain indicator icon (when rain_intensity > 0.2)

---

## 7. Test Layer

### Test Structure

New test file: `tests/test_theme_mechanic_mapping.gd` — validate mapping chain logic without dialogue resources or scene tree.

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| StateSystem.apply_choice() | ✅ | ≥3 | ✅ |
| WorldviewController tone calculation | ✅ | ≥2 | ✅ |
| RainController intensity mapping | ✅ | ≥2 | ✅ |
| ClockManager day consumption | ✅ | ≥2 | ✅ |
| DialogueEngine branch filtering | ✅ | ≥2 | ✅ |

### Test Case Descriptions

**Normal Path (TC-M1): StateSystem basic apply/read cycle**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-M1-1 | Apply positive effect | Create StateSystem, call `apply_choice({hope: 1.0, conviction: 0.5})` | hope=6.0, conviction=5.5 | `_assert(state.hope == 6.0)` |
| TC-M1-2 | Apply negative effect | Create StateSystem, call `apply_choice({conviction: -2.0})` | conviction=3.0 | `_assert(state.conviction == 3.0)` |
| TC-M1-3 | Clamp at lower bound | Call `apply_choice({hope: -10.0})` | hope=0.0 (clamped) | `_assert(state.hope == 0.0)` |
| TC-M1-4 | Clamp at upper bound | Call `apply_choice({hope: 10.0})` | hope=10.0 (clamped) | `_assert(state.hope == 10.0)` |
| TC-M1-5 | state_changed signal emitted | Connect to signal, apply choice | Signal fires exactly once with correct state | `_assert(signal_fired == true)` |

**Edge Case (TC-M2): WorldviewController tone transitions**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-M2-1 | Despair tone | set hope=2.0, emit state_changed | tone="despair" | `_assert(tone == "despair")` |
| TC-M2-2 | Hope tone | set hope=8.0, emit state_changed | tone="hope" | `_assert(tone == "hope")` |
| TC-M2-3 | Boundary: neutral→despair | set hope=3.1 → hope=2.9 → emit each | First "neutral", then "despair" | `_assert(tone_last == "despair")` |
| TC-M2-4 | Boundary: hope→neutral | set hope=7.1 → hope=6.9 → emit each | First "hope", then "neutral" | `_assert(tone_last == "neutral")` |

**Edge Case (TC-M3): RainController intensity mapping**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-M3-1 | Low conviction → high rain | conviction=2.0, emit state_changed | rain_intensity ≈ 0.8 | `_assert(rain_intensity > 0.6)` |
| TC-M3-2 | High conviction → low rain | conviction=9.0, emit state_changed | rain_intensity ≈ 0.1 | `_assert(rain_intensity < 0.3)` |
| TC-M3-3 | Forced shelter trigger | conviction=2.0, rain_intensity above threshold | shelter signal emitted within 30s | `_assert(shelter_triggered == true)` |

**Edge Case (TC-M4): ClockManager deadlines**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-M4-1 | Normal day consumption | consume_days(3) | current_day=3, remaining=87 | `_assert(current_day == 3)` |
| TC-M4-2 | Deadline approaching | consume_days(76) → 76+14=90, remaining=14 | deadline_approaching fires at 14 days left | `_assert(approaching_fired == true)` |
| TC-M4-3 | Deadline reached | consume_days(90) from 0 | deadline_reached fires | `_assert(deadline_fired == true)` |
| TC-M4-4 | Exact boundary at 14 | consume_days(76) | remaining == 14, approaching fires | `_assert(remaining == 14)` |

**Failure Path (TC-M5): DialogueEngine branch filtering without resources**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-M5-1 | Empty dialogue data | start_dialogue() with empty resource | Graceful no-op, no crash | `_assert(no error)` |
| TC-M5-2 | No branches match condition | All branches have unmet conditions | No visible choices reported | `_assert(visible_branches.is_empty())` |
| TC-M5-3 | Choice with no next_id | Select terminal choice | dialogue_ended signal fires | `_assert(ended_fired == true)` |

---

## 8. Files Changed (per-layer summary)

### Node / Scene Tree Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/dialogue/dialogue_panel.tscn` | **New** — dialogue UI scene | +60 |
| `scenes/hud/state_display.tscn` | **New** — HUD with 3 progress bars + day counter | +50 |
| `scenes/weather/rain_overlay.tscn` | **New** — GPUParticles2D rain overlay | +40 |
| `scenes/main.tscn` | Add CanvasLayer children for dialogue, HUD, weather | +15 |

### GDScript / Logic Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/state_system.gd` | **New** — tri-axis state manager with `state_changed` signal | +60 |
| `gdscripts/dialogue_engine.gd` | **New** — state-aware dialogue branching engine | +100 |
| `gdscripts/worldview_controller.gd` | **New** — hope/conviction → tone filter | +40 |
| `gdscripts/rain_controller.gd` | **New** — conviction → rain intensity + shelter trigger | +50 |
| `gdscripts/clock_manager.gd` | **New** — 90-day deadline tracker | +40 |
| `gdscripts/constants.gd` | **New** — threshold constants for mapping chain | +25 |
| `gdscripts/game_manager.gd` | Modify — add Autoload init, route `state_changed` signal | +20 |

### Resource / Config Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `resources/dialogue/npc_001.tres` | **New** — sample dialogue resource | +30 |
| `resources/dialogue/npc_002.tres` | **New** — sample dialogue resource | +30 |
| `resources/dialogue/npc_003.tres` | **New** — sample dialogue resource | +30 |
| `project.godot` | Add Autoload entries for new systems | +5 |

### Asset / Visual Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `assets/weather/rain_drop.png` | **New** — rain particle texture | — |
| `assets/themes/dialogue_theme.tres` | **New** — dialogue UI theme | +20 |
| `assets/icons/hope_icon.png` | **New** — HUD icon | — |
| `assets/icons/conviction_icon.png` | **New** — HUD icon | — |
| `assets/icons/will_icon.png` | **New** — HUD icon | — |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_theme_mechanic_mapping.gd` | **New** — mapping chain test descriptions (implement agent writes runnable code) | +90 |

---

## 9. Verification Checklist

- [ ] TC-M1-1 through TC-M1-5: StateSystem basic operations pass
- [ ] TC-M2-1 through TC-M2-4: WorldviewController tone boundaries correct (±0.1 tolerance)
- [ ] TC-M3-1 through TC-M3-3: RainController intensity follows conviction inversely
- [ ] TC-M4-1 through TC-M4-4: ClockManager deadline events fire at correct thresholds
- [ ] TC-M5-1 through TC-M5-3: DialogueEngine gracefully handles edge cases
- [ ] All mapping chains from PRD section 5.1 are representable in the architecture (M1–M8)
- [ ] Harmony scores from PRD section 5.2 are reflected in threshold constants
- [ ] P0 mappings (dialogue-as-check + worldview filter + tri-axis slider) are implemented first
- [ ] No regression: existing `game_manager.gd` and `scenes/main.tscn` still load without errors
- [ ] `godot --headless --script tests/run_tests.gd` — all tests pass, 0 failures
