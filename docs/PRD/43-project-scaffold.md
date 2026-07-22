# Research: Project Scaffold — Godot 4.7 CRPG Base Framework

> Parent Issue: #43
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior
The project currently has a basic Godot 4.7 configuration from previous setup work, containing:
- **`project.godot`**: `forward_plus` renderer, 1920×1080 window, single `GameManager` autoload, basic features array (`"4.7"`)
- **`export_presets.cfg`**: Only Linux/X11 export preset; no macOS preset
- **`gdscripts/main.gd`**: Simple Hello World Label (`$Label.text = "Hello World"`)
- **`gdscripts/game_manager.gd`**: Minimal autoload with `game_started` boolean and print
- **`scenes/main.tscn`**: Root Node with a single Label child
- **`tests/run_tests.gd`**: 3 basic Label unit tests
- **Missing**: `GameState` singleton with hope/despair mechanics, proper input handling, 3D scene setup, placeholder architecture for dialogue/UI/text systems, scene hierarchy suited for CRPG development

### Expected Behavior
A CRPG-ready project scaffold with:
- **`project.godot`** configured for Godot 4.7.1 CRPG development with appropriate rendering settings
- **`GameState.gd`** autoload singleton managing global game state including `hope` and `despair` variables with a signal for state changes
- **Default scene** displaying a 3D text label that responds to keyboard input
- **Scene hierarchy** structured for CRPG development with placeholder slots for dialogue engine, UI overlay, and text rendering systems
- **Input mappings** configured for keyboard navigation and interaction
- **Export presets** for both macOS and Linux targets

### User Scenarios
- **Scenario A (Developer):** Clone the project, open in Godot 4.7.1, and immediately see a working 3D scene with a text label responding to keyboard input
- **Scenario B (Developer):** Begin implementing dialogue system, UI panels, and text components using pre-established placeholder nodes and GameState signals
- **Scenario C (CI/CD):** Every Push/PR triggers Godot headless tests verifying the project opens without errors
- **Frequency:** Every developer session, every CI run

---

## 2. Design Intent (Feature)

### Why Do We Need This?
This is the **foundation feature** — every subsequent system (dialogue engine, UI overlay, inventory, character management) depends on:
1. **GameState singleton** — All game state (hope, despair, narrative flags) must be globally accessible via autoload with signal-based change notifications
2. **Input handling** — Keyboard/mouse input must be mapped at the project level before any interactive system can work
3. **3D scene infrastructure** — The CRPG uses 3D environments; the default scene must demonstrate 3D text rendering and keyboard responsiveness
4. **Placeholder architecture** — Dialogue, UI, and text systems need pre-allocated nodes in the scene tree so downstream features can slot in without restructuring

### Why Change Now?
This is the **first infrastructure issue** in the project. All subsequent features (AC #44+, dialogue, UI, mechanics) depend on the scaffold being correct. Without it, every new feature will backtrack to fix foundational issues.

### Previous Constraints
- Project specifies Godot **4.7.1** (`game-env/manifest.yaml`); all config must be compatible
- Default branch is `main` (not `master`)
- Existing `GameManager` autoload must remain functional — `GameState` is an *additional* autoload
- Existing `tests/run_tests.gd` test framework must remain compatible
- Previous research attempt (PR #60, branch `research/43-project-scaffold`) was closed without merge — this is a clean restart

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `project.godot` | Project Config | Add input map entries, rendering optimizations for 3D CRPG |
| `export_presets.cfg` | Export Config | Add macOS export preset alongside existing Linux/X11 |
| `scenes/main.tscn` | Entry Scene | Restructure for CRPG: 3D root, text label, UI/dialogue placeholder nodes |
| `gdscripts/game_state.gd` | New — GameState Singleton | Create autoload with hope/despair variables + state_changed signal |
| `gdscripts/main.gd` | Main Script | Rewrite to handle keyboard input, display 3D text, initialize GameState |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/game_manager.gd` | Global Manager | GameState may reference or extend GameManager patterns |
| `tests/run_tests.gd` | Test Framework | CI must verify the new scaffold opens without errors |
| `docs/GAME_DESIGN/03-GODOT-SETUP.md` | Design Doc | Should be updated to reflect new project structure |

### Data Flow Impact
```
Godot Engine startup
    → project.godot loads config (renderer, input mappings)
    → Autoload GameManager initializes
    → Autoload GameState initializes (hope=100, despair=0)
    → scenes/main.tscn loads (3D root + text label + UI placeholder)
    → main.gd._ready() connects to GameState.state_changed signal
    → Player keyboard input → processed by main.gd._input()
    → Input updates text label content (AC3)
    → GameState emits state_changed signal on hope/despair change
```

### Documents to Update
- [x] `docs/PRD/43-project-scaffold.md` (this document)
- [ ] `docs/DESIGN/43-project-scaffold.md` (Plan phase)
- [ ] `docs/GAME_DESIGN/03-GODOT-SETUP.md` (after Implementation)
- [ ] `README.md` (if project structure changes significantly)

---

## 4. Solution Comparison

### Approach A: Incremental CRPG Scaffold (Recommended)
- **Description:** Build on the existing project files by adding a new `GameState` autoload, restructuring `main.tscn` for 3D CRPG, adding input mappings to `project.godot`, updating `export_presets.cfg` for macOS, and rewriting `main.gd` for keyboard-responsive 3D text.
- **Pros:**
  - Preserves existing code and test compatibility
  - Incremental changes — easy to review and verify
  - GameState can be built alongside existing GameManager without conflict
  - Placeholder nodes can be added without breaking existing functionality
- **Cons:**
  - project.godot input map must be manually configured (no editor UI)
  - 3D scene restructuring requires careful node hierarchy planning
- **Risk:** Low — standard Godot 4.7 configuration patterns
- **Effort:** ~6 files modified/created, ~200 lines total

### Approach B: Editor-First Full Scaffold
- **Description:** Delete existing project.godot, create a fresh Godot 4.7.1 project via editor with 3D template, then port existing scripts and scenes into the new structure.
- **Pros:**
  - Editor auto-generates input map, audio bus, and default 3D scene
  - Clean slate — no legacy config carryover
- **Cons:**
  - Destructive — existing GameManager autoload and tests must be manually re-registered
  - Harder to version-control as a PR diff
  - May introduce editor version-specific defaults
- **Risk:** Medium — existing tests and autoload must be manually re-integrated
- **Effort:** ~30 min manual work + debugging

### Recommendation
→ **Approach A** because: this is the foundational scaffold — the goal is a clean, reviewable PR that preserves existing functionality while adding the CRPG-specific GameState singleton, input handling, and 3D scene infrastructure. Incremental changes are easier to verify against the acceptance criteria and keep the existing tests passing.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path
1. `gdscripts/game_state.gd` created as an autoload singleton with `hope` and `despair` int variables and a `state_changed` signal
2. `project.godot` updated to register `GameState` autoload and input map entries
3. `scenes/main.tscn` restructured as a 3D scene (Node3D root) with a text label (Label3D) and placeholder nodes for UI/Control layer and dialogue system
4. `gdscripts/main.gd` rewritten to:
   - Accept keyboard input (arrow keys, Enter/Space, Esc)
   - Update the 3D text label content in response to input
   - Connect to GameState.state_changed signal
5. `export_presets.cfg` includes macOS export preset
6. Project opens without errors in Godot 4.7.1 on both macOS and Linux

### Edge Cases
1. **Godot 4.7.1 not installed locally:** CI must use GitHub Actions with `chickensoft-games/setup-godot@v2` to install the correct version
2. **GameManager ↔ GameState coexistence:** Both autoloads must load without conflict; GameState should be loaded second (runs after GameManager)
3. **Input mapping collisions:** Ensure keyboard mappings don't conflict with macOS system shortcuts (Cmd+Q, Cmd+H)
4. **3D rendering in headless CI:** Godot headless mode may not render Label3D — CI tests should verify project load and script execution, not visual output
5. **Existing PR #60 branch:** The branch `research/43-project-scaffold` was previously used and closed — ensure the new branch is created clean from `main`

### Failure Paths
1. **GameState autoload registration fails:** If `project.godot` autoload entry is malformed, Godot will error on startup → verify with `godot --headless --check-only`
2. **Input map entry format wrong:** Incorrect `[input]` section syntax in `project.godot` causes silent failures → verify by checking InputMap singleton at runtime
3. **Export preset path missing:** macOS export path `exports/` must be created before export

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Godot 4.7.1 engine | Stable | Low — confirmed in `game-env/manifest.yaml` |
| Existing `GameManager` autoload | Stable | Low — must remain functional |
| Existing `tests/run_tests.gd` | Stable | Low — must remain compatible |
| GitHub Actions runners | Available | Low — public repo quota |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Dialogue Engine (UI Control + input) | P0 — needs GameState and scene placeholder |
| UI System (Theme + layout + HUD) | P0 — needs Control layer placeholder nodes |
| Text System (narrative display, subtitles) | P0 — needs 3D text label infrastructure |
| Scene Switching (exploration areas) | P0 — needs main.tscn as entry point with proper hierarchy |

### Preparation Needed
- [ ] Confirm Godot 4.7.1 headless mode can open and validate the new project structure
- [ ] Verify `assets/icon.png` is present (confirmed — exists)
- [ ] Ensure no stale local branch `research/43-project-scaffold` remains from PR #60

---

## 7. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The Godot 4.7 CRPG project currently has a minimal setup: `project.godot` with `forward_plus` renderer, 1920×1080 window, and a `GameManager` autoload. `gdscripts/main.gd` sets a Hello World 2D label. `scenes/main.tscn` is a simple 2D scene with one Label node. `export_presets.cfg` has a single Linux/X11 preset. No GameState singleton exists. No input mappings are configured. No 3D scene infrastructure is present.

The proposed approach (Approach A) builds incrementally on the existing files: create `gdscripts/game_state.gd` as a new autoload with `hope` (int, default 100), `despair` (int, default 0), and a `state_changed` signal; update `project.godot` to register GameState and add input map entries (arrow keys, Enter/Space confirm, Esc pause); restructure `scenes/main.tscn` to use a Node3D root with a Label3D for text display plus placeholder Control nodes for UI overlay and dialogue; rewrite `gdscripts/main.gd` to handle keyboard input, update the 3D text label, and connect to GameState signals.

The main risk is ensuring the 3D scene structure is correct for Godot 4.7.1 — the Plan phase should verify Label3D node path references in the Godot headless environment. The CI workflow (`chickensoft-games/setup-godot@v2`) should use `--check-only` flag to validate project integrity without full rendering. macOS export preset requires downloading the macOS Godot export template, which must be done during CI setup.
