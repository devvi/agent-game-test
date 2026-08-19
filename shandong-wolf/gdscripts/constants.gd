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

# ── 弹反窗口（# DRAFT 候补值，待 #584 用户定稿）──
# PARRY_WINDOW_FRAMES
#   只狼基准: ~12 帧（0.2s @60fps，偏宽松=容错手感来源）
#   候选集: [8, 10, 12, 14]（默认 12 = 只狼基准；8/14 为容错两极备选）
#   偏离理由: 无——只狼基准直接采纳
const PARRY_WINDOW_FRAMES: int = 12          # # DRAFT
const PARRY_WINDOW_SECONDS: float = 0.2      # # DRAFT（派生展示 = FRAME_RHYTHM_BASE 换算，不重复定义来源）

# ── 架势回复（# DRAFT 候补值，待 #584 用户定稿）──
# POSTURE_RECOVERY_PER_SEC
#   只狼基准: 20-35/s（脱战/停防 1.5s 延迟后快速回复；回复太快=无脑弹反，太慢=龟缩——节奏阀）
#   候选集: [20, 25, 30, 35]（默认 25 = 区间中位；宽容 35 / 严苛 20）
#   偏离理由: 无——只狼基准区间直接采纳
const POSTURE_RECOVERY_PER_SEC: float = 25.0 # # DRAFT
# POSTURE_RECOVERY_DELAY
#   只狼基准: 脱战 1.5s 延迟后开始回复（原地喘息=只狼的停防）
#   候选集: [1.0, 1.5, 2.0]（默认 1.5 = 只狼基准）
#   偏离理由: 无
const POSTURE_RECOVERY_DELAY: float = 1.5    # # DRAFT
# POSTURE_BLOCK_COST
#   只狼基准: 中（8-12/次，长按格挡的代价）
#   候选集: [8, 10, 12]（默认 10 = 区间中位）
#   偏离理由: 无
const POSTURE_BLOCK_COST: float = 10.0       # # DRAFT
# POSTURE_BREAK_THRESHOLD
#   只狼基准: = 当前 HP 上限（满则架势崩解 → 可处决；血越多越扛架势——只狼铁律）
#   候选集: [100, 150]（派生=恒等于 LIFE_1_MAX，此处为 LIFE_1_MAX 候选映射）
#   偏离理由: 无（联动规则见 DESIGN §2.1）
const POSTURE_BREAK_THRESHOLD: float = 100.0 # # DRAFT

# ── 两条命数值（# DRAFT 候补值，待 #584 用户定稿）──
# LIFE_TOTAL
#   只狼基准: 回生机制（HP 归零 → 消耗回生机会原地复活；第 2 条 = 最后一搏）
#   候选集: [2]（两条命结构，机械语义，骨架期定稿）
#   偏离理由: 无
const LIFE_TOTAL: int = 2                    # # DRAFT
# LIFE_1_MAX
#   只狼基准: 100%（20 格）——第一条命是容错，允许失误
#   候选集: [100, 120]（基准 100；120 为高容错实验候选，面板 range 50-200 开放）
#   偏离理由: 无（只狼基准 100 直接采纳）
const LIFE_1_MAX: float = 100.0              # # DRAFT
# LIFE_2_ABS
#   只狼基准: 回生后约半血（40-60 绝对血量 = 命悬一线）
#   候选集: [40, 50, 60]（默认 50 = 半血基准）
#   偏离理由: 无（绝对血量替代 ratio 作为面板参数；LIFE_2_MAX_RATIO 保留为派生展示）
const LIFE_2_ABS: float = 50.0               # # DRAFT
# LIFE_2_MAX_RATIO
#   只狼基准: 回生后约半血（ratio 语义，派生展示）
#   候选集: [0.4, 0.5, 0.6]
#   偏离理由: 派生展示 = LIFE_2_ABS / LIFE_1_MAX，消费方经 get_value 读派生值
const LIFE_2_MAX_RATIO: float = 0.5          # # DRAFT

# ── 刀伤害（# DRAFT 候补值，待 #584 用户定稿）──
# SWORD_DAMAGE_LIGHT
#   只狼基准: 轻击连段 10-15 架势伤害（处决导向，架势伤害为主）
#   候选集: [10, 12, 15]（默认 12 = 区间中位）
#   偏离理由: 无
const SWORD_DAMAGE_LIGHT: float = 12.0       # # DRAFT
# SWORD_DAMAGE_HEAVY
#   只狼基准: 重击 25-40 架势伤害
#   候选集: [25, 30, 40]（默认 30 = 区间中位）
#   偏离理由: 无
const SWORD_DAMAGE_HEAVY: float = 30.0       # # DRAFT
# SWORD_DAMAGE_EXECUTE
#   只狼基准: 忍杀 = 一击必杀（架势崩解或 HP 归零后处决，无视架势）
#   候选集: [999.0]（机械语义：处决 = 无视架势终结，骨架期可定稿）
#   偏离理由: 无（数值本身无手感意义，语义即值）
const SWORD_DAMAGE_EXECUTE: float = 999.0    # # DRAFT

# ── 帧节奏（# DRAFT 候补值，待 #584 用户定稿）──
# FRAME_ATTACK_WINDUP
#   只狼基准: 玩家攻击前摇可读、收招滞（轻击连段节奏）
#   候选集: [6, 8, 10]（默认 8 = #572 占位延续，玩家侧手感）
#   偏离理由: 无（玩家侧前摇偏短=操作响应优先）
const FRAME_ATTACK_WINDUP: int = 8           # # DRAFT
# FRAME_ATTACK_RECOVERY
#   只狼基准: 攻击后摇可惩罚（后摇长 = 进攻有风险）
#   候选集: [12, 14, 16]（默认 14 = #572 占位延续）
#   偏离理由: 无
const FRAME_ATTACK_RECOVERY: int = 14        # # DRAFT

const FRAME_RHYTHM_BASE: int = 60            # # DRAFT（基准帧率参考，机械常量语义）

#   候补值: 攻击前摇 8 / 暴发 4 / 收招 10；过渡上限 2 帧；步态循环 4 帧；处决 5 帧；刀光衰减 4 帧；
#           墨色剪影 #2b2b2b（issue body 指定）/ 冷白刀身 #c0c8d0（雪夜反差）；头:躯干:臂:腿 ≈ 1:2.5:1.9:2.2
#   该值影响什么: 《小小系列》式「起势慢→爆发快→收招滞」的力度感全由这三段帧数承载；过渡上限是 AC1 硬约束
#                （2 帧 @60fps = 0.033s）；骨骼几何决定剪影可读性（角色总高 ≈150px @720p 画布）
#   情感断言: 干净力量感——前摇可读蓄力、暴发瞬间爆发、收招滞刀有余韵；单色剪影无贴图细节，靠摆姿与比例说话（禁止页游光效堆砌）
const FRAME_ANIM_ATTACK_WINDUP: int = 8    # # DRAFT（与 FRAME_ATTACK_WINDUP=8 对齐互引）
const FRAME_ANIM_ATTACK_BURST: int = 4     # # DRAFT（新值；挥刀暴发，刀光在此段触发）
const FRAME_ANIM_ATTACK_RECOVERY: int = 10 # # DRAFT（⚠️ 与 FRAME_ATTACK_RECOVERY=14 冲突，双值共存互引，禁止实现期二选一，定稿归 #584）
const FRAME_ANIM_TRANSITION_MAX: int = 2   # # DRAFT（AC1 过渡上限；2 帧 @60fps = 0.033s）
const FRAME_ANIM_MOVE_STEP: int = 4        # # DRAFT（步态摆臂循环 4 帧，配方 §6.5）
const FRAME_ANIM_EXECUTE_TOTAL: int = 5    # # DRAFT（处决上撩→斩落 5 帧，配方 §7）
const FRAME_ANIM_SWORD_ARC_FADE: int = 4   # # DRAFT（刀光存在/衰减帧数，PRD 实验 2 预期值）
const BODY_COLOR: Color = Color("#2b2b2b")      # # DRAFT（issue body 墨色剪影）
const SWORD_COLOR: Color = Color("#c0c8d0")     # # DRAFT（冷白刀身，雪夜反差点）
const BODY_HEAD_RADIUS: float = 16.0            # # DRAFT
const BODY_TORSO_LENGTH: float = 44.0           # # DRAFT
const BODY_ARM_LENGTH: float = 34.0             # # DRAFT
const BODY_LEG_LENGTH: float = 40.0             # # DRAFT
const BODY_LIMB_WIDTH: float = 6.0              # # DRAFT（Line2D width）
const SWORD_LENGTH: float = 88.0                # # DRAFT（长刀，视觉焦点）
const SWORD_WIDTH: float = 5.0                  # # DRAFT

# ── 刀光弧线参数（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 张角 120°（PRD 实验 2 预期）/ 半径 70 / 4 环透明度衰减 / 起始 alpha 0.6
#   该值影响什么: 挥砍轨迹的可读性——张角过大刺眼（反页游光效）、过小看不清轨迹
#   情感断言: 一刀见痕的爽快——轨迹醒目但不喧宾夺主（角色退后、刀是视觉焦点，配方 §6.5）
const SWORD_ARC_SWEEP_DEG: float = 120.0        # # DRAFT（实验 2 预期最佳值）
const SWORD_ARC_RADIUS: float = 70.0            # # DRAFT
const SWORD_ARC_RINGS: int = 4                  # # DRAFT（径向透明度衰减环数）
const SWORD_ARC_ALPHA_START: float = 0.6        # # DRAFT

# ── 输入层（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 缓冲窗口 150ms ∈ [100,200]（AC4）；队列上限 8；垫步长按阈值 200ms；
#   移动加速度 1200 px/s² / 最高速度 300 px/s（起步 2 帧达标，冷冽干脆）
#   该值影响什么: 输入缓冲窗口=连招衔接手感（越大越宽容）；垫步阈值=轻按/按住双义分界；
#   移动参数=横板位移手感（AC6 位移 ≥100px 的达标基础）
#   情感断言: 输入零吞噬的"指哪打哪"——快速连按全生效，操作意图不丢失
const INPUT_BUFFER_WINDOW_MS: int = 150       # # DRAFT（AC4：∈ [100,200]）
const INPUT_BUFFER_MAX: int = 8               # # DRAFT（队列上限，拒新不丢旧）
const DASH_HOLD_THRESHOLD_MS: int = 200       # # DRAFT（轻按=垫步 / 按住≥此值=冲刺）
const MOVE_ACCELERATION: float = 1200.0       # # DRAFT（px/s²，起步 2 帧达标）
const MOVE_MAX_SPEED: float = 300.0           # # DRAFT（px/s）

# ── 受击/敌人/处决（# DRAFT 候补值，待 #584 用户定稿，本分区为 #584 新增）──
# POSTURE_HIT_COST
#   只狼基准: 受击扣架势大（30-40/次）——血+架势双重惩罚，纯防御会崩架势，逼玩家进攻（只狼核心哲学）
#   候选集: [30, 35, 40]（默认 35 = 区间中位；宽容 30 / 严苛 40）
#   偏离理由: 无
const POSTURE_HIT_COST: float = 35.0         # # DRAFT
# PARRY_COST
#   只狼基准: 弹反成功扣 0（精准格挡的奖励——成功不扣血不扣架势）
#   候选集: [0, 1, 2]（默认 1 = 轻微消耗）
#   偏离理由: 只狼为 0；本项目保留 0-2 微调通道——默认 1 防「无脑弹反」惩罚余地，用户实机裁决 0/1/2
const PARRY_COST: float = 1.0                # # DRAFT
# ENEMY_ATTACK_WINDUP
#   只狼基准: 危攻击前摇 14-18 帧（刺刀突刺=可识破的危攻击）；普通攻击前摇可读
#   候选集: [12, 15, 18]（默认 15 = 区间中位；12 = 快刀精英备选）
#   偏离理由: 无（issue body 指定 12-18 帧，与只狼 14-18 基本重合，取宽 12 下限）
const ENEMY_ATTACK_WINDUP: int = 15          # # DRAFT
# EXECUTE_RANGE
#   只狼基准: 忍杀触发 = 近身（架势崩解后玩家靠近即可处决）
#   候选集: [1.0, 1.2, 1.5]（默认 1.2 = issue body 指定）
#   偏离理由: 无
const EXECUTE_RANGE: float = 1.2             # # DRAFT
# SLOWMO_COEFF
#   只狼基准: 处决演出 = hit-stop + 特写慢动作（情绪峰值制造）
#   候选集: [0.1, 0.2, 0.3]（默认 0.2；0.1 = 最戏剧化，0.3 = 轻量演出）
#   偏离理由: 无（消费方 #577 处决演出在 Engine.time_scale 应用，clamp 下限 0.1 防冻结）
const SLOWMO_COEFF: float = 0.2              # # DRAFT

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
