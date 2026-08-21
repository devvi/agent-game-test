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
const FRAME_ANIM_MOVE_STEP: int = 4        # # DRAFT（关键姿态数 = 4：contact/pass ×2；完整步态周期由 FRAME_ANIM_MOVE_CYCLE 决定。值 4 保留——E3 断言依赖，禁止删除）
const FRAME_ANIM_EXECUTE_TOTAL: int = 5    # # DRAFT（处决上撩→斩落 5 帧，配方 §7）
const FRAME_ANIM_SWORD_ARC_FADE: int = 4   # # DRAFT（刀光存在/衰减帧数，PRD 实验 2 预期值）
const BODY_COLOR: Color = Color("#2b2b2b")      # # DRAFT（issue body 墨色剪影）
const SWORD_COLOR: Color = Color("#c0c8d0")     # # DRAFT（冷白刀身，雪夜反差点）
const BODY_HEAD_RADIUS: float = 9.5             # # DRAFT（#683 修订 16→9.5: GDD 头径:躯干 ≈ 1:2.2–2.5，候选 9–10；头圆最低点与躯干顶重叠 ≤4px）
const BODY_TORSO_LENGTH: float = 44.0           # # DRAFT
const BODY_ARM_LENGTH: float = 34.0             # # DRAFT
const BODY_LEG_LENGTH: float = 40.0             # # DRAFT（#683 保留不动——兼容既有测试/E2E；F2 已改用 UPPER/LOWER）
const BODY_LIMB_WIDTH: float = 6.0              # # DRAFT（Line2D width）
const SWORD_LENGTH: float = 88.0                # # DRAFT（长刀，视觉焦点）
const SWORD_WIDTH: float = 5.0                  # # DRAFT

# ── 火柴人结构（# DRAFT 候补值，待 #584 定稿；#683 新增，骨架结构修正专用）──
#   候补值: 颈长 10（候选 8–12）/ 大腿 20 / 小腿 20（候选 18–22，两段和保持 ≈ 原 BODY_LEG_LENGTH=40）；
#           头轮廓 开/关 + 宽 2.0（候选 1–2）+ 冷白 #c0c8d0（SWORD_COLOR 系，实验 1）；
#           步态周期 24 帧（候选 24/28/32 = 0.4–0.53s 2 步，实验 2）；
#           腿髋摆 25°（候选 20–30）/ 摆臂 25°（候选 20–35）/ 屈膝 40°（候选 30–50）；
#           膝机械上限 90° / 衔接阈值 15°；播放速度下限 0.3 / 上限 1.2（实验 3）；
#           hold 型 clip 归位段 3 帧（候选 2–4）
#   该值影响什么: 颈长决定头与躯干视觉分离度（太小粘连、太大离身）；头径按 GDD 头:躯干 ≈ 1:2.5 校准；
#           步态周期决定「走路像走路」还是「振动」（4 帧循环 = 振动）；摆幅/屈膝决定步态自然度；
#           衔接阈值保证状态切换骨架不瞬移；播放速度同步消除滑步
#   情感断言: 剪影火柴人干净可读——头身分离、步态有节奏、切换不瞬移（禁止振动/瞬移/滑步）
const BODY_NECK_LENGTH: float = 10.0                # # DRAFT（候选 8–12；影响: 头与躯干视觉分离度）
const BODY_LEG_UPPER_LENGTH: float = 20.0           # # DRAFT（候选 18–22；大腿长，两段和保持 ≈ 原 BODY_LEG_LENGTH=40）
const BODY_LEG_LOWER_LENGTH: float = 20.0           # # DRAFT（候选 18–22；小腿长，膝 pivot 支撑）
const HEAD_OUTLINE_ENABLED: bool = false            # # DRAFT（候选 true/false；taste 决策点实验 1，E2E 裁决）
const HEAD_OUTLINE_WIDTH: float = 2.0               # # DRAFT（候选 1–2；头轮廓线宽）
const HEAD_OUTLINE_COLOR: Color = Color("#c0c8d0")  # # DRAFT（冷白，SWORD_COLOR 系；头轮廓色）
const FRAME_ANIM_MOVE_CYCLE: int = 24               # # DRAFT（候选 24/28/32 = 0.4–0.53s 2 步；步态周期实验 2）
const MOVE_SWING_LEG_DEG: float = 12.0              # # DRAFT（候选 8–15；腿髋摆幅。偏离理由: 原候选 20–30 与 AC3 衔接阈值 POSE_DELTA_MAX_DEG=15° 冲突——contact 首帧腿摆幅即 idle→move 姿态差，须 ≤15°；12 为收敛后居中值）
const MOVE_SWING_ARM_DEG: float = 12.0              # # DRAFT（候选 8–15；摆臂幅度。偏离理由: 同 MOVE_SWING_LEG_DEG——摆臂以 REST_POSE 为基准 ±swing，AC3 约束 swing ≤15°）
const MOVE_KNEE_BEND_DEG: float = 40.0              # # DRAFT（候选 30–50；摆动相屈膝抬脚）
const KNEE_BEND_MAX_DEG: float = 90.0               # # DRAFT（机械上限，AC3 膝单向弯曲断言用）
const POSE_DELTA_MAX_DEG: float = 15.0              # # DRAFT（衔接阈值，AC3 状态切换关节角差上限）
const MOVE_PLAYBACK_SPEED_MIN: float = 0.3          # # DRAFT（实验 3：速度同步下限，起步/急停顺滑）
const MOVE_PLAYBACK_SPEED_MAX: float = 1.2          # # DRAFT（实验 3：速度同步上限）
const FRAME_ANIM_GUARD_EXIT: int = 3                # # DRAFT（候选 2–4；guard 尾帧归位段帧数）
const FRAME_ANIM_PARRY_SUCCESS_EXIT: int = 3        # # DRAFT（候选 2–4；parry_success 尾帧归位段帧数）
const FRAME_ANIM_STAGGER_EXIT: int = 3              # # DRAFT（候选 2–4；stagger 尾帧归位段帧数）
const FRAME_ANIM_STANCE_BREAK_EXIT: int = 3         # # DRAFT（候选 2–4；stance_break 尾帧归位段帧数）
const FRAME_ANIM_DEAD_EXIT: int = 3                 # # DRAFT（候选 2–4；dead 尾帧归位段帧数）

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
#   候选集: [12, 15, 18]（默认 12 = 区间下位；15 = 区间中位备选；18 = 慢刀兜底）
#   偏离理由: ⚠️ 2026-08-20 #581 实现期改值 12 对齐 AC1（前摇 12 帧可弹反），偏差记录交 #584 定稿
#   偏离理由: 无（issue body 指定 12-18 帧，与只狼 14-18 基本重合，取宽 12 下限）
const ENEMY_ATTACK_WINDUP: int = 12          # # DRAFT
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

# ── 夜色世界背景（# DRAFT 候补值，待 #582 用户裁决；#624 新增）──
#   作用: layer 0 世界垫底，供唯一 Moonlight（#6e7684）染色成冷蓝灰夜色（AC2 载体）
#   约束: 染后（× MOONLIGHT_COLOR_APPLIED）背景 luma ≥ 30 —— 不得回到 #613 近黑态（F3）
#   候选集: #d8dce4（浅月光灰，染后 ≈ #66686b 接近 AC2 目标 #6e7684，theme 断言可命中）——
#           #4e5464（中蓝灰，染后 ≈ #222734，luma ~39，需 A/B 亮度比断言）——
#           #0d1520（PRD §8 建议的深夜色，染后 ≈ #060a0f luma ~10，近黑，**否决候选**）
#   情感断言: 苍白、清冷——月光下的雪夜大地是亮冷灰蓝，不是无月黑夜
const NIGHT_BG_COLOR: Color = Color("#d8dce4")   # # DRAFT（首选候选；染后 ≈ #66686b）

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
# ── 战斗时序（# DRAFT 候补值，待 #584 定稿）──
# STAGGER_FRAMES
#   候补值: [8, 12, 16]（默认 12）
#   该值影响什么: 受击硬直时长——太短无受击感，太长卡操作
#   情感断言: 硬直是「被打断」的代价，不是「罚站」
const STAGGER_FRAMES: int = 12               # # DRAFT
# PARRY_SUCCESS_FRAMES
#   候补值: [8, 10, 12]（默认 10）
#   该值影响什么: 弹反成功瞬间帧（硬直窗口，#577 驱动进入）
#   情感断言: 弹反成功必须比格挡爽（只狼铁律 1）
const PARRY_SUCCESS_FRAMES: int = 10         # # DRAFT
# STANCE_BREAK_RECOVERY_SEC
#   候补值: 3.0（#580 同值互引）
#   该值影响什么: 崩解后敌人起身恢复时间
#   情感断言: 崩解 = 可从容处决的窗口（只狼铁律 2）
const STANCE_BREAK_RECOVERY_SEC: float = 3.0 # # DRAFT
# REVIVE_SECONDS
#   候补值: 1.0（#578 同值互引）
#   该值影响什么: 倒地→复活的演出时长
#   情感断言: 「还没打完这一仗」，不是神迹
const REVIVE_SECONDS: float = 1.0            # # DRAFT
# INVINCIBLE_SECONDS
#   候补值: 1.0（#578 同值互引）
#   该值影响什么: 复活后无敌时长
#   情感断言: 硬汉的第二次机会，不是耍赖
const INVINCIBLE_SECONDS: float = 1.0        # # DRAFT

# ── 判定层（# DRAFT 候补值，待 #584 定稿；#577 消费方，禁止实现期定稿）──
# PARRY_STANCE_DAMAGE
#   只狼基准: 弹反成功大幅涨敌架势（精准格挡的奖励——成功 0 伤害+敌架势大涨）
#   候选集: [20, 25, 30]（默认 25 = 区间中位；AC1 硬约束 ≥20）
#   该值影响什么: 弹反的「爽感」——太小=弹反无价值，太大=几下弹反直接崩解
#   情感断言: 弹反成功必须比格挡爽（只狼铁律 1）
const PARRY_STANCE_DAMAGE: float = 25.0      # # DRAFT
# CLASH_STANCE_COST
#   只狼基准: 拼刀（打铁）双方各扣小架势（互格=节奏博弈，代价低于受击）
#   候选集: [8, 10, 12]（默认 10 = 区间中位）
#   该值影响什么: 拼刀频率与架势续航——太小=无限拼刀，太大=拼刀=慢性自杀
#   情感断言: 打铁的代价是「势均力敌」，不是单方面惩罚
const CLASH_STANCE_COST: float = 10.0        # # DRAFT
# CLASH_PRIORITY
#   只狼基准: 弹反优先于拼刀（玩家精准按出弹反窗口却被拼刀顶掉 = 高操作被低操作覆盖）
#   候选集: [0=弹反优先, 1=拼刀优先]（默认 0；用户实机裁决，改此常量+冲突矩阵断言翻转）
#   该值影响什么: 同帧三重叠时的裁决结果——手感基调的决定性开关
const CLASH_PRIORITY: int = 0                # # DRAFT
# HITBOX_ACTIVE_FRAMES
#   只狼基准: 攻击暴发帧数（挥刀命中判定持续帧；#574 FRAME_ANIM_ATTACK_BURST=4 对齐）
#   候选集: [4, 6, 8]（默认 4 = #574 挥刀暴发帧）
#   该值影响什么: 命中宽容度——窗口越长越容易命中，同时拼刀/弹反判定窗口随之变宽
const HITBOX_ACTIVE_FRAMES: int = 4          # # DRAFT
# HITBOX_RANGE
#   只狼基准: 刀长近身判定（横板一维：攻击者 x 与防御者 x 的水平距离阈值，px）
#   候选集: [60, 80, 100]（默认 80 = SWORD_LENGTH=88 派生近似）
#   该值影响什么: 挥空语义——距离外攻击不命中（AC 未覆盖，挥空=不发射事件）
const HITBOX_RANGE: float = 80.0             # # DRAFT
# PARRY_DIRECTION_TOLERANCE
#   只狼基准: 弹反必须面向攻击（背对挨打=受击）
#   候选集: [1=仅同侧（defender 朝向攻击者）, 2=宽容（前后均可）]（默认 1）
#   该值影响什么: 弹反方向判定的严格度——1 防背身无脑弹反
const PARRY_DIRECTION_TOLERANCE: int = 1     # # DRAFT
# ── HUD (#576) ──
# HUD_LOW_HP_RATIO
#   候补值: [0.25, 0.30, 0.35]（默认 0.30）
#   该值影响什么: 低血 vignette 触发阈值（活性条占比，严格小于 + 0.001 容差）
#   情感断言: 命悬一线才见血色——过早是焦虑，过晚是欺骗
const HUD_LOW_HP_RATIO: float = 0.30           # # DRAFT
# HUD_KILL_HINT_SECONDS
#   候补值: [1.0, 1.5, 2.0]（默认 1.5）
#   该值影响什么: 击杀提示停留时长（含淡出）
#   情感断言: 足够读完，不留恋
const HUD_KILL_HINT_SECONDS: float = 1.5       # # DRAFT
# HUD_PLAYER_MARGIN
#   候补值: Vector2(16, 16)
#   该值影响什么: 玩家区块左上角边距
#   情感断言: 贴边不贴屏（细线呼吸感）
const HUD_PLAYER_MARGIN: Vector2 = Vector2(16, 16)  # # DRAFT
# HUD_STANCE_GAP
#   候补值: 6.0
#   该值影响什么: 血条与玩家架势条间距
#   情感断言: 同组相关，不粘连
const HUD_STANCE_GAP: float = 6.0             # # DRAFT
# HUD_BAR_WIDTH
#   候补值: 240.0
#   该值影响什么: 血条/玩家架势条宽度
#   情感断言: 一条线的克制
const HUD_BAR_WIDTH: float = 240.0            # # DRAFT
# HUD_BAR_HEIGHT
#   候补值: 10.0
#   该值影响什么: 血条高
#   情感断言: 细线不抢戏
const HUD_BAR_HEIGHT: float = 10.0            # # DRAFT
# HUD_STANCE_HEIGHT
#   候补值: 6.0
#   该值影响什么: 架势条高（玩家/敌人）
#   情感断言: 比血条更细 = 次级信息
const HUD_STANCE_HEIGHT: float = 6.0          # # DRAFT
# HUD_ENEMY_BAR_WIDTH
#   候补值: 240.0
#   该值影响什么: 敌人架势条宽
#   情感断言: 顶部中央细条（只狼首领条语义）
const HUD_ENEMY_BAR_WIDTH: float = 240.0      # # DRAFT
# HUD_ENEMY_BAR_TOP
#   候补值: 12.0
#   该值影响什么: 敌人架势条顶边距
#   情感断言: 贴顶不悬浮
const HUD_ENEMY_BAR_TOP: float = 12.0         # # DRAFT
# HUD_MOON_WHITE
#   候补值: Color("#e8e6e3")
#   该值影响什么: 常态描边/活性段填充
#   情感断言: 苍白月白（issue body 指定）
const HUD_MOON_WHITE: Color = Color("#e8e6e3") # # DRAFT
# HUD_INK_BLACK
#   候补值: Color("#141414")
#   该值影响什么: 背景/非活性段填充
#   情感断言: 墨黑（issue body 指定）
const HUD_INK_BLACK: Color = Color("#141414")  # # DRAFT
# HUD_BLOOD_RED
#   候补值: Color("#8c2f2f")
#   该值影响什么: 低血点缀（活性段填充+描边）
#   情感断言: 血色只在该出现时出现
const HUD_BLOOD_RED: Color = Color("#8c2f2f")  # # DRAFT
# HUD_HINT_FONT_SIZE
#   候补值: 16
#   该值影响什么: 提示文字字号
#   情感断言: 克制的可读
const HUD_HINT_FONT_SIZE: int = 16             # # DRAFT
# > 处决提示窗口不新增常量——复用 STANCE_BREAK_RECOVERY_SEC=3.0（#584 只读，PRD §4.4 字面）。

# ── AI 分区（# DRAFT 候补值，待 #584 定稿；#581 消费方，禁止实现期定稿）──
# ENEMY_SENSE_RANGE_PX
#   issue body: 视线范围 6m@100px/m
#   候选集: [400, 500, 600]（默认 600 = issue 指定）
#   该值影响什么: 感知水平距离上限——太大=全图索敌，太小=贴脸才发现
#   情感断言: 压迫感来自「被你发现」，不是「满屏都是你」
const ENEMY_SENSE_RANGE_PX: float = 600.0       # # DRAFT
# ENEMY_SENSE_ANGLE_DEG
#   issue body: 视线 120°（半角 60° → cos60°=0.5 点积阈值，派生不重复定义）
#   候选集: [90, 120, 180]（默认 120 = issue 指定）
#   该值影响什么: 视野锥张角——越大越容易发现玩家
#   情感断言: 背对敌人是安全感的来源
const ENEMY_SENSE_ANGLE_DEG: float = 120.0      # # DRAFT
# ENEMY_SENSE_HEIGHT_TOLERANCE
#   候选集: [100, 150, 200]（默认 150 = 平台制高度容忍，MVP 无 raycast）
#   该值影响什么: 高度差容忍——超出则不发现/不追击
#   情感断言: 高低差是走位资源，不是 bug
const ENEMY_SENSE_HEIGHT_TOLERANCE: float = 150.0  # # DRAFT
# ENEMY_PATROL_SPEED
#   候选集: [60, 80, 100]（默认 80 = 火柴人 move 动画节奏）
#   该值影响什么: 巡逻步态速度——太慢无聊，太快不像巡逻
#   情感断言: 雪夜村口的踱步，不急不慢
const ENEMY_PATROL_SPEED: float = 80.0          # # DRAFT
# ENEMY_CHASE_SPEED
#   候选集: [150, 180, 220]（默认 180 = 低于玩家 300 但足够逼近）
#   该值影响什么: 追击压迫感——太快无解，太慢无压迫
#   情感断言: 追得上你的恐惧，追不上的喘息
const ENEMY_CHASE_SPEED: float = 180.0          # # DRAFT
# ENEMY_TURN_DELAY_SEC
#   候选集: [0.1, 0.2, 0.3]（默认 0.2 = 防瞬移转身穿帮）
#   该值影响什么: 转向延迟——转身有过程，不是瞬移
#   情感断言: 敌人也是人，转身需要时间
const ENEMY_TURN_DELAY_SEC: float = 0.2         # # DRAFT
# ENEMY_ATTACK_RANGE
#   候选集: [70, 80, 100]（默认 80 = HITBOX_RANGE 对齐，停距=可命中）
#   该值影响什么: 攻击停距——<= 此距离才出刀
#   情感断言: 贴脸是危险的
const ENEMY_ATTACK_RANGE: float = 80.0          # # DRAFT
# ENEMY_ATTACK_COOLDOWN_SEC
#   候选集: [1.2, 1.5, 2.0]（默认 1.5 = 攻击节奏阀，压迫但不无脑）
#   该值影响什么: 攻击冷却——太快无脑，太慢木桩
#   情感断言: 有呼吸的攻击节奏
const ENEMY_ATTACK_COOLDOWN_SEC: float = 1.5    # # DRAFT
# ENEMY_HP_DAMAGE
#   候选集: [10, 15, 20]（默认 15 = sekiro 敌小兵对玩家伤害基准，100/15≈7 刀击杀）
#   该值影响什么: 敌人命中玩家 HP 伤害
#   情感断言: 七刀之内是紧张，一刀半血是恐惧
const ENEMY_HP_DAMAGE: float = 15.0             # # DRAFT
# ENEMY_HP_MAX
#   候选集: [30, 40, 50]（默认 40 = sekiro 敌小兵 HP 30-50）
#   该值影响什么: 敌人血条上限（life_1_max 注入）
#   情感断言: 小兵是消耗品，不是城墙
const ENEMY_HP_MAX: float = 40.0                # # DRAFT
# ENEMY_THRUST_CHANCE
#   候选集: [0.2, 0.3, 0.5]（默认 0.3 = 突刺 vs 三连砍 决策概率）
#   该值影响什么: 出招风格概率——突刺单发 vs 三连砍连段
#   情感断言: 敌人也会变招，但不多
const ENEMY_THRUST_CHANCE: float = 0.3          # # DRAFT
# ENEMY_RETREAT_CHANCE
#   issue body: 5% 后退回避（AC3 硬约束）
#   候选集: [0.03, 0.05, 0.10]（默认 0.05 = issue 指定）
#   该值影响什么: 玩家出刀时敌人后退概率——反页游木桩的关键
#   情感断言: 敌人会怕，但很少
const ENEMY_RETREAT_CHANCE: float = 0.05        # # DRAFT
# ENEMY_RETREAT_SECONDS
#   候选集: [0.3, 0.5, 0.8]（默认 0.5 = 回避位移时长）
#   该值影响什么: 后退回避持续时间
#   情感断言: 退一步海阔天空，退太久是逃跑
const ENEMY_RETREAT_SECONDS: float = 0.5        # # DRAFT
# ENEMY_RETREAT_TRIGGER_RANGE
#   候选集: [150, 200, 250]（默认 200 = 玩家攻击前摇触发回避的距离）
#   该值影响什么: 回避触发距离
#   情感断言: 刀够得着才会怕
const ENEMY_RETREAT_TRIGGER_RANGE: float = 200.0  # # DRAFT
# ENEMY_PARRY_STUN_SECONDS
#   候选集: [0.4, 0.5, 0.6]（默认 0.5 = AC2 硬直 0.5s，AI 层补足）
#   该值影响什么: 被弹反后 AI 抑制窗时长——不追击不攻击
#   情感断言: 弹反是打断，不是暂停
const ENEMY_PARRY_STUN_SECONDS: float = 0.5     # # DRAFT
# ENEMY_LOSE_SIGHT_RANGE
#   候选集倍数: [1.3, 1.5, 2.0]（默认 1.5× = ENEMY_SENSE_RANGE_PX 派生）
#   该值影响什么: 追击丢失距离——超出回巡逻
#   情感断言: 追丢是战术，不是 bug
const ENEMY_LOSE_SIGHT_RANGE: float = 900.0     # # DRAFT（= ENEMY_SENSE_RANGE_PX × 1.5 派生）
# ENEMY_PATROL_PAUSE_SEC
#   候选集: [0.5, 1.0, 1.5]（默认 1.0 = waypoint 到达停顿）
#   该值影响什么: 巡逻到达停顿时长
#   情感断言: 踱步要有节奏
const ENEMY_PATROL_PAUSE_SEC: float = 1.0       # # DRAFT
# ── 复活 FX 分区（# DRAFT 候补值，待 #584 定稿；#578 消费方，禁止实现期定稿）──
# INK_BURST_COUNT
#   只狼基准: issue body「30-50 黑点」
#   候选集: [30, 40, 50]（默认 40）
#   该值影响什么: 墨点密度——太少无爆开感，太多粘连成雾（实验 1）
#   情感断言: 硬汉再起的干脆爆散，不是雾
const INK_BURST_COUNT: int = 40              # # DRAFT
# INK_BURST_SPEED
#   只狼基准: 实验 1 候选（径向 px/s）
#   候选集: [120, 180, 240]（默认 180）
#   该值影响什么: 扩散速度——太慢成黑雾，太快成烟火（实验 1）
#   情感断言: 有爆散力道又不散架
const INK_BURST_SPEED: float = 180.0         # # DRAFT
# INK_BURST_LIFETIME
#   只狼基准: PRD §4.2「0.3-0.5s」
#   候选集: [0.3, 0.4, 0.5]（默认 0.4）
#   该值影响什么: 粒子存活——0.4s 内淡出，快速衰减不粘连（实验 1）
#   情感断言: 一击即逝的墨迹
const INK_BURST_LIFETIME: float = 0.4        # # DRAFT
# INK_BURST_COLOR
#   只狼基准: = HUD_INK_BLACK（同值互引，零新色相）
#   候选集: —（墨黑固定）
#   该值影响什么: 墨点色——墨黑，禁止彩色粒子（反页游）
#   情感断言: 水墨的克制
#   命名: INK_BURST_* 前缀（#578 复活 FX），与 #582 氛围 INK_COLOR（墨色 #1a1f26）区分——冲突解决重命名（PR #613 merge main）
const INK_BURST_COLOR: Color = Color("#141414")  # # DRAFT
# INK_BURST_SPREAD_DEG
#   只狼基准: 径向爆开语义
#   候选集: [120, 180, 360]（默认 180）
#   该值影响什么: 发射张角——180° 半球爆开（脚底发射），360° 全向（实验 1）
#   情感断言: 从身体迸出，不是四处乱溅
const INK_BURST_SPREAD_DEG: float = 180.0     # # DRAFT
# FLASH_WHITE
#   只狼基准: = HUD_MOON_WHITE（同值互引，零新色相）
#   候选集: —（苍白月白固定）
#   该值影响什么: 闪屏起始色——苍白月白（复用 HUD 色值，零新色相）
#   情感断言: 月光炸开的一瞬
const FLASH_WHITE: Color = Color("#e8e6e3")   # # DRAFT
# FLASH_BLOOD
#   只狼基准: issue body「血 #5a1e1e」
#   候选集: —（issue body 指定）
#   该值影响什么: 闪屏目标色——偏暗红不发亮（禁警报红，实验 2）
#   情感断言: 血色短暂浸染，不是警报
const FLASH_BLOOD: Color = Color("#5a1e1e")   # # DRAFT
# FLASH_SECONDS
#   只狼基准: issue body「0.2s 内」
#   候选集: [0.1, 0.2, 0.3]（默认 0.2）
#   该值影响什么: 闪白→血色时长——≤0.2s 短促（实验 2）
#   情感断言: 一秒都不用就醒过来
const FLASH_SECONDS: float = 0.2              # # DRAFT
# FLASH_HOLD_SECONDS
#   只狼基准: 实验 2 候选
#   候选集: [0.2, 0.3]（默认 0.2）
#   该值影响什么: 血色停留——克制停留 0.2-0.3s，不拖沓（实验 2）
#   情感断言: 足够看清一瞬，不留恋
const FLASH_HOLD_SECONDS: float = 0.2         # # DRAFT
# SLOWMO_HOLD_SECONDS
#   只狼基准: 实验 3 候选（复用 SLOWMO_COEFF=0.2）
#   候选集: [0.3, 0.4, 0.5]（默认 0.4）
#   该值影响什么: 全局降速时长——0.4s 足够读清「刀尖点地」帧（实验 3）
#   情感断言: 世界停一瞬，然后继续
const SLOWMO_HOLD_SECONDS: float = 0.4        # # DRAFT
# INVINCIBLE_FLICKER_HZ
#   只狼基准: 实验 4 候选
#   候选集: [6, 8, 10]（默认 8）
#   该值影响什么: 闪烁频率——8Hz 呼吸感可读，<10Hz 安全区（实验 4）
#   情感断言: 呼吸般的闪烁，不是故障屏闪
const INVINCIBLE_FLICKER_HZ: float = 8.0      # # DRAFT
# INVINCIBLE_FLICKER_ALPHA_MIN
#   只狼基准: 实验 4 候选
#   候选集: [0.2, 0.3, 0.4]（默认 0.3）
#   该值影响什么: 闪烁谷值——0.3 可读不刺眼（实验 4）
#   情感断言: 半透明但从不消失
const INVINCIBLE_FLICKER_ALPHA_MIN: float = 0.3 # # DRAFT

# ── 场景参数（# DRAFT 候补值，定稿 = #583 E2E 截图用户裁决）──
#   分区: 舞台尺寸 STAGE_* / 平台 PLATFORM_* / 色板 *COLOR / 月亮 MOON_* / 物件 HOUSE_* TREE_* MOUNTAIN_*
#   定稿机制: implement PR 附 battle_stage 组 3 shot 截图 → 用户 AC5 裁决（taste-draft；构图/配色归用户）
#   硬约束: 坐标/尺寸声明在 .tscn（本分区为声明参考值，test 断言一致防漂移）；物件 ≤5；零外部贴图

# ── 舞台尺寸（机械常量，骨架期定稿）──
#   候补值: 场景总宽 2400px（issue AC1 字面值）；视觉平台 3 段；高差 60-100px（视觉分层，非碰撞）
#   该值影响什么: 战斗移动空间宽度——2400px > 窗口 1280px，必须配 Camera2D 才能全貌可见
#   情感断言: 横向扁平、屋舍低矮——地雷战乡村空间感（横向构图优先，禁止竖向高塔/城堡）
const STAGE_WIDTH_PX: int = 2400          # AC1: 场景总宽（.tscn 根节点宽度声明参考值）
const STAGE_VISUAL_SEGMENTS: int = 3      # AC1: 雪地平台 3 段（视觉分段，碰撞单一连续面）

# ── 平台（# DRAFT 候补值，待 #583 用户裁决）──
#   候补值: 基准 Y=560（碰撞顶面）；厚度 24px；视觉雪堆深度 60-100px（高低错落 3 段）；相邻段重叠 ≥4px（防缝隙，若改拼接式）
#   该值影响什么: 角色站立高度 + 雪原起伏观感——碰撞面恒定是 AC1「可通行无阻碍」在 velocity.y=0 模型下的唯一严格解
#   情感断言: 雪原起伏但脚下踏实——视觉有高低错落，角色行走零阻塞
const PLATFORM_Y_BASE: float = 560.0          # # DRAFT（碰撞顶面基准 Y）
const PLATFORM_THICKNESS_PX: float = 24.0     # # DRAFT（碰撞体厚度）
const SNOW_DRIFT_DEPTH_MIN: float = 60.0      # # DRAFT（视觉雪堆深度下界，AC1 高差 60px）
const SNOW_DRIFT_DEPTH_MAX: float = 100.0     # # DRAFT（视觉雪堆深度上界，AC1 高差 100px）
const PLATFORM_SEGMENT_OVERLAP_PX: float = 4.0 # # DRAFT（拼接式边缘重叠，防缝隙；单一 shape 时仅作断言参考）

# ── 色板（# DRAFT 候补值，待 #583 用户裁决；与 #582 水墨 INK_COLOR 同色系）──
#   候补值: 墨色系 #4a5664（墙体/枯树/平台剪影；self-correct R1 调亮——#1a1f26 染后 luma 0.055 < 30
#           违反 #624 F3，#4a5664 染后 luma ≈ 39/255 ≥ 30）；雪层冷白 α0.6；月亮冷白 #b8c4d9 同源
#   该值影响什么: 冷墨色调整体观感——AC2 硬约束「整体为冷墨色调」；色板过黑 → 月光染后 luma < 30 违反 #624
#   情感断言: 大地如墨、雪压屋顶——黄土+雪的组合（屋顶压雪、墙体墨色、枯树如骨）
const STAGE_INK_COLOR: Color = Color("#4a5664")   # # DRAFT（墨色主体，染后 luma ≈ 39 ≥ 30，#624 F3）
const SNOW_LAYER_COLOR: Color = Color(0.92, 0.95, 0.98, 0.6)  # # DRAFT（雪层冷白，alpha 0.6 字面约束）
const MOUNTAIN_COLOR: Color = Color("#536171")    # # DRAFT（山峦远景，较主体淡一档）
const MOON_COLOR: Color = Color("#b8c4d9")        # # DRAFT（月亮冷白，同源 MOONLIGHT_COLOR_TARGET）

# ── 月亮（# DRAFT 候补值，待 #583 用户裁决）──
#   候补值: 半径 42px；位置 y≈120-160（苍月悬顶）；光晕强度/半径（taste-draft）
#   该值影响什么: 「苍月悬顶」构图焦点——月亮是场景情绪光源（视觉焦点），染后与 #582 月光色温同源
#   情感断言: 苍月悬顶——冷白月亮是雪夜最亮的视觉锚点，构图焦点而非装饰
const MOON_RADIUS_PX: float = 42.0            # # DRAFT（月亮主体半径）
const MOON_POSITION_Y: float = 140.0          # # DRAFT（苍月悬顶，y<150 区域）
const MOON_GLOW_STRENGTH: float = 0.35        # # DRAFT（光晕峰值 alpha，shader hint_range 上界）
const MOON_GLOW_RADIUS_RATIO: float = 2.2     # # DRAFT（光晕半径 = 主体 × 2.2）

# ── 物件（机械布局参考，坐标在 .tscn 声明）──
#   候补值: 草屋 ×2（屋脊 ≤120px，x≈300/1900）；枯树 ×2（x≈900/1500）；山峦/月亮为背景不计数
#   该值影响什么: 物件预算（≤5 硬约束，防噪杂）+ 空间锚点（玩家方位感）
#   情感断言: 克制——4 件家具/物件是极限，多一件即噪杂（反例: 日式鸟居/西式城堡禁止）
const HOUSE_RIDGE_HEIGHT_MAX: float = 120.0   # 机械常量（屋脊高度上限，低矮扁平）
const OBJECT_BUDGET_MAX: int = 5              # 机械常量（物件 ≤5，issue 硬约束）

# ── 反馈分区（# DRAFT 候补值，定稿 = #584 用户裁决；#579 消费方，禁止实现期定稿）──
# FEEDBACK_SPARK_COUNT:  {S:14, A:18, B:6, C:8}          # 粒子数（issue 矩阵 A 16-20 取 18）
const FEEDBACK_SPARK_COUNT: Dictionary = {"S": 14, "A": 18, "B": 6, "C": 8}
# FEEDBACK_SPARK_COLOR:  Color("#ffd9a0")  # 苍白金（issue 禁橙色页游爆焰）
const FEEDBACK_SPARK_COLOR: Color = Color("#ffd9a0")
# FEEDBACK_HITSTOP_MS:   {S:150, A:90, A_:100, B:30, C:50, PH:60}   # 顿帧时长（≤100ms 不黏腻，S 例外）
const FEEDBACK_HITSTOP_MS: Dictionary = {"S": 150, "A": 90, "A_": 100, "B": 30, "C": 50, "PH": 60}
# FEEDBACK_SHAKE_PX:     {S:4.0, A:3.0, A_:3.0, B:1.0, C:2.0, PH:4.0}  # 屏震幅值（沿攻击方向）
const FEEDBACK_SHAKE_PX: Dictionary = {"S": 4.0, "A": 3.0, "A_": 3.0, "B": 1.0, "C": 2.0, "PH": 4.0}
# FEEDBACK_SLOWMO:       {S:{scale:0.05, ms:500}, A:{scale:0.3, ms:200}, A_:{scale:0.5, ms:300}}
#                        # 慢动作仅 S/A/A- 级（issue: 滥用失去重量 = AC5）
const FEEDBACK_SLOWMO: Dictionary = {
    "S": {"scale": 0.05, "ms": 500},
    "A": {"scale": 0.3,  "ms": 200},
    "A_": {"scale": 0.5, "ms": 300},
}
# FEEDBACK_FLASH:        {A:{alpha:0.35, ms:120}, A_:{alpha:0.25, ms:100}}  # 实体闪/全屏淡闪
const FEEDBACK_FLASH: Dictionary = {"A": {"alpha": 0.35, "ms": 120}, "A_": {"alpha": 0.25, "ms": 100}}
# FEEDBACK_TIME_MAX_STACK: 3    # 时间栈深度上限（超限丢弃新 push 保旧恢复）
const FEEDBACK_TIME_MAX_STACK: int = 3
# FEEDBACK_SPARK_Z_INDEX: -1     # 火花层级 < 角色层（粒子不盖角色红线，单测断言）
const FEEDBACK_SPARK_Z_INDEX: int = -1
# FEEDBACK_SPARK_VELOCITY/LIFETIME: {S:{vel:260,lifetime:0.5}, A:{vel:240,lifetime:0.45}, B:{vel:140,lifetime:0.3}, C:{vel:170,lifetime:0.35}}  # # DRAFT 候补
const FEEDBACK_SPARK_VELOCITY: Dictionary = {"S": 260.0, "A": 240.0, "B": 140.0, "C": 170.0}  # # DRAFT
const FEEDBACK_SPARK_LIFETIME: Dictionary = {"S": 0.5, "A": 0.45, "B": 0.3, "C": 0.35}  # # DRAFT
# FEEDBACK_SHAKE_DECAY: 3.0   # 屏震指数衰减系数（trauma -= trauma * decay * delta）
const FEEDBACK_SHAKE_DECAY: float = 3.0  # # DRAFT
# FEEDBACK_ENTITY_FLASH_FACTOR: 5.0  # 实体白闪 modulate 倍乘（深色火柴人也冲白）
const FEEDBACK_ENTITY_FLASH_FACTOR: float = 5.0  # # DRAFT

# ── 处决演出（# DRAFT 候补值，定稿归 #584/用户；#580 消费方，禁止实现期定稿）──
# EXECUTE_SLOWMO_SCALE / EXECUTE_SLOWMO_MS
#   三处候选归拢（PRD §1.5，禁止二选一偷定）: issue body 0.1/0.6s vs #579 S 级 0.05/0.5s vs constants 默认 0.2/0.4s
#   机制消费方 = #579 S 级矩阵（FEEDBACK_SLOWMO["S"]）；本分区为候选登记，定稿时由 #584 改 FEEDBACK_SLOWMO
const EXECUTE_SLOWMO_SCALE: Array = [0.05, 0.1, 0.2]      # # DRAFT（候选集）
const EXECUTE_SLOWMO_MS: Array = [400, 500, 600]          # # DRAFT（候选集）
# EXECUTE_INVINCIBLE_SECONDS
#   候选集: [1.0, 1.5, 2.0]（默认 1.5；覆盖 execute 5 帧 + 淡出 0.3s 有余）
#   情感断言: 处决是「赢了一场艰难的仗」的奖励时刻——无敌窗口给足演出呼吸，不耍赖
const EXECUTE_INVINCIBLE_SECONDS: float = 1.5             # # DRAFT
# EXECUTE_FADE_SECONDS
#   issue body: modulate alpha 1→0 0.3s 如墨迹消散
const EXECUTE_FADE_SECONDS: float = 0.3                   # # DRAFT
# EXECUTE_RANGE_PX
#   派生: = EXECUTE_RANGE(1.2m) × 100px/m（# DRAFT 比例，与 HITBOX_RANGE=80px 同量级）
#   候选集: [100, 120, 150]（默认 120）
const EXECUTE_RANGE_PX: float = 120.0                     # # DRAFT
# EXECUTE_EXHAUSTED_SECONDS / EXECUTE_RECOVER_RATIO / EXECUTE_EXHAUST_MULTIPLIER
#   AC3: 崩解后 3s 未处决 → 起身恢复 50% 架势 + 5s 疲惫（受架势伤害 +20%）
const EXECUTE_EXHAUSTED_SECONDS: float = 5.0              # # DRAFT
const EXECUTE_RECOVER_RATIO: float = 0.5                  # # DRAFT
const EXECUTE_EXHAUST_MULTIPLIER: float = 1.2             # # DRAFT

# ── 组装编排（# DRAFT 候补值，定稿归 #584/用户；#585 消费方，禁止实现期定稿）──
# AFTERGLOW_SECONDS
#   AC3: 击杀后场景空闲 ≥5s 情绪余韵，雪花持续（Atmosphere 无暂停路径，天然持续）
#   候选集: [5.0, 6.0, 8.0]（默认 5.0；MVP 收束节奏，最短满足 AC3 字面）
const AFTERGLOW_SECONDS: float = 5.0             # # DRAFT
# FAIL_SUBTITLE_DELAY / FAIL_SUBTITLE_FADE_SECONDS
#   AC2: 死亡反馈（白闪/屏震 #579）播完后 ≥0.5s 字幕淡入 1s
#   候选集: delay [0.3, 0.5, 1.0] / fade [0.8, 1.0, 1.5]（默认 0.5 / 1.0）
const FAIL_SUBTITLE_DELAY: float = 0.5           # # DRAFT
const FAIL_SUBTITLE_FADE_SECONDS: float = 1.0    # # DRAFT
# TUTORIAL_HINT_DELAY
#   情绪弧「教学」: 开局 3s 内浮现操作提示（移动/攻击/格挡键位）
#   候选集: [2.0, 3.0, 5.0]（默认 3.0）
const TUTORIAL_HINT_DELAY: float = 3.0           # # DRAFT
# FAIL_SUBTITLE_CANDIDATES: B5 失败表达候选 5 选 1（taste-draft 进 PR 待用户定稿，实现期禁止裁决）
const FAIL_SUBTITLE_CANDIDATES: Array = [
    "雪落无声。村口只剩你。",
    "雪还在下。村口没人了。",
    "灯灭了。雪落无声。",
    "村口只剩下雪。",
    "刀还在。你没了。",
]
# TUTORIAL_HINT_CANDIDATES: 教学提示文案候选（taste-draft 进 PR 待用户定稿，实现期禁止裁决）
const TUTORIAL_HINT_CANDIDATES: Array = [
    "村口有动静。握紧你的刀。",
    "←→ 移动 · J 攻击 · K 格挡",
    "雪夜村口，有人来了。",
]
