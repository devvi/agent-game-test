# Design: Fix 7 Pre-Existing Test Failures on Main (Round 2)

> **Parent Issue:** #346
> **Agent:** game-plan-agent
> **Date:** 2026-07-30
> **Approach:** A — Test-only fixes; no production code changes (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── tests/
│   ├── test_ui_system.gd     ← MODIFIED: 6x get_theme_font_size → font_size
│   └── test_pause.gd         ← MODIFIED: TC1.3 game_hud.visible assertion
└── gdscripts/
    └── game_state_machine.gd ← UNCHANGED (production code)
```

**Design philosophy:** This is a pure test maintenance task — round two of pre-existing test failure cleanup. These 7 failures were introduced by commit `284e056` (the fix for #340 round one). That commit made two mistakes: (1) replaced `label.font_size` with `label.get_theme_font_size("font_size")` in 6 UI assertions, and (2) changed the ball mock type from `Node2D` to `Area2D`, exposing a pre-existing assertion bug in TC1.3. The fix reverts the wrong API choice and corrects the Pause assertion to match FSM design behavior. Zero production code changes.

### Key Architectural Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | font_size API | Use `label.font_size` (theme override property), not `get_theme_font_size()` | `.tscn` `font_size = N` sets a **theme override**, accessed via `Label.font_size` property. `get_theme_font_size()` walks the theme resource chain and returns 0 in headless (no theme loaded). |
| 2 | TC1.3 fix | Assert `game_hud.visible == false` | FSM `_set_ui("pause")` explicitly sets `game_hud.visible = false` (game_state_machine.gd). The test must reflect FSM's actual design behavior, not a wrong expectation. |
| 3 | ball mock type | Keep `Area2D.new()` | FSM declares `@onready var ball: Area2D`. `Area2D` is the type-correct mock. The old `Node2D` mock passed only because Godot silently coerced the type mismatch. |
| 4 | No production code changes | Zero changes to `.tscn` files, `.gd` scripts, or CI config | Per PRD scope: test maintenance only. |
| 5 | No TASKS doc needed | depth/standard — only 2 files, 7 lines changed | Per plan agent conventions, standardized tasks are unnecessary for a simple assertion fix across two files. |

---

## 2. Test-by-Test Fix Details

### 2.1 Root Cause: `get_theme_font_size()` vs `font_size`

In Godot 4.x, `.tscn` files set theme overrides via direct properties:

```tscn
[node name="TitleLabel" type="Label" parent="."]
font_size = 64
```

This is **not** the theme default — it''s a **theme override**. The correct accessor is `Label.font_size`. `get_theme_font_size("font_size")` reads from the theme resource chain (default → override), but in headless mode no theme is loaded, so it returns 0.

**Data flow (broken → fixed):**

```
.tscn font_size=64
    │
    ▼
Label.instantiate()
    │
    ├── get_theme_font_size("font_size") → 0  ❌ (theme default, no theme)
    │
    └── font_size → 64  ✅ (theme override property)
```

### 2.2 TC5-5 & TC5-8 — Start Menu Labels

**File:** `mini-pong/tests/test_ui_system.gd`

**Scene:** `scenes/ui_start_menu.tscn`

| Test | Node | tscn font_size | Current (broken) | Fixed |
|------|------|:---:|------|------|
| TC5-5 | TitleLabel | 64 | `title.get_theme_font_size("font_size") >= 48` | `title.font_size >= 48` |
| TC5-8 | PromptLabel | 28 | `prompt.get_theme_font_size("font_size") >= 24` | `prompt.font_size >= 24` |

```diff
- _assert(title.get_theme_font_size("font_size") >= 48, "TC5-5: TitleLabel font_size >= 48")
+ _assert(title.font_size >= 48, "TC5-5: TitleLabel font_size >= 48")

- _assert(prompt.get_theme_font_size("font_size") >= 24, "TC5-8: PromptLabel font_size >= 24")
+ _assert(prompt.font_size >= 24, "TC5-8: PromptLabel font_size >= 24")
```

---

### 2.3 TC6-4 & TC6-7 — Game HUD Labels

**File:** `mini-pong/tests/test_ui_system.gd`

**Scene:** `scenes/ui_game_hud.tscn`

| Test | Node | tscn font_size | Current (broken) | Fixed |
|------|------|:---:|------|------|
| TC6-4 | PlayerScoreLabel | 28 | `player_lbl.get_theme_font_size("font_size") >= 24` | `player_lbl.font_size >= 24` |
| TC6-7 | AIScoreLabel | 28 | `ai_lbl.get_theme_font_size("font_size") >= 24` | `ai_lbl.font_size >= 24` |

```diff
- _assert(player_lbl.get_theme_font_size("font_size") >= 24, "TC6-4: PlayerScoreLabel font_size >= 24")
+ _assert(player_lbl.font_size >= 24, "TC6-4: PlayerScoreLabel font_size >= 24")

- _assert(ai_lbl.get_theme_font_size("font_size") >= 24, "TC6-7: AIScoreLabel font_size >= 24")
+ _assert(ai_lbl.font_size >= 24, "TC6-7: AIScoreLabel font_size >= 24")
```

---

### 2.4 TC7-4 & TC7-7 — Game Over Labels

**File:** `mini-pong/tests/test_ui_system.gd`

**Scene:** `scenes/ui_game_over.tscn`

| Test | Node | tscn font_size | Current (broken) | Fixed |
|------|------|:---:|------|------|
| TC7-4 | WinnerLabel | 72 | `winner_lbl.get_theme_font_size("font_size") >= 48` | `winner_lbl.font_size >= 48` |
| TC7-7 | RestartPromptLabel | 28 | `restart_lbl.get_theme_font_size("font_size") >= 24` | `restart_lbl.font_size >= 24` |

```diff
- _assert(winner_lbl.get_theme_font_size("font_size") >= 48, "TC7-4: WinnerLabel font_size >= 48")
+ _assert(winner_lbl.font_size >= 48, "TC7-4: WinnerLabel font_size >= 48")

- _assert(restart_lbl.get_theme_font_size("font_size") >= 24, "TC7-7: RestartPromptLabel font_size >= 24")
+ _assert(restart_lbl.font_size >= 24, "TC7-7: RestartPromptLabel font_size >= 24")
```

---

### 2.5 TC1.3 — Pause: game_hud Visibility

**File:** `mini-pong/tests/test_pause.gd`

**Root cause:** Commit `284e056` changed the ball mock from `Node2D.new()` to `Area2D.new()` (L103). With `Node2D`, the type mismatch likely caused ball to be set to null, masking the assertion bug. With `Area2D` (correct type), FSM''s `enter_state(PAUSED)` runs properly and calls `_set_ui("pause")`, which explicitly sets `game_hud.visible = false`.

**FSM production behavior (game_state_machine.gd):**

```gdscript
func _set_ui(layer: String) -> void:
    game_hud.visible = (layer == "hud")  # "pause" != "hud" → false
    pause_overlay.visible = (layer == "pause")
    game_over_overlay.visible = (layer == "game_over")
```

**Fix:**

```diff
- _assert(mocks.game_hud.visible == true, "TC1.3: game_hud still visible in PAUSED")
+ _assert(mocks.game_hud.visible == false, "TC1.3: game_hud hidden in PAUSED (FSM _set_ui(\"pause\") hides HUD)")
```

**Why this is correct:** FSM''s design intent is to show only the pause overlay during PAUSED state, not the game HUD. The test now correctly validates this design.


---

## 3. Summary of Changes

| File | Line | Change | Test |
|------|------|--------|------|
| `tests/test_ui_system.gd` | L186 | `title.get_theme_font_size("font_size")` → `title.font_size` | TC5-5 |
| `tests/test_ui_system.gd` | L193 | `prompt.get_theme_font_size("font_size")` → `prompt.font_size` | TC5-8 |
| `tests/test_ui_system.gd` | L213 | `player_lbl.get_theme_font_size("font_size")` → `player_lbl.font_size` | TC6-4 |
| `tests/test_ui_system.gd` | L219 | `ai_lbl.get_theme_font_size("font_size")` → `ai_lbl.font_size` | TC6-7 |
| `tests/test_ui_system.gd` | L239 | `winner_lbl.get_theme_font_size("font_size")` → `winner_lbl.font_size` | TC7-4 |
| `tests/test_ui_system.gd` | L245 | `restart_lbl.get_theme_font_size("font_size")` → `restart_lbl.font_size` | TC7-7 |
| `tests/test_pause.gd` | L199 | `game_hud.visible == true` → `game_hud.visible == false` | TC1.3 |

**Total: 7 lines changed across 2 files. Zero production code touched.**

---

## 4. Verification

### Test commands

```bash
# Compile check (fast — catches parse errors)
cd mini-pong/
godot --headless --quit

# Full test suite
godot --path mini-pong/ --headless --script tests/run_tests.gd
# Expected: 902 passed, 0 failed
```

### Acceptance criteria

- [ ] TC5-5: `title.font_size >= 48` passes (tscn value: 64)
- [ ] TC5-8: `prompt.font_size >= 24` passes (tscn value: 28)
- [ ] TC6-4: `player_lbl.font_size >= 24` passes (tscn value: 28)
- [ ] TC6-7: `ai_lbl.font_size >= 24` passes (tscn value: 28)
- [ ] TC7-4: `winner_lbl.font_size >= 48` passes (tscn value: 72)
- [ ] TC7-7: `restart_lbl.font_size >= 24` passes (tscn value: 28)
- [ ] TC1.3: `game_hud.visible == false` passes (FSM hides HUD during PAUSED)
- [ ] All 895 previously-passing tests still pass
- [ ] Production code unchanged (`.tscn` files, `.gd` scripts, CI config)
- [ ] Compile check passes (`godot --headless --quit` exit code 0)

---

## 5. Edge Cases & Pitfalls

1. **font_size API consistency**: All 6 labels in the three `.tscn` files use `font_size = N` (theme override format). The fix is uniformly `get_theme_font_size("font_size")` → `font_size`. No mixed access patterns remain.

2. **TC1.3 assertion change is semantically correct**: The original assertion `game_hud.visible == true` was always wrong — FSM''s `_set_ui("pause")` has always set `game_hud.visible = false`. The old test passed only by accident (ball mock type mismatch).

3. **Other Pause assertions unaffected**: TC1.1 (`current_state == PAUSED`), TC1.2 (`pause_overlay.visible == true`), TC1.4 (`player_paddle.frozen`), TC1.5 (`ai_paddle.frozen`) are all unchanged.

4. **Other UI assertions unaffected**: text content, horizontal_alignment, layer visibility checks remain unchanged. Only font_size assertions change.

5. **Scene files NOT modified**: The `.tscn` files'' `font_size = N` properties are correct as-is. No migration to `theme_override_font_sizes/font_size` format is in scope for this fix.

6. **Thread safety / timing**: No async/await changes. All assertions are synchronous property reads.
