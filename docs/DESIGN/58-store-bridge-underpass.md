# Design: #58 — [Scene] Convenience Store → Bridge → Underpass

> Parent Issue: #58
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Implement the game's second scene sequence: player exits the **convenience store**, crosses a **bridge** over a dark canal, and descends into an **underpass**. The sequence culminates in an encounter with the Mysterious Stranger (echo dialogue). Branching dialogue in the underpass leads to three endings (via the upcoming subway station). This sequence is the **emotional climax** of the game — it carries the death-and-rebirth themes from Project YOUTH, with the underpass as a liminal space, and the Stranger's true nature revealed only on deep playthroughs.

Three depth layers as specified:
- **Shallow (AC1):** Player navigates store → bridge → underpass with 3 scene transitions
- **Middle (AC2):** Bridge text responds to earlier convenience store choice; Stranger dialogue has two visible layers
- **Deep (AC3):** Underpass hidden text (visible only at high despair) reveals Stranger as projection

### Data Flow

```
Convenience Store (existing)
    │ Player completes clerk dialogue
    │ Interacts with exit trigger
    │ advance_scene() → NarrativeManager.current_scene_index: 2→3
    │ change_scene_to_file("res://scenes/bridge/bridge.tscn")
    ▼
Bridge (NEW scene geometry + existing bridge.gd script)
    │ _ready() → fade_in → _configure_environmental_text() (based on will)
    │
    │ Interactions:
    │   Railing (俯瞰) → state-aware environmental text
    │   Homeless NPC → bridge_homeless.json → screensaver_echo set
    │   Low conviction → intrusive thought (内心独白)
    │   Bridge Exit → advance_scene() → index: 3→4
    │
    │ change_scene_to_file("res://scenes/underpass/underpass.tscn")
    ▼
Underpass (NEW scene geometry + existing underpass.gd script)
    │ _ready() → fade_in → _configure_environmental_text() (based on hope+conviction)
    │ _check_echoes() → check previously triggered echoes
    │
    │ Interactions:
    │   Graffiti → memory flashback (based on hope)
    │   Stranger Echo → underpass_stranger_echo.json (3 branches)
    │     ├── "我知道…" → hope+1, conviction+1, will+1
    │     ├── "不关你的事" → hope-1, conviction-1, will-1
    │     └── 沉默走过 → no change
    │
    │   High despair (hope ≤ 2 AND conviction ≤ 2): hidden text reveals Stranger as projection
    │
    │ Exit → advance_scene() → index: 4→5
    │ change_scene_to_file("res://scenes/subway_station/subway_station.tscn")
    ▼
Subway Station (future issue — endgame)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scene approach | **Scheme A** — standalone `.tscn` per scene (same as #55) | Scripts already written for independent scenes; NarrativeManager.SCENE_ORDER has bridge+underpass as separate entries; fade transitions reinforce nocturnal walking rhythm |
| Bridge geometry | CSG primitives (box bridge + railing + canal) | No external 3D assets needed. Matches the lo-fi Hopper aesthetic from #55. |
| Underpass geometry | CSG tunnel + wall planes with placeholder graffiti | Tunnel ambiance (dark floor, wet walls, flickering overhead lights) via CSG + OmniLight3D animation |
| despair mapping for AC3 | Map "despair < -5" to `state_system.gd`: **hope ≤ 2.0 AND conviction ≤ 2.0** | PRD Experiment A outcome — both state_system axes are 0–10. The "despair" concept maps to combined low hope + low conviction. If `game_state.gd.despair` is used, threshold set at despair ≥ 80. |
| Stranger dialogue 2-layer | Conditional branches in JSON using `flag` + `slider` condition types | PRD Experiment C outcome — approx 6 extra nodes, each branch has 2 variants (with/without echo flag) |
| Echo integration | Bridge intrusive thought also triggers `nm.trigger_echo("screensaver_echo")` | PRD Experiment B outcome — ensures diverge (intrusive thought) and converge (echo flags) are synchronized |
| Camera model | Fixed camera per scene | No CharacterBody3D needed. Each scene has 3–4 Area3D clickable triggers. Follows #55 compose-frame aesthetic. |
| Fade transition | CanvasLayer modulate animation (0.5s fade-out, 0.5s fade-in) | Same as #55. `transition_in_progress` flag prevents rapid double-trigger. |

---

## 2. Node / Scene Tree Layer

### Scene Template (shared by bridge.tscn and underpass.tscn)

Following the pattern established in #55:

```
Root: Node3D ("SceneRoot")
├── Camera3D ("MainCamera") — positioned per scene
├── WorldEnvironment — dark urban night settings
├── DirectionalLight3D — dim cool ambient
├── Environments
│   ├── StaticBody3D (bridge/canal or tunnel walls/floor)
│   └── LoFiText3D instances (environmental text)
├── InteractionZones
│   ├── Area3D trigger points (railing, homeless, exit / graffiti, stranger_echo, exit)
├── CanvasLayer ("DialogueUI")
│   ├── DialoguePanel (DialogueRunner.gd) — shared reused instance
│   └── FadeCurtain (ColorRect + AnimationPlayer) — fade_out / fade_in
└── SceneManager (Node, gdscripts/scene_manager.gd) — orchestrates transitions
```

### New Scene: `scenes/bridge/bridge.tscn` — **Modified (fill geometry)**

Currently exists as a skeleton. Must add:

- **Root:** Node3D ("BridgeRoot") — **existing**, attach `gdscripts/bridge.gd`
- **Lighting:** Cool blue ambient + one warm OmniLight3D at the midpoint (streetlamp on bridge). Dim overall.
- **Camera3D:** Positioned at bridge entrance, looking across the span — player sees the canal below, far city lights dimly
- **WorldEnvironment:** Dark night sky (`#1a1a2e`), glow enabled for distant city light emission
- **Geometry (CSG primitives):**
  - Bridge deck: CSGBox3D (wide flat box spanning Z-axis)
  - Left/right railings: CSGBox3D (low barriers with gaps for visual interest)
  - Canal below: CSGBox3D (dark surface, slight reflect)
  - Distant buildings: CSGBox3D silhouettes (just dark rectangles)
  - Streetlamp: CSGCylinder3D (pole) + CSGSphere3D (lamp housing) + OmniLight3D
- **LoFiText3D instances (existing):**
  - `TrafficText` (Billboard) — "Traffic flows below the bridge…" (will-dependent)
  - `HomelessText` (Billboard) — text near homeless spot
  - `RainBridgeText` (Billboard) — ambient rain/weather text
- **Interaction Zones (existing):**
  - `RailingTrigger` (Area3D) — click → state-aware text display (not a dialogue, just text)
  - `HomelessTrigger` (Area3D) — click → start `dialogues/bridge_homeless.json`
  - `BridgeExitTrigger` (Area3D) — click → scene transition to underpass
- **CanvasLayer:** Standard (DialoguePanel + FadeCurtain)
- **SceneManager:** Standard (attached to BridgeRoot)

#### Node Tree

```
BridgeRoot (Node3D, script: bridge.gd)
├── Camera3D ("MainCamera")
├── WorldEnvironment
├── DirectionalLight3D
├── OmniLight3D ("StreetLampLight") — warm, on pole
├── Environments
│   ├── StaticBody3D ("BridgeDeck") — CSGBox3D
│   ├── StaticBody3D ("RailingLeft") — CSGBox3D
│   ├── StaticBody3D ("RailingRight") — CSGBox3D
│   ├── StaticBody3D ("CanalSurface") — CSGBox3D
│   ├── StaticBody3D ("DistantBuilding1") — CSGBox3D
│   ├── StaticBody3D ("DistantBuilding2") — CSGBox3D
│   ├── StaticBody3D ("DistantBuilding3") — CSGBox3D
│   ├── StaticBody3D ("StreetLampPole") — CSGCylinder3D
│   └── LoFiText3D ("TrafficText") — existing
│   └── LoFiText3D ("HomelessText") — existing
│   └── LoFiText3D ("RainBridgeText") — existing
├── InteractionZones
│   ├── Area3D ("RailingTrigger") — existing
│   ├── Area3D ("HomelessTrigger") — existing
│   └── Area3D ("BridgeExitTrigger") — existing
├── CanvasLayer ("DialogueUI")
│   ├── DialoguePanel (DialogueRunner.gd)
│   └── FadeCurtain
│       ├── ColorRect
│       └── AnimationPlayer
└── SceneManager (gdscripts/scene_manager.gd)
```

### New Scene: `scenes/underpass/underpass.tscn` — **Modified (fill geometry)**

Currently exists as a skeleton. Must add:

- **Root:** Node3D ("UnderpassRoot") — **existing**, attach `gdscripts/underpass.gd`
- **Lighting:** Dim cool blue OmniLight3D + one flickering fluorescent OmniLight3D (animated modulate intensity via Tween)
- **Camera3D:** Positioned at underpass entrance, looking down the tunnel — exit light visible in distance
- **WorldEnvironment:** Very dark, slight fog for depth
- **Geometry (CSG primitives):**
  - Tunnel floor: CSGBox3D (wide flat)
  - Left wall: CSGBox3D (tall, textured with placeholder graffiti)
  - Right wall: CSGBox3D (tall)
  - Ceiling: CSGBox3D (low — claustrophobic feel)
  - Exit door/arch: CSGBox3D with opening
  - Tunnel end light: ColorRect or point light (distant exit glow)
- **LoFiText3D instances (existing):**
  - `GraffitiText` (Flat Sign) — state-aware graffiti text on walls (visibility depends on hope)
  - `EchoText` (Billboard) — echo text (screensaver_echo / rain_echo variants). **Hidden text holder for AC3** — set visible=false by default, conditionally shown when despair threshold met.
  - `UnderpassLight` (Billboard) — ambient text describing the tunnel lighting
- **Interaction Zones (existing):**
  - `GraffitiTrigger` (Area3D) — click → memory flashback text (based on hope)
  - `StrangerEchoTrigger` (Area3D) — click → start `dialogues/underpass_stranger_echo.json`
  - `UnderpassExitTrigger` (Area3D) — click → scene transition to subway_station
- **CanvasLayer:** Standard (DialoguePanel + FadeCurtain)
- **SceneManager:** Standard (attached to UnderpassRoot)

#### Node Tree

```
UnderpassRoot (Node3D, script: underpass.gd)
├── Camera3D ("MainCamera")
├── WorldEnvironment
├── DirectionalLight3D
├── OmniLight3D ("CeilingLight1") — warm, flickering
├── OmniLight3D ("CeilingLight2") — warm, dim
├── Environments
│   ├── StaticBody3D ("TunnelFloor") — CSGBox3D
│   ├── StaticBody3D ("TunnelWallLeft") — CSGBox3D
│   ├── StaticBody3D ("TunnelWallRight") — CSGBox3D
│   ├── StaticBody3D ("TunnelCeiling") — CSGBox3D
│   ├── StaticBody3D ("TunnelEndArch") — CSGBox3D with gap
│   └── LoFiText3D ("GraffitiText") — existing
│   └── LoFiText3D ("EchoText") — existing (AC3 hidden text target)
│   └── LoFiText3D ("UnderpassLight") — existing
├── InteractionZones
│   ├── Area3D ("GraffitiTrigger") — existing
│   ├── Area3D ("StrangerEchoTrigger") — existing
│   └── Area3D ("UnderpassExitTrigger") — existing
├── CanvasLayer ("DialogueUI")
│   ├── DialoguePanel (DialogueRunner.gd)
│   └── FadeCurtain
│       ├── ColorRect
│       └── AnimationPlayer
└── SceneManager (gdscripts/scene_manager.gd)
```

### Existing Scene Modification: `scenes/store/convenience_store.tscn` — **Modified**

- **Add:** `StoreExitTrigger` Area3D (or reuse existing exit zone if present) that connects to bridge scene
- The exit trigger starts a short dialogue or directly transitions via `advance_scene()` → `change_scene_to_file("res://scenes/bridge/bridge.tscn")`
- Follow the #55 pattern: choice with `"scene"` metadata field triggers scene transition via SceneManager

---

## 3. GDScript / Logic Layer

### Existing Script: `gdscripts/bridge.gd` — **No changes needed**

At 87 lines, this script is already complete:

- `_get_tone()` — returns `tired`/`determined`/`neutral` based on will value (≤3 tired, ≥7 determined)
- `_set_environmental_text()` — three sets of state texts
- `_check_intrusive_thought()` — triggers when conviction ≤ 2.0, displays despair text
- Railings → state-aware text
- Homeless → dialogue (bridge_homeless.json)
- Exit → scene transition

**Verified additions (to confirm in implementation):**
- `_ready()` calls `scene_manager.fade_in()` after environment text setup
- Intrusive thought path also calls `NarrativeManager.trigger_echo("screensaver_echo")` to synchronize with echo system

### Existing Script: `gdscripts/underpass.gd` — **No changes needed**

At 105 lines, this script is already complete:

- `_get_tone()` — returns `despair`/`resolute`/`neutral` based on hope+conviction composite
- `_check_echoes()` — integrates `screensaver_echo` and `rain_echo` echo systems
- Graffiti → memory flashback (based on hope)
- Stranger Echo → dialogue (underpass_stranger_echo.json)
- Exit → scene transition

**Verified additions (to confirm in implementation):**
- `_ready()` calls `scene_manager.fade_in()`
- AC3 hidden text condition check: if `hope ≤ 2.0 AND conviction ≤ 2.0`, set `EchoText.visible = true` and change text to Stranger-as-projection reveal

### Existing Script: `gdscripts/store.gd` — **Modified (add exit trigger)**

Add exit trigger handler. The store script needs an additional Area3D connection:

```gdscript
# New @onready
@onready var exit_trigger: Area3D = $InteractionZones/StoreExitTrigger

# In _ready()
exit_trigger.input_event.connect(_on_exit_trigger_input)

# New handler
func _on_exit_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _start_exit_dialogue()

func _start_exit_dialogue() -> void:
    dialogue_runner.start("res://dialogues/store_exit.json", "store_exit")
```

### `convenience_store.tscn` — **Modify** (add exit trigger Area3D)

Add `StoreExitTrigger` Area3D near the store entrance (visible to player after clerk dialogue).

### Dialogue Config: `dialogues/bridge_homeless.json` — **Already exists (no changes needed)**

3-choice dialogue (give change / stop and listen / walk past). Sets `screensaver_echo_heard` flag. Effects modify conviction/hope.

### Dialogue Config: `dialogues/underpass_stranger_echo.json` — **Modified (add 2nd layer)**

Currently has 1 layer (3 branches: admit/deny/silence). Must add conditional variants per PRD Experiment C:

- **Layer 1 (visible to all):** Current 3 branches
- **Layer 2 (visible when `screensaver_echo_heard == true` or `conviction < 4`):**
  - Each branch gets a variant with sharper/sadder dialogue
  - Example: Admit branch → if `screensaver_echo_heard`, Stranger says "……你听到了，是吧。那条声音。" vs default "……好。那就走吧。"
  - Conditions use `flag` type (`screensaver_echo_heard`) and `slider` type (`conviction`)

**Estimated expansion:** ~73 lines → ~150 lines (6 additional conditional node variants)

### New Dialogue: `dialogues/store_exit.json`

Short exit dialogue that triggers scene transition to bridge:

```json
{
  "entry_node_id": "store_exit_prompt",
  "nodes": {
    "store_exit_prompt": {
      "speaker": "Narrator",
      "text": "The door swings open. Cold air hits your face.\n⌈The rain has stopped.⌋\nA bridge stretches across the dark canal ahead.",
      "choices": [
        {
          "text": "Walk toward the bridge.",
          "effects": [],
          "scene": "res://scenes/bridge/bridge.tscn"
        },
        {
          "text": "Stand in the doorway a moment longer.",
          "next_node": "store_exit_stand",
          "effects": [
            { "type": "slider_delta", "axis": "will", "delta": -0.3 }
          ]
        }
      ]
    },
    "store_exit_stand": {
      "speaker": "Narrator",
      "text": "The night stretches out. Somewhere, a dog barks.\nThe bridge waits.",
      "choices": [
        {
          "text": "Walk toward the bridge.",
          "effects": [],
          "scene": "res://scenes/bridge/bridge.tscn"
        },
        {
          "text": "...",
          "next_node": "store_exit_stand_go",
          "effects": [
            { "type": "slider_delta", "axis": "hope", "delta": -0.5 }
          ]
        }
      ]
    },
    "store_exit_stand_go": {
      "speaker": "Narrator",
      "text": "You push off the doorframe. The bridge is your only way forward.",
      "choices": [
        {
          "text": "Go.",
          "effects": [],
          "scene": "res://scenes/bridge/bridge.tscn"
        }
      ]
    }
  }
}
```

### No Changes Needed

| Script | Reason |
|--------|--------|
| `gdscripts/scene_manager.gd` | Already handles transitions. No bridge/underpass-specific changes. |
| `gdscripts/narrative_manager.gd` | SCENE_ORDER already includes bridge (index 3) and underpass (index 4). |
| `gdscripts/state_system.gd` | No state axis changes. despair mapping is handled in underpass.gd. |
| `gdscripts/main.gd` | No changes. Boot → SceneManager → first scene already works. |
| `gdscripts/subway_station.gd` | Future issue. |

---

## 4. Resource / Config Layer

### New Dialogue File

| File | Purpose | Est. Size |
|------|---------|-----------|
| `dialogues/store_exit.json` | **New** — store exit → bridge transition dialogue | ~40 lines |

### Modified Dialogue File

| File | Change | Est. Size |
|------|--------|-----------|
| `dialogues/underpass_stranger_echo.json` | Add conditional 2nd-layer variants per AC2 | ~73→150 lines |

### Existing Dialogue Files (no changes)

| File | Reason |
|------|--------|
| `dialogues/bridge_homeless.json` | Already complete (3 options, screensaver_echo flag) |

### Constants Update (`gdscripts/constants.gd`)

```gdscript
# Add scene paths for #58
const SCENE_BRIDGE: String = "res://scenes/bridge/bridge.tscn"
const SCENE_UNDERPASS: String = "res://scenes/underpass/underpass.tscn"

# Depair thresholds for AC3
const DESPAIR_HOPE_THRESHOLD: float = 2.0
const DESPAIR_CONVICTION_THRESHOLD: float = 2.0
```

---

## 5. Asset / Visual Layer

### New Materials

| Asset | Type | Usage |
|-------|------|-------|
| `assets/materials/bridge_asphalt.tres` | Material | Bridge deck surface (dark grey, slight texture) |
| `assets/materials/canal_water.tres` | Material | Canal surface (dark, slight reflective) |
| `assets/materials/tunnel_wall.tres` | Material | Underpass wall (rough concrete, dark) |
| `assets/materials/tunnel_floor.tres` | Material | Underpass floor (wet, slight reflection) |
| `assets/materials/building_silhouette.tres` | Material | Distant building facade (flat dark/black) |

### LoFiText3D Configuration Per Scene

| Scene | Node ID | Mode | Properties |
|-------|---------|------|------------|
| Bridge | `TrafficText` | Billboard | `pixel_factor=0.4`, `color_bits=8`, `scanline_intensity=0.3`. Text set by `bridge.gd._set_environmental_text()` |
| Bridge | `HomelessText` | Billboard | `pixel_factor=0.4`, `color_bits=6`. Ambient text near homeless NPC |
| Bridge | `RainBridgeText` | Billboard | `pixel_factor=0.5`, `color_bits=6`. Post-rain atmosphere text |
| Underpass | `GraffitiText` | Flat Sign | `pixel_factor=0.6`, `color_bits=4`, faded alpha. Text set by script. |
| Underpass | `EchoText` | Billboard | `pixel_factor=0.4`, `color_bits=6`, `scanline_intensity=0.4`. Visible only when echo triggered. **For AC3**: also shown when despair threshold met, with reveal text. |
| Underpass | `UnderpassLight` | Billboard | `pixel_factor=0.3`, `color_bits=8`. Ambient lighting description. |

### Fade Curtain CanvasLayer

Same pattern as #55 — each scene contains a `FadeCurtain` CanvasLayer:

```
FadeCurtain (CanvasLayer, layer=128)
└── ColorRect (full-screen, Color.BLACK, modulate.a=0)
    └── AnimationPlayer
        └── "fade_out": modulate.a 0→1 (0.5s, ease-in)
        └── "fade_in":  modulate.a 1→0 (0.5s, ease-out)
```

---

## 6. Input / UI Layer

### New Interaction Pattern

| Action | Trigger | Implementation |
|--------|---------|----------------|
| Store exit → Bridge | Click on `Area3D("StoreExitTrigger")` | `input_event` → start `dialogues/store_exit.json` → choice with `"scene"` → transition |
| Bridge railing | Click on `Area3D("RailingTrigger")` | Direct text display (not dialogue) — state-aware description |
| Bridge homeless | Click on `Area3D("HomelessTrigger")` | Start `dialogues/bridge_homeless.json` |
| Bridge exit → Underpass | Click on `Area3D("BridgeExitTrigger")` | `advance_scene()` → transition to underpass |
| Underpass graffiti | Click on `Area3D("GraffitiTrigger")` | Memory flashback text based on hope |
| Underpass Stranger | Click on `Area3D("StrangerEchoTrigger")` | Start `dialogues/underpass_stranger_echo.json` |
| Underpass exit → Subway | Click on `Area3D("UnderpassExitTrigger")` | `advance_scene()` → transition to subway station |

### Persistent Keyboard Actions

Same as #55 — F9 for debug dialogue toggle, F12 for debug overlay. No new bindings.

### Dialogue UI Overlay

Reuses existing `dialogue_panel.tscn` unchanged. SceneManager intercepts `choice_made` to detect `"scene"` metadata for transitions.

---

## 7. Test Layer

> **Design principle:** Plan phase writes test descriptions only. Runnable test files are generated by the implement agent from these descriptions.

### Test Structure

- **New test file:** `tests/test_bridge_underpass.gd` — Tests for bridge/underpass scene logic, AC1/AC2/AC3 conditions, echo integration, and dialogue second-layer branching.
- **Existing test file modified:** `tests/run_tests.gd` — Add call to `run_bridge_underpass_tests()`.
- **Test mode:** Godot headless (`--script` mode). Individual script component unit tests (bridge.gd, underpass.gd functions) — not integration tests with actual scene loading.

### Test Case Descriptions

#### TC-B1: Bridge — Environmental Text State Dependence (Normal Path)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B1-1 | Bridge text at will=2 (tired) | Call `bridge._get_tone()` with `will=2.0` | Returns `"tired"` | `_assert(tone == "tired")` |
| TC-B1-2 | Bridge text at will=5 (neutral) | Call `bridge._get_tone()` with `will=5.0` | Returns `"neutral"` | `_assert(tone == "neutral")` |
| TC-B1-3 | Bridge text at will=8 (determined) | Call `bridge._get_tone()` with `will=8.0` | Returns `"determined"` | `_assert(tone == "determined")` |
| TC-B1-4 | Bridge text boundary will=3 | Call `bridge._get_tone()` with `will=3.0` | Returns `"tired"` (≤3) | `_assert(tone == "tired")` |
| TC-B1-5 | Bridge text boundary will=7 | Call `bridge._get_tone()` with `will=7.0` | Returns `"determined"` (≥7) | `_assert(tone == "determined")` |
| TC-B1-6 | Text set matches tone | Call `bridge._set_environmental_text()` with `will=2.0` | `TrafficText` contains tired variant text | `_assert(traffic_text.contains("exhaust"))` or similar despair keyword |

#### TC-B2: Bridge — Intrusive Thought (Edge Case)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B2-1 | Low conviction triggers intrusive thought | Call `bridge._check_intrusive_thought()` with `conviction=1.5` | Returns true, triggers thought text | `_assert(intrusive_thought_triggered == true)` |
| TC-B2-2 | High conviction no intrusive thought | Call with `conviction=5.0` | Returns false, no thought | `_assert(intrusive_thought_triggered == false)` |
| TC-B2-3 | Boundary conviction=2.0 | Call with `conviction=2.0` | Returns true (≤2) | `_assert(intrusive_thought_triggered == true)` |
| TC-B2-4 | Intrusive thought also triggers echo | Set `conviction=1.5`, ensure `nm` mock available | `nm.trigger_echo("screensaver_echo")` called | `_assert(echo_triggered == true)` |

#### TC-B3: Underpass — Environmental Text Composite State

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B3-1 | Underpass text despair (hope=2, conviction=2) | Call `underpass._get_tone()` with `hope=2.0, conviction=2.0` | Returns `"despair"` | `_assert(tone == "despair")` |
| TC-B3-2 | Underpass text resolute (hope=7, conviction=7) | Call with `hope=7.0, conviction=7.0` | Returns `"resolute"` | `_assert(tone == "resolute")` |
| TC-B3-3 | Underpass text neutral (hope=5, conviction=5) | Call with `hope=5.0, conviction=5.0` | Returns `"neutral"` | `_assert(tone == "neutral")` |
| TC-B3-4 | Underpass text mixed (hope=7, conviction=2) | Call with `hope=7.0, conviction=2.0` | Returns appropriate mixed state | `_assert(tone in ["neutral", "despair"])` |

#### TC-B4: Underpass — Echo System Integration

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B4-1 | screensaver_echo flag triggers echo text | Set `nm.echo_flags.screensaver_echo = true`, call `underpass._check_echoes()` | `EchoText` visible, contains screensaver echo content | `_assert(echo_text.visible == true)` + `_assert(echo_text.text.contains("echo"))` |
| TC-B4-2 | rain_echo flag triggers echo text | Set `nm.echo_flags.rain_echo = true`, call `_check_echoes()` | `EchoText` visible, contains rain echo content | `_assert(echo_text.visible == true)` |
| TC-B4-3 | No echo flags — echo text hidden | Set no flags, call `_check_echoes()` | `EchoText` remains hidden | `_assert(echo_text.visible == false)` |
| TC-B4-4 | Both echo flags — screensaver takes priority | Set both flags, call `_check_echoes()` | Screensaver echo displayed (not rain) | `_assert(echo_text.text.contains("screensaver"))` |

#### TC-B5: AC3 — Hidden Text (Deep Path)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B5-1 | Despair threshold met (hope=2, conviction=2) | Set `hope=2.0, conviction=2.0`, call `underpass._check_hidden_text()` | Hidden text visible, Stranger-as-projection reveal | `_assert(hidden_text.visible == true)` + `_assert(hidden_text.text.contains("projection"))` or equivalent |
| TC-B5-2 | Despair threshold not met (hope=5, conviction=5) | Set `hope=5.0, conviction=5.0`, call `_check_hidden_text()` | Hidden text remains hidden | `_assert(hidden_text.visible == false)` |
| TC-B5-3 | Boundary — hope=2, conviction=3 | Set `hope=2.0, conviction=3.0` | Not triggered (conviction > 2) | `_assert(hidden_text.visible == false)` |
| TC-B5-4 | Boundary — hope=3, conviction=2 | Set `hope=3.0, conviction=2.0` | Not triggered (hope > 2) | `_assert(hidden_text.visible == false)` |
| TC-B5-5 | Boundary — both exactly at threshold | Set `hope=2.0, conviction=2.0` | Triggered (both ≤2) | `_assert(hidden_text.visible == true)` |

#### TC-B6: Underpass Stranger Dialogue — Two Layers (AC2)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B6-1 | Default layer (no echo flag, high conviction) | Player starts dialogue, `screensaver_echo_heard=false`, `conviction=6` | Layer 1 text displayed (standard 3 branches) | `_assert(dialogue_text == layer1_variant)` |
| TC-B6-2 | Layer 2 via screensaver echo | `screensaver_echo_heard=true`, `conviction=5` | Layer 2 text (sharper/sadder) for each branch | `_assert(dialogue_text == layer2_variant_for_echo)` |
| TC-B6-3 | Layer 2 via low conviction | `screensaver_echo_heard=false`, `conviction=2` | Layer 2 text (low conviction variant) | `_assert(dialogue_text == layer2_variant_for_low_conviction)` |
| TC-B6-4 | Layer 2 via both conditions | `screensaver_echo_heard=true`, `conviction=2` | Layer 2 text (deepest variant) | `_assert(dialogue_text == layer2_deepest_variant)` |

#### TC-B7: Scene Transitions — Store → Bridge → Underpass (AC1)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B7-1 | Store exit → Bridge transition | Click store exit trigger, choose "Walk toward bridge", choice has `"scene": "bridge.tscn"` | SceneManager calls `trigger_scene_change("bridge.tscn")` | `_assert(scene_change_called_with == "bridge.tscn")` |
| TC-B7-2 | Bridge exit → Underpass transition | Click bridge exit trigger, `advance_scene()` called | SceneManager transitions to underpass | `_assert(current_scene_index == 4)` (from 3) |
| TC-B7-3 | Underpass exit → Subway transition | Click underpass exit trigger, `advance_scene()` called | SceneManager transitions to subway station | `_assert(current_scene_index == 5)` (from 4) |
| TC-B7-4 | Transition lockout — double-click exit | Click store exit trigger twice rapidly | Second call blocked by `transition_in_progress` | `_assert(transition_count == 1)` |

#### TC-B8: Bridge — Scene Fallbacks (Failure Paths)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B8-1 | bridge_homeless.json missing | `dialogue_runner.start("bridge_homeless.json")` returns false | Fallback text: "The homeless person doesn't respond." | `_assert(fallback_text_displayed == true)` |
| TC-B8-2 | StateSystem unavailable | `/root/StateSystem` returns null | Default neutral text variants used | `_assert(environment_text == neutral_variant)` |
| TC-B8-3 | Scene load failure | `change_scene_to_file("bad_path.tscn")` returns ERR | Error logged, current scene stays, `transition_in_progress` reset | `_assert(sm.transition_in_progress == false)` |

#### TC-B9: Underpass — Fallbacks (Failure Paths)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-B9-1 | underpass_stranger_echo.json missing | `dialogue_runner.start("underpass_stranger_echo.json")` returns false | Fallback text: "The tunnel is empty." | `_assert(fallback_text_displayed == true)` |
| TC-B9-2 | Echo flags undefined | `nm.echo_flags` is null or undefined in `_check_echoes()` | No crash, echo text stays hidden | `_assert(echo_text.visible == false)` |
| TC-B9-3 | Dialogue file corrupted | JSON parse error in underpass_stranger_echo.json | Parser returns error, runner logs error, fallback text | `_assert(error_logged == true)` + `_assert(fallback_displayed == true)` |

---

## 8. Files Changed (per-layer summary)

### Scene Tree Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/bridge/bridge.tscn` | **Modify** — add Camera3D, WorldEnvironment, lighting, CSG geometry, SceneManager, FadeCurtain | +150 |
| `scenes/underpass/underpass.tscn` | **Modify** — add Camera3D, WorldEnvironment, lighting, CSG tunnel geometry, SceneManager, FadeCurtain | +150 |
| `scenes/store/convenience_store.tscn` | **Modify** — add `StoreExitTrigger` Area3D | +10 |

### GDScript / Logic Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/store.gd` | **Modify** — add exit trigger handler + dialogue start | +15 |
| `gdscripts/bridge.gd` | **Verify only** — ensure fade_in + echo trigger_calls | 0 (verify only) |
| `gdscripts/underpass.gd` | **Verify only** — ensure fade_in + AC3 hidden text check | 0 (verify only) |
| `gdscripts/constants.gd` | **Modify** — add bridge/underpass scene path constants + despair thresholds | +6 |

### Resource / Config Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `dialogues/store_exit.json` | **New** — store exit → bridge transition dialogue | +40 |
| `dialogues/underpass_stranger_echo.json` | **Modify** — add condition-based 2nd-layer variants | +80 |
| `dialogues/bridge_homeless.json` | **No changes needed** | 0 |

### Asset / Visual Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `assets/materials/bridge_asphalt.tres` | **New** | +10 |
| `assets/materials/canal_water.tres` | **New** | +10 |
| `assets/materials/tunnel_wall.tres` | **New** | +10 |
| `assets/materials/tunnel_floor.tres` | **New** | +10 |
| `assets/materials/building_silhouette.tres` | **New** | +10 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_bridge_underpass.gd` | **New** — bridge/underpass scene logic tests (TC-B1 through TC-B9) | +350 |
| `tests/run_tests.gd` | **Modify** — add `run_bridge_underpass_tests()` call | +4 |

---

## 9. Verification Checklist

- [ ] TC-B1-1 through TC-B1-6: Bridge environmental text correctly reflects will state (tired/neutral/determined)
- [ ] TC-B2-1 through TC-B2-4: Intrusive thought triggers at conviction ≤ 2; also triggers screensaver_echo
- [ ] TC-B3-1 through TC-B3-4: Underpass environmental text correctly reflects composite hope+conviction state
- [ ] TC-B4-1 through TC-B4-4: Echo system integration — screensaver_echo and rain_echo display correct text
- [ ] TC-B5-1 through TC-B5-5: AC3 hidden text (Stranger-as-projection) visible only at combined threshold (hope ≤ 2 AND conviction ≤ 2)
- [ ] TC-B6-1 through TC-B6-4: AC2 Stranger dialogue has two visible layers (conditional on echo flag + conviction)
- [ ] TC-B7-1 through TC-B7-4: AC1 — 3 scene transitions (store→bridge→underpass) work correctly with lockout
- [ ] TC-B8-1 through TC-B8-3: Bridge failure paths handled (missing dialogue, unavailable state, scene load error)
- [ ] TC-B9-1 through TC-B9-3: Underpass failure paths handled (missing dialogue, undefined echoes, corrupted JSON)
- [ ] `godot --headless --script tests/run_tests.gd` — all tests pass, 0 failures
- [ ] No regression: existing #55 scene sequence tests still pass
- [ ] No regression: existing dialogue engine tests still pass
- [ ] Bridge bridge.tscn loads independently in Godot editor
- [ ] Underpass underpass.tscn loads independently in Godot editor
- [ ] Store exit trigger connects to bridge scene transition
- [ ] Bridge exit trigger connects to underpass scene transition
- [ ] Underpass exit trigger connects to subway station scene transition
- [ ] EchoText hidden by default, conditionally visible for AC3
- [ ] All new LoFiText3D instances have proper pixel_factor/color_bits/scanline setup per scene aesthetic
