# Design: #55 — [Scene] Office Door → Street → Convenience Store

> Parent Issue: #55
> Agent: plan-agent
> Date: 2026-07-22

---

## 1. Architecture Overview

### Core Idea

Implement the game's first playable scene sequence: player starts in an **office interior**, exits through a dialogue-triggered door to a **rainy street**, and enters a **convenience store** with a state-aware clerk NPC. Three standalone `.tscn` scenes are loaded via Godot's `change_scene_to_file()`, orchestrated by a new `SceneManager.gd` node in the main scene. Environmental text (LoFiText3D) updates per scene based on GameState, foreshadowing the Stranger. Dialogue choice history persists across scene transitions via the GameManager autoload.

### Data Flow

```
scenes/main.tscn (entry point)
    │
    ├── GameManager (autoload) — choices_history, state persistence
    ├── GameState (autoload) — legacy; superseded by StateSystem
    ├── StateSystem [NEW AUTOLOAD] — tri-axis state (hope/conviction/will)
    │
    ├── CanvasLayer (Dialogue UI) — DialogueRunner instance
    │       │
    │       └── scene_transition_requested signal (NEW)
    │               │
    ▼               ▼
SceneManager.gd [NEW] — orchestrates fade → change_scene_to_file → fade
    │
    ├── change_scene_to_file("res://scenes/office/office.tscn")
    ├── change_scene_to_file("res://scenes/street/street.tscn")
    └── change_scene_to_file("res://scenes/store/convenience_store.tscn")
            │
            ▼
Each scene _ready():
    1. Read GameState → configure environmental texts (LoFiText3D)
    2. Read GameManager.choices_history → restore dialogue context
    3. Connect input triggers (Area3D click → dialogue start)
    4. Connect RainController / WorldviewController signals

Transition sequence:
    Player input → Dialogue choice → choice_made signal
        → SceneManager connects to choice_made
        → Persists choices_made to GameManager.choices_history
        → Emits scene_transition_requested(target_scene_path)
        → CanvasLayer fade-to-black (0.5s AnimationPlayer)
        → SceneTree.change_scene_to_file(target)
        → New scene _ready() → fade-in (0.5s AnimationPlayer)
        → DialogueRunner restored from GameManager.choices_history
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scene transition strategy | Godot `change_scene_to_file()` (Approach A) | Standard pattern; autoloads persist state. No WorldEnvironment conflicts. Each scene independently testable. |
| Dialogue persistence across scenes | Serialize `choices_made` to `GameManager.choices_history` | ~10 lines in GameManager; preserves DialogueRunner state without making it an autoload. Aligns with PRD's spike recommendation (Strategy b). |
| Camera model | Fixed camera per scene (Approach D insight) | No CharacterBody3D/ActorBody needed. Each scene has 2–4 clickable Area3D interaction points. Matches the game's composed-frame Hopper aesthetic. |
| StateSystem autoload | **Make StateSystem an autoload** | WorldviewController and RainController already reference `/root/StateSystem`. Adding to `project.godot` `[autoload]` is minimal change (~1 line) and eliminates the `get_node_or_null` fragility. |
| Fade transition | CanvasLayer modulate animation (0.5s fade-out, 0.5s fade-in) | Thematically appropriate for noir. Prevents rapid scene-switching via `transition_in_progress` flag. |
| Interaction model | Click/accept on Area3D trigger zones | Each POI (door, store entrance, clerk) is an Area3D with `input_event` or `area_entered` detection. No free movement. |
| Environmental text integration | Per-scene config dictionary read in `_ready()` + WorldviewController signal | Text variants are determined at scene load time, then updated on state change. Mid-conversation updates are deferred. |

---

## 2. Node / Scene Tree Layer

### New Scenes

#### `scenes/main.tscn` — **Modified** (entry point restructured)

- **Current:** Single Node3D root with WorldLabel, Camera3D, Dialogue UI CanvasLayer.
- **Changes:**
  - Add `SceneManager` (Node) as child of root — orchestrates transitions
  - Add `FadeCurtain` (CanvasLayer) with `ColorRect` and `AnimationPlayer` — fade-to-black / fade-in
  - Keep existing `Dialogue` (CanvasLayer) with `DialoguePanel` as-is
  - Keep existing `DialogueDebug` (CanvasLayer) for dev
  - Replace static `WorldLabel` setup with dynamic scene loading — `main.gd`'s `_ready()` now delegates to `SceneManager` to load the first scene (office)

**New node hierarchy:**

```
main.tscn (Node3D root)
├── Camera3D (persistent — never destroyed)
├── DirectionalLight3D (persistent dim ambient)
├── SceneManager (Node, new script gdscripts/scene_manager.gd)
├── FadeCurtain (CanvasLayer)
│   ├── ColorRect (modulate for fade)
│   └── AnimationPlayer (fade_out / fade_in animations)
├── Dialogue (CanvasLayer) [existing]
│   └── DialoguePanel (DialogueRunner.gd attached) [existing]
├── DialogueDebug (CanvasLayer, dev only) [existing]
└── EnvironmentRoot (Node3D, empty) — target for add_child when not using change_scene_to_file
```

> **Decision:** Despite using `change_scene_to_file()`, we keep a persistent root scene (`main.tscn`) that hosts the Camera, SceneManager, FadeCurtain, and Dialogue UI. Each environment scene is a standalone `.tscn` that is loaded by `change_scene_to_file()` — but the camera and UI live in the root. Wait — `change_scene_to_file()` replaces the entire scene tree, so a persistent root and `change_scene_to_file` are mutually exclusive. **Revised decision:** The root scene IS the environment. When transitioning, the entire scene tree is replaced. Camera3D moves inside each environment scene. Dialogue panel is inside each environment scene as a CanvasLayer child, but DialogueRunner's `choices_made` persists via GameManager. This is the correct Approach A pattern.

**Revised node hierarchy (per environment scene):**

Each scene (`office.tscn`, `street.tscn`, `store.tscn`) follows this template:

```
Root: Node3D ("SceneRoot")
├── Camera3D ("MainCamera") — positioned per scene
├── WorldEnvironment — environment settings per scene
├── DirectionalLight3D — per-scene lighting
├── Environments
│   ├── StaticBody3D (floor, walls, furniture)
│   └── LoFiText3D instances (see Asset/Visual layer)
├── InteractionZones
│   ├── Area3D ("door_trigger") — office door
│   ├── Area3D ("store_entrance_trigger") — street→store
│   └── Area3D ("clerk_trigger") — store clerk
├── CanvasLayer ("DialogueUI")
│   ├── DialoguePanel (DialogueRunner.gd)
│   └── AnimationPlayer (fade curtain — part of each scene's CanvasLayer)
└── SceneManager (Node, gdscripts/scene_manager.gd) — present in every scene
```

> **Decision date:** 2026-07-22 — each scene is self-contained with its own Camera + UI + SceneManager. The alternative (persistent root + sub-scene swap, Approach B) was rejected because: (1) WorldEnvironment conflicts between scenes, (2) editor tooling is worse for sub-scenes, (3) this game has only 3 small scenes so reload cost is negligible.

#### `scenes/office/office.tscn` — **New**

Office interior scene:
- **Root:** Node3D ("OfficeRoot")
- **Lighting:** Dim warm amber — directional light at low angle, one OmniLight3D for desk lamp
- **Camera3D:** Positioned at desk looking toward the door and window — the player's seated perspective
- **WorldEnvironment:** Dark background (`#1a1a2e`), glow enabled for neon text emission
- **Geometry:**
  - Floor plane (dark wood / concrete material)
  - Back wall with window — window has a LoFiText3D "rain-streaked glass" effect
  - Side wall with door — Area3D trigger zone (`"office_door_trigger"`)
  - Desk with LoFiText3D lamp glow
- **LoFiText3D instances:**
  - `WindowText` (Billboard mode) — rain-streaked window text, state-variant
  - `DeskNote` (Flat Sign mode) — optional desk detail
- **Interaction Zones:**
  - `Area3D("office_door_trigger")` — click → start `dialogues/office_door.json`
- **CanvasLayer:**
  - `DialoguePanel` (DialogueRunner)
  - `FadeCurtain` (ColorRect + AnimationPlayer)

#### `scenes/street/street.tscn` — **New**

Rainy street segment scene:
- **Root:** Node3D ("StreetRoot")
- **Lighting:** Cool blue/amber mix — streetlamp OmniLights, dim overall
- **Camera3D:** Medium shot looking down the street, store entrance visible in frame
- **WorldEnvironment:** Night street ambiance, glow enabled
- **Geometry:**
  - Street surface (wet asphalt material)
  - Building facades (left and right)
  - Streetlamp (decorative + light source)
  - Convenience store front (glowing OPEN sign)
  - Sidewalk with graffiti wall
- **LoFiText3D instances:**
  - `NeonSign` (Emissive mode) — "YOU'RE STILL HERE", state-dependent pulse
  - `StreetSign` (Flat Sign mode) — "ELM ST."
  - `Graffiti` (Flat Sign mode) — wall text, state-variant
- **Interaction Zones:**
  - `Area3D("store_entrance_trigger")` — click → start `dialogues/office_door.json` (reuse "enter_store" path or separate mini-dialogue)
- **RainController:** Attached to root, connects to particle system (placeholder) and sets rain intensity from conviction
- **CanvasLayer:** Same template (DialoguePanel + FadeCurtain)

#### `scenes/store/convenience_store.tscn` — **New**

Convenience store interior scene:
- **Root:** Node3D ("StoreRoot")
- **Lighting:** Warm fluorescent — overhead panels, cool white + warm spots
- **Camera3D:** From entrance looking at counter
- **WorldEnvironment:** Bright interior, slight warm tint
- **Geometry:**
  - Floor (linoleum material)
  - Shelving units
  - Counter with clerk position
  - Entrance door (visible behind player)
- **LoFiText3D instances:**
  - `OpenSign` (Emissive mode) — "OPEN" with optional Stranger subtitle
  - `ShelfLabels` (Flat Sign mode) — ambient detail
- **Interaction Zones:**
  - `Area3D("clerk_trigger")` — click → start `dialogues/store_clerk.json`
- **Clerk NPC Node:**
  - `Node3D("ClerkNPC")` — positioned behind counter
  - LoFi billboard text "Clerk" as placeholder
- **CanvasLayer:** Same template

### Existing Scene Modifications

| Scene | Change |
|-------|--------|
| `scenes/main.tscn` | Repurpose as boot scene: load SceneManager, set initial scene to office. The root node stays but `_ready()` immediately calls `change_scene_to_file("res://scenes/office/office.tscn")`. After that, `main.tscn` is no longer in the tree — each environment scene is the active scene. |

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/scene_manager.gd`

**Extends:** `Node`

**Purpose:** Orchestrates scene transitions triggered by dialogue choices. Exists in every scene as a child of the scene root.

```gdscript
extends Node

signal transition_started(target_scene: String)
signal transition_completed()

var transition_in_progress: bool = false

## The fade curtain CanvasLayer node (added as child in _ready())
var _fade_curtain: CanvasLayer
var _fade_anim: AnimationPlayer

func _ready() -> void:
    # Find or create the fade curtain
    _setup_fade_curtain()
    # Connect to dialogue runner's choice_made to detect scene-transition triggers
    _connect_to_dialogue()

func _setup_fade_curtain() -> void:
    # Look for existing FadeCurtain child, or create one
    _fade_curtain = $FadeCurtain if has_node("FadeCurtain") else _create_fade_curtain()
    _fade_anim = _fade_curtain.get_node("AnimationPlayer")

func _connect_to_dialogue() -> void:
    var dr = get_node_or_null("CanvasLayer/DialoguePanel")
    if dr and dr.has_signal("choice_made"):
        dr.choice_made.connect(_on_choice_made)

## Handle choices that trigger scene transitions.
## Scene transitions are encoded in choice metadata: { "scene": "res://scenes/street/street.tscn" }
func _on_choice_made(choice_index: int, choice_text: String) -> void:
    var dr = get_node_or_null("CanvasLayer/DialoguePanel")
    if not dr or not is_instance_valid(dr):
        return
    var current: Dictionary = dr.current_node
    var choices: Array = current.get("choices", [])
    if choice_index < 0 or choice_index >= choices.size():
        return
    var choice: Dictionary = choices[choice_index]
    if choice.has("scene") and choice["scene"] != null and str(choice["scene"]) != "":
        trigger_scene_change(choice["scene"])

## Trigger a scene change with fade transition.
## Persists dialogue state to GameManager before changing scenes.
func trigger_scene_change(target_scene: String, fade_duration: float = 0.5) -> void:
    if transition_in_progress:
        return
    transition_in_progress = true
    transition_started.emit(target_scene)

    # Persist dialogue choices_made to GameManager
    _persist_dialogue_state()

    # Fade out
    _fade_anim.play("fade_out", -1, 1.0, false)
    await _fade_anim.animation_finished

    # Change scene
    var err: int = get_tree().change_scene_to_file(target_scene)
    if err != OK:
        push_error("SceneManager: Failed to change to scene: ", target_scene)
        # Fallback: reload current scene or show error
        return

    # Fade in (this runs after _ready() of the new scene)
    # The new scene's SceneManager handles fade-in

## Persist dialogue choices_made array to GameManager autoload.
func _persist_dialogue_state() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    var dr = get_node_or_null("CanvasLayer/DialoguePanel")
    if gm and dr:
        gm.set("choices_history", dr.choices_made.duplicate())

## Called by the new scene after its _ready() to fade in.
func fade_in(fade_duration: float = 0.5) -> void:
    if not transition_in_progress:
        return
    _fade_anim.play_backwards("fade_out")
    await _fade_anim.animation_finished
    transition_in_progress = false
    transition_completed.emit()
```

**Signals:**
- `transition_started(target_scene: String)` — emitted when fade-out begins
- `transition_completed()` — emitted after fade-in finishes

### New Script: `gdscripts/office.gd`

**Extends:** `Node` (attached to OfficeRoot)

**Purpose:** Office scene initialization — configure window text from GameState, connect door trigger.

```gdscript
extends Node

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var window_text: Node3D = $Environments/WindowText
@onready var door_trigger: Area3D = $InteractionZones/OfficeDoorTrigger

func _ready() -> void:
    # Fade in after scene load
    scene_manager.fade_in()

    # Configure environmental text from current state
    _configure_environmental_text()

    # Connect door trigger
    door_trigger.input_event.connect(_on_door_trigger_input)

    # Restore dialogue state if returning to office
    _restore_dialogue_state()

func _configure_environmental_text() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if not gm:
        return
    var hope: float = gm.get_slider("hope")
    var wv = preload("res://gdscripts/worldview_controller.gd").new()
    var tone: String = wv.get_tone_for_state({"hope": hope})

    match tone:
        "hope":
            window_text.text = "The city glitters through the rain.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
        "neutral":
            window_text.text = "Rain on the glass.\nAnother night at the office.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
        "despair":
            window_text.text = "The streetlights blur.\nOne more night. One more.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"

func _on_door_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _start_door_dialogue()

func _start_door_dialogue() -> void:
    dialogue_runner.start("res://dialogues/office_door.json", "office_door")

func _restore_dialogue_state() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm and dialogue_runner.choices_made.is_empty():
        if gm.has("choices_history") and not gm.choices_history.is_empty():
            dialogue_runner.choices_made = gm.choices_history.duplicate()
```

### New Script: `gdscripts/street.gd`

**Extends:** `Node` (attached to StreetRoot)

**Purpose:** Street scene initialization — configure neon, graffiti, and street sign text. Set rain intensity. Connect store entrance trigger.

```gdscript
extends Node

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var neon_sign: Node3D = $Environments/NeonSign
@onready var graffiti: Node3D = $Environments/Graffiti
@onready var street_sign: Node3D = $Environments/StreetSign
@onready var store_entrance: Area3D = $InteractionZones/StoreEntranceTrigger
@onready var rain_controller: Node = $RainController

func _ready() -> void:
    scene_manager.fade_in()
    _configure_environmental_text()
    _configure_rain()
    store_entrance.input_event.connect(_on_store_entrance_input)
    _restore_dialogue_state()

func _configure_environmental_text() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if not gm:
        return
    var hope: float = gm.get_slider("hope")
    var conviction: float = gm.get_slider("conviction")

    # Neon sign: conviction-based glow
    if conviction >= 7.0:
        neon_sign.modulate = Color(1.0, 0.7, 0.2)  # warm amber
        # emissive_strength set via LoFiText3D export
    elif conviction >= 4.0:
        neon_sign.modulate = Color(1.0, 0.6, 0.1)  # dim amber
    else:
        neon_sign.modulate = Color(0.8, 0.1, 0.1)  # dim red

    # Graffiti: hope-based visibility
    if hope >= 6.0:
        graffiti.text = "this too shall pass"
        graffiti.modulate = Color(1, 1, 1, 0.6)  # faded
    else:
        graffiti.text = "i was here"
        graffiti.modulate = Color(1, 1, 1, 0.3)  # partially scratched

    # Street sign is static
    street_sign.text = "ELM ST."

func _configure_rain() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm:
        var conviction: float = gm.get_slider("conviction")
        rain_controller._on_state_changed({"conviction": conviction})

func _on_store_entrance_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        dialogue_runner.start("res://dialogues/office_door.json", "store_entrance")

func _restore_dialogue_state() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm and dialogue_runner.choices_made.is_empty():
        if gm.has("choices_history") and not gm.choices_history.is_empty():
            dialogue_runner.choices_made = gm.choices_history.duplicate()
```

### New Script: `gdscripts/store.gd`

**Extends:** `Node` (attached to StoreRoot)

**Purpose:** Store scene initialization — configure OPEN sign text, trigger clerk dialogue.

```gdscript
extends Node

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var open_sign: Node3D = $Environments/OpenSign
@onready var clerk_trigger: Area3D = $InteractionZones/ClerkTrigger

func _ready() -> void:
    scene_manager.fade_in()
    _configure_environmental_text()
    clerk_trigger.input_event.connect(_on_clerk_trigger_input)
    _restore_dialogue_state()

func _configure_environmental_text() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if not gm:
        return
    var hope: float = gm.get_slider("hope")
    var conviction: float = gm.get_slider("conviction")

    # Always show "OPEN"
    # Show Stranger foreshadowing subtitle if both hope >= 5 and conviction >= 4
    if hope >= 5.0 and conviction >= 4.0:
        open_sign.text = "OPEN\n⌈He was here tonight.⌋"
    else:
        open_sign.text = "OPEN"

func _on_clerk_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        dialogue_runner.start("res://dialogues/store_clerk.json", "store_clerk")

func _restore_dialogue_state() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm and dialogue_runner.choices_made.is_empty():
        if gm.has("choices_history") and not gm.choices_history.is_empty():
            dialogue_runner.choices_made = gm.choices_history.duplicate()
```

### Existing Script Modifications

#### `gdscripts/main.gd` — **Modified**

- **Current:** Creates a `WorldLabel`, reads GameState, connects dialogue toggle on F9.
- **Changes:**
  - `_ready()` now starts the game by calling `SceneManager` to load the first scene (`office.tscn`)
  - Remove static `WorldLabel` setup (text moves to office scene)
  - Keep dialogue toggle (F9) for debug
  - Add initial scene load logic:

```gdscript
func _ready() -> void:
    var sm = $SceneManager
    if sm:
        # Start by loading the office scene
        # Use call_deferred to ensure the scene is fully set up first
        call_deferred("_load_starting_scene")

func _load_starting_scene() -> void:
    get_tree().change_scene_to_file("res://scenes/office/office.tscn")
```

#### `gdscripts/game_manager.gd` — **Modified**

- **Add:** `choices_history: Array` property for dialogue persistence across scene changes.
- **Add:** `dialogue_history: Array` property (future use).
- **Add:** `save_choices(choices: Array)` / `restore_choices() -> Array` helper methods.

```gdscript
# New properties
var choices_history: Array = []   # [{node_id, choice_index, choice_text}, ...]
var dialogue_history: Array = []  # future: full dialogue traversal log

# New methods
func save_choices(choices: Array) -> void:
    choices_history = choices.duplicate()

func restore_choices() -> Array:
    return choices_history.duplicate()
```

#### `gdscripts/dialogue_runner.gd` — **Modified**

- **Add:** `scene_transition_requested` signal for when a choice contains a `"scene"` field.
- **Note:** This is an alternative to SceneManager intercepting `choice_made`. The cleaner design is SceneManager handling it, so we'll keep the Runtime modifications minimal. Instead, SceneManager reads `current_node.choices[choice_index].scene` directly.

**No modification to DialogueRunner is needed** — SceneManager handles scene transitions externally via `_on_choice_made`. This keeps DialogueRunner pure (no awareness of scene management).

#### `project.godot` — **Modified**

- **Add** StateSystem to `[autoload]`:

```
StateSystem="*res://gdscripts/state_system.gd"
```

---

## 4. Resource / Config Layer

### New Constants (`gdscripts/constants.gd`) — **Modified**

Add scene-related constants:

```gdscript
# Scene Paths
const SCENE_OFFICE: String = "res://scenes/office/office.tscn"
const SCENE_STREET: String = "res://scenes/street/street.tscn"
const SCENE_STORE: String = "res://scenes/store/convenience_store.tscn"

# Fade Transition
const FADE_DURATION: float = 0.5
```

### Autoload Configuration (`project.godot`)

| Key | Value |
|-----|-------|
| `StateSystem` | `"*res://gdscripts/state_system.gd"` (NEW) |

### Dialogue Config Files

| File | Purpose |
|------|---------|
| `dialogues/office_door.json` | **New** — "Leave the office?" / "Enter the store?" branching dialogue |
| `dialogues/store_clerk.json` | **New** — 3+-branch clerk dialogue referencing state + `choices_made` |
| `dialogues/environmental_text.json` | **Deferred** — environmental text variants; instead, text is embedded in scene scripts for simplicity at this scale (3 scenes, ~9 text variants total) |

#### Dialogue: `dialogues/office_door.json`

Two entry points in one file:

- **Entry (office_door):** Player clicks office door → "Leave the office?" with choices:
  - "Step outside" → `{ "scene": "res://scenes/street/street.tscn", "effects": [...] }`
  - "Stay a while longer" → ends conversation (stays in office)
- **Entry (store_entrance):** Player clicks store entrance on street → "Enter the convenience store?" with choices:
  - "Go in" → `{ "scene": "res://scenes/store/convenience_store.tscn" }`
  - "Keep walking" → ends conversation (stays on street)

```json
{
  "entry_node_id": "office_door_prompt",
  "nodes": {
    "office_door_prompt": {
      "speaker": "Narrator",
      "text": "The door looms in front of you.\nLeave the office?",
      "choices": [
        {
          "text": "Step outside.",
          "condition": null,
          "effects": [
            { "type": "set_flag", "flag": "left_office_immediately", "value": true },
            { "type": "slider_delta", "axis": "conviction", "delta": 0.5 }
          ],
          "scene": "res://scenes/street/street.tscn"
        },
        {
          "text": "Stay a while longer.",
          "next_node": "office_stay",
          "effects": []
        }
      ]
    },
    "office_stay": {
      "speaker": "Narrator",
      "text": "You sit back down. The rain taps at the window.\nThe door is still there.",
      "choices": [
        {
          "text": "Step outside.",
          "effects": [
            { "type": "set_flag", "flag": "left_office_hesitated", "value": true },
            { "type": "slider_delta", "axis": "conviction", "delta": 0.3 }
          ],
          "scene": "res://scenes/street/street.tscn"
        },
        {
          "text": "Not yet.",
          "next_node": null,
          "effects": []
        }
      ]
    },
    "store_entrance_prompt": {
      "speaker": "Narrator",
      "text": "The convenience store glows through the rain.\nEnter?",
      "choices": [
        {
          "text": "Go in.",
          "effects": [],
          "scene": "res://scenes/store/convenience_store.tscn"
        },
        {
          "text": "Keep walking.",
          "next_node": "street_walk_away",
          "effects": []
        }
      ]
    },
    "street_walk_away": {
      "speaker": "Narrator",
      "text": "You walk past. The rain keeps falling.\nThe neon sign flickers behind you.",
      "choices": [
        {
          "text": "...",
          "next_node": null,
          "effects": []
        }
      ]
    }
  }
}
```

> **Note on `"scene"` field:** This is a new choice metadata field not currently parsed by DialogueRunner. The SceneManager intercepts `choice_made` and checks `current_node.choices[choice_index].scene` for a scene path. DialogueRunner does not need to understand `"scene"` — it's opaque metadata that SceneManager reads. However, DialogueParser's validation may need a non-breaking update to allow (not require) a `"scene"` key on choices.

#### Dialogue: `dialogues/store_clerk.json`

3+-branch dialogue keyed on player state:

```json
{
  "entry_node_id": "clerk_greet",
  "nodes": {
    "clerk_greet": {
      "speaker": "Clerk",
      "text": "Evening.",
      "choices": [
        {
          "text": "(Clerk greets you warmly)",
          "condition": { "type": "slider", "axis": "hope", "op": "gte", "value": 7 },
          "next_node": "clerk_upbeat",
          "effects": []
        },
        {
          "text": "(Clerk gives a neutral nod)",
          "condition": { "type": "slider", "axis": "hope", "op": "gte", "value": 4 },
          "next_node": "clerk_neutral",
          "effects": []
        },
        {
          "text": "(Clerk looks at you with concern)",
          "condition": { "type": "slider", "axis": "hope", "op": "lt", "value": 4 },
          "next_node": "clerk_concern",
          "effects": []
        },
        {
          "text": "...",
          "next_node": "clerk_silent",
          "effects": []
        }
      ]
    },
    "clerk_upbeat": {
      "speaker": "Clerk",
      "text": "You look... actually okay tonight.",
      "choices": [
        {
          "text": "Yeah. It's a good night.",
          "next_node": "clerk_upbeat_choice",
          "effects": [
            { "type": "slider_delta", "axis": "hope", "delta": 0.5 }
          ]
        },
        {
          "text": "Thanks. Just passing through.",
          "next_node": "clerk_farewell",
          "effects": []
        }
      ]
    },
    "clerk_upbeat_choice": {
      "speaker": "Clerk",
      "text": "Good to hear. You know, most people who come in this late don't say that.\n⌈He was here earlier. Said the same thing.⌋",
      "choices": [
        {
          "text": "He? Who?",
          "next_node": "clerk_stranger_hint",
          "effects": [
            { "type": "set_flag", "flag": "asked_about_stranger", "value": true }
          ]
        },
        {
          "text": "I should get going.",
          "next_node": "clerk_farewell",
          "effects": []
        }
      ]
    },
    "clerk_stranger_hint": {
      "speaker": "Clerk",
      "text": "Just a regular. Tall. Wears a coat even inside.\n⌈You'll know him when you see him.⌋",
      "choices": [
        {
          "text": "... Right.",
          "next_node": "clerk_farewell",
          "effects": [
            { "type": "set_flag", "flag": "stranger_hint_received", "value": true }
          ]
        }
      ]
    },
    "clerk_neutral": {
      "speaker": "Clerk",
      "text": "Evening. The usual?",
      "choices": [
        {
          "text": "Yeah. Same as always.",
          "next_node": "clerk_farewell",
          "effects": [
            { "type": "slider_delta", "axis": "hope", "delta": 0.3 }
          ]
        },
        {
          "text": "Not tonight. Just looking.",
          "next_node": "clerk_farewell",
          "effects": []
        }
      ]
    },
    "clerk_concern": {
      "speaker": "Clerk",
      "text": "Rough night? You look tired.",
      "choices": [
        {
          "text": "You have no idea.",
          "next_node": "clerk_farewell",
          "effects": [
            { "type": "slider_delta", "axis": "hope", "delta": 0.5 }
          ]
        },
        {
          "text": "I'm fine.",
          "next_node": "clerk_farewell",
          "effects": []
        },
        {
          "text": "...",
          "next_node": "clerk_silent",
          "effects": [
            { "type": "slider_delta", "axis": "despair", "delta": 0.3 }
          ]
        }
      ]
    },
    "clerk_silent": {
      "speaker": "Clerk",
      "text": "... Right.",
      "choices": [
        {
          "text": "...",
          "next_node": null,
          "effects": []
        }
      ]
    },
    "clerk_farewell": {
      "speaker": "Clerk",
      "text": "Take care.",
      "choices": [
        {
          "text": "You too.",
          "next_node": null,
          "effects": []
        }
      ]
    }
  }
}
```

### DialogueParser Validation Update

| Change | Reason |
|--------|--------|
| Allow (not require) `"scene"` key on choice objects | New metadata field for scene transitions — opaquely passed through DialogueRunner to SceneManager. Parser currently checks `next_node` references but doesn't reject unknown keys. No parser change needed unless a validation rule explicitly errors on unknown keys. |

---

## 5. Asset / Visual Layer

### New Assets

| Asset | Type | Usage |
|-------|------|-------|
| `assets/materials/office_floor.tres` | Material | Dark wood/concrete floor material for office |
| `assets/materials/wall_brick.tres` | Material | Brick facade material for street |
| `assets/materials/wet_asphalt.tres` | Material | Wet street surface with slight reflection |
| `assets/materials/store_floor.tres` | Material | Linoleum floor for convenience store |
| `assets/materials/desk_lamp.tres` | Material | Emissive material for desk lamp glow |

### LoFiText3D Configuration Per Scene

| Scene | Node ID | Mode | Properties |
|-------|---------|------|------------|
| Office | `WindowText` | Billboard | `pixel_factor=0.4`, `color_bits=8`, `scanline_intensity=0.2`, emissive off. Text set by script. |
| Street | `NeonSign` | Billboard / Emissive | `pixel_factor=0.5`, `color_bits=6`, `scanline_intensity=0.3`, `emissive_color=Color.ORANGE`, `emissive_strength=2.0`. Modulate set by script. |
| Street | `StreetSign` | Flat Sign | `pixel_factor=0.3`, `color_bits=8`, stationary. Text: "ELM ST." |
| Street | `Graffiti` | Flat Sign | `pixel_factor=0.6`, `color_bits=4`, faded alpha. Text set by script. |
| Store | `OpenSign` | Billboard / Emissive | `pixel_factor=0.4`, `color_bits=6`, `scanline_intensity=0.2`, `emissive_color=Color(1.0, 0.3, 0.0)`, `emissive_strength=1.5`. Text set by script. |
| Store | `ShelfLabels` | Flat Sign | Ambient detail text. |

### Fade Curtain CanvasLayer

Each scene contains a `CanvasLayer` named `FadeCurtain`:

```
FadeCurtain (CanvasLayer, layer=128 — above everything)
└── ColorRect (full-screen, Color.BLACK, modulate.a=0)
    └── AnimationPlayer
        └── "fade_out": modulate.a 0→1 (0.5s, ease-in)
        └── "fade_in":  modulate.a 1→0 (0.5s, ease-out)
```

---

## 6. Input / UI Layer

### New Interaction Pattern

No new keyboard input bindings are needed. All interactions are **mouse-based**:

| Action | Trigger | Implementation |
|--------|---------|----------------|
| Interact with office door | Mouse click on `Area3D("office_door_trigger")` | `input_event` signal → start `dialogues/office_door.json` |
| Interact with store entrance | Mouse click on `Area3D("store_entrance_trigger")` | `input_event` signal → start `dialogues/office_door.json` (store_entrance_prompt node) |
| Interact with clerk | Mouse click on `Area3D("clerk_trigger")` | `input_event` signal → start `dialogues/store_clerk.json` |

> **Cursor hint pattern (deferred):** A future issue will add a hover highlight effect on interactable Area3Ds. For now, the player clicks around the scene to find interactable zones.

### Persistent Keyboard Actions

| Key | Action | Existing/New |
|-----|--------|-------------|
| F9 | Toggle dialogue debug (start bartender.json) | Existing (dev only) |
| F12 | Toggle debug overlay | Existing (dev only) |

### Dialogue UI Overlay

The existing `dialogue_panel.tscn` (CanvasLayer with RichTextLabel + choice buttons) is reused in each scene unchanged. The only addition is the SceneManager intercepting choice selection to detect `"scene"` metadata.

---

## 7. Test Layer

> **设计原则：Plan 只写测试描述，不写可运行测试代码。** 可运行测试文件在 Implement 阶段由 implement agent 从 DESIGN doc 的测试描述生成。

### Test Structure

- **New test file:** `tests/test_scene_sequence.gd` — Tests for scene transitions, state persistence, environmental text configuration, and dialogue→transition integration.
- **Existing test file modified:** `tests/run_tests.gd` — Add call to `run_scene_sequence_tests()`.
- **Test mode:** Godot headless (`--script` mode). Since `change_scene_to_file()` cannot run in `--script` mode (no SceneTree), tests use isolated unit tests of the individual script components (SceneManager logic, text configuration functions, `choices_history` persistence) — not integration tests with actual scene loading.

### Test Case Descriptions

#### TC-S1: SceneManager — Transition State Machine (Normal Path)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S1-1 | Normal scene transition | Create SceneManager, call `trigger_scene_change("res://scenes/street/street.tscn")` | `transition_in_progress` becomes `true`, `transition_started` signal emitted | `_assert(sm.transition_in_progress == true)` + `_assert(transition_started_fired == true)` |
| TC-S1-2 | Transition lockout | Call `trigger_scene_change()` twice rapidly | Second call ignored (blocked by `transition_in_progress`) | `_assert(second_call_count == 0)` |
| TC-S1-3 | Dialogue state persisted before transition | Set up mock GameManager with `choices_history`, SceneManager with mock DialogueRunner containing `choices_made` | Before scene change, `choices_made` copied to `GameManager.choices_history` | `_assert(gm.choices_history.size() > 0)` + `_assert(gm.choices_history[0].has("node_id"))` |

#### TC-S2: SceneManager — Scene Detection in Choice Metadata (Edge Cases)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S2-1 | Choice has `"scene"` field | Choice `{"text": "Leave", "scene": "street.tscn"}` intercepted | `trigger_scene_change("street.tscn")` called | `_assert(scene_change_called_with == "street.tscn")` |
| TC-S2-2 | Choice has no `"scene"` field | Choice `{"text": "Stay", "next_node": "remain"}` | No scene change | `_assert(scene_change_not_called)` |
| TC-S2-3 | Choice has `"scene"` field + empty string | Choice `{"text": "Leave", "scene": ""}` | No scene change (empty path = no-op) | `_assert(scene_change_not_called)` |
| TC-S2-4 | SceneManager not connected to dialogue | SceneManager in scene but no DialogueRunner child | No crash on choice echoes | `_assert(sm._on_choice_made(0, "test") == null)` |

#### TC-S3: GameManager — Choices Persistence Across Transitions

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S3-1 | Save and restore choices | `gm.save_choices([{"node_id": "a", "choice_index": 0, "choice_text": "Leave"}])` then `gm.restore_choices()` | Restored array matches saved array | `_assert(restored.size() == 1)` + `_assert(restored[0].node_id == "a")` |
| TC-S3-2 | Save empty choices | `gm.save_choices([])` then restore | Empty array returned | `_assert(restored.is_empty())` |
| TC-S3-3 | Deep copy isolation | Save choices, modify the original array, restore | Restored array is unchanged (not a reference) | `_assert(restored == original_saved)` and `restored != modified_source` |

#### TC-S4: Environmental Text — State-Dependent Configuration (Normal + Boundary)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S4-1 | Office window text at hope=8 | Call `office._configure_environmental_text()` with `hope=8.0` | Window text contains "city glitters" variant | `_assert(window_text.contains("city glitters"))` |
| TC-S4-2 | Office window text at hope=5 | Call with `hope=5.0` | Neutral variant: "Another night" | `_assert(window_text.contains("Another night"))` |
| TC-S4-3 | Office window text at hope=2 | Call with `hope=2.0` | Despair variant: "streetlights blur" | `_assert(window_text.contains("streetlights blur"))` |
| TC-S4-4 | All office variants contain Stranger line | Call at hope=2, 5, 8 | All have `"someone walks the same streets"` | `_assert(window_text.contains("someone walks"))` for all three |
| TC-S4-5 | Street neon sign conviction=8 | Call `street._configure_environmental_text()` with `conviction=8.0` | Warm amber modulate | `_assert(neon.modulate.r > 0.9)` (check r channel) |
| TC-S4-6 | Street neon sign conviction=3 | Call with `conviction=3.0` | Dim red modulate | `_assert(neon.modulate.r < 0.9 and neon.modulate.g < 0.3)` |
| TC-S4-7 | Street graffiti hope=7 | Call with `hope=7.0` | "this too shall pass" | `_assert(graffiti.text == "this too shall pass")` |
| TC-S4-8 | Street graffiti hope=3 | Call with `hope=3.0` | "i was here" | `_assert(graffiti.text == "i was here")` |
| TC-S4-9 | Store OPEN sign hope=6, conviction=5 | Call `store._configure_environmental_text()` with `hope=6.0, conviction=5.0` | Includes Stranger subtitle | `_assert(open_sign.text.contains("He was here"))` |
| TC-S4-10 | Store OPEN sign hope=3, conviction=5 | Call with `hope=3.0, conviction=5.0` | No subtitle, just "OPEN" | `_assert(open_sign.text == "OPEN")` |

#### TC-S5: State Persistence — StateSystem Autoload Integration

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S5-1 | StateSystem accessible at `/root/StateSystem` | Check `get_node_or_null("/root/StateSystem")` | Returns StateSystem node | `_assert(ss != null)` |
| TC-S5-2 | WorldviewController reads state from autoload | Create WV controller, it connects via `_ready()` to `/root/StateSystem` | Signal connection succeeds | `_assert(wv._ready_connected == true)` |
| TC-S5-3 | RainController reads state from autoload | Create RC, call `_on_state_changed` with conviction=3 | Rain intensity = 0.7 | `_assert(abs(rc.get_intensity() - 0.7) < 0.001)` |

#### TC-S6: Dialogue → Scene Transition Integration (Failure Paths)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S6-1 | SceneManager handles missing dialogue file | `dialogue_runner.start("bad_path.json")` returns false | No crash, error logged, fallback text appears | `_assert(error_logged == true)` |
| TC-S6-2 | SceneManager handles scene load failure | `change_scene_to_file("bad_path.tscn")` returns ERR | Error logged, current scene stays, `transition_in_progress` reset | `_assert(sm.transition_in_progress == false)` |
| TC-S6-3 | Dialogue panel open during scene change | Scene change triggered while dialogue panel visible | SceneManager emits `dialogue_ended` before changing scene | `_assert(dialogue_ended_emitted == true)` |

---

## 8. Files Changed (per-layer summary)

### Scene Tree Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/office/office.tscn` | **New** — office interior scene | +120 |
| `scenes/street/street.tscn` | **New** — rainy street scene | +150 |
| `scenes/store/convenience_store.tscn` | **New** — convenience store interior | +130 |
| `scenes/main.tscn` | **Modify** — restructure as boot scene; add FadeCurtain CanvasLayer stub | +15 |

### GDScript / Logic Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/scene_manager.gd` | **New** — scene transition orchestrator | +100 |
| `gdscripts/office.gd` | **New** — office scene init script | +65 |
| `gdscripts/street.gd` | **New** — street scene init script | +85 |
| `gdscripts/store.gd` | **New** — store scene init script | +55 |
| `gdscripts/main.gd` | **Modify** — delegate to SceneManager on boot | +10 |
| `gdscripts/game_manager.gd` | **Modify** — add `choices_history` + save/restore methods | +15 |

### Resource / Config Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `dialogues/office_door.json` | **New** — door + entrance dialogue | +60 |
| `dialogues/store_clerk.json` | **New** — 3+-branch clerk dialogue | +85 |
| `project.godot` | **Modify** — add StateSystem autoload | +1 |
| `gdscripts/constants.gd` | **Modify** — add scene path constants | +5 |

### Asset / Visual Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `assets/materials/office_floor.tres` | **New** — dark wood floor material | +10 |
| `assets/materials/wall_brick.tres` | **New** — brick facade material | +10 |
| `assets/materials/wet_asphalt.tres` | **New** — wet street material | +10 |
| `assets/materials/store_floor.tres` | **New** — linoleum floor material | +10 |
| `assets/materials/desk_lamp.tres` | **New** — desk lamp emissive material | +10 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_scene_sequence.gd` | **New** — scene transition + persistence + text tests | +250 |
| `tests/run_tests.gd` | **Modify** — add `run_scene_sequence_tests()` call | +4 |

---

## 9. Verification Checklist

- [ ] TC-S1-1 through TC-S1-3: SceneManager transition state machine works (lockout, signal emission, dialogue persistence)
- [ ] TC-S2-1 through TC-S2-4: SceneManager correctly detects `"scene"` field in choice metadata
- [ ] TC-S3-1 through TC-S3-3: `choices_history` save/restore in GameManager preserves data and creates deep copies
- [ ] TC-S4-1 through TC-S4-10: All environmental text variants correctly reflect GameState (hope/conviction thresholds)
- [ ] TC-S5-1 through TC-S5-3: StateSystem autoload accessible at `/root/StateSystem`; WorldviewController / RainController connect successfully
- [ ] TC-S6-1 through TC-S6-3: Error paths handled gracefully (missing dialogue file, scene load failure, dialogue panel during transition)
- [ ] `godot --headless --script tests/run_tests.gd` — all tests pass, 0 failures
- [ ] No regression: existing dialogue engine tests still pass
- [ ] No regression: existing state system tests still pass
- [ ] StateSystem added to `project.godot` `[autoload]` section
- [ ] `choices_history` persists across `change_scene_to_file()` cycles
- [ ] Dialogue JSON `"scene"` field does not break existing DialogueParser validation
- [ ] All three scenes load independently in the Godot editor
