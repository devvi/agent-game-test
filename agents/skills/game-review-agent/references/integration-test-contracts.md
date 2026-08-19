# Godot Integration Test Contracts

> Part of `game-review-agent` references. Documents the three integration test
> patterns developed from the #289 neon wiring session (2026-07-30) that catch
> cross-component bugs static tests miss.

## Why Integration Tests

Static tests (node existence, property checks, script compilation) all pass even
when runtime interactions are completely broken. The three bugs found in the #289
session are archetypical:

| Bug | Static Test | Integration Test |
|-----|:-----------:|:----------------:|
| ScoreZone `body_entered` for Area2D ball | ✅ node exists, is Area2D | ❌ signal never fires |
| ScoreZone `collision_mask=1` vs ball layer 4 | ✅ shape exists, non-null | ❌ collision incompatible |
| FSM `reset_match()` on every serve | ✅ unit test isolates ScoringManager | ❌ games_won wiped each serve |

## Pattern 1: Collision Contract (`area_entered` + `collision_mask`)

**What it catches:**
- `body_entered` vs `area_entered` mismatch (Area2D balls need `area_entered`)
- `collision_layer` / `collision_mask` bitmask incompatibility

**Template:**
```gdscript
func _test_collision_contract() -> void:
    var scene = load("res://scenes/Main.tscn").instantiate()
    var detector = scene.get_node("ScoreZoneLeft")  # Area2D trigger
    var target = scene.get_node("Ball")             # Area2D that should trigger it

    # 1. Signal type: area_entered for Area2D↔Area2D
    var src = FileAccess.get_file_as_string("res://gdscripts/ball.gd")
    _assert(src.contains("area_entered.connect"),
        "ScoreZone detection uses area_entered (not body_entered)")

    # 2. Collision mask compatibility (bidirectional)
    _assert(detector.collision_mask & target.collision_layer != 0,
        "Detector mask includes target's layer")
    _assert(target.collision_mask & detector.collision_layer != 0,
        "Target mask includes detector's layer")

    scene.queue_free()
```

**When to add:** Every time a PR adds/modifies an Area2D that detects another
Area2D entering it. This is a one-time template — only the node paths change.

## Pattern 2: State Persistence (`autoload` data across transitions)

**What it catches:**
- Autoload data corruption during state machine transitions
- `reset_match()` called when `reset_game()` was intended
- Games-won counters wiped between serves

**Template:**
```gdscript
func _test_state_persistence() -> void:
    GameManager.reset_match()

    # Simulate the full game-winning flow
    for _i in range(5):
        GameManager.add_score("ai")

    _assert(GameManager.ai_games_won == 1,
        "games_won == 1 after 5 scores (game won)")
    _assert(GameManager.ai_score == 0,
        "per-game scores reset after game win")
    _assert(GameManager.get_winner() == "",
        "match not over after 1 game (need N games to win)")

    # Score in the next game — verify games_won still there
    GameManager.add_score("player")
    _assert(GameManager.ai_games_won == 1,
        "games_won persists across game boundary")
```

**When to add:** Every time a PR adds/modifies state machine transitions or
autoload state that must persist across transitions. The test verifies the
contract at the autoload API level — no scene instantiation needed.

## Pattern 3: Signal Chain Integrity

**What it catches:**
- Signals connected to wrong method signatures
- Missing signal connections in the chain (ball → ScoringManager → FSM → HUD)
- Autoloads not registered when signal fires (headless timing)

**Template (lightweight version — Pattern 1+2 cover 80% of bugs):**
```gdscript
# Verify signal exists and has expected parameter count
_assert(ball.has_signal("score"), "Ball has 'score' signal")
_assert(sm.has_signal("scored"), "ScoringManager has 'scored' signal")

# Verify cross-autoload signal connections
var gm_signals = GameManager.score_changed.get_connections()
_assert(gm_signals.size() >= 1, "GameManager.score_changed has listeners")
```

Full end-to-end signal chain tests (ball→ScoreZone→manager→FSM→UI) require
physics simulation and are covered by the existing `auto_play_test.gd` (100
AI-vs-AI matches). Add contract assertions to that test for the specific signal
paths being changed.

## When to Write Each

| PR Type | Pattern 1 | Pattern 2 | Pattern 3 |
|---------|:---------:|:---------:|:---------:|
| New Area2D that detects another Area2D | **Required** | — | Optional |
| State machine transition changes | — | **Required** | Optional |
| Signal wiring changes | Optional | Optional | **Required** |
| Scene layout / asset-only | — | — | — |
| Compile fix / migration | — | — | — |

## Verification

```bash
# These tests run as part of the full suite:
godot --path mini-pong/ --headless --script tests/run_tests.gd
# Look for: "Main Scene Assembly" (Pattern 1), "FSM Integration" (Pattern 2)
```
