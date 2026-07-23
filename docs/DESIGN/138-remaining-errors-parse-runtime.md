# DESIGN: #138 — Parse Error, Missing Scene Nodes, add_child Race (Game Still Won't Run)

> Parent Issue: #138
> Agent: plan-agent
> Date: 2026-07-23
> Depth: standard

---

## 1. Architecture Overview

### Affected Files and Their Interactions

The bug fix area spans 10 GDScript files and 2 TSCN files across the scene-loading, state-management, and dialogue subsystems:

```
main.tscn / main.gd (entry — Node3D)
  │
  ├── $Dialogue3D ──► dialogue_display_3d.gd (DialogueDisplay3D — Node3D) [B3 — missing child nodes]
  │
  ├── $SceneManager ──► scene_manager.gd (SceneManager — Node) [B1 — add_child race]
  │                       └── creates FadeCurtain programmatically
  │
  ├── $OfficeRoot ──► office.gd (extends SceneBase) [A1, B2, B4]
  │
  ├── $Lobby ──► lobby.gd (extends SceneBase) [A2, A3]
  │
  ├── $Bridge ──► bridge.gd (extends SceneBase) [A2, A3]
  │
  ├── $Street ──► street.gd (extends SceneBase) [A1, A3]
  │
  ├── $Store ──► store.gd (extends SceneBase) [A1, A3]
  │
  ├── $SubwayStation ──► subway_station.gd (extends SceneBase) [A2, A3]
  │
  └── $Underpass ──► underpass.gd (extends SceneBase) [A2, A3]
```

All scene subclasses inherit from `scene_base.gd` (SceneBase — Node) which also has bugs [A1]. The `ss` variable in all scripts references the `StateSystem` autoload (Node subclass), and `gm` references the `GameManager` autoload (Node subclass).

### Bug Classification by Root Cause Category

| Category | Count | Files | Fix Strategy |
|----------|:-----:|-------|-------------|
| A1 — `.has()` on Node (parse error) | 5 sites | 4 files (office, scene_base, store, street) | Replace `.has("key")` with `"key" in node` |
| A2 — `.get(key, default)` on Node (parse error) | 10 sites | 4 files (bridge, lobby, subway_station, underpass) | Replace `ss.get("key", default)` with property access (`ss.hope`, etc.) |
| A3 — `var scene_id` redeclaration (parse error) | 6 files | bridge, lobby, store, street, subway_station, underpass | Remove `var`, set `scene_id = "..."` in `_ready()` before `super._ready()` |
| B1 — `add_child` during `_ready()` (runtime crash) | 1 site | scene_manager.gd | Use `add_child.call_deferred()` |
| B2 — Missing office.tscn nodes (runtime null crash) | 2 nodes | office.tscn | Add ScreensaverText + DesktopText as Label3D nodes |
| B3 — Missing Dialogue3D children (runtime null crash) | 4 nodes | main.tscn | Instance `Dialogue3D.tscn` instead of raw Node3D |
| B4 — Duplicate FadeCurtain (visual/logic glitch) | 1 scene | office.tscn | Remove hardcoded FadeCurtain block |
| **Total unique sites** | **29** | **12 files** | — |

---

## 2. File-by-File Analysis

### 2.1. Bug A1: `.has()` on Node — Parse Error

**Root cause:** Variables typed as `Node` (StateSystem, GameManager from `get_node_or_null()`) use `.has("key")` which is a Dictionary method. GDScript 2.0's static typing rejects it because `Node` does not support duck-typed `.has()`.

**Design decision:** Replace with `"key" in node` — the `in` operator works for both Dictionary keys and object properties in GDScript 2.0, and type-checks correctly.

**Affected sites (5 across 4 files):**

| File | Line | Old Code | New Code |
|------|------|----------|----------|
| `office.gd` | 52 | `ss.has("day")` | `"day" in ss` |
| `office.gd` | 70 | `gm.has("choices_history")` | `"choices_history" in gm` |
| `scene_base.gd` | 37 | `gm.has("choices_history")` | `"choices_history" in gm` |
| `store.gd` | 49 | `gm.has("choices_history")` | `"choices_history" in gm` |
| `street.gd` | 62 | `gm.has("choices_history")` | `"choices_history" in gm` |

**Key insight:** Fixing `scene_base.gd:37` propagates to ALL 7 scene subclasses automatically.

**Risk:** 🟢 Low. The `in` operator is a compile-time type-checked expression. Identical semantics for property existence checks.

---

### 2.2. Bug A2: `.get(key, default)` on Node — Parse Error

**Root cause:** `ss` is the `StateSystem` autoload (extends Node). `Node.get()` accepts only 1 argument (`StringName key`). The 2-argument form with a default value is `Dictionary.get()`. GDScript reports "Expected at most 1 but received 2."

**Design decision:** Replace with direct property access on `StateSystem`. StateSystem exposes `hope`, `conviction`, and `will` as properties with getters. Use `ss.hope`, `ss.conviction`, `ss.will` directly.

Each access should be null-guarded: `ss.will if ss else 5.0` in case StateSystem is not available.

**Affected sites (10 across 4 files):**

| File | Line | Old Code | New Code |
|------|------|----------|----------|
| `bridge.gd` | 44 | `ss.get("will", 5.0)` | `ss.will if ss else 5.0` |
| `bridge.gd` | 68 | `ss.get("conviction", 5.0)` | `ss.conviction if ss else 5.0` |
| `bridge.gd` | 81 | `ss.get("conviction", 5.0)` | `ss.conviction if ss else 5.0` |
| `lobby.gd` | 40 | `ss.get("conviction", 5.0)` | `ss.conviction if ss else 5.0` |
| `subway_station.gd` | 50 | `ss.get("conviction", 5.0)` | `ss.conviction if ss else 5.0` |
| `underpass.gd` | 93 | `ss.get("hope", 5.0)` | `ss.hope if ss else 5.0` |
| `underpass.gd` | 94 | `ss.get("conviction", 5.0)` | `ss.conviction if ss else 5.0` |
| `underpass.gd` | 106 | `ss.get("hope", 5.0)` | `ss.hope if ss else 5.0` |
| `underpass.gd` | 130 | `ss.get("hope", 5.0)` | `ss.hope if ss else 5.0` |
| `underpass.gd` | 131 | `ss.get("conviction", 5.0)` | `ss.conviction if ss else 5.0` |

**Risk:** 🟢 Low. Mechanical one-to-one substitution. Property access is idiomatic GDScript.

---

### 2.3. Bug A3: `var scene_id` Redeclaration — Parse Error

**Root cause:** GDScript 2.0 forbids subclasses from redeclaring members inherited from base classes. `SceneBase` declares `var scene_id: String = ""` on line 10. Every scene script redeclaring `var scene_id: String = "..."` triggers a compile error.

**Design decision:** Follow the pattern proven in `office.gd` (fixed in PR #137): remove the `var` redeclaration and set `scene_id = "..."` in `_ready()` **before** calling `super._ready()`.

```
# OLD:
var scene_id: String = "lobby"  # redeclaration — parse error
func _ready() -> void:
    super._ready()
    ...

# NEW:
func _ready() -> void:
    scene_id = "lobby"
    super._ready()
    ...
```

**Affected files (6):**

| File | Line | Old Value | Fix |
|------|:----:|-----------|-----|
| `bridge.gd` | 13 | `var scene_id: String = "bridge"` | Remove `var`, set in `_ready()` |
| `lobby.gd` | 12 | `var scene_id: String = "lobby"` | Remove `var`, set in `_ready()` |
| `store.gd` | 11 | `var scene_id: String = "convenience_store"` | Remove `var`, set in `_ready()` |
| `street.gd` | 13 | `var scene_id: String = "street"` | Remove `var`, set in `_ready()` |
| `subway_station.gd` | 14 | `var scene_id: String = "subway_station"` | Remove `var`, set in `_ready()` |
| `underpass.gd` | 13 | `var scene_id: String = "underpass"` | Remove `var`, set in `_ready()` |

**Important:** Must set `scene_id` BEFORE `super._ready()` so the base class can use it correctly.

**Risk:** 🟢 Low. Pattern validated in PR #137 for `office.gd`. All 6 need the identical fix.

---

### 2.4. Bug B1: `add_child` During `_ready()` — Runtime Crash

**Root cause:** `scene_manager.gd:_setup_fade_curtain()` is called from `_ready()` (line 19). Godot 4's scene tree prevents `add_child()` while a node is in the middle of its `_ready()` callbacks.

**Design decision:** Replace with `scene_root.add_child.call_deferred(_fade_curtain)`. The `call_deferred()` pattern queues the `add_child` to execute after the current `_ready()` call stack completes.

**Affected site:** `scene_manager.gd:32`

```gdscript
# OLD:
scene_root.add_child(_fade_curtain)

# NEW:
scene_root.add_child.call_deferred(_fade_curtain)
```

**Risk:** 🟢 Low. `call_deferred()` is the canonical Godot 4 pattern recommended by the engine's own error message.

---

### 2.5. Bug B2: Missing Office Scene Nodes — Runtime Null Crash

**Root cause:** `office.gd:8-9` declares `@onready var screensaver_text: Label3D = $Environments/ScreensaverText` and `@onready var desktop_text: Label3D = $Environments/DesktopText`, but these nodes don't exist in `office.tscn`. When `_configure_environmental_text()` tries to set `.text` on these null references, it crashes.

**Design decision:** Add two Label3D nodes to `office.tscn` under the `Environments/` path. Both should use the `LoFiText3D` script (same as the existing `WindowText` node) to match the project's text rendering conventions.

**Node definitions to add:**
- `Environments/ScreensaverText` — Label3D with LoFiText3D script, positioned appropriately
- `Environments/DesktopText` — Label3D with LoFiText3D script, positioned appropriately

**Approach for TSCN editing:** Duplicate the existing `Environments/WindowText` block and adjust name, position, and node paths.

**Risk:** 🟡 Medium. TSCN file format requires careful syntax. Node paths, indentation, and resource references must be exact. Duplicate an existing node as template to minimize error.

---

### 2.6. Bug B3: Missing Dialogue3D Children in main.tscn — Runtime Null Crash

**Root cause:** `dialogue_display_3d.gd:18-21` references `$SpeakerLabel`, `$DialogueText`, `$ChoiceContainer`, `$ContinuePrompt` via `@onready` variables. These nodes are defined in `Dialogue3D.tscn` but `main.tscn` creates the `Dialogue3D` node as a plain `Node3D` with only the script attached — the child nodes are never instantiated.

**Design decision (Option B3a from PRD):** Change the Dialogue3D node in `main.tscn` to instance `Dialogue3D.tscn` instead of being a raw Node3D. This reuses the existing well-defined scene and avoids duplication.

**Current TSCN block:**
```tscn
[node name="Dialogue3D" type="Node3D" parent="."]
position = Vector3(0, 1.5, -3)
script = ExtResource("4_dialogue_3d")
```

**Replacement:**
```tscn
[node name="Dialogue3D" parent="." instance=ExtResource("4_dialogue_3d")]
position = Vector3(0, 1.5, -3)
```

**Note:** The `ExtResource` ID `"4_dialogue_3d"` is the same resource reference that was assigned to the `script = ExtResource("4_dialogue_3d")` line — `Dialogue3D.tscn` is a self-contained scene with the script and all child nodes, so instancing it provides everything needed.

**Alternative (Option B3b):** Add the 4 child nodes inline in main.tscn. Rejected in favor of B3a because B3a reuses the canonical scene definition and avoids duplication.

**Risk:** 🟡 Medium. Changing a TSCN node from typed to instanced changes how the scene loads. The `instance=ExtResource(...)` syntax must be valid. Verify that `Dialogue3D.tscn` has a proper UID and that no child overrides are needed (position is preserved as a property override).

---

### 2.7. Bug B4: Duplicate FadeCurtain in office.tscn — Visual/Logic Glitch

**Root cause:** `office.tscn` (lines 133-146) defines a `FadeCurtain` CanvasLayer node with ColorRect and AnimationPlayer. Meanwhile, `scene_manager.gd` programmatically creates its own FadeCurtain. The `_setup_fade_curtain()` function checks `has_node("FadeCurtain")` first, so the scene's pre-existing one is found and the script's expected AnimationPlayer (`_fade_anim`) may not match.

**Design decision:** Remove the hardcoded FadeCurtain block from `office.tscn` (approximately lines 133-146). SceneManager will create it programmatically for all scenes that don't have one.

**Verification step:** Check other .tscn files (lobby.tscn, street.tscn, store.tscn, etc.) for similar hardcoded FadeCurtain nodes. If any exist, remove them too for consistency.

**Risk:** 🟢 Low. SceneManager is designed to handle scenes without FadeCurtain — it creates one on demand if `has_node("FadeCurtain")` returns false.

---

## 3. Component Interaction After Fixes

```
Scene loading sequence (after all fixes):

godot --headless --quit
    │
    ├──► Load main.gd
    │       └──► _ready()
    │               ├──► Connect dialogue signals
    │               │       └──► Dialogue3D fully instanced from Dialogue3D.tscn [B3 FIXED]
    │               │               ├── SpeakerLabel ✓
    │               │               ├── DialogueText ✓
    │               │               ├── ChoiceContainer ✓
    │               │               └── ContinuePrompt ✓
    │               └──► call_deferred("_load_starting_scene")
    │                       └──► change_scene_to_file("office.tscn")
    │
    ├──► Load office.tscn
    │       ├──► Instance children
    │       │       ├──► Environments/WindowText ✓
    │       │       ├──► Environments/ScreensaverText ✓ [B2 FIXED]
    │       │       ├──► Environments/DesktopText ✓ [B2 FIXED]
    │       │       └──► No hardcoded FadeCurtain [B4 FIXED]
    │       ├──► SceneManager._ready()
    │       │       └──► _setup_fade_curtain() via call_deferred [B1 FIXED]
    │       └──► office.gd _ready()
    │               ├──► scene_id = "office" (set in _ready(), no var redeclare)
    │               ├──► super._ready() → SceneBase._ready()
    │               │       ├──► scene_manager.fade_in()
    │               │       ├──► _configure_environmental_text()
    │               │       │       └──► "day" in ss ✓ [A1 FIXED]
    │               │       └──► _restore_dialogue_state()
    │               │               └──► "choices_history" in gm ✓ [A1 FIXED]
    │               └──► door_trigger.input_event.connect(...)
    │
    └──► Other scenes (lobby, store, etc.)
            ├──► scene_id set in _ready() ✓ [A3 FIXED]
            └──► Property access ss.hope, ss.conviction ✓ [A2 FIXED]
```

---

## 4. Fix Verification Criteria

| Fix # | Bug | File(s) | Verification Criterion |
|:-----:|:---:|---------|----------------------|
| 1 | A1 | `scene_base.gd` | `"choices_history" in gm` compiles without error |
| 2 | A1 | `office.gd` | `"day" in ss` and `"choices_history" in gm` compile without error |
| 3 | A1 | `store.gd` | `"choices_history" in gm` compiles without error |
| 4 | A1 | `street.gd` | `"choices_history" in gm` compiles without error |
| 5 | A2 | `bridge.gd` | `ss.will` / `ss.conviction` compile without error |
| 6 | A2 | `lobby.gd` | `ss.conviction` compiles without error |
| 7 | A2 | `subway_station.gd` | `ss.conviction` compiles without error |
| 8 | A2 | `underpass.gd` | `ss.hope` / `ss.conviction` compile without error |
| 9 | A3 | 6 scene scripts | No "redeclaration of 'scene_id'" errors |
| 10 | B1 | `scene_manager.gd` | No "busy setting up children" runtime error |
| 11 | B2 | `office.tscn` | ScreensaverText + DesktopText exist, no null reference |
| 12 | B3 | `main.tscn` | Dialogue3D has all child nodes, no null reference |
| 13 | B4 | `office.tscn` | No hardcoded FadeCurtain, SceneManager handles it |

**Primary verification command:**
```bash
godot --headless --quit
```
Expected: exit code 0 with zero parse errors and zero runtime errors on stderr.

**Secondary verification (scene load smoke test):**
```bash
godot --headless scenes/main.tscn
```
Expected: loads without error, all scene scripts compile and execute cleanly.

---

## 5. Risk Assessment

| Fix | Bug | Risk | Rationale | Mitigation |
|:---:|:---:|:----:|-----------|------------|
| 1-4 | A1 | 🟢 Low | Mechanical `.has()` → `"in"` substitution; compiler-verified | Verify with `--headless --quit` |
| 5-8 | A2 | 🟢 Low | Mechanical `.get()` → property access; 1-to-1 mapping | Verify with `--headless --quit` |
| 9 | A3 | 🟢 Low | Pattern validated in PR #137; all 6 files same fix | Verify with `--headless --quit` |
| 10 | B1 | 🟢 Low | `call_deferred()` is canonical Godot 4 pattern | Verify with `--headless --quit` |
| 11 | B2 | 🟡 Medium | TSCN syntax requires precision; node positioning needed | Duplicate existing WindowText as template |
| 12 | B3 | 🟡 Medium | TSCN instance syntax; verify Dialogue3D.tscn resource ID | Test after change; verify child nodes exist |
| 13 | B4 | 🟢 Low | SceneManager already handles missing FadeCurtain | Verify other scenes don't have duplicate |

---

## 6. Fix Order and Dependencies

```
Execution order:
  1. scene_base.gd:37 (A1)         — base class fix, propagates to all subclasses
  2. office.gd:52,70 (A1)          — remaining .has() in office
  3. store.gd:49 (A1)              — remaining .has() in store
  4. street.gd:62 (A1)             — remaining .has() in street
  5. bridge.gd:44,68,81 (A2)       — .get() → property access
  6. lobby.gd:40 (A2)              — .get() → property access
  7. subway_station.gd:50 (A2)     — .get() → property access
  8. underpass.gd:93,94,106,130,131 (A2) — .get() → property access
  9. bridge.gd:13 (A3)             — remove var scene_id
 10. lobby.gd:12 (A3)              — remove var scene_id
 11. store.gd:11 (A3)              — remove var scene_id
 12. street.gd:13 (A3)             — remove var scene_id
 13. subway_station.gd:14 (A3)     — remove var scene_id
 14. underpass.gd:13 (A3)          — remove var scene_id
 15. scene_manager.gd:32 (B1)      — add_child.call_deferred()
 16. office.tscn (B2+B4)           — add ScreensaverText, DesktopText; remove FadeCurtain
 17. main.tscn (B3)                — instance Dialogue3D.tscn

Dependencies:
  - All A1 fixes are independent of each other (except scene_base.gd propagates)
  - All A2 fixes are independent of each other
  - All A3 fixes are independent of each other
  - B1-B4 are independent of A1-A3
  - B2 and B4 both modify office.tscn — apply together to avoid merge conflicts
  - No strict ordering dependencies — all changes are in separate files or are grouped
```

---

## 7. Recurrence Prevention

Key measures from the PRD:
- **Pre-merge compilation gate:** Run `godot --headless --quit` as CI step — will catch any future `.has()` on Node or `.get(key, default)` regressions
- **Comprehensive grep after each fix category:** Run `grep -rn '\.has("' --include='*.gd'` and `grep -rn '\.get("[a-z]' --include='*.gd'` to verify no remaining occurrences
- **Check for `var scene_id` in new scene scripts:** Any new scene subclass of SceneBase must avoid redeclaring `scene_id`
