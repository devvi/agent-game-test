# Design: #59 — Mysterious Stranger NPC (三层真相对话树)

> Parent Issue: #59
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Implement a three-layer dialogue tree for the Mysterious Stranger in the underpass scene: **Shallow** (AC1 — 3 dialogue paths → 3 ending directions), **Middle** (AC2 — prior scene choices dynamically affect Stranger's attitude and dialogue), and **Deep** (AC3 — second playthrough or specific triggers unlock meta-narrative layer where Stranger reveals "I am you"). All three layers live in a single JSON file (`underpass_stranger_echo.json`) using the existing Condition DSL (`slider`/`flag`/`choice_made`/`and`/`or`/`not`).

### Data Flow

```
Player reaches underpass (scene 5 of 6)
    │
    ├──► _ready():
    │       ├──► StateSystem.get_state()           — hope/conviction/will (0-10 each)
    │       ├──► GameManager.playthrough_count     — for AC3 (≥2 → deep layer)
    │       ├──► NarrativeManager.echo_flags       — screensaver_echo, rain_echo, etc.
    │       ├──► _check_echoes()                   — trigger screensaver/rain echoes
    │       └──► _check_hidden_text()              — AC3 despair threshold (hope≤2 AND conviction≤2)
    │
    ├──► Player clicks StrangerEchoTrigger:
    │       ├──► NarrativeManager.trigger_echo("rain_echo")
    │       └──► start_dialogue("res://dialogues/underpass_stranger_echo.json")
    │               │
    │               ├──► Layer Selection (Condition DSL in dialogue JSON):
    │               │       ├──► AC3 Deep Layer: playthrough_count ≥ 2
    │               │       │       └──► Stranger "I am you" — 4 nodes, meta-narrative
    │               │       │
    │               │       ├──► AC2 Middle Layer: prior choice flags from office/store/bridge
    │               │       │       ├──► office_exit_sigh / neutral / determined
    │               │       │       ├──► bought_coffee / clerk_comforted / chatted_with_clerk
    │               │       │       └──► screensaver_echo_heard (bridge intrusive thought)
    │               │       │       └──► slider thresholds (hope ≥ 9, hope ≤ 2, conviction ≤ 3, etc.)
    │               │       │
    │               │       └──► AC1 Shallow Layer: all players see (default)
    │               │               ├──► Path A: "我知道…" → Keep Walking (+hope/+conviction/+will)
    │               │               ├──► Path B: "不关你的事" → Turn Back direction
    │               │               └──► Path C: 沉默走过 → Stay direction
    │               │
    │               └──► Effects applied via on_enter / choices effects:
    │                       ├──► slider_delta: hope/conviction/will
    │                       └──► set_flag: stranger_revealed (AC3), etc.
    │
    ▼
Subway Station (ending determination based on final state)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Dialogue tree structure | Single-file three-layer (Solution A from PRD) | All layers in one JSON; Condition DSL controls branch visibility. No engine changes needed. ~24 nodes total, well within limits. |
| AC3 activation trigger | `GameManager.playthrough_count ≥ 2` | Simple counter incremented in `start_game()`. Dialogue engine's `flag` condition type checks `is_new_game_plus` flag set by underpass.gd before dialogue starts. |
| Middle-layer condition model | `and`/`or` combinations of `flag` + `slider` conditions | PRD Experiment 2 confirmed 6+ trackable flags and 3 slider axes. No new condition types needed. |
| Dialogue entry node routing | Single entry point (`echo_entry`) with condition-gated initial choices | All three layers start from the same entry node; condition DSL filters available choices per player state. No multi-file switching. |
| Hemingway constraints | Strict: ≤25 chars/sentence, ≤3 sentences/node | Must verify every node during implementation. Use `⌈⌋` brackets for AC3 meta-text emphasis. |
| Playthrough counting | `GameManager.playthrough_count: int` increment at `start_game()` + `reset()` propagation | Minimal change — add one field + one increment. Underpass.gd reads it before starting dialogue and sets `is_new_game_plus` flag. |
| Dialogue file organization | Single file: `underpass_stranger_echo.json` (rewrite from 250→~400 lines) | Current file already has 250 lines with 6 conditional variants. Expanding to ~400 lines with 24 nodes and conditions. |

---

## 2. New Files

### `gdscripts/narrative_manager.gd` — Extend (no new file)

No new files required for this issue. All changes are modifications to existing files.

---

## 3. Modified Files

### Dialogue Runner/Layer — Dialogue Files

#### `dialogues/underpass_stranger_echo.json` — REWRITE

**Current state:** 250 lines, 12 nodes (3 base paths + 6 conditional variants based on `screensaver_echo_heard` and low conviction sliders). Already has the basic structure for a 2-layer dialogue.

**Target state:** ~400 lines, ~24 nodes, 3 layers:

| Layer | Nodes | Description | Conditions |
|-------|-------|-------------|------------|
| **AC1 — Shallow** | 8 | Entry + 3 paths (acknowledge/deny/silent) + terminal nodes. Default for all players. | None (always visible) |
| **AC2 — Middle** | 12 | State-aware variants per choice. Office exit flags, store flags, bridge echo flags, slider thresholds. | `flag(office_exit_sigh/neutral/determined)`, `flag(bought_coffee)`, `flag(screensaver_echo_heard)`, `slider(hope, lte/gte, val)`, `slider(conviction, lte, 3.0)` |
| **AC3 — Deep** | 4 | Meta-narrative reveal. Stranger says "I am you". Only on second playthrough. | `flag(is_new_game_plus, true)` |

**Dialogue node structure (new nodes):**

```
echo_entry (entry node — unchanged, expand greetings)
│
├──▶ AC1 Shallow Paths:
│   ├── echo_acknowledge        "……好。那就走吧。"          (existing, expand)
│   ├── echo_deny               "……你说得对。不关我的事。"  (existing, expand)
│   └── echo_silent             "You walk past..."          (existing, expand)
│
├──▶ AC2 Middle Variants (per AC1 path, per state):
│   │   Each AC1 path has 4 conditional variants:
│   │   1. screensaver_echo variant        (existing: echo_acknowledge_echo, etc.)
│   │   2. low conviction variant          (existing: echo_acknowledge_low_conviction, etc.)
│   │   3. high hope variant               (new: hope ≥ 9, Stranger says "You're almost out")
│   │   4. low hope variant                (new: hope ≤ 2, Stranger says "You're still here")
│   │
│   └── Office/store cross-reference nodes:
│       ├── echo_office_sigh         Condition: flag(office_exit_sigh)
│       ├── echo_office_determined   Condition: flag(office_exit_determined)
│       └── echo_coffee_ref          Condition: flag(bought_coffee)
│
└──▶ AC3 Deep Path (second playthrough only):
    ├── echo_meta_entry       "你知道我是谁，对吧。"       Condition: flag(is_new_game_plus)
    ├── echo_meta_reveal      "我就是你。"                  (reveal)
    ├── echo_meta_choice      "接受 / 否认 / 沉默"          (choice)
    └── echo_meta_end         "(narrator) The tunnel is empty."  (terminal)
```

#### `dialogues/lobby_stranger.json` — EXPAND

Add 2–3 state-aware branches that set flags used by the underpass dialogue:

| New Node | Condition | Purpose | Effects |
|----------|-----------|---------|---------|
| `stranger_high_hope` | `slider(hope, gte, 7)` | Stranger warmer, more reflective | Sets `lobby_hope_high` flag |
| `stranger_low_conviction` | `slider(conviction, lte, 4)` | Stranger more guarded | Sets `lobby_low_conviction` flag |
| `stranger_dejavu_deep` | `slider(hope, gte, 7) AND slider(conviction, gte, 7)` | Stranger hints at "I am you" (pre-echo) | Sets `stranger_hinted_meta` flag |

#### `dialogues/subway_ending.json` — EXPAND

Add Stranger dialogue mapping for each ending that reflects the 3-layer dialogue choices:

| Node | Condition | Text Variation |
|------|-----------|----------------|
| `kw_stranger_meta` | `flag(stranger_revealed)` | "下次再见。……或者说，下次再见自己。" |
| `tb_stranger_meta` | `flag(stranger_revealed)` | "你确定？我知道你在想什么。因为我就是你。" |
| `st_stranger_meta` | `flag(stranger_revealed)` | "……… 你懂了吗？" |
| `kw_stranger_default` | default | "下次再见。" (existing) |

### GDScript Layer

#### `gdscripts/underpass.gd` — MODIFY

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Add `is_new_game_plus` flag setting before dialogue start | Before calling `start_dialogue()`, check `GameManager.playthrough_count ≥ 2` and set flag | +5 |
| Expand `_on_stranger_echo_trigger_input()` to pass playthrough context | Pass playthrough-aware flags to dialogue engine | +10 |
| Add state-query helpers for extreme slider values (hope ≥ 9, hope ≤ 2) | For AC2 extreme value variants | +8 |
| Ensure `_check_hidden_text()` AC3 path works alongside expanded dialogue | Verify `EchoText.visible` logic still correct | +2 |

#### `gdscripts/narrative_manager.gd` — EXTEND

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Add `playthrough_count` read accessor | Read GameManager.playthrough_count from dialogue condition evaluator path | +3 |
| Add `is_new_game_plus` flag pass-through | Ensure flag propagates to dialogue condition evaluator | +3 |
| End-echo variants for stranger_echo | The existing `stranger_echo` echo variant calculation already exists (line 111-125) — verify it handles new AC3 state | +0 |

#### `gdscripts/game_manager.gd` — MODIFY

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Add `playthrough_count: int` field | Default 0. Incremented in `start_game()` | +2 |
| Increment `playthrough_count` in `start_game()` | `playthrough_count += 1` at end of start_game | +1 |
| Propagate count in `reset()` or new-game flow | Ensure playthrough_count persists across game restarts (save to file or keep in memory for session) | +4 |
| Add accessor `get_playthrough_count() → int` | For dialogue condition evaluator to read | +3 |

### Documentation

#### `docs/GAME_DESIGN/06-NARRATIVE.md` — UPDATE

Expand Section 6 (Stranger NPC 设计) with the three-layer dialogue design:
- Update the 3-appearance table with dialogue layer descriptions
- Add sub-section for AC3 meta-narrative layer ("I am you" reveal)
- Document the `playthrough_count` mechanic

---

## 4. API Contracts

### Signal Connections (underpass.gd)

```gdscript
# Existing — no new signals needed
stranger_echo_trigger.input_event.connect(_on_stranger_echo_trigger_input)

# Modified handler (add playthrough-aware flag setting):
func _on_stranger_echo_trigger_input(camera: Node, event: InputEvent, ...) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var nm := get_node_or_null("/root/NarrativeManager")
        if nm and nm.has_method("trigger_echo"):
            nm.trigger_echo("rain_echo")
        
        # AC3: Set is_new_game_plus flag for dialogue conditions
        var gm := get_node_or_null("/root/GameManager")
        if gm and gm.has_method("get_playthrough_count"):
            if gm.get_playthrough_count() >= 2:
                if nm and nm.has_method("set_flag"):
                    nm.set_flag("is_new_game_plus", true)
        
        start_dialogue("res://dialogues/underpass_stranger_echo.json", "underpass_stranger_echo")
```

### Method Call Chains

```
underpass._ready()
    ├──► _check_echoes()
    │       └──► NarrativeManager.trigger_echo("screensaver_echo")
    │       └──► NarrativeManager.trigger_echo("rain_echo")
    └──► _check_hidden_text()
            └──► StateSystem.get("hope"), StateSystem.get("conviction")
                    └──► if hope ≤ 2.0 AND conviction ≤ 2.0:
                            └──► EchoText.visible = true (Stranger-as-projection reveal)

Player clicks StrangerEchoTrigger
    └──► _on_stranger_echo_trigger_input()
            ├──► NarrativeManager.trigger_echo("rain_echo")
            ├──► GameManager.get_playthrough_count()
            │       └──► if ≥ 2: NarrativeManager.set_flag("is_new_game_plus", true)
            └──► start_dialogue("res://dialogues/underpass_stranger_echo.json")
                    └──► DialogueRunner.load_dialogue(file, id)
                            └──► DialogueRunner.enter_node(entry_node_id)
                                    └──► DialogueConditionEvaluator.evaluate(condition, state)
                                            ├──► GameManager.get_slider(axis)
                                            ├──► GameManager.has_flag(flag_name)
                                            └──► GameManager.get_playthrough_count()
                                                    └──► return flag conditions match
                    └──► Player selects choice
                            ├──► Condition check for next_node visibility
                            └──► Effects applied: slider_delta / set_flag / next_node
```

### GameManager Extension

```gdscript
# New field
var playthrough_count: int = 0

# Modified start_game()
func start_game() -> void:
    game_started = true
    playthrough_count += 1
    print("Game started! (Playthrough #%d)" % playthrough_count)

# New accessor
func get_playthrough_count() -> int:
    return playthrough_count

# Modified reset() or new-game flow
func reset() -> void:
    _state_system = get_node_or_null("/root/StateSystem")
    _flags = {}
    dialogue_history = []
    current_scene_id = "office"
    scene_visited = {}
    choices_made = 0
    # Note: playthrough_count is NOT reset — it persists across playthroughs
```

### Dialogue Condition Format (AC3)

```json
{
  "type": "flag",
  "flag": "is_new_game_plus",
  "value": true
}
```

### Cross-scene Flag Reference (Middle Layer)

| Flag | Set In | Affects Underpass Dialogue |
|------|--------|---------------------------|
| `office_exit_sigh` | `dialogues/office_door.json` | Stranger references "that sigh" |
| `office_exit_neutral` | `dialogues/office_door.json` | Stranger references "the routine" |
| `office_exit_determined` | `dialogues/office_door.json` | Stranger acknowledges resolve |
| `bought_coffee` | `dialogues/store_clerk.json` | Stranger asks about coffee (existing) |
| `clerk_comforted` | `dialogues/store_clerk.json` | Stranger softer, "someone cares" |
| `chatted_with_clerk` | `dialogues/store_clerk.json` | Stranger "you like to talk" |
| `screensaver_echo_heard` | `dialogues/bridge_homeless.json` | Stranger references intrusive thought (existing) |
| `lobby_hope_high` | `dialogues/lobby_stranger.json` | Stranger "you were hopeful back then" |
| `lobby_low_conviction` | `dialogues/lobby_stranger.json` | Stranger "you were uncertain from the start" |
| `stranger_hinted_meta` | `dialogues/lobby_stranger.json` | Stranger "I told you, didn't I?" (AC3 bridge) |

---

## 5. Test Plan

### Test Structure

| File | Type | Target |
|------|------|--------|
| `tests/test_stranger_dialogue.gd` | Unit | Dialogue condition evaluation for all 3 layers, flag/slider combinations |
| `tests/test_game_manager_playthrough.gd` | Unit | `playthrough_count` increment, `get_playthrough_count()` accessor, `is_new_game_plus` flag |
| `tests/test_stranger_scene.gd` | Integration | Underpass dialogue trigger, AC1/AC2/AC3 dialogue routing, ending effects |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| AC1 — Shallow dialogue | ✅ | ≥3 | ✅ |
| AC2 — Middle dialogue (state-aware) | ✅ | ≥4 | ✅ |
| AC3 — Deep dialogue (meta) | ✅ | ≥2 | ✅ |
| playthrough_count | ✅ | ≥2 | ✅ |
| Lobby stranger expanded flags | ✅ | ≥2 | ✅ |
| Subway ending mapping | ✅ | ≥2 | ✅ |
| Hemingway constraints | ✅ | ≥3 | ✅ |

### Test Cases

#### AC1: Shallow Layer (TC1–TC4)

**TC1: AC1 Shallow — All three paths visible on first playthrough**
- Type: Unit / Normal
- Setup: Mock `GameManager.playthrough_count = 1`. All flags false. `hope=5, conviction=5, will=5`.
- Steps: Load `underpass_stranger_echo.json`. Start dialogue at `echo_entry`.
- Assert: All 3 choices visible in echo_entry: acknowledge, deny, silent. No condition-gated nodes shown.
- Verification: Check `echo_entry.choices` has 3 items. Check `echo_acknowledge` is terminal-reachable without conditions.

**TC2: AC1 Shallow — Acknowledge path applies +stats**
- Type: Unit / Normal
- Setup: Same as TC1.
- Steps: Select acknowledge path. Continue to terminal.
- Assert: `hope +1.0`, `conviction +1.0`, `will +1.0` applied. Flag `stranger_walked_with` set.
- Verification: Check slider deltas via mock GameManager. Check flag set.

**TC3: AC1 Shallow — Deny path applies -stats**
- Type: Unit / Normal
- Setup: Same as TC1.
- Steps: Select deny path. Continue to terminal.
- Assert: `hope -1.0`, `conviction -1.0`, `will -1.0` applied. Flag `stranger_denied` set.
- Verification: Check slider deltas.

**TC4: AC1 Shallow — Silent path is neutral**
- Type: Unit / Normal
- Setup: Same as TC1.
- Steps: Select silent path. Continue to terminal.
- Assert: No slider deltas (all ±0). No flags set.
- Verification: Check no slider changes. No flag changes.

#### AC2: Middle Layer (TC5–TC10)

**TC5: AC2 Middle — screensaver_echo_heard variant shown**
- Type: Unit / Normal
- Setup: `GameManager.playthrough_count = 1`. `screensaver_echo_heard = true`. All other flags false.
- Steps: Start dialogue at echo_entry. Select acknowledge.
- Assert: `echo_acknowledge_echo` shown instead of default `echo_acknowledge`. Text contains "你听到了" or equivalent screensaver reference.
- Verification: Check `choice_made` leads to echo variant node. Check text content matches.

**TC6: AC2 Middle — Low conviction variant shown**
- Type: Unit / Edge
- Setup: `conviction = 2.0` (≤3). `screensaver_echo_heard = false`.
- Steps: Start dialogue. Select acknowledge.
- Assert: `echo_acknowledge_low_conviction` shown. Text contains conviction reference.
- Verification: Check node ID matches expected variant.

**TC7: AC2 Middle — High hope variant (hope ≥ 9)**
- Type: Unit / Edge
- Setup: `hope = 9.0`. All flags false.
- Steps: Start dialogue. Select acknowledge.
- Assert: New high-hope variant node shown (e.g. "You're almost out"). Text more hopeful.
- Verification: Check new node `echo_acknowledge_high_hope` is chosen.

**TC8: AC2 Middle — Low hope variant (hope ≤ 2)**
- Type: Unit / Edge
- Setup: `hope = 1.0`. All flags false.
- Steps: Start dialogue. Select acknowledge.
- Assert: Low-hope variant shown (e.g. "You're still here"). Text darker.
- Verification: Check new node `echo_acknowledge_low_hope` is chosen.

**TC9: AC2 Middle — Office sigh flag triggers cross-reference**
- Type: Unit / Normal
- Setup: `office_exit_sigh = true`. All other flags false.
- Steps: Start dialogue. Navigate through.
- Assert: A cross-reference node (e.g. `echo_office_sigh`) is visible in the available choices, referencing the office sigh.
- Verification: Check node condition evaluated true.

**TC10: AC2 Middle — Multiple flags combine (and/or)**
- Type: Unit / Edge
- Setup: `screensaver_echo_heard = true AND conviction = 2.0` (both conditions match).
- Steps: Start dialogue. Select acknowledge.
- Assert: The highest-priority variant shows (screensaver variant has higher condition priority than slider-only variant). Check node ID is `echo_acknowledge_echo` (not low conviction).
- Verification: Simulate dialogue order — screensaver condition checked first.

#### AC3: Deep Layer (TC11–TC14)

**TC11: AC3 Deep — is_new_game_plus flag unlocks meta entry**
- Type: Unit / Normal
- Setup: `GameManager.playthrough_count = 2`. `is_new_game_plus = true` (set by underpass.gd before dialogue start). `hope = 5, conviction = 5`.
- Steps: Start dialogue at echo_entry.
- Assert: A 4th choice "你知道我是谁，对吧" is visible in echo_entry alternatives.
- Verification: Check `echo_meta_entry` node condition evaluates true. Check choice text.

**TC12: AC3 Deep — Meta reveal node shows "I am you"**
- Type: Unit / Normal
- Setup: Same as TC11. Select meta choice.
- Steps: Navigate through meta_entry → meta_reveal.
- Assert: `echo_meta_reveal` speaker is "Stranger" and text contains "我就是你" or "I am you".
- Verification: Check node text content.

**TC13: AC3 Deep — Meta choice affects ending flags**
- Type: Unit / Edge
- Setup: Same as TC11. Reach meta_choice node.
- Steps: Choose "接受" (accept).
- Assert: Flag `stranger_meta_accepted` set. Ending direction influenced.
- Verification: Check flag value. Check subway_ending.json has meta-aware variant.

**TC14: AC3 Deep — No deep layer on first playthrough (playthrough_count = 1)**
- Type: Unit / Boundary
- Setup: `GameManager.playthrough_count = 1`. `is_new_game_plus` was NOT set (flag is false).
- Steps: Start dialogue.
- Assert: No meta choice visible. Only AC1 and AC2 variants shown.
- Verification: Check `echo_meta_entry` NOT in visible choices.

#### GameManager & Infrastructure (TC15–TC18)

**TC15: playthrough_count increments on start_game()**
- Type: Unit / Normal
- Setup: Fresh GameManager instance. `playthrough_count = 0`.
- Steps: Call `start_game()`. Call again. Call again.
- Assert: After 3 calls, `playthrough_count = 3`.
- Verification: `assert(gm.playthrough_count == 3)`.

**TC16: playthrough_count persists across resets (memory persistence)**
- Type: Unit / Edge
- Setup: GameManager.playthrough_count = 2.
- Steps: Call `reset()` (or equivalent new-game flow that calls start_game).
- Assert: `playthrough_count = 3` (incremented from 2, not reset to 1).
- Verification: `assert(gm.playthrough_count == 3)`.

**TC17: get_playthrough_count() accessor returns correct value**
- Type: Unit / Normal
- Setup: GameManager.playthrough_count = 5.
- Steps: Call `get_playthrough_count()`.
- Assert: Returns 5.
- Verification: `assert(gm.get_playthrough_count() == 5)`.

**TC18: Lobby stranger expanded flags set correctly**
- Type: Integration / Normal
- Setup: In lobby scene, set `hope = 8, conviction = 4`.
- Steps: Interact with lobby Stranger. Choose appropriate options.
- Assert: `lobby_hope_high` flag set (from high-hope variant). `lobby_low_conviction` NOT set (conviction > 4).
- Verification: Check flag dictionary after dialogue ends.

#### Subway Ending Mapping (TC19–TC20)

**TC19: Keep Walking ending shows meta-aware Stranger line**
- Type: Integration / Normal
- Setup: `stranger_revealed = true` (AC3 completed). Ending state meets Keep Walking thresholds.
- Steps: Reach subway ending. Navigate to kw_stranger node.
- Assert: `kw_stranger_meta` shown instead of default kw_stranger. Text references "下次再见自己".
- Verification: Check node ID matches meta variant.

**TC20: Turn Back ending with meta awareness**
- Type: Integration / Edge
- Setup: `stranger_revealed = true`. Conviction ≤ 3 (Turn Back condition).
- Steps: Reach subway ending. Navigate to tb_stranger node.
- Assert: `tb_stranger_meta` shown. Stranger says "你确定？我知道你在想什么。因为我就是你。"
- Verification: Check node ID and text.

---

## 6. Files Changed

### Master Summary

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `dialogues/underpass_stranger_echo.json` | **Modified** | Rewrite from 250→~400 lines: expand from 12 nodes to ~24 with 3 layers. Add AC2 extreme-state variants (hope≥9, hope≤2), AC3 meta-narrative path, office/store cross-references. | +150 |
| `dialogues/lobby_stranger.json` | **Modified** | Add 2-3 state-aware branches: high hope variant, low conviction variant, deep deja vu path. | +40 |
| `dialogues/subway_ending.json` | **Modified** | Add meta-aware Stranger dialogue nodes for each ending path. Condition on `stranger_revealed` flag. | +30 |
| `gdscripts/underpass.gd` | **Modified** | Add `is_new_game_plus` flag setting before dialogue start. Add extreme-state query helpers. Expand `_on_stranger_echo_trigger_input()`. | +15 |
| `gdscripts/narrative_manager.gd` | **Modified** | Add `playthrough_count` read accessor, `is_new_game_plus` flag pass-through to dialogue system. | +6 |
| `gdscripts/game_manager.gd` | **Modified** | Add `playthrough_count` field (+2), increment in `start_game()` (+1), add `get_playthrough_count()` accessor (+3), propagate in reset flow (+4). | +10 |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | **Modified** | Update Section 6 with 3-layer dialogue design, AC3 meta-narrative, playthrough_count mechanic. | +30 |
| `tests/test_stranger_dialogue.gd` | **New** | Unit tests for dialogue condition evaluation: all 3 layers, flag/slider combinations, Hemingway constraints. | +150 |
| `tests/test_game_manager_playthrough.gd` | **New** | Unit tests for playthrough_count increment, persistence, accessor. | +60 |
| `tests/test_stranger_scene.gd` | **New** | Integration tests for full underpass dialogue flow, AC1/AC2/AC3 routing, ending effects mapping. | +120 |

### Legend

| Column | Meaning |
|--------|---------|
| **Type** | New file or modification to existing file |
| **Change** | Concise description of what changes |
| **Est. Lines** | Estimated line delta (+ added, - removed, ± net change) |

---

## 7. Verification Checklist

- [ ] **AC1 — Three dialogue paths in underpass (Shallow layer):**
  - [ ] All 3 choices visible in echo_entry: acknowledge, deny, silent
  - [ ] Acknowledge: +hope/+conviction/+will, sets `stranger_walked_with`
  - [ ] Deny: -hope/-conviction/-will, sets `stranger_denied`
  - [ ] Silent: no stat changes, no flags
  - [ ] Each path leads to a distinct terminal node (ending direction)
  - [ ] No condition-gated nodes visible on first playthrough with neutral state

- [ ] **AC2 — State-aware dialogue (Middle layer):**
  - [ ] `screensaver_echo_heard` → echo variants shown per chosen path
  - [ ] `conviction ≤ 3` → low conviction variants shown
  - [ ] `hope ≥ 9` → high hope variants shown (new)
  - [ ] `hope ≤ 2` → low hope variants shown (new)
  - [ ] `office_exit_sigh` → Stranger references office sigh
  - [ ] `office_exit_determined` → Stranger acknowledges resolve
  - [ ] `bought_coffee` → Stranger asks about coffee (existing)
  - [ ] Multiple conditions combine correctly (priority: screensaver > slider)
  - [ ] Cross-reference nodes only visible when their flag is set

- [ ] **AC3 — Second playthrough meta-narrative (Deep layer):**
  - [ ] `playthrough_count ≥ 2` → `is_new_game_plus` flag set before dialogue start
  - [ ] Meta entry node "你知道我是谁，对吧" visible as 4th choice
  - [ ] Meta reveal "我就是你" properly displayed
  - [ ] Meta choice (accept/deny/silence) affects ending dialogue
  - [ ] No meta layer visible on first playthrough

- [ ] **GameManager changes:**
  - [ ] `playthrough_count` increments on each `start_game()`
  - [ ] `get_playthrough_count()` accessor works
  - [ ] `playthrough_count` persists across `reset()` calls
  - [ ] `is_new_game_plus` flag set correctly in underpass.gd

- [ ] **Lobby stranger expanded flags:**
  - [ ] `lobby_hope_high` set when hope ≥ 7
  - [ ] `lobby_low_conviction` set when conviction ≤ 4
  - [ ] `stranger_hinted_meta` set on combined high hope + high conviction

- [ ] **Subway ending mapping:**
  - [ ] Keep Walking: meta variant shown if `stranger_revealed`
  - [ ] Turn Back: meta variant shown if `stranger_revealed`
  - [ ] Stay: meta variant shown if `stranger_revealed`
  - [ ] Default (non-meta) variants unchanged

- [ ] **Hemingway constraints:**
  - [ ] All dialogue nodes: ≤25 chars per sentence
  - [ ] All dialogue nodes: ≤3 sentences per node
  - [ ] AC3 meta-text wrapped in ⌈⌋ for emphasis

- [ ] **No regression:**
  - [ ] All pre-existing tests still pass
  - [ ] Existing underpass scene flow unchanged (graffiti, exit)
  - [ ] Existing echo triggers still work (rain_echo, screensaver_echo)
  - [ ] Existing Stranger behavior in lobby unchanged
  - [ ] Scene transitions (underpass → subway) unaffected
