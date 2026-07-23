# Research: Scene Transition System — Walking between areas

> Parent Issue: #156
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

Scene transitions in the game are currently **dialogue-only**: the player can only move between areas by selecting a dialogue choice that carries `"scene"` metadata (e.g., `{"scene": "res://scenes/street/street.tscn"}`). The flow is:

1. Player clicks an Area3D trigger (e.g., door) → dialogue panel opens
2. Dialogue branch has a choice with `"scene"` metadata
3. Player selects that choice → `SceneManager.trigger_scene_change()` fires
4. Fade-out → `change_scene_to_file()` → fade-in on destination scene

There is **no mechanism for the player to walk between areas** by physically moving the character (PlayerController with WASD) through a door, corridor, or zone boundary. The game has:

- **PlayerController** with WASD movement, mouse look, and E-key interaction (`gdscripts/player_controller.gd`)
- **EKeyTrigger** Area3D class (`gdscripts/e_key_trigger.gd`) — detects player proximity and emits `e_key_interacted` signal (used for NPC/door interaction)
- **SceneManager** for fade transitions (`gdscripts/scene_manager.gd`)
- **SceneBase** autoloads player position/rotation across transitions via `GameManager`
- **8 scenes** (office, street, convenience_store, bridge, underpass, lobby, subway_station) each with their own SceneManager and FadeCurtain

But **no exit/entry zones** exist in any scene. The player cannot walk to a door and press E to transition to the next scene. Scene transitions remain exclusively dialogue-driven.

### Expected Behavior

The player can **walk** between adjacent game areas by physically moving the character into an exit zone or pressing E at a boundary:

1. **Zone-based transitions** (primary): Player walks into an Area3D trigger zone (e.g., a doorway) → auto-triggers scene transition with current fade-in/fade-out
2. **E-key + proximity** (secondary): Player approaches a zone boundary, an optional prompt appears, player presses E to transition
3. **Dialogue-driven** (existing): The current dialogue-based scene transitions continue to work as before
4. **Spawn position is set per transition**: Each exit zone specifies the target scene AND the target spawn point position
5. **No manual spawn point placement needed per transition**: The destination scene uses a named Marker3D (`SpawnPoint`) that the exit zone references

All three mechanisms share the same SceneManager fade-out/fade-in pipeline.

### User Scenarios

- **Scenario A (Walking through a door):** Player is in the office, walks toward the door. The player's CharacterBody3D enters a DoorTrigger Area3D. A prompt reads "Press E to leave the office" appears (optional). Player presses E → fade-to-black → office unloads → street scene loads → player appears at the street-side spawn point → fade-in → player can walk around the street.
- **Scenario B (Auto-zone entry):** Player walks through an archway or doorframe into an auto-trigger zone. No E-key required — the zone detects the player and transitions automatically. Used for corridors, alleyways, underpass entrances.
- **Scenario C (Reverse direction):** Player on the street walks back toward the office door → enters reverse exit zone → transitions back to office → appears at the office interior spawn point. All position/rotation state is bidirectional.
- **Frequency:** Every scene transition in the game (~6+ per playthrough). The primary mode of navigation between areas.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

Scene transitions were originally implemented (Issue #55, #58) as **dialogue-only** because:

1. **Dialogue was the first interactive system** — Scene transitions were designed as dialogue choice outcomes because the dialogue engine was built first (Issue #46). Adding `"scene"` metadata to dialogue choices was the simplest path.
2. **No player controller existed** — The PlayerController (WASD movement + E-key interaction) was added later (Issue #142). Before that, the only input was mouse clicks on Area3D triggers.
3. **Proximity triggers add complexity** — Zone-based transitions require: (a) named Area3D exit zones per scene, (b) a mapping of exit zone → destination scene + spawn point, (c) bidirectional navigation, (d) E-key prompt UI, (e) guard against re-triggering during transition.

### Why Change Now?

1. **Player controller exists** — Issue #142 delivered WASD movement, mouse look, and E-key interaction. The player can physically walk around. The only missing piece is exit zones.
2. **Dialogue-only transitions are awkward** — The player must stop, click a trigger, navigate a dialogue tree, and select a choice just to leave a room. Walking through a door is more natural than clicking a door and reading dialogue each time.
3. **Scene transitions are the primary navigation** — The game is a series of connected city environments. The player should walk between them, not teleport via dialogue menu.
4. **Player position persistence works** — Issue #142 already saves/restores `player_position`, `player_rotation`, and `player_head_rotation` across `change_scene_to_file()` via `GameManager`.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Scene transitions | Fade-out (0.5s) → `change_scene_to_file()` → fade-in (0.5s). Must preserve this pipeline. |
| SceneManager | Per-scene instance, NOT autoload. `transition_in_progress` propagated via `GameManager` (Issue #148 fix). |
| Player persistence | Position/rotation saved in `GameManager` before `change_scene_to_file()`, restored in `SceneBase._instantiate_player()`. |
| Interaction system | E-key via `EKeyTrigger` Area3D — `body_entered`/`body_exited` → connect/disconnect `interaction_requested` signal. |
| Existing dialogue transitions | Must continue to work alongside walking transitions. Both call `SceneManager.trigger_scene_change()`. |
| Spawn points | Each scene has a `SpawnPoint` Marker3D child (or falls back to Vector3.ZERO). Currently only one per scene. |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/scene_manager.gd` | SceneManager | **Modified** — Add `trigger_zone_transition(scene_path, spawn_point, fade_duration)` — a new public method for zone-based transitions that sets both scene path AND target spawn point before calling the existing transition pipeline. |
| `gdscripts/scene_base.gd` | SceneBase | **Modified** — `_get_player_spawn_position()` should first check GameManager for `target_spawn_point` (set by the exit zone). Fall back to scene-local `SpawnPoint` Marker3D. |
| `gdscripts/game_manager.gd` | GameManager | **Modified** — Add `target_spawn_point: Vector3` property. Set by exit zone before transition. Read by SceneBase to position the player. |
| `gdscripts/exit_zone.gd` | Exit Zone Script | **New** — `extends Area3D` reusable class: configurable scene path, spawn point, transition mode (auto / E-key), optional HUD prompt. |
| `scenes/office/office.tscn` | Office Scene | **Modified** — Add `ExitZone` Area3D at the door boundary. Connect to `res://scenes/street/street.tscn`. |
| `scenes/street/street.tscn` | Street Scene | **Modified** — Add `ExitZone` Area3D at store entrance (→ `convenience_store.tscn`) and office door exit (→ `office.tscn`). |
| `scenes/store/convenience_store.tscn` | Store Scene | **Modified** — Add `ExitZone` Area3D at store entrance (→ `street.tscn`). |
| `scenes/bridge/bridge.tscn` | Bridge Scene | **Modified** — Add `ExitZone` Area3D at store exit (→ `store.tscn`) and underpass entrance (→ `underpass.tscn`). |
| `scenes/underpass/underpass.tscn` | Underpass Scene | **Modified** — Add `ExitZone` Area3D at bridge exit (→ `bridge.tscn`) and subway entrance (→ `subway_station.tscn`). |
| `scenes/lobby/lobby.tscn` | Lobby Scene | **Modified** — Add `ExitZone` Area3D at subway entrance (→ `subway_station.tscn`). |
| `scenes/subway_station/subway_station.tscn` | Subway Station | **Modified** — Add `ExitZone` Area3D at lobby entrance (→ `lobby.tscn`) and underpass exit (→ `underpass.tscn`). |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/e_key_trigger.gd` | EKeyTrigger | Existing EKeyTrigger pattern is the model for ExitZone — ExitZone can optionally extend or wrap similar logic. |
| `scenes/ui/exit_prompt.tscn` | Exit Prompt UI | **New** — Optional CanvasLayer label showing "Press E to enter" or walking arrow prompt (future). |
| `gdscripts/scene_manager.gd` | existing `_on_choice_made` | Must coexist with new `trigger_zone_transition()` — both call trigger_scene_change internally. |
| `docs/DESIGN/156-scene-transition-system.md` | DESIGN Doc | Must be created in Plan phase. |
| `tests/integration/test_scene_zones.gd` | Integration Tests | **New** — Test exit zone → scene transition → spawn position. |

### Data Flow Impact

**Current (dialogue-only):**
```
Player clicks Area3D → dialogue panel opens
  → Player selects choice with {"scene": "res://..."}
    → SceneManager._on_choice_made(choice_index)
      → SceneManager.trigger_scene_change(target_scene)
        → GameManager.set("transition_in_progress", true)
        → fade_out → change_scene_to_file → new scene loads
        → SceneManager._ready() reads GameManager.transition_in_progress
        → SceneBase._ready() → fade_in()
          → PlayerController instantiated at SpawnPoint
```

**Proposed (walking transitions coexist):**
```
Player walks into ExitZone Area3D
  → ExitZone.body_entered
    → (if auto-mode) → ExitZone.transition()
    → (if E-key mode) → show prompt, wait for E → ExitZone.transition()
      → GameManager.target_spawn_point = zone.spawn_point
      → SceneManager.trigger_zone_transition(target_scene, spawn_point)
        → fade_out → change_scene_to_file → new scene loads
        → SceneManager._ready() reads GameManager.transition_in_progress
        → SceneBase._ready() → fade_in()
          → SceneBase._instantiate_player()
            → Check GameManager.target_spawn_point FIRST
            → Fall back to scene-local SpawnPoint Marker3D
            → Clear GameManager.target_spawn_point
```

### Documents to Update

- [x] **This output:** `docs/PRD/156-scene-transition-system.md`
- [ ] `docs/DESIGN/156-scene-transition-system.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/` — May need updates for scene flow diagrams

---

## 4. Solution Comparison

### Approach A: ExitZone Area3D + SceneManager Extension

**Description:**

Create a reusable `ExitZone` class (`extends Area3D`) that detects player proximity and triggers a scene transition. Each exit zone has:
- `target_scene: String` — path to the destination `.tscn` file
- `spawn_point: Vector3` — where the player appears in the target scene (coordinate in target scene's local space)
- `transition_mode: int` — `AUTO` (instant on body_entered) or `EKEY` (player must press E)
- `prompt_enabled: bool` — show "Press E" label (only in EKEY mode)

SceneManager gets a new `trigger_zone_transition()` method that:
1. Saves `target_spawn_point` to `GameManager` (same pattern as `transition_in_progress`)
2. Calls the existing `trigger_scene_change()` (fade-out → change_scene_to_file → fade-in)

SceneBase's `_instantiate_player()` is updated to read `GameManager.target_spawn_point` before falling back to the scene's `SpawnPoint` Marker3D.

**ExitZone node structure:**
```
ExitZone (Area3D)
  ├── CollisionShape3D (BoxShape3D or CylinderShape3D)
  ├── ExitPrompt (Control / CanvasLayer) — optional label
  └── (No script on root — ExitZone.gd handles everything)
```

**Pros:**
- Reusable component — drop into any scene, configure 3-4 export properties
- Does not change the existing dialogue transition flow at all
- Both auto-mode and E-key mode share the same SceneManager pipeline
- Spawn point positioning is explicit per zone (precise player placement, no ambiguity)
- `GameManager.target_spawn_point` follows the same pattern as `transition_in_progress` (Issue #148)
- SceneBase only needs ~5 new lines of code to read the spawn point
- No new autoloads — everything uses existing `GameManager`

**Cons:**
- Needs spawn point coordinates hardcoded in each ExitZone (or use Marker3D name reference)
- E-key mode needs a reusable prompt UI (simple CanvasLayer label)
- Each existing scene needs manual editing to place ExitZone nodes
- Auto-mode may trigger re-entry if zone is large or player stands inside it (guard needed)
- Bidirectional zones (office door → street, street → office) need two separate ExitZones

**Risk:** 🟢 Low — Area3D detection, SceneManager fade, and GameManager persistence are all proven patterns. No new autoloads or engine-level changes. The ExitZone script is ~60 lines total.

**Effort:** Medium (~4-6 hours for script + scene modifications)

---

### Approach B: Dialogue-Free Transition via `_on_player_interaction` in SceneBase

**Description:**

Instead of a generic ExitZone class, extend the existing scene-specific scripts (e.g., `office.gd`, `street.gd`) to handle exit-zone interactions directly. Each scene extends `SceneBase` and overrides `_on_player_interaction()` to check if the interacted target is an exit/door and trigger a transition with hardcoded target scene + spawn point.

**No new ExitZone class** — reuse the existing `EKeyTrigger` Area3D for door interaction:

```
DoorTrigger (Area3D + EKeyTrigger child)
  → Player presses E near door
  → EKeyTrigger emits e_key_interacted
  → SceneBase._on_player_interaction() detects it's a door
  → Hardcoded if-else chain: if door_name == "office_exit": transition("street.tscn", ...)
  → SceneManager.trigger_scene_change()
```

**Pros:**
- No new class to maintain
- Each scene can have unique transition logic (e.g., special dialogue before leaving)
- Reuses existing `EKeyTrigger` — no new node types
- No spawn point coordination — each scene script knows its own exit points

**Cons:**
- **Does not support AUTO mode** — every transition requires E-key press
- Hardcoded exit logic in each scene script — duplicated code, hard to audit
- Adding a new exit means editing the scene's GDScript (not data-driven)
- No spawn point separation — each scene script must hardcode both source exit AND target spawn point
- Breaks the separation of concerns: scene scripts (dialogue/environment) also manage navigation maps
- Each subsequent scene (bridge, underpass, lobby, subway) needs its own exit logic duplicated
- No reusable pattern for new scenes added later

**Risk:** 🟡 Medium — Code duplication across 8 scenes is an anti-pattern. Adding auto-mode later would require rewriting all exits.

**Effort:** Medium (~4-5 hours for per-scene logic) — but doesn't scale to future scenes.

---

### Approach C: Autoload SceneRouter with Named Exit Registry

**Description:**

Create a `SceneRouter` autoload (or extend `GameManager`) that maintains a registry of named exits. Each exit is a data entry:
```gdscript
# SceneRouter.gd or GameManager extension
var exits: Dictionary = {
    "office_to_street": {"scene": "res://scenes/street/street.tscn", "spawn": Vector3(-2, 0, 3)},
    "street_to_office": {"scene": "res://scenes/office/office.tscn", "spawn": Vector3(0, 0, 1.5)},
    "street_to_store":  {"scene": "res://scenes/store/convenience_store.tscn", "spawn": Vector3(1, 0, 0)},
    # ... all bidirectional exits
}
```

Exit zones in scenes simply reference a named key by string, and `SceneRouter` resolves the target:
```gdscript
# ExitZone.gd
@export var exit_name: String = "office_to_street"
func _on_body_entered(body):
    var route = SceneRouter.resolve(exit_name)
    SceneManager.trigger_zone_transition(route.scene, route.spawn)
```

**Pros:**
- All routing data in one place — easy to audit and modify
- Exit zones are truly data-driven: just a name and a collision shape
- Route registry can be exported as JSON for level design tooling
- Future: scene flow visualizer could read the route registry
- No hardcoded spawn coordinates in scene instances

**Cons:**
- New autoload (or heavy GameManager extension) — adds singleton dependency
- SceneRouter couples the exit zone system to a global registry — less modular
- Route registry grows with every zone pair → maintenance burden for large maps
- `SceneRouter` doubles as a navigation graph — over-engineering for a linear/directed scene flow
- The autoload pattern adds coupling that Approach A avoids (GameManager already serves this role)
- Bidirectional routes need two entries, or a reverse-lookup convention

**Risk:** 🟡 Medium — New autoload is unnecessary for what is essentially a spawn-point-forwarding problem. Approach A's use of `GameManager` for spawn point is simpler.

**Effort:** Medium (~5-7 hours)

---

### Recommendation

→ **Approach A (ExitZone Area3D + SceneManager Extension)** because:

1. **Reusable, data-driven component** — ExitZone is a drop-in Area3D child with `target_scene` and `spawn_point` exports. Every scene gets the same behavior: add an ExitZone, set 3-4 properties, done.
2. **Reuses existing patterns** — `GameManager.target_spawn_point` follows the exact same pattern as `transition_in_progress` (Issue #148). SceneBase reads it the same way.
3. **Supports both AUTO and EKEY modes** — A single `transition_mode` enum on ExitZone determines whether the player auto-transitions or presses E. No other code changes.
4. **No new autoloads** — `GameManager` already persists state across scene changes. No `SceneRouter` singleton needed.
5. **Dialogue transitions still work** — The existing `_on_choice_made()` → `trigger_scene_change()` path is untouched. Both call the same fade pipeline.
6. **Scales to future scenes** — New scenes just add ExitZones. No per-scene script changes needed.
7. **Minimal SceneBase changes** — Just one check in `_instantiate_player()`: read `GameManager.target_spawn_point` first, fall back to `SpawnPoint` Marker3D.

**Key design decisions for Approach A:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| ExitZone detection | `Area3D.body_entered` | Simplest trigger. `body_entered` fires once per player entry, no continuous overlap checks needed. |
| Double-trigger guard | Check `transition_in_progress` | Same guard as `SceneManager.trigger_scene_change()`. If transition is already in progress, ignore zone entry. |
| Spawn point storage | `GameManager.target_spawn_point` | Same pattern as `transition_in_progress`. Cleared after use in `_instantiate_player()`. |
| E-key prompt | Optional Label3D child | ExitZone has optional export for prompt text. If non-empty, show prompt Label3D on body_entered, hide on body_exited. No additional UI system needed. |
| AUTO mode safety | 1-second cooldown on auto-trigger | Prevents re-trigger if player somehow doesn't leave the zone before collision re-entry. Timer starts `one_shot = true`. |
| Zone shape | BoxShape3D | Best for doorways and archways. Thin box (0.5m deep × 2m wide × 3m tall) aligned with the door frame. |

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Auto-zone transition:** Player walks into an ExitZone with `transition_mode = AUTO`. Zone detects body_entered → checks `transition_in_progress` → sets `GameManager.target_spawn_point` → calls `SceneManager.trigger_scene_change()` → fade-out (0.5s) → scene loads → fade-in (0.5s) → player appears at target spawn point.
2. **E-key zone transition:** Player walks into ExitZone with `transition_mode = EKEY`. Zone detects body_entered → shows prompt text (Label3D: "Press E to enter"). Player presses E → zone triggers `transition()` → same pipeline as auto-mode. Player walks away → prompt hides.
3. **Dialogue-driven transition (existing):** Player clicks a door Area3D → dialogue panel opens → selects choice with `"scene"` metadata → `SceneManager._on_choice_made()` → same pipeline. Player position reset to scene's default SpawnPoint (no `target_spawn_point` set).
4. **Bidirectional zone:** Office door ExitZone targets `street.tscn` with spawn at street-side door. Street door ExitZone targets `office.tscn` with spawn at office interior. Both work independently.
5. **Reverse direction:** Player enters street from office → walks to store → enters store ExitZone → transitions to store → walks back → store ExitZone → back to street. Position and rotation persist correctly.

### Edge Cases

1. **Rapid zone re-entry:** Player walks into a zone, transition starts, but player immediately walks back out during fade-out. The `transition_in_progress` guard on the exit zone prevents a second trigger. The fade-out completes and scene changes normally — player intended destination was correct.
2. **Player inside zone at scene load:** If a player spawns inside an ExitZone collision area (zone is too large or poorly placed), `body_entered` fires immediately on `_ready()`. **Mitigation:** ExitZone skips `body_entered` for the first 0.5s after scene load (use `_ready()` timer). Or check `transition_in_progress` (which is true during fade-in).
3. **Zone overlaps with another zone:** Two ExitZones placed near each other. Player enters both simultaneously. Both `body_entered` fire. The guard (`transition_in_progress`) ensures only the first trigger fires; the second is silently dropped.
4. **ExitZone at scene edge facing wall:** If the spawn point places the player inside a wall or floor, the player clips through or gets stuck. **Mitigation:** Spawn points must be placed in free space with CollisionShape3D above ground. Include a `validate_spawn_point()` check that adjusts upward if overlapping geometry.
5. **AUTO mode with player standing still in zone:** Player enters an auto-zone and stops. The 1-second cooldown timer fires once, then the zone is inactive until next `body_entered`. Player can walk out and back in to re-trigger. No continuous re-triggering.
6. **Dialogue-triggered transition while player is in a zone:** Player enters a dialogue (from a different Area3D) while standing inside an ExitZone. Dialogue choice triggers scene change. ExitZone should not interfere — guard on `transition_in_progress` is already true, so zone trigger is ignored.
7. **No SpawnPoint Marker3D in destination scene:** ExitZone's `spawn_point` is used directly. If not set, `GameManager.target_spawn_point` defaults to `Vector3.ZERO`. SceneBase also falls back to scene-local `SpawnPoint` Marker3D. Graceful degradation.

### Failure Paths

1. **ExitZone script error on initialization:** If `target_scene` is empty or invalid, `trigger_zone_transition` should log an error and not trigger. Fail-safe: guard `if target_scene.is_empty(): return`.
2. **GameManager unavailable (test mode):** `get_node_or_null(\"/root/GameManager\")` returns null. `target_spawn_point` is not set. SceneBase falls back to `SpawnPoint` Marker3D. Transition still works — just spawns at default position.
3. **`change_scene_to_file()` returns error:** Same error handling as existing `trigger_scene_change()` — error logged, `transition_in_progress = false`, current scene stays.
4. **Player exits zone during E-key prompt:** Player walks into EKEY zone → prompt shows → player walks away before pressing E → `body_exited` fires → prompt hides → no transition. Expected graceful behavior.
5. **ExitZone without CollisionShape3D:** `body_entered` never fires. No error, just no transition. **Mitigation:** Add a `_ready()` check: `if not $CollisionShape3D: push_warning(...)`.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| `GameManager` autoload (`/root/GameManager`) | Stable | Low |
| `SceneManager` (`gdscripts/scene_manager.gd`) — fade-out/fade-in pipeline | Stable | Low |
| `SceneBase` (`gdscripts/scene_base.gd`) — `_instantiate_player()` and `_get_player_spawn_position()` | Stable | Low |
| PlayerController (`gdscripts/player_controller.gd`) — WASD movement + E-key interaction | Stable | Low |
| `EKeyTrigger` (`gdscripts/e_key_trigger.gd`) — existing proximity interaction pattern | Stable | Low |
| Issue #148 — `transition_in_progress` propagation via GameManager | **Merged** | None |
| Issue #142 — Player position/rotation persistence across scene transitions | **Merged** | None |
| All 8 scenes with SceneManager and FadeCurtain | Stable | Low |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Scene flow map / mini-map showing connected areas | P3 |
| Auto-run transitions (walk-through archway without stopping) | P2 |
| Multi-door scenes (office has 2 exits to different areas) | P1 |
| Conditional exit zones (locked doors, state-gated areas) | P2 |
| Lore text near exit zones (e.g., "Underpass — beyond these stairs") | P3 |
| Exit zone animation (door opening, glow highlight) | P3 |

### Preparation Needed

- [ ] Confirm that `GameManager` supports dynamic property `target_spawn_point` (yes — same pattern as `transition_in_progress`)
- [ ] Verify that `SceneBase._instantiate_player()` reads `GameManager` AFTER `add_child(_player)` but BEFORE setting position
- [ ] Decide default exit zone shape: BoxShape3D (0.5m × 2m × 3m) — aligns with typical door/archway dimensions
- [ ] Define the 8 scene connections for the bidirectional routing table (office↔street, street↔store, store↔bridge, bridge↔underpass, underpass↔subway_station, subway_station↔lobby)
- [ ] Decide if exit zone prompt uses world-space Label3D or screen-space Control (recommend Label3D for diegetic consistency, placed above the zone)

---

## 7. Spike / Experiment (Optional — depth/standard only)

Not required for depth/standard. The ExitZone pattern is well-understood from `EKeyTrigger` and `Area3D.body_entered`. No uncertain engine behavior to resolve.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The Scene Transition System currently supports only **dialogue-driven** scene transitions via `SceneManager.trigger_scene_change()`. The player cannot walk between areas by physically moving the character through doors, archways, or zone boundaries.

**Key facts for the implementing agent:**

- **8 scenes** with SceneManager instances: `office`, `street`, `convenience_store`, `bridge`, `underpass`, `lobby`, `subway_station`, `main`
- **PlayerController** (`gdscripts/player_controller.gd`) has WASD movement, mouse look (first-person), E-key interaction via `EKeyTrigger` Area3D, and interaction proximity detection via `interaction_area` (Area3D child)
- **EKeyTrigger** (`gdscripts/e_key_trigger.gd`) is the proven pattern: `body_entered` → connect `interaction_requested` signal, `body_exited` → disconnect signal. 31 lines. Extends `Area3D`.
- **SceneManager** (`gdscripts/scene_manager.gd`) — 151 lines. `trigger_scene_change(target_scene, fade_duration)` at line 105. Calls `fade_out` (0.5s) → `change_scene_to_file()` → new scene's `SceneBase._ready()` calls `scene_manager.fade_in()`.
- **`transition_in_progress`** is propagated via `GameManager` (Issue #148 fix). Pattern: set in `trigger_scene_change()`, read in `SceneManager._ready()`, cleared in `fade_in()`.
- **Player position/rotation** persists across `change_scene_to_file()` via `GameManager.player_position`, `.player_rotation`, `.player_head_rotation`. Set in `SceneBase._exit_tree()`, read in `SceneBase._instantiate_player()`.
- **SpawnPoint** Marker3D is a convention: each scene has a `SpawnPoint` child node. Default is `Vector3.ZERO`. Read in `SceneBase._get_player_spawn_position()`.

**Proposed new files:**
1. **`gdscripts/exit_zone.gd`** — ~80 lines. `extends Area3D`. Export vars: `target_scene: String`, `spawn_point: Vector3`, `transition_mode: int (AUTO=0, EKEY=1)`, `prompt_text: String`. `body_entered` → connect player signal or auto-trigger. `body_exited` → disconnect signal or hide prompt. `_transition()` → save spawn to `GameManager` → call `SceneManager.trigger_scene_change()`.

**Modified files:**
1. **`gdscripts/scene_manager.gd`** — Add `trigger_zone_transition(scene_path, spawn_point, fade_duration)` method (~10 lines) that sets `GameManager.target_spawn_point` then calls `trigger_scene_change()`.
2. **`gdscripts/scene_base.gd`** — In `_instantiate_player()`, after `add_child()` and before reading `GameManager.player_position`, read `GameManager.target_spawn_point`. If non-zero, use it as the player's initial position instead of `SpawnPoint` Marker3D. Clear it after use (~5 new lines).
3. **`gdscripts/game_manager.gd`** — No code change needed. Dynamic property `target_spawn_point` is set via GDScript's dynamic dispatch on first write.

**Scenes to modify (add ExitZone Area3D child):**
- `office.tscn` — ExitZone at door → `street.tscn`, spawn at street office door
- `street.tscn` — ExitZone at store entrance → `convenience_store.tscn`, spawn at store entrance; ExitZone at office door → `office.tscn`, spawn at office interior
- `convenience_store.tscn` — ExitZone at store exit → `street.tscn` or `bridge.tscn`, spawn at street store door
- `bridge.tscn` — ExitZone at store exit → `store.tscn`; ExitZone at underpass → `underpass.tscn`
- `underpass.tscn` — ExitZone at bridge → `bridge.tscn`; ExitZone at subway → `subway_station.tscn`
- `lobby.tscn` — ExitZone at subway → `subway_station.tscn`
- `subway_station.tscn` — ExitZone at underpass → `underpass.tscn`; ExitZone at lobby → `lobby.tscn`

**Scene flow connections (bidirectional):**
```
office ↔ street ↔ convenience_store ↔ bridge ↔ underpass ↔ subway_station ↔ lobby
```

**Things to watch out for:**

1. **`Area3D.body_entered` vs `body_exited` ordering:** If the player spawns inside an ExitZone (zone too large), `body_entered` fires immediately. Use a 0.5-second `set_deferred("monitoring", false)` in `_ready()` then re-enable, or check `transition_in_progress` before firing.
2. **Double-firing in auto-mode:** `body_entered` fires once per physics collision. If the player walks through a thin zone, they exit and re-enter the collision shape on the other side — this counts as a new `body_entered`. Use `transition_in_progress` guard to prevent double-trigger.
3. **E-key zone vs dialogue zone conflict:** If a door has both an `EKeyTrigger` (for lore dialogue) and an `ExitZone` (for transition), the player pressing E near the door should prefer one over the other. **Recommendation:** If both are present, EKEY-mode ExitZone should take priority (player can still interact with the door via mouse click for dialogue).
4. **Spawn point vs scene layout mismatch:** If `exit_zone.spawn_point` is in a different coordinate space than the target scene expects (e.g., zone specifies world-space but target scene has a rotated root), the player appears at the wrong location. **Fix:** spawn_point should be in the target scene's local coordinate space. SceneBase reads it directly as `player.global_position = target_spawn_point`.
5. **`GameManager.target_spawn_point` stale value:** If a previous transition set `target_spawn_point` but a dialogue-driven transition triggers next (no spawn point set), `_instantiate_player()` reads the stale value and places the player at the old spawn point. **Fix:** clear `target_spawn_point` in `trigger_scene_change()` AND in `_instantiate_player()` after use.
