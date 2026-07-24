# Design: #213 — 雨夜普罗摩茨项目骨架 (Rainy Night Prometheus Scaffold)

> Parent Issue: #213
> Agent: plan-agent
> Date: 2026-07-24

---

## 1. Architecture Overview

### Core Idea

Create `rainy-night-prometheus/` as a second independent Godot 4.7.1 sub-project within the `agent-game-test` monorepo, reusing 6 core gdscripts from `urban-night-walker` (the root project) via symlinks. This scaffold establishes project isolation (independent `project.godot`, own scenes, dialogues, assets) while sharing the CRPG infrastructure — dialogue engine, state system, scene management — through filesystem symlinks that guarantee zero code drift.

### Data Flow

```ascii
Git Clone
    │
    └─ agent-game-test/
        │
        ├─ project.godot          ← urban-night-walker (root project)
        ├─ gdscripts/             ← 45 scripts (source of truth for 6 shared scripts)
        ├─ scenes/
        ├─ tests/
        │
        └─ rainy-night-prometheus/     ← independent sub-project
            ├─ project.godot           ← independent config, renderer, autoloads
            ├─ gdscripts/              ← 6 symlinks → ../gdscripts/*.gd
            ├─ scenes/                 ← empty — for RNP-specific scenes
            ├─ dialogues/json/         ← empty — for RNP dialogue content
            ├─ assets/materials/       ← empty — for RNP materials
            ├─ assets/audio/           ← empty — for RNP audio
            └─ tests/                  ← empty — for RNP tests

Godot Engine startup (godot --path rainy-night-prometheus/ --headless --quit)
    │
    ├─ project.godot loads config
    │   ├─ Renderer: forward_plus
    │   ├─ Window: 1920×1080
    │   ├─ Icon: res://assets/icon.png (symlink or copy of root assets/icon.png)
    │   └─ Autoloads:
    │       ├─ StateSystem        → res://gdscripts/state_system.gd     (symlink → ../gdscripts/)
    │       ├─ DialogueRunner     → res://gdscripts/dialogue_runner.gd  (symlink → ../gdscripts/)
    │       ├─ DialogueParser     → res://gdscripts/dialogue_parser.gd  (symlink → ../gdscripts/)
    │       ├─ SceneManager       → res://gdscripts/scene_manager.gd    (symlink → ../gdscripts/)
    │       └─ SceneBase          → res://gdscripts/scene_base.gd       (symlink → ../gdscripts/)
    │
    └─ Engine parses autoload scripts → follows symlinks → loads actual .gd files
         → syntax-check passes → engine quits cleanly with exit code 0
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sub-project location | `rainy-night-prometheus/` at repo root | Co-located with urban-night-walker; both share the same `gdscripts/` source tree. Godot's `--path` flag handles sub-directory projects. |
| Script reuse method | Symlinks (relative paths) | Zero code drift — urban-night-walker updates propagate automatically. Git stores symlinks as `120000` mode. No `git submodule` overhead. |
| Symlink target paths | `../gdscripts/xxx.gd` | Godot resolves `res://gdscripts/xxx.gd` in the sub-project's context, which maps to `rainy-night-prometheus/gdscripts/xxx.gd`. The symlink target `../gdscripts/xxx.gd` then resolves from `rainy-night-prometheus/gdscripts/` up to repo root `gdscripts/xxx.gd`. |
| Autoload naming | Same names as urban-night-walker for shared scripts | Scripts are identical (via symlink), so autoload names must be identical. There is no name conflict since autoloads are scoped per project. |
| `res://` path resolution | Godot's `--path` flag sets `res://` to the sub-project dir | Confirmed by PRD research experiments — Godot 4.7 treats the `--path` directory as the project root. Symlinks resolve through the filesystem normally. |
| `.gitattributes` | Add `core.symlinks=true` recommendation in README | macOS/Linux handle symlinks natively. Windows requires `git config core.symlinks true` before clone. |
| No runnable tests in Plan phase | Test descriptions only in DESIGN doc | Tests will be created during the Implement phase after the scaffold is merged. |

---

## 2. Directory Structure & Symlink Layout

### Full Directory Tree

```
rainy-night-prometheus/
├── project.godot           # Godot 4.7.1 project configuration
├── README.md               # Project documentation
├── gdscripts/              # Symlinks to root gdscripts/ (6 files)
│   ├── dialogue_runner.gd  → ../gdscripts/dialogue_runner.gd
│   ├── dialogue_parser.gd  → ../gdscripts/dialogue_parser.gd
│   ├── state_system.gd     → ../gdscripts/state_system.gd
│   ├── scene_manager.gd    → ../gdscripts/scene_manager.gd
│   ├── scene_base.gd       → ../gdscripts/scene_base.gd
│   └── constants.gd        → ../gdscripts/constants.gd
├── scenes/                 # Empty — RNP-specific scene files go here
├── dialogues/
│   └── json/               # Empty — RNP dialogue JSON files go here
├── assets/
│   ├── materials/          # Empty — RNP material resources go here
│   ├── audio/              # Empty — RNP audio files go here
│   └── icon.png            # Symlink → ../assets/icon.png (project icon)
└── tests/                  # Empty — RNP test scripts go here
```

### Symlink Creation Commands

```bash
# From repo root:
mkdir -p rainy-night-prometheus/gdscripts
cd rainy-night-prometheus/gdscripts
ln -s ../../gdscripts/dialogue_runner.gd dialogue_runner.gd
ln -s ../../gdscripts/dialogue_parser.gd dialogue_parser.gd
ln -s ../../gdscripts/state_system.gd state_system.gd
ln -s ../../gdscripts/scene_manager.gd scene_manager.gd
ln -s ../../gdscripts/scene_base.gd scene_base.gd
ln -s ../../gdscripts/constants.gd constants.gd
cd ../..
```

> **Note on path calculation:** The symlinks live in `rainy-night-prometheus/gdscripts/`. From that directory, `../gdscripts/xxx.gd` would go to `rainy-night-prometheus/gdscripts/xxx.gd` — wrong! The correct relative path is `../../gdscripts/xxx.gd` because we need three path segments: `rainy-night-prometheus/gdscripts/` → `rainy-night-prometheus/` → `repo-root/` → `gdscripts/xxx.gd`.

### Icon Symlink

```bash
ln -s ../assets/icon.png rainy-night-prometheus/assets/icon.png
```

### Git Symlink Tracking Verification

After adding symlinks, verify with:
```bash
git ls-files -s rainy-night-prometheus/gdscripts/
```
Expected output: `120000` mode for each symlink (not `100644` for regular files).

---

## 3. project.godot Configuration

### Full project.godot Content

```ini
; Godot 4.7 project file for Rainy Night Prometheus
; Created by Hermes Workflow Framework

[application]
config/name="Rainy Night Prometheus"
config/description="A narrative-driven CRPG set in a rainy nightscape"
config/features=PackedStringArray("4.7")
config/icon="res://assets/icon.png"

[rendering]
renderer/rendering_method="forward_plus"

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/mode=0
window/size/always_on_top=false
window/dpi/allow_hidpi=true

[autoload]
StateSystem="*res://gdscripts/state_system.gd"
DialogueRunner="*res://gdscripts/dialogue_runner.gd"
DialogueParser="*res://gdscripts/dialogue_parser.gd"
SceneManager="*res://gdscripts/scene_manager.gd"
SceneBase="*res://gdscripts/scene_base.gd"

[editor_plugins]
enabled=PackedStringArray()

[input]
; Same input mappings as urban-night-walker for consistency
toggle_debug={
"deadzone": 0.5,
"events": [{"keycode": 4194326, "type": 0}]
}
toggle_dialogue={
"deadzone": 0.5,
"events": [{"keycode": 4194318, "type": 0}]
}
dialogue_up={
"deadzone": 0.5,
"events": [{"keycode": 4194319, "type": 0}]
}
dialogue_down={
"deadzone": 0.5,
"events": [{"keycode": 4194321, "type": 0}]
}
dialogue_select={
"deadzone": 0.5,
"events": [{"keycode": 4194306, "type": 0}, {"keycode": 32, "type": 0}]
}
dialogue_skip={
"deadzone": 0.5,
"events": [{"keycode": 4194305, "type": 0}]
}
digit_1={
"deadzone": 0.5,
"events": [{"keycode": 49, "type": 0}]
}
digit_2={
"deadzone": 0.5,
"events": [{"keycode": 50, "type": 0}]
}
digit_3={
"deadzone": 0.5,
"events": [{"keycode": 51, "type": 0}]
}
digit_4={
"deadzone": 0.5,
"events": [{"keycode": 52, "type": 0}]
}
move_forward={
"deadzone": 0.5,
"events": [{"keycode": 87, "type": 0}, {"keycode": 4194320, "type": 0}]
}
move_backward={
"deadzone": 0.5,
"events": [{"keycode": 83, "type": 0}, {"keycode": 4194322, "type": 0}]
}
move_left={
"deadzone": 0.5,
"events": [{"keycode": 65, "type": 0}, {"keycode": 4194319, "type": 0}]
}
move_right={
"deadzone": 0.5,
"events": [{"keycode": 68, "type": 0}, {"keycode": 4194321, "type": 0}]
}
interact={
"deadzone": 0.5,
"events": [{"keycode": 69, "type": 0}]
}
```

### Autoload Registration Rationale

| Autoload Name | Script | Why Included | Expected Resolution |
|---------------|--------|-------------|---------------------|
| `StateSystem` | `state_system.gd` | Core CRPG state machine — all features depend on it | Symlink → `../gdscripts/state_system.gd` |
| `DialogueRunner` | `dialogue_runner.gd` | Runtime dialogue display and interaction | Symlink → `../gdscripts/dialogue_runner.gd` |
| `DialogueParser` | `dialogue_parser.gd` | JSON dialogue file loading and parsing | Symlink → `../gdscripts/dialogue_parser.gd` |
| `SceneManager` | `scene_manager.gd` | Scene transition management | Symlink → `../gdscripts/scene_manager.gd` |
| `SceneBase` | `scene_base.gd` | Base scene class for RNP scenes | Symlink → `../gdscripts/scene_base.gd` |
| `Constants` | `constants.gd` (not registered as autoload) | Used via `const Constants = preload("res://gdscripts/constants.gd")` in scripts | Symlink → `../gdscripts/constants.gd` |

> `constants.gd` is not registered as an autoload because it only defines constants and enums — it's `preload()`-ed by scripts that need it, not instantiated as a singleton.

---

## 4. README.md Content

```markdown
# Rainy Night Prometheus

A narrative-driven CRPG set in a rainy nightscape.

## Getting Started

### Prerequisites
- Godot 4.7.1
- Git with symlink support

### Clone & Run

```bash
git clone <repo-url>
cd agent-game-test
godot --path rainy-night-prometheus/ --headless --quit
```

To open in the Godot editor:
```bash
godot --path rainy-night-prometheus/ --editor
```

### Project Structure

- `project.godot` — Independent Godot project configuration
- `gdscripts/` — Symlinks to shared CRPG scripts from `urban-night-walker` (root project)
- `scenes/` — Rainy Night Prometheus scene files
- `dialogues/json/` — Dialogue JSON files
- `assets/` — Materials, audio, and icon resources
- `tests/` — Test scripts

### Symlinks & Cross-Project Script Sharing

This project reuses 6 core scripts from `urban-night-walker` via symlinks:
- `dialogue_runner.gd`, `dialogue_parser.gd`, `state_system.gd`
- `scene_manager.gd`, `scene_base.gd`, `constants.gd`

**Windows users:** Enable symlink support before cloning:
```bash
git config --global core.symlinks true
```

### Verification

```bash
godot --path rainy-night-prometheus/ --headless --quit
# Expected: exit code 0, no errors
```

## License

Same as parent repository.
```

---

## 5. Test Case Descriptions

> **Note:** These are test case **descriptions only** — no runnable test files will be created during the Plan phase. The Implement phase will create actual test scripts in `rainy-night-prometheus/tests/`.

### TC-1: Directory Structure Completeness

| Field | Value |
|-------|-------|
| **ID** | `scaffold-tc-01` |
| **Type** | Structural verification |
| **Description** | Verify all required directories and files exist under `rainy-night-prometheus/` |
| **Checklist** | |
| | `rainy-night-prometheus/project.godot` exists and is readable |
| | `rainy-night-prometheus/README.md` exists and is readable |
| | `rainy-night-prometheus/gdscripts/` is a directory |
| | `rainy-night-prometheus/scenes/` is a directory |
| | `rainy-night-prometheus/dialogues/` is a directory |
| | `rainy-night-prometheus/dialogues/json/` is a directory |
| | `rainy-night-prometheus/assets/materials/` is a directory |
| | `rainy-night-prometheus/assets/audio/` is a directory |
| | `rainy-night-prometheus/tests/` is a directory |
| | `rainy-night-prometheus/assets/icon.png` exists (symlink or file) |
| **Verification method** | Shell commands: `[ -f path ] && [ -d path ]` checks |

### TC-2: Symlink Correctness

| Field | Value |
|-------|-------|
| **ID** | `scaffold-tc-02` |
| **Type** | Symlink resolution verification |
| **Description** | Verify that all 6 symlinks in `rainy-night-prometheus/gdscripts/` correctly resolve to the target script in the root `gdscripts/` |
| **Checklist** | |
| | `dialogue_runner.gd` resolves to `gdscripts/dialogue_runner.gd` |
| | `dialogue_parser.gd` resolves to `gdscripts/dialogue_parser.gd` |
| | `state_system.gd` resolves to `gdscripts/state_system.gd` |
| | `scene_manager.gd` resolves to `gdscripts/scene_manager.gd` |
| | `scene_base.gd` resolves to `gdscripts/scene_base.gd` |
| | `constants.gd` resolves to `gdscripts/constants.gd` |
| **Verification method** | `readlink rainy-night-prometheus/gdscripts/xxx.gd` and verify the target path; also `diff rainy-night-prometheus/gdscripts/xxx.gd gdscripts/xxx.gd` should show identical content (following symlink) |

### TC-3: Git Symlink Tracking

| Field | Value |
|-------|-------|
| **ID** | `scaffold-tc-03` |
| **Type** | Git metadata verification |
| **Description** | Verify that git tracks symlinks with `120000` mode (not `100644` regular file mode) |
| **Checklist** | |
| | `git ls-files -s rainy-night-prometheus/gdscripts/dialogue_runner.gd` returns `120000` |
| | `git ls-files -s rainy-night-prometheus/gdscripts/dialogue_parser.gd` returns `120000` |
| | `git ls-files -s rainy-night-prometheus/gdscripts/state_system.gd` returns `120000` |
| | `git ls-files -s rainy-night-prometheus/gdscripts/scene_manager.gd` returns `120000` |
| | `git ls-files -s rainy-night-prometheus/gdscripts/scene_base.gd` returns `120000` |
| | `git ls-files -s rainy-night-prometheus/gdscripts/constants.gd` returns `120000` |
| | `git ls-files -s rainy-night-prometheus/assets/icon.png` returns `120000` |
| **Verification method** | `git ls-files -s rainy-night-prometheus/gdscripts/xxx.gd` — check mode bits |

### TC-4: Headless Godot Compilation

| Field | Value |
|-------|-------|
| **ID** | `scaffold-tc-04` |
| **Type** | Godot engine compilation verification |
| **Description** | Verify that `godot --path rainy-night-prometheus/ --headless --quit` runs without compilation errors |
| **Checklist** | |
| | Command exits with status 0 |
| | No GDScript parse errors in stderr/stdout |
| | No "autoload not found" errors |
| | No "unknown class" errors for referenced script types |
| | No "symlink resolution failed" errors |
| **Verification method** | `godot --path rainy-night-prometheus/ --headless --quit 2>&1; echo "Exit: $?"` |

### TC-5: project.godot Configuration Validation

| Field | Value |
|-------|-------|
| **ID** | `scaffold-tc-05` |
| **Type** | Configuration file parsing verification |
| **Description** | Verify that `project.godot` contains all required configuration sections and values |
| **Checklist** | |
| | `[application] config/name` is `"Rainy Night Prometheus"` |
| | `[rendering] renderer/rendering_method` is `"forward_plus"` |
| | `[display] window/size/viewport_width` is `1920` |
| | `[display] window/size/viewport_height` is `1080` |
| | All 5 autoload entries exist with correct paths |
| | `config/features` includes `"4.7"` |
| **Verification method** | Parse `project.godot` with `grep` or Python `configparser` |

### TC-6: Autoload Script Dependencies

| Field | Value |
|-------|-------|
| **ID** | `scaffold-tc-06` |
| **Type** | Script dependency verification |
| **Description** | Verify that each autoload-registered symlink script can be loaded by Godot and satisfies its own internal dependencies (e.g., `extends Node`, referenced classes/constants) |
| **Checklist** | |
| | `StateSystem` script loads and extends `Node` |
| | `DialogueRunner` script loads and can find `DialogueParser` |
| | `DialogueParser` script loads and can parse a minimal JSON dialogue |
| | `SceneManager` script loads without dependency errors |
| | `SceneBase` script loads and extends `Node` |
| **Verification method** | `godot --path rainy-night-prometheus/ --headless --quit` — all autoloads are loaded at startup; any dependency error will surface as a script error |

### TC-7: Icon File Existence

| Field | Value |
|-------|-------|
| **ID** | `scaffold-tc-07` |
| **Type** | Resource existence verification |
| **Description** | Verify that `rainy-night-prometheus/assets/icon.png` resolves to a valid file |
| **Checklist** | |
| | File exists (symlink or regular file) |
| | File is non-empty (at least the PNG header bytes) |
| | `file` command reports `PNG image data` |
| **Verification method** | `[ -f rainy-night-prometheus/assets/icon.png ] && file rainy-night-prometheus/assets/icon.png` |

---

## 6. Verification Plan

### Pre-Commit Verification

Before committing, the Plan phase will:

1. **Create directory structure** — `mkdir -p` for all subdirectories
2. **Create symlinks** — `ln -s` for all 6 scripts + icon
3. **Write `project.godot`** — with autoload registrations
4. **Write `README.md`** — project documentation
5. **Run `godot --headless --quit`** — verify the project compiles without errors
6. **Verify `git ls-files -s`** — confirm symlinks are `120000` mode
7. **Verify directory structure** — `[ -d path ]` for each directory
8. **Commit and create PR** — branch `plan/213-rainy-night-prometheus-scaffold`

### Post-Merge Verification (Implement Phase)

The Implement phase will:

1. Actually run `godot --path rainy-night-prometheus/ --headless --quit` as a CI or local test
2. Create runnable GDScript tests in `rainy-night-prometheus/tests/`
3. Verify each autoload symlink independently

---

## 7. CI Integration Notes

### How CI Runs This Project

```bash
# From repo root
godot --path rainy-night-prometheus/ --headless --quit
```

### stage-gate.py Considerations

If `scripts/stage-gate.py` is used for PR merge gating, it must be updated to handle the `rainy-night-prometheus/` sub-project. The gate should:
1. Detect which project(s) were modified in the PR
2. Run `godot --path rainy-night-prometheus/ --headless --quit` if any file under `rainy-night-prometheus/` changed
3. Not block on missing scenen or empty directories (scaffold is valid without scenes)

### GitHub Actions (If Applicable)

```yaml
- name: Validate Rainy Night Prometheus scaffold
  run: |
    godot --path rainy-night-prometheus/ --headless --quit
```

---

## 8. Edge Cases & Failure Modes

| Edge Case | Impact | Mitigation |
|-----------|--------|------------|
| Symlink target `../../gdscripts/xxx.gd` is wrong | Godot reports "script not found" for autoloads | Run `readlink` on each symlink and verify target exists before committing |
| Symlink wrongly stored as regular file in Git | Clone produces empty/corrupt files | Verify `git ls-files -s` shows `120000` |
| Godot ignores `--path` flag (older version) | `res://` resolves to repo root instead of sub-project | Ensure Godot 4.7.1 — check with `godot --version` |
| Windows clone without `core.symlinks=true` | Symlinks become empty text files | Document requirement in README; add `.gitattributes` as optional safeguard |
| `project.godot` has a syntax error | Godot fails to parse config | Validate with `godot --headless --quit` before commit |
| `assets/icon.png` missing | Godot warns about missing icon | Create symlink `ln -s ../assets/icon.png` |
| Symlink path uses absolute path | Not portable across machines | Always use relative paths (`../../gdscripts/xxx.gd`) |
