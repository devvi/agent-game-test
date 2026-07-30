# TASKS: [Integration] 主场景组装 — Main Scene Assembly

> **Issue:** #295
> **Priority:** P0 (high)
> **Duration:** 3–5 hours
> **Prerequisites:** All #287–#294 CLOSED; research PR #335 merged
> **Design Reference:** docs/DESIGN/295-main-scene-assembly.md
> **PRD Reference:** docs/PRD/295-main-scene-assembly.md

---

## Phase 1: Constants Extraction (纯增量，零破坏性)

**Rationale:** Extract all scattered constants into a single `constants.gd` first, before touching the scene file. This is a pure-addition step — no existing behavior changes. All constant values remain identical; only their definition location moves. Tests should pass without modification after this phase.

| ID | Task | Files Affected | Dependencies | Est. |
|----|------|----------------|:------------:|:----:|
| T1.1 | Create `gdscripts/constants.gd` with `class_name GameConstants` | `constants.gd` (NEW) | None | 15m |
| T1.2 | Migrate `ball.gd` constants to reference `GameConstants` via `preload()` | `ball.gd` | T1.1 | 15m |
| T1.3 | Migrate `paddle.gd` constants to reference `GameConstants` | `paddle.gd` | T1.1 | 10m |
| T1.4 | Migrate `scoring_manager.gd` POINTS/GAMES constants | `scoring_manager.gd` | T1.1 | 5m |
| T1.5 | Migrate `game_manager.gd` POINTS/GAMES constants | `game_manager.gd` | T1.1 | 5m |
| T1.6 | Run headless compilation + full test suite | All .gd files | T1.2–T1.5 | 10m |

### Validation (per task)

- **T1.1:** `constants.gd` exists at `mini-pong/gdscripts/constants.gd`. Contains all 20 constants from DESIGN §2.2 with exact values from original scripts.
- **T1.2:** `ball.gd` compiles. `CONSTS.BALL_INITIAL_SPEED == 300.0`. All ball physics unchanged.
- **T1.3:** `paddle.gd` compiles. `CONSTS.PADDLE_SPEED == 400.0`. Player + AI paddle movement unchanged.
- **T1.4:** `scoring_manager.gd` compiles. `CONSTS.POINTS_TO_WIN_GAME == 5`. Scoring thresholds unchanged.
- **T1.5:** `game_manager.gd` compiles. `CONSTS.POINTS_TO_WIN_GAME == 5`. No duplicate definitions remain.
- **T1.6:** `godot --headless --quit` → exit 0. `godot --headless --script tests/run_tests.gd` → all pass.

**Phase 1 Gate:** All tests pass with zero behavioral changes. If `class_name` fails in headless mode, switch all consumers to `preload()` — documented in DESIGN §2.2 Design Note.

---

## Phase 2: Scene Assembly (增量添加节点)

**Rationale:** Copy `game.tscn` → `Main.tscn`, then add 4 missing nodes. Keep all existing NodePath exports and signal connections intact. This is additive — the original `game.tscn` remains untouched until Phase 3 path updates confirm Main.tscn works.

| ID | Task | Files Affected | Dependencies | Est. |
|----|------|----------------|:------------:|:----:|
| T2.1 | Copy `game.tscn` → `Main.tscn` | `Main.tscn` (NEW) | Phase 1 ✓ | 5m |
| T2.2 | Add `WorldEnvironment` instance (ext_resource `world_environment.tscn`) | `Main.tscn` | T2.1 | 10m |
| T2.3 | Add `ScoreZoneLeft` Area2D (pos 0,360, collider 20×720) | `Main.tscn` | T2.1 | 10m |
| T2.4 | Add `ScoreZoneRight` Area2D (pos 1280,360, collider 20×720) | `Main.tscn` | T2.1 | 5m |
| T2.5 | Add `ScoreFlash` Node + child ColorRect "ScoreFlashRect" | `Main.tscn` | T2.1 | 10m |
| T2.6 | Add ScoreZone `body_entered` signal wiring in `ball.gd` `_ready()` | `ball.gd` | T2.3, T2.4 | 10m |
| T2.7 | Add `_scored_this_frame` dual-trigger guard in `ball.gd` | `ball.gd` | T2.6 | 5m |
| T2.8 | Verify Main.tscn loads in Godot editor with 0 warnings | `Main.tscn` | T2.2–T2.5 | 10m |

### Validation (per task)

- **T2.1:** `Main.tscn` is byte-identical to `game.tscn` at this point (except file path in Godot metadata).
- **T2.2:** `WorldEnvironment` node present at scene root. `glow_intensity=0.6`, `glow_bloom=0.8`, `bg_color=Color(0.039,0.039,0.071,1)`.
- **T2.3:** `ScoreZoneLeft` Area2D with child `CollisionShape2D` (RectangleShape2D 20×720). Position (0, 360).
- **T2.4:** `ScoreZoneRight` Area2D with child `CollisionShape2D` (RectangleShape2D 20×720). Position (1280, 360).
- **T2.5:** `ScoreFlash` Node with child `ColorRect` named "ScoreFlashRect" (1280×720, modulate.a=0.0).
- **T2.6:** `ball.gd` `_ready()` connects to ScoreZoneLeft/Right `body_entered` via `get_parent().get_node_or_null()`. Gracefully handles null zones.
- **T2.7:** `_scored_this_frame` reset at top of `_process()`. Both ScoreZone and X-boundary paths check flag before emitting.
- **T2.8:** Open Main.tscn in Godot Editor → zero warnings in Output panel. All ext_resource references resolve. Scene tree displays all 14+ nodes.

**Phase 2 Gate:** Main.tscn loads in editor without errors. WorldEnvironment glow visible in editor viewport. ScoreZones visible as Area2D collision shapes.

---

## Phase 3: Path Updates & File Rename (全局替换 + 删除旧文件)

**Rationale:** Update all hardcoded `game.tscn` references to `Main.tscn`, then delete the old file. This phase is globally destructive in path space but behaviorally neutral — the scene tree is the same, only the filename changes.

| ID | Task | Files Affected | Dependencies | Est. |
|----|------|----------------|:------------:|:----:|
| T3.1 | Update `project.godot` `run/main_scene` → `Main.tscn` | `project.godot` | Phase 2 ✓ | 2m |
| T3.2 | Update `test_ball.gd` references: `game.tscn` → `Main.tscn` (4 lines) | `test_ball.gd` | T3.1 | 5m |
| T3.3 | Update `test_ui_system.gd` references: `game.tscn` → `Main.tscn` (5 lines) | `test_ui_system.gd` | T3.1 | 5m |
| T3.4 | Run `grep -r "game\.tscn" mini-pong/` to find remaining references | All .gd/.tscn/.godot | T3.2, T3.3 | 2m |
| T3.5 | Update `game_state_machine.gd` comments (lines 23, 194) | `game_state_machine.gd` | T3.4 | 5m |
| T3.6 | Delete `scenes/game.tscn` | `game.tscn` (DELETE) | T3.5 | 1m |

### Validation (per task)

- **T3.1:** `grep 'run/main_scene' project.godot` → `"res://scenes/Main.tscn"`. NOT `game.tscn`.
- **T3.2:** `grep 'game.tscn' test_ball.gd` → zero matches. `grep 'Main.tscn' test_ball.gd` → 4 matches (was 4 before).
- **T3.3:** `grep 'game.tscn' test_ui_system.gd` → zero matches. `grep 'Main.tscn' test_ui_system.gd` → 5 matches.
- **T3.4:** Zero `game.tscn` matches in .gd/.tscn/.godot files. Exclude `docs/` directory.
- **T3.5:** Comments on lines 23 and 194 reference `Main.tscn`, not `game.tscn`.
- **T3.6:** `mini-pong/scenes/game.tscn` does not exist. `ls scenes/` shows `Main.tscn` but not `game.tscn`.

**Phase 3 Gate:** Zero `game.tscn` references in codebase. `project.godot` points to `Main.tscn`. Old file deleted.

---

## Phase 4: Compilation & Test Verification

**Rationale:** Run the full verification pipeline to confirm the assembled scene works end-to-end. This is the final gate before merge.

| ID | Task | Files Affected | Dependencies | Est. |
|----|------|----------------|:------------:|:----:|
| T4.1 | Run headless compilation: `godot --headless --quit` | All | Phase 3 ✓ | 2m |
| T4.2 | Run script check: `godot --headless --script tests/check_compile.gd` | All | T4.1 | 2m |
| T4.3 | Run test suite: `godot --headless --script tests/run_tests.gd` | All | T4.2 | 3m |
| T4.4 | Fix any test failures (path references, constant values) | Affected .gd files | T4.3 | 20m |
| T4.5 | Re-run test suite after fixes | All | T4.4 | 3m |

### Validation

- **T4.1:** Exit code 0. No `ERROR:` lines in stderr.
- **T4.2:** All scripts compile. No parse errors. No "Missing resource" errors.
- **T4.3:** All tests pass. If failures exist, note which tests and proceed to T4.4.
- **T4.4:** Each failure addressed. Common causes: (a) test_ball.gd TC-A3 expecting `game.tscn` → update to `Main.tscn`; (b) test_ui_system.gd TC15 expecting `game.tscn` → update; (c) `class_name GameConstants` not resolved in headless → switch to `preload()`.
- **T4.5:** All tests pass. Exit code 0.

**Phase 4 Gate:** Full test suite green. Acceptable known gaps (non-blocking): `game_won` signal has no UI consumer (per PRD §6, deferred to P3); paddle ShaderMaterial not yet applied (per PRD §6, deferred to P2).

---

## Dependency Graph

```
Phase 1 (Constants)
  T1.1 ──┬── T1.2 ──┐
         ├── T1.3 ──┤
         ├── T1.4 ──┼── T1.6 (verify)
         └── T1.5 ──┘
                          │
Phase 2 (Scene Assembly)  │
  T2.1 ──┬── T2.2 ──┐    │
         ├── T2.3 ──┤    │
         ├── T2.4 ──┼─ T2.6 ── T2.7 ──┐
         ├── T2.5 ──┘                  ├── T2.8 (verify)
         └────────────────────────────┘
                          │
Phase 3 (Paths)           │
  T3.1 ──┬── T3.2 ──┐    │
         └── T3.3 ──┼─ T3.4 ── T3.5 ── T3.6
                    │
Phase 4 (Verify)     │
  T4.1 ── T4.2 ── T4.3 ── T4.4 ── T4.5
```

---

## Summary

| Type | Count | Est. Lines |
|------|:-----:|:----------:|
| New files | 2 | ~+220 |
| Modified files | 7 | ~+45 |
| Deleted files | 1 | −140 |
| **Total** | **10** | **~+265 / −140** |

### File Change Table

| File | Type | Est. Lines |
|------|------|:----------:|
| `gdscripts/constants.gd` | New | +55 |
| `scenes/Main.tscn` | New | +165 |
| `scenes/game.tscn` | Delete | −140 |
| `project.godot` | Modify | ±1 |
| `gdscripts/ball.gd` | Modify | +25 |
| `gdscripts/paddle.gd` | Modify | ±4 |
| `gdscripts/scoring_manager.gd` | Modify | ±2 |
| `gdscripts/game_manager.gd` | Modify | ±2 |
| `gdscripts/game_state_machine.gd` | Modify | ±2 |
| `tests/test_ball.gd` | Modify | ±4 |
| `tests/test_ui_system.gd` | Modify | ±5 |

### Verification Protocol

```bash
# Primary: full pipeline
cd mini-pong
godot --headless --quit                                    # → exit 0
godot --headless --script tests/check_compile.gd           # → exit 0
godot --headless --script tests/run_tests.gd               # → exit 0

# Secondary: grep for stale references
grep -r "game\.tscn" . --include="*.gd" --include="*.tscn" --include="*.godot" | grep -v docs/
# → zero output

# Tertiary: verify project.godot
grep "run/main_scene" project.godot
# → run/main_scene="res://scenes/Main.tscn"
```
