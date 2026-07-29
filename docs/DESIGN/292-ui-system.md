# DESIGN: [Feature] UI System — Menus / Scoring / End Screen

> **Issue:** #292
> **Parent PRD:** docs/PRD/292-ui-system.md
> **Agent:** game-plan-agent
> **Date:** 2026-07-30
> **Depth:** standard (sections 1–10 + appendices)
> **Approach:** A — Three independent CanvasLayer scenes with signal wiring

---

## 1. Overview

### 1.1 Purpose

Build the display layer for Mini Pong — three CanvasLayer scenes (StartMenu, GameHUD, GameOverScreen) that consume signals from the existing GameManager autoload (#293) and ScoringManager (#291), using the neon color palette from #289. The game currently has all infrastructure (ball physics, paddles, scoring signals) but no visible UI — game starts directly into gameplay with no score display or menus.

### 1.2 Current Architecture (pre-#292)

```
game.tscn (Node2D root)
├── TopWall / BottomWall (StaticBody2D)
├── Ball (Area2D)
├── PlayerPaddle / AIPaddle (CharacterBody2D)
└── ScoringManager (Node)
       └── signal scored → score_flash._on_score_changed (wired)
```

**Signals emitted but unconsumed:**
| Signal | Source | Consumers |
|--------|--------|-----------|
| `GameManager.score_changed(player, ai)` | autoload | **none** |
| `GameManager.game_won(winner)` | autoload | **none** |
| `GameManager.match_over(winner)` | autoload | **none** |
| `ScoringManager.scored(winner)` | game.tscn node | `score_flash._on_score_changed` |
| `ScoringManager.game_won(winner)` | game.tscn node | **none** |
| `ScoringManager.match_over(winner)` | game.tscn node | **none** |

### 1.3 Target Architecture (post-#292)

```
game.tscn (Node2D root)
├── TopWall / BottomWall
├── Ball
├── PlayerPaddle / AIPaddle
├── ScoringManager
├── StartMenu (CanvasLayer)          ← NEW: visible=true initially
│   └── Label ("Mini Pong" title)
│   └── Label ("按 SPACE 开始" prompt)
├── GameHUD (CanvasLayer)            ← NEW: visible=false initially
│   └── HBoxContainer
│       ├── Label ("Player: {n}")
│       └── Label ("AI: {n}")
└── GameOverScreen (CanvasLayer)     ← NEW: visible=false initially
    └── Label ("YOU WIN!" / "AI WINS!")
    └── Label ("按 SPACE 重新开始")
```

**Visual hierarchy (Layer):**
- StartMenu: layer 1 (topmost — blocks interaction with game)
- GameHUD: layer 0 (overlay — transparent background)
- GameOverScreen: layer 1 (topmost — blocks interaction)

---

## 2. Architecture

### 2.1 CanvasLayer Switching

Only one CanvasLayer visible at any time. Switching is done in script code via `CanvasLayer.visible` — no `add_child`/`remove_child`, no queue_free.

```
State transitions (driven by SPACE key + signals):

  [StartMenu]  ──SPACE──►  [GameHUD]  ──match_over──►  [GameOverScreen]
       ▲                                                      │
       └────────────── SPACE ────────────────────────────────┘
```

### 2.2 Layer-to-Layer Communication

Layers do not hold direct references to each other. State changes flow through:

1. **SPACE key handling** — each layer's script calls helper methods on its parent (the game.tscn root) that toggle CanvasLayer nodes by name.
2. **GameManager signals** — HUD and GameOverScreen listen to GameManager autoload signals directly via `GameManager.score_changed.connect()`.

This avoids tight coupling: StartMenu doesn't import GameHUD; GameOverScreen doesn't import StartMenu.

### 2.3 Design Decisions Table

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Signal source for HUD | `GameManager.score_changed` (not ScoringManager) | GameManager is autoload, available everywhere. ScoringManager is scene-local and the two systems run in parallel. GameManager signals are cleaner for UI consumption. |
| Signal source for GameOver | `GameManager.match_over` | Same reasoning — autoload, always available |
| Glow effect | `Tween.tween_property(label, "modulate:a", ...)` | No ShaderMaterial needed for UI text. PRD specifies modulate alpha animation. |
| Font | `system_font` (Godot default) | No custom font file required. PRD says font selection is optional. AC5 (readability) met with 24px+ sizing. |
| Debouncing SPACE | `_transitioning` bool flag per script | Prevents double-trigger on rapid key presses. Set true before state change, cleared after 0.3s timer. |
| Headless safety | `if get_tree():` guard before `create_tween()` and `await` calls | Godot `--headless` returns null from `get_tree()`. Guards prevent runtime errors during CI validation. |
| Node references to siblings | `get_parent().get_node("GameHUD")` pattern | Layers reference sibling CanvasLayers by name through shared parent. Cleaner than exported NodePath vars that break on scene re-instancing. |

---

## 3. Scene Design

### 3.1 StartMenu (`res://scenes/ui_start_menu.tscn`)

**Node tree:**
```
StartMenu (CanvasLayer, layer=1, visible=true)
├── CenterContainer (anchors: full_rect)
│   └── VBoxContainer (alignment: CENTER)
│       ├── TitleLabel (Label)
│       │   - text: "Mini Pong"
│       │   - font_size: 64
│       │   - horizontal_alignment: CENTER
│       │   - modulate: Color(0.29, 0.56, 0.85, 1.0)  #4a90d9
│       │   - custom_effects: glow (enabled via project.godot, no per-node shader)
│       │
│       └── PromptLabel (Label)
│           - text: "按 SPACE 开始"
│           - font_size: 28
│           - horizontal_alignment: CENTER
│           - modulate: Color(0.29, 0.56, 0.85, 0.7)  #4a90d9 at 70%
```

**Script:** `res://gdscripts/start_menu.gd`
**Anchor strategy:** CenterContainer anchors to full rect → VBoxContainer centers its children → labels appear centered at mid-screen.

### 3.2 GameHUD (`res://scenes/ui_game_hud.tscn`)

**Node tree:**
```
GameHUD (CanvasLayer, layer=0, visible=false)
├── MarginContainer (anchors: top, margins: top=20, left=40, right=40)
│   └── HBoxContainer (alignment: CENTER, separation: 60)
│       ├── PlayerScoreLabel (Label)
│       │   - text: "Player: 0"
│       │   - font_size: 28
│       │   - horizontal_alignment: CENTER
│       │   - modulate: Color(0.29, 0.56, 0.85, 1.0)  #4a90d9
│       │
│       └── AIScoreLabel (Label)
│           - text: "AI: 0"
│           - font_size: 28
│           - horizontal_alignment: CENTER
│           - modulate: Color(1.0, 0.2, 0.33, 1.0)  #ff3355
```

**Script:** `res://gdscripts/game_hud.gd`
**Anchor strategy:** MarginContainer anchored top with 20px margin → HBoxContainer centered → labels side-by-side at top-center of screen.

### 3.3 GameOverScreen (`res://scenes/ui_game_over.tscn`)

**Node tree:**
```
GameOverScreen (CanvasLayer, layer=1, visible=false)
├── CenterContainer (anchors: full_rect)
│   └── VBoxContainer (alignment: CENTER)
│       ├── WinnerLabel (Label)
│       │   - text: "" (set dynamically: "YOU WIN!" or "AI WINS!")
│       │   - font_size: 72
│       │   - horizontal_alignment: CENTER
│       │   - modulate: set dynamically (blue #4a90d9 or red #ff3355)
│       │
│       ├── Spacer (Control, min_size.y=40)
│       │
│       └── RestartPromptLabel (Label)
│           - text: "按 SPACE 重新开始"
│           - font_size: 28
│           - horizontal_alignment: CENTER
│           - modulate: Color.WHITE with alpha-pulse animation
```

**Script:** `res://gdscripts/game_over_screen.gd`
**Anchor strategy:** Same as StartMenu — CenterContainer → VBoxContainer → center-aligned labels.

---

## 4. Script API Specifications

### 4.1 `start_menu.gd`

```gdscript
extends CanvasLayer
## StartMenu — neon title screen with pulsing glow and SPACE-to-start prompt.
## Parent Issue: #292

# ── Exported ──
@export var title_pulse_min: float = 0.6       # Minimum alpha during pulse
@export var title_pulse_max: float = 1.0       # Maximum alpha during pulse
@export var title_pulse_duration: float = 1.5  # Seconds for one full pulse cycle
@export var prompt_blink_period: float = 0.8   # Seconds for one full blink cycle

# ── Node References ──
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var prompt_label: Label = $CenterContainer/VBoxContainer/PromptLabel

# ── State ──
var _title_tween: Tween = null
var _prompt_tween: Tween = null
var _transitioning: bool = false


# ── Lifecycle ──
func _ready() -> void:
    # Guard: run only if nodes exist
    if not title_label or not prompt_label:
        return
    
    # Start glow/pulse animations (headless-safe)
    if get_tree():
        _start_title_pulse()
        _start_prompt_blink()
    
    visible = true


func _input(event: InputEvent) -> void:
    if not visible or _transitioning:
        return
    if event.is_action_pressed("ui_accept"):  # SPACE key
        _on_start_pressed()


# ── Public ──
func show_menu() -> void:
    """Called by state machine (#294) to re-show the start screen."""
    visible = true
    _transitioning = false
    if get_tree():
        _start_title_pulse()
        _start_prompt_blink()


func hide_menu() -> void:
    """Cleanup animations and hide."""
    _kill_tweens()
    visible = false


# ── Animation ──
func _start_title_pulse() -> void:
    _kill_tween(_title_tween)
    _title_tween = create_tween()
    _title_tween.set_loops()  # infinite
    _title_tween.tween_property(title_label, "modulate:a", title_pulse_min, title_pulse_duration * 0.5)
    _title_tween.tween_property(title_label, "modulate:a", title_pulse_max, title_pulse_duration * 0.5)


func _start_prompt_blink() -> void:
    _kill_tween(_prompt_tween)
    _prompt_tween = create_tween()
    _prompt_tween.set_loops()
    _prompt_tween.tween_property(prompt_label, "modulate:a", 0.0, prompt_blink_period * 0.5)
    _prompt_tween.tween_property(prompt_label, "modulate:a", 1.0, prompt_blink_period * 0.5)


# ── Internal ──
func _on_start_pressed() -> void:
    _transitioning = true
    _kill_tweens()
    visible = false
    
    # Show HUD layer
    var hud := _get_sibling("GameHUD")
    if hud:
        hud.visible = true
    
    # Trigger game start via GameManager
    GameManager.reset_match()


func _get_sibling(node_name: String) -> CanvasLayer:
    """Find a sibling CanvasLayer by name. Returns null if not found."""
    var parent := get_parent()
    if not parent:
        return null
    return parent.get_node_or_null(node_name)


func _kill_tween(tween: Tween) -> void:
    if tween and is_instance_valid(tween):
        tween.kill()


func _kill_tweens() -> void:
    _kill_tween(_title_tween)
    _kill_tween(_prompt_tween)
    _title_tween = null
    _prompt_tween = null
```

### 4.2 `game_hud.gd`

```gdscript
extends CanvasLayer
## GameHUD — top-center score display driven by GameManager.score_changed signal.
## Parent Issue: #292

# ── Node References ──
@onready var player_label: Label = $MarginContainer/HBoxContainer/PlayerScoreLabel
@onready var ai_label: Label = $MarginContainer/HBoxContainer/AIScoreLabel


# ── Lifecycle ──
func _ready() -> void:
    # Guard: skip if nodes missing
    if not player_label or not ai_label:
        return
    
    # Connect to GameManager signal
    if is_instance_valid(GameManager):
        # Check signal exists before connecting
        if GameManager.has_signal("score_changed"):
            GameManager.score_changed.connect(_on_score_changed)
    
    # Set initial values from GameManager state
    _on_score_changed(GameManager.player_score, GameManager.ai_score)
    
    visible = false  # Hidden until StartMenu triggers show


# ── Signal Handlers ──
func _on_score_changed(player_score: int, ai_score: int) -> void:
    """Update label text when GameManager.score_changed fires."""
    if player_label:
        player_label.text = "Player: " + str(player_score)
    if ai_label:
        ai_label.text = "AI: " + str(ai_score)
```

### 4.3 `game_over_screen.gd`

```gdscript
extends CanvasLayer
## GameOverScreen — winner announcement with pulse glow and SPACE-to-restart prompt.
## Parent Issue: #292

# ── Constants ──
const COLOR_PLAYER: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const COLOR_AI: Color     = Color(1.0, 0.2, 0.33, 1.0)      # #ff3355
const TEXT_PLAYER_WIN: String = "YOU WIN!"
const TEXT_AI_WIN: String     = "AI WINS!"

# ── Exported ──
@export var winner_pulse_duration: float = 1.0   # Seconds for one pulse cycle
@export var prompt_blink_period: float = 0.8      # Seconds for one blink cycle

# ── Node References ──
@onready var winner_label: Label = $CenterContainer/VBoxContainer/WinnerLabel
@onready var restart_label: Label = $CenterContainer/VBoxContainer/RestartPromptLabel

# ── State ──
var _winner_tween: Tween = null
var _prompt_tween: Tween = null
var _transitioning: bool = false


# ── Lifecycle ──
func _ready() -> void:
    # Guard: skip if nodes missing
    if not winner_label or not restart_label:
        return
    
    # Connect to GameManager.match_over signal
    if is_instance_valid(GameManager):
        if GameManager.has_signal("match_over"):
            GameManager.match_over.connect(_on_match_over)
    
    visible = false


func _input(event: InputEvent) -> void:
    if not visible or _transitioning:
        return
    if event.is_action_pressed("ui_accept"):  # SPACE key
        _on_restart_pressed()


# ── Signal Handlers ──
func _on_match_over(winner: String) -> void:
    """Called when GameManager.match_over fires. Shows winner text and animations."""
    if not winner_label or not restart_label:
        return
    
    # Set winner text and color
    match winner:
        "player":
            winner_label.text = TEXT_PLAYER_WIN
            winner_label.modulate = COLOR_PLAYER
        "ai":
            winner_label.text = TEXT_AI_WIN
            winner_label.modulate = COLOR_AI
        _:
            return
    
    # Hide HUD
    var hud := _get_sibling("GameHUD")
    if hud:
        hud.visible = false
    
    # Show this screen
    visible = true
    _transitioning = false
    
    # Start animations (headless-safe)
    if get_tree():
        _start_winner_pulse()
        _start_prompt_blink()


# ── Animation ──
func _start_winner_pulse() -> void:
    _kill_tween(_winner_tween)
    _winner_tween = create_tween()
    _winner_tween.set_loops()
    _winner_tween.tween_property(winner_label, "modulate:a", 0.4, winner_pulse_duration * 0.5)
    _winner_tween.tween_property(winner_label, "modulate:a", 1.0, winner_pulse_duration * 0.5)


func _start_prompt_blink() -> void:
    _kill_tween(_prompt_tween)
    _prompt_tween = create_tween()
    _prompt_tween.set_loops()
    _prompt_tween.tween_property(restart_label, "modulate:a", 0.0, prompt_blink_period * 0.5)
    _prompt_tween.tween_property(restart_label, "modulate:a", 1.0, prompt_blink_period * 0.5)


# ── Internal ──
func _on_restart_pressed() -> void:
    _transitioning = true
    _kill_tweens()
    visible = false
    
    # Return to start menu
    var menu := _get_sibling("StartMenu")
    if menu and menu.has_method("show_menu"):
        menu.show_menu()
    
    # Reset match state
    GameManager.reset_match()


func _get_sibling(node_name: String) -> CanvasLayer:
    var parent := get_parent()
    if not parent:
        return null
    return parent.get_node_or_null(node_name)


func _kill_tween(tween: Tween) -> void:
    if tween and is_instance_valid(tween):
        tween.kill()


func _kill_tweens() -> void:
    _kill_tween(_winner_tween)
    _kill_tween(_prompt_tween)
    _winner_tween = null
    _prompt_tween = null
```

---

## 5. Signal Wiring & Data Flow

### 5.1 Connection Table

| Connection | Where | When |
|-----------|-------|------|
| `GameManager.score_changed` → `game_hud._on_score_changed` | `game_hud.gd:_ready()` | On HUD scene enter |
| `GameManager.match_over` → `game_over_screen._on_match_over` | `game_over_screen.gd:_ready()` | On GameOver scene enter |
| `ScoringManager.scored` → `score_flash._on_score_changed` | `scoring_manager.gd:_ready()` line 47 | Already wired (#291) |

**Note on ScoringManager vs GameManager overlap:** Both systems track scores independently and emit signals. The UI connects to GameManager signals (autoload, always available) rather than ScoringManager signals (scene-local, requires node path). The score_flash already connects to `ScoringManager.scored` — this connection is preserved and does not need modification.

### 5.2 Full Data Flow Sequence

```
GAME START:
  1. game.tscn loads → StartMenu.visible=true, GameHUD.visible=false, GameOver.visible=false
  2. StartMenu._ready() → title pulse + prompt blink start
  3. Player presses SPACE → StartMenu._on_start_pressed()
     ├── StartMenu.visible=false (kill tweens)
     ├── GameHUD.visible=true
     └── GameManager.reset_match()

GAMEPLAY — SCORE:
  1. Ball exits boundary → ScoringManager._on_ball_score(side)
     ├── ScoringManager.scored.emit(winner) → score_flash._on_score_changed → flash()
     └── (ScoringManager also calls GameManager.add_score internally? NO — they are independent)
  
  IMPORTANT: The PRD envisions GameManager.add_score() being called by some coordinator.
  Currently GameManager tracks scores independently. For the UI to work, one of:
    (a) ScoringManager also calls GameManager.add_score() — coupling them
    (b) The UI listens to BOTH signal sources
    (c) A future state machine (#294) coordinates both

  RECOMMENDED for #292 implement phase: Have ScoringManager._on_ball_score()
  also call GameManager.add_score(winner) so GameManager signals fire.
  This is a 1-line addition to scoring_manager.gd (see §6.2).

GAMEPLAY — MATCH END:
  1. GameManager.match_over.emit(winner)
     └── game_over_screen._on_match_over(winner)
         ├── Set winner text + color
         ├── GameHUD.visible=false
         ├── GameOverScreen.visible=true
         └── Start winner pulse + prompt blink

RESTART:
  1. Player presses SPACE on GameOverScreen → _on_restart_pressed()
     ├── GameOverScreen.visible=false (kill tweens)
     ├── StartMenu.show_menu() → visible=true + restart animations
     └── GameManager.reset_match()
```

### 5.3 Critical Integration Point: GameManager.add_score() call

The scoring_manager.gd currently tracks scores and emits `scored` but does **not** call `GameManager.add_score()`. Without this call, `GameManager.score_changed` never fires, and the HUD never updates.

**Fix (1 line in scoring_manager.gd, `_on_ball_score` method, after line 66):**
```gdscript
# After scored.emit(winner) on line 66, add:
GameManager.add_score(winner)
```

This is the only modification to existing files. It bridges the ScoringManager→GameManager gap without duplicating logic.

---

## 6. Edge Cases & Error Handling

> Source: PRD §5 (边界条件) + §5 (失败路径). Adopted and extended for the UI layer.

| # | Edge Case | Mitigation |
|---|-----------|------------|
| 1 | **Headless mode:** `get_tree()` returns null, `create_tween()` and `await` crash | All scripts guard with `if get_tree():` before creating tweens or awaiting timers. `--headless --quit` runs compilation only — animations silently skipped. |
| 2 | **GameManager autoload not registered:** `[autoload]` missing from `project.godot` (#293 rollback) | `_ready()` checks `is_instance_valid(GameManager)` before connecting signals. If null, HUD labels display initial "Player: 0 / AI: 0" and remain static. No crash. |
| 3 | **Initial state — no signals emitted yet:** HUD loads before any score event | HUD's `_ready()` explicitly calls `_on_score_changed(GameManager.player_score, GameManager.ai_score)` to seed labels from GameManager's current state. Both are 0 on fresh start. |
| 4 | **Rapid SPACE double-press:** Player hits SPACE twice within 0.1s on StartMenu or GameOverScreen | Each script maintains a `_transitioning` bool flag. Set `true` at entry of transition handler; prevents second trigger. Flag is not auto-reset — reset happens when the screen is re-shown via `show_menu()` or `_on_match_over()`. |
| 5 | **Signal received while CanvasLayer is invisible:** HUD hidden but `score_changed` fires mid-game-over transition | HUD's `_on_score_changed()` unconditionally updates its Label.text regardless of `visible` state. When HUD becomes visible again, labels already show correct scores. No signal loss. |
| 6 | **Font missing / unavailable:** Specified font resource not found at runtime | Godot auto-falls back to `system_font`. UI remains readable — aesthetic quality degrades (falls back to default sans-serif) but all text renders and functions correctly. No crash. |
| 7 | **CanvasLayer sibling not found:** `_get_sibling("GameHUD")` returns null during transition | `_get_sibling()` uses `get_node_or_null()` — returns null safely. Callers check for null before accessing properties. Transition proceeds without toggling the missing layer — state machine (#294) provides the authoritative visibility control. |
| 8 | **Tween conflict on same Label:** New pulse/blink animation requested while previous Tween still running | All animation start methods (`_start_title_pulse()`, `_start_winner_pulse()`, `_start_prompt_blink()`) call `_kill_tween(existing)` before creating a new one. `tween.kill()` aborts in-progress animation cleanly. |
| 9 | **`match_over` signal fires with invalid winner string:** Unknown string (neither "player" nor "ai") | `_on_match_over()` has a `match` statement with `_:` fallthrough that returns early — no label update, no visible change, no crash. |
| 10 | **`scoring_manager.gd` bridge line missing:** Implement phase forgets to add `GameManager.add_score(winner)` | GameManager signals never fire → HUD never updates (labels stuck at "Player: 0 / AI: 0"). DESIGN doc explicitly calls this out in §5.3 and Appendix B as a **required** 1-line change. Implement agent's acceptance test TC4 verifies signal connection. |
| 11 | **CanvasLayer `layer` property mismatch:** StartMenu and GameOverScreen both use `layer=1`, but both could theoretically be visible if a bug sets both to `visible=true` | DESIGN contract: only one layer visible at a time enforced by transition code. `layer=1` is intentional — StartMenu and GameOverScreen are never visible simultaneously, so they share the same render layer without conflict. GameHUD uses `layer=0` (below). |

### Failed Paths

| # | Failure | Outcome |
|---|---------|---------|
| F1 | `GameManager.score_changed.connect()` throws because GameManager not yet initialized | `_ready()` guards with `is_instance_valid(GameManager) && GameManager.has_signal("score_changed")` — connection attempt skipped. Labels remain at default text. |
| F2 | CanvasLayer scene not instantiated in `game.tscn` — Label references are null | `_ready()` checks each `@onready` Label reference — if null, method returns early. No crash, no UI rendered. |
| F3 | `create_tween()` returns null (rare Godot edge case) | `_kill_tween()` checks `is_instance_valid(tween)` before calling `.kill()`. `_start_*` methods check `if _tween == null` before calling `.set_loops()` — no crash. |

---

## 7. Integration

### 7.1 game.tscn Modifications

Add three CanvasLayer instances as children of the root `Game` node, **after** the ScoringManager node. Node order in the scene tree matters — CanvasLayer `layer` property controls render order, but scene order determines processing order for `_input()`:

```gdscript
[node name="StartMenu" type="CanvasLayer" parent="."]
layer = 1
script = ExtResource("X_start_menu")

[node name="CenterContainer" type="CenterContainer" parent="StartMenu"]
... (see scene design §3.1)

[node name="GameHUD" type="CanvasLayer" parent="."]
layer = 0
script = ExtResource("X_game_hud")

[node name="MarginContainer" type="MarginContainer" parent="GameHUD"]
... (see scene design §3.2)

[node name="GameOverScreen" type="CanvasLayer" parent="."]
layer = 1
script = ExtResource("X_game_over")

[node name="CenterContainer" type="CenterContainer" parent="GameOverScreen"]
... (see scene design §3.3)
```

The StartMenu and GameOverScreen both use `layer=1` — only one is visible at a time, so they don't overlap.

### 7.2 scoring_manager.gd Modification

**File:** `mini-pong/gdscripts/scoring_manager.gd`
**Change:** Add `GameManager.add_score(winner)` call after `scored.emit(winner)` on line 66.

```gdscript
# Line 66-67, change from:
	scored.emit(winner)

# To:
	scored.emit(winner)
	GameManager.add_score(winner)
```

This is the minimal bridge required for GameManager signals to fire and the UI to receive updates.

### 7.3 Files Created / Modified

| File | Action | Description |
|------|--------|-------------|
| `mini-pong/scenes/ui_start_menu.tscn` | **CREATE** | CanvasLayer scene with title + prompt labels |
| `mini-pong/scenes/ui_game_hud.tscn` | **CREATE** | CanvasLayer scene with score labels |
| `mini-pong/scenes/ui_game_over.tscn` | **CREATE** | CanvasLayer scene with winner + restart labels |
| `mini-pong/gdscripts/start_menu.gd` | **CREATE** | Start menu controller with pulse/blink animations |
| `mini-pong/gdscripts/game_hud.gd` | **CREATE** | HUD score display, signal-driven |
| `mini-pong/gdscripts/game_over_screen.gd` | **CREATE** | Game over screen with winner display + restart |
| `mini-pong/scenes/game.tscn` | **MODIFY** | Add 3 CanvasLayer instance nodes |
| `mini-pong/gdscripts/scoring_manager.gd` | **MODIFY** | Add `GameManager.add_score(winner)` call (1 line) |

### 7.4 Dependencies

All dependencies are CLOSED:
- #301 (Scaffold) — directory structure exists
- #291 (Scoring) — signals emit, GameManager.add_score() API exists
- #293 (GameManager) — autoload registered, reset_match() available
- #289 (Neon Visual) — color constants #4a90d9 / #ff3355 defined

---

## 8. Spike / Experiments

*Skipped per depth/standard. No technical uncertainty — all components use Godot core classes (CanvasLayer, Label, Tween).*

---

## 9. Continuation Context

*Skipped per depth/standard — handled by PRD §8.*

---

## 10. Test Case Descriptions

These describe what the implement phase should verify. Headless tests use `godot --headless --quit` for compilation validation. Runtime tests require manual playtesting or future integration test infrastructure.

### TC1: Compilation — All Scripts Parse Without Errors

**Test file:** `mini-pong/tests/test_ui_system.gd`
**Method:** `godot --path mini-pong/ --headless --quit --script tests/test_ui_system.gd`
**What it does:**
1. Load each new script resource (`load("res://gdscripts/start_menu.gd")`, etc.)
2. Verify script is valid GDScript (non-null load result)
3. Verify each script extends the correct base class (CanvasLayer)
4. Exit with code 0 on success, 1 on failure

**Expected result:** Exit code 0. No parse errors, no missing method errors.

### TC2: Scene Loading — All Three Scenes Instantiate

**Test file:** same as TC1
**What it does:**
1. `load("res://scenes/ui_start_menu.tscn").instantiate()` → verify non-null, type is CanvasLayer
2. `load("res://scenes/ui_game_hud.tscn").instantiate()` → verify non-null
3. `load("res://scenes/ui_game_over.tscn").instantiate()` → verify non-null
4. Verify each has the expected child nodes (specific Label paths)

**Expected result:** All three scenes instantiate successfully. Label nodes exist at expected paths.

### TC3: Headless Safety — No Crashes on get_tree()==null

**Test file:** same as TC1
**What it does:**
1. Instantiate StartMenu scene in headless mode (no running tree)
2. Call `_ready()` — verify no errors (Tween creation guarded)
3. Instantiate GameOverScreen, call `_ready()`, call `_on_match_over("player")` — verify no errors
4. Call `_input()` with SPACE event — verify no crash from missing tree

**Expected result:** No errors printed to stderr. All guarded code paths skip silently.

### TC4: Signal Connection — GameManager.connect() Does Not Throw

**Test file:** same as TC1
**What it does:**
1. Register GameManager autoload manually in test
2. Instantiate GameHUD scene
3. Verify `GameManager.score_changed` signal exists
4. Verify connection succeeds (no "signal not found" error)
5. Emit `GameManager.score_changed.emit(3, 2)` — verify HUD labels update

**Expected result:** Connection succeeds. Labels show "Player: 3" and "AI: 2".

### TC5: Label Text Updates on Signal

**Test file:** same as TC1
**What it does:**
1. Instantiate GameHUD with mock GameManager
2. Call `_on_score_changed(0, 0)` → verify labels = "Player: 0", "AI: 0"
3. Call `_on_score_changed(5, 3)` → verify labels = "Player: 5", "AI: 3"
4. Edge: call with negative numbers → labels update correctly (str() handles int)

**Expected result:** Labels always reflect the passed integers.

### TC6: Winner Text — Correct Color and Text for Each Winner

**Test file:** same as TC1
**What it does:**
1. Instantiate GameOverScreen
2. Call `_on_match_over("player")` → verify winner_label.text = "YOU WIN!", color = #4a90d9
3. Reset, call `_on_match_over("ai")` → verify winner_label.text = "AI WINS!", color = #ff3355
4. Call `_on_match_over("invalid")` → verify no change (guard clause returns early)

**Expected result:** Correct text and color for both valid winners. Invalid input handled gracefully.

### TC7: Debounce — Rapid SPACE Press Does Not Double-Transition

**Test file:** same as TC1 (or manual playtest)
**What it does:**
1. Instantiate StartMenu, set visible=true
2. Send SPACE input event twice within 0.1s
3. Verify `_transitioning` flag prevented second transition
4. Verify HUD visible = true (not double-toggled)

**Expected result:** Only one transition occurs. HUD ends up visible=true.

### TC8: game.tscn Integration — CanvasLayers Present in Correct Order

**Test file:** same as TC1
**What it does:**
1. Load and instantiate `res://scenes/game.tscn`
2. Verify StartMenu CanvasLayer exists as child
3. Verify GameHUD CanvasLayer exists as child
4. Verify GameOverScreen CanvasLayer exists as child
5. Verify StartMenu.visible=true, GameHUD.visible=false, GameOverScreen.visible=false (initial state)

**Expected result:** All three CanvasLayers present with correct initial visibility.

### TC9: Resolution — Labels Readable at 1280×720

**Verification:** Manual playtest or screenshot comparison
**What to check:**
- Title "Mini Pong" at 64px font: centered, fully visible, not clipped
- HUD labels at 28px font: top margin 20px visible, text not truncated
- "YOU WIN!" at 72px font: centered, not overflowing
- Prompt text at 28px font: fully visible below winner text

**Expected result:** All text readable, no clipping, no overlap.

### TC10: Modulate Alpha Animation — Tweens Created and Run

**Test file:** same as TC1
**What it does:**
1. In a non-headless test (requires running tree), instantiate StartMenu
2. Add to scene tree
3. Verify `_title_tween` is not null after `_ready()`
4. Wait 0.5s, verify `title_label.modulate.a` has changed from initial value
5. Verify `prompt_label.modulate.a` oscillating

**Expected result:** Animations are running. Alpha values change over time. No Tween conflicts (only one active Tween per label).

---

## Appendix A: Color Reference

| Element | Hex | Godot Color |
|---------|-----|-------------|
| Player (blue) | #4a90d9 | `Color(0.29, 0.56, 0.85, 1.0)` |
| AI (red) | #ff3355 | `Color(1.0, 0.2, 0.33, 1.0)` |
| Background | #0a0a12 | `Color(0.039, 0.039, 0.071, 1.0)` |
| Flash alpha | — | `0.3` (score_flash.gd override) |

## Appendix B: Key Decisions for Implement Agent

1. **GameManager.add_score() bridge:** The implement phase MUST add the 1-line `GameManager.add_score(winner)` call to `scoring_manager.gd:_on_ball_score()`. Without this, GameManager signals never fire and the HUD never updates.

2. **Scene vs. inline nodes:** The PRD says three independent `.tscn` files. The implement phase should create `.tscn` files (not pack everything in game.tscn as inline nodes). This enables independent testing and editor preview.

3. **signal guard pattern:** Always check `GameManager.has_signal("signal_name")` before connecting — in case GameManager autoload registration fails.

4. **No ShaderMaterial:** Neon glow on UI text comes from project-wide glow (enabled in project.godot) + modulate alpha animation. No per-node shaders needed.

5. **SPACE mapping:** Uses `ui_accept` action (default SPACE / Enter in Godot) — no custom input map needed.
