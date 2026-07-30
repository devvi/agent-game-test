# Pause System — Escape Toggle & Overlay

> Reference: ../DESIGN/296-pause-and-sound.md
> Parent Issue: #296

## Overview

The pause system extends Mini Pong's GameStateMachine with a 6th `PAUSED` state, toggled
via the Escape key (`ui_cancel`). In the PAUSED state, gameplay freezes (paddles,
ball), a semi-transparent pause overlay appears with a "暂停" label, and audio
synthesis pauses. Pressing Escape again resumes gameplay from the PLAYING state.

## State Diagram (Extended)

```
MENU ──(SPACE)──→ SERVING ──(auto)──→ PLAYING ⇌(Escape)⇌ PAUSED
  ↑                  ↑                   │
  │                  │          [scored] │
  │                  │                   ▼
  │                  │        SCORED ──(1s)──┐
  │                  │          │            │
  │                  │ [no win]─┘   [winner]─┘
  │                  │                       ▼
  │                  └─────────── GAME_OVER ──(SPACE)──┘
```

## PAUSED State

| Property | Value |
|----------|-------|
| Entry trigger | `ui_cancel` (Escape) pressed in PLAYING state |
| Exit trigger | `ui_cancel` (Escape) pressed in PAUSED state |
| UI layer | PauseOverlay (visible) + HUD (hidden via _set_ui) |
| Paddles | `set_frozen(true)` |
| Ball | `_process` returns early (delta guard: `_is_serving` or delta ≤ 0) |
| Audio | `AudioEngine.pause_stream()` — pauses AudioStreamGenerator |
| Scoring | `_on_scored()` rejects in non-PLAYING state — ignored |

### Escape Input Routing

The FSM's `_input()` method handles `ui_cancel` with a `match current_state`:

```
State.PLAYING → transition_to(State.PAUSED)
State.PAUSED  → transition_to(State.PLAYING)
_             → no-op (MENU, SERVING, SCORED, GAME_OVER)
```

The event is consumed (`return`) after processing to prevent fall-through.

## PauseOverlay

A CanvasLayer with two children:
- **ColorRect**: Full-screen semi-transparent black mask (`color = Color(0, 0, 0, 0.5)`)
- **Label**: "暂停" text, centered, white color

### Script: `pause_overlay.gd`

```gdscript
extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label

func _ready() -> void:
    hide()  # hidden by default, shown via FSM

func show_overlay() -> void:
    visible = true

func hide_overlay() -> void:
    visible = false
```

Follows the same CanvasLayer + ColorRect + Label pattern established by
StartMenu and GameOverScreen (#292).

## Integration Points

| Component | How PAUSED Affects It |
|-----------|----------------------|
| `game_state_machine.gd` | New `PAUSED` enum member, Escape input handling in `_input()`, PAUSED entry/exit in `enter_state()` |
| `pause_overlay.gd` | New CanvasLayer script, shown/hidden by FSM |
| `ball.gd` | Already handles delta ≤ 0 guard (freezes during pause) |
| `paddle.gd` | `set_frozen(true)` — blocks input processing |
| `audio_engine.gd` | `pause_stream()` / `resume_stream()` called by FSM |
| `scoring_manager.gd` | `_on_scored()` rejects non-PLAYING state |
| `game.tscn` | New PauseOverlay CanvasLayer node with ext_resource + ColorRect + Label |

## Test Coverage

| Test | Description |
|------|-------------|
| TC1 | Escape in PLAYING → PAUSED, overlay visible, paddles frozen |
| TC2 | Escape in PAUSED → PLAYING, overlay hidden, paddles unfrozen |
| TC3 | Escape in MENU → no effect |
| TC4 | Escape in GAME_OVER → no effect |
| TC5 | Ball position unchanged during PAUSED |
| TC6 | Paddles frozen during PAUSED |
| TC7 | `_on_scored()` ignored during PAUSED |

Test file: `mini-pong/tests/test_pause.gd` (327 lines, 7 tests, 8 assertions)
