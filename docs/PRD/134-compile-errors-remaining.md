# Research: Remaining Compile Errors — office.gd, office.tscn, dialogue_display_3d (Post-#130)

> Parent Issue: #134
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

Running `godot --headless --quit` on the current `main` branch produces 5 distinct compile/runtime errors that prevent the game from loading:

| # | File | Line | Error | Severity |
|---|------|------|-------|:--------:|
| 1 | `gdscripts/office.gd` | 12 | `SCRIPT ERROR: The member "scene_id" already exists in parent class SceneBase` | ❌ Cannot load script |
| 2 | `gdscripts/office.gd` | 32 | `SCRIPT ERROR: Too many arguments for "get()" call. Expected at most 1 but received 2.` | ❌ Cannot load script |
| 3 | `gdscripts/office.gd` | 53 | Same as #2 — `ss.get("day", 0)` with 2 args | ❌ Cannot load script |
| 4 | `gdscripts/dialogue_display_3d.gd` | 44 | `SCRIPT ERROR: Cannot call method 'get_children' on a null value.` | ⚠️ Runtime crash |
| 5 | `scenes/office/office.tscn` | 46 | `Parse Error. [Resource file res://scenes/office/office.tscn:46]` | ❌ Cannot load scene |

Additionally, `assets/audio/footstep_office.wav` is reported as a missing resource by `audio_manager.gd:76`, though investigation shows the file exists on disk (44KB, valid WAV PCM 16-bit mono 44100Hz). This is treated as a secondary concern.

### Expected Behavior

1. **`office.gd` loads without parse errors** — no member redeclaration, no invalid `get()` calls.
2. **`dialogue_display_3d.gd` handles null `choice_container` gracefully** — no crash during `_ready()`.
3. **`office.tscn` parses without format errors** — no invisible characters or merge conflict residue.
4. **`footstep_office.wav` loads successfully** — audio plays when player is in the office scene.
5. **Game starts to title/main menu with `godot --headless --quit` returning exit code 0.**

### User Scenarios

- **Scenario A (Player):** Launches the game. Game must compile and render the office scene without crashing. The office is the starting environment.
- **Scenario B (Developer):** Runs `godot --headless --quit` after every implement PR to verify no regressions. Currently blocked by these 5 errors.
- **Scenario C (CI/CD Pipeline):** The `build` step in `manifest.yaml` runs `godot --headless --export-debug Linux/X11`. These errors block export.
- **Frequency:** 100% — every launch, every build attempt. These are hard errors, not intermittent.

---

## 2. Root Cause Analysis

### Why Does Current Behavior Exist?

| Bug | Root Cause | Introduced By |
|-----|-----------|---------------|
| #1: scene_id redeclaration | `office.gd:12` declares `var scene_id: String = "office"`. Parent `scene_base.gd:10` already declares `var scene_id: String = ""`. GDScript 2.0 does not allow subclasses to redeclare inherited members. | Implement PR for scene sequence (#55 area) |
| #2, #3: `get()` with 2 args | `StateSystem` (state_system.gd) has `hope` as a property with custom getter (`get:` block), not a custom `get(key, default)` method. `Node.get()` in Godot 4 only accepts 1 argument (StringName key). No 2-arg form exists on Node. | Implement PR for scene sequence (#55 area) |
| #4: choice_container null | `$ChoiceContainer` resolves from `Dialogue3D.tscn`. The ChoiceContainer node (line 40) and its children Choice0–Choice3 (lines 43–93) **do exist** in the scene file. The null reference could occur if: (a) the scene is loaded in a headless context without the full scene tree; (b) the script is attached to a different scene variant that lacks the container; (c) a race condition during `_ready()`. Null guard is the safest fix. | Implement PR for dialogue engine (#46 / #52 area) |
| #5: office.tscn parse error | Line 46 `light_color = Color(0.9, 0.7, 0.4)` is **valid tscn syntax** with no invisible/control characters per hexdump inspection. The error could be caused by: (a) a stale import cache in `.godot/imports/`; (b) merge conflict residue that was since cleaned up; (c) a different file version at the time the issue was filed. | Merge artifacts from scene sequence PRs |
| footstep_office.wav | File exists (44KB, PCM 16-bit mono 44100Hz). Similar WAV files (`city_hum.wav` at 22050Hz, `rain_loop.wav` at 22050Hz) load fine via `_try_load()`. The 44100Hz sample rate may trigger a different Godot import path, or the `.godot/imports/` cache is stale. | Implement PR for audio system (#48 area) |

### Why Change Now?

- These are **blocking errors** — the game cannot launch, build, or export.
- Issue #130 fixed the original 13 errors from the first implement wave, but these 5 are new regressions from later PRs that were auto-merged without review agent validation.
- The pipeline's feedback loop requires `godot --headless --quit` to pass before any further development.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| Script format | GDScript 2.0 with `extends`, `class_name`, typed variables |
| Scene format | TSCN (Godot text scene format) |
| Error tolerance | **Zero** — compile errors prevent game from loading |
| Fix scope | In-place fixes to existing files only; no architecture changes |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/office.gd` | Office scene script | Fix member redeclaration (1 line), fix two `get()` calls (3 lines) |
| `gdscripts/dialogue_display_3d.gd` | 3D dialogue display | Add null guard before `get_children()` (1 line) |
| `scenes/office/office.tscn` | Office scene file | Validate/rewrite line 46 if truly malformed; re-import otherwise |
| `gdscripts/audio_manager.gd` | Audio asset loading | Add defensive logging for 44100Hz WAV loading; no code change needed if file is valid |
| `assets/audio/footstep_office.wav` | Footstep audio asset | Delete Godot import cache and re-import; ensure .gitattributes preserves binary |

### New Files Needed

None. All fixes are in-place edits to existing files.

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/scene_base.gd` | Scene base class | If approach changes `scene_id` from variable to getter, base class needs modification |
| `.godot/imports/` | Godot import cache | May need to be cleared for footstep_office.wav and office.tscn re-imports |

### Data Flow Impact

```
office.gd _ready() calls super._ready()
    │
    ├──► scene_base.gd _ready()
    │       ├──► scene_manager.fade_in()          — No change
    │       ├──► _configure_environmental_text()  — office.gd override
    │       │       ├──► ss.get("hope", 5.0)      ──► FIX: use ss.hope directly
    │       │       └──► ss.get("day", 0)          ──► FIX: use ss.get("day") + has("day") check
    │       ├──► _configure_ambient_audio()        — No change
    │       └──► _restore_dialogue_state()          — No change
    │
    └──► door_trigger.input_event.connect(...)     — No change

dialogue_display_3d.gd _ready()
    └──► _setup_choice_pool()
            └──► choice_container.get_children()   ──► FIX: null guard before iteration

audio_manager.gd _load_audio_streams()
    └──► _try_load("footstep_office.wav")          ──► May need import cache cleared
```

### Documents to Update

- [x] `docs/PRD/134-compile-errors-remaining.md` — this document
- [ ] `docs/DESIGN/` — no design doc changes needed (fixes are bug patches, not architecture changes)

---

## 4. Solution Comparison

### Approach A: In-Place Minimal Fixes (Recommended)

- **Description:** Fix each error at its source with minimal changes. No restructuring of base classes or subsystems.
- **Specific Code Changes:**
  - **Bug #1 — scene_id redeclaration:** Remove `var` from `office.gd:12`. Set `scene_id = "office"` inside `_ready()` before `super._ready()` is called (so the parent class sees the correct value). The parent `scene_base.gd:_ready()` reads `scene_id` after `super._ready()` completes, so setting before or after `super._ready()` doesn't matter functionally.
    ```gdscript
    # office.gd — line 12 change: remove 'var'
    # OLD: var scene_id: String = "office"
    # NEW: (delete line 12 entirely)
    
    # office.gd _ready() — set scene_id before super._ready()
    func _ready() -> void:
        scene_id = "office"
        super._ready()
        door_trigger.input_event.connect(_on_door_trigger_input)
    ```
  - **Bug #2 — `ss.get("hope", 5.0)` (line 32):** StateSystem has `hope` as a custom property with a getter. Access it directly as `ss.hope`. Replace the 2-arg `get()` call with property access + null fallback:
    ```gdscript
    # OLD:
    var hope_val: float = ss.get("hope", 5.0) if ss else (gm.get_slider("hope") if gm else 5.0)
    # NEW:
    var hope_val: float = ss.hope if ss else (gm.get_slider("hope") if gm else 5.0)
    ```
  - **Bug #3 — `ss.get("day", 0)` (line 53):** Replace with `ss.get("day")` (1-arg form) guarded by `ss.has("day")`:
    ```gdscript
    # OLD:
    day = int(ss.get("day", 0)) if ss.has("day") else 0
    # NEW:
    day = int(ss.get("day")) if ss.has("day") else 0
    ```
    Note: The original code already has `ss.has("day")` as a precondition, so the 1-arg `get()` is safe.
  - **Bug #4 — choice_container.get_children() on null:** Add null guard before the loop:
    ```gdscript
    # OLD:
    func _setup_choice_pool() -> void:
        _choice_labels.clear()
        for child in choice_container.get_children():
    # NEW:
    func _setup_choice_pool() -> void:
        _choice_labels.clear()
        if choice_container == null:
            return
        for child in choice_container.get_children():
    ```
  - **Bug #5 — office.tscn parse error:** Run `godot --headless --quit` to trigger re-import. If the file still fails, check for UTF-8 BOM or hidden characters and rewrite the file. If the error is from a stale cache, delete `.godot/imports/office.tscn-*` and re-import.
  - **footstep_office.wav:** Delete `.godot/imports/footstep_office.wav-*` cache entries, then re-run Godot to re-import. If it still fails, check if the file's UID is missing from `.godot/` metadata, and add it via the Godot editor as a last resort.
- **Pros:**
  - Minimal diff — only ~5 lines changed across 3 files
  - No architecture change — all existing behavior preserved
  - Low risk of regressions
  - Fast to implement and test
- **Cons:**
  - Does not address the underlying pattern that allowed these errors (no CI gate for compile)
  - `office.tscn` and `footstep_office.wav` fixes are environment-dependent (Godot import cache)
- **Risk:** Low — each fix targets a single documented error with a well-understood root cause
- **Effort:** 30 minutes

### Approach B: Architecture Refactor

- **Description:** Fix the root causes by redesigning the affected patterns:
  1. Change `scene_id` from a `var` to a virtual getter `func get_scene_id() -> String:` in `SceneBase`, with each subclass overriding the method.
  2. Add a custom `get(key: String, default: Variant = null) -> Variant` method to `StateSystem` that wraps the 1-arg `Node.get()` error with a proper default fallback.
  3. Make `dialogue_display_3d.gd` resilient by using `@onready var choice_container` with a null-checked helper accessor.
- **Pros:**
  - Prevents these exact bugs from recurring in future subclass scenes
  - Cleaner API for state queries
  - Addresses the pattern, not just the symptoms
- **Cons:**
  - Modifies base classes (`SceneBase`, `StateSystem`) — higher regression surface
  - Multiple subclass scenes may need updates if `scene_id` changes to a getter pattern
  - Longer implementation and review cycle
  - Over-engineered for 5 compile errors that are one-time fixes
- **Risk:** Medium — changing base classes affects all subclass scenes
- **Effort:** 2–4 hours

### Recommendation

→ **Approach A (In-Place Minimal Fixes)** because:
1. All 5 bugs have clear, isolated root causes with trivial fixes.
2. The errors are one-time artifacts from auto-merged implement PRs, not systemic design flaws.
3. Minimal diffs reduce review burden and merge conflict risk.
4. The same CI gate (`godot --headless --quit`) that caught these errors will catch any future regressions.
5. Architecture refactors (Approach B) should be a separate issue if the team decides the patterns themselves are problematic.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

- [ ] **AC1: office.gd loads without member redeclaration error**
  - `godot --headless --quit` does not report "The member 'scene_id' already exists in parent class SceneBase"
  - `scene_id` has value `"office"` after OfficeScene enters `_ready()`
- [ ] **AC2: office.gd `get()` calls use valid 1-arg syntax**
  - `ss.get("hope", 5.0)` replaced with `ss.hope` on line 32 — compiles without "Too many arguments" error
  - `ss.get("day", 0)` replaced with `ss.get("day")` on line 53 — compiles without "Too many arguments" error
  - When `ss` is null, falls back to `gm.get_slider("hope")` on line 32 and `0` on line 53
- [ ] **AC3: dialogue_display_3d.gd handles null choice_container**
  - If `choice_container` is null, `_setup_choice_pool()` returns early without calling `get_children()` on null
  - `_choice_labels` array is empty after early return (no crash)
- [ ] **AC4: office.tscn parses without error**
  - `godot --headless --quit` does not report parse error for `office.tscn:46`
  - Lighting properties on the DirectionalLight3D node are valid
- [ ] **AC5: footstep_office.wav loads without "No loader found"**
  - `_try_load("res://assets/audio/footstep_office.wav")` returns a valid `AudioStream` (not null)
  - Audio plays when player enters office scene
- [ ] **AC6: `godot --headless --quit` exits with code 0**
  - No script errors reported during headless load
  - No parse errors in any scene file

### Edge Cases

1. **StateSystem autoload not available:** If `ss` is null (headless test context), `office.gd` falls back to `gm.get_slider()`. Both fallbacks must survive double-null with hardcoded defaults.
2. **Dialogue3D scene variant without ChoiceContainer:** If a different scene variant uses `DialogueDisplay3D` without a `ChoiceContainer` child node, `$ChoiceContainer` is null — the null guard in `_setup_choice_pool()` returns gracefully.
3. **Footstep WAV fails to import on first run:** Fresh checkout + first Godot launch — import cache is empty. The `_try_load()` function already handles null returns with `push_warning`. No crash, just silent audio. The fix is to verify the import succeeds after cache clear.
4. **Multiple subclass scenes with scene_id:** If `CityScene.gd`, `StoreScene.gd`, etc. also declare `var scene_id: String = "..."`, they will hit the same redeclaration error. The fix to `office.gd` serves as a template for the pattern to use in other scenes.
5. **`has("day")` returns false:** The `day` variable defaults to `0` when `ss` doesn't have the "day" key. The `ss.get("day")` call with 1 arg is safe because it's guarded by `ss.has("day")`.

### Failure Paths

1. **office.tscn parse error persists after fix:** If the error is in Godot's `.godot/imports/` cache and not in the file itself, delete the cache entry and re-run. Worst case: rewrite the scene file using the Godot editor (re-export).
2. **footstep_office.wav still doesn't load:** If the 44100Hz sample rate causes a Godot import bug, convert to 22050Hz (matching other WAV files) using `ffmpeg -i footstep_office.wav -ar 22050 footstep_office_fixed.wav`.
3. **New compile errors appear in other files:** The implement PR should run `godot --headless --quit` and report any new errors discovered after these fixes are applied.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| `scene_base.gd` — `scene_id` var declared on line 10 | Stable | Low — base class stays unchanged |
| `state_system.gd` — `hope` property (getter access via `.hope`) | Stable | Low — property access is idiomatic GDScript |
| `Dialouge3D.tscn` — `ChoiceContainer` node at line 40 | Stable | Low — node exists in the scene file |
| `audio_manager.gd` — `_try_load()` function | Stable | Low — handles null return gracefully |
| `Godot 4.7.1` engine import pipeline | Stable | Medium — import cache may need manual clearing |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Any feature that requires loading office.tscn (starting scene) | Critical |
| CI/CD pipeline `godot --headless --export-debug` | Critical |
| All subsequent scenes (city, store, underpass) that depend on the scene loading pipeline | High |

### Preparation Needed

- [ ] Delete stale `.godot/imports/` cache entries for `office.tscn` and `footstep_office.wav` before testing
- [ ] Run `godot --headless --quit` to verify all fixes

```
Dependency Chain:

scene_base.gd (var scene_id: String) ──► office.gd (must NOT redeclare)
    │
    └──► All scene scripts inherit from SceneBase

StateSystem (hope property, no custom get(key, default))
    │
    └──► office.gd lines 32, 53 (must use property access, not 2-arg get())

Dialouge3D.tscn (ChoiceContainer node exists)
    │
    └──► dialogue_display_3d.gd (must guard against null container)

audio_manager.gd _load_audio_streams()
    └──► footstep_office.wav on disk (must be importable by Godot 4.7.1)
```

---

## 7. Spike / Experiment

Skipped per `depth/standard` label. The root causes are well-understood from source code analysis and hexdump inspection.

---

## 8. Continuation Context

> *This section is the handoff to the plan agent. It captures the current state of the fix area so the plan agent can pick up without re-scanning all source files.*

The compile error fix area has 5 concrete bugs across 3 GDScript files (`gdscripts/office.gd`, `gdscripts/dialogue_display_3d.gd`, `gdscripts/audio_manager.gd`), 1 scene file (`scenes/office/office.tscn`), and 1 audio asset (`assets/audio/footstep_office.wav`).

**Office.gd current state:**
- Line 12: `var scene_id: String = "office"` — **remove `var`**, set in `_ready()` before `super._ready()`
- Line 32: `ss.get("hope", 5.0)` — **change to `ss.hope`** (StateSystem `hope` is a custom property with getter)
- Line 53: `ss.get("day", 0)` — **change to `ss.get("day")`** (already guarded by `ss.has("day")`)

**DialogueDisplay3D current state:**
- Line 44: `for child in choice_container.get_children():` — **add null guard** `if choice_container == null: return` before the loop

**Office.tscn current state:**
- Line 46: `light_color = Color(0.9, 0.7, 0.4)` — valid syntax per hexdump. If error persists, delete `.godot/imports/` cache.

**Footstep_office.wav current state:**
- File exists (44KB, PCM 16-bit mono 44100Hz). Delete `.godot/imports/footstep_office.wav-*` cache. If still fails, convert to 22050Hz.

**Testing approach:** Run `godot --headless --quit` — should exit with code 0 and no error output.

The main risk is that the Godot import cache has stale entries that mask whether the actual fixes are sufficient. Always clear the cache before the final verification run.
