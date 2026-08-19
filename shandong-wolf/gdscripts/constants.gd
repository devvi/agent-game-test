extends RefCounted
## WolfConstants — shandong-wolf 全局常量单一事实源。
## 消费方: const C = preload("res://gdscripts/constants.gd")
## 手感分区全部 # DRAFT 候补值，定稿归 #584（taste 域，本文件禁止"顺手定稿"）。

class_name WolfConstants

# ── 机械常量（非 taste 参数，骨架期定稿）──
const GAME_VERSION: String = "v0.1.0"        # 与 Main.tscn VersionLabel 一致（#562）
const SCREEN_WIDTH: int = 1280               # project.godot viewport_width（AC1）
const SCREEN_HEIGHT: int = 720               # project.godot viewport_height（AC1）
const STATE_MACHINE_MAX_TRANSITIONS: int = 1 # 状态机单次 update 允许的最大 transition 数（防重入，§2.2）

# ── 弹反窗口（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 12 帧 @60fps = 0.2s（只狼系参考: 弹反判定极短，成功即架势重创）
#   该值影响什么: 弹反判定时间窗——越短越硬核，越长越宽容；帧节奏候补值联动（§帧节奏）
#   情感断言: 生死一瞬的"叮"——成功弹反是最高潮时刻，窗口必须短到值得炫耀
const PARRY_WINDOW_FRAMES: int = 12          # # DRAFT
const PARRY_WINDOW_SECONDS: float = 0.2      # # DRAFT（= FRAME_RHYTHM 的派生展示，不重复定义来源）

# ── 架势回复（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 0.8 架势/秒 自然回复；格挡消耗 10；弹反成功不消耗反而崩解敌方
#   该值影响什么: 架势（士气）条 = 格挡/弹反资源；崩解 → 处决（brief 核心机制 #5）
#   情感断言: 攻防节奏的呼吸感——防守方靠回复喘息，进攻方靠持续压制崩解
const POSTURE_RECOVERY_PER_SEC: float = 0.8  # # DRAFT
const POSTURE_BLOCK_COST: float = 10.0       # # DRAFT
const POSTURE_BREAK_THRESHOLD: float = 100.0 # # DRAFT（满则崩解）

# ── 两条命数值（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 第 1 条满血 100；归零 → 原地复活（第 2 条半管血 50）
#   该值影响什么: 只狼式两条命（brief 核心机制 #4）——第 1 条是容错，第 2 条是决心
#   情感断言: 复活仪式感 + 半管血的紧迫——第二次倒下就是真的输了
const LIFE_TOTAL: int = 2                    # # DRAFT（两条命，机械语义可定稿）
const LIFE_1_MAX: float = 100.0              # # DRAFT
const LIFE_2_MAX_RATIO: float = 0.5          # # DRAFT（第 2 条 = 半管血）

# ── 刀伤害（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 轻击 10 / 重击 25；处决 999（无视架势直接击杀）
#   该值影响什么: 击杀节奏（普通兵 3-4 刀 vs 精英 8-10 刀）；刀来自尸体（brief 剧情起点）
#   情感断言: 刀刀见血不拖沓——每刀都有明确的"砍中了"反馈
const SWORD_DAMAGE_LIGHT: float = 10.0       # # DRAFT
const SWORD_DAMAGE_HEAVY: float = 25.0       # # DRAFT
const SWORD_DAMAGE_EXECUTE: float = 999.0    # # DRAFT（处决 = 架势崩解后终结）

# ── 帧节奏（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 攻击前摇 8 帧 / 攻击后摇 14 帧 / 弹反窗口 12 帧（与 PARRY_WINDOW 联动）
#   该值影响什么: 攻防节奏的"帧感"（只狼系动作游戏的核心手感）；所有动画关键帧规划基准
#   情感断言: 干脆利落——前摇可读、后摇可惩罚，拼刀节奏像呼吸
const FRAME_ATTACK_WINDUP: int = 8           # # DRAFT
const FRAME_ATTACK_RECOVERY: int = 14        # # DRAFT
const FRAME_RHYTHM_BASE: int = 60            # # DRAFT（基准帧率参考）

# ── 氛围参数（# DRAFT 候补值，定稿 = #582 E2E 用户裁决）──
# ── 雪幕（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 远 60 / 中 60 / 近 80 = 200 粒子（AC1 中心值）；视差 0.2x/0.5x/1.0x；scale 近 1.5x 远 0.5x；飘落 20-40px/s；白色 α70-90%
#   该值影响什么: 雪夜纵深与密度——三层视差营造空间，粒子密度决定氛围浓度；amount 只在 .tscn 静态声明，运行时禁改（rain_curtain 教训）
#   情感断言: 苍白、清冷——雪是安静的背景呼吸，不是注意力主角
const SNOW_PARTICLES_FAR: int = 60              # # DRAFT
const SNOW_PARTICLES_MID: int = 60              # # DRAFT
const SNOW_PARTICLES_NEAR: int = 80             # # DRAFT（合计 200）
const SNOW_PARALLAX_FAR: float = 0.2            # # DRAFT
const SNOW_PARALLAX_MID: float = 0.5            # # DRAFT
const SNOW_PARALLAX_NEAR: float = 1.0           # # DRAFT
const SNOW_SCALE_FAR: float = 0.5               # # DRAFT
const SNOW_SCALE_NEAR: float = 1.5              # # DRAFT
const SNOW_VELOCITY_MIN: float = 20.0           # # DRAFT（px/s 下界）
const SNOW_VELOCITY_MAX: float = 40.0           # # DRAFT（px/s 上界）
const SNOW_ALPHA_MIN: float = 0.7               # # DRAFT
const SNOW_ALPHA_MAX: float = 0.9               # # DRAFT
const SNOW_WIND_DEFAULT: float = 0.0            # # DRAFT（风向，Boss 战可加大）

# ── 冷月光（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 目标色温 #b8c4d9（issue AC2 字面值）；CanvasModulate 无独立 brightness，「亮度 0.6」经色值换算 ≈ #6e7684（PRD §4.2 方案 B）
#   该值影响什么: 全场景色温基调
#   情感断言: 苍白、清冷——只狼苇名城雪夜 + 抗战黑白电影月光；禁止阳光明媚/星光点缀
const MOONLIGHT_COLOR_TARGET: Color = Color("#b8c4d9")   # # DRAFT（AC2 字面色值）
const MOONLIGHT_COLOR_APPLIED: Color = Color("#6e7684")  # # DRAFT（= TARGET × 0.6 换算）
const MOONLIGHT_BRIGHTNESS: float = 0.6                  # # DRAFT（语义 = 色值换算系数）

# ── 水墨晕染（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 边缘暗角 alpha ≤ 0.3（AC3 硬约束）；墨色 #1a1f26
#   该值影响什么: 全屏水墨质感
#   情感断言: 大地如墨——暗角是氛围不是遮挡，中央读图区必须通透
const INK_EDGE_ALPHA_MAX: float = 0.3            # # DRAFT（硬上限）
const INK_COLOR: Color = Color("#1a1f26")        # # DRAFT（墨色）
const INK_INNER_RADIUS: float = 0.62             # # DRAFT
const INK_SOFTNESS: float = 0.35                 # # DRAFT
const INK_NOISE_AMOUNT: float = 0.06             # # DRAFT

# ── 血色 vignette（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 低血触发 alpha 0→0.35（AC4 硬上限），0.5s 平滑渐变；CanvasLayer layer=10
#   该值影响什么: 玩家低血时的生死压迫感——红色只在危险时出现
#   情感断言: 刀刀见血不拖沓——血色是唯一允许打破冷色调的高饱和元素
const BLOOD_VIGNETTE_ALPHA_MAX: float = 0.35     # # DRAFT（硬上限）
const BLOOD_VIGNETTE_FADE_SECONDS: float = 0.5   # # DRAFT（Tween 时长）
const BLOOD_VIGNETTE_LAYER: int = 10             # 机械常量（层级约定，定稿）
