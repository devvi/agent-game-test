# Tasks: #130 — Fix 13 Compile-Blocking Script Errors

> Parent Issue: #130
> Priority: critical
> Estimated: 40 minutes
> Prerequisite: Research PR #131 (merged), Research branch: research/130-compile-errors
> Design Reference: `docs/DESIGN/130-compile-errors.md`

---

## Task Breakdown

### Phase 1 — Parse Errors (P0)

**Rationale:** 7 parse errors across 3 files (dialogue_display_3d, status_bar, lo_fi_text_3d) prevent the game from even starting. These must be fixed first to enable any runtime testing.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Add `class_name LoFiText3D` to lo_fi_text_3d.gd | `gdscripts/lo_fi_text_3d.gd` | None | 2 min |
| T2 | Fix Node.get() with 2 args (×2) in dialogue_display_3d.gd | `gdscripts/dialogue_display_3d.gd` | T1 | 3 min |
| T3 | Replace `chr()` with `String.chr()` in dialogue_display_3d.gd | `gdscripts/dialogue_display_3d.gd` | None | 1 min |
| T4 | Fix Tween lifecycle in status_bar.gd | `gdscripts/status_bar.gd` | None | 5 min |
| T5 | Fix Node.get() with 2 args in status_bar.gd | `gdscripts/status_bar.gd` | None | 2 min |

#### T1 Details — class_name LoFiText3D

**File:** `gdscripts/lo_fi_text_3d.gd`

**Change:** After line 1 (`extends Label3D`), add:
```gdscript
class_name LoFiText3D
```

**Verification:** After fix, `var label := LoFiText3D.new()` in dialogue_display_3d.gd must compile without error.

**Edge cases:** None. This is a compile-time declaration with zero runtime side effects.

---

#### T2 Details — Fix Node.get() in dialogue_display_3d.gd

**File:** `gdscripts/dialogue_display_3d.gd`

**Change line 97:**
```gdscript
# Before:
var scale_factor: float = ui_config.get("auto_font_scale", 1.0)
# After:
var scale_factor: float = ui_config.get("auto_font_scale") if ui_config.has("auto_font_scale") else 1.0
```

**Change line 142:**
```gdscript
# Before:
spacing = ui_config.get("choice_spacing", choice_spacing)
# After:
spacing = ui_config.get("choice_spacing") if ui_config.has("choice_spacing") else choice_spacing
```

**Optional refactor:** If both fixes are applied together, consider extracting a helper:
```gdscript
func _ui_config_get(key: String, default: Variant) -> Variant:
    var cfg := get_node_or_null("/root/UIConfig")
    if cfg != null and cfg.has(key):
        return cfg.get(key)
    return default
```
This avoids repeating the `has()` / `get()` pattern across 3 call sites (2 here + 1 in status_bar.gd).

**Test scenario:** Set up a test scene with `UIConfig` singleton registered. Call `on_node_changed()` with and without UIConfig present. Verify:
- With UIConfig: font scale from config is applied
- Without UIConfig: default value (1.0 / choice_spacing) is used without error
- UIConfig with missing property: falls through to default

---

#### T3 Details — Replace chr() with String.chr()

**File:** `gdscripts/dialogue_display_3d.gd`

**Change line 237:**
```gdscript
# Before:
return chr(65 + index)
# After:
return String.chr(65 + index)
```

**Test scenario:** Call `_prefix_letter()` with indices 0-25. Verify:
- Indices 0-3 return "A" through "D" (match statement, unchanged)
- Index 4 returns "E", 5 returns "F", etc.
- Indices beyond 25 still return the correct Unicode codepoint

---

#### T4 Details — Fix Tween Lifecycle

**File:** `gdscripts/status_bar.gd`

**Changes:**

1. **Line 27:** Remove the `@onready var _tween: Tween` line — the variable will be initialized in `_ready()` instead.

```gdscript
# Before (line 27):
@onready var _tween: Tween

# After:
# (remove this line entirely — _tween will be declared in _ready)
```

2. **Lines 36-37:** Replace Tween.new() + add_child() with create_tween():
```gdscript
# Before:
_tween = Tween.new()
add_child(_tween)

# After:
_tween = create_tween()
```

3. **IMPORTANT: Variable declaration.** Ensure `_tween` is still declared at the class level (line 30 `var _current_ratio: float = 0.5` area) as:
```gdscript
var _tween: Tween
```
(This already exists implicitly via the `@onready var _tween: Tween` on line 27 — removing the `@onready` prefix and keeping `var _tween: Tween` works.)

**Corrected approach:** Instead of removing `@onready var _tween: Tween` (line 27), simply keep it as a plain member variable declaration and change the initialization in `_ready()`:
```gdscript
# Line 27: Keep as member declaration (remove @onready)
var _tween: Tween
```

Then in `_ready()`:
```gdscript
_tween = create_tween()
```

**Test scenarios:**
1. **Rapid state changes (compaction):** Call `_on_state_changed()` twice in quick succession. Verify that the first tween is killed (not orphaned) and the second starts cleanly. Check for leaked Tween objects.
2. **Initial render:** Verify `_update_bar_immediate(0.5)` in `_ready()` works — `_tween.is_running()` on a `null` or `create_tween()` result should not crash.
3. **Tween chaining:** Verify that `_tween.tween_property()` and `_tween.parallel()` calls after `create_tween()` work identically to the old pattern.
4. **Cleanup:** Verify `_tween.kill()` on a finished tween is a no-op (doesn't crash).

---

#### T5 Details — Fix Node.get() in status_bar.gd

**File:** `gdscripts/status_bar.gd`

**Change line 99:**
```gdscript
# Before:
scale_factor = ui_config.get("auto_font_scale", 1.0)
# After:
scale_factor = ui_config.get("auto_font_scale") if ui_config.has("auto_font_scale") else 1.0
```

**Test scenarios:** Same as T2 but for the status bar layout:
- StatusBar with UIConfig: layout scales correctly
- StatusBar without UIConfig: defaults to 1.0 scale
- StatusBar with UIConfig missing auto_font_scale: defaults to 1.0

---

### Phase 2 — Runtime Errors (P1)

**Rationale:** 2 runtime errors (scene_manager.gd) and 1 runtime error (main.gd) plus 4 corrupt resource references (default_bus_layout.tres) won't prevent startup but will crash the game on certain paths.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T6 | Rewrite animations to AnimationLibrary pattern in scene_manager.gd | `gdscripts/scene_manager.gd` | None | 20 min |
| T7 | Fix static type annotation in main.gd | `gdscripts/main.gd` | None | 1 min |
| T8 | Fix corrupt SubResource references in default_bus_layout.tres | `default_bus_layout.tres` | None | 2 min |

#### T6 Details — AnimationLibrary Rewrite

**File:** `gdscripts/scene_manager.gd`

**Change (lines 53-69):** Replace the two `anim.add_animation()` calls with the AnimationLibrary pattern.

**Before (lines 53-69):**
```gdscript
# Create fade_out animation
var anim_out := Animation.new()
anim_out.length = 0.5
var track_out := anim_out.add_track(Animation.TYPE_VALUE)
anim_out.track_set_path(track_out, "ColorRect:modulate")
anim_out.track_insert_key(track_out, 0.0, Color(0, 0, 0, 0))
anim_out.track_insert_key(track_out, 0.5, Color(0, 0, 0, 1))
anim.add_animation("fade_out", anim_out)

# Create fade_in animation (reverse of fade_out)
var anim_in := Animation.new()
anim_in.length = 0.5
var track_in := anim_in.add_track(Animation.TYPE_VALUE)
anim_in.track_set_path(track_in, "ColorRect:modulate")
anim_in.track_insert_key(track_in, 0.0, Color(0, 0, 0, 1))
anim_in.track_insert_key(track_in, 0.5, Color(0, 0, 0, 0))
anim.add_animation("fade_in", anim_in)
```

**After:**
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

**Test scenarios:**
1. **Animation creation:** Create a SceneManager instance in a test scene. Verify that `_setup_fade_curtain()` creates the AnimationPlayer with both animations accessible via `_fade_anim.get_animation_list()`.
2. **Fade-out playback:** Call `trigger_scene_change("res://scenes/office/office.tscn")`. Verify:
   - `transition_started` signal is emitted
   - `_fade_anim.play("fade_out")` starts and the ColorRect's modulate transitions to black over 0.5s
   - The scene change actually occurs
3. **Fade-in playback:** After scene change, the new scene's `SceneManager.fade_in()` should play "fade_in" and the ColorRect's modulate transitions from black to transparent.
4. **Rapid triggering:** Call `trigger_scene_change()` twice. The second call should be blocked by `transition_in_progress` check.

---

#### T7 Details — Fix Static Type Annotation

**File:** `gdscripts/main.gd`

**Change line 11:**
```gdscript
# Before:
@onready var dialogue_display_3d: Node3D = $Dialogue3D
# After:
@onready var dialogue_display_3d: DialogueDisplay3D = $Dialogue3D
```

**Test scenario:**
1. Verify that `dialogue_runner.node_changed.connect(dialogue_display_3d.on_node_changed)` (line 35) compiles without "Invalid access to property" errors.
2. Verify all 3 signal connection lines (35-37) work at runtime — call each method manually to confirm dispatch.

**Edge case:** If `$Dialogue3D` is not a `DialogueDisplay3D` in a particular scene, the `@onready` assignment will produce a type mismatch warning. This is acceptable since the scene SHOULD have a `DialogueDisplay3D` node.

---

#### T8 Details — Fix Corrupt SubResource References

**File:** `default_bus_layout.tres`

**Changes (4 corrections):**
```gdscript
# Line 9: BEFORE
bus/0/effect/0 = SubResource("distortion")
# Line 9: AFTER
bus/0/effect/0 = SubResource(1)

# Line 28: BEFORE
bus/3/effect/0 = SubResource("indoor_lpf")
# Line 28: AFTER
bus/3/effect/0 = SubResource(2)

# Line 35: BEFORE
bus/4/effect/0 = SubResource("underpass_reverb")
# Line 35: AFTER
bus/4/effect/0 = SubResource(3)

# Line 36: BEFORE
bus/4/effect/1 = SubResource("underpass_lpf")
# Line 36: AFTER
bus/4/effect/1 = SubResource(4)
```

**Verification:** Load the project and verify:
- No "Failed loading resource: res://default_bus_layout.tres" error at startup
- Audio buses exist with correct effects: Master→Distortion, IndoorBus→LowPassFilter, UnderpassBus→Reverb+LowPassFilter
- All effect parameters match the sub_resource definitions (lines 38-57)

**Test scenario:** Run `godot --headless --quit` — the audio bus layout loads silently. Alternatively, open the project in the Godot editor and check Audio → Audio Bus Layout.

---

## 3. Verification Protocol

### Primary Verification

After all 8 fixes are applied:

```bash
cd /Users/devvi/workspace/agent-game-test
godot --headless --quit
```

**Expected result:**
- Exit code: 0
- Stderr: zero parse errors, zero resource load errors
- Stdout: clean startup log (no error/warning prefixes)

**Failure indicators:**
- `SCRIPT ERROR:` prefix in output → specific file/line still broken
- `ERROR: Failed loading resource:` → resource file still corrupt
- Non-zero exit code → GDScript parser still rejecting something

### Secondary Verification (Runtime Smoke Test)

```bash
godot --headless scenes/main.tscn
```

**Expected result:**
- Loads entry scene without errors
- Audio bus layout loads successfully
- SceneManager fades can be exercised programmatically

**Failure indicators:**
- Runtime errors during scene loading
- Signal connection failures for dialogue wiring
- Audio bus load errors

### Runtime Integration Scenario (Manual)

1. Create a test GDScript that simulates a full dialogue flow:
   - Start dialogue → `DialogueRunner.dialogue_started` fires
   - Node change → `DialogueRunner.node_changed` fires → `DialogueDisplay3D.on_node_changed` receives it
   - Choices available → `DialogueRunner.choices_available` fires → `DialogueDisplay3D.on_choices_available` receives it
   - Navigate up/down → focus changes correctly
   - Dialogue ended → `DialogueRunner.dialogue_ended` fires → all elements fade
2. Trigger a scene transition via a choice with "scene" metadata:
   - Fade-out plays → ColorRect goes opaque
   - Scene changes to target scene
   - Fade-in plays on the new scene

---

## 4. Edge Cases to Verify After Fixes

### Fix-Level Edge Cases

| Fix | Edge Case | Expected Behavior |
|:---:|-----------|------------------|
| T1 | Another file also references `LoFiText3D` | Should resolve correctly — class_name is global |
| T2 | `UIConfig` node has property but of wrong type | `has()` returns true → `get()` returns the property (type mismatch up to caller) |
| T2 | `UIConfig` node doesn't exist | `get_node_or_null` returns null → skip block entirely |
| T4 | `create_tween()` called before `_ready()` completes | Safe — `create_tween()` is available once the node is in the tree |
| T4 | `_tween.kill()` called on a finished tween | `Tween.kill()` is idempotent on finished tweens |
| T4 | Rapid state changes while tween is running | `_tween.kill()` + new `create_tween()` — old tween is properly freed |
| T6 | `anim.add_animation_library("", library)` called twice | AnimationPlayer replaces or errors — should only be called in `_setup_fade_curtain()` |
| T6 | `play("fade_out")` on non-existent animation | Error logged by AnimationPlayer — verify animation names match |
| T7 | `$Dialogue3D` node is missing in scene | `@onready` produces null — signal `.connect()` call guarded by `!= null` check (lines 34-37) |
| T8 | SubResource numeric ID doesn't match definition | Resource load fails — verify ID mapping is correct |

### Cross-File Edge Cases

| Scenario | Files Involved | Expected Behavior |
|----------|---------------|-------------------|
| UIConfig present but with no properties set | dialogue_display_3d, status_bar | Both fall through to defaults (1.0 scale) |
| Scene has no FadeCurtain | scene_manager | `_setup_fade_curtain()` creates one dynamically |
| Dialogue3D node not a DialogueDisplay3D | main | `@onready` type mismatch at parse time → fix scene |
| Audio bus effects parameters changed | default_bus_layout.tres | SubResource data is separate from reference — no issue |
| Very rapid dialogue node changes (>10/sec) | dialogue_display_3d, status_bar | Tweens kill properly, no orphaned Tween references |

---

## 5. Rollback Strategy

Each fix is a small, targeted change in its own file. If any fix causes a regression:

1. **Revert individual file change** with `git checkout main -- <file>` and re-verify
2. **File-level isolation:** No fix depends on another fix's changed code path (except T1→T2 compilation dependency)
3. **Test granularity:** `godot --headless --quit` catches 7 of 8 fix categories immediately; only T6 and T7 need runtime testing

---

## 6. Test Descriptions (Non-Runnable)

*Note: This project has no runnable test framework. The following are verbal test scenarios for manual or scripted verification.*

### Test 1: Parse Error Clearance
```
Goal:      Confirm zero GDScript parse errors
Setup:     Any Godot 4.7 project with all fixed files
Action:    Run `godot --headless --quit`
Assert:    Exit code 0, no SCRIPT ERROR lines in output
```

### Test 2: Audio Bus Layout Integrity
```
Goal:      Confirm default_bus_layout.tres loads correctly
Setup:     Project using the fixed tres file
Action:    Run `godot --headless --quit`
Assert:    No "Failed loading resource" errors; 5 buses loaded with correct effects
```

### Test 3: DialogueDisplay3D Signal Wiring
```
Goal:      Confirm main.gd can connect to DialogueDisplay3D methods
Setup:     Main scene with $Dialogue3D as DialogueDisplay3D
Action:    Load scene and trigger dialogue (F9 key)
Assert:    Dialogue display appears; choices render with prefix letters; navigation works
```

### Test 4: StatusBar Tween Responsiveness
```
Goal:      Confirm status bar animates without Tween lifecycle errors
Setup:     Main scene with StatusBar visible
Action:    Trigger state changes (up/down arrow keys)
Assert:    Bar fill animates smoothly; rapid keypresses don't cause orphaned Tween warnings
```

### Test 5: Scene Transition Fade
```
Goal:      Confirm scene_manager.gd fades work correctly
Setup:     Scene with SceneManager and a choice that triggers scene change
Action:    Make a scene-transition choice
Assert:    Fade-out plays → scene changes → fade-in plays → no animation errors
```

### Test 6: LoFiText3D Dynamic Creation
```
Goal:      Confirm LoFiText3D.new() works as a registered class
Setup:     Any script that calls LoFiText3D.new()
Action:    Run `godot --headless --quit`
Assert:    No "Identifier 'LoFiText3D' not declared" error
```
