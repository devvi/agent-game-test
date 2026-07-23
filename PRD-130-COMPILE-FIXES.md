# PRD #130 — Game Won't Compile: Root Cause Analysis, Fix Plan & Test Strategy

**Status:** Draft  
**Priority:** P0/Critical  
**Author:** Hermes Agent Research Phase  
**Date:** 2026-07-23  

---

## 1. Executive Summary

The project (`agent-game-test`) on `main` branch fails to compile under Godot 4.7.1 with **7 unique parse errors** across 3 files, plus **2 runtime errors** and **6 missing audio assets**. All 18 implement PRs bypassed the review agent due to gateway rate limiting, allowing unchecked code quality issues to merge. This PRD documents every error found, root cause, prioritized fix plan, and test recommendations.

---

## 2. Verified Errors (from `godot --headless --quit`)

### 2.1 Blocking Parse Errors (must fix to compile)

| # | File | Line | Error | Severity |
|---|------|------|-------|----------|
| 1 | `default_bus_layout.tres` | 9 | SubResource `"distortion"` text-ID doesn't match actual sub_resource id=1 | **BLOCKING** |
| 2 | `gdscripts/dialogue_display_3d.gd` | 47 | `LoFiText3D` class not declared — `lo_fi_text_3d.gd` lacks `class_name LoFiText3D` | **BLOCKING** |
| 3 | `gdscripts/dialogue_display_3d.gd` | 47 | Type inference fails for `label` variable (cascading from #2) | CASCADING |
| 4 | `gdscripts/dialogue_display_3d.gd` | 97 | `Object.get()` with 2 args: `ui_config.get("auto_font_scale", 1.0)` | **BLOCKING** |
| 5 | `gdscripts/dialogue_display_3d.gd` | 142 | Same `Object.get()` 2-arg issue: `ui_config.get("choice_spacing", choice_spacing)` | **BLOCKING** |
| 6 | `gdscripts/dialogue_display_3d.gd` | 237 | `chr(65 + index)` — `chr()` removed in Godot 4; use `String.chr()` | **BLOCKING** |
| 7 | `gdscripts/status_bar.gd` | 37 | `add_child(_tween)` — `Tween` is `RefCounted`, not `Node`; use `create_tween()` | **BLOCKING** |
| 8 | `gdscripts/status_bar.gd` | 99 | `Object.get()` with 2 args: `ui_config.get("auto_font_scale", 1.0)` | **BLOCKING** |

**Total blocking parse errors: 7 unique** (8 lines across 3 files — #3 is cascading from #2)

### 2.2 Runtime Errors (non-compilation-blocking but crash on execution)

| # | File | Line | Error | Notes |
|---|------|------|-------|-------|
| 9 | `gdscripts/scene_manager.gd` | 60 | `AnimationPlayer` has no `add_animation()` in Godot 4 — uses AnimationLibrary system instead | Crashes on scene transition |
| 10 | `gdscripts/main.gd` | 35 | `dialogue_display_3d` is null (cascading from failed script load) | Prevents dialogue integration |

### 2.3 Missing Assets (warnings, non-blocking)

| # | File | Type |
|---|------|------|
| 11-16 | `res://assets/audio/rain_loop.wav`, `rain_heavy.wav`, `city_hum.wav` | Ambient audio |
| 17-19 | `res://assets/audio/footstep_office.wav`, `footstep_street.wav`, `footstep_underpass.wav` | SFX audio |

---

## 3. Root Cause Analysis

### 3.1 Primary Root Cause: Review Bypass

All implement PRs (18 total) merged without automated code review because the review agent was rate-limited by the gateway provider. This allowed code with:
- Godot 3→4 API incompatibilities (`chr()`, `Object.get()`, `Tween.new()`)
- Missing `class_name` declarations
- Merge-corrupted resource files

...to pass through unchecked.

### 3.2 Per-File Root Causes

#### `gdscripts/dialogue_display_3d.gd` (5 errors)
- **File created by implement agent** without checking that `lo_fi_text_3d.gd` has `class_name LoFiText3D`
- Used Godot 3 idioms: `chr()`, `Object.get(prop, default)`
- Reviewer would have caught all 5 issues

#### `gdscripts/status_bar.gd` (2 errors)
- **File created by implement agent** using `Tween.new() + add_child()` pattern that worked in Godot 3 but not Godot 4
- Same `Object.get()` Godot 3 idiom
- Reviewer would have caught both

#### `default_bus_layout.tres` (1 error)
- **Merge corruption** — the SubResource references on bus lines use text IDs (`"distortion"`) while the actual sub_resource declarations at the bottom use numeric IDs (`id=1`). This happens when a merge conflict in the `.tres` file was resolved incorrectly.

#### `gdscripts/scene_manager.gd` (1 runtime error)
- **Used Godot 3 API** (`AnimationPlayer.add_animation()`) — in Godot 4, animations must be added via `AnimationLibrary` objects
- This is a runtime error (would crash on scene transition), so it only shows up at runtime, not compile time

### 3.3 Systemic Issues

1. **No PR review gate** — The gateway rate limiting disabled the review agent entirely
2. **No CI compiler check** — No automated `godot --headless --quit` verification in CI pipeline
3. **No GDScript linting** — No static analysis for Godot 4 API compatibility
4. **Godot 3 idioms in Godot 4 project** — Multiple files use removed/renamed APIs

---

## 4. Fix Plan (Prioritized)

### Priority P0: Compilation Blockers

#### Fix 1: `default_bus_layout.tres` — Fix SubResource references
- **Root cause:** Merge corruption. Text IDs (`"distortion"`) on bus lines don't match numeric IDs (`id=1`) in sub_resource declarations.
- **Fix:** Regenerate the file from scratch. All buses are standard (Master with distortion effect, AmbientBus, SFXBus, IndoorBus with LPF, UnderpassBus with reverb+LPF).
- **Effort:** Low (57 lines to regenerate)
- **File:** `default_bus_layout.tres`

#### Fix 2: `gdscripts/lo_fi_text_3d.gd` — Add `class_name LoFiText3D`
- **Root cause:** Missing class_name declaration.
- **Fix:** Add `class_name LoFiText3D` on line 2.
- **Effort:** Trivial (1 line)
- **File:** `gdscripts/lo_fi_text_3d.gd`

#### Fix 3: `gdscripts/dialogue_display_3d.gd` — Fix `Object.get()` calls (×2)
- **Root cause:** Godot 3 idiom. `Object.get()` only accepts 1 arg.
- **Fix:** Replace `ui_config.get("auto_font_scale", 1.0)` with `ui_config.auto_font_scale` (direct property access, since UIConfig exports these as member variables).
- **Effort:** Trivial (2 lines)
- **File:** `gdscripts/dialogue_display_3d.gd` (lines 97, 142)

#### Fix 4: `gdscripts/dialogue_display_3d.gd` — Fix `chr()` call
- **Root cause:** `chr()` removed in Godot 4.
- **Fix:** Replace `chr(65 + index)` with `String.chr(65 + index)`.
- **Effort:** Trivial (1 line)
- **File:** `gdscripts/dialogue_display_3d.gd` (line 237)

#### Fix 5: `gdscripts/status_bar.gd` — Fix Tween lifecycle
- **Root cause:** Godot 3 idiom. `Tween.new()` + `add_child()` — Tween is RefCounted.
- **Fix:** Remove manual Tween creation. Use `@onready var _tween: Tween` without initialization and create with `_tween = create_tween()` on first use — OR remove the `@onready` and lazily create. Since this file already calls create_tween in some paths, the cleanest fix is to use `create_tween()` directly everywhere.
- **Effort:** Low (restructure `_ready()` to use `create_tween()`)
- **File:** `gdscripts/status_bar.gd` (lines 27, 36-37)

#### Fix 6: `gdscripts/status_bar.gd` — Fix `Object.get()` call
- **Root cause:** Same as Fix 3.
- **Fix:** Replace `ui_config.get("auto_font_scale", 1.0)` with `ui_config.auto_font_scale`.
- **Effort:** Trivial (1 line)
- **File:** `gdscripts/status_bar.gd` (line 99)

### Priority P1: Runtime Crashes

#### Fix 7: `gdscripts/scene_manager.gd` — Fix animation creation for Godot 4
- **Root cause:** Godot 4 removed `AnimationPlayer.add_animation()`. Animations must be added via `AnimationLibrary`.
- **Fix:** Create `AnimationLibrary` objects and add animations to them, then add the library to the `AnimationPlayer` with `add_animation_library()`.
- **Effort:** Low (restructure `_create_fade_curtain()`, ~10 lines changed)
- **File:** `gdscripts/scene_manager.gd` (lines 53-69)

### Priority P2: Missing Assets

#### Fix 8: Create placeholder audio assets
- **Root cause:** 6 `.wav` files referenced by `audio_manager.gd` don't exist.
- **Fix:** Generate placeholder silent audio files at the expected paths using `ffmpeg` or a simple GDScript utility. Alternatively, update `_try_load()` to handle null gracefully and add `@export` overrides for paths.
- **Effort:** Medium (6 files to generate)
- **Files:** `res://assets/audio/rain_loop.wav`, `rain_heavy.wav`, `city_hum.wav`, `footstep_office.wav`, `footstep_street.wav`, `footstep_underpass.wav`

---

## 5. Verification

### Post-Fix Compilation Check
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --quit
```
Expected: Exit code 0, no ERROR lines, no SCRIPT ERROR lines.

### Test Run
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/run_tests.gd
```
Expected: All tests pass (exit 0).

---

## 6. Test Strategy

### 6.1 Tests to Add

#### Unit Tests for Fixed Files

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `tests/unit/test_lo_fi_text_3d_fixed.gd` | Verify `LoFiText3D` has `class_name`, instantiates correctly | Regression |
| `tests/unit/test_status_bar_tween.gd` | Verify `StatusBar` creates Tween via `create_tween()`, not `Tween.new() + add_child()` | Regression |
| `tests/unit/test_dialogue_display_3d_fixed.gd` | Verify `_prefix_letter()` works, verify `ui_config` property access works | Regression |
| `tests/unit/test_scene_manager_animation.gd` | Verify fade curtain creates animations correctly (Godot 4 API) | Regression |

#### Integration Test
| Test File | Tests | Coverage |
|-----------|-------|----------|
| `tests/integration/test_compile_full.gd` | Run as `--script`, instantiate every gdscript, verify no parse errors at runtime | Compilation integrity |

#### Unit Test: Verify all autoloads can be instantiated

```
func test_all_autoloads_instantiate() -> void:
    for script_path in ["res://gdscripts/state_system.gd", "res://gdscripts/game_manager.gd", ...]:
        var instance = load(script_path).new()
        assert(instance != null)
```

### 6.2 CI Recommendations

1. **Pre-merge compiler gate:** Add a GitHub Action that runs `godot --headless --quit` before allowing merge
2. **GDScript lint:** Introduce a GDScript linter that catches Godot 3→4 incompatibilities:
   - `chr()` → `String.chr()`
   - `Object.get(prop, default)` → direct property access
   - `Tween.new()` → `create_tween()`
   - `AnimationPlayer.add_animation()` → `AnimationLibrary` pattern
3. **Review agent reliability:** Fix the gateway rate limiting that caused the review bypass — or add a fallback that skips merge-on-green if review can't run

### 6.3 Test Infrastructure Assessment

Current test infrastructure (`tests/run_tests.gd`) is robust — it uses `SceneTree._init()` for headless test running and already covers:
- GameState (legacy + new)
- Dialogue engine (v1 + v2)
- Narrative architecture
- State system sliders
- Audio system
- Hemingway enforcer
- NPC framework
- UI config
- Status bar

**Gap:** No test validates that ALL gdscript files can be parsed/instantiated without errors. A `--script` test that loads every `.gd` file and calls `.new()` would catch future compilation issues immediately.

---

## 7. Effort Summary

| Priority | Items | Lines Changed | Effort |
|----------|-------|---------------|--------|
| P0 | 6 fixes across 4 files | ~15 lines | ~30 min |
| P1 | 1 fix in scene_manager.gd | ~10 lines | ~20 min |
| P2 | 6 placeholder audio files | N/A | ~15 min |
| Tests | 4 new test files + 1 integration | ~200 lines | ~45 min |

**Total estimated effort:** ~2 hours for full fix + test suite additions.

---

## 8. Appendix: Compiler Output Reference

### Full error output from `godot --headless --quit`:

```
ERROR: res://default_bus_layout.tres:9 - Parse Error: .
SCRIPT ERROR: Parse Error: Identifier "LoFiText3D" not declared. (dialogue_display_3d.gd:47)
SCRIPT ERROR: Parse Error: Cannot infer type of "label" variable. (dialogue_display_3d.gd:47)
SCRIPT ERROR: Parse Error: Too many arguments for "get()" call. (dialogue_display_3d.gd:97)
SCRIPT ERROR: Parse Error: Too many arguments for "get()" call. (dialogue_display_3d.gd:142)
SCRIPT ERROR: Parse Error: Function "chr()" not found in base self. (dialogue_display_3d.gd:237)
SCRIPT ERROR: Parse Error: Invalid argument for "add_child()": arg 1 should be "Node" but is "Tween". (status_bar.gd:37)
SCRIPT ERROR: Parse Error: Too many arguments for "get()" call. (status_bar.gd:99)
SCRIPT ERROR: Nonexistent function 'add_animation' in base 'AnimationPlayer'. (scene_manager.gd:60)
SCRIPT ERROR: Invalid access to property 'on_node_changed' on base of type 'Node3D'. (main.gd:35)
```

### 6 audio files not found:
- `rain_loop.wav`, `rain_heavy.wav`, `city_hum.wav`
- `footstep_office.wav`, `footstep_street.wav`, `footstep_underpass.wav`
