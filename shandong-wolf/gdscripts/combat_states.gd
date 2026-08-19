extends RefCounted
## CombatStates — 战斗状态对象集（#575）。
## 归属: docs/DESIGN/575-combat-entity-state-machine.md §2.3（战斗状态对象）
## 职责边界: 基于 StateMachineBase（state_machine.gd）三接口派生: enter/exit/update。
##   状态名权威集见 combat_state_table.gd CANONICAL_STATES（与 #574 consume_state 逐字对齐）。
## 定时状态（帧/秒常量驱动）在 update() 内经 entity.request_transition("idle") 自动退出；
##   禁止在 enter() 内发起转移（StateMachineBase 防重入锁红线，一律延迟到 update 帧计数自然退出）。
## 同态重入钩子: restart()（仅 CombatStateAttack 实现）——attack 收招 phase 重置帧计数 = 连段。

const StateMachineBaseScript = preload("res://gdscripts/state_machine.gd")
const C = preload("res://gdscripts/constants.gd")

## 工厂: canonical 状态名 → 对应战斗状态对象（未知 → idle 兜底）
static func make_state(state_name: String, entity: Object) -> Object:
	match state_name:
		"idle":
			return CombatStateIdle.new(entity)
		"move":
			return CombatStateMove.new(entity)
		"attack":
			return CombatStateAttack.new(entity)
		"heavy_attack":
			return CombatStateHeavyAttack.new(entity)
		"guard":
			return CombatStateGuard.new(entity)
		"parry_success":
			return CombatStateParrySuccess.new(entity)
		"stagger":
			return CombatStateStagger.new(entity)
		"stance_break":
			return CombatStateStanceBreak.new(entity)
		"execute":
			return CombatStateExecute.new(entity)
		"revive":
			return CombatStateRevive.new(entity)
		"dead":
			return CombatStateDead.new(entity)
		_:
			return CombatStateIdle.new(entity)


class CombatStateBase:
	extends RefCounted
	## 三接口契约（StateMachineBase: enter/exit/update）+ restart 同态重入钩子
	var entity: Object = null        # CombatEntity 引用（转移统一走 entity.request_transition）
	var _elapsed: float = 0.0        # 定时状态帧计数累加（秒）

	func _init(ent: Object) -> void:
		entity = ent

	func enter() -> void:
		_elapsed = 0.0               # 进入即重置计时（同态重入 restart 也走 enter 重置）

	func exit() -> void:
		pass

	func update(_delta: float) -> void:
		pass

	## 可选钩子: 同态重入时由 entity.request_transition 调用（仅 AttackState 实现连段）
	func restart() -> void:
		pass


class CombatStateIdle:
	extends CombatStateBase
	## idle: 无行为，等待外部转移；不自动退出


class CombatStateMove:
	extends CombatStateBase
	## move: 位移由 PlayerController 负责（#573），本层只占状态名；不自动退出
	##   （轴归零 → idle 由实体输入桥驱动）


class CombatStateAttack:
	extends CombatStateBase
	## attack: 帧计数三段 phase（0 前摇 / 1 暴发 / 2 收招）；累计 WINDUP+RECOVERY(22) 帧自动退出 → idle。
	##   restart(): 仅收招 phase 重置 _elapsed = 连段成立；前摇/暴发 phase 忽略（防无脑连打）
	func _phase() -> int:
		var frame: int = int(_elapsed * float(C.FRAME_RHYTHM_BASE))
		var windup: int = int(C.FRAME_ATTACK_WINDUP)
		if frame >= windup + 4:
			return 2
		if frame >= windup:
			return 1
		return 0

	func update(delta: float) -> void:
		_elapsed += delta
		var total_frames: int = int(C.FRAME_ATTACK_WINDUP) + int(C.FRAME_ATTACK_RECOVERY)
		if _elapsed >= float(total_frames) / float(C.FRAME_RHYTHM_BASE):
			entity.request_transition("idle")

	func restart() -> void:
		if _phase() == 2:
			_elapsed = 0.0


class CombatStateHeavyAttack:
	extends CombatStateBase
	## heavy_attack: 帧计数累计 22 帧自动退出 → idle（复用 WINDUP+RECOVERY，无专属常量，# DRAFT 待 #584）
	func update(delta: float) -> void:
		_elapsed += delta
		var total_frames: int = int(C.FRAME_ATTACK_WINDUP) + int(C.FRAME_ATTACK_RECOVERY)
		if _elapsed >= float(total_frames) / float(C.FRAME_RHYTHM_BASE):
			entity.request_transition("idle")


class CombatStateGuard:
	extends CombatStateBase
	## guard: 持续姿态；架势回复/扣减归 #577 判定层（take_stance_damage）驱动；不自动退出
	##   （guard 释放 → idle 由实体输入桥驱动）


class CombatStateParrySuccess:
	extends CombatStateBase
	## parry_success: 弹反成功瞬间帧（硬直窗口），PARRY_SUCCESS_FRAMES 后自动退出 → idle
	func update(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= float(C.PARRY_SUCCESS_FRAMES) / float(C.FRAME_RHYTHM_BASE):
			entity.request_transition("idle")


class CombatStateStagger:
	extends CombatStateBase
	## stagger: 受击硬直，STAGGER_FRAMES 后自动退出 → idle
	func update(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= float(C.STAGGER_FRAMES) / float(C.FRAME_RHYTHM_BASE):
			entity.request_transition("idle")


class CombatStateStanceBreak:
	extends CombatStateBase
	## stance_break: 崩解失衡，STANCE_BREAK_RECOVERY_SEC 后自动退出 → idle
	##   （期间 #580 可经 request_transition("execute") 抢先处决）
	func update(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= float(C.STANCE_BREAK_RECOVERY_SEC):
			entity.request_transition("idle")


class CombatStateExecute:
	extends CombatStateBase
	## execute: 处决演出，FRAME_ANIM_EXECUTE_TOTAL 帧后自动退出 → idle（执行中无敌，§5 边界 6）
	func update(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= float(C.FRAME_ANIM_EXECUTE_TOTAL) / float(C.FRAME_RHYTHM_BASE):
			entity.request_transition("idle")


class CombatStateRevive:
	extends CombatStateBase
	## revive: 复活演出，REVIVE_SECONDS 后自动退出 → idle
	##   （hp_2 初始化/无敌开启在 entity.revive() 完成，#578 契约）
	func update(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= float(C.REVIVE_SECONDS):
			entity.request_transition("idle")


class CombatStateDead:
	extends CombatStateBase
	## dead: 状态机停摆，不自动退出（仅 entity.revive() 驱动 dead→revive 转移）
