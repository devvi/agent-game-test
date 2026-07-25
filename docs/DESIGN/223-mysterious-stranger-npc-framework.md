# Design: #223 — 神秘人角色框架 — 全场景NPC系统 (Mysterious Stranger NPC Framework)

> Parent Issue: #223
> Agent: plan-agent
> Date: 2026-07-25

---

## 1. Architecture Overview

### Core Idea

Implement a **full-scene Mysterious Stranger NPC framework** where the Stranger appears in every scene (office → lobby → store → bridge → underpass → subway_station) with different forms, dialogue variants tied to hallucination level (≥3 variants), and subtle visual changes (Decal color / text). The underpass scene hosts a **three-layer truth dialogue tree** (AC1 Shallow, AC2 Middle, AC3 Deep) as the narrative climax, while other scenes feature shorter conditional encounters that feed flags into the underpass dialogue and ending determination.

### Data Flow

```
Game Start (playthrough_count += 1)
    │
    ├──► Office: Stranger visible outside window (silhouette/reflection)
    │       └──► No direct interact — sets flag via environment text
    │
    ├──► Lobby: Stranger first meeting (existing lobby_stranger.dialogue)
    │       ├──► hope/conviction/will determine Stranger's opening line
    │       ├──► Expanded: hope ≥ 7 → stranger_high_hope dialogue variant
    │       ├──► Expanded: conviction ≤ 4 → stranger_low_conviction variant
    │       └──► Sets: met_stranger, lobby_hope_high, lobby_low_conviction
    │
    ├──► Store: Stranger appears outside store window (reflection)
    │       ├──► Conditional dialogue: "Looking out" → flag stranger_store_glimpse
    │       └──► Sets: store_stranger_seen flag for underpass cross-ref
    │
    ├──► Bridge: Stranger stands at far railing
    │       ├──► Conditional dialogue: calls out → flag stranger_bridge_call
    │       ├──► Hallucination level modulates text: higher = more distorted
    │       └──► Sets: bridge_stranger_encountered flag
    │
    ├──► Underpass: Three-layer truth dialogue tree (AC1/AC2/AC3)
    │       ├──► AC1 Shallow: 3 paths (acknowledge/deny/silent) → ending direction
    │       ├──► AC2 Middle: cross-scene flag combinations + extreme-state variants
    │       ├──► AC3 Deep: meta-narrative layer (playthrough_count ≥ 2)
    │       └──► Visual: Decal color shifts with hallucination level
    │
    └──► Subway Station: Decisive Stranger behavior
            ├──► Ending dialogue reflects ALL prior encounters
            ├──► Meta-aware ending if stranger_revealed flag set
            └──► Stranger Decal/appearance: final form based on accumulated flags
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| NPC placement model | Pre-placed per-scene scene node instances | Each scene has a unique layout; a single following-NPC system would be more complex. Pre-place Stranger-specific Area3D/Marker3D per scene. |
| Hallucination-linked visual variant | `NarrativeManager.get_hallucination_level()` drives Stranger Decal color via gradient | Hallucination system already exists (Issue #214). Reusing it avoids new state machinery. Color gradient: blue (low hallucination) → red (high hallucination). |
| Scene-specific vs global dialogue file | Per-scene .dialogue files (office_stranger, lobby_stranger, store_stranger, bridge_stranger, underpass_stranger_echo) | godot_dialogue_manager .dialogue format supports condition evaluation via StateSystem. Single-file approach for underpass (three-layer tree) but separate files for other scenes to keep each manageable. |
| Cross-scene flag routing | All flags stored in StateSystem via NarrativeManager.set_flag() | Existing infrastructure already handles flag persistence. No new flag-passing mechanism needed. |
| Ending decisive behavior | `NarrativeManager.determine_ending()` enhanced with `stranger_revealed`, `stranger_meta_accepted` flags | Existing ending determination already 3-way. Add Stranger-specific flag check before fallthrough. |
| Dialogue variant count | 3 variants per scene + special ending variant | Matches Issue AC: "对话随幻觉等级变化至少3个变体". Hallucination level 0–3 → variant A, 4–6 → variant B, 7–10 → variant C. |

---

## 2. Engine Layer 变更

### State Additions

```
New flags (in StateSystem, via NarrativeManager.set_flag()):
{
  stranger_office_glimpsed: bool,   // Seen Stranger at office window
  stranger_store_glimpse: bool,     // Seen Stranger at store reflection
  stranger_bridge_call: bool,       // Encountered Stranger on bridge
  stranger_met_lobby: bool,         // Talked to Stranger in lobby (existing: met_stranger)
  lobby_hope_high: bool,            // High hope variant triggered in lobby
  lobby_low_conviction: bool,       // Low conviction variant in lobby
  stranger_hinted_meta: bool,       // Stranger hinted at meta-truth in lobby
  store_stranger_seen: bool,        // Store reflection encounter
  bridge_stranger_encountered: bool,// Bridge call encounter
  stranger_revealed: bool,          // AC3 meta-reveal happened
  stranger_meta_accepted: bool,     // Player accepted meta-reveal
  is_new_game_plus: bool,           // Set by underpass.gd for AC3
}
```

### Game Loop Changes (`narrative_manager.gd`)
- New `get_scene_stranger_flags(scene_id: String) → Dictionary`: returns all Stranger-related flags for a given scene (used by dialogue conditions)
- New `get_hallucination_variant(scene_id: String, base_count: int) → int`: returns hallucination-driven variant index (0/1/2 based on hallucination level thresholds)
- Enhanced `determine_ending()`: check `stranger_revealed` flag — if set, return `keep_walking_meta` / `turn_back_meta` / `stay_meta` suffixes

### GameManager (`game_manager.gd`)
- Already implemented: `playthrough_count`, `get_playthrough_count()`, `start_game()` increment
- No new changes needed to GameManager — existing `set_flag()` / `has_flag()` / `get_slider()` suffice

---

## 3. Scene Layer 变更

> 场景脚本、NPC 节点、交互区域

### Office — NEW: Stranger Window Silhouette

| Element | Type | Description |
|---------|------|-------------|
| `StrangerWindowReflection` | Label3D / Decal | Text: "A silhouette stands outside. / Rain coats their shoulders." Visible from window area. |
| `window_side_trigger` | Area3D | Click to examine window — short flavor text, sets `stranger_office_glimpsed` flag |
| `StrangerDecal` | Decal | Subtle colored decal on window glass; color shifts with hallucination level |

**Dialogue:** No full dialogue — short environmental flavor text with flag set. Variant based on hallucination level (3 variants).

### Lobby — EXPAND existing

| Change | Detail |
|--------|--------|
| Stranger dialogue expansion | Add `stranger_high_hope` / `stranger_low_conviction` / `stranger_dejavu_deep` nodes (already in lobby_stranger.dialogue backup) |
| Hallucination variant | Stranger spotlight text gets an additional line modulated by hallucination level |
| Decal/Visual | Existing `StrangerSpotlight` Label3D text color shifts with hallucination |

### Store — NEW: Stranger Storefront Reflection

| Element | Type | Description |
|---------|------|-------------|
| `StrangerStoreReflection` | Label3D | Text: "A face in the glass / Not your own." Visible near storefront window. |
| `store_stranger_trigger` | Area3D | Click to examine — short dialogue starts `store_stranger.dialogue` |
| `StrangerDecal` | Decal | Subtle colored reflection on store glass |

**Dialogue:** `dialogues/store_stranger.dialogue` — 3 hallucination variants, sets `store_stranger_seen` flag.

### Bridge — NEW: Stranger at Far Railing

| Element | Type | Description |
|---------|------|-------------|
| `StrangerBridgeFigure` | Label3D | Text: "A figure at the railing. / They turn. / You can't see their face." |
| `bridge_stranger_trigger` | Area3D | Click to interact — short dialogue starts `bridge_stranger.dialogue` |
| `StrangerDecal` | Decal | Colored silhouette on bridge surface |

**Dialogue:** `dialogues/bridge_stranger.dialogue` — 3 hallucination variants, sets `bridge_stranger_encountered` flag.

### Underpass — REWRITE existing

| Change | Detail |
|--------|--------|
| Three-layer dialogue tree | Ref: docs/DESIGN/59-mysterious-stranger-npc.md — AC1/AC2/AC3 in single file |
| Hallucination visual | `StrangerEchoText` color shifts: low=white, mid=cyan, high=red-tinted |
| Extreme-state flags | Already implemented in underpass.gd: `underpass_hope_high`, `underpass_hope_low` |
| AC3 meta flag | Already implemented in underpass.gd: `is_new_game_plus` via playthrough_count |

### Subway Station — EXPAND existing

| Change | Detail |
|--------|--------|
| Meta-aware ending nodes | `kw_stranger_meta`, `tb_stranger_meta`, `st_stranger_meta` (already in backup) |
| Accumulated flag check | Ending dialogue shows different version based on how many Stranger encounters happened |
| Final visual | Stranger Decal reaches final form (brightest color, indicating narrative resolution) |

---

## 4. Data Layer 变更

### New Dialogue Files

| File | Type | Est. Lines |
|------|------|-----------|
| `dialogues/store_stranger.dialogue` | **New** | ~40 |
| `dialogues/bridge_stranger.dialogue` | **New** | ~40 |

### Existing Dialogue Files

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `dialogues/underpass_stranger_echo.dialogue` | **Modified** | Expand from ~60 to ~176 lines (already done in live file). Add hallicinatino-level variant routing for ending path selection. | +20 |
| `dialogues/lobby_stranger.dialogue` | **Modified** | Add hallucination-aware variants to exitsing nodes (3 variants per dialogue path). | +30 |
| `dialogues/subway_ending.dialogue` | **Modified** | Add meta-aware ending dialogue nodes for each path. Connect via `StateSystem.has_flag("stranger_revealed")` condition. | +30 |

### GDScript Files

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `gdscripts/office.gd` | **Modified** | Add StrangerWindowReflection trigger, Decal setup, hallucination color update. | +15 |
| `gdscripts/store.gd` | **Modified** | Add store_stranger_trigger, reflection text, hallucination Decal. | +15 |
| `gdscripts/bridge.gd` | **Modified** | Add bridge_stranger_trigger, figure text, hallucination Decal. | +15 |
| `gdscripts/lobby.gd` | **Modified** | Add hallucination visual update to StrangerSpotlight. | +5 |
| `gdscripts/underpass.gd` | **Modified** | Expand extreme-state flag setting to include hallucination level. Add Decal color update. | +10 |
| `gdscripts/subway_station.gd` | **Modified** | Add meta-ending path check, accumulated flags -> StrangerFinalText. | +15 |
| `gdscripts/narrative_manager.gd` | **Modified** | Add `get_hallucination_variant()`, `get_scene_stranger_flags()`, enhanced `determine_ending()`. | +25 |

### Scene Files (.tscn)

| File | Type | Change |
|------|------|--------|
| `scenes/office/office.tscn` | **Modified** | Add StrangerWindowReflection node, StrangerDecal, interaction trigger |
| `scenes/store/convenience_store.tscn` | **Modified** | Add StrangerStoreReflection node, StrangerDecal, interaction trigger |
| `scenes/bridge/bridge.tscn` | **Modified** | Add StrangerBridgeFigure node, StrangerDecal, interaction trigger |
| `scenes/lobby/lobby.tscn` | **Modified** | Add StrangerDecal to existing StrangerSpotlight |
| `scenes/underpass/underpass.tscn` | **Modified** | Add StrangerDecal to StrangerEchoTrigger area |
| `scenes/subway_station/subway_station.tscn` | **Modified** | Add final StrangerDecal to StrangerFinalText area |

### Documentation

| File | Change | Est. Lines |
|------|--------|-----------|
| `docs/GAME_DESIGN/06-NARRATIVE.md` | Update Section 6 with full-scene framework, per-scene table, hallucination visual system | +40 |

### Hallucination → Decal Color Mapping

```gdscript
# In NarrativeManager or a new helper

const STRANGER_DECAL_COLORS: Dictionary = {
    0: Color(0.5, 0.7, 1.0, 0.3),  # Low hallucination — blue-tinted, faint
    1: Color(0.3, 0.8, 1.0, 0.4),  # Mid-low — cyan
    2: Color(1.0, 1.0, 1.0, 0.5),  # Neutral — white
    3: Color(1.0, 0.7, 0.3, 0.5),  # Mid-high — orange
    4: Color(1.0, 0.2, 0.2, 0.6),  # High hallucination — red-tinted, more visible
}

static func get_stranger_decal_color(hallucination_level: int) -> Color:
    var idx: int = clampi(hallucination_level / 2, 0, 4)
    return STRANGER_DECAL_COLORS[idx]
```

---

## 5. Render / Visual Layer 变更

> Decal、Label3D 颜色、视觉效果

### Stranger Decal System

Each scene with a Stranger appearance gets a `Decal` node with:
- A subtle semi-transparent humanoid silhouette texture
- Color that shifts with hallucination level (blue → cyan → white → orange → red)
- Opacity that increases slightly with hallucination level (0.3 → 0.6)

The Decal is placed at a scene-specific position:
- **Office:** On the window glass (visible from desk area)
- **Lobby:** Near the entrance (existing StrangerSpotlight area)
- **Store:** On the storefront window glass
- **Bridge:** On the bridge railing
- **Underpass:** On the tunnel wall near StrangerEchoTrigger
- **Subway Station:** On the platform wall near StrangerFinalText

### Label3D Text Color Modulation

Stranger-related Label3D text color shifts with hallucination level using the same color mapping.

---

## 6. Input / UI Layer 变更

> 输入处理、UI 元件

### New Interaction Zones

| Scene | Zone Name | Type | Behavior |
|-------|-----------|------|----------|
| Office | `StrangerWindowTrigger` | Area3D | Click → flavor text → sets `stranger_office_glimpsed` |
| Store | `StrangerStoreTrigger` | Area3D | Click → starts `store_stranger.dialogue` → sets `store_stranger_seen` |
| Bridge | `StrangerBridgeTrigger` | Area3D | Click → starts `bridge_stranger.dialogue` → sets `bridge_stranger_encountered` |

All follow the existing pattern from underpass.gd / lobby.gd: `input_event.connect(_on_trigger_input)`.

---

## 7. Test Layer 变更

### Test Structure

| File | Type | Target |
|------|------|--------|
| `tests/test_stranger_dialogue.gd` | **Exists** | AC1/AC2/AC3 dialogue condition evaluation — expand to cover new scene flags |
| `tests/test_stranger_scene.gd` | **Exists** | Underpass integration — expand to cover hallucination visual & ending meta |
| `tests/test_stranger_full_scene.gd` | **New** | Full-scene framework: office/store/bridge Stranger encounter flags and routing |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Office Stranger window | ✅ | ≥2 (hallucination variants) | ✅ |
| Store Stranger reflection | ✅ | ≥2 (hallucination variants) | ✅ |
| Bridge Stranger figure | ✅ | ≥2 (hallucination variants) | ✅ |
| Lobby expanded flags | ✅ | ≥2 | ✅ |
| Underpass three-layer tree | ✅ | ≥4 | ✅ |
| Subway meta ending | ✅ | ≥2 | ✅ |
| Hallucination Decal color | ✅ | ≥2 (boundary: level 0, 10) | ✅ |
| Cross-scene flag accumulation | ✅ | ≥2 (partial vs full encounter) | ✅ |
| playthrough_count persistence | ✅ | ≥2 | ✅ |

### Test Cases

#### TC1–TC14: Underpass Dialogue Tree (from docs/DESIGN/59-mysterious-stranger-npc.md)

All 14 test cases from the existing DESIGN doc apply directly. Already implemented in `tests/test_stranger_dialogue.gd` and `tests/test_stranger_scene.gd` against backup JSON files.

#### TC15–TC17: Full-Scene Framework

**TC15: Office Stranger window triggers flag**
- Type: Integration / Normal
- Setup: Load office scene. `stranger_office_glimpsed = false`.
- Steps: Click window area.
- Assert: Flavor text displayed. `stranger_office_glimpsed = true`.
- Verification: Check flag in StateSystem.

**TC16: Store Stranger reflection dialogue**
- Type: Integration / Normal
- Setup: Load store scene. `store_stranger_seen = false`.
- Steps: Click storefront reflection trigger.
- Assert: `store_stranger.dialogue` starts. After completion, `store_stranger_seen = true`.
- Verification: Check dialogue loaded. Check flag set.

**TC17: Bridge Stranger encounter dialogue**
- Type: Integration / Normal
- Setup: Load bridge scene. `bridge_stranger_encountered = false`.
- Steps: Click bridge stranger trigger.
- Assert: `bridge_stranger.dialogue` starts. After completion, `bridge_stranger_encountered = true`.
- Verification: Check dialogue loaded. Check flag set.

#### TC18–TC20: Hallucination Variants

**TC18: Hallucination level drives dialogue variant**
- Type: Unit / Normal
- Setup: Mock hallucination_level = 0, 5, 10.
- Steps: Call `NarrativeManager.get_hallucination_variant("bridge", 3)`.
- Assert: Returns 0 for level 0–3, 1 for 4–6, 2 for 7–10.
- Verification: Check variant index matches hallucination threshold bucket.

**TC19: Hallucination level drives Decal color**
- Type: Unit / Edge
- Setup: Mock hallucination_level = 0, 2, 4, 6, 8, 10.
- Steps: Call `get_stranger_decal_color(level)`.
- Assert: Returns blue for low levels, red for high levels, with intermediate colors.
- Verification: Check color values match expected gradient.

**TC20: Decal color updates on state change**
- Type: Integration / Normal
- Setup: Underpass scene loaded. Hallucination_level = 3.
- Steps: Trigger state change that raises hope by 4. Check Decal color.
- Assert: Decal color updates to match new hallucination level.
- Verification: Capture color before/after, verify change.

#### TC21–TC23: Subway Ending with Accumulated Flags

**TC21: All Stranger flag status affects ending Stranger text**
- Type: Integration / Normal
- Setup: All 4 stranger encounter flags set (`stranger_office_glimpsed`, `stranger_met_lobby`, `store_stranger_seen`, `bridge_stranger_encountered`).
- Steps: Reach subway ending. Examine StrangerFinalText.
- Assert: Text mentions "you've been there all along" or equivalent meta-reference.
- Verification: Check modified text vs default (partial or no flags).

**TC22: Meta-reveal unlock in ending**
- Type: Integration / Normal
- Setup: `stranger_revealed = true`. Ending thresholds met for keep_walking.
- Steps: Navigate to keep_walking ending dialogue.
- Assert: `kw_stranger_meta` node shown. Text contains "下次再见自己".
- Verification: Check node ID in dialogue history.

**TC23: No meta ending on first playthrough with no encounters**
- Type: Integration / Edge
- Setup: `playthrough_count = 1`. No Stranger flags set.
- Steps: Reach subway ending. Check Stranger dialogue.
- Assert: Default ending dialogue shown. No meta text.
- Verification: Check default `kw_stranger` node used.

#### TC24–TC25: Regression

**TC24: Existing lobby stranger unchanged**
- Type: Regression / Normal
- Setup: Load lobby scene. No special flags.
- Steps: Interact with lobby Stranger.
- Assert: All existing nodes (`stranger_greet`, `stranger_talk`, etc.) work as before. New nodes only appear with correct conditions.
- Verification: Dialogue tree traversal matches pre-expansion behavior.

**TC25: All pre-existing tests pass**
- Type: Regression / Normal
- Setup: Run test suite.
- Steps: Execute all tests.
- Assert: No regressions. All tests pass.
- Verification: Test runner output.

---

## 8. Files Changed (按層匯總)

### Scene Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/office.gd` | Add window trigger handler, Decal update | +15 |
| `gdscripts/store.gd` | Add store stranger trigger, reflection handler | +15 |
| `gdscripts/bridge.gd` | Add bridge stranger trigger, figure handler | +15 |
| `gdscripts/lobby.gd` | Add hallucination visual update | +5 |
| `gdscripts/underpass.gd` | Expand extreme-state flags + Decal color | +10 |
| `gdscripts/subway_station.gd` | Add meta-ending check, accumulated flags text | +15 |
| `scenes/office/office.tscn` | Add Stranger nodes | +N |
| `scenes/store/convenience_store.tscn` | Add Stranger nodes | +N |
| `scenes/bridge/bridge.tscn` | Add Stranger nodes | +N |
| `scenes/lobby/lobby.tscn` | Add Decal to StrangerSpotlight | +N |
| `scenes/underpass/underpass.tscn` | Add Decal to StrangerEchoTrigger | +N |
| `scenes/subway_station/subway_station.tscn` | Add final Decal | +N |

### Data Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `dialogues/store_stranger.dialogue` | **New** | +40 |
| `dialogues/bridge_stranger.dialogue` | **New** | +40 |
| `dialogues/lobby_stranger.dialogue` | Expand with hallucination variants | +30 |
| `dialogues/underpass_stranger_echo.dialogue` | Expand hallucination routing | +20 |
| `dialogues/subway_ending.dialogue` | Meta-ending nodes with conditions | +30 |

### Engine Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/narrative_manager.gd` | Add hallucination variant helper, stranger flag query, enhanced ending | +25 |

### Documentation

| File | Change | Est. Lines |
|------|--------|-----------|
| `docs/GAME_DESIGN/06-NARRATIVE.md` | Update Section 6 with full-scene framework | +40 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_stranger_dialogue.gd` | Expand existing (add TC15–TC25) | +60 |
| `tests/test_stranger_scene.gd` | Expand existing integration tests | +40 |
| `tests/test_stranger_full_scene.gd` | **New** — full-scene framework tests | +100 |

### Summary

| Category | New Files | Modified Files | Total Est. Lines |
|----------|-----------|---------------|-----------------|
| Scene scripts | 0 | 6 | +75 |
| Scene files (.tscn) | 0 | 6 | ~+60 |
| Dialogue files | 2 | 3 | +160 live / ~+200 backup JSON |
| Engine scripts | 0 | 1 | +25 |
| Documentation | 0 | 1 | +40 |
| Tests | 1 | 2 | +200 |
| **Total** | **3** | **19** | **~+600** |

---

## 9. Verification Checklist

- [ ] **Office Stranger window:**
  - [ ] Label3D shows silhouette text at office window
  - [ ] Click sets `stranger_office_glimpsed` flag
  - [ ] Text has 3 hallucination variants

- [ ] **Lobby Stranger expanded:**
  - [ ] `stranger_high_hope` node accessible when hope ≥ 7
  - [ ] `stranger_low_conviction` node accessible when conviction ≤ 4
  - [ ] `stranger_dejavu_deep` accessible when both high
  - [ ] Existing nodes unchanged

- [ ] **Store Stranger reflection:**
  - [ ] Label3D shows reflection text at storefront
  - [ ] Click starts `store_stranger.dialogue`
  - [ ] `store_stranger_seen` flag set after dialogue
  - [ ] Dialogue has 3 hallucination variants

- [ ] **Bridge Stranger figure:**
  - [ ] Label3D shows figure text at far railing
  - [ ] Click starts `bridge_stranger.dialogue`
  - [ ] `bridge_stranger_encountered` flag set after dialogue
  - [ ] Dialogue has 3 hallucination variants

- [ ] **Underpass three-layer tree:**
  - [ ] AC1: 3 paths visible on first playthrough (acknowledge/deny/silent)
  - [ ] AC1: Effects applied correctly per path (+stat/–stat/neutral)
  - [ ] AC2: screensaver_echo_heard variant shown when flag set
  - [ ] AC2: low conviction variant shown when conviction ≤ 3
  - [ ] AC2: high/low hope extreme variants shown
  - [ ] AC2: Office/store flag cross-references shown
  - [ ] AC3: Meta entry visible only when `is_new_game_plus = true`
  - [ ] AC3: Meta reveal text contains "我就是你" or equivalent
  - [ ] AC3: Meta choice sets `stranger_revealed` or `stranger_meta_accepted`

- [ ] **Decal color system:**
  - [ ] Six scenes each have StrangerDecal node
  - [ ] Color shifts properly with hallucination level (blue→red gradient)
  - [ ] Opacity increases with higher hallucination levels

- [ ] **Subway station ending:**
  - [ ] `kw_stranger_meta` shown when `stranger_revealed = true` on keep_walking path
  - [ ] `tb_stranger_meta` shown on turn_back path with meta
  - [ ] `st_stranger_meta` shown on stay path with meta
  - [ ] Default ending text unchanged when no meta
  - [ ] Accumulated flags modulate final Stranger text

- [ ] **Cross-scene flag accumulation:**
  - [ ] Underpass AC2 correctly reads `stranger_office_glimpsed`, `store_stranger_seen`, `bridge_stranger_encountered`
  - [ ] Subway ending references number of accumulated encounters

- [ ] **Regression:**
  - [ ] All existing lobby/guard/clerk/homeless dialogues unchanged
  - [ ] Pre-existing tests still pass
  - [ ] Scene sequence unchanged (office→lobby→store→bridge→underpass→subway)
  - [ ] Hemingway constraints retained (≤25 chars/sentence, ≤3 sentences/node)
