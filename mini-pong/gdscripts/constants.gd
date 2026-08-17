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
# 弃用 (#385): 21 分制无局/比赛分层 — 保留声明避免测试加载错误，不被任何代码引用
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

# ── Dual Scoring (#385) ──
# 双得分制 (PLAN-rogue-pong §2.2/§2.4, 用户 2026-08-13 拍板, mechanical)
const BRICK_SCORE: int = 1        # 拆砖分：最后触球方 +1
const PIERCE_SCORE: int = 3       # 穿墙分：穿越墙带后出界未被接住 +3
const WIN_SCORE: int = 21         # 终局分：任一方总分先到 21 获胜（取代 5 分/2 局制）
const GRID_WALL_Y: float = 640.0  # 砖墙中线 Y（与 #384 DESIGN #414 同值；#393 组装时统一对齐）
const WALL_BAND_HALF_HEIGHT: float = 22.0  # 墙带判定半高 = BRICK_SIZE.y/2(12) + BALL_RADIUS(10)，防高速球单帧漏判

# ── Wave Cycle (#386) ──
# 波次循环 (PLAN-rogue-pong §2.1; mechanical; 数值曲线占位归 taste-draft)
const WAVE_START_THICKNESS: int = 1        # 首波厚度（行数）——机械占位，taste-draft 可调
const WAVE_THICKNESS_STEP: int = 1         # 每波厚度增量（AC2 厚度杠杆）
const WAVE_MAX_INDEX: int = 99             # 波次上限防御（21 分制下实际远早触发 AC5）
const WAVE_SETTLE_DELAY: float = 1.0       # 结算 → 下一波自动延时（#388 接线后由其接管推进时机）
const AI_DIFFICULTY_FACTOR: float = 0.9    # 每波 AI 参数收紧系数（<1 = 更难；taste-draft 占位）
const AI_REACTION_DELAY_MIN_FLOOR: float = 0.05  # 收紧下限（clamp，防过度）
const AI_REACTION_DELAY_MAX_FLOOR: float = 0.12
const AI_POSITION_ERROR_FLOOR: float = 8.0

# ── Colors ──
const PLAYER_NEON_BLUE: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const AI_NEON_RED: Color = Color(1.0, 0.2, 0.33, 1.0)            # #ff3355

# ── Visual Three-Color Layer (#464) ──
# 视觉三色分层 (Issue #464 机械定稿; mechanical): 可控物=高亮冷色(电光青, WCAG 对比度≥4:1),
# 目标物=暖色(琥珀橙, 与可控物 HSV 色相分离≥60°), 环境=低饱和中性冷暗(亮度最低)。
# 双板共享 player_paddle.tscn → 玩家板/AI板同色, 位置区分 (经典 Pong 惯例)。
# 值可配: taste 微调在 Issue 参考区间内改此两常量, 零代码改动。
const PADDLE_NEON: Color = Color(0.0, 0.898, 1.0, 1.0)   # #00e5ff 电光青 (WCAG 12.8:1 vs BG_COLOR; 备选 #7fdfff 13.1:1)
const BRICK_NEON: Color = Color(1.0, 0.616, 0.271, 1.0)  # #ff9d45 琥珀橙 (HSV hue 28.4° vs PADDLE 186.1° = 157.7° ≥ 60°)

# ── Brick Wall (#384) ──
# 砖墙系统 (DESIGN #414 §4.2; mechanical)。BRICK_MIN_DIM 防隧穿下限：
# 球速上限 330×1.9≈627px/s → 单帧位移 ≈10.5px → 砖最小边长 ≥14px。
# GRID_WALL_Y / WALL_BAND_HALF_HEIGHT 已由 #385 定义，此处引用不重复（单一事实源）。
const BRICK_SIZE: Vector2 = Vector2(64.0, 24.0)
const BRICK_GAP: float = 4.0
const BRICK_MIN_DIM: float = 14.0

# ── Wave Transition (#390) ──
# 波次转场 (PRD #429 §4; mechanical)。时长三段和恒 == 2.0（AC2，测试断言）；
# 副句内容归 #396 taste-draft（本组只含机械常量与读取路径）。
const WAVE_TRANSITION_FADE_IN: float = 0.5
const WAVE_TRANSITION_HOLD: float = 1.0
const WAVE_TRANSITION_FADE_OUT: float = 0.5
const WAVE_TRANSITION_TITLE_FONT_SIZE: int = 112
const WAVE_TRANSITION_SUBTITLE_FONT_SIZE: int = 40
const WAVE_TRANSITION_OUTLINE_SIZE: int = 10
const WAVE_TRANSITION_JSON_PATH: String = "res://content/wave_failure_text.json"  # #396 schema wave-failure-text/v1
const WAVE_TRANSITION_DECISIVE_SCORE: int = 18   # 决胜波阈值（任一方 ≥ 此值 → ws4）
const WAVE_TRANSITION_LAYER: int = 3             # 转场层序（Atmosphere 0 < HUD 1 < Upgrade 2 < 本层 3 < Pause 10）
const WAVE_TRANSITION_BAND1_MAX: int = 2         # 波次分档边界（ws1：波 1-2）
const WAVE_TRANSITION_BAND2_MAX: int = 5         # 波次分档边界（ws2：波 3-5；6+ → ws3）

# -- Rain Curtain (#389) --
# 雨量公式 = clamp(base + 球速因子 + 波次因子 + 紧张因子 + 事件脉冲 - 喘息, 0.1, 1.0)
# 设计: docs/DESIGN/389-dynamic-rain-curtain.md 3.2；RAIN_MIN/RAIN_MAX 为唯一边界源。
const RAIN_BASE: float = 0.3
const RAIN_MIN: float = 0.1
const RAIN_MAX: float = 1.0
const RAIN_SMOOTH_TAU: float = 0.15
const RAIN_SPEED_FACTOR_MAX: float = 0.3
const RAIN_TENSION_THRESHOLD: int = 2
const RAIN_TENSION_BONUS: float = 0.2
const RAIN_WAVE_STEP: float = 0.1
const RAIN_PULSE_PIERCE: float = 0.4
const RAIN_BREATHING_DROP: float = 0.15
const BG_COLOR: Color = Color(0.039, 0.039, 0.071, 1.0)          # #0a0a12

# ── Neon HUD (#392) ──
# 霓虹描边/微投影/安全区常量（DESIGN §4.6；描边粗细、投影偏移、信息条配色 = taste-draft 可调）
const HUD_OUTLINE_SIZE: int = 6            # 霓虹描边粗细（taste-draft 4–6）
const HUD_SHADOW_OFFSET_X: int = 2         # 微投影偏移（taste-draft）
const HUD_SHADOW_OFFSET_Y: int = 2
const HUD_SHADOW_COLOR: Color = Color(0, 0, 0, 0.6)   # 微投影而非重阴影（克制优先）
const HUD_INFO_COLOR: Color = Color(0.72, 0.76, 0.85, 1.0)  # 中立信息条色（taste-draft）
const HUD_TOP_BAND_Y: float = 12.0         # 顶部安全区上缘
const HUD_TOP_BAND_H: float = 72.0         # 顶部区高度 → y∈[12,84]
const HUD_BOTTOM_BAND_Y: float = 1252.0    # 底部区上缘（玩家挡板 1230–1250 之下，零交集）
const HUD_INFO_BAR_Y: float = 88.0         # 信息条 Y（顶部区下方）
const HUD_SCORE_PREFIX_PLAYER: String = "Player: "
const HUD_SCORE_PREFIX_AI: String = "AI: "
const HUD_WAVE_PREFIX: String = "第 "
const HUD_WAVE_SUFFIX: String = " 波"

# ── Upgrade Pool (#387) ──
# 稀有度权重 60/30/10（common/rare/legendary）——AC2 精确权重，研究 spike 已证伪
# "升级粒度加权无放回"（边际分布漂移到 55.7/37.8/6.5）。抽取 = 稀有度先掷 →
# 稀有度内均匀选（见 upgrade_pool.gd get_candidates）。
const UPGRADE_RARITY_WEIGHTS: Array[int] = [60, 30, 10]
const UPGRADE_CANDIDATE_COUNT: int = 3
const UPGRADE_POOL_SIZE: int = 9
const UPGRADE_JSON_PATH: String = "res://assets/content/upgrade_pool.json"

# ── Failure Screen (#391) ──
# 失败屏 (PLAN-rogue-pong §2.4; mechanical; 文案值归 #396 taste-draft)
const FAILURE_TEXT_PATH: String = "res://content/wave_failure_text.json"  # #396 schema wave-failure-text/v1
const FAILURE_TEXT_DEFAULT_PHRASE: String = "墙还在，雨未停"               # JSON 缺失/损坏兜底（≤10字、无感叹号/emoji，红线合规）
const FAILURE_WAVE_TIER1_MAX: int = 2    # fp1 早败（波 1-2）
const FAILURE_WAVE_TIER2_MAX: int = 5    # fp2 中败（波 3-5）
const FAILURE_WAVE_TIER3_MIN: int = 6    # fp3 晚败（波 6+）
# ── Upgrade Pick UI (#388) ──
# 3 选 1 升级选择层（PLAN-rogue-pong §3.3：3 张霓虹卡片、glow 边框、数值大字、
# 动效 Tween 150–300ms）。色值为 taste 占位（沿 #387 机械占位先例），映射键机械定稿。
const UPGRADE_UI_LAYER: int = 2                     # GameHUD(1) 之上、PauseOverlay(10) 之下（DESIGN #388 差异决策 1）
const UPGRADE_UI_CARD_WIDTH: float = 180.0          # 卡片尺寸（taste 占位）
const UPGRADE_UI_CARD_HEIGHT: float = 260.0
const UPGRADE_UI_CARD_SEPARATION: float = 16.0
const UPGRADE_UI_FOCUS_TWEEN: float = 0.15          # 焦点切换动效 150ms（PLAN §3.3 区间内）
const UPGRADE_UI_REVEAL_TWEEN: float = 0.25         # reveal 动效 250ms
const UPGRADE_UI_REVEAL_HOLD: float = 0.8           # reveal 展示时长（DESIGN 差异决策 2；taste 占位，测试可注入缩短）
const UPGRADE_UI_NEUTRAL_BORDER: Color = Color(0.29, 0.56, 0.85, 0.6)   # 确认前中性霓虹边框（无稀有度线索，AC3）
const UPGRADE_UI_FOCUS_BORDER: Color = Color(0.45, 0.75, 1.0, 1.0)      # 聚焦高亮边框
const UPGRADE_UI_IDLE_MODULATE: Color = Color(0.7, 0.7, 0.75, 1.0)      # 非焦点卡调暗
const UPGRADE_UI_FOCUS_MODULATE: Color = Color(1.0, 1.0, 1.0, 1.0)      # 焦点卡全亮
const UPGRADE_RARITY_COLORS: Dictionary = {         # AC3：稀有度 → 边框/光晕色（taste 占位色值，映射键机械定稿）
	0: Color(0.29, 0.56, 0.85, 1.0),   # COMMON    → 霓虹蓝系（PLAYER_NEON_BLUE 同系）
	1: Color(0.62, 0.32, 0.95, 1.0),   # RARE      → 霓虹紫系
	2: Color(1.0, 0.78, 0.2, 1.0),     # LEGENDARY → 金系
}
const UPGRADE_RARITY_NAMES: Dictionary = {0: "普通", 1: "稀有", 2: "传说"}   # AC3 稀有度名称（确认后展示）

# ── Background Pulse (#449) ──
# 背景霓虹呼吸 (PLAN-rogue-pong §3.1 L0「背景光晕」执行层; 机制/常量 = mechanical,
# 峰值不透明度与色调 = taste-draft, human-review 定稿, 调参零代码改动)
const BG_PULSE_PERIOD: float = 4.0          # 呼吸周期 ~4s（AC1 默认，可配）
const BG_PULSE_BASE_ALPHA: float = 0.08     # 基线 alpha
const BG_PULSE_AMPLITUDE: float = 0.07      # 振幅 → alpha ∈ [0.01, 0.15]（克制 ≤15%，PLAN 暗角 ≤10% 同量级）
const BG_PULSE_TINT: Color = Color(0.29, 0.56, 0.85, 1.0)  # 霓虹蓝同系（PLAYER_NEON_BLUE #4a90d9）

# ── Ball Speed HUD (#448) ──
# 球速实时显示：GameHUD 顶部右上 Label + SpeedPollTimer 10Hz 轮询 ball.speed
# （Timer timeout 信号驱动，非 _process —— #392 TF-1 零轮询契约）。显示值 = round(ball.speed) + px/s。
const HUD_SHOW_SPEED: bool = true
const HUD_SPEED_POLL_INTERVAL: float = 0.1
const HUD_SPEED_UNIT: String = "px/s"
const HUD_SPEED_LABEL_PREFIX: String = "球速 "

# ── Audio (#450) ──
# 拆砖专属音效 (PRD #450 方案 B: 噪声突发 + 指数衰减; 机制/常量 = mechanical,
# 音色/时长数值 = taste-draft, human-review 定稿, 调参零代码改动)
const BRICK_BREAK_DURATION: float = 0.08    # 80ms 短促碎裂音
const BRICK_BREAK_VOLUME: float = 0.7       # <1.0 防削波 (spike peak 0.689 验证)
const BRICK_BREAK_DECAY_TAU: float = 0.02   # τ = duration/4 快速指数衰减
const BRICK_BREAK_SEED: int = 450           # 固定种子 → 合成确定性 (CI 可复现)

# ── Combo Speed Feedback (#504) ──
# 玩家板连击加速反馈：2s 窗口内玩家再次得分 → 板速 +20%（乘性叠加于 PADDLE_SPEED 基值）。
# 数值按 issue 字面执行（mechanical，#367 taste 域不校准）；窗口过期恢复基速。
const COMBO_WINDOW_SECONDS: float = 2.0
const COMBO_SPEED_BONUS: float = 0.2

# ── Special Brick Wave Trigger (#529) ──
# 波数触发迭代 (PRD #529 方案1; 机制/常量 = mechanical, 色值 = taste-draft 占位,
# human-review 定稿, 调参零代码改动)。特殊砖 = 普通砖 + is_special 标记,
# 击碎即触发波次结算 (替代整墙打空), 拆砖分/计数/终局规则不变 (AC5)。
const SPECIAL_BRICK_PER_WAVE: int = 1        # 每波恰好 1 颗 (替换式, 不新增砖)
const SPECIAL_BRICK_MIN_THICKNESS: int = 3   # 厚度 < 3 无内部位 → 回退 wall_cleared (AC4)
const SPECIAL_BRICK_COLOR: Color = Color(0.45, 1.0, 0.75, 1.0)       # taste 占位: 亮薄荷绿 #73ffbf
const SPECIAL_BRICK_GLOW_COLOR: Color = Color(0.45, 1.0, 0.75, 1.0)  # taste 占位: 同色光晕

