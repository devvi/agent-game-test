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

# ── 动画帧节奏与骨骼几何（# DRAFT 候补值，待 #584 定稿）──
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
