# Research: Player Controller — WASD/mouse/E Have Zero Response

> Parent Issue: #142
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The game loads and runs without errors, but there is **zero player interactivity beyond dialogue UI**.

- WASD / Arrow keys produce no movement or response
- Mouse movement does not rotate the camera
- Pressing E or Space does nothing (Space is mapped only to `dialogue_select`, gated by `_dialogue_active`)
- The only working input: F9 (toggle dialogue test), dialogue nav keys (PGUP/PGDN/Enter), digit keys 1–4 for choice selection, and `ui_up/down/left/right` debug inputs that manipulate StateSystem test sliders
- **Mouse clicks on Area3D triggers work** (e.g., clicking the door triggers `office_door` dialogue)

**Steps to reproduce:**
1. Launch the game — office scene renders with desk, walls, door, window text
2. Press W/A/S/D — nothing happens
3. Move mouse — camera stays fixed at `(0, 2, 5)`
4. Press E or Space — nothing happens
5. Click on the door Area3D — the door dialogue triggers (mouse click interaction works — but this is the ONLY way to interact)

### Expected Behavior (Per Issue Author)

The issue body requests:
- **Input Map actions:** `move_forward` (W/↑), `move_backward` (S/↓), `move_left` (A/←), `move_right` (D/→), `interact` (E/Space), `look_up/down/left/right` (mouse)
- **Player controller script:** `player_controller.gd` handling WASD movement (CharacterBody3D or direct Camera3D manipulation), mouse drag rotation, E/Space interaction
- **Camera follows player** instead of being fixed at `(0, 2, 5)`

### User Scenarios

- **Scenario A (Movement):** Player presses W to walk forward, S to back up, A/D to strafe. Character collides with geometry.
- **Scenario B (Mouse Look):** Player holds left mouse button or uses captured mouse to rotate the camera and look around.
- **Scenario C (Interaction):** Player approaches a door/NPC, sees an on-screen prompt, presses E — dialogue triggers.
- **Scenario D (Dialogue Navigation — Existing):** Player in dialogue mode uses PGUP/PGDN to navigate choices, Enter/Space to select, F9 to toggle.
- **Frequency:** Every frame, every input. This is the single largest missing feature — the game is unplayable as a game without it.

### Core Question

> **Does this game NEED free-movement WASD controls, given it's a dialogue-driven narrative CRPG?**

This PRD does not assume the answer. It explores both paths and lets the evidence decide.

---

## 2. Root Cause Analysis / Design Intent

### Why Does Current Behavior Exist?

1. **Development pipeline gap:** The project was built from 18+ issues covering scenes, dialogue, UI, audio, narrative, and game state — but a PlayerController was **never created**. The issue tracker jumped from project scaffold directly to narrative architecture, skipping the fundamental player movement mechanic.

2. **No CharacterBody3D in any scene:** `scenes/main.tscn` uses a standalone Camera3D with no parent relationship to a player body. All scene TSCN files similarly have no player body — only environment geometry (CSGBox3D), StaticBody3D colliders, and Area3D interaction triggers.

3. **No Input Map for movement:** `project.godot` defines only `toggle_debug`, `toggle_dialogue`, `dialogue_up/down/select/skip`, and `digit_1-4` — zero movement actions exist.

4. **Camera is static:** Camera3D in all scenes (office, lobby, street, etc.) is at a fixed position with no follow logic.

5. **Interaction model is mouse-click only:** Every scene script connects Area3D `input_event` signals checking `MOUSE_BUTTON_LEFT` — there is no proximity detection, no `body_entered`/`body_exited` pattern, no E-key pathway.

### Why Change Now?

The game runs but is functionally incomplete. Without a player controller:
- The NPCNode architecture's proximity detection (`body_entered` w/ `is_in_group("player")`) is dead code — no player body exists to enter its trigger zones
- Dialogue can only be triggered by clicking Area3D zones (works, but not the intended UX)
- Scene geometry serves no gameplay purpose — no collision matters
- The "walking through a rainy city at night" premise has no physical embodiment

### Previous Constraints — Architectural Intent Signals

The codebase **strongly signals that a player body was always intended**, even if never built:

| Evidence | Location | Signal |
|----------|----------|--------|
| `NPCNode._on_body_entered` checks `body.is_in_group("player")` | `npc_node.gd:89` | Proximity detection designed for a player body |
| `NPCNode._on_body_exited` unchecks `is_in_group("player")` | `npc_node.gd:95` | Exit tracking for proximity |
| `NPCNode` has `_player_nearby`, `_name_label`, `_prompt_label` | `npc_node.gd:33-35` | Labels designed to show/hide based on player proximity |
| `NPCNode` has `interaction_prompt_text = "⌈Talk⌋"` | `npc_node.gd:19` | E-key equivalent prompt |
| `NPCNode` uses `proximity_distance = 3.0` | `npc_node.gd:16` | CylinderRadius for proximity trigger zone |
| Scene scripts connect `Area3D.input_event` | `office.gd:16` | Click-to-interact (fallback, not primary path) |
| All interaction zones are `Area3D` (not just click triggers) | `office.tscn:126-132` | Area3D supports both `input_event` AND `body_entered` |
| No player group node exists anywhere | `project.godot` search | Evidence = absent player body |

**Verdict:** The architecture was designed for a player character body with proximity-based NPC interaction, with mouse-click interaction as a secondary debug/fallback path. The body was simply never built.

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `project.godot` | Input Map | **Add** — movement/interaction actions (`move_forward`, `move_backward`, `move_left`, `move_right`, `interact`, `look_up`, `look_down`, `look_left`, `look_right`) |
| `gdscripts/player_controller.gd` | **New Script** | **Create** — CharacterBody3D script with movement, mouse look, interaction detection |
| `scenes/main.tscn` | Entry Scene | **Modify** — Add CharacterBody3D, parent Camera3D to it, OR move Camera3D to scene-local PlayerController |
| All scene TSCN files | Scene Structure | **Modify** — Add PlayerController instance or spawn point Marker3D |
| All scene GDScripts | Scene Scripts | **Modify** — Add `body_entered`/`body_exited` handlers to Area3D triggers (additive to existing `input_event`) |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/npc_node.gd` | NPC Framework | Already checks `is_in_group("player")` — no change needed, but E-key path should be added alongside mouse-click |
| `gdscripts/scene_base.gd` | Scene Base | **Modify** — May need `_initialize_player()` method to instantiate PlayerController on scene load |
| `gdscripts/scene_manager.gd` | Scene Manager | Sequence: scene transitions destroy scene tree → player must be re-created |
| `gdscripts/main.gd` | Entry Script | May move `_load_starting_scene` logic or delegate player creation |
| All scene scripts (6) | Interaction Zones | Need `body_entered`/`body_exited` handlers for proximity prompts + E-key routing |
| `gdscripts/game_manager.gd` | Game Manager | May need player position/rotation persistence fields |

### Data Flow Impact

**Current (click-only) flow:**
```
Mouse click on Area3D → input_event → _on_trigger_input() → dialogue_runner.start()
```

**Proposed (proximity + E-key) flow:**
```
Player walks near Area3D → body_entered → show "⌈E⌋ Interact" prompt
  └→ Player presses E → PlayerController emits interaction_requested(area)
    └→ Scene script routes to dialogue_runner.start()

OR (backward compatible):
Mouse click on Area3D → input_event → _on_trigger_input() → dialogue_runner.start()
```

**There is no conflict: both paths coexist.** The click path stays unchanged. The proximity + E-key path is additive.

### Documents to Update

- [ ] `docs/DESIGN/142-player-controller.md` — Will be created in Plan phase
- [ ] `docs/GAME_DESIGN/03-GODOT-SETUP.md` — Update Input Map section (currently says "no custom input mappings needed")
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` — May need interaction model documentation

---

## 4. Solution Comparison

### Approach A: WASD Free-Movement + CharacterBody3D

**Description:** Add a `CharacterBody3D` with `PlayerController.gd` script. WASD controls movement via `move_and_slide()`. Mouse look rotates camera/player (captured mouse mode). E-key detects nearest `Area3D` interactable via `body_entered`/`body_exited` and triggers interaction. Player is instantiated per-scene by `SceneBase._ready()` (since `change_scene_to_file()` destroys the scene tree).

**Implementation sketch:**
```gdscript
# player_controller.gd
extends CharacterBody3D
class_name PlayerController

@export var walk_speed: float = 3.0
@export var mouse_sensitivity: float = 0.002
@onready var camera: Camera3D = $Camera3D

var _current_interactable: Area3D = null
var _dialogue_active: bool = false

func _ready() -> void:
    add_to_group("player")
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    velocity = direction * walk_speed
    move_and_slide()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera.rotate_x(-event.relative.y * mouse_sensitivity)
        camera.rotation.x = clamp(camera.rotation.x, -1.2, 1.2)
    if event.is_action_pressed("interact") and _current_interactable and not _dialogue_active:
        # Emit signal — scene script handles routing to dialogue_runner
        interaction_requested.emit(_current_interactable)

func _on_interactable_body_entered(body: Node) -> void:
    if body.is_in_group("interactable"):
        _current_interactable = body
        show_prompt(body)

func _on_interactable_body_exited(body: Node) -> void:
    if body == _current_interactable:
        _current_interactable = null
        hide_prompt()
```

**Pros:**
- Player can freely explore scene geometry at own pace
- Natural first-person immersion — matches the "walk through rainy city" premise
- NPCNode proximity detection works immediately (just needs `add_to_group("player")`)
- Collision prevents wall-clipping — physics feel adds weight
- Industry standard — no player confusion

**Cons:**
- **Scenes are tiny** — office is ~8x8m, store is compact. WASD in such small spaces feels claustrophobic or trivial
- **Cinematic framing is lost** — the current static camera at `(0, 2, 5)` creates a specific visual composition. Free camera breaks every composed shot
- **Camera repositioning per scene** — each scene currently has its own MainCamera position. Player camera must adapt or spawn at scene-specific points
- **Dialogue focus is diluted** — a dialogue-driven CRPG where you walk 3 meters to click a door feels like unnecessary movement
- **Mouse mode conflicts** — captured mouse means no cursor for UI interaction. Escape-uncapture cycle is friction
- **Scene transition complexity** — player must be re-created on every scene change
- Every scene TSCN needs a PlayerController node or spawn point Marker3D
- Dialogue input must block WASD during conversations

**Risk:** Medium. The biggest risk is the scene transition architecture — `change_scene_to_file()` destroys the entire scene tree. PlayerController must survive or be re-created each scene. The NPCNode architecture already anticipates a player body, so that integration is low-risk.

**Effort:** Medium-High (~4-6 hours for full integration across all 6 scenes)

### Approach B: Point-and-Click Movement (Classic Adventure RPG)

**Description:** Keep the static camera framing. Add mouse-based movement: click on the ground → player walks to that position (like Disco Elysium, classic point-and-click). The Camera3D stays put or does a subtle pan/follow. Interaction is still click-on-Area3D (existing pattern) with optional proximity prompts.

**Implementation sketch:**
```gdscript
# point_and_click_controller.gd
extends CharacterBody3D
class_name ClickController

@export var walk_speed: float = 3.0

var _target_position: Vector3
var _is_moving: bool = false

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if _current_interactable:
            return  # Let Area3D.input_event handle it
        var space_state := get_world_3d().direct_space_state
        var params := PhysicsRayQueryParameters3D.new()
        params.from = ...  # camera position
        params.to = ...    # camera + mouse direction * max_distance
        var result := space_state.intersect_ray(params)
        if result.has("position"):
            _target_position = result.position
            _is_moving = true

func _physics_process(delta: float) -> void:
    if _is_moving:
        var direction := (_target_position - global_position).normalized()
        direction.y = 0
        velocity = direction * walk_speed
        move_and_slide()
        if global_position.distance_to(_target_position) < 0.5:
            _is_moving = false
            velocity = Vector3.ZERO
```

**Pros:**
- **Preserves cinematic framing** — camera stays at composed angles per scene
- **Matches narrative CRPG genre** — Disco Elysium, classic adventure games
- **No mouse mode conflicts** — cursor stays visible for UI and dialogue
- **Natural with existing interaction model** — click to move, click to interact (no mode switching)
- **Works in small scenes** — no need to walk, just click what you want
- **No scene transition architecture changes required** — player can be simple
- **Dialogue does not need to block movement** — there's no continuous WASD that needs pausing

**Cons:**
- **More complex raycasting setup** — need ground plane detection, navigation mesh or collision-based pathfinding
- **Pathfinding needed** — can't just move in a straight line (obstacles). Need NavigationAgent3D or simple A-star
- **Not what the issue author asked for** — issue body explicitly requests WASD
- **Player movement feels indirect** — not as immediate as WASD
- **Ground click may conflict with Area3D click** — need to distinguish "click on ground" from "click on trigger"
- **No mouse look** — player can't freely look around (if that's desired)

**Risk:** Medium. The click-to-move approach is simpler architecturally but needs raycasting + simple pathfinding. Navigation3D setup adds dependency but is well-supported in Godot 4.

**Effort:** Medium (~3-4 hours for complete integration)

### Approach C: Click-to-Interact Only (No Movement — Current Design)

**Description:** The game has NO player movement. Keep the current static camera and click-to-interact model. Simply add the E-key as an alternative trigger for the nearest interactable zone. Add an interaction highlighter/prompt system for UX polish. No CharacterBody3D needed.

**Implementation sketch:**
```gdscript
# extend main.gd or create interact_manager.gd
func _input(event: InputEvent) -> void:
    if event.is_action_pressed("interact") and not _dialogue_active:
        # Find nearest Area3D interactable, raycast-center-of-screen approach
        _trigger_nearest_interactable()

func _trigger_nearest_interactable() -> void:
    var space_state := get_world_3d().direct_space_state
    var camera := get_viewport().get_camera_3d()
    var mouse_pos := get_viewport().get_mouse_position()
    var from := camera.project_ray_origin(mouse_pos)
    var to := from + camera.project_ray_normal(mouse_pos) * 10.0
    var query := PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    var result := space_state.intersect_ray(query)
    if result and result.collider is Area3D:
        # Route to the existing _on_*_trigger_input handler
        # Or: keep a map of {Area3D: Callable} for dispatch
```

**Pros:**
- **Zero architectural change** — everything stays as-is
- **Preserves all cinematic camera work**
- **No scene transition issues** — player doesn't need to persist
- **Works perfectly with existing interaction model** — E-key maps to same Area3D triggers
- **Smallest effort** — just E-key as alternative to mouse-click
- **Matches the game's design DNA** — dialogue-driven, atmospheric, contemplative

**Cons:**
- **Ignores the architecture's clear intent** — NPCNode proximity detection was designed for a moving player body
- **No physical embodiment** — the player is a disembodied "clicker" not a person in a world
- **Doesn't match issue author's requirements** — explicitly requests WASD + mouse look
- **Limited engagement** — player sits and clicks. No exploration, no walking through the rain
- **Cannot leverage NPCNode proximity features** — `_player_nearby`, `_name_label`, `_prompt_label` stay unused
- **Scene geometry serves no gameplay purpose** — walls, floors, obstacles are purely visual

**Risk:** Low. Minimal code change, zero architectural risk. But risks rejecting the issue's core requirement.

**Effort:** Low (~1 hour)

### Recommendation

→ **Approach A (WASD Free-Movement)** for the player controller core, **but with deliberate design constraints that respect the narrative genre.**

**Rationale:**

1. **Architecture proves intent:** The NPCNode system, with its `body_entered`/`body_exited` proximity detection, `is_in_group("player")` checks, `_player_nearby` states, and `proximity_distance` configuration, was designed for a moving player body. Ignoring this architectural intent is fighting the codebase.

2. **First-person, not third-person:** The camera should be at eye level (~1.6m), not the current `(0, 2, 5)`. The player IS the camera — no avatar rendering needed. This matches the "lo-fi text everywhere" aesthetic (the player sees text naturally as part of the environment).

3. **Movement speed tuned for narrative pacing:** Walk speed should be SLOW (~2-3 m/s) — not action-game fast. The goal is contemplative exploration, not speedrunning.

4. **Scene transition re-creation pattern:** PlayerController is instantiated by `SceneBase._ready()` on each scene load. A PackedScene reference is preloaded. Player position/rotation is stored in GameManager and restored. This avoids fighting `change_scene_to_file()`.

5. **Backward compatibility:** Existing mouse-click interactions continue to work identically. E-key interaction is additive.

6. **Dialogue-priority input:** When `_dialogue_active == true`, WASD movement pauses and E/Space routes to dialogue selection, not world interaction.

**Design constraints for narrative CRPG fit:**
- Walk speed: 2.5 m/s (leisurely pace, not run)
- Mouse look optional: default is click-and-drag, not captured mouse (preserves cursor for UI)
- Camera height: 1.6m (eye level), slight downward tilt (-5°)
- No crouch, no sprint, no jump — this is not an action game
- Interaction E-key has a short range (2m) — player must approach triggers
- Each scene has a defined spawn point (Marker3D) set by the scene script
- Transition between scenes uses fade + spawn, not continuous world

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Movement:** Player presses W → moves forward at 2.5 m/s relative to camera facing. S strafes backward, A/D strafe. Player releases key → smooth stop (no slippage).
2. **Mouse Look (optional):** Player holds left mouse button + drags → camera rotates left/right/up/down, clamped vertically (-60° to +60°).
3. **Interaction (E-key):** Player walks within 2m of door Area3D → `body_entered` fires → "⌈E⌋" prompt appears. Player presses E → dialogue starts. Player walks away → prompt disappears.
4. **Interaction (Click — Legacy):** Player clicks on door Area3D → existing `_on_trigger_input` fires → dialogue starts. No E-key needed.
5. **Scene Transition:** Player interacts with door → dialogue choice triggers scene change → fade-out → new scene loads → PlayerController instantiated at spawn point → fade-in.
6. **Dialogue Mode:** During dialogue (F9 triggered), WASD movement is paused. E/Space routes to dialogue selection. Interaction prompts disappear.
7. **NPC Proximity:** Player walks near NPC → NPCNode's `_on_body_entered` fires → `is_in_group("player")` is true → NPC name label + "⌈Talk⌋" prompt appear.
8. **Collision:** Player collides with StaticBody3D geometry. Player does not clip through walls. `move_and_slide()` handles physics.

### Edge Cases

1. **Multiple overlapping triggers:** Two Area3D zones overlap at the same point. E-key triggers the most recently entered zone (LIFO stack).
2. **Scene change during movement:** Player is moving when dialogue choice triggers scene change. Movement stops during fade. Player respawns at new scene's default position.
3. **Escape cursor release:** Player presses Escape during click-and-drag mouse look → cursor reappears, camera stops rotating. Player clicks in viewport → camera control returns.
4. **E-key during dialogue:** If `_dialogue_active == true`, PlayerController ignores `interact` action. Handled by dialogue input in main.gd.
5. **Rapid E-tapping:** Player mashes E near an interactable — only ONE interaction fires per trigger entry. Debounce via `_current_interactable` null check or cooldown.
6. **Player falls off world:** No floor collision in a scene → player falls → `move_and_slide()` keeps falling → reset to spawn point with a warning.
7. **Player spawns inside geometry:** Respawn collision resolution — `move_and_slide()` pushes player out. Spawn points should be clear of walls.
8. **No interactable nearby:** Player presses E in empty space → nothing happens (silent). No error or feedback.
9. **Mouse sensitivity extremes:** Player moves mouse very fast → rotation is clamped per-frame. Very slow → smooth incremental rotation. Sensitivity configurable via exported variable.

### Failure Paths

1. **Input Map missing:** If `project.godot` lacks movement actions, `Input.get_vector()` returns `Vector2.ZERO` silently — player can't move. No error is raised. **Must verify via automated check.**
2. **PlayerController not instantiated:** If `SceneBase._ready()` fails to instantiate PlayerController, the scene loads without a player body. Game is playable via mouse-click only (degraded mode).
3. **Collision layer mismatch:** Player on layer 1, scene geometry on layer 2 → player clips through walls. **Convention: all environment physics bodies on layer 1, player on layer 1, raycasts on mask 1.**
4. **Camera duplicate conflict:** Scene-local MainCamera (from office.tscn, etc.) and player Camera3D both have `current = true` → Godot picks the last one set, may flicker. **Solution: Scene-local cameras use `current = false`. Only player Camera3D is `current = true`.**
5. **NPCNode mouse-only fallback:** If player controller breaks, NPCNode still works via mouse-click (`input_event` path). Degraded but functional.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Existing scene geometry with StaticBody3D colliders | ✅ Complete (office, street, lobby have floors/walls) | Low — collision shapes exist |
| Existing Area3D interaction triggers (door, NPC, exit) | ✅ Complete | Low — `body_entered` is additive |
| NPCNode proximity system | ✅ Complete | Low — `is_in_group("player")` check ready |
| SceneBase abstract class | ✅ Complete | Low — hook point for player instantiation |
| SceneManager fade transitions | ✅ Complete | Low — works independent of player |
| GameManager state persistence | ✅ Complete | Low — can store player position |

### Blocks

| Future Work | Priority |
|-------------|----------|
| NPC interaction via E-key (enhancement of NPCNode) | P1 |
| First-person camera refinements (head bob, view bobbing) | P2 |
| Player footstep audio (Linked to Issue #48 Sound System) | P2 |
| Ambient interaction prompts (glowing outline on interactables) | P3 |

### Preparation Needed

- [ ] **Convention decision:** Define player collision layer (suggest: layer 1). Confirm all scene geometry is on mask 1.
- [ ] **Scene audit:** Walk each scene file and verify all StaticBody3D have CollisionShape3D children. Office ✅, others need check.
- [ ] **Spawn point convention:** Decide on Marker3D naming (`SpawnPoint`, `PlayerSpawn`) or use per-scene `_get_player_spawn()` override in scene script.
- [ ] **Input action names:** Finalize names before adding to `project.godot`. Suggestion: `move_forward`, `move_backward`, `move_left`, `move_right`, `interact` (E only — Space conflicts with `dialogue_select`).
- [ ] **Mouse mode:** Decide between captured mouse (immersive, but cursor lost for UI) vs click-and-drag (cursor stays, less immersive but more practical for CRPG). **Recommendation: click-and-drag for default, with Shift+Escape toggle for captured mode.**

---

## 7. Spike / Experiment (depth/deep — 3 experiments mandatory)

### Experiment 1: Scene Transition Survivability — Can PlayerController Survive change_scene_to_file()?

**Question:** `get_tree().change_scene_to_file()` replaces the entire current scene tree. Can a PlayerController instantiated by `SceneBase._ready()` work cleanly across all 6 scene transitions?

**Method:**
1. Create a minimal `player_controller.gd` with a simple `Node3D` (not CharacterBody3D yet) that logs its lifecycle: `_ready()`, `_exit_tree()`, `_enter_tree()`.
2. Add to office.tscn as a child of OfficeRoot. Run the game. Verify it logs `_ready()`.
3. Trigger a dialogue → scene transition to lobby.tscn. Verify lobby logs work.
4. Check if the player node persists or is re-created. Verify no orphan nodes.
5. Repeat for all 6 scenes in sequence.

**Expected Result:** `change_scene_to_file()` destroys the OLD scene tree and creates a NEW one. The PlayerController is destroyed and must be re-created. `SceneBase._ready()` is the correct hook point — it fires on every scene load after `change_scene_to_file()` completes and before `fade_in()` completes.

**Impact:** Confirms Approach A's re-creation pattern. SceneBase._ready() must:
1. Preload PlayerController PackedScene
2. Instantiate it as child of scene root
3. Restore position from GameManager if available
4. Set Camera3D as `current = true` (scene-local cameras get `current = false`)

### Experiment 2: Scene Dimension Survey — Is WASD Practical in Current Scenes?

**Question:** The scenes are small blockouts (CSG boxes). Is there enough room for WASD movement, or would the player constantly bump into walls in a frustrating way?

**Method:**
1. Calculate bounding boxes for each scene by measuring CSGBox3D extents:
   - **Office:** Floor is 8×8m. Desk at (0, 0, -1), walls at z=-4 and z=+4, x=-4 to +4. Usable space ≈ 6×6m (desk takes center).
   - **Street:** Need to check (read full street.tscn). Likely longer than wide (street corridor).
   - **Lobby:** Check lobby.tscn for floor dimensions (appears compact).
   - **Underpass/Bridge/Store/Subway:** Need scene measurements.
2. At walk speed 2.5 m/s, crossing a 6m room takes ~2.4 seconds. Crossing a 15m corridor takes ~6 seconds.
3. Determine if this pacing feels natural for a narrative CRPG.

**Method (practical):**
```
cd /Users/devvi/workspace/agent-game-test
# Extract floor dimensions from each scene
grep -A2 "CSGBox3D" scenes/*/*.tscn | grep size
```

Search output analysis:
- **Office floor:** `Vector3(8, 0.2, 8)` — 8×8m
- **Street floor:** likely larger — need to check full street.tscn
- **Lobby floor:** check lobby.tscn (currently has no CSG geometry visible in header — uses Label3D triggers only)

**Expected Result:** Office and lobby are small (6-8m usable). Street is corridor-like (narrow but longer). Bridge is open. Underpass is tunnel (narrow). Subway station is medium. This is NOT a problem — **slow walk in small spaces is atmospheric**, not frustrating. Think "walking simulator" pacing, not "action game" pacing. The small size reinforces the claustrophobic/contemplative mood of the Edward Hopper night aesthetic.

**Impact:** WASD is practical. Small spaces enhance atmosphere. Walk speed should be 2-3 m/s. No sprint needed.

### Experiment 3: NPCNode Integration Test — Does PlayerController's is_in_group("player") Unlock Proximity Features?

**Question:** NPCNode has built `_on_body_entered` with `body.is_in_group("player")` and `_on_body_exited` with the same check. Currently, no node in the game belongs to the `"player"` group. Does adding a PlayerController with `add_to_group("player")` in its `_ready()` fully activate NPC proximity features without any additional NPCNode changes?

**Method:**
1. Add `add_to_group("player")` to PlayerController._ready().
2. Create a test scene with an NPCNode instance (from `scenes/components/NPC.tscn`) and a PlayerController.
3. Walk the player toward the NPCNode's Area3D trigger zone (radius = `proximity_distance` = 3.0m).
4. Verify: `_on_body_entered` fires → `_player_nearby = true` → name label and prompt label become visible.
5. Walk away → `_on_body_exited` fires → labels hide.
6. Click on the NPC → `_on_interaction` fires → `dialogue_runner.start()`.

**Expected Result:**
- `body.is_in_group("player")` on `_on_body_entered(body)` returns `true` ✅
- `_player_nearby` is correctly tracked ✅
- Name label and prompt label visibility works ✅
- Click interaction continues to work ✅
- E-key interaction (new) would need a separate signal or direct call — NPCNode currently only handles mouse-click. An `interact_via_e()` method or signal connection is needed for full E-key support.

**Impact:** NPCNode integration is 80% complete with just `add_to_group("player")`. The remaining 20% is adding an `interact_via_key()` method (or connecting PlayerController's `interaction_requested` signal) to call `evaluate_personality_layer()` and `dialogue_runner.start()` on E-key press. This is a small additive change to NPCNode.

**Recommendation from experiments:** Approach A is confirmed viable.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The player controller system currently has **zero implementation across the entire project**. The relevant existing systems are at the following states:

### Current State Summary

| System | State | Key Details |
|--------|-------|-------------|
| Input Map (`project.godot`) | Dialogue-only | No movement actions. Action names needed: `move_forward`, `move_backward`, `move_left`, `move_right`, `interact` |
| Player Controller | **Does not exist** | New file `gdscripts/player_controller.gd` extending `CharacterBody3D`. Handles: WASD movement, mouse look (click-and-drag), E-key interaction, Camera3D as child |
| Camera (main.tscn) | Fixed at `(0, 2, 5)` | Needs re-parenting as child of PlayerController. Scene-local cameras (office.tscn MainCamera) set to `current = false` |
| Interaction Zones | Mouse-click only | 6 scene scripts connect Area3D `input_event`. Additive change: add `body_entered`/`body_exited` handlers for proximity prompts + E-key |
| NPCNode | Proximity-ready | `is_in_group("player")` checks work. Needs additive `interact_via_key()` method for E-key support |
| Scene Transitions | Destructive | `change_scene_to_file()` destroys scene tree. PlayerController instantiated via `SceneBase._ready()` |
| Player Persistence | Not implemented | `GameManager` needs `player_spawn_position: Vector3` and `player_spawn_rotation: Vector3` fields |

### Architecture Decisions for Plan Phase

1. **PlayerController script:** Single GDScript `player_controller.gd` with `class_name PlayerController`, extending `CharacterBody3D`. Do NOT create a separate scene file — the script on a CharacterBody3D node is sufficient for MVP. A TSCN can be added later for visual polish.

2. **Camera:** `Camera3D` is a child of the PlayerController node, positioned at `Vector3(0, 1.6, 0)` (eye level). All scene-local cameras (MainCamera in office.tscn etc.) should have `current = false` — only the player camera is `current = true`.

3. **PlayerController instantiation:** `SceneBase._ready()` calls `_initialize_player()` which:
   ```
   var PlayerControllerScene := preload("res://scenes/player/player_controller.tscn")
   var player := PlayerControllerScene.instantiate()
   add_child(player)
   player.global_position = _get_spawn_point()
   ```
   Each scene script overrides `_get_spawn_point()` to return a `Vector3`.

4. **Player group:** `add_to_group("player")` in `PlayerController._ready()`.

5. **Interaction flow:**
   - `Area3D` zones get `body_entered`/`body_exited` connected to scene script
   - E-key check in `PlayerController._input()`: if `_current_interactable` and not `_dialogue_active`, emit `interaction_requested`
   - Scene script connects `interaction_requested` signal and routes to `dialogue_runner.start()`
   - Mouse-click `input_event` path remains unchanged

6. **Dialogue compatibility:** main.gd sets `_dialogue_active = true/false`. PlayerController watches this (via signal or direct reference) and pauses movement + ignores E-key during dialogue.

7. **Input Map additions:** Add to `project.godot`:
   - `move_forward` (W=87, ↑=4194320)
   - `move_backward` (S=83, ↓=4194321)
   - `move_left` (A=65, ←=4194322)
   - `move_right` (D=68, →=4194323)
   - `interact` (E=69 — NOT Space, which conflicts with `dialogue_select`=32)

### Main Risk

The **scene transition architecture** is the single biggest risk. `change_scene_to_file()` destroys the complete scene tree, including any PlayerController child. The `SceneBase._ready()` re-instantiation pattern must work reliably for all 6 scenes without race conditions with the fade animation. The `call_deferred()` pattern should be used for player instantiation to ensure the scene tree is fully constructed before adding the player.

**Secondary risk:** Collision layer consistency across all scenes. A systematic audit of every scene's collision layers/masks is needed before implementation.
