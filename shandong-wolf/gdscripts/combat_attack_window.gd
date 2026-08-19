extends RefCounted
class_name AttackWindow
## AttackWindow — 单次攻击的命中判定窗口描述器 (#577)。
## 归属: docs/DESIGN/577-parry-clash-stance-break.md §2.2
## 职责: 纯数据容器（无节点、无逻辑分支，headless 免树 new）——CombatJudge 消费
##   is_active(frame) 判定命中帧；#581 敌AI 与玩家攻击共用本窗口契约。
## 帧约定: hit_frame = start_frame + FRAME_ATTACK_WINDUP；
##   有效区间 [hit_frame, hit_frame + active_frames] 闭区间（含端点，@60fps 逻辑帧）。

const C = preload("res://gdscripts/constants.gd")

var attacker         # 攻击者引用（untyped Object；headless class_name 解析不可靠，不类型化）
var start_frame: int     # 攻击开始帧（进入 attack/heavy_attack 态帧，判定器逻辑帧计数）
var active_frames: int   # 判定有效帧数（HITBOX_ACTIVE_FRAMES # DRAFT）
var hp_damage: float     # 命中 HP 伤害（玩家 SWORD_DAMAGE_LIGHT/HEAVY；敌人 #581 配置）
var stance_damage: float # 命中架势伤害（POSTURE_HIT_COST # DRAFT）
var direction: int       # 攻击方向（-1/1 = 攻击者 facing 快照；命中瞬间 facing 校验用）
var windup_frames: int = -1     # -1 → 回退 FRAME_ATTACK_WINDUP（玩家窗口零变化）；敌人 = ENEMY_ATTACK_WINDUP

## 命中判定起始帧（闭区间下界）: start_frame + windup_frames（>=0 时）或 FRAME_ATTACK_WINDUP（回退）
func hit_frame() -> int:
	var w: int = windup_frames if windup_frames >= 0 else int(C.FRAME_ATTACK_WINDUP)
	return start_frame + w

## 有效区间判定（闭区间含端点）: frame ∈ [hit_frame, hit_frame + active_frames]
func is_active(frame: int) -> bool:
	return frame >= hit_frame() and frame <= hit_frame() + active_frames

## 过期判定: frame > hit_frame + active_frames（判定器据此清理窗口）
func is_expired(frame: int) -> bool:
	return frame > hit_frame() + active_frames
