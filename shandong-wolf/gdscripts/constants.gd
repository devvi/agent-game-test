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
