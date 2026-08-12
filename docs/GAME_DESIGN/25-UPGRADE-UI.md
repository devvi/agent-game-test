# Upgrade Pick UI — 波间 3 选 1 升级选择层

> Reference: ../DESIGN/388-upgrade-pick-ui.md · PRD ../PRD/388-upgrade-pick-ui.md
> Merged: #440 (2026-08-13) · Issue #388

## Overview

The **Upgrade Pick UI** is the player-facing 3-choice upgrade layer of PONG://NEON's
rogue-lite loop — the missing interaction link between wave settlement (#386) and the
upgrade pool (#387). On `GameManager.wave_settled` it opens a three-card neon selection
layer, lets the player cycle focus with `ui_left`/`ui_right`, confirms with `ui_accept`,
reveals the rarity *after* confirmation (PLAN-rogue-pong §2.5 surprise moment), then
resumes the game and explicitly advances the wave.

Ownership: `content_ownership: mechanical` (interaction mechanics; rarity **colors** and
card **copy** belong to taste domain #395 — this layer consumes `display` read-only with
working-name fallback).

## Architecture

```
GameManager.wave_settled(wave_index)          # #386 hook (autoload signal)
        │
        ▼
UpgradePickUI (CanvasLayer, layer=2, process_mode=ALWAYS, ui_upgrade_pick.tscn)
├── open(wave_index)
│     ├─ UpgradePool.get_candidates(3)        # AC5 sole source (#387)
│     ├─ get_tree().paused = true             # AC4 freeze game time
│     └─ WaveController.settle_hold = true    # take over advance timing
├── _unhandled_input → ui_left/right/accept   # manual focus ring (no Control focus)
├── _confirm → UpgradePool.apply(id) → _start_reveal()
│     ├─ true  → REVEALING: border → rarity color + RarityLabel + hold 0.8s → close()
│     └─ false → keep open + push_warning
└── close()
      ├─ visible=false, get_tree().paused = false   # AC4 resume
      └─ WaveController.advance_settlement() → next wave
```

## Key Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `get_tree().paused` (tree-level) + UI `PROCESS_MODE_ALWAYS` | Freezes all PAUSABLE logic (ball/paddle/FSM/rain); `process_mode` gates `_input`/`_unhandled_input` so FSM's Escape handling is naturally suppressed while open |
| 2 | Explicit `settle_hold`/`advance_settlement()` takeover | `SceneTreeTimer` defaults to `process_always=true` — pause alone cannot stop WaveController's auto-advance; hold flag is explicit and defaults `false` (zero regression on #386) |
| 3 | Rarity revealed **after** confirmation (REVEALING state) | PLAN §2.5 surprise moment — cards are neutral neon before confirm (AC3), then border switches to rarity color + name |
| 4 | Manual focus state machine (`_focus_index` + `posmod`) | No Control `grab_focus` dependency — headless-testable, works in pause |
| 5 | Group `wave_controllers` + `has_method`/`"in"` guards | #393 assembly not yet live → UI works standalone, takeover calls no-op safely |

## CanvasLayer Stack

| Layer | Node | Notes |
|:-----:|------|-------|
| 0 | AtmosphereLayer (RainCurtain) | |
| 1 | StartMenu / GameHUD / GameOverScreen | |
| **2** | **UpgradePickUI** | above HUD, below PauseOverlay; mutually exclusive with PauseOverlay (FSM suppressed under tree pause) |
| 10 | PauseOverlay | |

## 状态机

```
CLOSED ──open(wave_index)──▶ SELECTING ──ui_accept + apply==true──▶ REVEALING
  ▲                            │  ▲                                  │
  └────────close()─────────────┘  └── apply==false: stay open ───────┘
REVEALING: input locked; after UPGRADE_UI_REVEAL_HOLD (0.8s) → close()
```

## Test Anchor

`tests/test_upgrade_pick_ui.gd` (139 assertions, Scenarios A–H per DESIGN §9):
real autoloads + mini tree (scene instance + real WaveController + mock BreakoutGrid),
`UpgradePool.rng.seed()` determinism, `Input.parse_input_event()` action feeding,
`_reveal_hold` injection for short waits. Regression: `test_wave_cycle.gd` 61/61 green
with default `settle_hold=false`.
