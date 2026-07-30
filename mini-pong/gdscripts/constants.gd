extends RefCounted
## Global constants for Mini Pong — single source of truth.
## Imported by ball.gd, paddle.gd, scoring_manager.gd, game_manager.gd.
##
## Usage: const CONSTS = preload("res://gdscripts/constants.gd")
## Design: docs/DESIGN/295-main-scene-assembly.md §2.2

class_name GameConstants

# ── Screen ──
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720

# ── Ball Physics ──
const BALL_INITIAL_SPEED: float = 300.0
const BALL_MAX_SPEED_MULTIPLIER: float = 2.0
const BALL_SPEED_INCREMENT: float = 1.05
const BALL_MAX_BOUNCE_ANGLE: float = 60.0
const BALL_SERVE_ANGLE_RANGE: float = 45.0
const BALL_RADIUS: float = 10.0

# ── Paddle ──
const PADDLE_SPEED: float = 400.0
const PADDLE_WIDTH: float = 20.0
const PADDLE_HEIGHT: float = 120.0

# ── AI ──
const AI_REACTION_DELAY_MIN: float = 0.1
const AI_REACTION_DELAY_MAX: float = 0.3
const AI_POSITION_ERROR: float = 20.0
const AI_SPEED_BOOST: float = 1.2
const AI_SPEED_SLOW: float = 0.8

# ── Scoring ──
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

# ── Colors ──
const PLAYER_NEON_BLUE: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const AI_NEON_RED: Color = Color(1.0, 0.2, 0.33, 1.0)            # #ff3355
const BG_COLOR: Color = Color(0.039, 0.039, 0.071, 1.0)          # #0a0a12
