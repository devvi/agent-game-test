# Design: #156 — Scene Transition System — Walking between areas

> Parent Issue: #156
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Replace the current **dialogue-only** scene transition system with a **walk-based** system where the player physically moves the character into exit zones (Area3D) to trigger scene-to-scene transitions. Three transition modes coexist:

1. **Zone-based (AUTO)** — Player walks into an ExitZone → automatic fade-to-black → next scene loads
2. **Zone-based (EKEY)** — Player walks into an ExitZone → optional prompt ("Press E") → player presses E → transition
3. **Dialogue-driven (existing)** — Dialogue choices with `"scene"` metadata continue to work unchanged

All three paths share the same `SceneManager` fade-out / fade-in pipeline and the same `GameManager` persistence layer.

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| ExitZone detection | `Area3D.body_entered` | Simplest trigger; fires once per player entry, no continuous overlap checks |
| Double-trigger guard | Check `transition_in_progress` | Same guard existing in `trigger_scene_change()`; transit + zone both guarded |
| Spawn point storage | `GameManager.target_spawn_point` | Follows the same pattern as `transition_in_progress` (Issue #148); cleared after use |
| E-key prompt | Optional Label3D child on ExitZone | No separate UI system needed; diegetic world-space label |
| AUTO mode safety | 1-second cooldown timer on auto-trigger | Prevents re-trigger if player doesn't leave zone before collision re-entry |
| Zone shape | BoxShape3D | Best fit for doorways/archways (0.5m × 2m × 3m) |
| Spawn point fallback | Scene-local `SpawnPoint` Marker3D | `GameManager.target_spawn_point` checked first; falls back to Marker3D, then `Vector3.ZERO` |

### `add_child` Race Condition (already fixed in #148)

The SceneManager already uses `call_deferred` for `add_child(_fade_curtain)` in `_setup_fade_curtain()` (line 35). The `transition_in_progress` propagation via `GameManager` was also fixed in #148. No additional race-condition fixes are needed for this issue. The exit zone system builds on top of this working foundation.

---

## 2. Files Changed

### 2.1 New File: `gdscripts/exit_zone.gd` — ExitZone Area3D Component

**Purpose:** Reusable `extends Area3D` class placed at scene exits. Detects player proximity via `body_entered`/`body_exited` and triggers scene transitions.

**Exported properties:**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `target_scene` | `String` | `""` | Path to destination `.tscn` file |
| `spawn_point` | `Vector3` | `Vector3.ZERO` | Player position in target scene's local space |
| `transition_mode` | `int` (enum) | `AUTO` | `AUTO=0` transition immediately, `EKEY=1` wait for E key |
| `prompt_text` | `String` | `""` | If non-empty, show Label3D when player is inside zone (EKEY mode only) |
| `cooldown` | `float` | `1.0` | Seconds to ignore re-trigger after auto-trigger fires |

**Constants:**
```gdscript
const TRANSITION_MODE_AUTO := 0
const TRANSITION_MODE_EKEY := 1
```

**Script structure (~90 lines):**

```
ExitZone (Area3D)
  ├── CollisionShape3D (BoxShape3D — 0.5m × 2m × 3m)
  ├── PromptLabel (Label3D) — optional, only created if prompt_text is set
```

**Key methods:**

| Method | Visibility | Description |
|--------|-----------|-------------|
| `_ready()` | private | Connect `body_entered`/`body_exited`; validate `target_scene`; add safety timer |
| `_on_body_entered(body)` | private | If body is in `"player"` group: auto-zone → call `_transition()`; EKEY zone → show prompt, connect player's `interaction_requested` |
| `_on_body_exited(body)` | private | If body is player: hide prompt, disconnect signal |
| `_on_player_interact(_target)` | private | EKEY mode only: call `_transition()` |
| `_transition()` | private | Set `GameManager.target_spawn_point`, call `SceneManager.trigger_zone_transition()` |
| `_show_prompt()` | private | Make PromptLabel visible (EKEY mode) |
| `_hide_prompt()` | private | Make PromptLabel invisible (EKEY mode) |
| `_validate_config()` | private | Warn if `target_scene` is empty or CollisionShape3D is missing |

**Transition flow:**
```gdscript
func _transition() -> void:
    var sm := get_parent().get_node_or_null("SceneManager")
    if not sm or not sm.has_method("trigger_zone_transition"):
        push_error("ExitZone: SceneManager not found on parent")
        return
    var gm := get_node_or_null("/root/GameManager")
    if gm:
        gm.set("target_spawn_point", spawn_point)
    sm.trigger_zone_transition(target_scene)
```

**Edge-case guards:**
- `body_entered` ignored if `transition_in_progress` is already true (on GameManager)
- AUTO mode uses a `Timer` (one-shot, 1s cooldown) to prevent rapid re-trigger
- EKEY mode: `interaction_requested` signal is connected only while player is inside zone
- `_ready()`: exit early if no CollisionShape3D child (push_warning, not error)

### 2.2 Modified: `gdscripts/scene_manager.gd` — Add `trigger_zone_transition()`

**Current state:** 162 lines. Manages fade transitions. Has `trigger_scene_change()`, `fade_in()`, `transition_in_progress` guard.

**Add a new public method** after the existing `trigger_scene_change()`:

```gdscript
## Trigger a scene transition from an ExitZone.
## Sets target spawn point for the player in the destination scene,
## then delegates to the existing fade pipeline.
func trigger_zone_transition(target_scene: String, fade_duration: float = 0.5) -> void:
    if transition_in_progress:
        return
    # target_spawn_point is already set on GameManager by the ExitZone
    trigger_scene_change(target_scene, fade_duration)
```

**Why a separate method?** Keeps the dialogue path (no spawn-point override) cleanly separated from the zone path (spawn-point set). Both converge at `trigger_scene_change()` for the fade pipeline. The `target_spawn_point` is set by the ExitZone *before* calling this method, so the chain is:

```
ExitZone._transition()
  → GameManager.target_spawn_point = zone.spawn_point   [set before transition starts]
  → SceneManager.trigger_zone_transition(target_scene)
    → SceneManager.trigger_scene_change(target_scene)
      → fade_out → change_scene_to_file → new scene loads
      → SceneManager._ready() → fade_in()
      → SceneBase._ready()
        → _instantiate_player()
          → reads GameManager.target_spawn_point FIRST
          → clears it after use
```

**Also modify `trigger_scene_change()`** to clear `GameManager.target_spawn_point` on the source side (prevent stale values):

```gdscript
# At the start of trigger_scene_change, clear any stale spawn point
var gm := get_node_or_null("/root/GameManager")
if gm and "target_spawn_point" in gm:
    gm.set("target_spawn_point", Vector3.ZERO)
```

Add this right after the existing `var gm := get_node_or_null("/root/GameManager")` block (around line 113). This ensures that dialogue-driven transitions (which don't set `target_spawn_point`) will not accidentally use a stale value from a previous zone-based transition.

### 2.3 Modified: `gdscripts/scene_base.gd` — Read `GameManager.target_spawn_point`

**Current state:** 139 lines. `_get_player_spawn_position()` (line 109-114) reads the scene's `SpawnPoint` Marker3D, falls back to `Vector3.ZERO`.

**Changes:**

**A — Add `target_spawn_point` lookup in `_instantiate_player()`**

After `add_child(_player)` (line 80) and position restoration from GameManager (lines 84-98), add a new priority check: **before** falling back to the SceneBase `SpawnPoint`, check if `GameManager.target_spawn_point` was set by an ExitZone. If so, use that as the player's initial position instead:

```gdscript
# Inside _instantiate_player(), after add_child and after
# the existing GameManager position-restore block (≈ line 98):

# Check for ExitZone-directed spawn point first
var gm := get_node_or_null("/root/GameManager")
if gm and "target_spawn_point" in gm:
    var zone_spawn = gm.get("target_spawn_point")
    if zone_spawn != null and zone_spawn is Vector3 and zone_spawn != Vector3.ZERO:
        _player.global_position = zone_spawn
        # Override the existing player_position read so fall reset matches
        if _player.has_method("set_fall_reset_position"):
            _player.set_fall_reset_position(zone_spawn)
    # Clear after reading so subsequent uses / non-zone transitions get correct fallback
    gm.set("target_spawn_point", Vector3.ZERO)
```

**Why this ordering?** The existing code already restores `GameManager.player_position` for position continuity. The `target_spawn_point` check should come **after** the continuity check and **before** the fall-reset, so that:
- Dialogue/homogeneous transitions: `player_position` continuity preserved (no `target_spawn_point` set)
- Zone transitions: `target_spawn_point` overrides any stale `player_position` from the previous scene

**B — Update `_get_player_spawn_position()` (optional enhancement)**

This method is currently used only for fall-reset position. With the change above, fall-reset is also set to `target_spawn_point`. No change needed — `_get_player_spawn_position()` continues to return the Marker3D SpawnPoint for non-zone-transition scenarios.

**C — Clear `GameManager.target_spawn_point` in `_exit_tree()`**

To prevent stale `target_spawn_point` values if `_instantiate_player()` isn't called (e.g., scene loads but player isn't spawned for some reason), add a cleanup in `_save_player_state()`:

```gdscript
func _save_player_state() -> void:
    # ... existing code ...
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm and "target_spawn_point" in gm:
        gm.set("target_spawn_point", Vector3.ZERO)
```

### 2.4 Modified: `gdscripts/game_manager.gd` — Add `target_spawn_point` property

**Current state:** 148 lines. Autoload. Stores `player_position`, `player_rotation`, `player_head_rotation`, `transition_in_progress`, etc.

**Add one new declared property** near the existing position properties (after line 27):

```gdscript
# Player spawn point set by ExitZone for zone-to-zone transitions (Issue #156)
var target_spawn_point: Vector3 = Vector3.ZERO
```

**Why declare it instead of using dynamic dispatch?** Declaring the property makes it visible in the inspector, enables type-safe access, and prevents potential issues with GDScript's dynamic property dispatch. The existing `transition_in_progress` was dynamic (not declared) in #148 due to the minimal-change constraint — for this issue, since we're already making multiple changes, a declared property is cleaner.

### 2.5 Scene Modifications (add ExitZone Area3D children)

Each scene gets one or more `ExitZone` Area3D children placed at doorways/boundaries.

#### Scene Flow Map (bidirectional connections)

```
office ↔ street ↔ convenience_store ↔ bridge ↔ underpass ↔ subway_station ↔ lobby
```

#### Detailed Zone Placement

| Scene | ExitZone Name | target_scene | spawn_point | Mode | Notes |
|-------|--------------|-------------|-------------|------|-------|
| `office.tscn` | `ExitZoneToStreet` | `res://scenes/street/street.tscn` | Street-side office door position | AUTO | Player walks out office door |
| `street.tscn` | `ExitZoneToOffice` | `res://scenes/office/office.tscn` | Office interior spawn position | AUTO | Player walks toward office door from street |
| `street.tscn` | `ExitZoneToStore` | `res://scenes/store/convenience_store.tscn` | Store interior entrance position | AUTO | Player walks into store entrance |
| `convenience_store.tscn` | `ExitZoneToStreet` | `res://scenes/street/street.tscn` | Street store door position | AUTO | Player exits store |
| `convenience_store.tscn` | `ExitZoneToBridge` | `res://scenes/bridge/bridge.tscn` | Bridge entrance position | AUTO | Back exit of store → bridge |
| `bridge.tscn` | `ExitZoneToStore` | `res://scenes/store/convenience_store.tscn` | Store back-entrance position | AUTO | Bridge → store |
| `bridge.tscn` | `ExitZoneToUnderpass` | `res://scenes/underpass/underpass.tscn` | Underpass entrance position | AUTO | Bridge → underpass |
| `underpass.tscn` | `ExitZoneToBridge` | `res://scenes/bridge/bridge.tscn` | Bridge exit position | AUTO | Underpass → bridge |
| `underpass.tscn` | `ExitZoneToSubway` | `res://scenes/subway_station/subway_station.tscn` | Subway station entrance position | AUTO | Underpass → subway |
| `lobby.tscn` | `ExitZoneToSubway` | `res://scenes/subway_station/subway_station.tscn` | Subway station lobby-door position | AUTO | Lobby → subway |
| `subway_station.tscn` | `ExitZoneToUnderpass` | `res://scenes/underpass/underpass.tscn` | Underpass subway exit position | AUTO | Subway → underpass |
| `subway_station.tscn` | `ExitZoneToLobby` | `res://scenes/lobby/lobby.tscn` | Lobby entrance position | AUTO | Subway → lobby |

---

## 3. Data Flow

### Current (dialogue-only — unchanged)

```
Player clicks Area3D → dialogue panel opens
  → Player selects choice with {"scene": "res://..."}
    → SceneManager._on_choice_made(choice_index)
      → SceneManager.trigger_scene_change(target_scene)
        → GameManager.transition_in_progress = true
        → fade_out → change_scene_to_file → new scene loads
        → SceneManager._ready() reads GameManager.transition_in_progress
        → SceneBase._ready() → fade_in()
          → PlayerController instantiated at SpawnPoint Marker3D
```

### Proposed (walking transitions — new path in bold)

```
Player walks into ExitZone Area3D
  → ExitZone.body_entered
    → GameManager.transition_in_progress check — skip if already transitioning

    AUTO mode:
      → ExitZone._transition()
        → GameManager.target_spawn_point = zone.spawn_point    [NEW]
        → SceneManager.trigger_zone_transition(target_scene)
          → SceneManager.trigger_scene_change(target_scene)

    EKEY mode:
      → Show prompt Label3D: "Press E to enter"
      → Player presses E:
        → ExitZone._on_player_interact()
          → ExitZone._transition()
            → GameManager.target_spawn_point = zone.spawn_point    [NEW]
            → SceneManager.trigger_zone_transition(target_scene)
      → Player walks away:
        → ExitZone.body_exited → hide prompt, disconnect E-key

    [Both paths converge:]
    → GameManager.transition_in_progress = true
    → fade_out (0.5s)
    → change_scene_to_file(target_scene)
    → [Old scene destroyed, new scene loads]

    → SceneManager._ready()
      → _setup_fade_curtain()
      → read GameManager.transition_in_progress = true
    → SceneBase._ready()
      → SceneManager.fade_in()
        → play("fade_in") (0.5s)
        → await animation_finished
        → transition_in_progress = false
        → GameManager.transition_in_progress = false
      → _instantiate_player()
        → Restore GameManager.player_position for rotation/head
        → **Check GameManager.target_spawn_point FIRST**    [NEW]
          → If non-zero: use as player.global_position
          → If zero: fall through to SpawnPoint Marker3D
        → Clear GameManager.target_spawn_point
        → Set fall reset position
```

### Dialogue-zone coexistence

```
Dialogue trigger (Area3D + EKeyTrigger) at same location as ExitZone?
  → If both present: ExitZone with EKEY mode takes E-key priority
  → Player can still click the dialogue Area3D for lore interaction
  → Dialogue choice with {"scene": ...} still triggers scene change
  → Dialogue path does NOT set target_spawn_point → player spawns at SpawnPoint
```

---

## 4. Component Interaction

### Autoload Dependency Graph

```
GameManager (autoload)
  ├── transition_in_progress: bool         [read/write by SceneManager]
  ├── target_spawn_point: Vector3 [NEW]    [write by ExitZone, read by SceneBase]
  ├── player_position: Vector3             [write by SceneBase, read by SceneBase]
  └── player_rotation: Vector3             [write by SceneBase, read by SceneBase]

SceneManager (per-scene)
  ├── trigger_scene_change(target)         [dialogue path]
  ├── trigger_zone_transition(target) [NEW] [zone path ← calls trigger_scene_change]
  └── fade_in()                            [called by SceneBase._ready()]

ExitZone (per-zone, Area3D) [NEW]
  ├── Reads: GameManager.transition_in_progress (guard)
  ├── Writes: GameManager.target_spawn_point
  └── Calls: SceneManager.trigger_zone_transition()

SceneBase (per-scene script)
  ├── Reads: GameManager.target_spawn_point [NEW — in _instantiate_player()]
  ├── Reads: GameManager.player_position / player_rotation
  ├── Writes: GameManager.player_position / player_rotation (in _exit_tree)
  └── Clears: GameManager.target_spawn_point [NEW — after use]
```

### Scene Tree Layout (per scene, after modification)

```
[Scene Root] (Node3D)
  ├── SpawnPoint (Marker3D)
  ├── SceneManager (Node)
  ├── ExitZoneToNextScene (Area3D) [NEW]
  │     ├── CollisionShape3D (BoxShape3D)
  │     └── PromptLabel (Label3D) — optional
  ├── FadeCurtain (CanvasLayer) — existing
  │     ├── ColorRect
  │     └── AnimationPlayer
  ├── CanvasLayer
  │     └── DialoguePanel
  └── ... (scene-specific nodes: buildings, NPCs, environmental text)
```

---

## 5. Verification & Test Descriptions

> **Design principle:** Plan phase writes test descriptions only. Runnable test files are generated by the implement agent from these descriptions.

### Test File: `tests/unit/test_exit_zone.gd` (unit) + `tests/integration/test_scene_zones.gd` (integration)

#### Test Categories

| Prefix | Category | Description |
|--------|----------|-------------|
| TC-EZ-N | Normal Path | Basic zone transition cases |
| TC-EZ-E | Edge Cases | Boundary conditions and unusual scenarios |
| TC-EZ-F | Failure Paths | Error handling and graceful degradation |

---

### TC-EZ-N: Normal Path (Zone Transitions Work)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EZ-N-1 | AUTO mode — player walks into zone | Create ExitZone with `transition_mode=AUTO`, `target_scene="res://scenes/street/street.tscn"`, `spawn_point=Vector3(2,0,3)`. Mock player enters collision zone. | `ExitZone._on_body_entered(player)` triggers `_transition()`. `GameManager.target_spawn_point` set to `Vector3(2,0,3)`. SceneManager's `trigger_zone_transition()` is called. | Assert `GameManager.get("target_spawn_point") == Vector3(2,0,3)`. Assert `trigger_zone_transition` was called (mock). |
| TC-EZ-N-2 | EKEY mode — player enters, presses E, transitions | Create ExitZone with `transition_mode=EKEY`, `prompt_text="Press E to enter"`. Mock player enters zone → prompt shows. Player emits `interaction_requested` → transition fires. | Prompt visible while player inside. On E press: `_transition()` fires, sets `target_spawn_point`, calls `trigger_zone_transition()`. | Assert `_transition()` called. Assert prompt was visible before E, hidden after. |
| TC-EZ-N-3 | EKEY mode — player enters, walks away, no transition | Same EKEY zone. Player enters → prompt shows. Player exits zone → `body_exited` fires. | Prompt hidden. No `_transition()` call. Player's `interaction_requested` signal disconnected. | Assert prompt hidden. Assert `_transition()` NOT called. Assert signal disconnected. |
| TC-EZ-N-4 | Player appears at `target_spawn_point` after zone transition | Mock a full zone transition: set `GameManager.target_spawn_point=Vector3(5,0,2)`, then call `SceneBase._instantiate_player()`. | `_player.global_position` is `Vector3(5,0,2)` (not `SpawnPoint` Marker3D, not `GameManager.player_position`). | Assert `_player.global_position == Vector3(5,0,2)`. Assert `target_spawn_point` cleared after use (`== Vector3.ZERO`). |
| TC-EZ-N-5 | Dialogue transition still works without target_spawn_point | Dialogue choice triggers `trigger_scene_change("res://...")`. `GameManager.target_spawn_point` is ZERO. SceneBase spawns player. | Player appears at scene's `SpawnPoint` Marker3D (or `Vector3.ZERO` if missing). No interference from stale `target_spawn_point`. | Assert player spawned at `SpawnPoint` position, not at some leftover `target_spawn_point`. |
| TC-EZ-N-6 | Bidirectional zones: A→B and B→A both work | ExitZone on scene A targets scene B. ExitZone on scene B targets scene A. Simulate A→B transition, then B→A. | Both transitions complete. Player position is correct in each direction (A's spawn point when returning to A). | Assert correct spawn position per direction. Assert no stale directional data. |

### TC-EZ-E: Edge Cases

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EZ-E-1 | Double body_entered (player stands inside zone) | ExitZone with `transition_mode=AUTO`. Player stays inside zone after entry. `body_entered` fires again (physics edge case). | Guard checks `transition_in_progress` and cooldown timer. Second `_transition()` is suppressed. | Assert `_transition()` called exactly once. Timer prevents second trigger. |
| TC-EZ-E-2 | Player spawns inside an ExitZone (zone too large) | Scene loads with player already inside an ExitZone `CollisionShape3D`. `body_entered` fires in `_ready()`. | ExitZone's `_ready()` should skip detection for 0.5s (defer `monitoring=true)` or check `transition_in_progress` (true during fade-in). No spurious transition. | Assert no immediate transition. Player can walk out and re-enter to trigger normally. |
| TC-EZ-E-3 | Two overlapping ExitZones, player enters both | Two ExitZones placed adjacently. Player walks through overlap zone. Both `body_entered` fire. | First zone's `_transition()` sets `transition_in_progress=true`. Second zone's `body_entered` checks guard → silently ignored. | Assert only one transition fires. Assert no error/crash from second zone. |
| TC-EZ-E-4 | Rapid zone re-entry during fade-out | Player enters zone A → fade-out starts → player walks back (scene still loaded during fade). | `transition_in_progress` guard prevents re-trigger. Fade-out completes and scene changes as intended. | Assert no double-transition. Assert original destination scene loads. |
| TC-EZ-E-5 | AUTO mode with 1-second cooldown active | Player enters zone → auto-trigger fires → cooldown starts. Player walks out and back in within 1 second. | Cooldown timer is still running. `body_entered` fires again but `_transition()` returns due to cooldown check. | Assert only one `_transition()` in total. After 1 second, re-entry works again. |
| TC-EZ-E-6 | Dialogue triggered while player stands in an ExitZone | Player enters EKEY ExitZone → prompt shows. Player clicks a separate Area3D → dialogue panel opens → choice triggers scene change. | Zone's `transition_in_progress` guard (from `trigger_scene_change()`) prevents double-trigger. Dialogue transition proceeds normally. | Assert dialogue transition completes. Assert zone prompt hides during transition. |

### TC-EZ-F: Failure Paths

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EZ-F-1 | ExitZone with empty `target_scene` | Create ExitZone with `target_scene=""`. Player enters zone. | `_transition()` checks `target_scene.is_empty()` → returns early. `push_warning` logged. No scene change. | Assert no transition attempted. Assert warning emitted. |
| TC-EZ-F-2 | ExitZone with invalid `target_scene` path | Create ExitZone with `target_scene="res://nonexistent.tscn"`. Auto-mode trigger. | `SceneManager.trigger_scene_change()` receives invalid path. `change_scene_to_file()` returns `ERR_FILE_NOT_FOUND`. Error logged. `transition_in_progress` cleared. Current scene persists. | Assert `change_scene_to_file` returned non-OK. Assert `transition_in_progress=false`. Assert scene unchanged. |
| TC-EZ-F-3 | ExitZone without CollisionShape3D child | Create ExitZone node with no `CollisionShape3D` child. | `_ready()` checks `has_node("CollisionShape3D")` → `push_warning` logged. `body_entered` never fires (no collision shape). No crash. | Assert warning logged. Assert no crash. Assert `_on_body_entered` never called. |
| TC-EZ-F-4 | GameManager unavailable (headless test) | ExitZone in isolated tree without `/root/GameManager`. Player enters zone. | `get_node_or_null("/root/GameManager")` returns `null`. `_transition()` skips setting `target_spawn_point`. Still calls `trigger_zone_transition()`. | Assert no crash. Assert transition proceeds (spawn defaults to SpawnPoint). |
| TC-EZ-F-5 | SceneManager unavailable on parent | ExitZone's parent has no `SceneManager` child node. | `get_parent().get_node_or_null("SceneManager")` returns `null`. `push_error` logged. No scene change. | Assert error logged. Assert no crash. Assert no transition. |
| TC-EZ-F-6 | `target_spawn_point` stale after dialogue transition | Zone transition sets `target_spawn_point=Vector3(5,0,2)`. Next transition is dialogue-based (no spawn point). Player spawns in new scene. | Dialogue's `trigger_scene_change()` clears `target_spawn_point` at the start (see §2.2 change). SceneBase reads ZERO → falls back to SpawnPoint Marker3D. | Assert player appears at SpawnPoint, NOT at `(5,0,2)`. Assert `target_spawn_point` is ZERO after dialogue transition. |
| TC-EZ-F-7 | Two EKEY zones in same scene, player exits one, enters other | Player enters zone A (EKEY) → prompt shows A. Player walks to zone B (EKEY) → `body_exited` for A → `body_entered` for B. | A's prompt hidden, signal disconnected. B's prompt shown, signal connected. Player presses E → B's transition fires. | Assert only B's prompt visible. Assert only B's transition fires. Assert A's signal disconnected. |

### Manual / Integration Test Scenarios

| # | Scenario | Steps | Expected Behavior |
|---|----------|-------|-------------------|
| INT-ZONE-1 | Full traversal: office → street → store → street | Player walks office door → street → store entrance → store → store exit → street | Each transition has fade-out + fade-in. Player appears at correct spawn point per scene. |
| INT-ZONE-2 | Full traversal: street → bridge → underpass → subway | Street store's rear exit → bridge → underpass → subway | Transitions chain correctly. No scene gets stuck in `transition_in_progress` state. |
| INT-ZONE-3 | Dialogue transition then zone transition | Player triggers dialogue-based scene change (e.g., office → street), then walks to next exit zone. | Both transition types work sequentially. No stale `target_spawn_point` interference. |
| INT-ZONE-4 | Zone transition then dialogue choice with "scene" | Player zone-transitions to street, then selects a dialogue choice that triggers another scene change (e.g., to bridge). | Dialogue transition works after zone transition. `transition_in_progress` correctly guards each. |
| INT-ZONE-5 | Visual: fade curtain plays correctly on both AUTO and EKEY | Trigger both types of zone transition. | Both show smooth 0.5s fade-out → black → 0.5s fade-in. No visual glitches. |

### Test Double / Mock Strategy

For unit tests (headless, `extends RefCounted` with `run()`):

| Dependency | Mock Strategy |
|------------|--------------|
| `GameManager` | Create a plain `Node`, set `script = GameManagerScript`, add `target_spawn_point = Vector3.ZERO` property (or use `set("target_spawn_point", ...)`). Add to test scene tree as `/root/GameManager`. |
| `SceneManager` | Create a plain `Node`, set `script = SceneManagerScript`. Add as child of test scene root. |
| `PlayerController` | Use `_make_pc()` pattern from existing `test_e_key_trigger.gd` — create bare `Node` with `PlayerControllerScript`, add `Head`, `Camera3D`, `InteractionArea` children, add to `"player"` group. Add `interaction_requested` signal. |
| Scene tree | Use `Node.new()` as root, add ExitZone + mock SceneManager + mock GameManager as children. Use `add_child()` and manually call `_ready()` etc. |

---

## 6. Migration & Rollout

### Implement Order

1. **`gdscripts/exit_zone.gd`** — Create new class (≈90 lines)
2. **`gdscripts/game_manager.gd`** — Add `target_spawn_point: Vector3` property (1 line)
3. **`gdscripts/scene_manager.gd`** — Add `trigger_zone_transition()` + clear `target_spawn_point` in `trigger_scene_change()` (≈15 lines)
4. **`gdscripts/scene_base.gd`** — Read `target_spawn_point` in `_instantiate_player()`, clear in `_save_player_state()` (≈15 lines)
5. **All 7 scenes** — Add `ExitZone` Area3D children with configured properties
6. **`tests/unit/test_exit_zone.gd`** — Unit tests for ExitZone (headless)
7. **`tests/integration/test_scene_zones.gd`** — Integration tests with mocked scene transitions

### Rollback

Revert the commit. Dialogue-only transitions continue to work unchanged. No data migration needed.

### Scenes Needing SpawnPoint Verification

| Scene | Has SpawnPoint? | Notes |
|-------|----------------|-------|
| `office.tscn` | Unknown | NEEDS VERIFICATION by implement agent |
| `street.tscn` | Unknown | NEEDS VERIFICATION by implement agent |
| `convenience_store.tscn` | Unknown | NEEDS VERIFICATION by implement agent |
| `bridge.tscn` | Unknown | NEEDS VERIFICATION by implement agent |
| `underpass.tscn` | Unknown | NEEDS VERIFICATION by implement agent |
| `lobby.tscn` | Unknown | NEEDS VERIFICATION by implement agent |
| `subway_station.tscn` | Unknown | NEEDS VERIFICATION by implement agent |

The implement agent must verify each scene's `.tscn` file for an existing `SpawnPoint` Marker3D child and create one if missing.

---

## 7. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ExitZone double-trigger from physics edge cases (body_entered fires twice) | Low | Medium | `transition_in_progress` guard + timer cooldown. Both must pass for trigger. |
| Stale `target_spawn_point` leaks into dialogue transitions | Low | Medium | Cleared at start of `trigger_scene_change()`, cleared after use in `_instantiate_player()`, cleared in `_save_player_state()`. |
| Players spawn inside an ExitZone at scene load | Medium | Low | ExitZone defers monitoring 0.5s in `_ready()`; `transition_in_progress` guard prevents trigger during fade-in. |
| Zone shape misaligned with door geometry | Medium | Low | BoxShape3D (0.5m × 2m × 3m) is standard door size. Tune per scene during implementation. |
| `GameManager` dynamic property conflicts with existing uses | Very Low | Low | Declared `target_spawn_point` property avoids dynamic dispatch entirely. |
| EKEY zones conflict with existing `EKeyTrigger` on same door | Low | Low | ExitZone wraps E-key logic internally. If both present, ExitZone's EKEY mode takes priority. Separate Area3D for dialogue remains clickable. |

### Overall Risk: Low

The ExitZone pattern is directly modeled on the existing `EKeyTrigger` (31 lines, proven working). The `GameManager.target_spawn_point` pattern mirrors the `transition_in_progress` pattern from Issue #148 (also proven). SceneBase modification is ~15 lines with clear fallback logic. The largest risk is per-scene zone placement (geometry alignment), which requires scene-specific tuning.

---

## 8. Continuation Context

> Handoff for the implement agent.

### Files to Create

| File | Est. Lines | Description |
|------|-----------|-------------|
| `gdscripts/exit_zone.gd` | ~90 | ExitZone Area3D class |
| `tests/unit/test_exit_zone.gd` | ~150 | Unit tests for ExitZone |
| `tests/integration/test_scene_zones.gd` | ~100 | Integration tests for zone transitions |

### Files to Modify

| File | Change | Est. Lines Added |
|------|--------|-----------------|
| `gdscripts/game_manager.gd` | Add `target_spawn_point` property (after line 27) | 1 |
| `gdscripts/scene_manager.gd` | Add `trigger_zone_transition()` method + clear `target_spawn_point` in `trigger_scene_change()` | ~15 |
| `gdscripts/scene_base.gd` | Read `target_spawn_point` in `_instantiate_player()` after position restore; clear in `_save_player_state()` | ~15 |
| All 7 scene `.tscn` files | Add ExitZone Area3D children at doorways | ~10 per scene |

### Key Implementation Notes

1. **ExitZone extends Area3D, NOT Node3D** — Must extend Area3D to emit `body_entered`/`body_exited`. Do NOT extend Node3D.
2. **EKEY mode uses `interaction_requested` signal** — Follows the exact pattern from `EKeyTrigger.gd` lines 17-27: connect signal in `body_entered`, disconnect in `body_exited`.
3. **`signal_fired` test helper** — Use the same `var _signal_fired: bool = false` pattern from `test_e_key_trigger.gd` for testing `interaction_requested` connections.
4. **Do NOT remove existing dialogue transitions** — Both paths coexist. The dialogue path is the fallback if zone transitions are missing or broken.
5. **SpawnPoint Marker3D** — If a scene lacks a `SpawnPoint` child, create one at the intended player start position. `SceneBase._get_player_spawn_position()` reads it.
6. **BoxShape3D size** — Default `0.5 × 2 × 3` (width × height × depth). Depth should be thin (~0.5m) so the player passes through it quickly, preventing double `body_entered` on zone edges.
