# Research: [Design] State-World Feedback — Hope/Despair Slider System

> Parent Issue: #50
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project has **two overlapping state systems** and a **stub GameManager**, with the narrative architecture now fully merged but lacking a unified hope/despair slider:

| System | File | Values | Range | Role |
|--------|------|--------|-------|------|
| `GameState` | `game_state.gd` | `hope`, `despair` | 0–100 each | Legacy autoload, prints on init |
| `StateSystem` | `state_system.gd` | `hope`, `conviction`, `will` | 0–10 each, 5=neutral | Tri-axis state manager, emits `state_changed`, NOT an autoload |
| `GameManager` | `game_manager.gd` | stub `get_slider()`, `apply_slider_delta()`, `set_flag()` | Returns `5.0` / `pass` / `false` | Autoload, intended but NOT wired to StateSystem |

**Problems with the current state:**

1. **Dual-system confusion** — `GameState` treats hope and despair as *independent* values (0–100 each, hope starts at 100, despair at 0). `StateSystem` treats hope as a *single bipolar axis* (0–10, 5=neutral). Neither is authoritative.

2. **No unified Hope/Despair slider** — There is no single authoritative slider representing the player's emotional state on a bipolar scale. The issue requires **one slider from -10 (despair) to +10 (hope)**.

3. **GameManager is still a stub** — `get_slider()` returns `5.0` for every axis. `apply_slider_delta()`, `set_flag()`, and `get_flags()` are `pass` / `false` stubs. The dialogue engine's `_build_state_snapshot()` queries GameManager for sliders but gets all `5.0`.

4. **WorldviewController uses 3 tones only** — Maps hope to `"despair"` / `"neutral"` / `"hope"` tones. Issue #50 requires **5 discrete states** for deeper granularity.

5. **NarrativeManager uses 3-state per-scene tones** — `_calculate_tone_for_scene()` maps each scene to 3 tones (e.g., office: `despair`/`neutral`/`hope`, lobby: `fear`/`neutral`/`defiant`). Echo variant calculation uses 3 variants. No 5-state system exists.

6. **No NPC attitude system** — NPC dialogue choices are statically authored. There is no system that adjusts NPC tone, willingness, or dialogue branch availability based on the player's hope/despair slider position. Dialogue JSON files define conditions manually per choice.

7. **No emotional pacing tooling** — The slider is not yet used as a pacing mechanism. There is no system that automatically modulates slider change rates, caps accumulation, or creates emotional "checkpoints."

8. **RainController maps conviction → rain** — Currently rain intensity is inversely proportional to conviction. For the hope/despair slider system, rain should be inversely proportional to hope (as specified in Issue #42's theme-mechanic mapping).

### Expected Behavior

A unified **Hope/Despair Slider System** that:

1. **Provides a single authoritative slider** — Range -10 (absolute despair) to +10 (boundless hope), with **5 discrete states** that map to player emotional tiers.

2. **Drives NPC attitude** — NPC dialogue branches, greeting tones, and availability of special dialogue options are gated by the slider state. Existing dialogue JSON files add `condition` fields referencing the new `hope_despair` axis.

3. **Drives environmental text** — Every scene object (window text in office, neon signs in street, graffiti in underpass, OPEN sign in store) has **at least 3 text variants** keyed to slider ranges. The 3-state tone system in `WorldviewController` and `NarrativeManager` is expanded to 5 states.

4. **Gates choices** — Dialogue choices reflect the player's internal state: some choices are *only visible* at certain slider ranges, some have *different outcomes* based on slider position, and some choices *change the slider itself*.

5. **Serves as an emotional pacing tool** — The slider changes at controlled rates, has "sticky" regions (harder to leave deep despair), and provides emotional checkpoints that gate narrative progression.

6. **Wires GameManager to StateSystem** — GameManager's `get_slider()` and `apply_slider_delta()` delegate to StateSystem, providing real data to the dialogue engine's `_build_state_snapshot()`.

7. **Re-maps RainController** — Rain intensity becomes inversely proportional to hope (instead of conviction), matching the design intent where the player's hope level affects how the world *feels*.

### User Scenarios

- **Scenario A (Player in despair, slider -10 to -5):** Player who made repeatedly self-destructive dialogue choices finds themselves in "Despair" state. Environmental text turns monochrome, rain intensity is max, NPCs speak curtly or with pity. Dialogue choices that require optimism are hidden. Special "glimmer of hope" choices appear but require high will to select.

- **Scenario B (Player neutral, slider -4 to +4):** Baseline state. Environmental text is neutral-faded. NPCs are polite but distant. All standard dialogue choices are available. This is the "reset" state after emotional checkpoints.

- **Scenario C (Player hopeful, slider +5 to +10):** Environmental text brightens, NPCs are warmer, special "compassion" or "insight" dialogue choices unlock. Hidden story fragments become accessible. Rain intensity drops.

- **Frequency:** Every state change affects every scene element. The slider changes multiple times per play session. The dialogue engine calls `_build_state_snapshot()` on every `enter_node()` call.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally through layered issues:

1. **Issue #43** — Project scaffold: `GameState` autoload with hope/despair (legacy).
2. **Issue #42** — Theme-Mechanic Mapping: designed tri-axis (hope, conviction, will) in `StateSystem`.
3. **Issue #46** — Dialogue Engine: built dialogue runner, parser, condition evaluator referencing `GameManager` stub.
4. **Issue #45** — Narrative Architecture: built `NarrativeManager`, scene scripts, echo system, all scene dialogues — but using 3-state tones because the slider system hadn't been designed yet.
5. **Issue #55** — Scene sequence: built office/street/store with per-scene environmental text scripts.

Each layer was authored independently. The `GameManager` stub was a placeholder awaiting this issue (#50) to define the final design.

Now **Issue #45 is merged** (PR #96). The narrative architecture exists with 6 scenes, 7 dialogue files, echo system, and ending determination — all using 3-state tone mappings. This PRD must define how the existing narrative systems upgrade from 3-state to 5-state.

### Why Change Now?

- **Issue #45 (Narrative Architecture)** is merged — the narrative framework exists. This feedback loop is the missing core component that makes the world *feel responsive*.
- **Issue #56 (Story Content)** depends on this issue — the script writing phase needs the State-World Feedback design to author NPC attitudes, environmental text, and choice trees.
- The dialogue engine supports condition evaluation on sliders — but the slider values are all stubs. Without a real slider system, authored dialogue conditions can never fire.
- The scene scripts implement 3-variant environmental text per scene object, but the tone mapping is hardcoded in `worldview_controller.gd` and `narrative_manager.gd`. A 5-state design needs to update both.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| State architecture | Tri-axis: hope, conviction, will via `state_system.gd` |
| State range | 0–10 per axis, 5=neutral, clamped |
| Legacy system | `GameState` autoload (hope/despair 0–100) — must not break existing references |
| Autoloads | `GameManager` (stub), `GameState` (legacy), `NarrativeManager` — all persist across scene changes |
| Dialogue conditions | Supported ops: `gte`, `lte`, `gt`, `lt`, `eq` on slider axes |
| Current worldview tones | `"despair"` (hope ≤ 3), `"neutral"` (3 < hope < 7), `"hope"` (hope ≥ 7) |
| Current narrative tones | Per-scene 3-state mapping in `narrative_manager.gd._calculate_tone_for_scene()` |
| Scene scripts | Each scene's `_configure_environmental_text()` reads state at `_ready()` |
| Existing dialogues | 7 JSON files with condition-gated choices; most use slider conditions on hope/conviction/will |
| Writing style | Hemingway — short lines, iceberg theory, ≤25 words per line |
| Visual style | Edward Hopper urban night — dark (#1a1a2e sky), warm amber light, lo-fi pixel text |
| Endings | 3 (Keep Walking / Turn Back / Stay) via `NarrativeManager.determine_ending()` |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/state_system.gd` | StateSystem | **Modified** — Add `hope_despair` as a unified bipolar axis (-10 to +10); add `get_state_id()` returning 1–5; add emotional resistance multipliers |
| `gdscripts/game_manager.gd` | GameManager | **Modified** — Implement `get_slider()`, `apply_slider_delta()`, `set_flag()`, `get_flags()` with real data delegating to StateSystem |
| `gdscripts/worldview_controller.gd` | Worldview Controller | **Modified** — Expand from 3-tone to 5-state mapping; emit discrete state ID via new signal `world_state_changed(state_id: int)` |
| `gdscripts/narrative_manager.gd` | Narrative Manager | **Modified** — Expand `_calculate_tone_for_scene()` from 3-state to 5-state mapping per scene; update echo variant calculation |
| `gdscripts/rain_controller.gd` | Rain Controller | **Modified** — Change rain mapping from conviction-inverse to hope-inverse; increase to 5 rain intensity levels |
| `gdscripts/state_system.gd` (project.godot) | Autoload registration | **Modified** — Add `StateSystem` to `[autoload]` section |
| `gdscripts/game_state.gd` | GameState (legacy) | **Deprecated** — Keep for backward compat but delegate internally to StateSystem |
| `dialogues/store_clerk.json` | Clerk Dialogue | **Modified** — Expand conditions to use 5-state slider gating |
| `dialogues/office_door.json` | Door Dialogue | **Modified** — Add slider-gated choice branches |
| `dialogues/lobby_stranger.json` | Stranger First Meeting | **Modified** — Add 5-state variant conditions |
| `dialogues/bridge_homeless.json` | Homeless Dialogue | **Modified** — Add slider-gated echo variants |
| `dialogues/underpass_stranger_echo.json` | Stranger Echo | **Modified** — Expand echo variants to 5-state |
| `dialogues/subway_ending.json` | Subway Ending | **Modified** — Ensure ending choices use 5-state conditions |
| `scenes/*/*.tscn` | Scene files | **Possibly modified** — If environmental text components need additional variant slots |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/dialogue_runner.gd` | Dialogue Runner | `_build_state_snapshot()` currently queries GameManager for many axes. Should add `hope_despair` and may simplify axis list |
| `gdscripts/dialogue_condition_evaluator.gd` | Condition Evaluator | No changes needed — existing ops (`gte`/`lte`/`gt`/`lt`/`eq`) work with `hope_despair` axis values directly |
| `gdscripts/main.gd` | Main Script | May need to initialize or wire the new slider system |
| `gdscripts/scene_base.gd` | Scene Base | Scene scripts need to read the new `hope_despair` axis — may need updated helper method |
| `gdscripts/office.gd`, `lobby.gd`, `store.gd`, `bridge.gd`, `underpass.gd`, `subway_station.gd` | Scene Scripts | Environmental text selection may need expanding from 3-variant to 5-variant |
| `gdscripts/scene_manager.gd` | Scene Manager | If slider state affects scene transition effects (e.g., fade color), may need update |
| `gdscripts/dialogue_display_3d.gd` | Dialogue 3D Display | If disabled-choice rendering is adopted (grayed-out choices), this needs update |
| All dialogue JSONs | All dialogue files | All authored dialogues may need condition updates to use 5-state ranges for `hope_despair` |
| `docs/DESIGN/50-state-world-feedback.md` | DESIGN Doc | Plan phase output |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | GDD Overview | Update state system description |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | GDD Dialogue | Add `hope_despair` axis to slider documentation |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | GDD Narrative | Update tone mapping from 3-state to 5-state |

### Data Flow Impact

```
Player makes dialogue choice
    │
    ├──► DialogueRunner records choice
    │       └──► _apply_effects() → calls GameManager.apply_slider_delta()
    │               └──► GameManager (wired) → StateSystem.apply_choice()
    │                       └──► state_changed signal emitted
    │
    ├──► WorldviewController receives state_changed
    │       └──► _calculate_tone() → 5-state discrete tier (was 3-tone)
    │       └──► world_text_changed.emit(tone)
    │       └──► world_state_changed.emit(state_id) [NEW]
    │
    ├──► NarrativeManager receives state_changed
    │       └──► _calculate_tone_for_scene() → 5-state tier per scene
    │       └──► scene_text_changed.emit(scene_id, tone)
    │
    ├──► RainController receives state_changed
    │       └──► Rain intensity mapped from hope (inverse) — was conviction
    │
    ├──► Echo variant calculation
    │       └──► _calculate_echo_variant() → 5 variant choices (was 3)
    │
    └──► Next dialogue encounter
            └──► DialogueRunner._build_state_snapshot()
                    └──► GameManager.get_slider("hope_despair") → real value
                    └──► Condition evaluator gates choices against discrete ranges
```

### Documents to Update

- [x] **This output:** `docs/PRD/50-state-world-feedback.md`
- [ ] `docs/DESIGN/50-state-world-feedback.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md` — Update state system description
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Add `hope_despair` axis and 5-state patterns
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` — Update tone mapping from 3-state to 5-state
- [ ] `docs/GAME_DESIGN/INDEX.md` — Index update

---

## 4. Solution Comparison

> At least 2 approaches required (depth/deep label).

### Approach A: Unify Under StateSystem — Expand hope to Bipolar Slider

**Description:**

Keep `StateSystem` as the authoritative state manager. Add a `hope_despair: float` property that represents the unified -10 to +10 range. The existing `hope` axis (0–10) becomes *derived* from `hope_despair` (mapping: `hope = (hope_despair + 10.0) / 2.0`, i.e. -10→0.0, 0→5.0, +10→10.0). `conviction` and `will` remain independent axes.

The 5 discrete states are defined as:

| State ID | Name | Slider Range | Hope Mapping | Tone (Worldview) |
|----------|------|-------------|--------------|-------------------|
| 1 | **Despair** | -10.0 to -6.0 | hope 0.0–2.0 | Deepest despair — monochrome |
| 2 | **Low** | -5.0 to -2.0 | hope 2.5–4.0 | Negative but not hopeless |
| 3 | **Neutral** | -1.0 to +1.0 | hope 4.5–5.5 | Baseline — flat affect |
| 4 | **Buoyant** | +2.0 to +5.0 | hope 6.0–7.5 | Positive outlook, warm |
| 5 | **Hope** | +6.0 to +10.0 | hope 8.0–10.0 | Boundless hope, glowing |

Boundary rule: upper bound is inclusive (`<=`), so state 1 = [-10.0, -6.0], state 2 = (-6.0, -2.0], etc.

**Updates to existing systems:**

- **WorldviewController:** Expand from 3-tone to 5-state. Add new signal `world_state_changed(state_id: int)`. The existing `world_text_changed(tone)` signal still fires with the state name string for backward compatibility.
- **NarrativeManager:** Expand `_calculate_tone_for_scene()` to return 5-state values per scene (e.g., office → `"despair"`/`"low"`/`"neutral"`/`"buoyant"`/`"hope"`). Update `_calculate_echo_variant()` to use 5 variants.
- **RainController:** Change from `(10.0 - conviction) / 10.0` to `(10.0 - hope) / 10.0` where `hope` is the derived 0–10 value. Five rain intensity levels map to 5 states.
- **StateSystem:** Must become an autoload for scene-persistent access.
- **GameManager:** Wire `get_slider("hope_despair")` to return the bipolar value. Wire `apply_slider_delta()` to call `StateSystem.apply_choice()` with the new axis.

**NPC attitude system:**

Each NPC's dialogue JSON defines per-state greeting and choice gating using the `hope_despair` axis:
```json
{
  "text": "「今天过得不好。」",
  "condition": {
    "type": "slider",
    "axis": "hope_despair",
    "op": "gte",
    "value": 2
  }
}
```

NPC response trees include 5-tier greeting variants keyed to state ID. When a state has no authored variant, the nearest available variant is used via `get_variant(state_id, variants_array)` fallback helper.

**Choice gating style (from Spike 3):** Use **disabled gating** — choices are visible but grayed out with a tooltip ("You don't feel like saying this right now.") when the slider condition isn't met. This preserves player awareness of what they're missing.

**Emotional resistance (from Spike 2):** Apply **mild resistance** — at Despair (state 1), positive deltas are ×0.5; at Hope (state 5), negative deltas are ×0.5. Resistance multipliers are configurable via exported variables.

**Mid-dialogue state changes:** Queue state changes that occur during active dialogue and flush on `dialogue_ended` signal, preventing jarring visual changes mid-conversation.

**Pros:**
- Clean unification — one authoritative source of truth for hope/despair.
- Existing `state_changed` signal wiring continues to work.
- `StateSystem` is already a well-defined Node with signals.
- `conviction` and `will` remain independent but can be cross-wired (e.g., high conviction can slow despair descent).
- The 5-state mapping matches the issue's AC1 requirement exactly.
- Dialogue engine conditions work without modification (slider conditions already exist).
- NarrativeManager and scene scripts are already wired to StateSystem — minimal rewiring.

**Cons:**
- Must deprecate `GameState` autoload (hope/despair 0–100).
- `GameManager` must be wired to `StateSystem` instead of being a stub.
- `NarrativeManager._calculate_tone_for_scene()` has per-scene tone tables that need 5-state expansion (6 scenes × 5 states = 30 entries).
- Existing scene scripts use 3-variant environmental text — need expansion to 5 variants.
- Both `WorldviewController` and `NarrativeManager` have overlapping tone responsibilities — risk of drift.
- All 7 dialogue JSONs need condition review and possible expansion.
- `RainController` behavior change (conviction → hope) may break existing scene expectations.

**Risk:** Low-Medium — The narrative architecture is fully wired. The main risk is the volume of changes across dialogue files and scene scripts, requiring careful regression testing.

**Effort:** 3-4 weeks (StateSystem slider + autoload + GameManager wiring + worldview 5-state + narrative tone expansion + rain re-mapping + 7 dialogue JSON updates + scene text expansion + NPC attitude patterns + tests)

---

### Approach B: New Node — HopeDespairSlider as an Independent Autoload + NPCManager

**Description:**

Create a new `HopeDespairSlider` autoload that manages the -10 to +10 slider with 5 discrete states independently of the tri-axis `StateSystem`. `StateSystem`'s `hope` axis is synchronized from this slider (read-only mapping). `conviction` and `will` continue to operate independently.

A new `NPCManager` autoload holds per-NPC attitude profiles keyed by state ID. Each NPC profile defines: `greeting[5]`, `information_tiers[5]`, `special_actions[5]`. Dialogue runner consults `NPCManager.get_npc(npc_id)` to gate choice availability.

The 5-state mapping is identical to Approach A.

`GameManager` queries `HopeDespairSlider` for the authoritative slider value. `WorldviewController` and `NarrativeManager` listen to `HopeDespairSlider.slider_changed` instead of `StateSystem.state_changed`.

The autoload provides:
- `get_value() → float` (-10 to +10)
- `get_state_id() → int` (1–5)
- `apply_delta(delta: float)` — clamped, with "sticky" resistance at extremes
- `signal slider_changed(value: float, state_id: int)`

**NPC attitude system (NPCManager):**
- Standalone autoload with per-NPC profiles.
- Each NPC profile defines greeting, information tiers, special actions per state ID.
- Profile data loaded from a JSON data file in `dialogues/npc_profiles.json`.

**Pros:**
- Clean separation — slider is a single-purpose module, NPC attitudes are a separate concern.
- No risk of breaking existing `StateSystem` (conviction/will remain untouched).
- Autoload persists across all scene changes by definition.
- Can be tested independently from the tri-axis system.
- `NPCManager` provides a centralized, data-driven attitude system that's easier for content authors.
- Future extension (clamping events, emotional checkpoints, NPC mood persistence) is contained.

**Cons:**
- Duplication with `StateSystem.hope` — now two sources of "hope" data requiring synchronization.
- More autoloads = more initialization complexity (adding `HopeDespairSlider` and `NPCManager`).
- Existing code that reads `StateSystem.hope` won't automatically pick up slider changes.
- `WorldviewController`, `NarrativeManager`, and `RainController` currently listen to `StateSystem.state_changed` — need additional wiring or migration.
- `NarrativeManager` has deep integration with `StateSystem` — the echo system reads `_state_system.hope` and `_state_system.conviction` directly. Migration to a new signal source requires changes to multiple internal methods.
- The dialogue engine's `_build_state_snapshot()` queries `GameManager.get_slider("hope")` — the path must be reconciled.

**Risk:** Medium-High — Three autoloads (HopeDespairSlider, NPCManager) create a synchronization problem with `StateSystem.hope`. If synchronization drifts, authored dialogue conditions fail silently. The migration from `StateSystem.state_changed` to `HopeDespairSlider.slider_changed` for WorldviewController, NarrativeManager, and RainController is invasive.

**Effort:** 4-5 weeks (new autoloads + synchronization layer + signal migration for 3 listeners + narrative tone expansion + rain re-mapping + NPCManager + dialogue JSON updates + scene text expansion + tests)

---

### Recommendation

→ **Approach A (Unify Under StateSystem)** because:

1. **Single source of truth** — `StateSystem` already owns `hope`. Expanding it to a bipolar `hope_despair` axis is a natural evolution, not a new system.
2. **Zero synchronization risk** — No need to keep two modules in sync. The slider IS `StateSystem.hope`, just mapped to -10/+10.
3. **Existing signal wiring works** — `state_changed` already reaches `WorldviewController`, `NarrativeManager`, and `RainController`. No rewiring needed.
4. **NarrativeManager already deeply integrated with StateSystem** — it reads `_state_system.hope` and `_state_system.conviction` directly in echo variant calculations. Keeping the same source avoids refactoring.
5. **Dialogue engine already compatible** — `_build_state_snapshot()` queries `GameManager.get_slider("hope_despair")`. Adding the new axis name is a one-line change.
6. **Simpler integration** — Scene scripts reference `StateSystem` indirectly via `WorldviewController.get_tone_for_state()`. Expanding to 5 states is an update to existing code paths.
7. **Cleaner deprecation** — The legacy `GameState` autoload can be deprecated in one pass.

**Key design decisions for Approach A:**

1. `StateSystem.hope` remains 0–10 internally but is **driven by** a `hope_despair` property (-10 to +10) using the mapping `hope = (hope_despair + 10.0) / 2.0`.
2. `StateSystem.get_state_id() → int` returns 1–5 based on `hope_despair`.
3. `GameManager.get_slider("hope_despair")` returns the bipolar value. `get_slider("hope")` returns the 0–10 mapped value for backward compatibility.
4. `WorldviewController` is expanded to 5 states. New signal `world_state_changed(state_id: int)` in addition to existing `world_text_changed(prefix: String)`.
5. `NarrativeManager._calculate_tone_for_scene()` is expanded to 5-state per-scene mapping tables.
6. `RainController` re-mapped from conviction→rain to hope→rain.
7. The legacy `GameState` autoload (`game_state.gd`) is deprecated — its `hope` and `despair` values are replaced by the single `hope_despair` slider.
8. NPC attitude is implemented as a **data-driven pattern** within existing dialogue JSONs: per-state greeting and choice gating using the `hope_despair` axis.
9. **StateSystem must become an autoload** — added to `project.godot`'s `[autoload]` section.

**Why not Approach B?**
- The synchronization problem between two "hope" sources is a real maintenance burden that will cause bugs during Issue #56 script writing.
- Adding more autoloads fragments the state architecture (currently `GameManager`, `GameState`, `NarrativeManager`, plus new `HopeDespairSlider` and `NPCManager`).
- `NarrativeManager` reads `_state_system.hope` directly in 4 places. Migrating to a new signal from `HopeDespairSlider` requires changes across the entire narrative layer.
- The project already has a working signal chain that Approach A extends naturally.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **AC1 (Shallow): Slider ranges -10 to +10 with 5 discrete states.**
   - `StateSystem.hope_despair` initialized to `0.0` (Neutral).
   - Range clamped to [-10.0, +10.0] on every `apply_choice()`.
   - 5 discrete state IDs mapped as: 1=Despair (-10 to -6), 2=Low (-5 to -2), 3=Neutral (-1 to +1), 4=Buoyant (+2 to +5), 5=Hope (+6 to +10).
   - Upper bound inclusive: state 1 = [-10.0, -6.0], state 2 = (-6.0, -2.0], etc.
   - `get_state_id()` returns correct ID for any slider value.
   - `GameManager.get_slider("hope_despair")` returns the real current value.

2. **AC2 (Middle): Every scene object has at least 3 text variants mapped to slider ranges.**
   - Each scene object with environmental text (window text in office, neon sign in street, graffiti in underpass, OPEN sign in store, counter text in store, railing text on bridge, ticket gate in subway station) has at least 3 authored text variants.
   - Variants are selected at scene load (`_ready()`) based on the current slider state via `WorldviewController.get_tone_for_state()` or equivalent.
   - Minimum variant count: 3 per object covering Despair/Low, Neutral, Buoyant/Hope ranges.
   - Recommended: 5 variants per object (one per state) for a polished experience.

3. **AC3 (Deep): Slider influences not just text but also available choices.**
   - At least one dialogue in the game has a choice that is **only visible** at a specific slider state (e.g., "I feel like things might change..." only appears at Buoyant or Hope).
   - At least one dialogue choice has a **different outcome** based on slider value (e.g., "Are you okay?" → clerk responds differently at Despair vs Hope).
   - At least one NPC has a **different greeting tone** per slider state (3+ variants).
   - All choice gating uses the dialogue engine's condition system (slider conditions with `gte`/`lte` on `hope_despair` axis).
   - Disabled choices (grayed out) are used instead of hidden choices for player clarity.

### Edge Cases

1. **Slider at exact boundary:** If `hope_despair = -6.0`, `get_state_id()` returns `1` (Despair, not Low). The mapping uses `<=` for the upper bound of each state: state 1 is [-10.0, -6.0], state 2 is (-6.0, -2.0], etc. Documented in code comments.

2. **State change during active dialogue:** If a dialogue choice applies a delta that crosses a state boundary mid-conversation, the environmental text should NOT update until the dialogue ends (to avoid jarring visual changes during text-heavy scenes). Queue state changes and flush on `dialogue_ended` signal.

3. **Rapid slider changes:** If multiple `apply_choice()` calls happen in the same frame (e.g., a composite effect), only one `state_changed` emission should fire. Implement with a debounce or batch-apply pattern in StateSystem.

4. **Empty text variant:** If a scene object only has 3 variants authored but the current state falls into a range that maps to a variant that hasn't been written (e.g., only despair, neutral, hope — but not low or buoyant), fall back to the nearest available variant. A `get_variant(state_id, variants_array)` helper clamps to available variant count.

5. **Legacy GameState still referenced:** If existing code references `GameState.get_state()` (hope/despair 0–100), it gets stale values. Mitigation: `GameState` delegates to `StateSystem` internally, or emits a deprecation log warning and redirects.

6. **NPC with no state-specific greeting:** If an NPC's dialogue JSON doesn't define all 5 state greetings, the `default` choice in the dialogue engine fallback mechanism handles it (current behavior: if no condition matches, end conversation gracefully or use the default choice).

### Failure Paths

1. **StateSystem not found as autoload:** If `StateSystem` isn't at `/root/StateSystem` (not added to `project.godot`'s `[autoload]`), all listeners (`WorldviewController`, `NarrativeManager`, `RainController`) log an error in `_ready()` and use default neutral values. All state-dependent systems degrade gracefully to state 3 (Neutral).

2. **GameManager.get_slider() still returns stub:** If `GameManager` hasn't been wired to `StateSystem` yet, `get_slider()` returns default `5.0` for any axis. The dialogue engine's `_build_state_snapshot()` picks up this default. **Mitigation:** Ensure GameManager wiring is the first implementation task.

3. **Dialogue JSON references unknown slider axis:** If an authored dialogue uses `"axis": "hope_despair"` but `GameManager` doesn't support it (e.g., implementation hasn't completed), the condition evaluator gets `sliders["hope_despair"] = 0.0` (default float) and the condition likely fails. The existing fallback-to-default-choice mechanism handles this gracefully.

4. **NarrativeManager tone table drift:** If `WorldviewController` uses a 5-state mapping but `NarrativeManager._calculate_tone_for_scene()` is not updated to match, scene text variants and tone calculations diverge. **Mitigation:** Both systems derive state from `StateSystem.get_state_id()`, so tone tables share the same state ID reference.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #45 — Narrative Architecture | ✅ **Merged** (PR #96) | **Low** — Narrative systems exist and are fully wired |
| StateSystem current architecture | Existing file, NOT autoload | **Medium** — Must become autoload for cross-scene slider persistence |
| GameManager current state | Stub (`get_slider()` returns 5.0) | **Low** — Stub API exists; just needs implementation |
| Dialogue engine (Issue #46 / #52) | ✅ **Merged** (PR #77 / #83) | **Low** — Condition evaluator supports slider conditions |
| WorldviewController current architecture | 3-tone system, wired to StateSystem | **Low** — Direct expansion to 5-state |
| NarrativeManager current architecture | 3-state per-scene tones, wired to StateSystem | **Low** — Direct expansion to 5-state per method |
| Godot 4.7.1 | Stable | **Low** — Engine features stable |

**Dependency chain map:**
```
#42 Theme-Mechanic Mapping → #45 Narrative Architecture → #50 (this issue)
                                                              │
                                                              └── #56 Story Content (depends on slider design)
```

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #56 — Story Content | **Critical** — Script writing needs the slider system design finalized to author state-dependent NPC attitudes, environmental text, and choice trees |
| Any dialogue-content issue | **High** — All authored dialogue conditions need the slider axis name (`hope_despair`) and range (-10 to +10) |
| Rain particle system fine-tuning | **Medium** — Rain intensity levels depend on 5-state slider mapping |
| Final environmental text pass | **Medium** — All scene objects need 5-variant text authoring |

### Preparation Needed

- [ ] **StateSystem autoload decision:** `StateSystem` is currently NOT an autoload — scene scripts get it via `get_node("/root/StateSystem")`. For the slider to work across all scenes, it must be added to `project.godot`'s `[autoload]` section.
- [ ] **GameManager wiring:** Implement real `get_slider()`, `apply_slider_delta()`, `set_flag()`, `get_flags()` methods that delegate to `StateSystem`.
- [ ] **Dialogue JSON audit:** Review all 7 existing dialogue files for hardcoded 3-tone references; update conditions to use `hope_despair` with -10/+10 range.
- [ ] **Scene script audit:** Review `office.gd`, `lobby.gd`, `store.gd`, `bridge.gd`, `underpass.gd`, `subway_station.gd` for hardcoded 3-variant text; expand to 5 variants.
- [ ] **Axis name coordination:** The `DialogueRunner._build_state_snapshot()` currently queries axes `["hope", "despair", "vigor", "burnout", "conviction", "falter"]`. The new `"hope_despair"` axis must be added to this list. Old axes can remain for backward compat.

---

## 7. Spike / Experiment (Mandatory — depth/deep)

### Spike 1: StateTransition Smoothness — Does instant state change feel jarring?

**Question to Answer:**  
When the slider changes state mid-scene (e.g., from Neutral to Despair after a dialogue choice), should environmental text transition instantly or with a lerp/fade? What is the player's tolerance for abrupt visual change?

**Method:**
1. Create a minimal Godot test scene with a `LoFiText3D` node and a button that cycles the slider state.
2. Test three transition modes:
   - (a) **Instant** — text swaps on next frame.
   - (b) **Fade** — text fades out (0.3s), swaps, fades in (0.3s).
   - (c) **Slide** — text scrolls vertically, new text replaces old after 0.5s.
3. Run with `godot --headless --script tests/test_state_transition.gd` and measure visual completion times.
4. Also test during an active dialogue — does mid-conversation state change conflict with dialogue panel rendering?

**Expected Result:**  
Instant swaps are acceptable for background environmental text (neon sign, graffiti, street signs). Fade transitions are preferred for focal text (window text, store sign, ticket gate text). Mid-dialogue state changes should be queued and deferred until dialogue ends.

**Impact on Approach:**  
If fade transitions are required, update `WorldviewController` and `NarrativeManager` to emit a `transition_requested(target_text, state_id)` signal instead of immediate `world_text_changed`. If instant is fine, no change needed.

---

### Spike 2: Sticky Despair — How much player frustration is acceptable?

**Question to Answer:**  
The narrative architecture has 6 scenes. If the slider has "emotional inertia" (harder to escape Despair than to fall into it), what are the acceptable delta multipliers so the player feels the weight of despair without getting stuck before reaching the subway station?

**Method:**
1. Implement three resistance profiles in `StateSystem.apply_choice()`:
   - (a) **Linear:** Every delta is applied as-is. No resistance. Easiest to escape.
   - (b) **Mild resistance:** At Despair state (state 1), positive deltas are halved (×0.5). At Hope state (state 5), negative deltas are halved.
   - (c) **Strong resistance:** At Despair, positive deltas are ×0.25. At Hope, negative deltas are ×0.25. At extreme boundaries (-10 or +10), deltas are ×0.1.
2. Simulate 20 dialogue choice sequences of varying lengths and record the slider trajectory for each profile.
3. Compare: how many choices does it take to go from Despair to Neutral under each profile?

**Expected Result:**  
Profile (b) Mild resistance provides the best pacing — it takes 3-4 positive choices to escape Despair (not trivial but not frustrating). Profile (a) is too easy (1-2 choices). Profile (c) is too punishing (6+ choices across 6 scenes, potentially preventing reaching Hope by the subway station).

**Impact on Approach:**  
If mild resistance is adopted, `StateSystem.apply_choice()` needs a `_get_resistance_multiplier(state_id, delta_sign)` helper. The resistance multipliers should be configurable via exported variables for designer tuning.

---

### Spike 3: Disabled vs Hidden Choices — Which gating style maintains player agency?

**Question to Answer:**  
When dialogue choices are hidden (not just disabled) due to slider state, do players notice? Does the lack of visible-but-grayed-out options reduce perceived agency in a linear narrative game?

**Method:**
1. Create three test dialogue nodes in a minimal JSON:
   - (a) **Hidden gating:** Choices are simply absent from the `choices_available` array when conditions aren't met (current behavior in dialogue engine).
   - (b) **Disabled gating:** Choices are present in the array but have `disabled: true`, displayed as grayed-out text with tooltip: "You don't feel like saying this right now."
   - (c) **Always visible:** All choices are visible regardless of state; selecting one with unmet condition shows a thought bubble: "No. That's not what I really feel."
2. Run a playtest with 3-5 testers and record completion rate, time-to-choice, and perceived agency score for each gating style.
3. Collect qualitative feedback: "Did you feel frustrated by options you couldn't pick?"

**Expected Result:**  
Approach (c) "Always visible" scores highest on perceived agency but lowest on immersion (players feel the choices are meaningless — "why show me something I can't do?"). Approach (a) "Hidden" is most immersive but risks confusion ("why is this choice missing?"). Approach (b) "Disabled" is the best balance — players see what they're missing, creating narrative tension and a "goal" to reach that state. This aligns with the narrative architecture's "your choices reflect your inner state" philosophy.

**Impact on Approach:**  
If disabled gating is preferred, the `choices_available` signal payload must include a `disabled` field per choice. The dialogue display (`dialogue_display_3d.gd`) must render disabled choices (grayed out, with tooltip). This is a moderate change to `dialogue_display_3d.gd` but requires no change to the runner or evaluator.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The game currently has the following state-relevant systems (all merged and functional):

- **StateSystem** (`gdscripts/state_system.gd`) — Tri-axis (hope/conviction/will, 0–10, 5=neutral) with `apply_choice()`, `get_state()`, `reset()`, `get_state_tier()`, and `state_changed` signal. **Not an autoload** — must be made one for scene-persistent access.
- **WorldviewController** (`gdscripts/worldview_controller.gd`) — Maps hope to 3 tones via `_calculate_tone()`. Emits `world_text_changed(prefix)`. Wired to `StateSystem.state_changed`.
- **NarrativeManager** (`gdscripts/narrative_manager.gd`) — Fully implemented 179-line module. Manages scene sequence, ending determination, echo system. `_calculate_tone_for_scene()` returns 3-state tones per scene. `_calculate_echo_variant()` returns 2-3 variants. Wired to `StateSystem.state_changed`.
- **RainController** (`gdscripts/rain_controller.gd`) — Conviction → rain intensity (inverse). Has `forced_shelter_triggered` with timer check every 30s. Wired to `StateSystem.state_changed`.
- **GameManager** (`gdscripts/game_manager.gd` — autoload) — Stub `get_slider()`, `apply_slider_delta()`, `set_flag()`, `get_flags()` methods all returning defaults. Has `choices_history` for dialogue persistence across scene changes. Has `current_scene_id` and scene tracking.
- **GameState** (`gdscripts/game_state.gd` — legacy autoload) — Hope/despair 0–100 as separate values. **To be deprecated** after slider system is implemented.
- **DialogueRunner** (`gdscripts/dialogue_runner.gd` — 204 lines) — `_build_state_snapshot()` queries `GameManager.get_slider()` for axes `["hope", "despair", "vigor", "burnout", "conviction", "falter"]`. Supports slider conditions with `gte`/`lte`/`gt`/`lt`/`eq`. Stores `choices_made` array.
- **DialogueConditionEvaluator** (`gdscripts/dialogue_condition_evaluator.gd`) — Stateless utility. Supports slider, flag, choice_made, AND/OR/NOT conditions. No changes needed for 5-state support.
- **Scene scripts** (office.gd, lobby.gd, store.gd, bridge.gd, underpass.gd, subway_station.gd) — Each has `_configure_environmental_text()` that reads state and selects 3 text variants. All inherit from `SceneBase`.
- **Dialogue files** (7 JSONs in `dialogues/`) — office_door.json, lobby_stranger.json, lobby_guard.json, store_clerk.json, bridge_homeless.json, underpass_stranger_echo.json, subway_ending.json. All use slider conditions on hope/conviction/will.

**Key decisions for the Plan agent:**

1. **StateSystem must become an autoload.** Add to `project.godot`'s `[autoload]` section as `StateSystem`.
2. **Recommended approach: Approach A** — Expand StateSystem to include a unified `hope_despair` bipolar slider (-10 to +10) with `get_state_id()` returning 1–5.
3. **WorldviewController expands** from 3-tone to 5-state mapping. Add `world_state_changed(state_id: int)` signal.
4. **NarrativeManager expands** `_calculate_tone_for_scene()` to 5-state for each of 6 scenes. Expand `_calculate_echo_variant()` to 5 variants. The scene-tone table needs 30 entries (6 scenes × 5 states).
5. **GameManager must be wired** to StateSystem (not left as stub).
6. **GameState (legacy) deprecation** — redirect internal calls to StateSystem.
7. **RainController re-mapping** — Change from conviction→rain to hope→rain.
8. **Dialogue gating style:** Use disabled choices (visible but grayed out) for clearest player communication.
9. **Emotional resistance:** Use mild resistance profile (×0.5 at extremes) for best pacing.
10. **Mid-dialogue state changes:** Queue and defer until `dialogue_ended` signal fires.

**The proposed implementation order:**

1. Make `StateSystem` an autoload (`project.godot` → `[autoload]`).
2. Add `hope_despair` property (-10 to +10) and `get_state_id()` method to `StateSystem`. Add emotional resistance in `apply_choice()`.
3. Wire `GameManager` methods to delegate to `StateSystem` — `get_slider("hope_despair")` returns real value.
4. Add `"hope_despair"` to `DialogueRunner._build_state_snapshot()` axis list.
5. Update `WorldviewController` to 5-state mapping + new signal.
6. Update `NarrativeManager` to 5-state per-scene tones + 5-variant echo calculation.
7. Re-map `RainController` from conviction→rain to hope→rain.
8. Update scene scripts to use 5-state (or fallback 3-state) text variants.
9. Author NPC attitude data: update 7 dialogue JSONs with `hope_despair` conditions. Add disabled rendering support to `dialogue_display_3d.gd`.
10. Deprecate `GameState` autoload — delegate to StateSystem internally.
11. Write tests for slider boundaries, state transitions, NPC gating, and backward compatibility.

**The main risk** is the volume of changes across dialogue JSONs and scene scripts. Each of the 7 dialogue files needs condition review, and 6 scene scripts need 5-state environmental text. **Recommendation:** Implement the core engine (items 1–6) first, verify with existing 3-variant fallback, then expand scene text and dialogue conditions incrementally.
