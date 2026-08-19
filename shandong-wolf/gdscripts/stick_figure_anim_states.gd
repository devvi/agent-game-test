extends RefCounted
## StickFigureAnimStates — 火柴人动画状态对象集（#574）。
## 归属: docs/DESIGN/574-stick-figure-silhouette-animation.md §2.4（动画状态对象）
## 职责边界: 本文件【不是战斗状态机】——战斗状态机权威归 #575（注释互引）。
##   本层 = 「动画层最小调度」: 每态 enter() 调 controller.play_clip(clip)，
##   update(delta) 转发推进（Attack 态维护 phase: 0 前摇 / 1 暴发 / 2 收招）。
##   状态对象基于 StateMachineBase（state_machine.gd）派生（RefCounted 内部类）。
## 派生约定: 11 个动画状态对象 = AnimStateIdle/Move/Attack/HeavyAttack/Guard/
##   ParrySuccess/Stagger/StanceBreak/Execute/Revive/Dead。
## 说明: controller 在 consume_state() 内创建状态对象并喂给其 StateMachineBase，
##   enter() → play_clip 即完成动画切换（同态重入在 play_clip 内重置前摇首帧）。

const StateMachineBaseScript = preload("res://gdscripts/state_machine.gd")

const ANIM_CLIP_NAMES: Dictionary = {
	"idle": "anim_idle",
	"move": "anim_move",
	"attack": "anim_attack",
	"heavy_attack": "anim_heavy_attack",
	"guard": "anim_guard",
	"parry_success": "anim_parry_success",
	"stagger": "anim_stagger",
	"stance_break": "anim_stance_break",
	"execute": "anim_execute",
	"revive": "anim_revive",
	"dead": "anim_dead",
}


## 工厂: canonical 状态名 → 对应动画状态对象（未知 → idle 兜底）
static func make_state(state_name: String, controller: Object) -> Object:
	match state_name:
		"idle":
			return AnimStateIdle.new(controller)
		"move":
			return AnimStateMove.new(controller)
		"attack":
			return AnimStateAttack.new(controller)
		"heavy_attack":
			return AnimStateHeavyAttack.new(controller)
		"guard":
			return AnimStateGuard.new(controller)
		"parry_success":
			return AnimStateParrySuccess.new(controller)
		"stagger":
			return AnimStateStagger.new(controller)
		"stance_break":
			return AnimStateStanceBreak.new(controller)
		"execute":
			return AnimStateExecute.new(controller)
		"revive":
			return AnimStateRevive.new(controller)
		"dead":
			return AnimStateDead.new(controller)
		_:
			return AnimStateIdle.new(controller)


## 供 #575 战斗状态机复用姿态命名/阶段标记（注释互引，替换成本低）
static func clip_for_state(state_name: String) -> String:
	return ANIM_CLIP_NAMES.get(state_name, "anim_idle")


class AnimStateBase:
	extends RefCounted
	## 三接口契约（StateMachineBase: enter/exit/update）
	var controller: Object = null

	func _init(ctrl: Object) -> void:
		controller = ctrl

	func enter() -> void:
		pass

	func exit() -> void:
		pass

	func update(_delta: float) -> void:
		pass


class AnimStateIdle:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_idle")


class AnimStateMove:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_move")


class AnimStateAttack:
	extends AnimStateBase
	## Attack 态: 维护 phase（0 前摇 / 1 暴发 / 2 收招）；暴发段首帧的刀光触发由
	## anim_attack clip 的 method track 在 8/60s 处调用 SwordArc.trigger_burst()（§2.3）
	var phase: int = 0
	var _burst_start: float = 0.0
	var _burst_end: float = 0.0

	func enter() -> void:
		controller.play_clip("anim_attack")
		phase = 0
		_burst_start = controller.attack_windup_end
		_burst_end = controller.attack_burst_end

	func update(_delta: float) -> void:
		var pos: float = controller.get_animation_position()
		if pos >= _burst_end:
			phase = 2
		elif pos >= _burst_start:
			phase = 1
		else:
			phase = 0


class AnimStateHeavyAttack:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_heavy_attack")


class AnimStateGuard:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_guard")


class AnimStateParrySuccess:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_parry_success")


class AnimStateStagger:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_stagger")


class AnimStateStanceBreak:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_stance_break")


class AnimStateExecute:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_execute")


class AnimStateRevive:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_revive")


class AnimStateDead:
	extends AnimStateBase

	func enter() -> void:
		controller.play_clip("anim_dead")
