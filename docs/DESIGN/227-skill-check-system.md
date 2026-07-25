# Design: #227 — 检定系统 (Skill-Check System)

> Parent Issue: #227
> Agent: game-plan-agent
> Date: 2026-07-25
> PRD Reference: `docs/PRD/227-skill-check-system.md`
> Recommended Approach: **Approach A — Independent SkillCheckManager** (adopted)

---

## 1. Architecture Overview

### Core Idea

Create an **independent SkillCheckManager autoload** that provides a centralized dice-rolling and attribute-comparison engine for the dialogue system. Checks are triggered from `.dialogue` files via godot_dialogue_manager `using` statements, and results drive dialogue branching (success_branch / failure_branch) without blocking the narrative.

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                  SkillCheckManager (autoload)                        │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ roll_check(attribute_name, difficulty): CheckResult           │   │
│  │   ├── D20 roll (randi() % 20 + 1)                             │   │
│  │   ├── hallucination_offset (randf_range)                      │   │
│  │   ├── attribute lookup → StateSystem or AttributeSystem       │   │
│  │   ├── natural 20/1 short-circuit                              │   │
│  │   └── result = roll + attribute + offset vs difficulty         │   │
│  │                                                               │   │
│  │ last_check_result: CheckResult (cached for 1 frame)           │   │
│  │ check_history: Array[CheckResult] (ring buffer, latest 50)    │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌──────────────────────┐   ┌──────────────────────────┐
│  SkillCheckUI         │   │  StateSystem              │
│  (CanvasLayer scene)  │   │  (autoload)               │
│                       │   │  - check_history store    │
│  play_animation(r)    │   │  - flags (check_*)        │
│  ├─ success: green    │   └──────────────────────────┘
│  │  flash + risetext │
│  ├─ failure: red     │
│  │  shake + decay    │
│  └─ ~1.5s total      │
└──────────────────────┘
```

### Data Flow (Check Trigger)

```
.dialogue file
  │
  │ using StateSystem
  │ using SkillCheckManager
  │
  ├── ► "洞察检定"
  │   do SkillCheckManager.roll_check("insight", 12)
  │   ↓
  │   SkillCheckManager:
  │     ├─ Get attribute: StateSystem.get_attribute("insight")
  │     ├─ Roll D20
  │     ├─ Apply hallucination offset
  │     ├─ Compare vs difficulty
  │     ├─ Cache result in last_check_result
  │     └─ Emit check_completed(result)
  │         ↓
  │   SkillCheckUI:
  │     ├─ Display dice animation (~1.2s)
  │     ├─ Show result animation (~0.5s success/failure)
  │     └─ Emit animation_finished()
  │         ↓
  │   Dialogue resumes:
  │     ├─ [if SkillCheckManager.last_success] → success_branch
  │     └─ [else] → failure_branch
  │
  └── ► (dialogue continues)
```

---

## 2. Component Specification

### 2.1 SkillCheckManager.gd

**Path:** `gdscripts/skill_check_manager.gd`
**Type:** Node (autoload singleton)
**Purpose:** Core check engine

#### Public API

| Method | Signature | Description |
|--------|-----------|-------------|
| `roll_check` | `(attribute: String, difficulty: int, hallucination_override: int = -1) → CheckResult` | Execute check. Returns CheckResult immediately. Caches result for 1 frame. |
| `get_attribute_value` | `(attribute: String) → int` | Reads attribute from StateSystem or AttributeSystem. Returns 0 if not found. |
| `get_last_check_result` | `() → CheckResult` | Returns cached result. |
| `is_last_check_successful` | `() → bool` | Synthax helper for `.dialogue` condition: `[if SkillCheckManager.is_last_check_successful]` |
| `clear_last_check` | `()` | Resets cached result (called on dialogue end). |

#### CheckResult (data class)

```gdscript
class CheckResult:
    var success: bool
    var roll: int            # D20 result (1-20)
    var attribute_value: int # from attribute system (0-10)
    var difficulty: int      # target difficulty (1-20, clamped)
    var hallucination_offset: float  # -hall*0.5 to +hall*0.5
    var total: float         # roll + attribute + offset
    var is_natural_20: bool  # auto success
    var is_natural_1: bool   # auto failure
    var timestamp: int       # frame count at check time
```

#### Check Formula

```
roll = randi() % 20 + 1                   # D20 (1-20)
offset = randf_range(-hallucination * 0.5, hallucination * 0.5)
total = roll + attribute_value + offset

# Short-circuit
if roll == 20 → auto success
if roll == 1  → auto failure

# Normal comparison
success = total >= difficulty
```

#### Hallucination Offset Formula

| Hallucination Level | Offset Range | Effective Impact |
|---------------------|-------------|------------------|
| 0 | ±0 | Pure D20 + attribute |
| 1-3 | ±(0.5-1.5) | Minor sway |
| 4-6 | ±(2-3) | Noticeable variance |
| 7-9 | ±(3.5-4.5) | Significant unpredictability |
| 10 | ±5 | Extreme — can flip success |

#### Single-Frame Cache

`randi()` in Godot returns different values if polled across multiple frames. To guarantee consistency:
- `roll_check()` calculates and caches the result in one frame.
- All subsequent reads (`last_check_result`, `last_success`, etc.) read from cache.
- `clear_last_check()` called on dialogue end.

### 2.2 CheckResult Data Class

**Path:** `gdscripts/check_result.gd` (optional standalone, or inline in SkillCheckManager)

```gdscript
class_name CheckResult
extends RefCounted

var success: bool
var roll: int
var attribute_value: int
var difficulty: int
var hallucination_offset: float
var total: float
var is_natural_20: bool
var is_natural_1: bool
var timestamp: int

func _init(
    p_success: bool,
    p_roll: int,
    p_attribute_value: int,
    p_difficulty: int,
    p_hallucination_offset: float,
    p_total: float
):
    success = p_success
    roll = p_roll
    attribute_value = p_attribute_value
    difficulty = p_difficulty
    hallucination_offset = p_hallucination_offset
    total = p_total
    is_natural_20 = p_roll == 20
    is_natural_1 = p_roll == 1
    timestamp = Engine.get_process_frames()
```

### 2.3 SkillCheckUI.gd

**Path:** `gdscripts/skill_check_ui.gd`
**Type:** CanvasLayer (instantiable, not autoload)
**Purpose:** Check animation display

#### Lifecycle

1. `skill_check_ui.tscn` instantiated by `_show_check()` call in balloon
2. Show dice rolling animation (~1.2s): numbers cycle 15→9→3→14→...→final
3. Resolve result → show feedback:
   - **Success:** Green flash overlay + rising text "✓ 判定成功" + brief glow
   - **Failure:** Red shake (position jitter) + decaying overlay + "✗ 判定失败"
4. ~0.3s pause for reading
5. Emit `animation_finished()` signal
6. Queue free

#### Visual Feedback Details

| State | Duration | Visual Effect | Color |
|-------|----------|---------------|-------|
| Dice cycle | ~1.2s | Random digits cycling → settle on final | White amber `#d4a76a` |
| Success flash | 0.3s | Full-screen green tint flash | Green `#4ade80` |
| Rising text | 1.0s | "✓ 检定成功" floats up + fades | Green `#4ade80` |
| Failure shake | 0.4s | Position jitter + red overlay | Red `#ef4444` |
| Decay effect | 1.0s | "✗ 检定失败" fades with particle decay | Red `#ef4444` → fade |

#### Signal

```gdscript
signal animation_finished()
```

### 2.4 skill_check_ui.tscn

**Path:** `scenes/ui/skill_check_ui.tscn`
**Type:** PackedScene (CanvasLayer)
**Structure:**

```
CanvasLayer (SkillCheckUI)
├── ColorRect (fullscreen overlay, transparent)
├── CenterContainer
│   └── VBoxContainer
│       ├── Label (attribute name + difficulty, e.g. "洞察检定 DC:12")
│       ├── Label (dice result display, e.g. "D20: 14")
│       └── Label (outcome, e.g. "✓ 判定成功")
├── AnimationPlayer (dice roll, flash, shake)
└── Timer (check failure timeout fallback)
```

### 2.5 NarrativeManager Integration

**Path:** `gdscripts/narrative_manager.gd`
**Changes:** Add `_route_check_result()` method (or integrate into existing dialogue flow)

When a check completes:
1. Read `SkillCheckManager.last_check_result`
2. Determine success/failure branch ID from check result
3. Route dialogue to the appropriate branch continuation

This may instead be handled entirely by godot_dialogue_manager condition branches (preferred — less coupling). NarrativeManager only needs integration if custom routing logic is required beyond what `.dialogue` conditions provide.

### 2.6 StateSystem Integration

**Path:** `gdscripts/state_system.gd`
**Changes:** Add check history storage

```gdscript
# New members
var check_history: Array[CheckResult] = []
var max_check_history := 50

# New method
func record_check(result: CheckResult) -> void:
    check_history.append(result)
    if check_history.size() > max_check_history:
        check_history.pop_front()

# New flag: check_<attribute>_success / check_<attribute>_failure
# Set by SkillCheckManager after each check
```

---

## 3. Dialogue Integration

### 3.1 DSL Extension

In `.dialogue` files, checks are triggered via godot_dialogue_manager's `using` mechanism:

```dialogue
using SkillCheckManager

~ insight_check_12
"The lock on the drawer is old. You try to remember the warehouse code."
# This triggers the check via do statement
do SkillCheckManager.roll_check("insight", 12)
→ success_path
→ failure_path

== success_path
"You remember! The code is 7-3-1."

== failure_path
"The number escapes you. You feel a headache coming on."
```

### 3.2 Branch Condition

Checking the result after the `do` trigger:

```dialogue
~ after_check
do SkillCheckManager.roll_check("empathy", 10)

== empathy_pass
[if SkillCheckManager.is_last_check_successful]
"The clerk smiles. 'You understand.'"

== empathy_fail
[if not SkillCheckManager.is_last_check_successful]
"The clerk stares. 'You don't get it, do you?'"
```

### 3.3 Fallback Strategy

If `do SkillCheckManager.roll_check(...)` does not work with godot_dialogue_manager's DSL:

1. **Fallback A:** Use `do StateSystem.set_flag("check_pending", true)` to signal check, then have a GDScript bridge that polls for the flag and routes dialogue.
2. **Fallback B:** Dialogue pauses momentarily while a GDScript callback reads a temporary flag set by the SkillCheckManager.

The current understanding is that `do` statements on autoload methods work with godot_dialogue_manager v3.10.5. Verify during implementation (T1).

---

## 4. Acceptance Criteria Implementation Map

| Criteria | Implementation |
|----------|---------------|
| Check triggers during dialogue, pauses dialogue, shows UI | SkillCheckUI CanvasLayer overlaid during check |
| D20 + attribute + hallucination vs difficulty | `roll_check()` formula |
| Success (green flash + rising text) visual | `play_animation(success: true)` |
| Failure (red shake + decay) visual | `play_animation(success: false)` |
| Dialogue continues on success/failure branch | `.dialogue` conditions via `is_last_check_successful` |
| Check result in StateSystem | `record_check()` stores to `check_history` |
| Attribute = 0: pure D20 luck | Formula uses 0, works naturally |
| Hallucination = 0: zero offset | `offset = randf_range(0, 0)` |
| Hallucination = 10: ±5 offset | `offset = randf_range(-5, 5)` |
| Difficulty out of [1,20]: clamped | `clamp(difficulty, 1, 20)` + `push_warning()` |
| Natural 20: auto success | Short-circuit in formula |
| Natural 1: auto failure | Short-circuit in formula |
| Consecutive checks: queue | Queue in SkillCheckUI, block until animation_finished |
| Scene change mid-check: cancel | Check if scene tree changing → skip animation, use cached result |
| ESC skip animation | Skip to final state, emit animation_finished immediately |

---

## 5. Edge Case Handling

| Edge Case | Handling |
|-----------|----------|
| `roll_check` called with unknown attribute name | Return 0, print `push_warning("Unknown attribute: {name}")` |
| `roll_check` called during animation | Queue the check, execute after current animation_finished |
| `difficulty` < 1 or > 20 | Clamp, `push_warning("Difficulty {val} out of [1,20], clamped to {clamped}")` |
| `is_last_check_successful` called before any check | Return false, `push_warning("No check has been performed yet")` |
| SkillCheckUI fails to instantiate | Fallback: silent check, no animation, route via cached result |
| Multiple checks in same dialogue node | Last check result cached, overwritten by each call |
| Player quits game mid-animation | `_exit_tree()` → stop animations gracefully |
| Hallucination level not available (nil) | Treat as 0, no offset |

---

## 6. Failure Paths

| Failure | Mitigation |
|---------|------------|
| godot_dialogue_manager's `do` doesn't execute autoload methods | Fallback: write check result to StateSystem flag, read flag in dialogue condition |
| SkillCheckUI.tres missing (resource not packed) | Wrap UI instantiation in `@onready var check_ui_resource = preload("...")` with try/catch |
| `randi()` inconsistency across frames | Single-frame cache (Section 2.1) |
| AttributeSystem not ready (Issue #222 not done yet) | `get_attribute_value()` defaults to 0 with `push_warning()`, system works without attributes (pure D20 luck) |
| Dialogue balloon freed during animation | Connect to `tree_exiting` signal → force-clean UI, commit cached result |

---

## 7. Files to Create / Modify

| File | Action | Description |
|------|--------|-------------|
| `gdscripts/skill_check_manager.gd` | **NEW** | Core check engine (autoload) |
| `gdscripts/check_result.gd` | **NEW** | CheckResult data class |
| `gdscripts/skill_check_ui.gd` | **NEW** | Check UI animation controller |
| `scenes/ui/skill_check_ui.tscn` | **NEW** | Check UI scene (CanvasLayer) |
| `gdscripts/narrative_manager.gd` | MODIFY | Add check routing (light integration) |
| `gdscripts/state_system.gd` | MODIFY | Add check_history, record_check(), flag methods |
| `dialogues/*.dialogue` | MODIFY | Embed check nodes (MVP: at least 1 check point) |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | UPDATE | Add check node DSL documentation |

---

## 8. Dependencies

| Dependency | Status | Description |
|------------|--------|-------------|
| #215 — godot_dialogue_manager integration | ✅ CLOSED | Required for `.dialogue` DSL integration |
| #222 — Attribute & Perk system | 🔄 OPEN (research) | Provides attribute values (insight/empathy/resilience). SkillCheckManager works without it (defaults attribute to 0) |
| StateSystem | ✅ CLOSED | Already integrated, used for check_history and hallucination_level retrieval |

### Attribute Dependency Strategy

Since #222 is not yet complete, SkillCheckManager will:
1. Attempt to read `StateSystem.get_attribute(attr_name)` if that method exists
2. Otherwise read from a dictionary fallback: `_attributes = {"insight": 0, "empathy": 0, "resilience": 0}`
3. When #222 lands, the fallback is replaced with the real attribute system

This design means **#227 does not block on #222** — the system works without attributes (pure luck), and attributes enhance it when available.

---

## 9. Open Questions (to resolve during implementation)

1. **Q1:** Does godot_dialogue_manager's `do` statement support calling methods with parameters on autoload? (e.g., `do SkillCheckManager.roll_check("insight", 12)`)
2. **Q2:** Can `[if SkillCheckManager.is_last_check_successful]` be used in the same dialogue node after a `do` call?
3. **Q3:** What is the exact attribute API from #222? (method name, signature, return type)
4. **Q4:** Does hallucination_level live in StateSystem already (from #215), or do we need to add it?
5. **Q5:** Should CheckResult be a standalone class (extends RefCounted) or a Dictionary for easier serialization?
