extends RefCounted
class_name CombatStateTable
## CombatStateTable — 11 态战斗状态转移合法性表（#575）。
## 归属: docs/DESIGN/575-combat-entity-state-machine.md §2.2（转移拓扑权威集）
## 职责: 数据驱动 Dictionary + 查询 API，无状态无逻辑分支。
## 状态名权威集 CANONICAL_STATES 与 #574 consume_state 的 ANIM_CLIP_NAMES 键集逐字对齐
##   （禁止自造状态名：parry 单列 / run 代替 move 均为红线）。
## 语义要点（红线案例显式列出）:
##   - stance_break → attack/heavy_attack/guard 表外 = reject（崩解失衡不可攻击/格挡）
##   - dead → 除 revive 外全部表外 = reject（状态机停摆，仅复活可出）
##   - guard → stance_break 表内（格挡中崩解 = 失衡，优先级高于格挡姿态）
##   - guard → parry_success 表内（#577 弹反成功驱动入口）
##   - stagger → stance_break 表内（硬直中崩解 = 失衡，优先级高于硬直，与 guard 同构 #577）
##   - parry_success → stance_break 表内（弹反窗口内 clash 扣架势归零同样失衡）
##   - attack → attack 表内（连段拓扑合法；条件合法性 = request_transition 同态 restart 钩子）

## 11 态转移拓扑（canonical 状态名权威集，与 #574 ANIM_CLIP_NAMES 键集逐字对齐）
const CANONICAL_STATES: Array[String] = [
	"idle", "move", "attack", "heavy_attack", "guard", "parry_success",
	"stagger", "stance_break", "execute", "revive", "dead",
]

## from -> [to, ...]；表外转移一律非法
const TRANSITIONS: Dictionary = {
	"idle": ["move", "attack", "heavy_attack", "guard", "stagger", "stance_break", "parry_success", "dead"],
	"move": ["idle", "attack", "heavy_attack", "guard", "stagger", "stance_break", "parry_success", "dead"],
	"attack": ["attack", "idle", "stagger", "stance_break", "dead"],   # attack→attack = 连段（同态重入钩子）
	"heavy_attack": ["idle", "stagger", "stance_break", "dead"],
	"guard": ["idle", "attack", "heavy_attack", "stance_break", "dead", "parry_success"],
	"parry_success": ["idle", "attack", "heavy_attack", "move", "stance_break"],
	"stagger": ["idle", "dead", "stance_break"],
	"stance_break": ["idle", "execute", "dead"],
	"execute": ["idle"],
	"revive": ["idle"],
	"dead": ["revive"],                                              # 状态机停摆：仅复活可出
}

static func is_legal(from: String, to: String) -> bool:
	var allowed: Array = TRANSITIONS.get(from, [])
	return allowed.has(to)
