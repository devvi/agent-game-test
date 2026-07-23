# Research: Minimal Ending — Complete One Playable Path (#155)

> Parent Issue: #155
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

All six narrative scenes exist in the game files with dialogue, environmental text, and interaction triggers. The NarrativeManager (Issue #45) defines the scene sequence and ending determination. The dialogue engine (Issue #52) handles JSON-based branching with conditions and effects. The SceneManager performs fade-to-black transitions.

**However, the player cannot complete one full playable path from start to an ending without getting stuck.** The following gaps prevent end-to-end playthrough:

1. **Incomplete scene transitions — most exit triggers do not load the next scene.**
   - `office_door.json` sets `left_office` / `left_with_purpose` flags but has **no `"scene"` key** in any choice — the player stays in the office after the dialogue.
   - `lobby.gd` exit trigger calls `nm.advance_scene()` (increments the NarrativeManager counter) but **does not call `scene_manager.trigger_scene_change()`** — so no actual scene load occurs.
   - `bridge.gd` exit trigger calls `nm.advance_scene()` without loading the next scene.
   - `underpass.gd` exit trigger calls `nm.advance_scene()` without loading the next scene.
   - Only `store_exit.json` properly uses the `"scene"` key: `"scene": "res://scenes/bridge/bridge.tscn"`.

2. **No exit dialogue JSON files for lobby, bridge, or underpass.**
   - These scenes have exit triggers but no corresponding exit dialogue that could carry a `"scene"` transition key.
   - The exit triggers hook into `Area3D.input_event` but only perform `nm.advance_scene()` without scene loading.

3. **Endings set flags but have no terminal behavior.**
   - `subway_ending.json` sets flags `ending_keep_walking`, `ending_turn_back`, or `ending_stay` via `set_flag` effects.
   - After the final dialogue node, the `next_node: null` choice ends the conversation — but **nothing happens**. No credits screen, no return to main menu, no game over screen, no state reset. The player is left standing in the subway station.

4. **No exit dialogue for lobby → convenience_store transition.**
   - The lobby scene has an exit trigger but the store is the next scene. The street scene (`scenes/street/street.tscn`) exists but is not part of the narrative sequence.

5. **No main menu or post-game state.**
   - `main.tscn` loads `office.tscn` immediately on start (`_load_starting_scene`). There is no title screen, no new game / continue / credits flow.

### Expected Behavior

A player should be able to:

1. Start the game → land in the office
2. Click the office door → choose to leave → fade transition to lobby
3. Explore lobby (talk to guard, meet Stranger) → exit → fade transition to convenience store
4. Talk to clerk → exit store → fade transition to bridge
5. Explore bridge (railing, homeless NPC) → exit → fade transition to underpass
6. Explore underpass (graffiti, Stranger echo) → exit → fade transition to subway station
7. Engage with the ending → ending is determined → final credits / post-game screen → return to main menu

### User Scenarios

- **Scenario A (First playthrough):** Player loads the game, walks through all 6 scenes in order, reaches subway station, sees an ending, and is returned to a menu or title screen.
- **Scenario B (State-dependent ending):** Player's in-game choices (hope/conviction/will) determine which of the 3 endings triggers — keep_walking, turn_back, or stay.
- **Scenario C (Replay):** After seeing an ending, player can start a new game to experience a different path.
- **Frequency:** Every play session — this is the fundamental game loop.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

Scene transitions were designed piecemeal across multiple issues:
- Issue #50 (lobby + store) and issue #55 (office door + street + store) focused on individual scene content.
- The SceneManager's dialogue-based transition (checking `choice["scene"]`) was built in `scene_manager.gd` but only used in `store_exit.json`.
- Exit triggers in bridge, underpass, and lobby were written with placeholder `advance_scene()` calls as scaffolding for later completion.
- Ending terminal behavior (credits, menu return) was deferred — Issue #56 covered content but not the game loop closure.

### Why Change Now?

Without completing the scene transition chain and ending terminal behavior, the game has no complete playable path. This blocks all further testing and QA. Issue #155 is the capping issue that closes the loop from "game scenes exist" to "game can be played from start to finish."

### Constraints

- **Preserve existing architecture:** Use the SceneManager's `trigger_scene_change()` and `fade_in()` mechanisms.
- **Preserve NarrativeManager's scene sequence** (`SCENE_ORDER`): `["office", "lobby", "convenience_store", "bridge", "underpass", "subway_station"]`.
- **Exit dialogue JSON must include `"scene"` key** for SceneManager to trigger transitions.
- **Ending detection already works** — `NarrativeManager.determine_ending()` returns `"keep_walking"`, `"turn_back"`, or `"stay"`.
- **No new autoloads** — use existing GameManager, NarrativeManager, StateSystem.

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `dialogues/office_door.json` | Dialogue data | **Choices must get `"scene"` keys** to trigger lobby transition |
| `dialogues/lobby_exit.json` (NEW) | Dialogue data | **New exit dialogue** with scene transition to convenience_store |
| `dialogues/bridge_exit.json` (NEW) | Dialogue data | **New exit dialogue** with scene transition to underpass |
| `dialogues/underpass_exit.json` (NEW) | Dialogue data | **New exit dialogue** with scene transition to subway_station |
| `dialogues/subway_ending.json` | Dialogue data | Add `"scene"` to terminal choice → credits/menu scene |
| `gdscripts/subway_station.gd` | Scene script | Wire ending completion → trigger credits/menu load |
| `gdscripts/scene_manager.gd` | Transition system | (Possibly) add callback after ending for menu return |
| `scenes/end_credits.tscn` (NEW) | Scene | New credits/post-game scene |
| `gdscripts/end_credits.gd` (NEW) | Scene script | Credits display, auto-return to main menu |
| `gdscripts/main.gd` | Entry script | Add main menu flow before starting game |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/lobby.gd` | Scene script | Lobby exit trigger should start exit dialogue instead of bare `advance_scene()` |
| `gdscripts/bridge.gd` | Scene script | Bridge exit trigger should start exit dialogue |
| `gdscripts/underpass.gd` | Scene script | Underpass exit trigger should start exit dialogue |
| `gdscripts/game_manager.gd` | Game state | May need `reset()` cleanup for new game flow |
| `gdscripts/state_system.gd` | State | May need `reset()` for new game |
| `tests/test_game_manager_playthrough.gd` | Tests | Update to validate full loop |
| `tests/test_stranger_scene.gd` | Tests | Update if lobby exit changes |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | Design doc | May need updates |

### Data Flow Impact

The scene transition data flow becomes:

```
InteractionTrigger (click)
  → SceneScript.start_dialogue(exit_dialogue.json)
    → DialogueRunner starts JSON
      → Player selects choice with "scene" key
        → SceneManager._on_choice_made()
          → trigger_scene_change(target_scene)
            → fade_out → change_scene → _ready() → fade_in
```

This flow already works (proven by `store_exit.json` → `bridge.tscn`). The fix is adding the same pattern to the other 4 exit points and the ending terminal.

### Documents to Update

- [x] `docs/PRD/155-minimal-ending.md` (this document)
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` — Update scene transition table
- [ ] `README.md` — Add playable path status

---

## 4. Solution Comparison

### Approach A: Dialogue-based scene transitions (recommended)

**Description:** Create exit dialogue JSON files for lobby, bridge, and underpass (or repurpose existing exit triggers to start dialogues). Add `"scene"` keys to office_door.json choices and to subway_ending.json terminal choices. Create a minimal credits/main-menu scene for after endings.

**Steps:**

| # | Task | File(s) |
|---|------|---------|
| 1 | Add `"scene": "res://scenes/lobby/lobby.tscn"` to office_door.json choices (door_leave node) | `dialogues/office_door.json` |
| 2 | Create lobby_exit.json with choices leading to convenience_store via `"scene"` key | `dialogues/lobby_exit.json` |
| 3 | Wire lobby's exit trigger to start lobby_exit.json dialogue | `gdscripts/lobby.gd` |
| 4 | Create bridge_exit.json with choices leading to underpass via `"scene"` key | `dialogues/bridge_exit.json` |
| 5 | Wire bridge's exit trigger to start bridge_exit.json dialogue | `gdscripts/bridge.gd` |
| 6 | Create underpass_exit.json with choices leading to subway_station via `"scene"` key | `dialogues/underpass_exit.json` |
| 7 | Wire underpass's exit trigger to start underpass_exit.json dialogue | `gdscripts/underpass.gd` |
| 8 | Add post-ending scene transition in subway_ending.json terminal choices | `dialogues/subway_ending.json` |
| 9 | Create end_credits.tscn / end_credits.gd scene with credits + menu return | `scenes/end_credits.tscn` + `gdscripts/end_credits.gd` |
| 10 | Add main menu scene (title + new game) or keep immediate start | `scenes/main_menu.tscn` (optional) |

**Pros:**
- Reuses proven pattern from `store_exit.json` — lowest risk
- Each exit can carry state-aware narrative text (different text based on hope/conviction)
- No new transition mechanism needed
- Each exit dialogue can offer meaningful choices (not just "go forward")

**Cons:**
- 3 new JSON files to create
- Some exit dialogues may be very short (one choice, one transition)
- Lobby → store bypasses the street scene entirely (street.tscn exists but isn't on the narrative path)

**Risk:** Low — every element of this approach is already implemented and working elsewhere.

**Effort:** 2–4 hours (JSON creation, scene script wiring, credits scene)

### Approach B: Direct scene_manager.trigger_scene_change() in exit triggers

**Description:** Skip exit dialogues entirely. In each scene's exit trigger handler, directly call `scene_manager.trigger_scene_change(NarrativeManager.get_next_scene())`.

**Pros:**
- Fewer files to create (no exit JSON files)
- Faster path to a working loop

**Cons:**
- No state-aware exit text — player just gets a fade with no narrative framing
- Inconsistent with store_exit.json's dialogue-based approach
- Bypasses the established dialogue transition pattern
- Exit text provides important narrative closure between scenes

**Risk:** Medium — technically simpler but inconsistent with architecture.

**Effort:** 1 hour

### Recommendation

→ **Approach A** because:
1. It uses the proven dialogue-based transition pattern
2. Exit dialogues carry narrative value (state-aware text based on player's journey)
3. It's consistent with the existing `store_exit.json` approach
4. Risk is near-zero since every component is already battle-tested
5. The subway ending needs its own handling anyway (credits scene)

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path (Full Playthrough)

**Start → Office → Lobby → Store → Bridge → Underpass → Subway → Ending**

| Step | Scene | Interaction | Expected Result |
|------|-------|-------------|-----------------|
| 1 | Office | Click door → dialogue → choose "Walk out" | Fade → lobby.tscn loads |
| 2 | Lobby | Explore (guard, Stranger optional). Click exit → dialogue → choose "Leave" | Fade → convenience_store.tscn loads |
| 3 | Store | Talk to clerk (optional). Click exit → dialogue → choose "Walk toward bridge" | Fade → bridge.tscn loads (ALREADY WORKS via store_exit.json) |
| 4 | Bridge | Explore (railing, homeless). Click exit → dialogue → choose "Forward" | Fade → underpass.tscn loads |
| 5 | Underpass | Explore (graffiti, Stranger echo). Click exit → dialogue → choose "Toward the station" | Fade → subway_station.tscn loads |
| 6 | Subway | Ending determined. Interact with gate/bench/turn-back → ending dialogue → final choice | Fade → end_credits.tscn loads |

### Ending Handling

- **keep_walking:** Player boards train → brief conclusion text → "scene": credits
- **turn_back:** Player returns to night street → brief conclusion text → "scene": credits
- **stay:** Player sits on bench → brief conclusion text → "scene": credits

The credits scene should:
- Display ending title (Keep Walking / Turn Back / Stay) + brief epilogue text
- Display "The End" or equivalent
- After 5–10 seconds or on click, return to main menu (or resets to office if no menu exists yet)

### Acceptance Criteria

**AC1 (Critical — scene chain complete):**
- [ ] Player can walk: office → lobby → store → bridge → underpass → subway_station
- [ ] Each scene transition uses a fade-to-black + fade-in
- [ ] Player position is preserved across transitions (via GameManager.player_position)

**AC2 (Critical — ending terminal behavior):**
- [ ] After any ending dialogue completes, a credits/epilogue screen appears
- [ ] After credits, player returns to start (main menu or office reload)

**AC3 (State preservation across path):**
- [ ] hope/conviction/will state persists across all scene transitions
- [ ] Dialogue history (choices_made) persists across all scene transitions
- [ ] Flags set in one scene are readable in later scenes

**AC4 (Edge cases):**
- [ ] If no NPCs are interacted with, the game still completes (minimal path)
- [ ] Rapid clicking during transitions does not break the state machine
- [ ] Ending determination works correctly based on accumulated state

### Edge Cases

1. **Minimal playthrough (no NPC conversations):** Player walks from office to subway without talking to guard, clerk, homeless, or Stranger. All three endings should still be reachable, though state will be mostly neutral (hope=5.0, conviction=5.0, will=5.0), defaulting to "stay" ending.

2. **New Game Plus (playthrough_count ≥ 2):** The underpass Stranger echo trigger checks `get_playthrough_count() >= 2` to set `is_new_game_plus` flag. This should still work with the completed path.

3. **State extremes:** If all three axes are maxed (10.0), the ending should correctly determine "keep_walking". If all are at 1.0, "turn_back" may trigger (if conviction ≤ 3.0).

4. **Rapid scene transitions:** SceneManager has `transition_in_progress` guard — clicking exit trigger during a fade-out should be no-op.

### Failure Paths

1. **Missing scene key in exit dialogue:** Player clicks exit → dialogue plays → choice selected → no scene change → stuck. **All exit choices must have `"scene"` key or a valid `next_node` that eventually leads to one.**

2. **Incorrect file path in scene key:** SceneManager calls `change_scene_to_file()` with wrong path → error logged → `transition_in_progress` stays true → game soft-locked. **All scene paths must match existing .tscn files.**

3. **Ending credits scene path mismatch:** If `end_credits.tscn` doesn't exist or path is wrong, the final choice leaves player in subway with no further action. **Create credits scene before wiring subway ending.**

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #45 — Narrative Architecture (SCENE_ORDER, ending determination) | ✅ Merged (PR #96) | None |
| #50 — Lobby + Store scenes | ✅ Merged | None |
| #51 — Bridge + Underpass + Subway Station scenes | ✅ Merged | None |
| #55 — Office door + Street + Store complete | ✅ Merged | None |
| #56 — Story content / script / endings | ✅ Merged (PR #170) | None |
| #58 — Store/Bridge/Underpass scenes | ✅ Merged | None |
| Dialogue Engine (Issue #46, #52) | ✅ Merged | None |
| SceneManager fade transitions | ✅ Implemented | None |
| PlayerController (Issue #142) | ✅ Merged | None |
| StateSystem tri-axis | ✅ Implemented | None |

### Blocks

| Future Work | Priority |
|-------------|----------|
| #? — QA / playtest pass | Critical |
| #? — Release / demo build | High |
| All further content work needs a playable path | High |

### Preparation Needed

- [ ] Confirm NarrativeManager.SCENE_ORDER is still the canonical path (no street scene needed)
- [ ] Verify all existing scene paths in constants.gd match actual files
- [ ] Check if `main.tscn` should get a main menu or stay immediate-start
- [ ] Decide on credit scene content (minimal or styled)

---

## 7. Spike / Experiment (Depth Requirement — at least 3 items)

### Spike A: Scene Transition Gap Audit — Map every exit trigger to its actual behavior

**Question:** What does each scene's exit trigger actually do right now?

**Method:** Trace every exit trigger handler across all 6 scene scripts.

**Results:**

| Scene | Exit Trigger | Current Behavior | Gap |
|-------|-------------|------------------|-----|
| Office | `OfficeDoorTrigger` → `_start_door_dialogue()` → `office_door.json` | `next_node: null` choices set flags only | No `"scene"` key → player stays in office |
| Lobby | `ExitTrigger` → `_on_exit_trigger_input()` → `nm.advance_scene()` | Advances counter, no scene load | No dialogue, no transition |
| Store | `StoreExitTrigger` → `store_exit.json` | Choice has `"scene": "res://scenes/bridge/bridge.tscn"` | ✅ WORKS |
| Bridge | `BridgeExitTrigger` → `_on_exit_trigger_input()` → `nm.advance_scene()` | Advances counter, no scene load | No dialogue, no transition |
| Underpass | `UnderpassExitTrigger` → `_on_exit_trigger_input()` → `nm.advance_scene()` | Advances counter, no scene load | No dialogue, no transition |
| Subway Station | Gate/Bench/TurnBack triggers → `subway_ending.json` | Ending plays, sets flag, dialogue ends | No final transition after ending |

**Impact:** 4 of 6 exits are broken (office, lobby, bridge, underpass). Store works. Subway has content but no terminal behavior.

---

### Spike B: Dialogue JSON Scene Key Verification

**Question:** Does the existing dialogue engine + SceneManager actually parse `"scene"` keys from JSON dialogue choices?

**Method:** Check `scene_manager.gd` `_on_choice_made()`:

```gdscript
# SceneManager._on_choice_made (line 87-100):
var current: Dictionary = dr.current_node
var choices: Array = current.get("choices", [])
var choice: Dictionary = choices[choice_index]
if choice.has("scene") and choice["scene"] != null and str(choice["scene"]) != "":
    trigger_scene_change(choice["scene"])
```

Wait — this reads `dr.current_node`, which is the **DialogueRunner's current_node**. But the SceneManager connects to `dr.choice_made`. By the time `choice_made` fires, `dr.current_node` is still the node being acted on, not the next node. So reading `current_node` from the connection should work — it's the node where the choice was made.

But the SceneManager gets `dr` via `get_node_or_null("CanvasLayer/DialoguePanel")` — it accesses the current scene's dialogue panel. This should be the same DialogueRunner instance.

**Risk:** The `"scene"` key detection is functional and battle-tested by `store_exit.json`. No issues.

**Impact:** Confirmed — the scene transition mechanism works. The fix is purely about adding `"scene"` keys to the right dialogue choices.

---

### Spike C: Credits Scene Minimum Viable Prototype

**Question:** What's the simplest credits/post-game scene that works with the existing transition system?

**Method:** Design a minimal scene that:
1. Accepts an ending ID passed from the subway station
2. Displays the ending title and a brief epilogue text
3. Auto-advances to main menu after 10 seconds (or on click)
4. Uses the existing fade transition system

**Prototype design:**

```gdscript
# end_credits.gd
extends Node3D

var ending_id: String = ""

func _ready() -> void:
    # Ending ID could be passed via GameManager or a global
    var gm := get_node_or_null("/root/GameManager")
    if gm:
        # Check which ending flag was set
        if gm.has_flag("ending_keep_walking"):
            ending_id = "keep_walking"
        elif gm.has_flag("ending_turn_back"):
            ending_id = "turn_back"
        elif gm.has_flag("ending_stay"):
            ending_id = "stay"
    
    # Display epilogue based on ending
    _show_epilogue()
    
    # Fade in via SceneManager if present
    var sm := $SceneManager
    if sm and sm.has_method("fade_in"):
        sm.fade_in()
    
    # Auto-return to menu
    get_tree().create_timer(10.0).timeout.connect(_return_to_menu)

func _show_epilogue() -> void:
    # Set text based on ending_id
    pass

func _return_to_menu() -> void:
    get_tree().change_scene_to_file("res://scenes/main.tscn")
    GameManager.reset()
    StateSystem.reset()
```

**Scene structure:**
- Label3D for ending title
- Label3D for epilogue text (3 sentences max per Hemingway)
- Timer for auto-return
- Click-to-continue via `_input`

**Risk:** Low — this is a standard pattern.

**Impact:** Confirms that the credits scene is quick to build and integrates cleanly with existing systems.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

### Current State Summary

The narrative game has 6 fully-authored scenes with dialogue, state-aware environmental text, and NPC interactions. The core systems (StateSystem, NarrativeManager, DialogueRunner, SceneManager, PlayerController) are all implemented and tested. The scene sequence is:

```
office → lobby → convenience_store → bridge → underpass → subway_station
```

### Key Gaps to Fill

**1. Office door transition (office_door.json)**
- Currently: `door_leave` choices set flags (`left_office`, `left_with_purpose`) with `next_node: null` — no scene transition.
- Fix: Add `"scene": "res://scenes/lobby/lobby.tscn"` to all terminal choices in `door_leave` node.

**2. Lobby exit transition (lobby.gd + new lobby_exit.json)**
- Currently: `_on_exit_trigger_input` calls `nm.advance_scene()` but loads nothing.
- Fix: Change exit trigger to start a new `lobby_exit.json` dialogue with `"scene": "res://scenes/store/convenience_store.tscn"`.

**3. Bridge exit transition (bridge.gd + new bridge_exit.json)**
- Currently: Same pattern as lobby — `advance_scene()` only.
- Fix: Change exit trigger to start `bridge_exit.json` with `"scene": "res://scenes/underpass/underpass.tscn"`.

**4. Underpass exit transition (underpass.gd + new underpass_exit.json)**
- Currently: Same pattern.
- Fix: Change exit trigger to start `underpass_exit.json` with `"scene": "res://scenes/subway_station/subway_station.tscn"`.

**5. Subway ending terminal (subway_ending.json + new end_credits scene)**
- Currently: Ending dialogue sets flag and ends — no further action.
- Fix: Add `"scene": "res://scenes/end_credits.tscn"` to each ending's terminal choice. Create credits scene.

**6. Post-credits behavior**
- Currently: No main menu, no reset flow.
- Fix: Credits scene should display ending info, then transition back to start (main.tscn → office.tscn) with full GameManager + StateSystem reset.

### Implementation Order

1. Create `dialogues/lobby_exit.json` (simplest — 1–2 nodes, 1 choice to go)
2. Create `dialogues/bridge_exit.json` (same pattern)
3. Create `dialogues/underpass_exit.json` (same pattern)
4. Update `dialogues/office_door.json` — add `"scene"` keys to terminal choices
5. Update `dialogues/subway_ending.json` — add `"scene"` keys to terminal choices
6. Create `scenes/end_credits.tscn` + `gdscripts/end_credits.gd`
7. Update scene scripts (lobby.gd, bridge.gd, underpass.gd) to wire exit triggers
8. Test full playthrough: office → lobby → store → bridge → underpass → subway → credits

### Risk Summary

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Scene path typo in JSON | Low | Copy existing scene paths from constants.gd |
| Dialogue runner state after exit | Low | SceneManager persists to GameManager before transition |
| Credits scene doesn't reset state | Low | Explicit reset in _ready() |
| Player spawned at wrong position | Low | PlayerController restores position from GameManager |
| Street scene not needed | Confirmed | Street is not in SCENE_ORDER, no path references it |
