# Research: [Design] State-World Feedback — Hope/Despair Slider System

> Parent Issue: #50
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

The project currently has **two overlapping state systems** that manage hope and despair:

| System | File | Values | Range | Role |
|--------|------|--------|-------|------|
| `GameState` | `game_state.gd` | `hope`, `despair` | 0–100 each | Legacy autoload, prints on init |
| `StateSystem` | `state_system.gd` | `hope`, `conviction`, `will` | 0–10 each, 5=neutral | Tri-axis state manager, emits `state_changed` |
| `GameManager` | `game_manager.gd` | stub `get_slider()` | Returns `5.0` | Autoload, intended but not wired |

**Problems with the current state:**

1. **Dual-system confusion** — `GameState` treats hope and despair as *independent* values (0–100 each, hope starts at 100, despair at 0). `StateSystem` treats hope as a *single bipolar axis* (0–10, 5=neutral). Neither is authoritative.
2. **No Hope/Despair unified slider** — There is no single authoritative slider that represents the player's emotional state on a bipolar scale. The issue requires **one slider from -10 (despair) to +10 (hope)**.
3. **GameManager is a stub** — `get_slider()` returns `5.0` for every axis. `apply_slider_delta()`, `set_flag()`, and `get_flags()` are `pass` / `false` stubs. The dialogue engine's `_build_state_snapshot()` queries GameManager but gets no real data.
4. **WorldviewController uses 3 tones only** — Maps hope to `"despair"`/`"neutral"`/`"hope"` tones. Issue #50 requires **5 discrete states** for deeper granularity.
5. **No NPC attitude system** — NPC dialogue choices are statically authored. There is no system that adjusts NPC tone, willingness, or dialogue branch availability based on the player's hope/despair slider position.
6. **No emotional pacing tooling** — The slider is not yet used as a pacing mechanism. There is no system that automatically modulates slider change rates, caps accumulation, or creates emotional "checkpoints."

### Expected Behavior

A unified **Hope/Despair Slider System** that:

1. **Provides a single authoritative slider** — Range -10 (absolute despair) to +10 (boundless hope), with **5 discrete states** that map to player emotional tiers.
2. **Drives NPC attitude** — NPC dialogue branches, greeting tones, and availability of special dialogue options are gated by the slider state.
3. **Drives environmental text** — Every scene object (rain, neon sign, puddle, window, graffiti, store sign) has **at least 3 text variants** keyed to slider ranges.
4. **Gates choices** — Dialogue choices reflect the player's internal state: some choices are *only visible* at certain slider ranges, some have *different outcomes* based on slider position, and some choices *change the slider itself*.
5. **Serves as an emotional pacing tool** — The slider changes at controlled rates, has "sticky" regions (harder to leave deep despair), and provides emotional checkpoints that gate narrative progression.

### User Scenarios

- **Scenario A (Player in despair, slider -10 to -5):** Player who made repeatedly self-destructive dialogue choices finds themselves in "Despair" state. Environmental text turns monochrome, rain intensity is max, NPCs speak curtly or with pity. Dialogue choices that require optimism are hidden. Special "glimmer of hope" choices appear but require high will to select.
- **Scenario B (Player neutral, slider -4 to +4):** Baseline state. Environmental text is neutral-faded. NPCs are polite but distant. All standard dialogue choices are available. This is the "reset" state after emotional checkpoints.
- **Scenario C (Player hopeful, slider +5 to +10):** Environmental text brightens, NPCs are warmer, special "compassion" or "insight" dialogue choices unlock. Hidden story fragments become accessible. Rain intensity drops.
- **Frequency:** Every state change affects every scene element. The slider changes multiple times per play session.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally through layered issues:

1. **Issues #1 / #6 / #43** — Project scaffold: GameState autoload with hope/despair (legacy).
2. **Issue #42** — Theme-Mechanic Mapping: designed tri-axis (hope, conviction, will) in `StateSystem`.
3. **Issue #46** — Dialogue Engine: built dialogue runner, parser, condition evaluator referencing GameManager stub.
4. **Issue #55** — Scene sequence: built office/street/store scenes with per-scene environmental text scripts.

Each layer was authored independently, so the state system was never unified. The `GameManager` stub was a placeholder awaiting this issue (#50) to define the final design.

### Why Change Now?

- **Issue #45 (Narrative Architecture)** is the prerequisite — it defines how narrative systems compose, and this feedback loop is a core component.
- **Issue #56 (Story Content)** depends on this issue — the script writing phase needs the State-World Feedback design to author NPC attitudes, environmental text, and choice trees.
- The dialogue engine (merged in PR #77) already supports condition evaluation on sliders — but the slider values are all stubs. Without a real slider system, authored dialogue conditions can never fire.
- The scene scripts (office.gd, street.gd, store.gd, from issue #55) implement 3-variant environmental text per scene object, but the tone mapping (`hope` <= 3 / >= 7) is hardcoded in `worldview_controller.gd`. A 5-state design would need to update the mapping.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| State architecture | Tri-axis: hope, conviction, will via `state_system.gd` |
| State range | 0–10 per axis, 5=neutral, clamped |
| Legacy system | `GameState` autoload (hope/despair 0–100) — must not break existing references |
| Autoloads | `GameManager` (stub), `GameState` (legacy) — both persist across scene changes |
| Dialogue conditions | Supported ops: `gte`, `lte`, `gt`, `lt`, `eq` on slider axes |
| Worldview tones | `"despair"` (hope <= 3), `"neutral"` (3 < hope < 7), `"hope"` (hope >= 7) |
| Scene scripts | Each scene's `_configure_environmental_text()` reads state at `_ready()` |
| Writing style | Hemingway — short lines, iceberg theory, ≤25 words per line |
| Visual style | Edward Hopper urban night — dark (#1a1a2e sky), warm amber light, lo-fi pixel text |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/state_system.gd` | StateSystem | **Modified** — Add HopeDespairSlider as a unified bipolar axis; connect to GameManager |
| `gdscripts/game_manager.gd` | GameManager | **Modified** — Implement `get_slider()`, `apply_slider_delta()`, `set_flag()`, `get_flags()` with real data |
| `gdscripts/worldview_controller.gd` | Worldview Controller | **Modified** — Expand from 3-tone to 5-state mapping; emit discrete state ID |
| `gdscripts/rain_controller.gd` | Rain Controller | **Modified** — Map slider state to rain intensity layers (5 levels instead of continuous) |
| `gdscripts/office.gd` | Office Scene Script | **Modified** — Update environmental text to 5-state variants if needed |
| `gdscripts/street.gd` | Street Scene Script | **Modified** — Update neon, graffiti, street sign to 5-state variants |
| `gdscripts/store.gd` | Store Scene Script | **Modified** — Update OPEN sign + clerk foreshadowing to 5-state |
| `gdscripts/game_state.gd` | GameState (legacy) | **Deprecated** — Keep for backward compat but emit deprecation warning |
| `dialogues/store_clerk.json` | Clerk Dialogue | **Modified** — Expand conditions to use 5-state slider gating |
| `dialogues/office_door.json` | Door Dialogue | **Modified** — Add slider-gated choice branches |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/dialogue_runner.gd` | Dialogue Runner | May need `_build_state_snapshot()` update if slider API changes |
| `gdscripts/dialogue_condition_evaluator.gd` | Condition Evaluator | May need new operators (e.g., `in_range`, `state_eq`) for 5-state matching |
| `gdscripts/main.gd` | Main Script | May need to initialize or wire the new slider system |
| `dialogues/` | All dialogue files | All authored dialogues may need condition updates to use 5-state ranges |
| `docs/DESIGN/50-state-world-feedback.md` | DESIGN Doc | Plan phase output |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | GDD Overview | Update state system description |

### Data Flow Impact

```
Player makes dialogue choice
    │
    ├──► DialogueRunner records choice
    │       └──► _apply_effects() → calls GameManager.apply_slider_delta()
    │               └──► GameManager → StateSystem.apply_choice()
    │                       └──► state_changed signal emitted
    │
    ├──► WorldviewController receives state_changed
    │       └──► _calculate_tone() → 5-state discrete tier
    │       └──► world_text_changed.emit(state_id)
    │               └──► Scene environmental text updates (if dynamic, not just at _ready)
    │
    ├──► RainController receives state_changed
    │       └──► Rain intensity mapped from slider (hope → inverse rain)
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
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Add slider gating patterns
- [ ] `docs/GAME_DESIGN/INDEX.md` — Index update

---

## 4. Solution Comparison

> At least 2 approaches required (depth/deep label).

### Approach A: Unify Under StateSystem — Expand hope to Bipolar Slider

**Description:**

Keep `StateSystem` as the authoritative state manager. Add a `hope_despair: float` slider that represents the unified -10 to +10 range. The existing `hope` axis (0–10) becomes derived from `hope_despair` (mapping: `hope = (hope_despair + 10) / 2`, i.e. -10→0, 0→5, +10→10). `conviction` and `will` remain independent axes but can also be influenced by the slider.

The 5 discrete states are defined as:

| State ID | Name | Slider Range | Hope Mapping | Tone |
|----------|------|-------------|--------------|------|
| 1 | **Despair** | -10 to -6 | hope 0.0–2.0 | Deepest despair — monochrome tone |
| 2 | **Low** | -5 to -2 | hope 2.5–4.0 | Negative but not hopeless |
| 3 | **Neutral** | -1 to +1 | hope 4.5–5.5 | Baseline — flat affect |
| 4 | **Buoyant** | +2 to +5 | hope 6.0–7.5 | Positive outlook, warm tone |
| 5 | **Hope** | +6 to +10 | hope 8.0–10.0 | Boundless hope, glowing tone |

`WorldviewController` is updated to emit the 5-state ID instead of the 3-tone string. Scene scripts switch on state ID to select text variants (at least 3, up to 5 depending on the scene object).

`GameManager.get_slider()` returns `hope_despair` (the unified bipolar value). The dialogue engine's `_build_state_snapshot()` picks this up automatically. Dialogue conditions use `gte`/`lte` with threshold values (-6, -2, +2, +6) to gate choices.

**NPC attitude system:**
- Each NPC has a `base_greeting` and `state_greetings[5]` — one greeting per slider state.
- Special dialogue choices are gated with conditions like:
  ```json
  {"type": "slider", "axis": "hope_despair", "op": "gte", "value": 6}
  ```
- NPC willingness to share information is proportional to slider state: in Despair (state 1), NPCs give curt 1-line responses. In Hope (state 5), NPCs offer 3+ branching options.

**Pros:**
- Clean unification — one authoritative source of truth for hope/despair.
- Existing `state_changed` signal wiring continues to work.
- `StateSystem` is already a well-defined Node with signals.
- `conviction` and `will` remain independent but can be cross-wired (e.g., high conviction can slow despair descent).
- The 5-state mapping matches the issue's AC1 requirement exactly.
- Dialogue engine conditions work without modification (slider conditions already exist).

**Cons:**
- Must deprecate `GameState` autoload (hope/despair 0–100) — all references need updating.
- `GameManager` must be wired to `StateSystem` instead of being a stub.
- Existing scene scripts use `hope` axis (0–10) directly — need to update to `hope_despair` (-10 to +10).
- Existing worldview_controller uses 3 tones — needs expansion to 5 states.
- The `RainController` currently maps conviction → rain intensity. If we want hope → rain, that's a behavior change.

**Risk:** Low — most of the architecture already exists (`StateSystem`, `state_changed` signal, dialogue condition evaluator). The main risk is breaking existing scene scripts that reference `hope` directly.

**Effort:** 2-3 weeks (StateSystem slider addition + GameManager wiring + worldview 5-state + scene text updates + NPC attitude system + tests)

---

### Approach B: New Node — HopeDespairSlider as an Independent Autoload

**Description:**

Create a new `HopeDespairSlider` autoload that exists independently of the tri-axis `StateSystem`. This autoload manages the -10 to +10 slider with 5 discrete states. `StateSystem`'s `hope` axis is synchronized from this slider (read-only mapping: `hope = (slider + 10) / 2`). `conviction` and `will` continue to operate independently.

The 5-state mapping is identical to Approach A:

| State ID | Name | Slider Range |
|----------|------|-------------|
| 1 | Despair | -10 to -6 |
| 2 | Low | -5 to -2 |
| 3 | Neutral | -1 to +1 |
| 4 | Buoyant | +2 to +5 |
| 5 | Hope | +6 to +10 |

`GameManager` queries `HopeDespairSlider` for the authoritative slider value. `WorldviewController` listens to `HopeDespairSlider.slider_changed` instead of `StateSystem.state_changed`.

The autoload provides:
- `get_value() → float` (-10 to +10)
- `get_state_id() → int` (1-5)
- `apply_delta(delta: float)` — clamped, with "sticky" resistance at extremes
- `signal slider_changed(value: float, state_id: int)`

**NPC attitude system:**
- `NPCManager` autoload (new) holds per-NPC attitude profiles keyed by state ID.
- Each NPC profile defines: `greeting[5]`, `information_tiers[5]`, `special_actions[5]`.
- Dialogue runner consults `NPCManager.get_npc(npc_id)` to gate choice availability.

**Pros:**
- Clean separation of concerns — slider is a single-purpose module.
- No risk of breaking existing `StateSystem` (conviction/will remain untouched).
- Autoload means it persists across all scene changes by definition.
- Can be tested independently from the tri-axis system.
- Adding "sticky resistance" at extremes is easier in a dedicated module.
- Future extension (e.g., clamping events, emotional checkpoints) is contained.

**Cons:**
- Duplication with `StateSystem.hope` — now there are two sources of "hope" data, requiring synchronization.
- More autoloads = more initialization complexity.
- Existing code that reads `StateSystem.hope` won't automatically pick up slider changes unless synchronization is wired.
- `WorldviewController` and `RainController` currently listen to `StateSystem.state_changed` — they'd need additional wiring or migration to the new slider signal.
- The dialogue engine's `_build_state_snapshot()` already queries `GameManager.get_slider("hope")` — if the slider value comes from a different source, the path must be reconciled.

**Risk:** Medium — adding a new autoload creates a synchronization problem between `HopeDespairSlider` and `StateSystem.hope`. If synchronization drifts (e.g., a dialogue effect modifies `StateSystem.hope` directly but not the slider), the two systems diverge.

**Effort:** 3-4 weeks (new autoload + synchronization layer + worldview/rain migration + NPC manager + scene text updates + tests)

---

### Recommendation

**→ Approach A (Unify Under StateSystem)** because:

1. **Single source of truth** — `StateSystem` already owns `hope`. Expanding it to a bipolar `hope_despair` axis is a natural evolution, not a new system.
2. **Zero synchronization risk** — No need to keep two modules in sync. The slider IS `StateSystem.hope`, just mapped to -10/+10.
3. **Existing signal wiring works** — `state_changed` already reaches `WorldviewController`, `RainController`, and any future listener. No rewiring needed.
4. **Dialogue engine already compatible** — `_build_state_snapshot()` queries `GameManager.get_slider("hope_despair")` which can return the bipolar value directly. Existing slider conditions work.
5. **Simpler integration** — Scene scripts already reference `StateSystem` indirectly via `WorldviewController.get_tone_for_state()`. Expanding the tone mapping to 5 states is a one-file change.
6. **Cleaner deprecation** — The legacy `GameState` autoload can be removed in one pass, with all references migrated to `StateSystem` (which is already close to being an autoload).

**Key design decisions for Approach A:**

1. `StateSystem.hope` remains 0–10 internally but is **driven by** a `hope_despair` property (-10 to +10) using the mapping `hope = (hope_despair + 10) / 2.0`.
2. `GameManager.get_slider("hope_despair")` returns the bipolar value. `get_slider("hope")` returns the 0–10 mapped value.
3. `WorldviewController` is expanded to 5 states with a new signal `world_state_changed(state_id: int)` in addition to the existing `world_text_changed(prefix: String)`.
4. The legacy `GameState` autoload (`game_state.gd`) is deprecated. Its `hope` and `despair` values are replaced by the single `hope_despair` slider.
5. NPC attitude is implemented as a **data-driven component**: each NPC's dialogue JSON includes per-state greeting and choice gating patterns.

**Why not Approach B?**
- The synchronization problem between two "hope" sources is a real maintenance burden that will cause bugs in later issues (especially #56 script writing).
- Adding yet another autoload (`GlobalState`, `GameState`, `GameManager`, `StateSystem`, now `HopeDespairSlider`) fragments the state architecture.
- The project already has a working signal chain: `StateSystem.state_changed → WorldviewController / RainController`. Breaking this chain requires re-wiring in multiple files.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **AC1 (Shallow): Slider ranges -10 to +10 with 5 discrete states.**
   - `StateSystem.hope_despair` initialized to `0.0` (Neutral).
   - Range clamped to [-10.0, +10.0] on every `apply_choice()`.
   - 5 discrete state IDs mapped as: 1=Despair (-10 to -6), 2=Low (-5 to -2), 3=Neutral (-1 to +1), 4=Buoyant (+2 to +5), 5=Hope (+6 to +10).
   - `get_state_id()` returns correct ID for any slider value.
   - GameManager `get_slider("hope_despair")` returns the current value.

2. **AC2 (Middle): Every scene object has at least 3 text variants mapped to slider ranges.**
   - Each scene object with environmental text (window text in office, neon sign in street, graffiti in street, OPEN sign in store) has at least 3 authored text variants.
   - Variants are selected at scene load (`_ready()`) based on the current slider state.
   - Minimum variant count: 3 per object (covering Despair/Low, Neutral, Buoyant/Hope ranges).
   - Recommended: 5 variants per object (one per state) for a polished experience.

3. **AC3 (Deep): Slider influences not just text but also available choices.**
   - At least one dialogue in the game has a choice that is **only visible** at a specific slider state (e.g., "I feel like things might change..." only appears at Buoyant or Hope).
   - At least one dialogue choice has a **different outcome** based on slider value (e.g., "Are you okay?" → clerk responds differently at Despair vs Hope).
   - At least one NPC has a **different greeting tone** per slider state (3+ variants).
   - All choice gating uses the dialogue engine's condition system (slider conditions with `gte`/`lte`).

### Edge Cases

1. **Slider at exact boundary:** If `hope_despair = -6.0`, `get_state_id()` returns `1` (Despair, not Low). The mapping uses `<=` for the upper bound of each state: state 1 is [-10.0, -6.0], state 2 is (-6.0, -2.0], etc. This is documented in the code comments.

2. **State change during active dialogue:** If a dialogue choice applies a delta that crosses a state boundary mid-conversation, the environmental text should NOT update until the dialogue ends (to avoid jarring visual changes during text-heavy scenes). Recommendation: queue state changes and flush on `dialogue_ended`.

3. **Rapid slider changes:** If multiple `apply_choice()` calls happen in the same frame (e.g., a composite effect), only one `state_changed` emission should fire. Implement with a debounce or batch-apply pattern in `StateSystem`.

4. **Empty text variant:** If a scene object only has 3 variants authored but the current state falls into a range that maps to a variant that hasn't been written (e.g., only despair, neutral, hope — but not low or buoyant), fall back to the nearest variant. Recommendation: a `get_variant(state_id, variants_array)` helper that clamps to available variant count.

5. **Legacy GameState still referenced:** If existing code references `GameState.get_state()` (hope/despair 0–100), it gets stale values. Mitigation: `GameState` delegates to `StateSystem` internally, or emits a deprecation log warning and redirects.

6. **NPC with no state-specific greeting:** If an NPC's dialogue JSON doesn't define all 5 state greetings, the `default` choice in the dialogue engine fallback mechanism handles it (current behavior: if no condition matches, end conversation gracefully or use the default choice).

### Failure Paths

1. **StateSystem not found:** If `StateSystem` isn't at `/root/StateSystem` (e.g., not added as autoload), `WorldviewController._ready()` logs an error and uses default neutral tone. All state-dependent systems degrade gracefully to state 3 (Neutral).

2. **GameManager.get_slider() still returns stub:** If `GameManager` hasn't been wired to `StateSystem`, `get_slider()` returns default `5.0` for any axis. The dialogue engine's `_build_state_snapshot()` picks up this default. Mitigation: ensure GameManager wiring is the first implementation task.

3. **Dialogue JSON references unknown slider axis:** If an authored dialogue uses `"axis": "hope_despair"` but `GameManager` doesn't support it (e.g., if implementation hasn't completed), the condition evaluator gets `sliders["hope_despair"] = 0.0` (default float) and the condition likely fails. The existing fallback-to-default-choice mechanism handles this gracefully.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #45 — Narrative Architecture | **OPEN / backlog** | **High** — Prerequisite. The slider system's design depends on how narrative systems compose. If #45 hasn't defined the narrative architecture, the slider integration points are speculative. |
| Issue #55 — Scene Sequence (Office/Street/Store) | ✅ Merged | **Low** — Scene scripts exist; environmental text can be updated in-place |
| Issue #52 — Dialogue Engine (parent #46) | ✅ Merged (PR #77) | **Low** — Condition evaluator supports slider conditions |
| Issue #49 — State System (parent #42) | ✅ Merged | **Low** — StateSystem exists with `state_changed` signal |
| Issue #47 — Theme-Mechanic Mapping | ✅ Merged | **Low** — Theme mapping chain documented |
| Godot 4.7.1 | Stable | **Low** — Engine features stable |

**Dependency chain map:**
```
#45 Narrative Architecture (OPEN — blocker)
  │
  └── #50 (this issue) ← defines state-world feedback design
        │
        └── #56 Story Content (depends on #50's slider design)
```

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #56 — Story Content | **Critical** — Script writing needs the slider system design finalized to author state-dependent NPC attitudes, environmental text, and choice trees |
| Issue #58 — Rain particle system | **High** — Rain intensity levels depend on slider state mapping |
| Any dialogue-content issue | **High** — All authored dialogue conditions need the slider axis name and range |

### Preparation Needed

- [ ] **Issue #45 review:** Read Narrative Architecture design doc (when merged) to ensure slider system composes correctly within the narrative framework.
- [ ] **StateSystem autoload decision:** `StateSystem` is currently NOT an autoload — scene scripts get it via `get_node("/root/StateSystem")`. For the slider to work across all scenes, it must either become an autoload or its state must be duplicated to `GameManager`. **Recommendation:** Add `StateSystem` to `project.godot`'s `[autoload]` section.
- [ ] **GameManager wiring:** Implement real `get_slider()`, `apply_slider_delta()`, `set_flag()`, `get_flags()` methods that delegate to `StateSystem`.
- [ ] **Dialogue JSON audit:** Review all existing dialogue files for hardcoded 3-tone references; update conditions to use 5-state ranges.
- [ ] **Scene script audit:** Review `office.gd`, `street.gd`, `store.gd` for hardcoded 3-variant text; expand to 5 variants.

---

## 7. Spike / Experiment (Mandatory — depth/deep)

### Spike 1: StateTransition Smoothness — Does instant state change feel jarring?

**Question to Answer:**  
When the slider changes state mid-scene (e.g., from Neutral to Despair after a dialogue choice), should environmental text transition instantly or with a lerp/fade? What is the player's tolerance for abrupt visual change?

**Method:**

1. Create a minimal Godot test scene with a LoFiText3D node and a button that cycles the slider state.
2. Test three transition modes:
   - (a) Instant — text swaps on next frame.
   - (b) Fade — text fades out (0.3s), swaps, fades in (0.3s).
   - (c) Slide — text scrolls vertically, new text replaces old after 0.5s.
3. Run with `godot --headless --script tests/test_state_transition.gd` and measure visual completion times.
4. Also test during an active dialogue — does mid-conversation state change conflict with dialogue panel rendering?

**Expected Result:**  
Instant swaps are acceptable for background environmental text (neon sign, graffiti). Fade transitions are preferred for focal text (window text, store sign). Mid-dialogue state changes should be queued and deferred until dialogue ends.

**Impact on Approach:**  
If fade transitions are required, update `WorldviewController` to emit a `transition_requested(target_text, duration)` signal instead of immediate `world_text_changed`. If instant is fine, no change needed.

---

### Spike 2: Sticky Despair — How much player frustration is acceptable?

**Question to Answer:**  
If the slider has "emotional inertia" (harder to escape Despair than to fall into it), what are the acceptable delta multipliers so the player feels the weight of despair without getting stuck?

**Method:**

1. Implement three resistance profiles in `StateSystem.apply_choice()`:
   - (a) **Linear:** Every delta is applied as-is. No resistance. Easiest to escape.
   - (b) **Mild resistance:** At Despair state (state 1), positive deltas are halved (×0.5). At Hope state (state 5), negative deltas are halved.
   - (c) **Strong resistance:** At Despair, positive deltas are ×0.25. At Hope, negative deltas are ×0.25. At extreme boundaries (-10 or +10), deltas are ×0.1.
2. Simulate 20 dialogue choice sequences of varying lengths and record the slider trajectory for each profile.
3. Compare: how many choices does it take to go from Despair to Neutral under each profile?

**Expected Result:**  
Profile (b) Mild resistance provides the best pacing — it takes 3-4 positive choices to escape Despair (not trivial but not frustrating). Profile (a) is too easy (1-2 choices). Profile (c) is too punishing (6+ choices).

**Impact on Approach:**  
If mild resistance is adopted, `StateSystem.apply_choice()` needs a `_get_resistance_multiplier(state_id, delta_sign)` helper. This is a 10-line addition. The resistance multipliers should be configurable via exported variables for designer tuning.

---

### Spike 3: Dialogue Choice Gating — Does condition-based hiding confuse players?

**Question to Answer:**  
When dialogue choices are hidden (not just disabled) due to slider state, do players notice? Does the lack of visible-but-grayed-out options reduce perceived agency?

**Method:**

1. Create three test dialogue nodes in a minimal JSON:
   - (a) **Hidden gating:** Choices are simply absent from the `choices_available` array when conditions aren't met.
   - (b) **Disabled gating:** Choices are present in the array but have `disabled: true`, displayed as grayed-out text with tooltip: "You don't feel like saying this right now."
   - (c) **Always visible:** All choices are visible regardless of state; selecting one with unmet condition shows a thought bubble: "No. I don't mean that."
2. Run a playtest with 3 players (or simulate with test scripts) and record completion rate for each gating style.
3. Measure: time-to-choice for each style, perceived agency score.

**Expected Result:**  
Approach (c) "Always visible" scores highest on perceived agency but lowest on immersion (players feel the choices are meaningless). Approach (a) "Hidden" is most immersive but risks confusion ("why is this choice missing?"). Approach (b) "Disabled" is the best balance — players see what they're missing, creating narrative tension and a "goal" to reach that state.

**Impact on Approach:**  
If disabled gating is preferred, the `choices_available` signal payload must include a `disabled` field per choice. The dialogue panel UI must render disabled choices (grayed out, with tooltip). This is a moderate change to `dialogue_display_3d.gd` but requires no change to the runner or evaluator.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The game currently has the following state-relevant systems:

- **StateSystem** (`state_system.gd`) — Tri-axis (hope/conviction/will, 0–10, 5=neutral) with `apply_choice()`, `get_state()`, `reset()`, and `state_changed` signal. **Not an autoload** — must be made one for scene-persistent access.
- **WorldviewController** (`worldview_controller.gd`) — Maps hope to 3 tones ("despair"/"neutral"/"hope") via `_calculate_tone()`. Emits `world_text_changed(prefix)`. Currently wired to `StateSystem.state_changed`.
- **RainController** (`rain_controller.gd`) — Conviction → rain intensity (inverse). Has `forced_shelter_triggered` with timer check every 30s. Wired to `StateSystem.state_changed`.
- **GameManager** (`game_manager.gd` — autoload) — Stub `get_slider()`, `apply_slider_delta()`, `set_flag()`, `get_flags()` methods. Has `choices_history` for dialogue persistence across scene changes.
- **GameState** (`game_state.gd` — legacy autoload) — Hope/despair 0–100 as separate values. **To be deprecated** after slider system is implemented.
- **DialogueRunner** (`dialogue_runner.gd`) — `_build_state_snapshot()` queries `GameManager.get_slider()`. Supports slider conditions with `gte`/`lte`/`gt`/`lt`/`eq`. Stores `choices_made` array.
- **Scene scripts** (office.gd, street.gd, store.gd) — Each has `_configure_environmental_text()` that reads `gm.get_slider("hope")` and selects 3 text variants. Uses `WorldviewController.get_tone_for_state()` to map hope to tone.

**Key decisions for the Plan agent:**

1. **StateSystem must become an autoload.** Add to `project.godot`'s `[autoload]` section as `StateSystem`.
2. **Recommended approach: Approach A** — Expand StateSystem to include a unified `hope_despair` bipolar slider (-10 to +10) with `get_state_id()` returning 1–5.
3. **WorldviewController expands** from 3-tone to 5-state mapping.
4. **GameManager must be wired** to StateSystem (not left as stub).
5. **GameState (legacy) deprecation** — redirect internal calls to StateSystem.
6. **Dialogue gating style:** Use disabled choices (visible but grayed out) for the clearest player communication.
7. **Emotional resistance:** Use mild resistance profile (×0.5 at extremes) for best pacing.
8. **Mid-dialogue state changes:** Queue and defer until `dialogue_ended` signal fires.

**The proposed implementation order:**
1. Make `StateSystem` an autoload.
2. Add `hope_despair` property (-10 to +10) and `get_state_id()` method to `StateSystem`.
3. Wire `GameManager` methods to delegate to `StateSystem`.
4. Update `WorldviewController` to 5-state mapping.
5. Update scene scripts to use 5-state (or fallback 3-state) text variants.
6. Author NPC attitude data for store clerk (3+ greeting variants).
7. Add disabled-choice rendering in dialogue display.
8. Implement emotional resistance in `apply_choice()`.
9. Deprecate `GameState` autoload.
10. Write tests for slider boundaries, state transitions, and NPC gating.

**The main risk** is the prerequisite dependency on Issue #45 (Narrative Architecture). If #45 hasn't defined the narrative composition model, the slider's integration points with other narrative systems (e.g., flags, events, clock) are speculative and may need rework. **Recommendation:** Proceed with the slider design as a self-contained module; the narrative architecture integration can be adjusted when #45 merges.
