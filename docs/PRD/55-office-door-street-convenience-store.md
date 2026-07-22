# Research: [Scene] Office Door → Street → Convenience Store

> Parent Issue: #55
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

The project currently contains only a single scene (`scenes/main.tscn`) with a bare Node3D, a Label3D displaying "Hope: 100  Despair: 0", a Camera3D, and the Dialogue UI overlay. There is:

- **No scene transition mechanism** — the game has never attempted to move between environments.
- **No environment scenes** — no office interior, no street, no convenience store.
- **No NPC placement** — the bartender dialogue (dialogues/bartender.json) exists as authored JSON but has no associated scene or NPC node.
- **No environmental text** — the LoFiText3D system (`gdscripts/lo_fi_text_3d.gd`, `shaders/lo_fi_text.gdshader`) is fully implemented (pixelation, color depth, scanlines, emissive glow) and has a test scene (`scenes/test_3d_text.tscn`) but is not used in the main game scene.
- **No rain or worldview integration with a specific scene** — RainController and WorldviewController are wired to StateSystem via signals but have no visual representation in a 3D environment.
- **Dialogue engine** (DialogueRunner, DialogueParser, DialogueConditionEvaluator) is fully implemented and tested, with one sample dialogue file (`dialogues/bartender.json`) triggered by F9.

In summary: all the *infrastructure* for a playable scene sequence exists (dialogue engine, state system, LoFi text rendering), but none of it is assembled into a coherent player experience. The player cannot move, cannot interact with any environment, and cannot see the office, street, or store.

### Expected Behavior

The player can:

1. **Start in an office interior** — see the desk, window, door. The window shows a rainy street at night via an environmental text component (LoFiText3D).
2. **Leave the office through a dialogue choice** — interact with the office door → dialogue prompt → scene transitions to street.
3. **Walk along the rainy street** — see street signs, neon signs, hear/see rain. Environmental text (neon, graffiti, shop signs) reflects the player's hope/despair state (WorldviewController integration).
4. **Enter the convenience store** — approach the store entrance → dialogue or proximity trigger → scene transitions to store interior.
5. **Interact with the convenience store clerk** — trigger a branched dialogue (3+ branches) that references choices the player made earlier (state-aware condition evaluation).
6. **Environmental texts foreshadow the Stranger** — the office window text, a street sign, and the store neon all contain oblique references to an NPC known as "the Stranger" whose full encounter is deferred to a later issue.

### User Scenarios

- **Scenario A (First-time player):** Player launches the game, sees the office with its dim desk lamp and rain-streaked window. The window text reads "Another night. Another deadline." (low hope variant) or "The city glitters through the rain." (high hope variant). Player clicks the door, gets a dialogue: "Leave the office?" → Yes/No. Yes → fade/transition to street. Player walks (via teleport or click-to-move) to the convenience store entrance. Enters → clerk dialogue fires: "You look tired." (if hope < 4) or "Welcome back." (if hope >= 4). After dialogue, player can browse (placeholder) or leave.
- **Scenario B (Replay/seeded run):** Player with high conviction sees different neon text ("YOU'RE STILL HERE" shifts from dim red to glowing amber). Street sign phrase changes. Clerk's dialogue includes "You seem different tonight." conditioned on `conviction >= 7`.
- **Scenario C (Developer/designer):** Wants to verify scene transitions with dialogue-based triggers. Needs to test that `DialogueRunner.enter_node("door_leave")` fires a scene change signal, and that the new scene's environment text reads the current GameState.
- **Frequency:** Every playthrough starts with this sequence. It is the game's first impression and tutorial-equivalent.

---

## 2. Design Intent (Feature)

### Why Does Current Behavior Exist?

The project was built in layered issues following the architecture model:
1. **Issues #1, #6, #43** — Project scaffold: Godot project, GameState autoload, 3D scene, input handling.
2. **Issue #42** — Theme-Mechanic Mapping: designed the conceptual bridge between narrative themes and game systems.
3. **Issue #46** — Dialogue Engine: built the data model, parser, condition evaluator, and runner.
4. **Issue #44** — LoFi 3D Text Rendering: built the shader system for environmental text.

Each layer was designed and implemented independently (and for #46, the dialogue engine was actually implemented before the scene sequence issue because it is a foundational dependency). Issue #55 is the *integration* issue — it assembles the parts into a playable experience for the first time.

### Why Change Now?

- All foundational systems (state, dialogue, LoFi text, rain, worldview) are implemented and tested.
- The dialogue engine (key dependency #46 for office door → convenience store transition) is merged with working tests.
- The project has no playable content at all — this is the first issue that produces something a human can actually interact with.
- Finding integration issues (scene transitions, state persistence across scenes, dialogue-triggered scene changes) early prevents cascading problems in later environment-heavy issues.
- The Stranger foreshadowing (AC3 requirement) must be seeded now; retrofitting foreshadowing later would require rewriting environmental text.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| Scene format | TSCN (Godot text scene format) |
| State system | Tri-axis: hope, conviction, will (0-10, 5=neutral) via `state_system.gd` |  
| Dialogue format | JSON-based, loaded by DialogueParser |  
| Visual style | Edward Hopper urban night — dark (#1a1a2e sky), warm amber light, lo-fi pixel text |
| Writing style | Hemingway — short lines, iceberg theory, ≤25 words per line |
| LoFi text | Label3D + custom shader (pixelation, color depth, scanlines, emissive glow) |
| Main scene | `scenes/main.tscn` — must remain the entry point; new scenes are loaded from it |
| Dialogue engine | Signals-based: `dialogue_started`, `dialogue_ended`, `node_changed`, `choices_available`, `choice_made` |
| Autoloads | GameManager (`game_manager.gd`), GameState (`game_state.gd`) — state persists across scene changes |
| Autoload state | `game_manager.gd` has skeleton `get_slider`/`set_flag` methods; `state_system.gd` is manually instanced, not autoloaded |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `scenes/office/office.tscn` | Office Scene | **New** — office interior with desk, window, door, lighting |
| `scenes/street/street.tscn` | Street Scene | **New** — rainy street segment with signs, store entrance |
| `scenes/store/convenience_store.tscn` | Store Scene | **New** — convenience store interior with clerk NPC |
| `gdscripts/scene_manager.gd` | Scene Manager | **New** — handles scene transitions (dialogue trigger → scene switch) with fade/to signal |
| `dialogues/office_door.json` | Door Dialogue | **New** — "Leave the office?" branching dialogue |
| `dialogues/store_clerk.json` | Clerk Dialogue | **New** — 3+-branch clerk dialogue referencing earlier choices |
| `dialogues/environmental_text.json` | Environmental Text | **New** — per-scene environmental text templates keyed by state |
| `scenes/main.tscn` | Main Scene | **Modified** — add SceneManager node, potentially restructure for scene loading |
| `gdscripts/main.gd` | Main Script | **Modified** — add scene transition signal handlers |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/rain_controller.gd` | Rain Controller | Street scene needs visual rain; may need to spawn particle systems |
| `gdscripts/worldview_controller.gd` | Worldview Controller | Environmental text needs tone selection at scene load |
| `gdscripts/lo_fi_text_3d.gd` | LoFi Text | May need API for programmatic text updates from state signal |
| `gdscripts/dialogue_runner.gd` | Dialogue Runner | May need a `scene_transition_requested` signal if dialogue choices trigger scene changes |
| `tests/` | Test Suite | Scene transition tests, dialogue → scene integration tests |
| `docs/DESIGN/55-office-door-street-convenience-store.md` | DESIGN Doc | Plan phase output |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | GDD | Update with dialogue integration patterns |

### Data Flow Impact

```
Player in Office Scene
    │
    ├──► Read GameState (hope, conviction, will) at scene load
    │       └──► WorldviewController → environmental text tone variant
    │       └──► RainController → rain intensity (for street scene)
    │
    ├──► Player approaches door → input prompt → DialogueRunner.start("office_door.json")
    │       └──► Dialogue condition evaluation against current state
    │       └──► Player selects "Leave" → choice_made signal
    │       └──► SceneManager receives signal → fade-out → change_scene_to_file("street.tscn")
    │
    ├──► Street Scene loads → GameState read again
    │       └──► Environmental texts (neon, street sign) get tone-filtered text
    │       └──► Rain intensity set based on conviction
    │       └──► Player moves to store entrance → dialogue or proximity trigger
    │
    └──► Store Scene loads → clerk dialogue triggers
            └──► Dialogue condition references choices_made from office_door.json
            └──► Clerk has 3+ branches based on hope/conviction + office door choice
            └──► Environmental text (neon "OPEN" sign) foreshadows Stranger
```

### Documents to Update

- [x] **This output:** `docs/PRD/55-office-door-street-convenience-store.md`
- [ ] `docs/DESIGN/55-office-door-street-convenience-store.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Add dialogue→scene transition pattern
- [ ] `docs/GAME_DESIGN/INDEX.md` — Update index
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md` — Update core loop to include scene sequence

---

## 4. Solution Comparison

> At least 2 approaches required (depth/deep label).

### Approach A: Godot `change_scene_to_file()` with SceneManager Orchestrator

**Description:**

Use Godot's built-in `SceneTree.change_scene_to_file(path)` for clean scene transitions. A new `SceneManager.gd` (Node, not autoload) lives in the current scene and acts as orchestrator:

- Holds references to trigger zones (Area3D nodes for proximity) and dialogue triggers.
- On dialogue choice that requests scene change, it calls `change_scene_to_file()`.
- State is preserved via autoloads (GameManager, GameState) — values persist across scene swaps because autoloads are not scene children.
- `_ready()` in each scene reads autoload state to configure environmental text, rain, lighting.
- Scene transition uses a CanvasLayer fade-out curtain (AnimationPlayer playing modulate to black, then change scene, then fade-in).
- Each scene is a standalone `.tscn` with its own environment, lighting, and trigger zones.

**Pros:**
- Godot-native — simple, well-documented, proven at small scale.
- Clean scene separation — each scene loads independently, no scene tree bloat.
- State persistence via autoload is free (GameManager and GameState are already autoloads).
- Fade curtain is easy to implement as a CanvasLayer with AnimationPlayer.
- Each scene can have its own WorldEnvironment (night street vs warm store lighting).
- Dialogue signals cross scenes naturally since DialogueRunner is in the scene being replaced.

**Cons:**
- Loses the previous scene's state *within* that scene (NPC positions, open doors, etc.) unless saved to autoload.
- Fade-to-black breaks immersion between back-to-back transitions (but is thematically appropriate for the game's noir style).
- DialogueRunner instance is destroyed and recreated with each scene change — dialogue history (`choices_made` array in DialogueRunner) would be lost unless persisted to autoload.
- Each scene must rewire signal connections on `_ready()`.

**Risk:** Low — standard Godot pattern. The main risk is losing DialogueRunner's `choices_made` state across transitions, which can be mitigated by persisting to GameManager on each choice.

**Effort:** 3-4 weeks (3 scenes + scene manager + trigger zones + dialogue content + fade transition + environmental text integration + tests)

---

### Approach B: Sub-Scene Loading with Persistent Root Scene

**Description:**

Keep `scenes/main.tscn` as a persistent root. Instead of swapping entire scenes, load environment sub-scenes as children of the root Node3D:

- Main scene has a `EnvironmentContainer` Node3D child.
- On scene transition, unload current environment (`remove_child()`, free resources), load new environment as child of `EnvironmentContainer`.
- Camera, UI, DialogueRunner, and SceneManager all remain in the root scene and are never destroyed.
- `DialogueRunner.choices_made` persists naturally because the Runner is never freed.
- Environmental text, rain particles, and lighting are within the sub-scene and are swapped.
- A small "loading" sub-scene or fade-to-black plays during the unload→load sequence.

**Pros:**
- Dialogue engine state (choices_made, visited_nodes) persists across scene transitions without serialization.
- Camera remains at fixed position — no need to reposition per scene.
- UI overlays (dialogue panel, debug overlay) stay connected.
- Faster transitions — Godot doesn't need to unload and reload the entire root scene.
- Better for eventual non-linear navigation (player can return to office later).

**Cons:**
- Scene tree grows with each sub-scene if not properly freed — risk of memory leaks if `queue_free()` isn't called.
- Godot's editor workflow is less natural for sub-scenes — each environment is designed in isolation but tested inside root.
- Lighting and WorldEnvironment may conflict (WorldEnvironment is per-viewport, not per-sub-scene).
- Each environment's WorldEnvironment would need to be managed through the persistent root's WorldEnvironment.
- More complex asset management — must ensure textures/meshes are properly freed.
- Trigger zones and Area3D nodes must be inside sub-scenes and discovered via signals or tree walking.

**Risk:** Medium — sub-scene management is doable but requires careful memory management. The WorldEnvironment conflict is a real concern: if the street scene has a dark WorldEnvironment and the store has a warm one, you can't have both as children of the same viewport simultaneously (only the first WorldEnvironment applies). Mitigation: use a single WorldEnvironment in the root and swap environment resources.

**Effort:** 4-5 weeks (scene manager with sub-scene lifecycle + 3 environments + dialogue integration + WorldEnvironment management + tests)

---

### Approach C: Hybrid — Single Root Scene with Environment State Machine

**Description:**

All three environments (office, street, store) exist as preloaded sub-scenes attached to a single root scene, but only one is visible at a time. The SceneManager acts as a state machine:

- Three Node3D children of root, each containing one environment.
- `visible` property toggled (visible environment shown, others hidden).
- Camera and lighting switches via environment-specific camera positions or `current` camera toggles.
- Dialogue engine persists across all environments.
- Environmental text is updated via WorldviewController signals (already implemented).
- Transitions use a CanvasLayer fade + `modulate` fade on the environment's root node.
- Input handling switches per environment (e.g., door interaction prompt only in office, store entrance only on street).

**Pros:**
- Zero scene load time — all environments loaded at game start.
- Dialogue engine state preserved perfectly.
- Camera transitions can be animated (e.g., camera moves from office desk to street through the door).
- Easy to add "look back" feature (player sees office from street, store from street).
- Most flexible for environmental storytelling (rain from street scene can affect office window texture).

**Cons:**
- Game load time and memory footprint are higher (3 environments loaded simultaneously).
- Godot's editor UX for 3 parallel environments in one scene is poor (cluttered scene tree, unintuitive to edit).
- Lighting and environment setup conflict (single WorldEnvironment, single DirectionalLight) — must manage per-environment lighting through scripts.
- Not suitable for large environments; fine for the small, focused environments in this game.
- Risk of accumulating visual glitches if many nodes are visible-toggled.
- Environment children still exist in the tree and process physics — potential performance waste if not using `process_mode` to pause inactive environments.

**Risk:** Medium-High — works best for small, contained environments (which this game has), but the editor UX friction and lighting management overhead are real. Mitigation: use `process_mode = PROCESS_MODE_DISABLED` on hidden environments.

**Effort:** 3-4 weeks (state machine + 3 environments + camera management + lighting scripts + transitions + tests)

---

### Approach D: Camera-as-Player — Slide Trigger Zones with Point-and-Click Movement

**Description:**

Build on Approach A or C but add a click-to-move mechanism:

- The player doesn't walk with WASD. Instead, the camera is static per scene and the player clicks/selects points of interest (door, street segment, store entrance).
- Each point of interest is an Area3D that responds to click/accept input.
- Moving from office door to street triggers a dialogue choice ("Step outside?") and then scene transition.
- Moving along the street uses a set of waypoints (click destination → camera slides along spline to new vantage point).
- Entering the store triggers the clerk dialogue directly.
- This approach matches the game's "interactive fiction with 3D environments" design direction (closer to Disco Elysium's style).

**Pros:**
- No player controller needed — dramatically simplifies movement code.
- Aligns with the game's CRPG/interactive novel design.
- Dialogue-as-movement naturally fits the existing dialogue engine.
- Each "position" is a fixed camera angle (matching Hopper's composed frames aesthetic).
- Ideal for environmental text readability (player always at the right distance to read signs).
- Reduced QA surface — no collision detection, no navigation mesh, no pathfinding.

**Cons:**
- Player expectation may be full movement — needs clear visual affordances (highlight interactables).
- Less player agency than free movement.
- Must design interesting "camera positions" (at least 3-4 per scene) to avoid static feeling.
- Scene transitions must be frequent if each camera position is a separate sub-scene.
- Point-and-click needs clickable UI elements that work across scences.

**Risk:** Low-Medium — fits the design direction but may feel limiting. Mitigation: make interaction points glow/highlight with LoFi emissive effect.

**Effort:** 4-5 weeks (point-and-click system + waypoint navigation + 3 environments + dialogue integration + camera positions + tests)

---

### Recommendation

**→ Approach A (Godot `change_scene_to_file()` with SceneManager Orchestrator)**, with the following refinements drawn from other approaches:

1. **Dialogue persistence:** Before each scene transition, serialize `DialogueRunner.choices_made` to `GameManager.custom_data` (a new Dictionary property on the autoload). On scene load, if the DialogueRunner finds persisted data, it restores it. This solves the state-loss problem of naive `change_scene_to_file()`.

2. **Camera-as-player (Approach D insight):** Use fixed camera positions per scene rather than free movement. Each scene has 2-4 interaction points the player clicks. This avoids the complexity of a full CharacterBody3D controller and matches the game's composed-frame aesthetic.

3. **Fade transitions (Approach A):** Use CanvasLayer fade-to-black (0.5s), then scene change, then fade-in (0.5s). The fade is thematically appropriate for the noir/Hopper mood.

**Why not Approach B or C?**
- Approach B (sub-scene) creates WorldEnvironment conflicts and memory management overhead for no clear benefit at this project scale (3 small scenes).
- Approach C (all-loaded) wastes memory and has poor editor UX for what is fundamentally a sequential experience — the player doesn't need all 3 environments at once.
- Approach D is combined into A's interaction model rather than taken as-is, because scene `change_scene_to_file()` is more natural for the design tooling.

**Why Approach A fits:**
- Three scenes × ~5 dialogue files × 3 environment text components = small enough for clean `change_scene_to_file()`.
- Autoload-based state persistence is already working (GameManager, GameState persist across scenes).
- The dialogue engine's `choice_made` signal can be intercepted by SceneManager to trigger scene changes.
- Adding a small persistence layer for `choices_made` is simple (append to an array in GameManager, nothing more complex than saving to a file).
- Each scene can be independently tested in the Godot editor by opening its `.tscn` directly.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **AC1 (Shallow): Player can move from office to store through dialogue choices.**
   - Game starts → Office scene loads → Office environmental texts display (window text shows rain-streaked night).
   - Player sees office door → clicks/interacts → Dialogue prompt: "Leave the office?" with choices ["Step outside", "Stay a while longer"].
   - Player selects "Step outside" → fade-out → Street scene loads → fade-in.
   - Street environmental texts display (neon sign "BAR", street sign "ELM ST.", graffiti).
   - Player sees convenience store entrance → clicks/interacts → Dialogue or proximity trigger: "Enter the convenience store?" → ["Go in", "Keep walking"].
   - Player selects "Go in" → fade-out → Store scene loads → fade-in.
   - Store environmental text displays (neon "OPEN" sign, shelf labels).
   - Scene sequence complete. Transition is smooth, no crashes, dialogue choices correctly trigger scene changes.

2. **AC2 (Middle): Clerk NPC has 3 dialogue branches referencing earlier choices.**
   - Store scene loads → clerk NPC node present → DialogueRunner.start("store_clerk.json").
   - Entry node: clerk greets. Choices displayed depend on `hope` value:
     - `hope >= 7`: "You look... actually okay tonight." (upbeat branch)
     - `hope >= 4 and hope < 7`: "Evening. The usual?" (neutral branch)
     - `hope < 4`: "Rough night? You look tired." (concern branch)
   - Within each branch, further choices reference whether the player left the office quickly (from `choices_made` in office_door dialogue):
     - If player chose "Step outside" immediately (no hesitation): "At least you got out early."
     - If player had to "Stay a while longer" first: "Glad you made it out. Staying in too long isn't good."
   - Branching continues for at least 3 dialogue node traversals before reaching a terminal node.
   - All conditions are evaluated against actual GameState via DialogueConditionEvaluator.
   - Returning to store scene with different state values shows different branches.

3. **AC3 (Deep): Environmental texts reflect state and foreshadow the Stranger.**
   - **Office window text** (LoFiText3D, Billboard mode, emissive glow):
     - `hope >= 7`: "The city glitters through the rain. Tonight could be different."
     - `hope >= 4 and hope < 7`: "Rain on the glass. Another night at the office."
     - `hope < 4`: "The streetlights blur. One more night. One more."
     - (All variants include a subtle connection: "⌈Somewhere out there, someone walks the same streets.⌋")
   - **Street neon sign** (LoFiText3D, Emissive mode, warm amber glow):
     - `conviction >= 7`: "YOU'RE STILL HERE" — warm amber, steady glow.
     - `conviction >= 4 and conviction < 7`: "YOU'RE STILL HERE" — dim amber, flickering.
     - `conviction < 4`: "YOU'RE STILL HERE" — dim red, barely lit.
     - (The sign is the Stranger's callout — permanent fixture in all variants.)
   - **Store neon "OPEN" sign** (LoFiText3D, Emissive mode):
     - Always present. When the player has both `hope >= 5` and `conviction >= 4`, a subtitle flickers: "⌈He was here tonight.⌋" — a direct Stranger foreshadowing.
     - Otherwise the sign just says "OPEN" with no subtitle.
   - **Graffiti on street wall** (LoFiText3D, Flat Sign mode):
     - `hope >= 6`: "this too shall pass" — faded but legible.
     - `hope < 6`: "???" or "i was here" — partially scratched out.
   - All texts are updated on state change (WorldviewController signal) or at scene load time.

### Edge Cases

1. **State at boundaries:** If `hope = 0` or `hope = 10` exactly, the correct tone variant is selected (thresholds use >= and <, not strict equals for readability). Verified: WV controller uses `hope <= 3.0` / `hope >= 7.0`.

2. **All clerk choices gated:** If the player's state satisfies zero conditions for the current clerk node, the fallback (default: true choice) is used — same as existing dialogue engine behavior. If no default exists, conversation ends gracefully with "Customer shuffles away."

3. **Rapid scene switching:** Player triggers dialogue, selects "Leave" twice rapidly. Mitigation: SceneManager has a `transition_in_progress` flag that blocks new transitions during fade animation (0.5s per direction → 1s total lockout).

4. **Missing dialogue file for scene:** If office_door.json or store_clerk.json is missing or malformed, DialogueRunner returns false from `start()`, SceneManager logs error, and a fallback text appears: "The door doesn't budge." / "The clerk is busy."

5. **Scene load failure:** If the `.tscn` file is missing, `change_scene_to_file()` returns an error code. SceneManager catches this and shows an in-game error overlay. The GameManager persists the last known state to recover.

6. **LoFiText3D resources freed on scene change:** Since LoFiText3D instances are destroyed with each scene change, the material/shader must be reloaded. Mitigation: the shader is preloaded via `preload()` in lo_fi_text_3d.gd's `_setup_material()`, which works across scene changes because shaders are Resource-type objects cached by Godot.

7. **Multiple environmental texts updating simultaneously:** If hope changes while rain also changes, both WorldviewController (text tone) and RainController (rain intensity) fire simultaneously. Mitigation: use a short `await` debounce or process the state snapshot at scene load time rather than dynamically (AC3 texts update on load + on state change, but not mid-conversation).

### Failure Paths

1. **Dialogue file not found at runtime:** `DialogueRunner.start("office_door.json")` returns false. SceneManager catches the return value, logs error, and the office door stays interactable with a fallback: "The door is locked. (Dialogue not found)".

2. **Clerk dialogue file malformed:** Parser returns error on load. DialogueRunner's `load_dialogue()` logs the error. Store scene shows clerk standing silently — player can "examine" them for a fallback text: "The clerk is reading a magazine. They don't look up."

3. **Scene transition during active dialogue:** If a dialogue choice triggers a scene change while the dialogue panel is open, the scene change should close the panel first. Mitigation: SceneManager calls `dialogue_ended.emit()` before changing scene.

4. **GameState system not available:** If StateSystem isn't found at `/root/StateSystem`, environmental texts default to neutral/5 variants. Dialogue conditions evaluate against default values.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #52 — Dialogue Engine (parent #46) | ✅ Merged (PR #77) | **Low** — DialogueParser, DialogueRunner, ConditionEvaluator all implemented and tested |
| Issue #49 — State System (parent #42) | ✅ Merged | **Low** — Tri-axis state_system.gd exists with apply_choice, reset, signal |
| Issue #47 — Theme-Mechanic Mapping | ✅ Merged | **Low** — Mapping chain documented; environmental text patterns defined |
| Issue #53 — LoFi 3D Text Rendering (parent #44) | ✅ Merged (PR #75) | **Low** — lo_fi_text_3d.gd + shader exist; test scene works |
| Issue #43 — Project Scaffold | ✅ Merged (PR #74) | **Low** — main.tscn, GameManager, GameState autoload all functional |
| Godot 4.7.1 | Stable | **Low** — Engine features in use are stable |

**Dependency chain map:**
```
#42 Theme-Mechanic Mapping
  ├── #43 Project Scaffold (GameState, scenes)
  │     └── #44 LoFi 3D Text (shader, Label3D)
  ├── #46 Dialogue Engine (#52 parent)
  │     └── #53 Dialogue refinement
  └── #55 (this issue) ← integrates all above
```

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #57 — Stranger NPC encounter | **Critical** — AC3 foreshadowing must be seeded here; full Stranger scene depends on #55's street/store environments |
| Issue #58 — Rain particle visual system | **High** — Street scene needs visual rain; rain_controller.gd exists but has no particle system |
| Issue #59 — Game menu / title screen | Medium — Not blocked, but office scene could serve as title screen background |
| Issue #62 — Day/night clock visualization | Medium — ClockManager exists; visual integration with scenes comes after scene structure is stable |

### Preparation Needed

- [ ] **StateSystem autoload decision:** Currently `state_system.gd` is NOT an autoload — `main.gd` gets it via `get_node("/root/GameState")`. For persistence across scene changes, it must either be made an autoload or its state must be copied to GameManager. **Recommendation:** Add `StateSystem` to project.godot's `[autoload]` section.
- [ ] **SceneManager.gd definition:** Define the interface before building scenes:
  - `trigger_scene_change(target_scene_path: String, fade_duration: float = 0.5)`
  - `connect_dialogue_trigger(dialogue_file: String, scene_path_on_choice: String, choice_text: String)`
  - Signal: `scene_changed(scene_name: String)`
- [ ] **GameManager extension:** Add `choices_history: Array` to persist dialogue choices across scene transitions.
- [ ] **Three scene .tscn files** with basic geometry, camera position, lighting, trigger zones.
- [ ] **Three dialogue JSON files** (office_door.json, store_clerk.json, environmental_text_config.json).
- [ ] **Environmental text configuration**: Per-scene list of LoFiText3D node paths + the text variants they can display.

---

## 7. Spike / Experiment (Optional — depth/deep only)

### Question to Answer

**How does `change_scene_to_file()` interact with the DialogueRunner's state — specifically `choices_made`, `visited_nodes`, and `current_node`?**

This is the highest-risk uncertainty because it determines whether Approach A is viable or whether we need Approach B's sub-scene persistence.

### Method

1. Create a minimal test: a root scene with a DialogueRunner instance, load a small dialogue JSON, make one choice (which records to `choices_made`), then call `change_scene_to_file()` to a second scene.
2. In the second scene's `_ready()`, create a new DialogueRunner instance and check if the old `choices_made` can be restored.
3. Test three recovery strategies:
   - (a) No recovery — default empty state.
   - (b) Persist `choices_made` to a global (GameManager autoload) and restore on runner init.
   - (c) Use a shared Runner instance in an autoload that survives scene changes.
4. Run the test via Godot headless (`godot --headless --script tests/test_scene_transition.gd`).

### Result

*(To be determined via actual spike — this section describes the intended experiment.)*

**The two viable recovery strategies from the spike are expected to be:**

- **Strategy (b)** — Persist to autoload: The `DialogueRunner.choices_made` array is serialized into `GameManager.custom_data` before scene change, then on new DialogueRunner init, it reads `GameManager.custom_data` and repopulates `choices_made`. This matches existing patterns (GameManager is already an autoload). **Expected complexity:** ~10 lines in GameManager, ~5 lines in DialogueRunner's initialization.

- **Strategy (c)** — Shared autoload Runner: Move the DialogueRunner instance to an autoload script so it survives scene changes. The Runner is then retrieved via `get_node("/root/DialogueRunner")` from any scene. **Expected complexity:** ~5 lines in project.godot autoload config, but requires re-plumbing all signal connections since autoloads are on a different node path.

**Expected recommendation:** Strategy (b) — minimal change, preserves current architecture, doesn't require rewiring the main scene.

### Impact on Approach

The result will confirm or reject Approach A's viability. If strategy (b) works (choices_made survives scene transitions via autoload), Approach A stands. If it proves fragile (e.g., Resource objects don't serialize well), Approach B (sub-scene loading) becomes the fallback, which would increase effort from "3-4 weeks" to "4-5 weeks" and add WorldEnvironment complexity.

**Spike priority:** Run this spike **before** starting Plan phase. It directly affects the architecture choice for scene management.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The game currently has all foundational systems implemented and tested:
- **Dialogue Engine** (Runner, Parser, ConditionEvaluator) — signal-based, JSON-driven, with anti-loop protection and default choice fallback.
- **State System** (`state_system.gd`) — tri-axis (hope/conviction/will, 0-10, 5=neutral) with `apply_choice()` and `state_changed` signal.
- **LoFi Text Rendering** (`lo_fi_text_3d.gd` + shader) — Label3D with pixelation, color depth, scanlines, emissive glow.
- **Rain Controller** (`rain_controller.gd`) — conviction → rain intensity mapping with shelter threshold.
- **Worldview Controller** (`worldview_controller.gd`) — hope → tone mapping (despair/neutral/hope).
- **Clock Manager** (`clock_manager.gd`) — 90-day deadline tracker.
- **Main Scene** (`scenes/main.tscn`) — single entry scene with dialogue panel and debug overlay.
- **Autoloads** — `GameManager` (skeleton), `GameState` (legacy, deprecated in favor of state_system.gd but still the named autoload).

**Key decision for the Plan agent:** `state_system.gd` is referenced at `/root/StateSystem` by the dialogue engine and environmental controllers, but it is NOT an autoload — `main.gd` manually creates or references it. For the scene sequence to work across scene changes, StateSystem needs to be either:
1. Made an autoload (add to project.godot), OR
2. Its state persisted onto GameManager (which IS an autoload) before scene changes and restored on scene load.

**Recommendation: Make StateSystem an autoload.** It's the cleanest solution and aligns with the existing architecture pattern (GameManager and GameState are already autoloads).

**The proposed implementation order:**
1. Spike: test `change_scene_to_file()` + `choices_made` persistence (Section 7).
2. Make `state_system.gd` an autoload (or copy state to GameManager on scene transition).
3. Extend GameManager with `choices_history: Array` for dialogue persistence.
4. Implement SceneManager.gd with fade transition and dialogue→scene change plumbing.
5. Build three scenes in order: Office → Street → Convenience Store.
6. Author dialogue JSON: office_door.json, store_clerk.json.
7. Implement environmental text system (per-scene text configs keyed by state thresholds).
8. Wire everything together and test.

**The main risk** is the interaction between `change_scene_to_file()` and DialogueRunner state persistence — addressed by the spike. The secondary risk is designing environmental text that is expressive enough to foreshadow the Stranger without revealing too much (the Stranger encounter is a later issue).

**Key design decisions for the Plan agent:**
1. StateSystem autoload vs GameManager state copying (recommend autoload)
2. Scene geometry fidelity (minimal blocks or detailed meshes?)
3. Environmental text update timing (on scene load only, or dynamic via state_changed signal?)
4. Proximity triggers vs click-to-interact for door and store entrance
5. Whether to implement click-to-move (Approach D pattern) or simple teleport/waypoint jumps between scenes
