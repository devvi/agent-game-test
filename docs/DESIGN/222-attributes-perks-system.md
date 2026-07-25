# Design: #222 — 属性与Perk系统 (Attributes & Perks System)

> Parent Issue: #222
> Agent: game-plan-agent
> Date: 2026-07-25
> PRD Reference: `docs/PRD/222-attributes-perks-system.md` (research branch)
> Recommended Approach: **Approach A — Independent AttributeSystem Autoload + PerkManager** (adopted)

---

## 1. Architecture Overview

### Core Idea

Create an **independent AttributeSystem autoload** that manages three character attributes (Insight/Empathy/Tenacity), attribute growth from NPC interactions, and a Perk system with unlock conditions and passive bonuses. The system lives as a separate concept layer from StateSystem (which manages emotional/mood states) and exposes its data to godot_dialogue_manager via `using AttributeSystem` for both condition checks and mutation effects.

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AttributeSystem (autoload)                           │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │  insight: int (1-10)                                           │     │
│  │  empathy: int (1-10)                                           │     │
│  │  tenacity: int (1-10)                                          │     │
│  │  perk_points: int (unused pool)                                │     │
│  │  unlocked_perks: Array[String]   (perk IDs)                    │     │
│  │                                                                │     │
│  │  ┌────────────────────────────────────────────────────────┐   │     │
│  │  │  PerkManager (internal component)                       │   │     │
│  │  │  - perk_definitions: Dictionary (by ID)                 │   │     │
│  │  │  - check_unlocks() → Array[String] (newly unlocked IDs) │   │     │
│  │  │  - get_active_effects() → Dictionary (modifier map)     │   │     │
│  │  └────────────────────────────────────────────────────────┘   │     │
│  │                                                                │     │
│  │  Signals:                                                      │     │
│  │  - attribute_changed(attr_name, old_value, new_value)          │     │
│  │  - perk_unlocked(perk_id, perk_name)                           │     │
│  │  - growth_offered(available_attrs: Array[String])              │     │
│  └────────────────────────────────────────────────────────────────┘     │
└──────────────────────────┬───────────────────────────────────────────────┘
                           │
              ┌────────────┼────────────────┐
              ▼            ▼                ▼
┌─────────────────┐ ┌──────────┐ ┌──────────────────┐
│  AttributePanel  │ │  Growth  │ │  SkillCheck      │
│  (CanvasLayer)   │ │  Prompt  │ │  Manager (#227)   │
│  - C key toggle  │ │  UI     │ │  - reads attr     │
│  - bar + value   │ │  popup  │ │  - applies perk   │
│  - perk display  │ │  dialog │ │    modifiers      │
└─────────────────┘ └──────────┘ └──────────────────┘
                           │
              ┌────────────┘
              ▼
┌──────────────────────────────────┐
│  NarrativeManager (#214)         │
│  - perk hallucination resistance │
└──────────────────────────────────┘
```

### Data Flow (NPC Dialogue → Attribute Growth)

```
NPC dialogue ends
    │
    ├──► NPCNode._on_dialogue_ended()
    │       └──► dialogue_completed.emit(npc_id)
    │
    ├──► AttributeGrowthController receives signal
    │       ├── Checks NPC type / dialogue context
    │       ├── Determines available growth options
    │       ├── Opens AttributeGrowthPrompt UI
    │       │       ├── Shows 1-3 attribute options (filtered by NPC type)
    │       │       ├── Player selects one (or times out / dismisses)
    │       │       └── Emits growth_selected(attr_name)
    │       │
    │       ├──► AttributeSystem.increase_attribute(attr_name)
    │       │       ├── Clamps to 1-10 range
    │       │       ├── Updates attribute value
    │       │       ├── Emits attribute_changed signal
    │       │       └── Runs PerkManager.check_unlocks()
    │       │               ├── Evaluates all locked perk conditions
    │       │               ├── Unlocks any newly satisfied perks
    │       │               └── Emits perk_unlocked signal
    │       │
    │       └──► AttributePanel updates (via signal)
    │               ├── Bar animation (tween width)
    │               ├── Value label update
    │               └── Perk unlock popup (if applicable)
    │
    └──► (StateSystem also records growth flag for persistence)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | **Approach A — Independent AttributeSystem Autoload** | Concept separation from StateSystem (mood vs traits); SRP; testability in headless mode; easy integration with dialogue system |
| Attribute range | `int` 1-10, initial 1 | Matches existing StateSystem convention (0-10); 1 = baseline human; 10 = mastery |
| Growth direction | **Unidirectional only** — attributes never decrease | Long-term growth vs mood state fluctuation; player choice patterns define character |
| Growth trigger | **NPC dialogue completion** — growth prompt after `dialogue_ended` | Natural feedback loop; NPC type filters available attributes |
| Perk definitions | **Hardcoded Dictionary** in MVP (no external Resource file) | Simpler to iterate during MVP; can extract to `.tres` later |
| Perk condition DSL | **Reuse DialogueConditionEvaluator pattern** — Dictionary-based conditions | Familiar format; can evaluate single-attr thresholds and compound conditions |
| Dialogue integration | `using AttributeSystem` — expose via godot_dialogue_manager | Same pattern as StateSystem; `if AttributeSystem.insight >= 3` in conditions, `do AttributeSystem.increase_attribute(...)` for mutations |
| Save/Load | **Independent serialization** in AttributeSystem | Separate from StateSystem's save dict; loaded alongside state |
| UI style | **Hopper minimal** — semi-transparent, amber/dark palette, matching status_bar | Visual consistency with existing UI system |
| Input binding | `C` key toggle (via InputMap action `toggle_attribute_panel`) | Existing InputMap pattern; add new action |

---

## 2. Component Specification

### 2.1 AttributeSystem.gd

**Path:** `gdscripts/attribute_system.gd`
**Type:** Node (autoload singleton, registered as `AttributeSystem`)
**Purpose:** Central attribute and perk state management

#### Properties

```gdscript
extends Node

# ── Attributes ──
var insight: int = 1:        # 1-10 range
    set(value):
        insight = clampi(value, 1, 10)
var empathy: int = 1:         # 1-10 range
    set(value):
        empathy = clampi(value, 1, 10)
var tenacity: int = 1:        # 1-10 range
    set(value):
        tenacity = clampi(value, 1, 10)

# ── Perk State ──
var perk_points: int = 0     # Unspent perk points (unused in MVP, reserved)
var unlocked_perks: Array[String] = []  # Array of perk IDs
var _perk_manager: PerkManager           # Internal component
var _growth_cooldowns: Dictionary = {}   # {npc_id: timestamp} anti-spam
```

#### Signals

```gdscript
signal attribute_changed(attr_name: String, old_value: int, new_value: int)
## Emitted when any attribute value changes.
## attr_name: "insight", "empathy", or "tenacity"

signal perk_unlocked(perk_id: String, perk_name: String)
## Emitted when a new perk is unlocked.
## perk_name is the display name (e.g. "Clear Mind")

signal growth_opportunity(available_attrs: Array[String], npc_id: String)
## Emitted when a growth opportunity is available after NPC dialogue.
## available_attrs: attributes the player may choose to increase
```

#### Public API

| Method | Signature | Description |
|--------|-----------|-------------|
| `get_attribute` | `(name: String) → int` | Returns current value of named attribute (0 if unknown) |
| `get_attributes` | `() → Dictionary` | Returns `{insight, empathy, tenacity}` snapshot |
| `increase_attribute` | `(name: String) → bool` | Increase attribute by 1. Returns false if already at 10 or invalid name |
| `get_perk_manager` | `() → PerkManager` | Returns the internal PerkManager reference |
| `get_active_perks` | `() → Array[String]` | Returns list of unlocked perk IDs |
| `has_perk` | `(perk_id: String) → bool` | Check if a specific perk is unlocked |
| `get_perk_modifiers` | `(check_type: String) → int` | Sum of all perk modifiers for a given check type (e.g. "insight_check", "hallucination_resist") |
| `get_hallucination_resistance` | `() → int` | Sum of hallucination resistance from perks (used by NarrativeManager) |
| `_offer_growth` | `(npc_id: String, available: Array[String]) → void` | Internal: emits growth_opportunity signal |
| `can_increase` | `(name: String) → bool` | Returns true if attribute exists and is below 10 |
| `get_attribute_names` | `() → Array[String]` | Returns `["insight", "empathy", "tenacity"]` |
| `reset` | `()` | Reset all attributes to 1, clear perks and perk_points |

#### Attribute Growth Rules

1. **Trigger:** After a dialogue completes (`NPCNode.dialogue_completed` signal), the GrowthController evaluates whether this NPC interaction qualifies for growth.
2. **Filtering:** Available attributes are filtered by NPC type/personality:
   - **Empathy-aligned NPCs** (e.g., store clerk, bartender): `["empathy", "insight"]`
   - **Tenacity-aligned NPCs** (e.g., homeless person on bridge): `["tenacity", "insight"]`
   - **Balanced NPCs** (e.g., lobby guard): `["insight", "empathy", "tenacity"]`
   - **Key narrative moments** (e.g., ending choices): may offer specific single-attribute growth
3. **Cooldown:** Each NPC has a growth cooldown (per-playthrough). Once you've grown from an NPC interaction, you cannot grow from that same NPC again in the same playthrough.
4. **Maximum:** When an attribute reaches 10, it is excluded from growth options. If all three are at 10, no growth prompt appears.
5. **Timeout:** If player doesn't choose within 60 seconds, prompt auto-dismisses — no growth applied.

### 2.2 PerkManager.gd

**Path:** `gdscripts/perk_manager.gd`
**Type:** Node (internal component of AttributeSystem, not standalone autoload)
**Purpose:** Perk definition storage, unlock condition evaluation, modifier queries

#### Perk Definition Structure

```gdscript
# Perk definition dictionary format
{
    "id": "clear_mind",                    # Unique identifier
    "name": "Clear Mind",                  # Display name
    "name_zh": "冷静头脑",                  # Chinese display name
    "description": "洞察检定 +1 加成",       # Effect description
    "icon": "res://assets/perks/clear_mind.png",  # Icon path (optional MVP)
    "condition": {                         # Unlock condition (DialogueConditionEvaluator DSL)
        "type": "attribute",
        "attr": "insight",
        "op": "gte",
        "value": 3
    },
    "effects": {                           # Passive effects
        "insight_check_bonus": 1,
        "hallucination_resist": 0,
        "dialogue_unlock": ""
    }
}
```

#### Condition Types Supported

| Type | Format | Example |
|------|--------|---------|
| Single attribute | `{"type": "attribute", "attr": "insight", "op": "gte", "value": 3}` | `insight >= 3` |
| Compound attribute | `{"type": "attribute_sum", "attrs": ["insight", "tenacity"], "op": "gte", "value": 8}` | `insight + tenacity >= 8` |
| Attribute + flag | `{"type": "and", "conditions": [attr_cond, flag_cond]}` | `empathy >= 5 and has_flag("chatted_with_clerk")` |
| Attribute + mood | `{"type": "and", "conditions": [attr_cond, mood_cond]}` | `tenacity >= 5 and StateSystem.hope_despair >= 0` |

#### Effect Types

| Effect Key | Type | Description | Example |
|------------|------|-------------|---------|
| `insight_check_bonus` | int | Bonus to insight-based skill checks | `+1` |
| `empathy_check_bonus` | int | Bonus to empathy-based skill checks | `+1` |
| `tenacity_check_bonus` | int | Bonus to tenacity-based skill checks | `+2` |
| `any_check_bonus` | int | Universal check bonus (all types) | `+1` |
| `hallucination_resist` | int | Reduces effective hallucination level | `2` |
| `hallucination_jitter_reduction` | float | Reduces hallucination offset multiplier | `0.5` (50% reduction) |
| `dialogue_unlock` | String | Dialogue node ID that becomes available | `"clerk_empathy_path"` |
| `npc_attitude_bonus` | int | Improves NPC starting attitude | `1` (one tier better) |

### 2.3 MVP Perk Definitions

| # | Perk ID | Name (EN) | Name (ZH) | Unlock Condition | Effects |
|---|---------|-----------|-----------|-----------------|---------|
| 1 | `clear_mind` | Clear Mind | 冷静头脑 | `insight >= 3` | `insight_check_bonus: 1` |
| 2 | `empathic_insight` | Empathic Insight | 敏锐直觉 | `empathy >= 3` | `dialogue_unlock: "npc_empathy_path"` |
| 3 | `night_walker` | Night Walker | 雨夜行者 | `tenacity >= 3` | `hallucination_resist: 2` |
| 4 | `lucid_gaze` | Lucid Gaze | 清澈目光 | `insight + tenacity >= 8` | `hallucination_jitter_reduction: 0.5` |
| 5 | `compassionate_heart` | Compassionate Heart | 仁心 | `empathy >= 5` | `npc_attitude_bonus: 1` |
| 6 | `unbreakable_will` | Unbreakable Will | 不屈意志 | `tenacity >= 5` | `tenacity_check_bonus: 2` |

#### Perk Routes

| Route Focus | Perks Unlocked | Narrative Theme |
|-------------|---------------|-----------------|
| **Insight** (洞察) | Clear Mind, Lucid Gaze (compound) | Seeing through illusion, understanding reality |
| **Empathy** (共情) | Empathic Insight, Compassionate Heart | Human connection, NPC relationships |
| **Tenacity** (坚韧) | Night Walker, Unbreakable Will | Endurance against hallucination, resilience |
| **Balanced** | Lucid Gaze (requires both insight + tenacity) | Rewards even distribution |

### 2.4 AttributePanel UI

**Path:** `scenes/ui/attribute_panel.tscn` + `gdscripts/attribute_panel.gd`
**Type:** CanvasLayer (instantiable, toggled by `C` key)

#### Visual Layout

```
┌────────────────────────────────────────────┐
│  ┌─ 属性 / ATTRIBUTES ─────────────────┐   │
│  │                                       │   │
│  │  洞察 Insight   ████████░░░░  7/10    │   │
│  │  共情 Empathy   ██████░░░░░░  6/10    │   │
│  │  坚韧 Tenacity  ████░░░░░░░░  4/10    │   │
│  │                                       │   │
│  │  ── Perks ──                         │   │
│  │  ✓ Clear Mind   洞察检定 +1          │   │
│  │  ✓ Night Walker 幻觉抵抗 +2          │   │
│  │  ✗ Lucid Gaze  洞察+坚韧 ≥ 8        │   │
│  │  ✗ Empathic Ins… 共情 ≥ 3           │   │
│  │                                       │   │
│  │  [C] 关闭 / Close                     │   │
│  └───────────────────────────────────────┘   │
└────────────────────────────────────────────┘
```

#### Styling Specifications

| Element | Style | Detail |
|---------|-------|--------|
| Panel background | Semi-transparent dark | `Color("#1a1a2e", 0.85)` — matches status_bar bg |
| Text color | Amber | `Color("#FFB000")` for labels |
| Value color | Gold | `Color("#FFD700")` for numbers |
| Bar fill (gradient) | Left→Right: dark→amber | `Color("#2A2A4A")` → `Color("#FFB000")` |
| Perk unlocked | Green checkmark | `Color("#4ade80")` ✓ |
| Perk locked | Dimmed text | `Color("#808080")` ✗ |
| Font | Same as status_bar | LoFi-style, pixel font |
| Border | None | Floats without frame, Hopper minimal |
| Position | Bottom-right corner | offset from edge: 20px |

#### Interaction

- **Toggle:** Press `C` key → show/hide. Same key closes.
- **Animation:** Bars animate width on attribute change (tween 0.3s, ease-out).
- **Perk unlock popup:** When new perk unlocks, a centered floating notification appears for 3 seconds, then auto-fades.
- **Hotkey:** `C` key bound to `toggle_attribute_panel` InputMap action.

### 2.5 AttributeGrowthPrompt UI

**Path:** `gdscripts/attribute_growth_prompt.gd` + `scenes/ui/attribute_growth_prompt.tscn`
**Type:** Popup / CanvasLayer (instantiated by GrowthController)

#### Visual Layout

```
┌────────────────────────────────┐
│  ┌─ 属性成长 ──────────────┐    │
│  │  选择一个属性提升 +1     │    │
│  │                         │    │
│  │  [🔍 洞察 Insight]     │    │
│  │     当前: 3 → 4        │    │
│  │                         │    │
│  │  [❤ 共情 Empathy]      │    │
│  │     当前: 5 → 6        │    │
│  │                         │    │
│  │  或按 ESC 跳过          │    │
│  └─────────────────────────┘    │
└────────────────────────────────┘
```

#### Behavior

1. Appears after `dialogue_completed` signal when growth opportunity is available
2. Shows up to 3 attribute options (filtered by NPC type and at-capacity status)
3. Player clicks or presses key 1/2/3 to select
4. Selection is disabled after 60 seconds → auto-dismiss
5. After selection: brief visual feedback (value animation), panel closes
6. Panel closes immediately if player moves or starts another interaction

---

## 3. Integration with Existing Systems

### 3.1 StateSystem Integration

AttributeSystem is a **separate autoload** — it does not modify StateSystem directly. However, they share the same save/load cycle:

- **Save:** `StateSystem.save_state_to_file()` remains unchanged. AttributeSystem saves its own file: `user://save_states/attributes_<slot>.json`
- **Load:** Both systems restore independently.
- **Cross-references in dialogue:** Both are available via `using StateSystem` and `using AttributeSystem` in godot_dialogue_manager.
- **Mood + attribute conditions:** `[if StateSystem.hope >= 5 and AttributeSystem.empathy >= 3]` — fully supported by godot_dialogue_manager's AND expression.

### 3.2 NPCNode Integration

**Changes to `gdscripts/npc_node.gd`:**

```gdscript
# New signal (or extend existing)
signal dialogue_completed(npc_id: String)
# Already exists — used as growth trigger

# New export (optional — growth affinity mapping)
@export var growth_affinities: Array[String] = ["insight", "empathy", "tenacity"]
## Which attributes this NPC can grow. Empty = all three available.
```

**Flow:**
1. `NPCNode._on_dialogue_ended()` emits `dialogue_completed.emit(name)`
2. `AttributeGrowthController` (a `Node` connected at scene level) receives signal
3. Checks `AttributeSystem` cooldowns and maximums
4. If growth available → emits `growth_opportunity` signal to AttributeGrowthPrompt UI

No changes required to NPCNode core logic — `dialogue_completed` signal already exists.

### 3.3 Godot Dialogue Manager Integration

In `.dialogue` files, AttributeSystem is accessible via:

```dialogue
using StateSystem
using AttributeSystem

~ clerk_greet
Store Clerk: Welcome. Late night shopping?
# Condition using attribute
- 「我注意到你换了咖啡机。」 [if AttributeSystem.insight >= 3]
    => insight_response
# Effect using attribute growth (via flag relay — see 3.3.1)
```

#### 3.3.1 Attribute Growth in .dialogue Files

godot_dialogue_manager's `do` statement may not support calling methods with parameters on arbitrary autoloads. The safe, tested approach is **flag-based relay**:

```dialogue
~ clerk_comfort
Store Clerk: Sometimes coffee helps.
- 「谢谢你的话。」
    do StateSystem.set_flag("growth_empathy", true)
    => after_growth
```

Then `AttributeGrowthController` (GDScript) polls or listens for flag changes and fires the growth prompt when a `growth_*` flag is set.

**If `do AttributeSystem.increase_attribute("insight")` works** (to be verified during implementation), the direct method call is preferred:

```dialogue
- 「谢谢你的话。」
    do AttributeSystem.increase_attribute("empathy")
    => after_growth
```

#### 3.3.2 Attribute Conditions in .dialogue Files

Attribute reading in conditions is expected to work via `using AttributeSystem`:

```dialogue
- 「你看起来很累。」 [if AttributeSystem.empathy >= 3]
    => clerk_empathy_path

- 「我注意到门口的痕迹。」 [if AttributeSystem.insight >= 5]
    => clerk_insight_path
```

### 3.4 SkillCheckManager Integration (#227)

The SkillCheckManager (Issue #227) will query AttributeSystem for attribute values and perk modifiers:

```gdscript
# In SkillCheckManager.roll_check(attr_name, difficulty):
var attr_value: int = AttributeSystem.get_attribute(attr_name)  # 0 if AttributeSystem not available
var perk_bonus: int = AttributeSystem.get_perk_modifiers(attr_name + "_check")  # 0 if no AttributeSystem
# Formula: total = roll + attr_value + perk_bonus + hallucination_offset
```

**Interface contract between #222 and #227:**

| Method | Returns | When Available |
|--------|---------|---------------|
| `AttributeSystem.get_attribute(name: String) → int` | `0` if unknown, `1-10` otherwise | After AttributeSystem ready |
| `AttributeSystem.get_perk_modifiers(check_type: String) → int` | Sum of relevant perk bonuses | After AttributeSystem ready |
| `AttributeSystem.get_hallucination_resistance() → int` | Sum of resistance from perks | After AttributeSystem ready |

If AttributeSystem is not available (not yet implemented, or test environment), SkillCheckManager defaults all values to 0 with a push_warning.

### 3.5 NarrativeManager Integration (#214)

**Changes to `gdscripts/narrative_manager.gd`:**

The `get_hallucination_level()` static method should accept an optional perk resistance parameter:

```gdscript
static func get_hallucination_level(
    scene_id: String,
    state: Dictionary,
    perk_resistance: int = 0  # NEW: from AttributeSystem
) -> int:
    var base_level: int = HALLUCINATION_BASE_LEVELS.get(scene_id, 0)
    var hope_val: float = state.get("hope", 5.0)
    var state_modifier: int = 0

    if hope_val >= 8.0:
        state_modifier = -1
    elif hope_val <= 2.0:
        state_modifier = 1

    # NEW: apply perk resistance after all other modifiers
    var effective: int = clampi(base_level + state_modifier, HALLUCINATION_MIN, HALLUCINATION_MAX)
    effective = clampi(effective - perk_resistance, HALLUCINATION_MIN, HALLUCINATION_MAX)
    return effective
```

This is a low-impact, backward-compatible change — existing callers without the new parameter continue to work (default `perk_resistance = 0`).

### 3.6 GameManager Integration

**Changes to `gdscripts/game_manager.gd`:**

- Update `_verify_autoloads()` to include `AttributeSystem`
- Add delegation methods (optional, for consistency):

```gdscript
func get_attribute(attr_name: String) -> int:
    var attr_sys := get_node_or_null("/root/AttributeSystem")
    if attr_sys and attr_sys.has_method("get_attribute"):
        return attr_sys.get_attribute(attr_name)
    return 0

func has_perk(perk_id: String) -> bool:
    var attr_sys := get_node_or_null("/root/AttributeSystem")
    if attr_sys and attr_sys.has_method("has_perk"):
        return attr_sys.has_perk(perk_id)
    return false
```

### 3.7 Input Map Integration

Add new input actions to `project.godot`:

```ini
[input]

toggle_attribute_panel={
"deadzone": 0.5,
"events": [{
"keycode": 4194310,
"type": 0
}]
}
```

Keycode `4194310` = key `C` on US keyboard layout.

---

## 4. Save/Load Architecture

### Save Format

AttributeSystem saves to its own file: `user://save_states/attributes_<slot>.json`

```json
{
    "version": 1,
    "insight": 3,
    "empathy": 5,
    "tenacity": 2,
    "perk_points": 0,
    "unlocked_perks": ["clear_mind", "night_walker"],
    "growth_cooldowns": {
        "StoreClerk": 1623345678,
        "BridgeHomeless": 1623345778
    }
}
```

### Load Behavior

- **Normal load:** AttributeSystem reads from its save file, restores all state, emits `attribute_changed` signal once per attribute.
- **New game (no save file):** All attributes = 1, no perks, empty cooldowns.
- **Upgraded save (no AttributeSystem data):** Safely defaults to `{insight: 1, empathy: 1, tenacity: 1, unlocked_perks: []}` — backward compatible.

### Save Coordination with StateSystem

AttributeSystem save/load is triggered by the same Save/Load UI flow:
1. Player saves → `StateSystem.save_state_to_file(path)` + `AttributeSystem.save_state_to_file(path)`
2. Player loads → `StateSystem.load_state_from_file(path)` + `AttributeSystem.load_state_from_file(path)`
3. AttributeSystem's growth cooldowns are independent of StateSystem's flags

---

## 5. Autoload Registration

**Add to `project.godot`:**

```ini
[autoload]

AttributeSystem="*res://gdscripts/attribute_system.gd"
```

Autoload order: `StateSystem` → `GameManager` → `NarrativeManager` → `AudioManager` → `AttributeSystem` → `GameState` → `UIConfig`

AttributeSystem depends on no other autoload (it reads nothing from StateSystem at `_ready()`; it writes signals that consumers may subscribe to).

---

## 6. Edge Case Handling

| Edge Case | Handling |
|-----------|----------|
| Attribute already at 10 | `increase_attribute()` returns `false`; growth prompt filters out maxed attributes |
| All attributes at 10 | Growth prompt never appears (`_offer_growth` returns early with `push_warning`) |
| Perk already unlocked | `check_unlocks()` skips already-unlocked perks; `perk_unlocked` not re-emitted |
| Multiple perks unlock simultaneously | Emit `perk_unlocked` signal once per newly unlocked perk; UI queues them (0.5s delay between popups) |
| Growth timeout (60s) | Timer auto-dismisses prompt; no attribute change; `growth_opportunity` consumed |
| Player starts new dialogue during growth prompt | Prompt auto-closes; growth opportunity lost |
| NPC with cooldown active | `_offer_growth` checks cooldown; if active, returns early silently |
| Perk condition references unknown flag | Condition evaluates to `false` (same as DialogueConditionEvaluator behavior) |
| AttributeSystem not yet ready (early frame) | `get_attribute()` returns 1 (default); `push_warning` if called before `_ready()` |
| Hallucination resistance overflow | `hallucination_resist` clamps effective level to `>= 0` — cannot go negative |
| Perk effect stacking | Multiple perks with same check type: effects sum. E.g., two `insight_check_bonus: +1` = total `+2` |
| Perk condition using StateSystem state | `condition` Dictionary can include state checks via `{"type": "state", "axis": "hope_despair", ...}` — evaluated at unlock moment |
| C key in dialogue mode | `toggle_attribute_panel` input is consumed by dialogue balloon when dialogue is active; attribute panel will not toggle during dialogue |

---

## 7. Failure Paths

| Failure | Mitigation |
|---------|------------|
| `using AttributeSystem` in .dialogue fails (autoload not exposed) | Fallback: read attributes via `StateSystem.get_attribute()` after adding delegation methods to StateSystem |
| `do AttributeSystem.increase_attribute(...)` not supported by godot_dialogue_manager | Use flag-relay pattern: `do StateSystem.set_flag("growth_empathy", true)`, then GDScript monitors flags |
| `growth_prompt.tscn` fails to instantiate (resource missing) | Attribute growth is skipped silently; dialogue continues normally |
| `attribute_panel.tscn` fails to load (resource missing) | C key does nothing; game continues without attribute display (perk effects still work silently) |
| Perk definition data corrupt (missing field) | Perk entry is skipped with `push_warning`; remaining perks load normally |
| Save file version mismatch | `_from_save_dict()` applies defaults for missing fields; saves forward-compatible |
| Player has no GrowthAffinity export on NPCNode | Default to all three attributes available |
| Multiple NPC conversations queue growth prompts | Prompt only appears after the *last* conversation ends (single dialogue_balloon at a time enforced by godot_dialogue_manager) |

---

## 8. Test Case Descriptions

### Scenario A: AttributeSystem Autoload Initialization

- **Test A1 — Autoload registration:** `AttributeSystem` is accessible as `get_node("/root/AttributeSystem")` after project load. Not null.
- **Test A2 — Default values:** After `_ready()`, all three attributes are `1`. `perk_points` is `0`. `unlocked_perks` is empty.
- **Test A3 — Headless mode:** `godot --headless --quit` exits with code 0. No script errors from AttributeSystem.
- **Test A4 — Autoload order independence:** AttributeSystem initializes correctly even if StateSystem is temporarily unavailable.

### Scenario B: Attribute Growth

- **Test B1 — Basic growth:** `increase_attribute("insight")` changes `insight` from 1 to 2. Returns `true`.
- **Test B2 — Cap at 10:** After `insight` reaches 10, `increase_attribute("insight")` returns `false`. Value stays 10.
- **Test B3 — Unknown attribute:** `increase_attribute("unknown")` returns `false`. Emits `push_warning`.
- **Test B4 — Signal emission:** After `increase_attribute("empathy")`, `attribute_changed` signal fires with correct `attr_name`, `old_value`, `new_value`.
- **Test B5 — Can only grow from NPC once:** Same NPC ID triggers growth only once per playthrough. Second attempt returns early silently.
- **Test B6 — All three at 10:** When all three are 10, `_offer_growth()` returns early without emitting `growth_opportunity`.

### Scenario C: Perk Unlock

- **Test C1 — Single attribute threshold:** Set `insight = 3`. After `increase_attribute()`, `check_unlocks()` reports `clear_mind` as newly unlocked.
- **Test C2 — Compound attribute threshold:** Set `insight = 4`, `tenacity = 4`. After attribute change, `lucid_gaze` unlocks (sum = 8 ≥ 8).
- **Test C3 — Not-yet-met condition:** Set `insight = 2`. After growth to `insight = 3`, only `clear_mind` unlocks; `compassionate_heart` (empathy >= 5) does not.
- **Test C4 — Already unlocked:** If `clear_mind` is already unlocked and conditions are still met, `check_unlocks()` does not re-return it.
- **Test C5 — Multiple simultaneous unlocks:** Set `insight = 3` and `empathy = 3`. After triggering growth on the third attribute, both `clear_mind` and `empathic_insight` unlock. Two separate `perk_unlocked` signals emitted.
- **Test C6 — Perk condition using StateSystem:** Perk with `condition` that references `StateSystem.hope_despair` is evaluated correctly — only unlocks when both attribute and state conditions are met.

### Scenario D: Perk Effect Queries

- **Test D1 — Check bonus:** `perk_clear_mind` unlocked. `get_perk_modifiers("insight_check")` returns `1`.
- **Test D2 — Stacking bonuses:** `perk_clear_mind` (+1) and another perk with `insight_check_bonus: +1` → `get_perk_modifiers("insight_check")` returns `2`.
- **Test D3 — Hallucination resistance:** `perk_night_walker` unlocked. `get_hallucination_resistance()` returns `2`.
- **Test D4 — No perks:** No perks unlocked. `get_perk_modifiers("insight_check")` returns `0`.
- **Test D5 — Unknown check type:** `get_perk_modifiers("nonexistent")` returns `0`.

### Scenario E: AttributePanel UI

- **Test E1 — Toggle visibility:** Press `C` key → panel appears. Press `C` again → panel disappears.
- **Test E2 — Display values:** Panel shows correct values for all three attributes (numeric and bar width).
- **Test E3 — Update animation:** After `attribute_changed` signal, panel bar animates from old width to new width over ~0.3s.
- **Test E4 — Perk display:** Unlocked perks show with ✓, locked (conditions visible but unmet) show grayed out.
- **Test E5 — No interference with dialogue:** Panel does not block dialogue balloon input when visible.
- **Test E6 — Headless mode:** Panel instantiation in headless mode fails gracefully (resource wrap) with push_warning.

### Scenario F: Attribute Growth Prompt UI

- **Test F1 — Prompt visibility:** After `dialogue_completed` signal with growth available, prompt appears with correct attribute options.
- **Test F2 — Attribute selection:** Click on an attribute option → `increase_attribute()` called with correct name → prompt closes.
- **Test F3 — Timeout:** Prompt displayed for 60 seconds with no input → auto-dismisses → no attribute change.
- **Test F4 — Maxed attribute hidden:** If attribute is at 10, it is not shown as an option.
- **Test F5 — Close on new interaction:** If player starts a new NPC interaction while prompt is visible, prompt auto-closes.

### Scenario G: Dialogue Integration

- **Test G1 — Attribute condition in .dialogue:** A `.dialogue` file with `using AttributeSystem`. Set `AttributeSystem.insight = 3`. Condition `[if AttributeSystem.insight >= 3]` evaluates to `true` → response `is_allowed == true`.
- **Test G2 — Attribute growth via flag relay:** Dialogue mutation sets `StateSystem.set_flag("growth_empathy", true)`. After dialogue ends, `GrowthController` detects flag and triggers growth prompt.
- **Test G3 — Attribute growth via direct call (preferred):** Dialogue mutation calls `do AttributeSystem.increase_attribute("empathy")`. After execution, `AttributeSystem.empathy` increased by 1.
- **Test G4 — Compound condition:** Condition `[if AttributeSystem.insight >= 3 and StateSystem.hope >= 5]` correctly evaluates both parts.

### Scenario H: Save/Load

- **Test H1 — Save attributes:** After attribute changes and perk unlocks, `save_state_to_file()` produces a JSON file with correct values.
- **Test H2 — Load attributes:** Loading a save with `insight=5, empathy=3, tenacity=2, unlocked_perks=[clear_mind]` restores all values correctly. `attribute_changed` emitted.
- **Test H3 — New game (no save):** No save file exists → attributes default to 1, no perks.
- **Test H4 — Upgraded save (missing fields):** Save file without attribute data → `_from_save_dict()` defaults all three attributes to 1, unlocked_perks to empty.
- **Test H5 — Cooldown persistence:** Growth cooldowns saved and restored correctly — NPC cannot give growth twice after reload.

### Scenario I: NarrativeManager Integration

- **Test I1 — Hallucination resistance applied:** `get_hallucination_level("underpass", {hope: 3.0}, perk_resistance=2)` returns `5` (base 7 + 0 modifier - 2 resistance = 5).
- **Test I2 — No resistance (default):** `get_hallucination_level("underpass", {hope: 3.0})` returns `7` (unchanged behavior, perk_resistance defaults to 0).
- **Test I3 — Resistance cannot go below 0:** `get_hallucination_level("office", {hope: 5.0}, perk_resistance=5)` returns `0` — not `-5`.

### Scenario J: SkillCheckManager Integration (Contract)

- **Test J1 — Attribute lookup:** With AttributeSystem available, `get_attribute("insight")` returns current value.
- **Test J2 — Attribute fallback (no AttributeSystem):** Without AttributeSystem, `get_attribute("insight")` returns `0` with `push_warning`.
- **Test J3 — Perk modifier lookup:** With perks, `get_perk_modifiers("insight_check")` returns sum.
- **Test J4 — Perk modifier fallback (no AttributeSystem):** Without AttributeSystem, `get_perk_modifiers("insight_check")` returns `0`.

---

## 9. Files to Create / Modify

### New Files

| File | Description |
|------|-------------|
| `gdscripts/attribute_system.gd` | Core AttributeSystem autoload — attribute storage, growth API, perk integration |
| `gdscripts/perk_manager.gd` | Internal PerkManager — perk definitions, unlock evaluation, modifier queries |
| `gdscripts/attribute_panel.gd` | AttributePanel CanvasLayer controller — C key toggle, bar rendering, perk display |
| `scenes/ui/attribute_panel.tscn` | AttributePanel scene — bar graphics, labels, layout |
| `gdscripts/attribute_growth_prompt.gd` | GrowthPrompt controller — option display, timeout, selection handling |
| `scenes/ui/attribute_growth_prompt.tscn` | GrowthPrompt scene — button options, timer, layout |
| `gdscripts/growth_controller.gd` | Bridge between NPCNode signals and AttributeSystem growth flow |
| `tests/unit/test_attribute_system.gd` | Unit tests for AttributeSystem and PerkManager |

### Modified Files

| File | Change |
|------|--------|
| `project.godot` | Add `AttributeSystem` autoload entry; add `toggle_attribute_panel` input action |
| `gdscripts/game_manager.gd` | Update `_verify_autoloads()` to include AttributeSystem; optionally add `get_attribute()` and `has_perk()` delegation |
| `gdscripts/narrative_manager.gd` | Update `get_hallucination_level()` to accept optional `perk_resistance` parameter |
| `dialogues/store_clerk.dialogue` | Add attribute-conditioned dialogue branches and growth trigger flags |
| `dialogues/bridge_homeless.dialogue` | Add attribute-conditioned dialogue branches and growth trigger flags |
| `docs/PROJECT.md` | Update module map to include AttributeSystem |

### Files Not Modified (Intentionally)

| File | Reason |
|------|--------|
| `gdscripts/state_system.gd` | AttributeSystem is separate — no concept coupling |
| `gdscripts/npc_node.gd` | `dialogue_completed` signal already exists; growth controller is external |
| `gdscripts/dialogue_condition_evaluator.gd` | Replaced by godot_dialogue_manager's built-in condition evaluation |
| `gdscripts/ui_config.gd` | StatusBar and AttributePanel share same visual language but remain independent |

---

## 10. Implementation Phases

### Phase 0 — Pre-flight (Spike Verification)

- [ ] Verify `using AttributeSystem` works in godot_dialogue_manager
- [ ] Verify `do AttributeSystem.increase_attribute(...)` works (or confirm flag-relay fallback)
- [ ] Verify AttributeSystem signals can be received by AttributePanel CanvasLayer

### Phase 1 — Core Engine

- [ ] Implement `attribute_system.gd` with three attributes, getters, setters
- [ ] Implement `increase_attribute()` with clamping and signal emission
- [ ] Implement `get_attribute()` / `get_attributes()` / `can_increase()` API
- [ ] Implement `reset()` method
- [ ] Implement save/load serialization
- [ ] Add autoload registration and verify headless compilation

### Phase 2 — Perk System

- [ ] Implement `perk_manager.gd` with hardcoded perk definitions (6 MVP perks)
- [ ] Implement condition evaluation (attribute thresholds, compound conditions)
- [ ] Implement `check_unlocks()` with signal emission
- [ ] Implement `get_perk_modifiers()` and `get_hallucination_resistance()`
- [ ] Implement `has_perk()` and `get_active_perks()`
- [ ] Unit test all 6 perk unlock conditions

### Phase 3 — UI Components

- [ ] Implement `attribute_panel.gd` + `attribute_panel.tscn`
- [ ] Implement C key toggle with InputMap integration
- [ ] Implement bar rendering and value display
- [ ] Implement tween animation on attribute change
- [ ] Implement perk display (unlocked/locked states)
- [ ] Implement `attribute_growth_prompt.gd` + `attribute_growth_prompt.tscn`
- [ ] Implement growth selection buttons and timeout timer
- [ ] Implement `growth_controller.gd` — NPC signal bridge

### Phase 4 — Dialogue Integration

- [ ] Add `growth_*` flag triggers to at least 2 NPC dialogue files
- [ ] Add attribute-conditioned dialogue branches to NPC dialogues
- [ ] Implement flag-relay growth detection in GrowthController
- [ ] Test end-to-end: dialogue → growth prompt → attribute increase → perk unlock

### Phase 5 — System Integration

- [ ] Update `narrative_manager.gd` for hallucination resistance
- [ ] Update `game_manager.gd` for autoload verification and delegation
- [ ] Verify AttributeSystem ↔ SkillCheckManager contract (interface alignment)
- [ ] Verify save/load coordination with StateSystem

### Phase 6 — Edge Cases & Polish

- [ ] Test attribute growth with all attribute maxed
- [ ] Test growth timeout behavior
- [ ] Test growth prompt dismissal on new interaction
- [ ] Test panel open during dialogue (should not block)
- [ ] Test upgraded save compatibility (no attributes in save)
- [ ] Test cooldown persistence across save/load cycle
- [ ] Add input validation for attribute name strings

---

## 11. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #215 — godot_dialogue_manager integration | ✅ CLOSED | Low — `using` DSL confirmed working with StateSystem; expected to work with any autoload |
| #216 — Godot minimal theme | ✅ CLOSED | Low — UI visual language reference, not a runtime dependency |
| StateSystem | ✅ IMPLEMENTED | Low — AttributeSystem is independent, no tight coupling |

### Blocks

| Future Work | Priority | Notes |
|-------------|----------|-------|
| #227 — SkillCheck System | P0 | AttributeSystem provides attribute values for `D20 + attribute + perk_bonus + offset vs difficulty` formula |
| Perk effects in narrative branching | P1 | Dialogue authors reference `AttributeSystem.has_perk(...)` in conditions |

### Open Questions

1. **Q1:** Does `using AttributeSystem` work in godot_dialogue_manager for an autoload registered in `project.godot`? (Same pattern as StateSystem — expected to work, but must verify)
2. **Q2:** Does `do AttributeSystem.increase_attribute("empathy")` execute as a mutation in `.dialogue` files? (If not, use flag-relay fallback)
3. **Q3:** What is the exact NPC → growth affinity mapping for each NPC in the game? (Content design decision — store_clerk = empathy, bridge_homeless = tenacity, lobby_guard = balanced)
4. **Q4:** Should perk definitions eventually be extracted to `.tres` Resource files for moddability? (Deferred to post-MVP)
