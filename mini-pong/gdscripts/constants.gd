extends RefCounted
## Global constants for Mini Pong — single source of truth.
## Imported by ball.gd, paddle.gd, scoring_manager.gd, game_manager.gd.
##
## Usage: const CONSTS = preload("res://gdscripts/constants.gd")
## Design: docs/DESIGN/295-main-scene-assembly.md §2.2
##
## 手感定稿 (#367, 2026-08-11): 11 个手感参数已由用户全采纳定稿（A1 数值即表达，
## 人机共做 v4）。定稿差异记录见 docs/TASTE.md §4。机械常量
## （SCREEN/VERSION/RADIUS/SCORING/COLORS）非 taste 参数。

class_name GameConstants

# ── Screen ──
const SCREEN_WIDTH: int = 720
const SCREEN_HEIGHT: int = 1280

# ── Version ──
const GAME_VERSION: String = "v1.0.0"

# ── Ball Physics ──
# 定稿 BALL_INITIAL_SPEED = 330.0（#367 用户全采纳）
#   该值影响什么: 开局节奏（竖屏 720x1280 纵穿 1280px: 300→4.3s, 330→3.9s；横穿 720px 更快）
#   情感断言: 利落开局——第一拍就有街机速度感
const BALL_INITIAL_SPEED: float = 330.0
# 定稿 BALL_SPEED_INCREMENT = 1.07（#367 用户全采纳）
#   该值影响什么: 每次击打加速幅度（指数曲线斜率；1.07^10≈1.97 恰好触顶）
#   情感断言: 每一次反弹都更紧迫（单次 +7%，远低于 20% 廉价感红线）
const BALL_SPEED_INCREMENT: float = 1.07
# 定稿 BALL_MAX_SPEED_MULTIPLIER = 1.9（#367 用户全采纳）
#   该值影响什么: 速度上限（330×1.9≈627 px/s ≈ 2.0s 横穿）——上限越高越易"突然失控"
#   情感断言: 高压但可控——紧张峰值不越过"失控"阈值
const BALL_MAX_SPEED_MULTIPLIER: float = 1.9
# 定稿 BALL_MAX_BOUNCE_ANGLE = 55.0（#367 用户全采纳）
#   该值影响什么: 边缘击打的锐利度（影响偏移 → 角度线性映射斜率）
#   情感断言: 利落击打感——角度干脆但不刁钻到不可救
const BALL_MAX_BOUNCE_ANGLE: float = 55.0
# 定稿 BALL_SERVE_ANGLE_RANGE = 30.0（#367 用户全采纳）
#   该值影响什么: 发球散布宽度——随机性对开局的主导权
#   情感断言: 可控性优先——发球不靠随机坑人，胜负交给 rally
const BALL_SERVE_ANGLE_RANGE: float = 30.0
const BALL_RADIUS: float = 10.0

# ── Paddle ──
# 竖屏 (#383): PADDLE_WIDTH=120 横向长度、PADDLE_HEIGHT=20 纵向厚度。
# 定稿 PADDLE_SPEED = 430.0（#367 用户全采纳）
#   该值影响什么: 玩家操控响应速度（球速加快后必须跟得上）
#   情感断言: 跟手——玩家感到"够得着"，挫败来自判断而非操作延迟
const PADDLE_SPEED: float = 430.0
const PADDLE_WIDTH: float = 120.0
const PADDLE_HEIGHT: float = 20.0

# ── AI ──
# 定稿 AI_REACTION_DELAY_MIN = 0.15（#367 用户全采纳）
#   该值影响什么: AI 反应下限（0.1s ≈ 人类顶尖反应，显作弊）
#   情感断言: 挑战但不作弊——快但可被读
const AI_REACTION_DELAY_MIN: float = 0.15
# 定稿 AI_REACTION_DELAY_MAX = 0.4（#367 用户全采纳）
#   该值影响什么: AI 反应上限 = 玩家喘息窗口
#   情感断言: 给玩家呼吸空间——紧张与放松交替（张力曲线）
const AI_REACTION_DELAY_MAX: float = 0.4
# 定稿 AI_POSITION_ERROR = 24.0（#367 用户全采纳）
#   该值影响什么: AI 失误幅度（可见可预期的犯错空间）；连带影响 paddle.gd 速度切换阈值 = error × 2（40→48px）
#   情感断言: 人可战胜——失误是"人性"，不是 bug
const AI_POSITION_ERROR: float = 24.0
# 定稿 AI_SPEED_BOOST = 1.25（#367 用户全采纳）
#   该值影响什么: AI 远距离追击速度（红线只约束球速曲线，AI 追击速度不属 20% 红线）
#   情感断言: 紧咬比分——压力渐进（隐式难度选择：玩家越快 AI 越咬）
const AI_SPEED_BOOST: float = 1.25
# 定稿 AI_SPEED_SLOW = 0.75（#367 用户全采纳）
#   该值影响什么: AI 接近目标后的缓速（精准度）
#   情感断言: 精准但不机械——到位后不抽搐
const AI_SPEED_SLOW: float = 0.75

# ── Scoring ──
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

# ── Colors ──
const PLAYER_NEON_BLUE: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const AI_NEON_RED: Color = Color(1.0, 0.2, 0.33, 1.0)            # #ff3355
const BG_COLOR: Color = Color(0.039, 0.039, 0.071, 1.0)          # #0a0a12
