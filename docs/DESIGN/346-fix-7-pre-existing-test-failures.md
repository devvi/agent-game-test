# DESIGN: Fix 7 Pre-Existing Test Failures on Main (Round 2)

> **Parent Issue:** #346
> **Agent:** game-plan-agent
> **Date:** 2026-07-30
> **Approach:** A — Test-only fixes; no production code changes (PRD recommendation, confirmed)

---

## 1. Summary

Seven test failures were introduced on main by commit `284e056` (which attempted to fix 5 other test failures for #340). Six failures in `test_ui_system.gd` result from an incorrect API change (`get_theme_font_size("font_size")` → `font_size`) that returns 0 in headless Godot instead of the theme override from `.tscn` files. One failure in `test_pause.gd` results from a TC1.3 assertion that expects `game_hud.visible == true` in PAUSED state, but the FSM's `_set_ui("pause")` explicitly sets `game_hud.visible = false`. All fixes are test-only: 7 lines changed across 2 files, zero production code touched.

## 2. Root Cause Analysis

### Root Cause 1: `get_theme_font_size()` returns 0 in headless (6 failures)

Commit `284e056` replaced `label.font_size` with `label.get_theme_font_size("font_size")` in 6 assertions across `test_ui_system.gd`. The author believed Godot 4 requires the theme accessor to read font size from `.tscn` files. This is incorrect.

**How Godot 4 handles font_size:**
- `.tscn` files set `font_size = N`, which writes to the **theme override** slot on the Label node
- `Label.font_size` directly reads/writes this theme override — it's the correct Godot 4 API
- `Label.get_theme_font_size("font_size")` walks the theme resource chain (default Theme → any Theme resources attached → theme overrides)
- In headless mode (`--headless`), no project Theme is loaded, so `get_theme_font_size()` returns the theme default: **0**

**Current (broken):**
```gdscript
# Line 186 — title.get_theme_font_size("font_size") returns 0, .tscn has font_size=64
_assert(title.get_theme_font_size("font_size") >= 48, "TC5-5: ...")
# ❌ 0 >= 48 → FAIL
```

**Fix:** Revert to `label.font_size` which correctly reads the theme override from `.tscn`:
```gdscript
_assert(title.font_size >= 48, "TC5-5: ...")
# ✅ 64 >= 48 → PASS
```

**.tscn font_size values (for reference, all verified):**

| Scene | Node | `.tscn` font_size |
|-------|------|------------------:|
| `scenes/ui_start_menu.tscn` | TitleLabel | 64 |
| `scenes/ui_start_menu.tscn` | PromptLabel | 28 |
| `scenes/ui_game_hud.tscn` | PlayerScoreLabel | 28 |
| `scenes/ui_game_hud.tscn` | AIScoreLabel | 28 |
| `scenes/ui_game_over.tscn` | WinnerLabel | 72 |
| `scenes/ui_game_over.tscn` | RestartPromptLabel | 28 |

### Root Cause 2: TC1.3 asserts `game_hud.visible == true` in PAUSED state (1 failure)

Commit `284e056` changed the ball mock from `Node2D.new()` to `Area2D.new()`, matching the FSM's `@onready var ball: Area2D` type annotation. This is type-correct, but it exposed a pre-existing assertion bug in TC1.3.

**What the FSM actually does in PAUSED state** (`game_state_machine.gd:175-184`):
```gdscript
func _set_ui(layer: String) -> void:
    if game_hud:
        game_hud.visible = (layer == "hud")   # "pause" != "hud" → false
```

When `enter_state(PAUSED)` calls `_set_ui("pause")`, `game_hud.visible` is explicitly set to `false`. The PauseOverlay is shown instead. This is the FSM's **design behavior** — the HUD is hidden behind the pause screen.

**Current (broken):**
```gdscript
# Line 199
_assert(mocks.game_hud.visible == true, "TC1.3: game_hud still visible in PAUSED")
# ❌ game_hud.visible is false (FSM _set_ui("pause") behavior)
```

**Fix:** Correct the assertion to match the FSM's actual design behavior:
```gdscript
_assert(mocks.game_hud.visible == false, "TC1.3: game_hud hidden in PAUSED (FSM _set_ui design)")
# ✅ game_hud.visible is false → PASS
```

The ball mock stays as `Area2D.new()` — this is the correct type matching `@onready var ball: Area2D`.

## 3. Fix Inventory

| # | Test | File:Line (HEAD) | Fix | Lines Changed |
|---|------|-----------------|-----|:---:|
| 1 | TC5-5 | `mini-pong/tests/test_ui_system.gd:186` | `title.get_theme_font_size("font_size")` → `title.font_size` | 1 |
| 2 | TC5-8 | `mini-pong/tests/test_ui_system.gd:193` | `prompt.get_theme_font_size("font_size")` → `prompt.font_size` | 1 |
| 3 | TC6-4 | `mini-pong/tests/test_ui_system.gd:213` | `player_lbl.get_theme_font_size("font_size")` → `player_lbl.font_size` | 1 |
| 4 | TC6-7 | `mini-pong/tests/test_ui_system.gd:219` | `ai_lbl.get_theme_font_size("font_size")` → `ai_lbl.font_size` | 1 |
| 5 | TC7-4 | `mini-pong/tests/test_ui_system.gd:239` | `winner_lbl.get_theme_font_size("font_size")` → `winner_lbl.font_size` | 1 |
| 6 | TC7-7 | `mini-pong/tests/test_ui_system.gd:245` | `restart_lbl.get_theme_font_size("font_size")` → `restart_lbl.font_size` | 1 |
| 7 | TC1.3 | `mini-pong/tests/test_pause.gd:199` | `mocks.game_hud.visible == true` → `mocks.game_hud.visible == false` | 1 |

**Total: 7 lines changed across 2 files. Zero production code touched.**

Line numbers verified against HEAD (`main`, fset:4e5321c5) — they match the PRD's line numbers.

## 4. Verification

### Test commands

```bash
cd /Users/devvi/workspace/agent-game-test

# Baseline (before fix)
godot --path mini-pong/ --headless --script tests/run_tests.gd
# Expected: 895 passed, 7 failed

# After fix
godot --path mini-pong/ --headless --script tests/run_tests.gd
# Expected: 902 passed, 0 failed

# Compile check
godot --path mini-pong/ --headless --quit
# Expected: exit code 0
```

### Acceptance criteria

- [ ] TC5-5: `title.font_size >= 48` passes (`.tscn` has font_size=64)
- [ ] TC5-8: `prompt.font_size >= 24` passes (`.tscn` has font_size=28)
- [ ] TC6-4: `player_lbl.font_size >= 24` passes (`.tscn` has font_size=28)
- [ ] TC6-7: `ai_lbl.font_size >= 24` passes (`.tscn` has font_size=28)
- [ ] TC7-4: `winner_lbl.font_size >= 48` passes (`.tscn` has font_size=72)
- [ ] TC7-7: `restart_lbl.font_size >= 24` passes (`.tscn` has font_size=28)
- [ ] TC1.3: `game_hud.visible == false` passes (FSM `_set_ui("pause")` hides HUD)
- [ ] All 895 previously-passing tests still pass (902 passed, 0 failed)
- [ ] Production code (`game_state_machine.gd`, UI scripts, `.tscn` files) unchanged
- [ ] `godot --headless --quit` exits cleanly (no parse errors)

## 5. Out of Scope

| Deferred item | Reason |
|--------------|--------|
| Confirm Pause UX design intent (should game_hud be visible during pause?) | P3 — separate UX decision; current FSM behavior is explicit and consistent |
| Migrate `.tscn` `font_size` to `theme_override_font_sizes/font_size` format | P4 — Godot 4 recommended format, but current format works correctly with `Label.font_size` |
| Add headless font_size API guidance to test documentation | P4 — useful for future test authors to avoid `get_theme_font_size()` in headless |
| Modify production code (FSM, UI scripts, scenes) | Not in scope — this is a test maintenance task |
| Re-run first-round fixes from #340 | Already done and verified; this round addresses only the 7 new failures from commit `284e056` |
