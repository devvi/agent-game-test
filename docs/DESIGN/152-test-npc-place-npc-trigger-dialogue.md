# Design: #152 — Test NPC: Place NPC + Trigger Dialogue

> Parent Issue: #152
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Place a test NPC instance in the Street scene that validates the end-to-end interaction cycle: player approaches → VisualName + InteractionPrompt appear → player presses E → dialogue starts → dialogue advances/ends → NPC cooldown. This is the first integration of the NPC framework (NPCNode) with the E-key interaction pathway (EKeyTrigger), and serves as both a validation stub and a reference template for all future NPCs.

### Design Principle

**Minimal invasion, maximum coverage.** The existing NPC framework (`NPC.tscn` + `npc_node.gd`) works via mouse-click (`input_event`). The E-key system (`EKeyTrigger` + `PlayerController.interaction_requested`) was developed independently. This feature glues them together with a single new public method on NPCNode (`start_npc_interaction()`) and a few lines of wiring in `street.gd`. No existing NPC behavior is changed; the new codepath is additive.

### Data Flow

```
StreetScene._ready()
    │
    ├── SceneBase._ready()
    │   ├── _instantiate_player() → PlayerController + group "player"
    │   └── Connects PlayerController.interaction_requested → _on_player_interaction

    ├── NPCNode (TestNPC) _ready()
    │   ├── InteractionTrigger.body_entered → _on_body_entered (sets _player_nearby)
    │   └── InteractionTrigger.body_entered → EKeyTrigger._on_body_entered
    │       └── Connects player.interaction_requested → EKeyTrigger._on_player_interact

    ├── Player walks into NPC proximity (< proximity_distance = 3.0m):
    │   ├── NPCNode._on_body_entered: _player_nearby = true → show VisualName + Prompt
    │   └── EKeyTrigger._on_body_entered: connects interaction_requested if PlayerController

    ├── Player presses E (within interaction_range = 2.0m):
    │   ├── PlayerController._try_interact()
    │   │   └── Pops from _nearby_interactables LIFO stack
    │   ├── interaction_requested.emit(EKeyTrigger)
    │   │   └── SceneBase._on_player_interaction(target)
    │   │       └── target.has_method("start_npc_interaction")? → target.start_npc_interaction()
    │   │           └── NPCNode.start_npc_interaction() [NEW METHOD]
    │   │               ├── evaluate_personality_layer()
    │   │               ├── set_state(NPCState.TALKING)
    │   │               ├── update_name_label()
    │   │               └── dialogue_runner.start("res://dialogues/npc_test.json", "npc_test")
    │   └── EKeyTrigger also receives interaction_requested → e_key_interacted.emit()
    │       └── (Treated as alternative activation path - both converge on start_npc_interaction)

    ├── DialogueRunner loads npc_test.json:
    │   ├── dialogue_started signal → DialogueDisplay3D.show_dialogue()
    │   └── node_changed signal → DialogueDisplay3D.on_node_changed()

    ├── Player presses E during dialogue:
    │   ├── _dialogue_active == true → _route_to_dialogue_select()
    │   └── DialoguePanel.select_current() → advance to next node or end

    └── Dialogue ends (option with next_node: null selected):
        ├── dialogue_ended signal → NPCNode._on_dialogue_ended()
        ├── set_state(NPCState.COOLDOWN)
        ├── _cooldown_timer.start(2.0s)
        └── On cooldown_timeout: set_state(NPCState.IDLE) [or EXHAUSTED if no branches remain]
```

### Scene Tree Addition (street.tscn)

```
StreetRoot (SceneBase)
├── Environments (existing)
├── InteractionZones
│   ├── StoreEntranceTrigger (existing)
│   ├── StoreLabel (existing)
│   └── TestNPC (NPC.tscn instance)  ← NEW
│       ├── NPC (Node3D) [NPCNode script]
│       │   ├── InteractionTrigger (Area3D)
│       │   │   ├── CollisionShape3D
│       │   │   └── EKeyTrigger (EKeyTrigger)  ← NEW child node
│       │   ├── VisualName (Label3D)
│       │   ├── InteractionPrompt (Label3D)
│       │   └── CooldownTimer (Timer)
├── SceneManager (existing)
└── CanvasLayer (existing)
    ├── DialoguePanel (DialogueRunner)
    ├── Dialogue3D (DialogueDisplay3D)
    └── FadeCurtain
```

---

## 2. File Changes

### Modified Files

| File | Change | Rationale |
|------|--------|-----------|
| `gdscripts/npc_node.gd` | Add `start_npc_interaction()` public method | Gives SceneBase/EKeyTrigger a programmatic activation path alongside existing `input_event` mouse-click path |
| `scenes/street/street.tscn` | Add NPC.tscn instance at `InteractionZones/TestNPC` with EKeyTrigger child | Places the physical NPC in the street scene |
| `gdscripts/street.gd` | Add `_on_test_npc_interact()` handler + connect EKeyTrigger | Wires the E-key → NPC activation path |
| `gdscripts/constants.gd` | Add `DIALOGUE_NPC_TEST` constant | Standard dialogue path constant for the test NPC |

### New Files

| File | Change | Rationale |
|------|--------|-----------|
| `dialogues/npc_test.json` | Create 2-node test dialogue | Minimal Hemingway-conforming dialogue for end-to-end validation |

---

## 3. Detailed Design

### 3.1 NPCNode: `start_npc_interaction()` Method

**Location:** Add after `_on_interaction()` (~line 108), before `evaluate_personality_layer()`.

```gdscript
## Public entry point for E-key / SceneBase-triggered interaction.
## Mirrors the core logic of _on_interaction() without requiring an InputEvent.
func start_npc_interaction() -> void:
    if not is_interactable():
        return
    evaluate_personality_layer()
    set_state(NPCState.TALKING)
    update_name_label()
    if _dialogue_runner:
        _dialogue_runner.start(dialogue_file, dialogue_id, _greeting_override)
    npc_interacted.emit(name)
```

This method is deliberately a near-identical copy of the `input_event` handler's activation block — the same state transitions, evaluations, and dialogue call. The `is_interactable()` guard ensures cooldown/EXHAUSTED states block both paths uniformly.

**Verification:** `SceneBase._on_player_interaction(target)` already has `target.has_method("start_npc_interaction")` check (line 119 of `scene_base.gd`), so the method just needs to exist on NPCNode for the routing to work.

### 3.2 NPC Node Instantiation (street.tscn)

The NPC.tscn instance is placed under `InteractionZones/TestNPC`:

| Property | Value |
|----------|-------|
| `InteractionZones/TestNPC` position | `Vector3(4, 0, 0)` |
| `NPC.dialogue_file` | `"res://dialogues/npc_test.json"` |
| `NPC.dialogue_id` | `"npc_test"` |
| `NPC.speaker_name` | `"???"` |
| `NPC.proximity_distance` | `3.0` |
| `NPC.cooldown_seconds` | `2.0` |

The EKeyTrigger node is added as a child of `InteractionZones/TestNPC/InteractionTrigger` (not as a child of the NPC node itself — it needs to be inside the Area3D to receive body_entered/exited events).

### 3.3 street.gd Wiring

```gdscript
# Add to the script-level @onready declarations:
@onready var test_npc_interact: Node = $InteractionZones/TestNPC/InteractionTrigger/EKeyTrigger

# Add to _ready():
func _ready() -> void:
    scene_id = "street"
    super._ready()
    store_entrance.input_event.connect(_on_store_entrance_input)
    if test_npc_interact and test_npc_interact.has_signal("e_key_interacted"):
        test_npc_interact.e_key_interacted.connect(_on_test_npc_interact)

# New handler:
func _on_test_npc_interact() -> void:
    var npc_node: Node = $InteractionZones/TestNPC/NPC
    if npc_node and npc_node.has_method("start_npc_interaction"):
        npc_node.start_npc_interaction()
```

The `e_key_interacted` → `street.gd` → `NPCNode.start_npc_interaction()` path is the main E-key route. The alternative path via `SceneBase._on_player_interaction()` (where EKeyTrigger itself is the target of `interaction_requested`) also works but requires EKeyTrigger to be in group "interactable" (which it already is in `_ready()`). Both paths converge on `start_npc_interaction()` — the street.gd handler is more explicit and easier to debug.

### 3.4 Test Dialogue JSON

```json
{
  "entry_node_id": "test_greet",
  "nodes": {
    "test_greet": {
      "speaker": "???",
      "text": "Hey.\\nYou're still here.",
      "choices": [
        {
          "text": "Who are you?",
          "next_node": "test_answer",
          "condition": null,
          "effects": []
        },
        {
          "text": "...",
          "next_node": null,
          "effects": []
        }
      ]
    },
    "test_answer": {
      "speaker": "???",
      "text": "Just a test.\\nNothing more.",
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

Conforms to Hemingway constraints: ≤25 chars per sentence, ≤1 sentence per speaker turn.

### 3.5 Constants Addition

In `constants.gd`, add alongside existing dialogue path constants:

```gdscript
const DIALOGUE_NPC_TEST: String = "res://dialogues/npc_test.json"
```

---

## 4. Edge Cases & Hazards

| Hazard | Mitigation |
|--------|-----------|
| **E-key + mouse-click race condition** — player clicks NPC and presses E simultaneously | Both paths check `is_interactable()` which blocks when state != IDLE. The first activation sets TALKING; the second call is a no-op. |
| **E-key pressed outside interaction_range but inside proximity_distance** | PlayerController._try_interact() uses LIFO stack built by InteractionArea body_entered (range = 2.0m). Proximity_distance (3.0m) only controls label visibility. The two ranges are independent — E-key only triggers when PlayerController's own Area3D overlaps the interactable. |
| **EKeyTrigger disconnected on body_exited** | If player walks out of NPC range while EKeyTrigger.is_connected(), EKeyTrigger._on_body_exited() disconnects interaction_requested signal. If dialogue is already active, it continues unaffected. |
| **Dialogue file missing** | DialogueParser returns {ok: false}; push_error is emitted but game continues. No crash. |
| **EKeyTrigger node path changes** | street.gd uses a hardcoded path `$InteractionZones/TestNPC/InteractionTrigger/EKeyTrigger`. If the scene tree structure changes, the path breaks. Mitigated by error checking: `has_signal("e_key_interacted")` guard. |
| **Test NPC remains in production builds** | Acceptable — the NPC is unobtrusive and serves as a reference template. Remove later if desired by removing the single scene instance. |

---

## 5. Test Case Descriptions

> These test cases describe the unit and integration verification strategy. No separate TASKS doc; test specs are embedded here. The implementer writes the tests alongside the code.

### Unit Tests

#### T1: NPCNode.start_npc_interaction() exists and invokes dialogue

| Field | Value |
|-------|-------|
| **File** | `tests/unit/test_npc_node.gd` (modify existing) |
| **Test** | `_test_start_npc_interaction_public_method()` |
| **Setup** | Create NPCNode with mock _dialogue_runner, set state = IDLE |
| **Action** | Call `npc.start_npc_interaction()` |
| **Assert** | State transitions to TALKING (1). `_dialogue_runner.start()` called with correct args (dialogue_file, dialogue_id, _greeting_override). `npc_interacted` signal emitted. |
| **Edge** | Call again while state = TALKING → `is_interactable()` returns false → no-op. |

#### T2: start_npc_interaction() respects cooldown/exhausted states

| Field | Value |
|-------|-------|
| **File** | `tests/unit/test_npc_node.gd` (modify existing) |
| **Test** | `_test_start_npc_interaction_respects_state()` |
| **Setup** | Set state = COOLDOWN (2), then EXHAUSTED (3) |
| **Action** | Call `start_npc_interaction()` each time |
| **Assert** | No state change, no signal emission, no dialogue start. `is_interactable()` guard blocks. |

#### T3: NPCNode.start_npc_interaction() is idempotent with mouse-click path

| Field | Value |
|-------|-------|
| **File** | `tests/unit/test_npc_node.gd` (modify existing) |
| **Test** | `_test_start_npc_interaction_vs_input_event()` |
| **Setup** | Create NPCNode with mock dialogue_runner, state = IDLE |
| **Action** | Call `start_npc_interaction()` → state becomes TALKING. Immediately simulate a mouse-click `input_event` on the trigger area. |
| **Assert** | Second activation is blocked by `is_interactable()` (state != IDLE). Dialogue started exactly once. |

#### T4: EKeyTrigger.e_key_interacted emitted on player interact

| Field | Value |
|-------|-------|
| **File** | `tests/unit/test_e_key_trigger.gd` (modify existing) |
| **Test** | `_test_e_key_interacted_signal_emitted()` |
| **Setup** | Create EKeyTrigger. Create mock player node (group "player", with interaction_requested signal). Add both to scene tree. Trigger body_entered(player). |
| **Action** | Emit player.interaction_requested.emit(player) |
| **Assert** | `e_key_interacted` signal fires. |

#### T5: EKeyTrigger disconnects on body_exited

| Field | Value |
|-------|-------|
| **File** | `tests/unit/test_e_key_trigger.gd` (modify existing) |
| **Test** | `_test_e_key_trigger_disconnects_on_exit()` |
| **Setup** | Same as T4. body_entered → connected. |
| **Action** | Emit body_exited(player). Then emit player.interaction_requested.emit(player) |
| **Assert** | `e_key_interacted` does NOT fire. Signal was correctly disconnected. |

### Integration Tests

#### T6: E2E — player walks to NPC and presses E

| Field | Value |
|-------|-------|
| **File** | `tests/integration/test_npc_in_scene.gd` (modify existing) |
| **Test** | `_test_npc_e_key_full_cycle()` |
| **Setup** | Load street scene with TestNPC instance and mocked dialogue runner. Spawn PlayerController within proximity_distance of NPC (position = 3.0, 0, 0). |
| **Action** | Press interact action (simulate `Input.action_press("interact")`). |
| **Assert** | NPCNode state = TALKING. `dialogue_runner.start()` called with `res://dialogues/npc_test.json`. VisualName visible. InteractionPrompt hidden (during dialogue). |
| **Assert (advance)** | Press interact again → `dialogue_active` routes to `dialogue_select`. Dialogue advances to next node. |
| **Assert (end)** | Advance to final node → `dialogue_ended` signal → NPCNode state = COOLDOWN → after 2s → IDLE (or EXHAUSTED). |

#### T7: E2E — NPC name label visibility

| Field | Value |
|-------|-------|
| **File** | `tests/integration/test_npc_in_scene.gd` (modify existing) |
| **Test** | `_test_npc_label_visibility_proximity()` |
| **Setup** | Load street scene. Place PlayerController at distance 4.0m from NPC (outside proximity_distance of 3.0m). |
| **Action** | Move player to distance 2.0m (inside proximity). |
| **Assert** | VisualName visible, InteractionPrompt visible. |
| **Action** | Move player to distance 4.0m (outside proximity). |
| **Assert** | Both labels hidden. |

#### T8: E2E — rapid E-key during cooldown

| Field | Value |
|-------|-------|
| **File** | `tests/integration/test_npc_in_scene.gd` (modify existing) |
| **Test** | `_test_npc_e_key_during_cooldown()` |
| **Setup** | Complete a full dialogue with NPC (state = COOLDOWN). |
| **Action** | Press interact repeatedly during the 2s cooldown window. |
| **Assert** | No new dialogue started. NPCNode state remains COOLDOWN. `is_interactable()` returns false. |
| **Action** | Wait for cooldown timeout. |
| **Assert** | NPCNode state returns to IDLE (or EXHAUSTED if no branches remain). E-key works again. |

#### T9: Dialogue file missing — graceful degradation

| Field | Value |
|-------|-------|
| **File** | `tests/integration/test_npc_in_scene.gd` (modify existing) |
| **Test** | `_test_npc_missing_dialogue_file()` |
| **Setup** | Load street scene. Set NPC's dialogue_file to a nonexistent path. |
| **Action** | Walk to NPC and press E. |
| **Assert** | `start_npc_interaction()` is called. `push_error` or equivalent is emitted. Game does not crash. NPCNode state returns to IDLE (dialogue start fails gracefully). |

---

## 6. Risks & Open Questions

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `EKeyTrigger` and `NPCNode` both connect to `player.interaction_requested` → double activation | Low | High (double dialogue) | SceneBase._on_player_interaction catches EKeyTrigger as target first. NPCNode does NOT connect to interaction_requested — it only listens via input_event. The EKeyTrigger's e_key_interacted → street.gd handler → npc_node.start_npc_interaction() path ensures single activation. Verified in research spike. |
| `EKeyTrigger` body_entered/exited needs to be inside `InteractionTrigger` Area3D, not outside | Medium | High (E-key range mismatch) | Design calls for EKeyTrigger as child of InteractionTrigger, sharing the same CollisionShape3D. Verified in research: both nodes receive the same body_entered events. |
| NPCNode path in street.gd hardcoded | Low | Low (refactoring friction) | Acceptable for test NPC. Future NPCs would use a more generic registration pattern. |

---

## 7. Implementation Order

1. **Add `start_npc_interaction()` to NPCNode** — the minimal public method
2. **Write/update unit tests** — T1, T2, T3 (NPCNode), T4, T5 (EKeyTrigger)
3. **Create `dialogues/npc_test.json`** — 2-node test dialogue
4. **Add `DIALOGUE_NPC_TEST` constant** to constants.gd
5. **Modify `street.tscn`** — add NPC.tscn instance + EKeyTrigger child
6. **Modify `street.gd`** — add @onready, _ready connection, handler
7. **Write/update integration tests** — T6, T7, T8, T9
8. **Manual verification**: load street scene, walk to NPC, press E, observe dialogue

No scene manager changes needed — the street scene already has a working dialogue runner via its CanvasLayer/DialoguePanel.

---

## 8. Verification Checklist

- [ ] `NPCNode.start_npc_interaction()` exists and is callable from SceneBase._on_player_interaction
- [ ] `is_interactable()` guard works for both E-key and mouse-click paths
- [ ] Unit tests T1–T5 pass
- [ ] `dialogues/npc_test.json` loads without parse errors
- [ ] `street.tscn` TestNPC instance at Vector3(4, 0, 0) with all exports set
- [ ] EKeyTrigger child exists under InteractionTrigger
- [ ] Integration tests T6–T9 pass
- [ ] Manual: E-key activates dialogue, dialogue advances, NPC cooldown works
