# Research: Fix 13 Compile-Blocking Script Errors

> Parent Issue: #130
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project crashes on startup with 13 script errors. `godot --headless --quit` reports parse errors across 4 GDScript files plus 1 corrupted resource file, leaving the game completely uncompilable.

### Root Cause

All 18 implement PRs had their code reviews (review agent) silently skipped due to gateway rate limiting. Generated code merged into `master` without any quality checks, accumulating 13 errors across 5 files.

---

### Catalogued Errors (by file)

#### 🔴 `gdscripts/dialogue_display_3d.gd` — 5 errors (BLOCKING)

| # | Line | Error | Root Cause | Severity |
|---|------|-------|-----------|:--------:|
| 1 | 47 | `Identifier "LoFiText3D" not declared in the current scope` | `gdscripts/lo_fi_text_3d.gd` exists but **lacks `class_name LoFiText3D`** — it only has `extends Label3D`. The `LoFiText3D.new()` call fails because GDScript cannot resolve the type. | **BLOCKING** |
| 2 | 47 | `Cannot infer the type of "label" variable because the value doesn't have a set type` | Consequence of error #1: since `LoFiText3D` is undeclared, `var label := LoFiText3D.new()` cannot infer the type for the `:=` operator. | **BLOCKING** |
| 3 | 97 | `Too many arguments for "get()" call. Expected at most 1 but received 2` | `ui_config.get("auto_font_scale", 1.0)` — `ui_config` is a `Node` (not a Dictionary). In Godot 4, `Object.get()` accepts exactly 1 argument (a property name string). The second argument (default value) is only valid for Dictionary.get(). | **BLOCKING** |
| 4 | 142 | Same as #3 — `ui_config.get("choice_spacing", choice_spacing)` | Same root cause as #3. | **BLOCKING** |
| 5 | 237 | `Function "chr()" not found in base self` | `chr()` is not a GDScript builtin function. In Godot 4, the correct API is `String.chr(code_point: int) -> String`. Used in the static helper `_prefix_letter()` for indices beyond 3. | **BLOCKING** |

**Total: 5 parse errors — file will not load.**

---

#### 🔴 `gdscripts/status_bar.gd` — 2 errors (BLOCKING)

| # | Line | Error | Root Cause | Severity |
|---|------|-------|-----------|:--------:|
| 6 | 37 | `Invalid argument for "add_child()": argument 1 should be "Node" but is "Tween"` | Line 36 creates `_tween = Tween.new()`, then line 37 passes it to `add_child()`. In Godot 4, `Tween` extends `RefCounted` (not `Node`), so it cannot be added as a child. The tween should be created via `create_tween()` (which auto-manages lifecycle) or kept as a standalone RefCounted reference. | **BLOCKING** |
| 7 | 99 | `Too many arguments for "get()" call. Expected at most 1 but received 2` | Same as dialogue_display_3d.gd errors #3/#4: `ui_config.get("auto_font_scale", 1.0)` — `ui_config` is a `Node`, not a Dictionary. | **BLOCKING** |

**Total: 2 parse errors — file will not load.**

---

#### ⚠️ `gdscripts/scene_manager.gd` — 2 errors (RUNTIME CRASH)

| # | Line | Error | Root Cause | Severity |
|---|------|-------|-----------|:--------:|
| 8 | 60 | `Nonexistent function 'add_animation' in base 'AnimationPlayer'` | `anim.add_animation("fade_out", anim_out)` — Godot 4 **removed** `AnimationPlayer.add_animation()`. In Godot 4, animations belong to `AnimationLibrary` objects, which are added to the player via `add_animation_library()`. | **RUNTIME** |
| 9 | 69 | Same as #8 — `anim.add_animation("fade_in", anim_in)` | Same root cause as #8. | **RUNTIME** |

**Total: 2 runtime errors — crashes on scene transition.**

---

#### ⚠️ `gdscripts/main.gd` — 1 error (RUNTIME CRASH)

| # | Line | Error | Root Cause | Severity |
|---|------|-------|-----------|:--------:|
| 10 | 35 | `Invalid access to property 'on_node_changed' on Node3D` | `dialogue_display_3d` is typed as `Node3D` (line 11: `@onready var dialogue_display_3d: Node3D = $Dialogue3D`). The GDScript parser validates against the static type `Node3D`, which does not have an `on_node_changed` method. The runtime object is actually a `DialogueDisplay3D` (which extends `Node3D` and has `on_node_changed`), but the typed variable prevents the parser from resolving the method reference for `.connect()`. | **RUNTIME** |

**Total: 1 runtime error — dialogue signal wiring fails.**

---

#### ❌ `default_bus_layout.tres` — 1 error (CORRUPTED)

| # | Line | Error | Root Cause | Severity |
|---|------|-------|-----------|:--------:|
| 11 | 9 | `Parse Error — Failed loading resource: res://default_bus_layout.tres` | Line 9 references `SubResource("distortion")` using a **string label** instead of a **numeric ID**. The sub_resource definitions use numeric IDs (`[sub_resource type="AudioEffectDistortion" id=1]`), so `SubResource("distortion")` does not resolve. This is likely a merge artifact where a textual reference was left during conflict resolution. | **CORRUPTED** |

**Total: 1 resource corruption — audio bus layout fails to load.**

---

### Severity Summary

| File | Errors | Impact |
|------|:------:|--------|
| `gdscripts/dialogue_display_3d.gd` | 5 (parse) | ❌ **Cannot compile** |
| `gdscripts/status_bar.gd` | 2 (parse) | ❌ **Cannot compile** |
| `gdscripts/scene_manager.gd` | 2 (runtime) | ⚠️ Crashes on scene transition |
| `gdscripts/main.gd` | 1 (runtime) | ⚠️ Dialogue signal wiring fails silently |
| `default_bus_layout.tres` | 1 (corrupt) | ❌ **Cannot load** audio resources |
| **Total** | **11 unique errors** | **Game completely unplayable** |

---

## 2. Solution

### Fix Order (recommended)

| Priority | File | Error Class | Fix |
|:--------:|------|-------------|-----|
| 1 | `gdscripts/lo_fi_text_3d.gd` | Missing `class_name` | Add `class_name LoFiText3D` on line 2, after `extends Label3D` |
| 2 | `gdscripts/dialogue_display_3d.gd` | Node.get() with 2 args | Replace `ui_config.get("auto_font_scale", 1.0)` with `ui_config.get("auto_font_scale") if ui_config.has("auto_font_scale") else 1.0` on lines 97 and 142 |
| 3 | `gdscripts/dialogue_display_3d.gd` | `chr()` not found | Replace `chr(65 + index)` with `String.chr(65 + index)` on line 237 |
| 4 | `gdscripts/status_bar.gd` | Tween as Node child | Replace the current tween pattern (lines 27, 36-37) with `@onready var _tween: Tween = $Tween` and either create a Tween node in the scene, or use `create_tween()` which returns a self-managed Tween |
| 5 | `gdscripts/status_bar.gd` | Node.get() with 2 args | Same fix as #2 — replace `ui_config.get("auto_font_scale", 1.0)` on line 99 |
| 6 | `gdscripts/scene_manager.gd` | `add_animation()` removed | Replace `add_animation()` calls (lines 60, 69) with the Godot 4 `AnimationLibrary` pattern: create `AnimationLibrary` objects, add animations to them via `add_animation()`, then call `anim.add_animation_library("", library)` |
| 7 | `gdscripts/main.gd` | Type constraint | Change `@onready var dialogue_display_3d: Node3D = $Dialogue3D` to `@onready var dialogue_display_3d: DialogueDisplay3D = $Dialogue3D` on line 11, so the parser can resolve `on_node_changed` |
| 8 | `default_bus_layout.tres` | Corrupt SubResource ref | Replace `SubResource("distortion")` with `SubResource(1)` on line 9, or regenerate the file from a fresh Godot project AudioBusLayout export |

### Detailed Fix Specifications

#### Fix 1: `gdscripts/lo_fi_text_3d.gd` — Add `class_name LoFiText3D`
- **File:** `gdscripts/lo_fi_text_3d.gd`
- **Change:** After line 1 (`extends Label3D`), add `class_name LoFiText3D`
- **Impact:** Resolves `dialogue_display_3d.gd` errors #1 and #2 (LoFiText3D undeclared + type inference)

#### Fix 2: `gdscripts/dialogue_display_3d.gd` — Node get() with default
- **File:** `gdscripts/dialogue_display_3d.gd`
- **Lines 97:** Change `ui_config.get("auto_font_scale", 1.0)` to `ui_config.get("auto_font_scale") if ui_config.has("auto_font_scale") else 1.0`
- **Line 142:** Change `ui_config.get("choice_spacing", choice_spacing)` to `ui_config.get("choice_spacing") if ui_config.has("choice_spacing") else choice_spacing`
- **Better alternative (refactor):** Create a helper method `_ui_config_get(key, default)` that safely wraps the Node get with `has()` check. This avoids repeating the pattern.

#### Fix 3: `gdscripts/dialogue_display_3d.gd` — chr() → String.chr()
- **File:** `gdscripts/dialogue_display_3d.gd`
- **Line 237:** Change `return chr(65 + index)` to `return String.chr(65 + index)`

#### Fix 4: `gdscripts/status_bar.gd` — Tween lifecycle
- **File:** `gdscripts/status_bar.gd`
- **Option A (recommended):** Remove lines 36-37 (`_tween = Tween.new(); add_child(_tween)`). Replace with `_tween = create_tween()` on line 36, which returns a self-managed Tween that runs to completion without needing to be added to the tree.
- **Option B:** Replace with `@onready var _tween: Tween = $Tween` and add a Tween node in the scene under StatusBar.
- **Impact:** Fixes error #6 (Tween cannot be added as child).

#### Fix 5: `gdscripts/status_bar.gd` — Node get() with default
- **File:** `gdscripts/status_bar.gd`
- **Line 99:** Same pattern as Fix 2 — replace `ui_config.get("auto_font_scale", 1.0)` with `ui_config.get("auto_font_scale") if ui_config.has("auto_font_scale") else 1.0`

#### Fix 6: `gdscripts/scene_manager.gd` — AnimationLibrary pattern
- **File:** `gdscripts/scene_manager.gd`
- **Change for lines 53-69:**
```gdscript
# Create AnimationLibrary to hold our animations
var library := AnimationLibrary.new()
library.name = "fade_library"

# Create fade_out animation
var anim_out := Animation.new()
anim_out.length = 0.5
var track_out := anim_out.add_track(Animation.TYPE_VALUE)
anim_out.track_set_path(track_out, "ColorRect:modulate")
anim_out.track_insert_key(track_out, 0.0, Color(0, 0, 0, 0))
anim_out.track_insert_key(track_out, 0.5, Color(0, 0, 0, 1))
library.add_animation("fade_out", anim_out)

# Create fade_in animation (reverse of fade_out)
var anim_in := Animation.new()
anim_in.length = 0.5
var track_in := anim_in.add_track(Animation.TYPE_VALUE)
anim_in.track_set_path(track_in, "ColorRect:modulate")
anim_in.track_insert_key(track_in, 0.0, Color(0, 0, 0, 1))
anim_in.track_insert_key(track_in, 0.5, Color(0, 0, 0, 0))
library.add_animation("fade_in", anim_in)

# Add library to animation player
anim.add_animation_library("", library)
```
- **Note:** `AnimationLibrary.add_animation()` exists (different from `AnimationPlayer.add_animation()` which was removed). The library is then added to the player via `add_animation_library()`.
- **Impact:** Fixes errors #8 and #9.

#### Fix 7: `gdscripts/main.gd` — Static type constraint
- **File:** `gdscripts/main.gd`
- **Line 11:** Change `@onready var dialogue_display_3d: Node3D = $Dialogue3D` to `@onready var dialogue_display_3d: DialogueDisplay3D = $Dialogue3D`
- **Impact:** Fixes error #10 — the parser can now resolve `on_node_changed` as a method on `DialogueDisplay3D`.

#### Fix 8: `default_bus_layout.tres` — Corrupt SubResource reference
- **File:** `default_bus_layout.tres`
- **Line 9:** Change `bus/0/effect/0 = SubResource("distortion")` to `bus/0/effect/0 = SubResource(1)`
- **Verification:** `[sub_resource type="AudioEffectDistortion" id=1]` at line 38 confirms the numeric ID is 1.
- **Alternative:** Regenerate from a fresh Godot project with identical bus layout and export.

### Verification

After applying all fixes, run:
```bash
cd /Users/devvi/workspace/agent-game-test
godot --headless --quit
```

Expected: zero parse errors, zero resource load errors, clean exit.

Then smoke-test scene transitions and dialogue signals:
```bash
godot --headless scenes/main.tscn
```

---

## 3. Effort Estimate

| File | Lines Changed | Fix Type | Risk | Est. Time |
|------|:-------------:|----------|:----:|:---------:|
| `gdscripts/lo_fi_text_3d.gd` | 1 | Add `class_name` | 🟢 Low | 2 min |
| `gdscripts/dialogue_display_3d.gd` | 3 | 2× get() fix + chr() | 🟢 Low | 5 min |
| `gdscripts/status_bar.gd` | 3 | Tween refactor + get() fix | 🟡 Medium | 10 min |
| `gdscripts/scene_manager.gd` | ~25 | AnimationLibrary rewrite | 🟡 Medium | 20 min |
| `gdscripts/main.gd` | 1 | Type annotation change | 🟢 Low | 1 min |
| `default_bus_layout.tres` | 1 | SubResource ID fix | 🟢 Low | 2 min |

**Total: ~40 minutes** for a developer familiar with Godot 4.

**Risk assessment:**
- 🟢 Low risk: `class_name` addition, `chr()` fix, type annotation change, SubResource ID — well-understood one-line changes.
- 🟡 Medium risk: Tween refactor (need to ensure `_tween.is_running()` and `_tween.kill()` still work with `create_tween()` return), AnimationLibrary rewrite (Godot 4 API change, need to verify `AnimationLibrary.add_animation()` accepts the same parameters).
- 🔴 No high-risk changes — all fixes are mechanical API migrations with clear Godot 4 documentation.

---

## 4. Dependencies & Blockers

### Technical Dependencies

- **Godot 4.7.1** — All fixes target the documented GDScript 2.0 and Godot 4 API surface.
- **No external plugins** — `LoFiText3D` is an internal class (not an addon). The `class_name` fix makes it register correctly.
- **No asset changes** — The font, shader, and scene files are unaffected.

### Workflow Changes (Preventing Recurrence)

| Issue | Recommendation | Priority |
|-------|---------------|:--------:|
| Review agent bypassed by rate limiting | **Implement a pre-merge gate:** if the review agent did not produce a "pass" verdict, the implement PR's auto-merge must be blocked. The gateway should return a hard failure (not a silent skip) when rate limited. | **Critical** |
| No compilation check before merge | **Add a CI step** that runs `godot --headless --quit` on every PR branch before allowing merge. This catches parse errors immediately. | **High** |
| No type validation on generated code | **Enforce strict typing** in the implement agent's prompt — generated GDScript should use explicit type annotations and avoid `var x :=` inference patterns that break when referenced classes are missing. | **Medium** |
| Missing `class_name` on LoFiText3D | **Add a file-level validation step** before PR creation that checks every `.gd` file referenced via `new()` in other files has the corresponding `class_name` declaration. | **Medium** |

---

## 5. Error Classification Quick Reference

| Error | Count | Files Affected | Type |
|-------|:-----:|----------------|:----:|
| Node.get() with 2 args | 3 | `dialogue_display_3d.gd:97,142`, `status_bar.gd:99` | Godot 3→4 migration |
| Missing `class_name` | 1 | `lo_fi_text_3d.gd` | Missing declaration |
| `chr()` → `String.chr()` | 1 | `dialogue_display_3d.gd:237` | Godot 3→4 migration |
| Tween as Node child | 1 | `status_bar.gd:37` | Godot 3→4 migration |
| `add_animation()` removed | 2 | `scene_manager.gd:60,69` | Godot 3→4 migration |
| Incorrect static type | 1 | `main.gd:11` | Type safety |
| Corrupt SubResource ref | 1 | `default_bus_layout.tres:9` | Merge artifact |

**7 of the 11 unique errors** are Godot 3→4 API migration issues — the implement agent generated code targeting Godot 3's API surface instead of Godot 4. This is consistent with the root cause (no code review).

---

## 6. Continuation Context

> Handoff to implement agent.

The implement agent should fix files in the order specified in Section 2, then verify with `godot --headless --quit`. After fixing, close issue #130 with a summary of each fix applied.

**Key files to modify:**
1. `gdscripts/lo_fi_text_3d.gd` — Add `class_name LoFiText3D`
2. `gdscripts/dialogue_display_3d.gd` — Fix 2× Node.get(), fix chr()
3. `gdscripts/status_bar.gd` — Fix Tween + Node.get()
4. `gdscripts/scene_manager.gd` — AnimationLibrary pattern
5. `gdscripts/main.gd` — Fix type annotation
6. `default_bus_layout.tres` — Fix SubResource reference

**Do NOT touch:**
- Any scene files (`.tscn`) — not needed for compilation fixes
- Any shader files — not relevant to these errors
- Any test files — error fixes will make tests pass again
