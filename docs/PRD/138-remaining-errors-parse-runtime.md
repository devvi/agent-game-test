# Research: #138 — Parse Error, Missing Scene Nodes, add_child Race (Game Still Won't Run)

> Parent Issue: #138
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

After PR #137 (Fix #134 remaining compile errors) was merged, the game still cannot load in `godot --headless --quit`. Running produces 1 parse error and multiple runtime errors across 4 GDScript files and 2 scene files.

The issue has spread across the codebase beyond what was documented in the original issue — several scene scripts (`lobby.gd`, `store.gd`, `street.gd`, `bridge.gd`, `subway_station.gd`, `underpass.gd`) contain the same bugs that exist in `office.gd` and `scene_base.gd`.

### Bug Catalog — Complete Discovery

| # | Category | File(s) | Count | Severity |
|---|----------|---------|:-----:|:--------:|
| A1 | `.has()` on Node — parse error | `office.gd`, `scene_base.gd`, `store.gd`, `street.gd` | 5 sites | ❌ Blocking |
| A2 | `.get(key, default)` 2-arg on Node — parse error | `bridge.gd`, `lobby.gd`, `subway_station.gd`, `underpass.gd` | 10 sites | ❌ Blocking |
| A3 | `var scene_id` redeclaration in subclass — parse error | `bridge.gd`, `lobby.gd`, `store.gd`, `street.gd`, `subway_station.gd`, `underpass.gd` | 6 files | ❌ Blocking |
| B1 | `add_child` during `_ready()` — runtime error | `scene_manager.gd` | 1 site | ⚠️ Runtime crash |
| B2 | Missing scene nodes in office.tscn | `office.tscn` — needs `ScreensaverText`, `DesktopText` | 2 nodes | ❌ Blocks scene |
| B3 | Missing child nodes under Dialogue3D in main.tscn | `main.tscn` — needs `SpeakerLabel`, `DialogueText`, `ChoiceContainer`, `ContinuePrompt` | 4 nodes | ❌ Blocks dialogue |
| B4 | Duplicate FadeCurtain (in TSCN + created by script) | `office.tscn` + `scene_manager.gd` | 1 site | ⚠️ Visual glitch |
| C1 | Resource leaks | Engine-wide | 3 resources, 13 ObjectDB | 🟡 Minor |

### Expected Behavior

1. `godot --headless --quit` exits with code 0 and no script/scene errors on stderr
2. Office scene loads with all environmental text nodes rendered
3. Dialogue3D displays dialogue with speaker label, text, choices, and continue prompt
4. Scene transitions work without `add_child` errors
5. No resource leaks at exit

### User Scenarios

- **Scenario A (Player):** Launches the game. Office scene must render all text elements (window, screensaver, desktop deadline). Dialogue UI must show speaker name, dialogue text, and choices.
- **Scenario B (Developer):** Runs `godot --headless --quit` after every implement PR. Currently blocked by parse errors — this is the regression gate.
- **Scenario C (CI/CD Pipeline):** The `build` step in `manifest.yaml` runs `godot --headless --export-debug`. These errors block export.
- **Frequency:** 100% — every launch, every build attempt.

---

## 2. Root Cause Analysis

### 2.1 Why Does Current Behavior Exist?

#### Bug A1: `.has()` on Node objects

```gdscript
# office.gd:52
day = int(ss.get("day")) if ss.has("day") else 0

# office.gd:70, scene_base.gd:37, store.gd:49, street.gd:62
if gm.has("choices_history") and not gm.choices_history.is_empty():
```

**Root cause:** `ss` and `gm` are typed as `Node` (from `get_node_or_null()`). In Godot 4 GDScript 2.0, `Node.has()` is a metadata method, not a property/member existence checker like Dictionary.has(). The GDScript compiler rejects `.has()` on Node when the intent is clearly to check for a property/key, because `.has()` is fundamentally a Dictionary method and GDScript's static typing doesn't support duck-typing `.has()` on Node.

**Introduced by:** Scene sequence and dialogue persistence implementations that treated GameManager and StateSystem like dictionaries.

#### Bug A2: `.get(key, default)` with 2 args on Node

```gdscript
# bridge.gd:44
var will_val: float = ss.get("will", 5.0)

# underpass.gd:93
var hope_val: float = ss.get("hope", 5.0)
```

**Root cause:** `StateSystem` inherits from `Node`. In Godot 4, `Node.get()` accepts only 1 argument (`StringName key`), returning metadata. There is no 2-argument form with a default value — that's `Dictionary.get()`. The `.get("hope", 5.0)` pattern imitates dictionary access but fails at compile time with "Expected at most 1 but received 2."

These persisted even after #137 because that PR only fixed `office.gd` — it did not fix the same pattern in `bridge.gd`, `lobby.gd`, `subway_station.gd`, or `underpass.gd`.

**Introduced by:** Same wave of scene sequence/dialogue PRs that produced the office.gd bugs.

#### Bug A3: `var scene_id` redeclaration

```gdscript
# scene_base.gd:10 — base class
var scene_id: String = ""

# lobby.gd:12, store.gd:11, subway_station.gd:14, etc. — subclass
var scene_id: String = "lobby"
```

**Root cause:** GDScript 2.0 forbids subclasses from redeclaring members of parent classes. `SceneBase` declares `var scene_id: String = ""` on line 10. Every scene script that writes `var scene_id: String = "..."` triggers a compile error.

PR #137 fixed this in `office.gd` (removed `var`, set in `_ready()`) but did NOT fix it in the other 6 scene subclasses. The `lobby.gd` fix is particularly important because the lobby scene is one of the next scenes the player visits.

#### Bug B1: `add_child` during `_ready()`

```gdscript
# scene_manager.gd:23-32
func _setup_fade_curtain() -> void:
    var scene_root = get_tree().current_scene
    ...
    scene_root.add_child(_fade_curtain)   # Line 32
```

**Root cause:** Called from `_ready()` (line 19). Godot 4's scene tree prevents `add_child()` while a node is in the middle of its `_ready()` callbacks ("Parent node is busy setting up children"). The error message specifically suggests `add_child.call_deferred(child)`.

Additionally, `office.tscn` already has a `FadeCurtain` node defined (lines 133-146 of office.tscn). The `_setup_fade_curtain()` function checks for an existing FadeCurtain via `has_node("FadeCurtain")` first, so the `add_child` would only fire for scenes that don't have a pre-existing FadeCurtain. But the function is still called from every scene's `_ready()`, meaning any scene without a FadeCurtain in its TSCN will hit this error.

#### Bug B2: Missing scene nodes in office.tscn

`office.gd:8-9` references `$Environments/ScreensaverText` and `$Environments/DesktopText`. The current office.tscn has `Environments/WindowText` (line 86) and `Environments/DeskNote` (line 93) but NO `ScreensaverText` or `DesktopText` children under `Environments/`.

When the script tries to `screensaver_text.text = "..."` on a null node (since `@onready var screensaver_text` resolves to null when the path doesn't exist), it produces: "Cannot set 'text' on a null value."

#### Bug B3: Missing child nodes under Dialogue3D in main.tscn

`dialogue_display_3d.gd:18-21` references `$SpeakerLabel`, `$DialogueText`, `$ChoiceContainer`, `$ContinuePrompt`. The file `Dialogue3D.tscn` defines all 4 of these nodes, but `main.tscn:33-35` does NOT instance `Dialogue3D.tscn` — it creates a plain `Node3D` with only the script attached:

```tscn
[node name="Dialogue3D" type="Node3D" parent="."]
position = Vector3(0, 1.5, -3)
script = ExtResource("4_dialogue_3d")
```

The child nodes from `Dialogue3D.tscn` (SpeakerLabel, DialogueText, ChoiceContainer, Choice0-3, ContinuePrompt) are never instantiated. The `@onready` variables resolve to null.

#### Bug B4: Duplicate FadeCurtain

`office.tscn` (lines 133-146) defines a `FadeCurtain` CanvasLayer node with a ColorRect and AnimationPlayer. Meanwhile, `scene_manager.gd` programmatically creates and adds its own FadeCurtain in `_create_fade_curtain()`. Because `_setup_fade_curtain()` checks `has_node("FadeCurtain")` first, it will find the scene's pre-existing one and skip creation. This means the office scene has a FadeCurtain that doesn't match the script's expectations (different structure). The `_fade_anim` assignment on line 33 would get a different AnimationPlayer than expected, potentially breaking the fade animation system.

**This is likely a leftover artifact from when scene_manager.gd was introduced** — the fade curtain was moved from scene-embedded to programmatic, but office.tscn wasn't cleaned up.

### 2.2 Complete Bug Site Inventory

#### A1: `.has()` on Node (5 sites across 4 files)

| File | Line | Code | Variable Type |
|------|------|------|---------------|
| `office.gd` | 52 | `ss.has("day")` | StateSystem (Node) |
| `office.gd` | 70 | `gm.has("choices_history")` | GameManager (Node) |
| `scene_base.gd` | 37 | `gm.has("choices_history")` | GameManager (Node) |
| `store.gd` | 49 | `gm.has("choices_history")` | GameManager (Node) |
| `street.gd` | 62 | `gm.has("choices_history")` | GameManager (Node) |

**Note:** `scene_base.gd:37` is inherited by ALL scene scripts — `office.gd`, `lobby.gd`, `store.gd`, `street.gd`, `bridge.gd`, `subway_station.gd`, `underpass.gd`. Fixing it in the base class fixes it for all.

#### A2: `.get(key, default)` with 2 args on Node (10 sites across 4 files)

| File | Line | Code |
|------|------|------|
| `bridge.gd` | 44 | `ss.get("will", 5.0)` |
| `bridge.gd` | 68 | `ss.get("conviction", 5.0)` |
| `bridge.gd` | 81 | `ss.get("conviction", 5.0)` |
| `lobby.gd` | 40 | `ss.get("conviction", 5.0)` |
| `subway_station.gd` | 50 | `ss.get("conviction", 5.0)` |
| `underpass.gd` | 93 | `ss.get("hope", 5.0)` |
| `underpass.gd` | 94 | `ss.get("conviction", 5.0)` |
| `underpass.gd` | 106 | `ss.get("hope", 5.0)` |
| `underpass.gd` | 130 | `ss.get("hope", 5.0)` |
| `underpass.gd` | 131 | `ss.get("conviction", 5.0)` |

All `ss` references are to StateSystem (Node). Fix by replacing with property access: `ss.hope`, `ss.conviction`, `ss.will`.

#### A3: `var scene_id` redeclaration (6 files)

| File | Line | Code |
|------|------|------|
| `bridge.gd` | 13 | `var scene_id: String = "bridge"` |
| `lobby.gd` | 12 | `var scene_id: String = "lobby"` |
| `store.gd` | 11 | `var scene_id: String = "convenience_store"` |
| `street.gd` | 13 | `var scene_id: String = "street"` |
| `subway_station.gd` | 14 | `var scene_id: String = "subway_station"` |
| `underpass.gd` | 13 | `var scene_id: String = "underpass"` |

**Already fixed in #137:** `office.gd` — removed `var`, set in `_ready()`.

#### B1: `add_child` in `_ready()` (1 site)

| File | Line | Code |
|------|------|------|
| `scene_manager.gd` | 32 | `scene_root.add_child(_fade_curtain)` |

#### B2: Missing scene nodes in office.tscn (2 nodes)

| Missing Node | Path | Required By |
|-------------|------|-------------|
| `Environments/ScreensaverText` | `office.tscn/Environments/` | `office.gd:8` |
| `Environments/DesktopText` | `office.tscn/Environments/` | `office.gd:9` |

#### B3: Missing scene nodes in main.tscn Dialogue3D (4 nodes)

| Missing Node | Path | Required By |
|-------------|------|-------------|
| `Main/Dialogue3D/SpeakerLabel` | Label3D | `dialogue_display_3d.gd:18` |
| `Main/Dialogue3D/DialogueText` | Label3D | `dialogue_display_3d.gd:19` |
| `Main/Dialogue3D/ChoiceContainer` | Node3D | `dialogue_display_3d.gd:20` |
| `Main/Dialogue3D/ContinuePrompt` | Label3D | `dialogue_display_3d.gd:21` |

#### B4: Duplicate FadeCurtain (1 scene)

| Issue | Detail |
|-------|--------|
| `office.tscn` lines 133-146 | Defines `FadeCurtain` CanvasLayer with ColorRect + AnimationPlayer |
| `scene_manager.gd` `_create_fade_curtain()` | Programmatically creates an equivalent FadeCurtain |
| Fix | Remove the hardcoded FadeCurtain from office.tscn; let SceneManager handle it programmatically |

### 2.3 Why Change Now?

- These are **blocking errors** — the game cannot launch, build, or export.
- PR #137 only fixed bugs in `office.gd` and `dialogue_display_3d.gd`. The same bugs in the same patterns exist across 6 other scene scripts, plus the base class.
- The pipeline feedback loop requires `godot --headless --quit` to pass before any further development.

### 2.4 Data Flow Impact

```
Scene loading sequence:

godot --headless --quit
    │
    ├──► Load main.gd
    │       ├──► _ready()
    │       │       ├──► Connect dialogue signals
    │       │       │       └──► dialogue_display_3d gd has @onready refs to null nodes  ← B3
    │       │       └──► call_deferred("_load_starting_scene")
    │       │               └──► change_scene_to_file("office.tscn")
    │
    ├──► Load office.tscn
    │       ├──► Parse TSCN (was error #134, now probably OK after cache clear)
    │       ├──► Instantiate children
    │       │       ├──► Environmens/WindowText ✓
    │       │       ├──► Environmens/ScreensaverText ? ← B2
    │       │       └──► Environmens/DesktopText ? ← B2
    │       ├──► Instantiate SceneManager → _ready()
    │       │       └──► _setup_fade_curtain() → add_child() fails ← B1
    │       └──► office.gd _ready() → super._ready()
    │               ├──► SceneBase._ready()
    │               │       ├──► scene_manager.fade_in()
    │               │       ├──► _configure_environmental_text()  ← office.gd override
    │               │       │       ├──► ss.hope ✓ (fixed in #137)
    │               │       │       ├──► screensaver_text.text = ... ← B2 (null)
    │               │       │       ├──► desktop_text.text = ... ← B2 (null)
    │               │       │       └──► ss.has("day") ← A1 (parse error)
    │               │       ├──► _configure_ambient_audio()
    │               │       └──► _restore_dialogue_state()
    │               │               └──► gm.has("choices_history") ← A1 (parse error)
    │               └──► door_trigger.input_event.connect(...)
    │
    ├──► ... next scene (lobby / store / etc.)
    │       ├──► var scene_id redeclaration ← A3 (6 files)
    │       └──► ss.get("key", default) ← A2 (10 sites)
    │
    └──► Scene transition (triggered by dialogue choice)
            └──► SceneManager._on_choice_made()
                    ├──► _persist_dialogue_state()
                    │       └──► gm.set("choices_history", ...) — works
                    └──► trigger_scene_change()
                            └──► change_scene_to_file(target_scene)
```

### 2.5 Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7 / GDScript 2.0 (static types) |
| Script format | GDScript 2.0 with `extends`, `class_name`, typed variables |
| Scene format | TSCN (Godot text scene format) |
| Error tolerance | **Zero** — compile errors prevent game from loading |
| Fix scope | In-place edits to existing files only |

---

## 3. Impact Analysis

### 3.1 Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/scene_base.gd` | Scene base class | Fix `.has()` → `"in"` pattern (1 line) |
| `gdscripts/office.gd` | Office scene script | Fix `.has()` calls (2 lines) |
| `gdscripts/store.gd` | Store scene script | Fix `.has()` (1 line), fix `var scene_id` (1 line) |
| `gdscripts/street.gd` | Street scene script | Fix `.has()` (1 line), fix `var scene_id` (1 line) |
| `gdscripts/lobby.gd` | Lobby scene script | Fix `.get(key, default)` (1 line), fix `var scene_id` (1 line) |
| `gdscripts/bridge.gd` | Bridge scene script | Fix `.get(key, default)` (3 lines), fix `var scene_id` (1 line) |
| `gdscripts/subway_station.gd` | Subway station script | Fix `.get(key, default)` (1 line), fix `var scene_id` (1 line) |
| `gdscripts/underpass.gd` | Underpass scene script | Fix `.get(key, default)` (5 lines), fix `var scene_id` (1 line) |
| `gdscripts/scene_manager.gd` | Scene transition manager | Fix `add_child` → `call_deferred` (1 line) |
| `gdscripts/dialogue_display_3d.gd` | 3D dialogue display | Already has null guard from #137 — no change needed |
| `scenes/office/office.tscn` | Office scene file | Add ScreensaverText + DesktopText nodes; remove duplicate FadeCurtain |
| `scenes/main.tscn` | Main entry scene | Fix Dialogue3D to use Dialogue3D.tscn instance, or add child nodes |

### 3.2 New Files Needed

None. All fixes are in-place edits to existing `.gd` and `.tscn` files.

### 3.3 Files That DO NOT Need Changes

| File | Rationale |
|------|-----------|
| `gdscripts/dialogue_engine.gd` | All `.has()` and `.get()` calls are on Dictionary objects (valid) |
| `gdscripts/dialogue_runner.gd` | All `.has()` and `.get()` calls are on Dictionary objects (valid) |
| `gdscripts/dialogue_parser.gd` | All `.has()` and `.get()` calls are on Dictionary objects (valid) |
| `gdscripts/state_system.gd` | Uses `.has()` and `.get()` on Dictionary objects from JSON, or on self (valid) |
| `gdscripts/game_manager.gd` | All `.get()` on choice dicts; `.has_method()` is valid Node method |
| `gdscripts/audio_manager.gd` | `state.get()` is on Dictionary from get_state() |
| `gdscripts/main.gd` | No `.has()` or `.get()` on Node issues |
| `gdscripts/text_component_base.gd` | `state.get()` on Dictionary from get_state() |
| `gdscripts/npc_node.gd` | `layer.get()` on Dictionary objects |
| All component scripts (puddle_text, rain_text, neon_sign, lamppost_text, etc.) | `state.get()` on Dictionary from get_state() |

---

## 4. Solution Comparison

### Approach A: In-Place Minimal Fixes (Recommended)

**Description:** Fix each bug at its source with minimal changes. Use a consistent pattern for each bug type across all affected files.

**Specific Fixes:**

#### Fix A1: Replace `.has("key")` with `"key" in object` on Nodes

For StateSystem (ss) and GameManager (gm) typed as Node, use the `in` operator which works for both Dictionary keys and object properties in GDScript 2.0.

```gdscript
# OLD (parse error):
if gm.has("choices_history") and not gm.choices_history.is_empty():

# NEW:
if "choices_history" in gm and not gm.choices_history.is_empty():
```

```gdscript
# OLD (parse error):
day = int(ss.get("day")) if ss.has("day") else 0

# NEW:
day = int(ss.get("day")) if "day" in ss else 0
```

**Affected sites:** `office.gd:52,70`, `scene_base.gd:37`, `store.gd:49`, `street.gd:62`

#### Fix A2: Replace `ss.get("key", default)` with property access

All `ss` variables reference `StateSystem` (Node subclass). StateSystem has custom properties `hope`, `conviction`, `will` with getters. Use direct property access.

```gdscript
# OLD (parse error):
var will_val: float = ss.get("will", 5.0)

# NEW:
var will_val: float = ss.will
```

```gdscript
# OLD (parse error):
ss.get("conviction", 5.0) <= 3.0

# NEW:
ss.conviction <= 3.0
```

Always wrap in null checks: `ss.conviction if ss else 5.0`

**Affected sites:** `bridge.gd:44,68,81`, `lobby.gd:40`, `subway_station.gd:50`, `underpass.gd:93,94,106,130,131`

#### Fix A3: Remove `var scene_id` redeclaration

Follow the #137 pattern for `office.gd`: remove the `var` declaration and set `scene_id = "..."` in `_ready()` before `super._ready()`.

```gdscript
# OLD (6 files):
var scene_id: String = "lobby"  # (or store/street/bridge/subway/underpass)

func _ready() -> void:
    super._ready()
    ...

# NEW:
func _ready() -> void:
    scene_id = "lobby"
    super._ready()
    ...
```

**Affected files:** `lobby.gd`, `store.gd`, `street.gd`, `bridge.gd`, `subway_station.gd`, `underpass.gd`

#### Fix B1: Use `add_child.call_deferred()` in scene_manager.gd

```gdscript
# OLD:
scene_root.add_child(_fade_curtain)

# NEW:
scene_root.add_child.call_deferred(_fade_curtain)
```

#### Fix B2: Add missing scene nodes to office.tscn

Add `ScreensaverText` (Label3D) and `DesktopText` (Label3D) under `Environments/` in office.tscn. Both should use `LoFiText3D` script (like `WindowText` already does).

#### Fix B3: Fix Dialogue3D in main.tscn

**Option B3a (recommended):** Change the `Dialogue3D` node in main.tscn to instance `Dialogue3D.tscn` instead of being a raw Node3D:

```tscn
# Currently:
[node name="Dialogue3D" type="Node3D" parent="."]
position = Vector3(0, 1.5, -3)
script = ExtResource("4_dialogue_3d")

# Fix: Instance the scene
[node name="Dialogue3D" parent="." instance=ExtResource("uid://dialogue_display_3d")]
position = Vector3(0, 1.5, -3)
```

**Option B3b:** Add the 4 child nodes (SpeakerLabel, DialogueText, ChoiceContainer, ContinuePrompt) as sub-resource nodes under the existing Dialogue3D node in main.tscn.

Option B3a is preferred because it reuses the existing well-defined scene and avoids duplication.

#### Fix B4: Remove duplicate FadeCurtain from office.tscn

Delete lines 133-146 of office.tscn (the FadeCurtain node block). SceneManager will create it programmatically.

#### Resource leaks (C1)

Investigate if leaks are caused by circular references or un-freed resources from the dialogue system. Likely from: (a) Signal connections between dialogue runner and 3D display not disconnecting, (b) Tween not killed on scene change, (c) AnimationPlayer references not cleaned up. Fix in a follow-up if primary fixes resolve it.

**Pros:**
- Minimal diff — ~30 lines total across 10 files + 2 scene files
- Consistent pattern for each bug type
- No architecture change — all existing behavior preserved
- Low risk of regressions
- Fast to implement and test

**Cons:**
- Does not address the underlying pattern that allowed these errors (no CI gate for compile)
- Office.tscn and main.tscn scene edits need careful TSCN syntax

**Risk:** Low — each fix targets a documented error with a well-understood root cause

**Effort:** 1–2 hours

### Approach B: Architecture Refactor

**Description:** Fix root causes by redesigning how state access and inheritance work.

- Change `scene_id` from `var` to a virtual getter `func get_scene_id() -> String:` in `SceneBase`
- Add a custom `get(key: String, default: Variant)` wrapper method to `StateSystem` / `GameManager`
- Refactor dialogue display to use dependency injection instead of `@onready` paths

**Pros:**
- Prevents these exact bugs from recurring
- Cleaner API for state queries
- Addresses the pattern, not just symptoms

**Cons:**
- Modifies base classes (`SceneBase`, `StateSystem`, `GameManager`) — higher regression surface
- Multiple subclass scenes need updates (approach A changes are already needed here too)
- Longer implementation and review cycle
- Over-engineered for bugs that are one-time fixes from auto-merged PRs

**Risk:** Medium

**Effort:** 4–6 hours

### Recommendation

→ **Approach A (In-Place Minimal Fixes)** because:
1. All bugs have clear, isolated root causes with trivial fixes.
2. The errors are artifacts from auto-merged implement PRs, not systemic design flaws.
3. Minimal diffs reduce review burden and merge conflict risk.
4. The same CI gate (`godot --headless --quit`) that caught these errors will catch future regressions.
5. Architecture refactors (Approach B) should be a separate issue if the patterns themselves are problematic.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

- [ ] **AC1: `godot --headless --quit` exits with code 0**
  - No script errors, parse errors, or null-reference errors on stderr
  - Game loads and exits cleanly

- [ ] **AC2: No `.has()` errors on Node**
  - `office.gd` line 52: uses `"day" in ss` — no "Nonexistent function 'has'" error
  - `office.gd` line 70: uses `"choices_history" in gm` — no error
  - `scene_base.gd` line 37: uses `"choices_history" in gm` — no error
  - `store.gd` line 49: uses `"choices_history" in gm` — no error
  - `street.gd` line 62: uses `"choices_history" in gm` — no error

- [ ] **AC3: No `.get(key, default)` 2-arg errors on Node**
  - All `ss.get("key", default)` replaced with `ss.key` property access
  - `bridge.gd`, `lobby.gd`, `subway_station.gd`, `underpass.gd` compile cleanly

- [ ] **AC4: No `var scene_id` redeclaration errors**
  - All 6 scene subclasses set `scene_id` in `_ready()` instead of `var` declaration
  - `scene_id` has the correct value when `super._ready()` runs

- [ ] **AC5: SceneManager does not crash on `add_child`**
  - `scene_manager.gd` uses `add_child.call_deferred()` — no "busy setting up children" error
  - Fade curtain is created correctly on scenes without a pre-existing one

- [ ] **AC6: Office scene has all environmental text nodes**
  - `ScreensaverText` and `DesktopText` exist under `Environments/` in office.tscn
  - `office.gd` does not crash when setting `.text` on these nodes

- [ ] **AC7: Dialogue3D display has all child nodes**
  - `SpeakerLabel`, `DialogueText`, `ChoiceContainer`, `ContinuePrompt` exist under `Dialogue3D` in main.tscn
  - Dialogue display works without null-reference errors

- [ ] **AC8: No duplicate FadeCurtain in office.tscn**
  - The hardcoded FadeCurtain block removed from office.tscn
  - SceneManager creates it programmatically without conflict

### Edge Cases

1. **StateSystem autoload not available:** If `ss` is null, fallback to `gm.get_slider()` or hardcoded default (5.0). Property access `ss.hope` with null `ss` should already be handled by null guards — but verify.
2. **GameManager autoload not available:** If `gm` is null, `_restore_dialogue_state()` returns early. The `"choices_history" in gm` check will short-circuit on null check.
3. **Multiple scene scripts with `scene_id`:** All 6 scene scripts need the same fix. Missing one will cause a compile error when that scene is loaded.
4. **Office.tscn FadeCurtain removal:** Verify that other scenes (lobby.tscn, street.tscn, etc.) do NOT have hardcoded FadeCurtain nodes. If they do, remove them too.

### Failure Paths

1. **Parse error persists after fixes:** Run `godot --headless --quit` immediately after each file fix to isolate. Use `grep -n` to verify no remaining `.has("` or `.get("x",` on Node-typed variables.
2. **Main.tscn Dialogue3D still missing nodes:** Verify the TSCN syntax for instancing `Dialogue3D.tscn` is correct. The `uid://dialogue_display_3d` UID must match the one defined in `Dialogue3D.tscn` line 1.
3. **New compile errors in unmodified files:** The `.has()` and `.get()` patterns may exist in other GD files not yet scanned. Run a comprehensive grep after fixes.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| `scene_base.gd` — base class for scene scripts | Stable | Low |
| `state_system.gd` — `hope`, `conviction`, `will` properties | Stable | Low — property access is idiomatic GDScript |
| `scene_manager.gd` — fade curtain creation | Stable | Low — `call_deferred` is standard pattern |
| `Dialogue3D.tscn` — self-contained scene with all child nodes | Stable | Low — scene definition is complete |
| `office.tscn` — scene file must be valid TSCN | Stable | Medium — TSCN editing requires care |
| `main.tscn` — entry scene file | Stable | Medium — instance change could affect loading |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Any feature requiring game load (all gameplay) | Critical |
| CI/CD pipeline `godot --headless --export-debug` | Critical |
| All subsequent scene development | High |

### Preparation Needed

- [ ] Run `godot --headless --quit` to establish baseline error count
- [ ] Search for `scene_id: String` patterns in new branches to prevent regressions
- [ ] Clear `.godot/imports/` cache if scene file parse issues appear

```
Fix Dependency Chain:

scene_base.gd:37 .has() fix ──► All 7 scene subclasses inherit fix automatically

office.gd:52 .has() fix      office.gd:70 .has() fix
    │                              │
    └──► Same pattern fix          └──► Same pattern fix
         for store.gd:49,                for store.gd, street.gd,
         street.gd:62                     scene_base.gd (already)

scene_manager.gd:32 call_deferred ──► Works for all scenes

office.tscn add nodes ──► Office scene renders fully
main.tscn instance fix ──► Dialogue3D displays correctly

Each subclass:
   1. Remove var scene_id     │
   2. Set in _ready()         ├──► Must fix ALL 6
   3. Replace .get(key, def)  │

Office.tscn: Remove FadeCurtain ──► SceneManager handles it
```

---

## 7. Spike / Experiment

Skipped per `depth/standard` label. Root causes are well-understood from source code analysis and direct comparison with the #137 fix patterns.

---

## 8. Continuation Context

> *This section is the handoff to the plan agent. It captures the current state so the plan agent can pick up without re-scanning all source files.*

The bug fix area has 4 categories of issues across 10 GDScript files and 2 TSCN files.

**Bug A1 — `.has()` on Node:** 5 sites in 4 files (`office.gd:52,70`, `scene_base.gd:37`, `store.gd:49`, `street.gd:62`). Fix with `"key" in node` pattern.

**Bug A2 — `.get(key, default)` on Node:** 10 sites in 4 files (`bridge.gd:44,68,81`, `lobby.gd:40`, `subway_station.gd:50`, `underpass.gd:93,94,106,130,131`). All `ss` is StateSystem (Node) — use property access `ss.hope`, `ss.conviction`, `ss.will`.

**Bug A3 — `var scene_id` redeclaration:** 6 files (`bridge.gd:13`, `lobby.gd:12`, `store.gd:11`, `street.gd:13`, `subway_station.gd:14`, `underpass.gd:13`). Remove `var`, set in `_ready()` before `super._ready()`. Pattern already proven in `office.gd`.

**Bug B1 — `add_child` in `_ready()`:** 1 site (`scene_manager.gd:32`). Use `scene_root.add_child.call_deferred(_fade_curtain)`.

**Bug B2 — Missing office scene nodes:** Add `ScreensaverText` and `DesktopText` as Label3D (LoFiText3D) under `Environments/` in office.tscn.

**Bug B3 — Missing Dialogue3D children in main.tscn:** Either instance `Dialogue3D.tscn` or add the 4 child nodes (SpeakerLabel, DialogueText, ChoiceContainer, ContinuePrompt) to the Dialogue3D node.

**Bug B4 — Duplicate FadeCurtain:** Remove lines 133-146 of office.tscn.

**Testing approach:** Run `godot --headless --quit` — should exit with code 0 and no error output. After primary fixes, check for remaining 'SCRIPT ERROR' or 'Parse Error' on stderr.

The main risk is not fixing all instances of each bug pattern — a comprehensive grep after each fix category is essential. The `scene_base.gd` fix propagates to all subclasses, so it's the highest-value single change.
