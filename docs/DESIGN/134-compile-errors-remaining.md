# Design: #134 — Remaining Compile Errors (Post-#130)

> Parent Issue: #134
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Design Overview

### Core Idea

Fix 5 compile/runtime errors across 3 GDScript files and 1 scene file that prevent Godot 4.7.1 from loading the game. All fixes are in-place minimal changes — no new files, no architecture refactors. The approach mirrors Approach A from the research PRD: remove the `scene_id` redeclaration, replace invalid 2-arg `get()` calls with property access, add a null guard for `choice_container`, and clear the Godot import cache for the scene file and audio asset.

### Data Flow

```
godot --headless --quit
    │
    ├──► Compile office.gd
    │       ├── Bug #1: scene_id redeclaration ──► Remove var, set in _ready()
    │       ├── Bug #2: ss.get("hope", 5.0)    ──► ss.hope
    │       └── Bug #3: ss.get("day", 0)       ──► ss.get("day") + has("day") guard
    │
    ├──► Compile dialogue_display_3d.gd
    │       └── Bug #4: choice_container.get_children() on null ──► null guard
    │
    ├──► Parse office.tscn
    │       └── Bug #5: line 46 parse error    ──► Clear .godot/imports/ cache
    │
    └──► Load footstep_office.wav
            └── Import cache stale             ──► Clear .godot/imports/ cache
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Fix scope | In-place edits to existing files only | All 5 bugs have isolated root causes; minimal diff reduces review burden and merge conflict risk |
| `scene_id` fix strategy | Remove `var` declaration, set in `_ready()` before `super._ready()` | Parent `SceneBase` already declares `scene_id`; GDScript 2.0 forbids redeclaration of inherited members |
| `get("hope", 5.0)` fix | Replace with `ss.hope` (property access) | `StateSystem` has `hope` as a custom property with getter; `Node.get()` in Godot 4 only accepts 1 arg |
| `get("day", 0)` fix | Replace with 1-arg `ss.get("day")` | Already guarded by `ss.has("day")` — the 2nd argument (default) is unnecessary |
| `choice_container` null guard | Early return in `_setup_choice_pool()` | If the node isn't found (`$ChoiceContainer` returns null), skip choice pool setup gracefully |
| office.tscn parse error | Clear `.godot/imports/` cache | The file's syntax is valid per hexdump; error is likely from stale import cache |
| footstep_office.wav | Clear `.godot/imports/` cache; fallback to downsample to 22050Hz | The WAV at 44100Hz may trigger a different Godot import path; other WAVs at 22050Hz load fine |

---

## 2. Per-Component Changes

### 2.1 `gdscripts/office.gd` — Office scene script

**Bug #1 — `scene_id` member redeclaration (line 12)**

Current code:
```gdscript
var scene_id: String = "office"
```

Fix: Remove the `var scene_id` line entirely. Set `scene_id = "office"` at the top of `_ready()`, before `super._ready()`:

```gdscript
func _ready() -> void:
    scene_id = "office"
    super._ready()
    door_trigger.input_event.connect(_on_door_trigger_input)
```

**Bug #2 — `ss.get("hope", 5.0)` with 2 args (line 32)**

Current code:
```gdscript
var hope_val: float = ss.get("hope", 5.0) if ss else (gm.get_slider("hope") if gm else 5.0)
```

Fix: Replace `ss.get("hope", 5.0)` with `ss.hope` (the `hope` property on `StateSystem` has a custom getter):

```gdscript
var hope_val: float = ss.hope if ss else (gm.get_slider("hope") if gm else 5.0)
```

**Bug #3 — `ss.get("day", 0)` with 2 args (line 53)**

Current code:
```gdscript
day = int(ss.get("day", 0)) if ss.has("day") else 0
```

Fix: Remove the default value argument — `get("day")` with 1 arg is the valid GDScript form. The `ss.has("day")` guard already ensures the key exists:

```gdscript
day = int(ss.get("day")) if ss.has("day") else 0
```

### 2.2 `gdscripts/dialogue_display_3d.gd` — 3D dialogue display

**Bug #4 — `choice_container.get_children()` on null (line 44)**

Current code:
```gdscript
func _setup_choice_pool() -> void:
    _choice_labels.clear()
    for child in choice_container.get_children():
```

Fix: Add a null guard before the loop. If `choice_container` is null (e.g., loaded in headless context or scene variant without the node), return early:

```gdscript
func _setup_choice_pool() -> void:
    _choice_labels.clear()
    if choice_container == null:
        return
    for child in choice_container.get_children():
```

### 2.3 `scenes/office/office.tscn` — Office scene file

**Bug #5 — Parse error at line 46**

The line `light_color = Color(0.9, 0.7, 0.4)` is valid TSCN syntax per hexdump inspection. No file content change is needed.

Fix: Clear the stale import cache for office.tscn:
```
rm -f .godot/imports/office.tscn-*
```
Then run `godot --headless --quit` to trigger re-import.

### 2.4 `assets/audio/footstep_office.wav` — Footstep audio (secondary)

The file exists on disk (44KB, PCM 16-bit mono 44100Hz) but `audio_manager.gd:76` reports it missing. This is likely a stale import cache issue.

Fix: Clear the stale import cache:
```
rm -f .godot/imports/footstep_office.wav-*
```
Then run `godot --headless --quit` to trigger re-import.

If the error persists: convert the WAV to 22050Hz to match the sample rate of other working WAV files:
```
ffmpeg -i assets/audio/footstep_office.wav -ar 22050 assets/audio/footstep_office.wav
```

---

## 3. Test Cases

All test cases are **descriptions** only — no runnable test files. The primary verification is `godot --headless --quit` returning exit code 0 with no error output. Secondary verifications use manual inspection (print/log output or Godot editor).

### TC1: Headless load — full suite (Primary)
- **What:** Run `godot --headless --quit` and check exit code and stderr
- **How:** `cd project && godot --headless --quit 2>&1; echo "Exit: $?"`
- **Expected:** Exit code 0. No output containing "SCRIPT ERROR", "Parse Error", or "Cannot call method"
- **Normal path:** Game loads and exits cleanly
- **Edge cases:** Fresh checkout with empty `.godot/` directory
- **Failure path:** If errors remain, the exit code will be non-zero and error messages will appear on stderr

### TC2: scene_id initialization
- **What:** Verify `scene_id` is set to `"office"` when `OfficeScene._ready()` runs
- **How:** Add a temporary `print("scene_id = ", scene_id)` at the start of `_ready()` in office.gd; run `godot --headless --quit`
- **Expected:** Output contains `scene_id = office`
- **Edge cases:** Verify `super._ready()` in `SceneBase` reads the correct value (not empty string)

### TC3: hope_val fallback chain
- **What:** Verify `hope_val` is computed correctly when `ss` is null
- **How:** Inspect the ternary chain: `ss.hope if ss else (gm.get_slider("hope") if gm else 5.0)`. With autoloads, `ss` should be non-null; the function should not crash
- **Expected:** No "Too many arguments" error. `hope_val` is a float in range [0, 10]
- **Edge cases:** Both `ss` and `gm` null → fallback to 5.0. `ss` exists but `hope` property returns null → GDScript type conversion may produce 0.0

### TC4: day value from state
- **What:** Verify `day` is parsed correctly from `ss.get("day")`
- **How:** Inspect line 53 change: `day = int(ss.get("day")) if ss.has("day") else 0`
- **Expected:** No "Too many arguments" error. `day` is an integer between 0 and 90
- **Edge cases:** `ss.has("day")` returns false → day = 0. `ss.get("day")` returns a non-integer → `int()` conversion produces 0

### TC5: choice_container null guard
- **What:** Verify `_setup_choice_pool()` doesn't crash when `choice_container` is null
- **How:** If `choice_container` is null, the function should return early without calling `get_children()`
- **Expected:** No "Cannot call method 'get_children' on a null value" error
- **Edge cases:** `Dialogue3D` scene variant without `ChoiceContainer` node → graceful early return. All `_choice_labels`-using methods (`show_choices_immediate`, `highlight_choice`) check array size before iteration

### TC6: office.tscn parse
- **What:** Verify `office.tscn` parses without errors after cache clear
- **How:** Delete `.godot/imports/office.tscn-*` cache, run `godot --headless --quit`, check stderr
- **Expected:** No "Parse Error" for `office.tscn:46` or any other line
- **Failure path:** If error persists, inspect the file for UTF-8 BOM or hidden control characters using `hexdump -C` on line 46

### TC7: footstep_office.wav import
- **What:** Verify footstep audio loads without "No loader found" warning
- **How:** Delete `.godot/imports/footstep_office.wav-*` cache, run `godot --headless --quit`, check stderr for audio warnings
- **Expected:** No "No loader found" warning for `footstep_office.wav`
- **Failure path:** If error persists, downsample to 22050Hz with ffmpeg and re-test

---

## 4. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|:----------:|:------:|------------|
| `.godot/imports/` cache stale beyond cache clear | Low | Medium | Delete entire `.godot/imports/` directory and let Godot regenerate all imports |
| `ss.hope` returns unexpected type (not float) | Low | Medium | GDScript's typed variable `hope_val: float` will raise a runtime type error; verify with print before closing the fix |
| `$ChoiceContainer` returns null in normal gameplay (not just headless) | Low | High | The null guard handles this gracefully — choice pool remains empty but node-based UI still works via the programmatic fallback in the while loop |
| Other scene scripts also declare `var scene_id: String` | Medium | Medium | If `CityScene.gd`, `StoreScene.gd`, etc. have the same pattern, they will hit the same error. Check each subclass of `SceneBase` during the implement phase |
| `office.tscn` parse error is a Godot bug, not cache | Low | High | If cache clear doesn't fix it, rewrite the scene file via Godot editor (re-export as TSCN) or recreate the DirectionalLight3D node |
| footstep WAV at 44100Hz is fundamentally incompatible with Godot's WAV import on this platform | Low | Low | Downsample to 22050Hz with ffmpeg as documented fallback |

---

## 5. Files Changed

| File | Change | Est. Lines Changed |
|------|--------|:------------------:|
| `gdscripts/office.gd` | Remove `var scene_id` declaration, set in `_ready()`; replace `ss.get("hope", 5.0)` with `ss.hope`; replace `ss.get("day", 0)` with `ss.get("day")` | -1 line, +2 lines, ±2 edits |
| `gdscripts/dialogue_display_3d.gd` | Add null guard before `choice_container.get_children()` | +3 lines |
| `.godot/imports/` (cache) | Delete stale cache entries for `office.tscn` and `footstep_office.wav` | 0 (cache rebuilds) |
| `assets/audio/footstep_office.wav` | Possibly downsample from 44100Hz to 22050Hz | 0 (binary file) |

No new files are created. No base classes are modified.

---

## 6. Verification Checklist

- [ ] **TC1:** `godot --headless --quit` exits with code 0, no script errors on stderr
- [ ] **TC2:** `scene_id` is `"office"` when `OfficeScene._ready()` runs
- [ ] **TC3:** `hope_val` computed without "Too many arguments" error
- [ ] **TC4:** `day` value parsed from `ss.get("day")` without "Too many arguments" error
- [ ] **TC5:** `_setup_choice_pool()` does not crash on null `choice_container`
- [ ] **TC6:** `office.tscn` parses without "Parse Error"
- [ ] **TC7:** `footstep_office.wav` loads without "No loader found" warning
- [ ] No regression on existing features — all prior test files still pass via `godot --headless --quit`
