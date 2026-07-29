# Game State Machine — Runtime Orchestration

> Reference: ../DESIGN/294-game-state-machine.md
> Parent Issue: #294

## Overview

The GameStateMachine is a **scene-level Node** (not an autoload) that centralizes all
runtime state orchestration in Mini Pong. Before #294, state transitions were scattered
across `start_menu.gd`, `scoring_manager.gd`, and `game_over_screen.gd` — each handling
its own input and UI visibility. The FSM consolidates these into a single 5-state machine.

## State Diagram

```
MENU ──(SPACE)──→ SERVING ──(auto)──→ PLAYING ──(scored)──→ SCORED
  ↑                  ↑                                      │
  │                  │                              ┌───────┴────────┐
  │                  │                         no winner         winner
  │                  │                              │                │
  │                  └──────────────────────────────┘                │
  │                                                                  ↓
  └──────────────────(SPACE)─────────────────────── GAME_OVER
```

## States

| State | Entry Actions | Input | UI Layer | Paddles |
|-------|--------------|-------|----------|---------|
| `MENU` | Show start menu, lock transition | SPACE → SERVING | start_menu | frozen |
| `SERVING` | Show HUD, reset match, serve ball after 1s delay | none (auto-advances) | hud | frozen |
| `PLAYING` | Show HUD, unfreeze paddles | none (scored signal) | hud | unfrozen |
| `SCORED` | Show HUD, 1s pause, check winner | none (auto-advances) | hud | frozen |
| `GAME_OVER` | Show game over screen, unlock transition | SPACE → MENU | game_over | frozen |

## Signal Integration

| Source | Signal | FSM Handler | Effect |
|--------|--------|------------|--------|
| ScoringManager | `scored(winner)` | `_on_scored()` | PLAYING → SCORED |
| GameManager | `match_over(winner)` | `_on_match_over()` | Any → GAME_OVER |

## Subsystem Control

### Input Routing
- FSM's `_input()` handles `ui_accept` in `MENU` and `GAME_OVER` states only.
- `start_menu.gd` and `game_over_screen.gd` no longer handle input directly.
- `ui_accept` is Godot's built-in action (Space/Enter).

### Paddle Freeze
- `paddle.gd` exposes `set_frozen(bool)` — guards `_process()` movement.
- FSM calls `set_frozen(true)` in MENU, SERVING, SCORED, GAME_OVER.
- FSM calls `set_frozen(false)` in PLAYING.

### UI Visibility
- FSM's `_set_ui(layer)` toggles `visible` on CanvasLayer siblings.
- Layers: StartMenu, GameHUD, GameOverScreen.

### Serve Timing
- SERVING state: await 1s timer → `ball.serve()` → await serve animation → auto-advance to PLAYING.
- In headless mode, timers are skipped (synchronous advancement).

## Transition Lock

`_transition_lock` prevents double-trigger of SPACE in MENU/GAME_OVER:
- Set `true` when SPACE is pressed.
- Reset `false` when the target state's `enter_state()` runs.

## Architecture

```
game.tscn
├── GameStateMachine (Node)  ← NEW
│   ├── start_menu → NodePath("../StartMenu")
│   ├── game_hud → NodePath("../GameHUD")
│   ├── game_over_screen → NodePath("../GameOverScreen")
│   ├── ball → NodePath("../Ball")
│   ├── player_paddle → NodePath("../PlayerPaddle")
│   ├── ai_paddle → NodePath("../AIPaddle")
│   └── scoring_manager → NodePath("../ScoringManager")
├── StartMenu (CanvasLayer)
├── GameHUD (CanvasLayer)
├── GameOverScreen (CanvasLayer)
├── Ball (Area2D)
├── PlayerPaddle (Area2D)
├── AIPaddle (Area2D)
└── ScoringManager (Node)
```

## Key Design Decisions

- **Not an autoload:** Lives in `game.tscn` alongside the nodes it orchestrates, consistent with ScoringManager and ScoreFlash.
- **`@onready` node references with `NodePath` exports:** Set in `game.tscn`, validated at `_ready()` with null warnings. No runtime `get_node()`.
- **`Engine.get_singleton("GameManager")`:** Uses runtime singleton lookup instead of compile-time `class_name` reference — compatible with headless `--script` tests.
- **`await`-based timers:** Same pattern already proven in `scoring_manager.gd`. Timers are skipped in headless mode.

## Test Coverage

| Test | What It Verifies |
|------|-----------------|
| TC2 | FSM instantiation, enum values, methods exist |
| TC3 | enter_state(MENU) — UI visibility, paddle freeze |
| TC4 | enter_state(PLAYING) — UI visibility, paddle unfreeze |
| TC5 | enter_state(GAME_OVER) — UI visibility, paddle freeze |
| TC6 | scored signal → SCORED → GAME_OVER (winner exists) |
| TC7 | scored signal in non-PLAYING → ignored |
| TC8 | double SPACE transition lock + ignored in PLAYING |
| TC9 | match_over during SCORED → cancel timer |
| TC10 | duplicate match_over ignored |
| TC11 | transition_to same state → no-op |
| TC12-13 | UI visibility for each state |
| TC14-15 | Paddle freeze state for each state |
| TC16 | reset_match called on SERVING enter |
| TC17 | null node references handled without crash |
