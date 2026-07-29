# UI System — Menus, HUD, and Game Over

> Reference: ../DESIGN/292-ui-system.md
> Parent Issue: #292

## Overview

The UI system provides three CanvasLayer scenes that form the complete display layer for Mini Pong:
- **StartMenu** — Neon title screen with pulsing glow and SPACE-to-start prompt
- **GameHUD** — Top-center score display for player and AI
- **GameOverScreen** — Winner announcement with SPACE-to-restart

Layers consume signals from the `GameManager` autoload and use the neon color palette from #289.

## Architecture

Three independent CanvasLayer nodes embedded in `game.tscn`, each driven by its own GDScript:

| Layer | Scene File | Script | Layer | Initial Visible |
|-------|-----------|--------|-------|----------------|
| StartMenu | `ui_start_menu.tscn` | `start_menu.gd` | 1 | true |
| GameHUD | `ui_game_hud.tscn` | `game_hud.gd` | 0 | false |
| GameOverScreen | `ui_game_over.tscn` | `game_over_screen.gd` | 1 | false |

Only one CanvasLayer is visible at any time. Transitions are driven by SPACE key input and `GameManager` signals.

## State Transitions

```
StartMenu  ──SPACE──►  GameHUD  ──match_over──►  GameOverScreen
     ▲                                                │
     └──────────── SPACE ────────────────────────────┘
```

## Signal Wiring

| Connection | Source | Target | When |
|-----------|--------|--------|------|
| `score_changed(p, a)` → label update | GameManager | game_hud.gd | On `_ready()` |
| `match_over(winner)` → winner display | GameManager | game_over_screen.gd | On `_ready()` |
| `scored.emit()` → `GameManager.add_score()` | ScoringManager | GameManager | On ball score |

The critical bridge is a 1-line addition in `scoring_manager.gd:_on_ball_score()`:
```gdscript
GameManager.add_score(winner)
```
Without this, GameManager signals never fire and the HUD never updates.

## Scene Design

### StartMenu

- **TitleLabel**: "Mini Pong" at 64px, centered, neon blue (#4a90d9)
- **PromptLabel**: "按 SPACE 开始" at 28px, centered, blue at 70% alpha
- **Animation**: Title alpha pulses between 0.6–1.0 (1.5s cycle), prompt blinks (0.8s cycle)
- **Input**: SPACE key triggers `_on_start_pressed()` → hides menu, shows HUD, calls `GameManager.reset_match()`

### GameHUD

- **PlayerScoreLabel**: "Player: {n}" at 28px, neon blue, centered in HBox
- **AIScoreLabel**: "AI: {n}" at 28px, neon red (#ff3355), centered in HBox
- **Position**: Anchored to top of screen with 20px margin, 40px horizontal padding
- **Update**: `_on_score_changed()` connected to `GameManager.score_changed` signal

### GameOverScreen

- **WinnerLabel**: "YOU WIN!" or "AI WINS!" at 72px, dynamically colored (blue/red)
- **RestartPromptLabel**: "按 SPACE 重新开始" at 28px with alpha-pulse animation
- **Animation**: Winner text pulses (1.0s cycle), prompt blinks (0.8s cycle)
- **Input**: SPACE key triggers restart → returns to StartMenu, calls `GameManager.reset_match()`

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Signal source for HUD | GameManager (not ScoringManager) | Autoload available everywhere |
| Glow effect | Tween modulate alpha | No ShaderMaterial needed |
| Font | Godot system_font | Readable at 24px+ without custom font |
| Debounce | `_transitioning` bool flag | Prevents double-trigger on rapid SPACE |
| Headless safety | `if get_tree():` guard | CI validation without crash |
| Sibling references | `get_parent().get_node_or_null()` | No exported NodePath vars |

## Edge Cases

| # | Case | Mitigation |
|---|------|------------|
| 1 | Headless mode: `get_tree()` returns null | All scripts guard with `if get_tree():` before creating tweens |
| 2 | GameManager autoload missing | `_ready()` checks `is_instance_valid(GameManager)` before connecting |
| 3 | Initial state — no signals emitted yet | HUD seeds labels from `GameManager.player_score` / `ai_score` |
| 4 | Rapid SPACE double-press | `_transitioning` bool prevents second trigger |
| 5 | Signal while layer invisible | `_on_score_changed()` updates text unconditionally |
| 6 | Font missing | Godot falls back to system_font |
| 7 | Sibling CanvasLayer not found | `get_node_or_null()` returns null safely |
| 8 | Tween conflict | `_kill_tween()` called before creating new animation |
| 9 | Invalid winner string | `match` falls through without action |

## Files

| File | Role |
|------|------|
| `gdscripts/start_menu.gd` | StartMenu controller (107 lines) |
| `gdscripts/game_hud.gd` | HUD score display (34 lines) |
| `gdscripts/game_over_screen.gd` | Game over screen controller (126 lines) |
| `scenes/ui_start_menu.tscn` | StartMenu scene |
| `scenes/ui_game_hud.tscn` | GameHUD scene |
| `scenes/ui_game_over.tscn` | GameOverScreen scene |
| `scenes/game.tscn` | Modified: 3 CanvasLayer instances added |
| `gdscripts/scoring_manager.gd` | Modified: 1-line bridge to GameManager |
| `tests/test_ui_system.gd` | 26 test cases (451 lines) |

## Dependencies

All dependencies are closed:
- #301 (Scaffold) — directory structure
- #291 (Scoring) — signals emit
- #293 (GameManager) — autoload registered
- #289 (Neon Visual) — color constants defined
