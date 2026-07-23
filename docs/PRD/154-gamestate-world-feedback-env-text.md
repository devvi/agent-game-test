# Research: GameState-World Feedback — Hope/Despair affects environment text

> Parent Issue: #154
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The foundational **infrastructure** for state-driven environmental text is already in place from Issues #47, #50, and #45:

| System | File | Status | What It Provides |
|--------|------|--------|-----------------|
| StateSystem | `state_system.gd` | ✅ Implemented | Bipolar hope_despair slider (-10 to +10), 5 discrete state IDs (1=Despair, 2=Low, 3=Neutral, 4=Buoyant, 5=Hope), `state_changed` and `state_id_changed` signals, emotional resistance |
| GameManager | `game_manager.gd` | ✅ Wired | Delegates `get_slider()`, `apply_slider_delta()`, flags, choice history to StateSystem |
| NarrativeManager | `narrative_manager.gd` | ✅ 5-state expanded | Per-scene 5-state tone tables (6 scenes × 5 states = 30 entries), `scene_text_changed(scene_id, tone)` signal, echo variant calculation |
| WorldviewController | `worldview_controller.gd` | ✅ 5-state expanded | `world_text_changed(tone)` + `world_state_changed(state_id)` signals, 5-state `_calculate_tone()` |
| RainController | `rain_controller.gd` | ✅ Hope-mapped | Rain intensity = (10.0 - hope) / 10.0, 5 levels |
| DialogueRunner | `dialogue_runner.gd` | ✅ hope_despair-aware | Queries `hope_despair` axis in `_build_state_snapshot()`, applies effects via GameManager |
| ConditionEvaluator | `dialogue_condition_evaluator.gd` | ✅ Compatible | All ops (gte/lte/gt/lt/eq) work on `hope_despair` axis |

**However, the actual environmental text rendering is stuck at 2–3 variants per scene object:**

| Scene | Text Objects | Current Variants | What's Missing |
|-------|-------------|-----------------|----------------|
| Office | window_text, screensaver_text, desktop_text | 3-tones (hope/neutral/despair) | No 5-state variant mapping, no dynamic updates |
| Street | neon_sign, graffiti, street_sign | 2-3 ad-hoc variants | `street.gd` reads conviction/hope directly, not via tone system |
| Lobby | entrance_text, stranger_spotlight | 3 (fear/neutral/defiant) | No 5-state mapping, no dynamic updates |
| Bridge | traffic_text, homeless_text, rain_bridge_text | 2-3 (tired/neutral/determined) | Ad-hoc will-based tone, not 5-state |
| Underpass | graffiti_text, echo_text, underpass_light | 2-3 (despair/neutral/resolute) | Ad-hoc composite tone, not matching NarrativeManager |
| Convenience Store | open_sign | 2 (open/with-subtitle) | Minimal variants, not state-aware beyond hope+conviction |
| Subway Station | ticket_gate_text, clock_text, broadcast_text | 3 (backward/waiting/forward) | Not using 5-state per-scene tone table from NarrativeManager |

**Key gap: The `TextComponentBase` system (used by LamppostText, PuddleText, NeonSign, RainText) supports only 3 tiers (low/mid/high), not the full 5-state range.** The system maps:

```
State tiers: low (hope ≤ 3.0) → variant index 0
              mid (3.0 < hope < 7.0) → variant index 1
              high (hope ≥ 7.0) → variant index 2
```

This means State IDs 1 (Despair) and 2 (Low) both map to the same "low" variant, and State IDs 4 (Buoyant) and 5 (Hope) both map to the same "high" variant. **The middle 50% of the emotional spectrum collapses into two variant indices for the entire environment.**

All TextVariantData resources (`lamppost_text_shallow.tres`, `lamppost_text_middle.tres`, `lamppost_text_deep.tres`, etc.) exist only in 3 sets — there are no "very low" or "very high" variants.

Additionally, **no scene dynamically updates environmental text mid-scene** when the slider changes. Text is set once at `_configure_environmental_text()` during `_ready()` and never updated. `TextComponentBase` listens to `scene_text_changed` but only uses it for emissive color overrides (`_apply_tone_overrides()`), not for text content changes.

### Expected Behavior

A **5-state environmental text system** where:

1. **Every scene text object** has 5 authored variants (one per state ID 1–5), selected by the NarrativeManager's per-scene tone table at scene load.

2. **Text variants update dynamically** when the slider changes mid-scene — the `state_changed` or `scene_text_changed` signal triggers variant switching with smooth transitions (fade/crossfade).

3. **TextComponentBase** is expanded from 3-tier to 5-state variant selection, with 5 `TextVariantData` slots per text object.

4. **Scene scripts** are refactored to use a shared 5-state tone lookup (via NarrativeManager or WorldviewController) instead of ad-hoc 2-3 branch tone logic.

5. **Visual properties** (emissive color, pixelation, scanlines) shift alongside text content for each of the 5 states, creating an immersive emotional gradient across the full spectrum.

6. **Hemingway constraints** are enforced for all 5 variants per object — short lines, iceberg theory, ≤25 chars per sentence, ≤3 sentences per narration domain.

### User Scenarios

- **Scenario A (Player at Despair, state ID 1):** The office window shows "Rain blurs the glass. You can't see anything." The neon sign in the street flickers dim red. Lampposts shed weak, sickly light. Graffiti reads "i was here" in scratched letters. Every text object reflects the deepest emotional low.

- **Scenario B (Player at Low, state ID 2):** The office window shows "The city is grey. Same rain. Same night." The neon sign is dull orange. Lampposts cast pale yellow light. Things are negative but not hopeless.

- **Scenario C (Player at Neutral, state ID 3):** Baseline. The office window shows "Rain on the glass. Another night at the office." Neon is standard warm amber. This is the reference state.

- **Scenario D (Player at Buoyant, state ID 4):** The office window shows "Raindrops shimmer on the glass. The city is wet and alive." The neon sign glows warm gold. Lampposts cast inviting pools of light.

- **Scenario E (Player at Hope, state ID 5):** The office window shows "The city glitters through the rain. Tonight could be different." The neon sign burns brilliant amber-white. Graffiti reads "this too shall pass" with a hopeful glow.

- **Frequency:** Every slider-tick during play (6–14 per session) triggers a `state_changed` emission. If the state ID changes, environment text should transition smoothly.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project evolved through a sequence of issues, each building on the previous:

| Issue | What It Added | State of Env Text |
|-------|--------------|-------------------|
| #42/#43 | Project scaffold, basic GameState | No environmental text system |
| #45 | Narrative architecture, scene scripts | 3-tone per-scene hand-rolled text (first pass) |
| #46/#52 | Dialogue engine, condition evaluator | No env text changes |
| #47 | StateSystem autoload, 5-state slider | Infrastructure only — env text not updated |
| #50 | 5-state tone tables (NarrativeManager) | Design doc only — PRD defined 5-state, not implemented for env text |
| #55 | Scene sequence, per-scene text scripts | Ad-hoc 2-3 variants per scene |

Each layer added capability to the *state infrastructure*, but no issue has yet **connected** the 5-state slider to the environmental text rendering. The `TextComponentBase` and its 3-variant system were designed for a 3-state worldview that predates the 5-state design.

### Why Change Now?

1. **Infrastructure is ready** — StateSystem, NarrativeManager, WorldviewController, and GameManager all support 5-state. The missing link is only in the text rendering layer.

2. **NarrativeManager already has the per-scene tone tables** — The 30-entry tone table (6 scenes × 5 states) defines what tone string each scene should display at each state. Scene scripts should use these tones instead of hand-rolled logic.

3. **TextComponentBase already listens to signals** — `_on_state_changed()` and `_on_tone_changed()` are already connected. The only change needed is expanding from 3-tiers to 5-states and adding text content switching alongside the existing emissive color switching.

4. **TextVariantData resources exist as a pattern** — The 3-variant `.tres` files (`*_shallow.tres`, `*_middle.tres`, `*_deep.tres`) prove the pattern works. Adding 2 more variants per object (`*_very_low.tres`, `*_very_high.tres`) is an extension of a proven approach.

5. **No authored dialogue files need changes** — The condition evaluator already supports 5-state slider ranges. This issue touches only the rendering layer, not dialogue content.

6. **Player immersion gap** — Currently, the emotional state system is invisible to the player for large parts of the game. A player at Despair (state 1) sees the same environment text as a player at Low (state 2). The world doesn't respond to emotional shifts, breaking the core immersive promise of the CRPG design.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| State system | 5 discrete state IDs (1–5) from StateSystem.hope_despair (-10 to +10) |
| Per-scene tones | Defined in NarrativeManager.SCENE_TONES (6 scenes × 5 states) |
| Text components | `TextComponentBase` extends `LoFiText3D` (Label3D with custom shader) |
| Variant data | `TextVariantData` Resource with: text, emissive_color, emissive_strength, pixel_factor, color_bits, scanline_intensity, fragment_text |
| Signal chain | `state_changed` → NarrativeManager → `scene_text_changed(scene_id, tone)` → TextComponentBase._on_tone_changed() |
| Writing style | Hemingway — short lines, iceberg theory, ≤25 chars per sentence, ≤3 sentences per narration domain |
| Visual style | Edward Hopper urban night — dark (#1a1a2e sky), warm amber light, lo-fi pixel text |
| Current variant count | 3 per text object (shallow/low, middle/mid, deep/high mapping) |
| TextComponentBase base | `LoFiText3D` (Label3D with pixel_factor, color_bits, scanline_intensity, emissive) |
| Scene text setup | `_configure_environmental_text()` called in SceneBase._ready(), runs once |
| Dynamic updates | `TextComponentBase._on_state_changed()` exists but only updates emissive via `_apply_tone_overrides()` |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/text_component_base.gd` | TextComponentBase | **Modified** — Expand from 3-tier to 5-state variant selection; add `_variant_index_for_state_id()`; make `_on_state_changed` switch text content instead of just emissive; add fade transition support |
| `gdscripts/text_variant_data.gd` | TextVariantData (Resource) | **No changes** — Existing resource fields (text, emissive_color, emissive_strength, pixel_factor, color_bits, scanline_intensity, fragment_text) are sufficient for 5 variants |
| `gdscripts/lamppost_text.gd` | LamppostText | **Modified** — Update `_calculate_tier()` → `_calculate_state_id()` for 5-state; or remove override and use base class method |
| `gdscripts/puddle_text.gd` | PuddleText | **Modified** — Same as LamppostText |
| `gdscripts/neon_sign.gd` | NeonSign | **Modified** — Same; conviction-based tier currently, may keep or change to hope-based |
| `gdscripts/rain_text.gd` | RainText | **Modified** — Update for 5-state; special-case emissive multiplier can use state ID |
| `gdscripts/office.gd` | OfficeScene | **Modified** — Refactor `_configure_environmental_text()` to use NarrativeManager tone lookup; add dynamic update support; expand to 5 variants |
| `gdscripts/street.gd` | StreetScene | **Modified** — Same refactor; remove ad-hoc conviction-based neon sign logic |
| `gdscripts/lobby.gd` | LobbyScene | **Modified** — Refactor to use 5-state lookup |
| `gdscripts/bridge.gd` | BridgeScene | **Modified** — Refactor to use 5-state lookup; remove ad-hoc will-based tone |
| `gdscripts/underpass.gd` | UnderpassScene | **Modified** — Refactor to use 5-state lookup; keep composite tone for special interactions |
| `gdscripts/store.gd` | StoreScene | **Modified** — Expand open_sign variants to 5-state |
| `gdscripts/subway_station.gd` | SubwayStationScene | **Modified** — Refactor to use 5-state lookup for ticket_gate, clock, broadcast |
| `gdscripts/scene_base.gd` | SceneBase | **Modified** — Add helper method `_get_tone_for_scene(scene_id)` that queries NarrativeManager; add `_connect_state_signals()` for dynamic updates |

### New Files Needed

| File | Purpose |
|------|---------|
| `scenes/components/variants/<text>_very_low.tres` × 4 | Very Low variant resources for lamppost, puddle, neon, rain (state 1) |
| `scenes/components/variants/<text>_very_high.tres` × 4 | Very High variant resources for lamppost, puddle, neon, rain (state 5) |
| `tests/test_env_text_5_state.gd` | Headless test: verify 5-state variant selection, signal-driven updates, fallback behavior |
| None | All existing files are modified, not created from scratch |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/narrative_manager.gd` | NarrativeManager | No changes needed — tone tables already exist. Scene scripts now consume them. |
| `gdscripts/worldview_controller.gd` | WorldviewController | No changes needed — already emits `scene_text_changed` / `world_text_changed`. |
| `gdscripts/audio_manager.gd` | AudioManager | May benefit from state-driven audio modulation alongside text changes — out of scope for this issue. |
| `gdscripts/rain_controller.gd` | RainController | Already mapped to hope-inverse — but text transitions could be timed with rain intensity changes. Out of scope. |
| `gdscripts/hemingway_enforcer.gd` | HemingwayEnforcer | Text content for all 5 variants must pass Hemingway constraints — the enforcer should be used in test/authoring. |
| `scenes/office/office.tscn` | Office Scene | May need additional TextVariantData slots in the Inspector |
| `scenes/street/street.tscn` | Street Scene | Same — may need adding LamppostText/PuddleText nodes if not already placed |
| `scenes/lobby/lobby.tscn` | Lobby Scene | Same |
| `scenes/bridge/bridge.tscn` | Bridge Scene | Same |
| `scenes/underpass/underpass.tscn` | Underpass Scene | Same |
| `scenes/store/convenience_store.tscn` | Store Scene | Same |
| `scenes/subway_station/subway_station.tscn` | Subway Station | Same |

### Data Flow Impact

```
StateSystem.apply_choice({hope_despair: delta})
    │
    ├── state_changed(state) emitted
    │
    ├──► NarrativeManager._on_state_changed(state)
    │       └── _calculate_tone_for_scene(current_scene_index, state)
    │       └── scene_text_changed.emit(scene_id, tone_string)
    │               │
    │               ├──► TextComponentBase._on_tone_changed(scene_id, tone)
    │               │       ├── Calculate state_id from tone
    │               │       ├── Select variant index for state_id (0-4)
    │               │       ├── Apply text variant (text content)
    │               │       ├── Apply visual overrides (emissive, pixelation, scanlines)
    │               │       └── Trigger fade transition (0.3s)
    │               │
    │               └──► SceneScript (office.gd, lobby.gd, etc.) _on_tone_changed()
    │                       └── Update scene-specific environment nodes
    │
    ├──► WorldviewController._on_state_changed(state)
    │       └── world_text_changed.emit(tone)
    │       └── world_state_changed.emit(state_id)
    │
    └──► RainController._on_state_changed(state)
            └── Update rain intensity (hope-inverse)
```

### Documents to Update

- [x] **This output:** `docs/PRD/154-gamestate-world-feedback-env-text.md`
- [ ] `docs/DESIGN/154-gamestate-world-feedback-env-text.md` — Plan phase output
- [ ] `docs/TASKS/154-gamestate-world-feedback-env-text.md` — Task breakdown
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md` — Update env text description
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` — Document 5-state env text system

---

## 4. Solution Comparison

### Approach A: Expand TextComponentBase to 5-State + Refactor Scene Scripts (Recommended)

**Description:**

A two-part change:

**Part 1 — TextComponentBase Expansion:**
- Add `_variant_index_for_state_id(state_id: int) → int` mapping: state 1→idx0, 2→idx1, 3→idx2, 4→idx3, 5→idx4
- Update `_on_state_changed()` to switch text content alongside emissive overrides (currently `_on_state_changed` calls `set_state_tier()` which only applies the variant, but `_on_tone_changed` only does emissive overrides — merge these into a single 5-state variant switch)
- Add `_apply_variant_for_state(state_id: int)` that picks the right TextVariantData entry
- Add tween-based fade transition: old text fades out (0.2s), new text fades in (0.2s) via modulating alpha on the Label3D
- No change to `TextVariantData` resource class — fields already sufficient

**Part 2 — Scene Script Refactoring:**
- Remove ad-hoc `_get_tone()` and `_set_environment_text(tone)` from each scene script
- Replace with `_get_state_text_variant(scene_id, state_id) → String` shared helper in SceneBase
- Scene scripts set static text (signage, graffiti) via TextComponentBase variant switching triggered by NarrativeManager's `scene_text_changed` signal
- Each scene connects to NarrativeManager's `scene_text_changed` for dynamic updates

**TextComponentBase subclass mapping update:**

| Subclass | Current Axis | Current 3-Tier Mapping | New 5-State Mapping |
|----------|-------------|----------------------|---------------------|
| PuddleText | hope | hope ≤ 3→low, 3-7→mid, ≥7→high | state_id 1→5 directly |
| LamppostText | will | will ≤ 3→low, 3-7→mid, ≥7→high | state_id → variant index (keep will-based for lamppost uniqueness) |
| NeonSign | conviction | conviction ≤ 3→low, 3-7→mid, ≥7→high | state_id → variant index (keep conviction-based) |
| RainText | hope | hope ≤ 3→low, 3-7→mid, ≥7→high | state_id → variant index |

Each subclass can keep its unique axis mapping for *tier calculation*, but the variant selection uses the state_id from that axis's tier range mapped to 5 states. However, since the existing axes (hope, will, conviction) are 0-10, mapping to 5 states requires a new approach:

```gdscript
# New 5-state tier calculation in TextComponentBase
func _calculate_state_id(state: Dictionary) -> int:
    var hope_val: float = state.get("hope", 5.0)
    return _hope_to_state_id(hope_val)  # 1-5

static func _hope_to_state_id(hope: float) -> int:
    if hope <= 2.0: return 1
    elif hope <= 4.0: return 2
    elif hope <= 6.0: return 3
    elif hope <= 8.0: return 4
    else: return 5

func _variant_index_for_state_id(state_id: int) -> int:
    return clampi(state_id - 1, 0, 4)  # state 1→0, 5→4
```

Subclasses that use alternative axes (will for LamppostText, conviction for NeonSign) can override `_calculate_state_id()` to map their axis to 1-5 independently.

**Transition handling:**
- Add `@export var transition_duration: float = 0.3` to TextComponentBase
- On variant switch: create Tween, fade modulate.a from 1→0, swap text, fade 0→1
- Use modulate instead of visible toggle for smooth visual

**Pros:**
- **Complete solution** — Every text object in every scene gets 5 unique variants
- **Shared infrastructure** — TextComponentBase handles variant selection, scene scripts just place nodes
- **Dynamic updates** — Text components react to state changes mid-scene without scene script changes
- **Minimal scene script changes** — SceneBase gets the shared helper; individual scene scripts lose ad-hoc tone logic
- **Proven pattern** — The 3-variant system already works; extending to 5 is mechanical
- **Hemingway enforcement** — Each variant text content must pass the enforcer — variants make this explicit
- **Backward compatible** — Existing 3-variant resources still work (variants 0-2 map to states 1/3/5; states 2/4 fall back to nearest available)

**Cons:**
- New text content: 8 text objects × 2 new variants = 16 new pieces of authored text (Hemingway-formatted)
- New `.tres` files: ~8 new resource files to create (very_low and very_high variants)
- Transition tweens add complexity to what is currently a one-line text assignment
- Subclasses with alternative axes (LamppostText/will, NeonSign/conviction) need careful state_id derivation to maintain their unique behavior
- Scene .tscn files may need Inspector re-wiring if additional variant slots are added

**Risk:** Low — The existing structure is proven. This is a mechanical expansion of a working pattern.

**Effort:** 1-2 weeks (TextComponentBase expansion + 4 subclass updates + 8 new variant resources + 7 scene script refactors + tests)

---

### Approach B: Keep 3-Tier TextComponentBase — Add Scene-Level 5-State Mapping Only

**Description:**

Leave `TextComponentBase` at 3 tiers. Instead, expand only the scene scripts to handle 5-state text by adding 2 more condition branches to their existing `_configure_environmental_text()` methods.

Each scene script's `_configure_environmental_text()` would use the NarrativeManager's 5-state tone table to pick text, but directly assign `.text` properties rather than going through TextComponentBase.

Existing `TextComponentBase` components (LamppostText, PuddleText, etc.) continue to use 3 tiers for their visual properties (emissive color, pixelation), while scene scripts manually assign `.text` for each of the 5 states.

**Scene script pattern:**
```gdscript
func _configure_environmental_text() -> void:
    var tone := _get_tone_from_narrative_manager()
    match tone:
        "despair":     window_text.text = "Rain blurs the glass.\nYou can't see anything."
        "low":         window_text.text = "The city is grey.\nSame rain. Same night."
        "neutral":     window_text.text = "Rain on the glass.\nAnother night at the office."
        "buoyant":     window_text.text = "Raindrops shimmer.\nThe city is wet and alive."
        "hope":        window_text.text = "The city glitters.\nTonight could be different."
```

**Pros:**
- Minimal changes to TextComponentBase (keep 3-tier emissive/visual switching)
- Scene script changes are localized — each scene independently expanded
- No new `.tres` resource files needed
- No transition tween complexity
- Scene scripts remain the single source of truth for text content (easier to audit)

**Cons:**
- **No dynamic mid-scene updates** — Text is set once at scene load. State changes during a scene don't update text.
- **Duplicated logic** — Both TextComponentBase and scene scripts manage text state; relationship is unclear
- **TextComponentBase's `_on_tone_changed` becomes misleading** — It handles emissive only while text doesn't change
- **3-tier visual properties mismatch with 5-state text** — Emissive color changes at 3 levels while text changes at 5
- **Harder to maintain** — Each scene script has its own copy of 5 text variants; no shared infrastructure
- **TextComponentBase subclasses still only respond to 3 tiers** — LamppostText/puddle/neon/rain text content stuck at 3

**Risk:** Low-Medium — Less code change but creates an incomplete experience (visual properties at 3 tiers, text at 5 tiers).

**Effort:** 1 week (scene script expansions + tone lookup helper in SceneBase + tests)

---

### Approach C: Create New StateWorldLinker Autoload — Centralized Text Management

**Description:**

Create a new `StateWorldLinker` autoload that manages all environmental text centrally. Scene scripts register their text nodes with the linker at `_ready()`. The linker listens to `StateSystem.state_changed`, looks up the scene's tone from `NarrativeManager`, and pushes text variants to all registered nodes via a unified API.

```gdscript
# StateWorldLinker.gd
signal text_applied(node_path: String, text: String, tone: String)

var _scene_text_registry: Dictionary = {}  # {scene_id: {node_path: [variant_texts_5]}}
var _registered_nodes: Dictionary = {}     # {node_path: Node}

func register_text_node(scene_id: String, node: Node, variants: Array[String]) -> void:
    # variants[0] = despair text, variants[4] = hope text
    _scene_text_registry[scene_id][node.get_path()] = variants
    _registered_nodes[node.get_path()] = node

func _on_state_changed(state: Dictionary) -> void:
    var state_id: int = state.get("state_id", 3)
    var tone: String = NarrativeManager.get_tone_for_scene(current_scene, state_id)
    for node_path in _scene_text_registry.get(current_scene, {}):
        var variants: Array = _scene_text_registry[current_scene][node_path]
        var text: String = variants[state_id - 1]
        _registered_nodes[node_path].text = text
```

`TextComponentBase` is kept but used only for visual properties (emissive, pixelation) with 5-state support. Text content ownership moves to the linker.

**Pros:**
- **Centralized** — One autoload owns all environmental text, easy to audit and debug
- **Data-driven** — Variants can be loaded from JSON or Resource files, enabling content authors to edit text without touching GDScript
- **Dynamic updates** — Linker pushes updates on every state change
- **Clean separation** — Scene scripts only register nodes, not manage text; TextComponentBase handles visuals

**Cons:**
- **New autoload** on top of existing 5 (GameManager, GameState, StateSystem, NarrativeManager, AudioManager) — adds initialization complexity
- **Scene scripts must register** every text node — more boilerplate than current `_configure_environmental_text()`
- **Text variant data stored in GDScript arrays** — not in .tres resources. Content authors need to modify code
- **Two systems for text** — Linker owns content, TextComponentBase owns visuals. Risk of drift
- **Over-engineering** for a game with 8 text objects across 6 scenes — a centralized linker is disproportionate to the problem size
- **Godot's Label3D.text** is a simple string property; the linker adds a layer of abstraction that isn't needed when GDScript `match` blocks suffice

**Risk:** Medium — New autoload, new registration contract, new test surface. The added complexity exceeds the problem size.

**Effort:** 2-3 weeks (new autoload + registration API + scene script updates + TextComponentBase visual expansion + variant content data + tests)

---

### Recommendation

→ **Approach A (Expand TextComponentBase to 5-State + Refactor Scene Scripts)** because:

1. **Complete 5-state coverage** — Every text object gets 5 unique variants, covering the full emotional spectrum. No tier collapse.
2. **Dynamic mid-scene updates** — TextComponentBase already listens to `scene_text_changed`. Making it switch text content (not just emissive) is a mechanical change.
3. **Shared infrastructure** — Scene scripts use a common pattern. No ad-hoc tone logic. No duplicated variant mapping.
4. **Proven pattern** — The existing 3-variant TextComponentBase system works. Extending to 5 is a simple expansion of `_variant_index_for_tier()` → `_variant_index_for_state_id()`.
5. **Content authoring** — Variant text lives in `.tres` resource files (TextVariantData). Authors can edit text without touching GDScript.
6. **Subclass flexibility** — LamppostText (will), NeonSign (conviction), PuddleText (hope), RainText (hope) each override `_calculate_state_id()` to use their own axis for variant determination. The 5-state mapping in the base class provides a sensible default.

**Key design decisions for Approach A:**

1. `TextComponentBase._calculate_tier(state)` → becomes `_calculate_state_id(state) → int` returning 1-5.
2. `TextComponentBase._variant_index_for_tier(tier)` → becomes `_variant_index_for_state_id(state_id)` mapping 1→0, 2→1, 3→2, 4→3, 5→4.
3. `TextComponentBase._apply_variant(idx)` stays the same — it already reads `variant_data[idx]` from the exported array.
4. `variant_data` array expands from size 3 to size 5. Existing 3-variant resources work via fallback (states 2 and 4 use variants[1] and variants[3] if new resources not created).
5. `TextComponentBase._on_tone_changed()` merges with `_on_state_changed()` — both update text content and visual properties in a single call.
6. `transition_duration` exported variable added to TextComponentBase for fade-in/out tweens.
7. Scene scripts remove their `_get_tone()` / `_set_environment_text()` methods. Static text (screensaver, desktop deadline) stays in scene scripts; environmental text moves to TextComponentBase nodes.
8. SceneBase gets a helper `_get_tone_for_scene(scene_id: String) → String` that queries NarrativeManager.

**Why not Approach B?** No dynamic mid-scene updates means the environment is frozen at scene load. A player whose emotional state changes dramatically (e.g., going from Neutral to Despair from a dialogue choice) won't see the world respond until the next scene transition.

**Why not Approach C?** A centralized autoload is over-engineered for 8 text nodes. The existing TextComponentBase pattern with 5-variant expansion achieves the same result with less code, no new autoload, and no registration boilerplate.

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 Acceptance Criteria

| ID | Description | Verification |
|----|-------------|-------------|
| **AC1** | TextComponentBase selects from 5 variants based on state_id 1–5 | `set_state_tier("despair")` → variant[0]; state_id=5 → variant[4] |
| **AC2** | Every scene text object has at least 3 authored variants; targeting 5 for primary objects | Variant count in .tres files per object |
| **AC3** | Environmental text updates dynamically when state changes mid-scene | Inject state change → verify text node .text property updates within same frame |
| **AC4** | Text transitions use fade (0.2–0.4s) when switching variants | Visual verification or Tween capture in test |
| **AC5** | Fallback: if only 3 variants exist, states 2 (Low) and 4 (Buoyant) use nearest neighbor (1 and 5 respectively) | Set state_id=2 → variant[1] (not variant[0]) with 3-variant setup |
| **AC6** | LamppostText uses will axis for state determination; NeonSign uses conviction | Override `_calculate_state_id()` returns values based on correct axis |
| **AC7** | All text content passes Hemingway constraints (≤25 chars/sentence, ≤3 sentences) | HemingwayEnforcer.truncate() test per variant |
| **AC8** | Scene scripts use 5-state tone from NarrativeManager instead of ad-hoc logic | Scene script `_configure_environmental_text()` calls `_get_tone_for_scene()` |
| **AC9** | TextComponentBase _on_state_changed updates text content AND visual properties (emissive, pixelation, scanlines) | Verify both text and emissive change on signal |

### 5.2 Normal Path

1. Game starts in Office scene → `StateSystem.hope_despair = 0.0` (Neutral, state ID 3)
2. `TextComponentBase._ready()` → connects to state_changed signal → calls `_on_state_changed({hope: 5.0})`
3. `_calculate_state_id()` returns 3 → `_variant_index_for_state_id(3)` returns 2
4. `variant_data[2]` applied: window text = "Rain on the glass. Another night at the office." with neutral emissive
5. Player makes dialogue choice with effect `{\"hope_despair\": 4.0}` → slider moves to 4.0 (state ID 4, Buoyant)
6. `state_changed` fires → `TextComponentBase._on_state_changed()` → state_id=4 → variant index 3
7. Text content fades over 0.3s → "Raindrops shimmer on the glass. The city is wet and alive."
8. Emissive color shifts to warm gold, emissive_strength increases, pixel_factor decreases

### 5.3 Edge Cases

1. **Rapid state changes:** Multiple `state_changed` emissions in the same frame → only the last variant is applied. Tween is restarted rather than queued (cancel any active tween before starting a new one).

2. **variant_data array size mismatch:** If array has 4 elements (not 5), state_id=5 tries to access index 4 → clamped to `variant_data.size() - 1` via `clampi(idx, 0, variant_data.size() - 1)`.

3. **State change during active dialogue:** Text transitions should be deferred until dialogue ends to avoid visual disruption mid-conversation. Use the queuing pattern from Issue #50 DESIGN — `TextComponentBase` checks `dialogue_runner.is_active()` and defers updates.

4. **Scene transition during tween:** If a fade tween is in progress when a scene unloads, the tween node is freed. Ensure Tween is created as a child of the text node (auto-freed on scene exit).

5. **Subclass with unique axis (LamppostText/will):** When will maps to a different state_id than hope, the env text may feel disconnected from the emotional narrative. This is intentional — lampposts represent resolve/willpower, while puddle text represents hope. The environment can feel non-uniform when different aspects of the player's psyche diverge.

6. **Empty variant data slots:** If a scene author frees a variant_data entry (leaving null), the `_apply_variant()` check `if not data: return` prevents crashes.

### 5.4 Failure Paths

1. **NarrativeManager not found:** TextComponentBase falls back to `hope_to_state_id()` using StateSystem's hope value directly, bypassing the per-scene tone table.

2. **StateSystem not found:** TextComponentBase uses hope=5.0 (Neutral) as fallback. All env text defaults to neutral variant.

3. **All variant_data entries null:** TextComponentBase outputs empty string for text. The 3D label shows nothing.

4. **Hemingway violation in authored text:** Text is truncated at runtime by HemingwayEnforcer. Log warning in editor. The truncated text may not fit the intended emotional tone — authoring must validate with `scripts/hermes-verify-dialogue-schema.py` or similar.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #47 — StateSystem (autoload, 5-state slider, state_changed signal) | ✅ **Merged and wired** | **Low** — StateSystem exists and provides the state source |
| Issue #50 — 5-state tone tables in NarrativeManager | ✅ **Implemented in code** | **Low** — SCENE_TONES and _calculate_tone_for_scene() exist |
| Issue #45 — Narrative architecture (SceneBase, scene scripts, echo system) | ✅ **Merged** (PR #96) | **Low** — Scene scripts exist, ready for refactor |
| Issue #52 — Dialogue engine runtime (DialogueRunner) | ✅ **Merged** (PR #83) | **Low** — Not directly affected, but dialogue state changes trigger the feedback loop |
| Existing TextComponentBase + TextVariantData pattern | ✅ **Working in codebase** | **Low** — Proven 3-variant system to extend |
| Existing `.tres` variant files for 4 text types | ✅ **Exist** | **Low** — 3 per type, need 2 more each |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #56 — Story Content (script writing with 5-state env text) | **Blocked** — Authors need the 5 variant slots defined and .tres files created |
| Polish pass — visual tuning of 5-state emissive colors, pixel factor, scanlines per state | **Medium** — Can proceed after text content is authored |

### Preparation Needed

- [ ] **Audit all scene .tscn files** — Verify each environmental TextComponentBase node has a `variant_data` array exported with at least 3 entries. Add 2 additional empty slots for the 5-state expansion.
- [ ] **Author 16 new text variant strings** — 4 text types × 2 new variants (very_low, very_high). Each must pass Hemingway constraints.
- [ ] **Create 8 new `.tres` files** — 4 text types × 2 variant levels. Copy existing middle variant as template, modify text + visual params.
- [ ] **Verify NarrativeManager.SCENE_TONES completeness** — Ensure all 30 entries (6 scenes × 5 states) are populated.

---

## 7. Spike / Experiment (Mandatory — depth/deep)

### Spike 1: Tween-Based Text Transition — Is 0.3s Fade Enough?

**Question to Answer:**
When environmental text switches between state variants, what transition duration and style (fade, slide, dissolve) provides the best player experience without being distracting?

**Method:**
1. Create a minimal Godot test scene with a LoFiText3D node cycling through all 5 variant texts.
2. Test three transition modes:
   - (a) **Instant swap** — text changes on next frame (current behavior)
   - (b) **Fade** — modulate.a from 1.0→0.0 over T, swap text, 0.0→1.0 over T
   - (c) **Slide** — old text scrolls up, new text scrolls down, 0.5s overlap
3. Test at T = 0.1s, 0.2s, 0.3s, 0.5s for modes (b) and (c)
4. Run with `godot --headless --script tests/test_text_transition.gd` and measure:
   - Frame time impact (is the tween expensive?)
   - Visual completion time (when is the new text fully readable?)
5. Also test during an active dialogue — does text transition conflict with dialogue panel rendering?

**Expected Result:**
Instant swaps are acceptable for background text (lamppost, neon sign). Fade transitions at 0.2-0.3s are preferred for focal text (window text, store sign, ticket gate). Slide transitions feel too busy for a lo-fi, slow-paced narrative game.

**Impact on Approach:**
If fade transitions are adopted, add `@export var transition_duration: float = 0.3` to TextComponentBase. If instant swaps are the default with optional fade, make `transition_duration = 0.0` mean instant swap. If tween performance is a problem in headless mode, skip transitions during tests.

---

### Spike 2: Fallback Behavior — What Happens With 3 Variants in a 5-State World?

**Question to Answer:**
Not all scene objects will get 5 authored variants initially. When a TextComponentBase has only 3 variants but the state requires a 4th or 5th variant, what fallback mapping provides the most coherent experience?

**Method:**
1. Set up TextComponentBase with 3 variants (indexes 0=despair, 1=neutral, 2=hope)
2. Test three fallback strategies:
   - (a) **Closest index:** state 2 (Low) → variant[0] (despair), state 4 (Buoyant) → variant[2] (hope)
   - (b) **Nearest-neighbor:** state 2 → variant[0], state 4 → variant[2] — but scale emissive to match state (partial application)
   - (c) **Default to neutral:** state 2 or 4 → variant[1] (neutral) — safest, least representative
3. For each strategy, evaluate: does the text feel "wrong" at the boundary state?
4. Also test with 4 variants (missing state 2 or state 4) — does the single missing break immersion?

**Expected Result:**
Strategy (a) — closest available index — is the best balance. State 2 (Low) showing the despair variant is tonally closer than showing neutral. State 4 (Buoyant) showing the hope variant feels slightly optimistic but acceptable. The emissive color should still use the 5-state gradient even when text content falls back.

**Impact on Approach:**
Add `_closest_available_index(target_idx: int, available: int) → int` to TextComponentBase. When `variant_data.size() < 5`, remap the target state index to the closest available index. Apply visual overrides (emissive, pixelation) from the tone overrides system which always has 5 levels even if text content doesn't.

---

## 8. Implementation Plan

### Phase 1: TextComponentBase Expansion (Day 1-2)

1. **Refactor `_calculate_tier()` to `_calculate_state_id()` in TextComponentBase**
   - Return int 1-5 instead of String "low"/"mid"/"high"
   - Use `_hope_to_state_id(hope_val)` for the default implementation
   - Keep `_calculate_tier()` as a deprecated wrapper that delegates to `_calculate_state_id()`

2. **Add `_variant_index_for_state_id(state_id: int) → int`**
   - Mapping: state 1→0, 2→1, 3→2, 4→3, 5→4
   - Clamp to `variant_data.size() - 1` for fallback

3. **Merge `_on_state_changed()` and `_on_tone_changed()`**
   - `_on_state_changed(state)` → call `_on_tone_changed_from_state(state_id)`
   - `_on_tone_changed(scene_id, tone)` → derive state_id from tone string and apply variant
   - Both paths call `_apply_variant_for_state(state_id)` which sets text + emissive + visual props

4. **Add fade transition support**
   - `@export var transition_duration: float = 0.3`
   - In `_apply_variant_for_state()`, if transition_duration > 0: tween modulate.a from 1→0, swap text, 0→1
   - Cancel any running tween before starting new one

5. **Update subclass `_calculate_tier()` overrides to `_calculate_state_id()`**
   - `lamppost_text.gd`: will-based → `_will_to_state_id(will)`
   - `neon_sign.gd`: conviction-based → `_conviction_to_state_id(conviction)`
   - `puddle_text.gd`: hope-based → use base class default
   - `rain_text.gd`: hope-based → use base class default; keep the special-case emissive multiplier

6. **Add `_on_tone_changed_from_state(state_id: int)` in TextComponentBase**
   - Applies tone overrides (emissive color, emissive_strength) based on the tone for the current scene

### Phase 2: Variant Resource Creation (Day 3)

For each of the 4 text types (lamppost, puddle, neon, rain), create 2 new `.tres` variant files:

| Text Type | Existing Files (3) | New Files (2) |
|-----------|-------------------|---------------|
| Lamppost | `lamppost_text_shallow.tres`, `lamppost_text_middle.tres`, `lamppost_text_deep.tres` | `lamppost_text_very_low.tres`, `lamppost_text_very_high.tres` |
| Puddle | `puddle_text_shallow.tres`, `puddle_text_middle.tres`, `puddle_text_deep.tres` | `puddle_text_very_low.tres`, `puddle_text_very_high.tres` |
| Neon | `neon_sign_shallow.tres`, `neon_sign_middle.tres`, `neon_sign_deep.tres` | `neon_sign_very_low.tres`, `neon_sign_very_high.tres` |
| Rain | `rain_text_shallow.tres`, `rain_text_middle.tres`, `rain_text_deep.tres` | `rain_text_very_low.tres`, `rain_text_very_high.tres` |

Each new file copies the existing deep/shallow variant for the "most extreme" state, then adjusts:
- **very_low** (state 1): Most extreme visual degradation — high pixel_factor (~0.6), low color_bits (4), high scanlines (0.3), desaturated emissive color
- **very_high** (state 5): Most pristine visual — low pixel_factor (~0.2), high color_bits (16), low scanlines (0.08), bright emissive color

### Phase 3: Scene Script Refactoring (Day 4-5)

For each scene, replace ad-hoc `_get_tone()` / `_set_environment_text()` with:
1. Call `_get_tone_from_narrative_manager(scene_id)` in `_configure_environmental_text()`
2. Set initial text via TextComponentBase's `set_text_variant(state_id)` or rely on initial signal emission
3. Remove hardcoded tone logic (fear/neutral/defiant for lobby, tired/neutral/determined for bridge, etc.)

**SceneBase additions:**
```gdscript
func _get_tone_for_scene(scene_id: String) -> String:
    var nm: Node = get_node_or_null("/root/NarrativeManager")
    if not nm or not nm.has_method("_calculate_tone_for_scene"):
        return "neutral"
    var ss: Node = get_node_or_null("/root/StateSystem")
    if not ss:
        return "neutral"
    return nm._calculate_tone_for_scene(
        NarrativeManager.SCENE_ORDER.find(scene_id),
        ss.get_state()
    )
```

### Phase 4: Tests (Day 5-6)

Create `tests/test_env_text_5_state.gd` covering:

| TC | Description | Verifies |
|----|-------------|----------|
| TC1 | TextComponentBase with 5 variants → state_id=1 selects variant[0] | AC1 |
| TC2 | TextComponentBase with 3 variants → state_id=2 falls back to variant[1] | AC5 |
| TC3 | state_changed signal triggers text content update | AC3 |
| TC4 | state_changed signal triggers emissive update | AC9 |
| TC5 | LamppostText uses will axis for state determination | AC6 |
| TC6 | NeonSign uses conviction axis for state determination | AC6 |
| TC7 | All authored variant text passes Hemingway constraints (signage domain) | AC7 |
| TC8 | SceneBase._get_tone_for_scene() returns correct tone from NarrativeManager | AC8 |
| TC9 | Fade tween runs on variant switch when transition_duration > 0 | AC4 |
| TC10 | Rapid state changes apply only the last variant (tween restart) | Edge case |

### Phase 5: Scene .tscn Wiring Audit (Day 6)

- Open each scene in the Godot editor
- Verify each TextComponentBase node has `variant_data` array with 5 entries
- Re-order variant entries to match state_id order (index 0=state1, index 4=state5)
- Verify exported `transition_duration` is set (0.0 for background signs, 0.3 for focal text)

### Phase 6: Hemingway Validation & Polish (Day 7)

- Run `scripts/hermes-verify-dialogue-schema.py` or equivalent against all variant text
- Verify no text exceeds Hemingway constraints
- Tune emissive colors for each state's emotional tone:
  - State 1 (Despair): Desaturated, blue-grey tint, low strength
  - State 2 (Low): Muted warm, dim
  - State 3 (Neutral): Standard amber warm
  - State 4 (Buoyant): Brighter gold, medium strength
  - State 5 (Hope): Bright warm-white, high strength
