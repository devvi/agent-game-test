# DESIGN: #130 — Fix 13 Compile-Blocking Script Errors

> Parent Issue: #130
> Agent: plan-agent
> Date: 2026-07-23
> Depth: deep

---

## 1. Architecture Overview

### Affected Files and Their Interactions

The five source files and one resource file that need fixes form part of the game's dialogue, UI, and scene-transition subsystems:

```
main.gd (entry scene — Node3D)
  │
  ├── $Dialogue3D ──► dialogue_display_3d.gd (DialogueDisplay3D — Node3D)
  │                       │
  │                       └── LoFiText3D.new()  ──► lo_fi_text_3d.gd (LoFiText3D — Label3D)
  │
  ├── $StatusBar ──► status_bar.gd (StatusBar — CanvasLayer)
  │                       │
  │                       └── uses Tween (RefCounted, NOT Node)
  │
  ├── $SceneManager ──► scene_manager.gd (SceneManager — Node)
  │                       │
  │                       └── creates AnimationPlayer dynamically
  │
  └── /root/UIConfig (singleton) — queried by both dialogue_display_3d.gd & status_bar.gd

default_bus_layout.tres — loaded automatically by Godot AudioServer at startup
```

### Error Classification by Root Cause Category

| Category | Count | Files | Fix Strategy |
|----------|:-----:|-------|-------------|
| Godot 3→4 API migration | 7 | dialogue_display_3d, status_bar, scene_manager, main | Use Godot 4 equivalents (create_tween(), AnimationLibrary, String.chr(), typed get()) |
| Missing declaration | 1 | lo_fi_text_3d | Add `class_name` |
| Type safety | 1 | main | Relax/retarget static type |
| Merge artifact (corrupt ref) | 1 | default_bus_layout.tres | String→numeric SubResource ID |
| **Total unique errors** | **10*** | 6 files | — |

*\*11 unique errors originally catalogued; errors #1 and #2 in the PRD (LoFiText3D undeclared + type inference failure) are both resolved by the single Fix 1 (`class_name LoFiText3D`), so 10 distinct fix actions cover all 11 error locations.*

---

## 2. File-by-File Analysis

### 2.1. `gdscripts/lo_fi_text_3d.gd` — Missing `class_name`

**Current state:** `extends Label3D` only. Other files reference `LoFiText3D.new()` but GDScript has no way to resolve the type.

**Design decision:** Add `class_name LoFiText3D` immediately after `extends Label3D`. This is the canonical Godot 4 pattern for declaring a globally-registered script class. Alternatives considered:
- **Preloading via `preload()` in each consumer** — fragile, duplicates path knowledge across files.
- **Using `load()` in consumers** — runtime cost, would need changes in 3 files instead of 1.

**Risk:** 🟢 Low. Single-line addition with zero side effects. `class_name` is a compile-time only declaration.

### 2.2. `gdscripts/dialogue_display_3d.gd` — Two Node.get() Calls + chr()

**Error 1 (lines 97, 142):** `ui_config.get("auto_font_scale", 1.0)` and `ui_config.get("choice_spacing", choice_spacing)` — `ui_config` is a `Node` (from `get_node_or_null("/root/UIConfig")`), not a `Dictionary`. `Object.get()` in Godot 4 takes exactly 1 argument (a property name); passing a default value is a Dictionary-only feature.

**Design decision:** Replace with `ui_config.get("auto_font_scale") if ui_config.has("auto_font_scale") else 1.0`. This pattern:
- First checks if the property exists via `has()` (which Object does support)
- If not, returns the default
- Is more explicit about the fallback behavior

**Alternative considered:** Creating a helper method `_ui_config_get(key, default)` to avoid repeating the pattern. Rejected for now because the pattern only appears twice in this file (and once in status_bar.gd); a helper adds indirection with minimal gain. The implement agent can optionally extract it.

**Error 2 (line 237):** `chr(65 + index)` — `chr()` is a Python builtin, not a GDScript builtin. Godot 4 provides `String.chr()` as a static method.

**Design decision:** Replace with `String.chr(65 + index)`. Trivial one-to-one API mapping.

**Risk:** 🟢 Low for all three changes. Type-checked by the GDScript compiler.

### 2.3. `gdscripts/status_bar.gd` — Tween Lifecycle + Node.get()

**Error 1 (lines 36-37):** `_tween = Tween.new(); add_child(_tween)` — In Godot 4, `Tween` extends `RefCounted` (not `Node`), so `add_child()` rejects it.

**Design decision:** Replace with `_tween = create_tween()`. The `create_tween()` method (available on any `Node`) returns a self-managed `Tween` that:
- Lives as long as it's running (RefCounted lifecycle)
- Does not need to be added to the scene tree
- Supports all the same chaining API (`tween_property()`, `parallel()`, `kill()`, `is_running()`)

The existing code at lines 53-54 and 78-79 already calls `_tween.is_running()` and `_tween.kill()` — these methods work identically on `create_tween()` results.

**Alternative considered:** Using `@onready var _tween: Tween = $Tween` and adding a Tween node in the scene file. Rejected — modifying scene files is out of scope, and `create_tween()` is the idiomatic Godot 4 approach.

**Error 2 (line 99):** `ui_config.get("auto_font_scale", 1.0)` — same root cause as dialogue_display_3d.gd.

**Design decision:** Same fix: `ui_config.get("auto_font_scale") if ui_config.has("auto_font_scale") else 1.0`.

**Risk:** 🟡 Medium (Tween refactor). `create_tween()` returns a `Tween` that auto-starts. Need to verify that `_update_bar_immediate` (called from `_ready` before `_tween` was set up with `create_tween()`) doesn't break — both `_update_bar_immediate` and `_update_bar` check `_tween.is_running()` first, but `_tween` will now be `null` until `_ready` runs. This is safe because `_ready` initializes `_tween` before calling `_update_bar_immediate`.

### 2.4. `gdscripts/scene_manager.gd` — AnimationLibrary Rewrite

**Error (lines 60, 69):** `anim.add_animation("fade_out", anim_out)` and `anim.add_animation("fade_in", anim_in)` — In Godot 3, `AnimationPlayer` had `add_animation()`. In Godot 4, this was removed; animations belong to `AnimationLibrary` objects.

**Design decision:** Restructure the animation creation to use the Godot 4 `AnimationLibrary` pattern:

```gdscript
# Before (Godot 3 API — BROKEN):
anim.add_animation("fade_out", anim_out)
anim.add_animation("fade_in", anim_in)

# After (Godot 4 API):
var library := AnimationLibrary.new()
library.name = "fade_library"
library.add_animation("fade_out", anim_out)
library.add_animation("fade_in", anim_in)
anim.add_animation_library("", library)
```

Key insight: `AnimationLibrary.add_animation()` exists in Godot 4 and accepts an `(animation_name: String, animation: Animation)` signature. The method that was removed is `AnimationPlayer.add_animation()`.

**Data flow after fix:**
```
AnimationPlayer
  └── AnimationLibrary("")
        ├── "fade_out" → Animation (ColorRect:modulate 0→1 over 0.5s)
        └── "fade_in"  → Animation (ColorRect:modulate 1→0 over 0.5s)
```

**Risk:** 🟡 Medium. The `play("fade_out", ...)` and `play("fade_in", ...)` calls in `trigger_scene_change()` (line 118) and `fade_in()` (line 146) continue to work unchanged — animations are still accessible by name. The `library.name` is cosmetic (not referenced). The empty string library name `""` means the library is the default library, so animation names are at the top-level namespace.

### 2.5. `gdscripts/main.gd` — Static Type Constraint

**Error (line 11):** `@onready var dialogue_display_3d: Node3D = $Dialogue3D` — The variable is typed as `Node3D`, but the actual runtime object is `DialogueDisplay3D` (which extends Node3D). The GDScript parser validates `.connect()` calls against the static type, and `Node3D` doesn't have `on_node_changed`, `on_choices_available`, or `on_dialogue_ended`.

**Design decision:** Change the type to `DialogueDisplay3D`:
```
@onready var dialogue_display_3d: DialogueDisplay3D = $Dialogue3D
```

Since `DialogueDisplay3D` has `class_name DialogueDisplay3D` (line 2 of dialogue_display_3d.gd), this type is already registered and parsable.

**Alternative considered:** Dropping the explicit type entirely (`@onready var dialogue_display_3d = $Dialogue3D`). Rejected — explicit typing is project convention and provides better IDE support.

**Risk:** 🟢 Low. Single-character-type change. No runtime behavior difference.

### 2.6. `default_bus_layout.tres` — Corrupt SubResource Reference

**Error (line 9):** `SubResource("distortion")` — a string label instead of a numeric ID. The sub-resource definition at line 38 uses `[sub_resource type="AudioEffectDistortion" id=1]`, so `SubResource("distortion")` is a merge artifact.

**Design decision:** Replace `SubResource("distortion")` with `SubResource(1)`. Verify all other SubResource references:
- Line 28: `SubResource("indoor_lpf")` → should be `SubResource(2)`
- Line 35: `SubResource("underpass_reverb")` → should be `SubResource(3)`
- Line 36: `SubResource("underpass_lpf")` → should be `SubResource(4)`

**Correction to PRD finding:** The PRD identified only line 9, but the investigation reveals lines 28, 35, and 36 also use string labels referencing sub-resources with numeric IDs. All four occurrences must be fixed.

**Mapping:**
| String Label | Numeric ID | Sub-resource Type |
|-------------|:----------:|-------------------|
| `"distortion"` | `1` | AudioEffectDistortion (line 38) |
| `"indoor_lpf"` | `2` | AudioEffectLowPassFilter (line 42) |
| `"underpass_reverb"` | `3` | AudioEffectReverb (line 47) |
| `"underpass_lpf"` | `4` | AudioEffectLowPassFilter (line 54) |

**Risk:** 🟢 Low. Trivial ID substitution. The resource format is well-understood.

---

## 3. Component Interaction After Fixes

```
main.gd (entry scene — Node3D)
  │
  ├── $Dialogue3D ──► dialogue_display_3d.gd (DialogueDisplay3D — Node3D) [FIXED]
  │                       │                        ✓ Node.get() → safe has/get pattern
  │                       │                        ✓ String.chr() instead of chr()
  │                       └── LoFiText3D.new()  ──► lo_fi_text_3d.gd (LoFiText3D — Label3D) [FIXED]
  │                                                    ✓ class_name LoFiText3D added
  │
  ├── $StatusBar ──► status_bar.gd (StatusBar — CanvasLayer) [FIXED]
  │                       │           ✓ create_tween() instead of Tween.new()+add_child()
  │                       │           ✓ Node.get() → safe has/get pattern
  │                       └── _tween: Tween (RefCounted, NOT in scene tree)
  │
  ├── $SceneManager ──► scene_manager.gd (SceneManager — Node) [FIXED]
  │                       │           ✓ AnimationLibrary pattern for animations
  │                       └── AnimationPlayer
  │                             └── AnimationLibrary("")
  │                                   ├── "fade_out"
  │                                   └── "fade_in"
  │
  └── /root/UIConfig — queried by dialogue_display_3d & status_bar (both use safe get pattern)

AudioServer
  └── default_bus_layout.tres [FIXED]
        └── SubResource references use numeric IDs
```

---

## 4. Fix Verification Criteria

| Fix # | File | Verification Criterion |
|:-----:|------|----------------------|
| 1 | `lo_fi_text_3d.gd` | `godot --headless --quit` produces no "LoFiText3D not declared" errors |
| 2-3 | `dialogue_display_3d.gd` | No "Too many arguments for get()" or "chr() not found" errors |
| 4-5 | `status_bar.gd` | No "Invalid argument for add_child()" or "Too many arguments for get()" errors |
| 6 | `scene_manager.gd` | No "Nonexistent function 'add_animation'" errors on scene transition |
| 7 | `main.gd` | No "Invalid access to property 'on_node_changed' on Node3D" errors |
| 8 | `default_bus_layout.tres` | No "Failed loading resource: res://default_bus_layout.tres" errors |

**Primary verification command:**
```bash
godot --headless --quit
```
Expected: exit code 0 with zero parse errors.

**Secondary verification (runtime smoke test):**
```bash
godot --headless scenes/main.tscn
```
Expected: loads without error, exits cleanly.

---

## 5. Risk Assessment

| Fix | Risk Level | Rationale | Mitigation |
|:---:|:----------:|-----------|------------|
| 1 | 🟢 Low | Single `class_name` addition, no code paths change | Verify with `--headless --quit` |
| 2-3 | 🟢 Low | Mechanical replacements, compiler-verified | Verify with `--headless --quit` |
| 4 | 🟡 Medium | Tween lifecycle changes — `create_tween()` returns auto-started Tween | Check `_update_bar_immediate` / `_ready` ordering; verify tween `.kill()` and `.is_running()` work on `create_tween()` result |
| 5 | 🟢 Low | Same pattern as Fix 2 | Verify with `--headless --quit` |
| 6 | 🟡 Medium | ~25 lines of new code; `AnimationLibrary` API correctness | Verify scene transitions trigger correctly; check that `play("fade_out")` still works |
| 7 | 🟢 Low | Single type annotation change | Verify with `--headless --quit` |
| 8 | 🟢 Low | 4 numeric ID substitutions | Verify with `--headless --quit` |

---

## 6. Migration Path Summary

```
Fix Order:
  1. lo_fi_text_3d.gd     (class_name)        — enables Fix 2's type resolution
  2. dialogue_display_3d.gd (Node.get() ×2)   — parse error removal
  3. dialogue_display_3d.gd (String.chr())    — parse error removal
  4. status_bar.gd          (Tween lifecycle)  — parse error removal
  5. status_bar.gd          (Node.get())       — parse error removal
  6. scene_manager.gd       (AnimationLibrary) — runtime crash fix
  7. main.gd                (type annotation)  — runtime crash fix
  8. default_bus_layout.tres (SubResource ×4)  — resource load fix

Dependency chain:
  Fix 1 must precede Fix 2 (dialogue_display_3d imports LoFiText3D)
  Fix 4 must not break _ready() ordering (Tween init before use)
  All other fixes are independent and can be applied in any order
```

---

## 7. Recurrence Prevention

See the PRD (docs/PRD/130-compile-errors.md, Section 4) for detailed workflow recommendations. Key measures:
- **Pre-merge compilation gate:** Run `godot --headless --quit` as CI step
- **Hard failure on review bypass:** Gateway rate-limiting must surface as error, not silent skip
- **Strict typing in generated code:** Avoid `var x :=` inference patterns in code-gen prompts
- **Cross-file dependency validation:** Check every `.gd` file referenced via `new()` has the corresponding `class_name`
