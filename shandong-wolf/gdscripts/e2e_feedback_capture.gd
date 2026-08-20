extends Node2D
class_name E2EFeedbackCapture
## E2EFeedbackCapture — 打击反馈截图 rig（#579，AC2/AC6）。
## 归属: docs/DESIGN/579-combat-feedback-system.md §2.6
## 职责: 提供「可被 e2e_capture.gd 驱动」的反馈截图场景——双火柴人 + ReactionController，
##   三档效果（parry_success / stance_broken / execute）可注入触发、current_state 可轮询。
## 驱动契约（与 #574 CaptureRig 兼容）:
##   - current_state: int（IDLE=0 / PARRY_SUCCESS=1 / STANCE_BREAK=2 / EXECUTE=3 / HIT_LANDED=4）
##     —— shot plan 的 state_node/state_property 轮询目标
##   - inject_feedback(event) 公开方法: 推导刀与刀交点 + 法线，转 _controller.trigger_feedback
##   - digit 键（_unhandled_input，沿用 #574 模式）: 4→parry_success / 6→stance_broken /
##     7→execute / 2→hit_landed
##   - auto_cycle 兜底: 依 CYCLE_SEQUENCE 每 auto_cycle_frames 帧自循环（shot plan autoplay 开启）
##   - 冻结效果帧模式（AC2 决定性兜底）: freeze_effects 开启 → 时间栈墙钟不推进，
##     hit-stop 保持冻结、火花/白闪停留画面供截图
## 双火柴人由本 rig _ready 代码创建（零 .tscn 美术资产，复用 player_stick_figure.tscn）。

const PlayerScene = preload("res://scenes/player_stick_figure.tscn")

enum {
	IDLE = 0,
	PARRY_SUCCESS = 1,
	STANCE_BREAK = 2,
	EXECUTE = 3,
	HIT_LANDED = 4,
}

## auto-cycle 状态序列（IDLE → 三档效果 → 回到 IDLE）
const CYCLE_SEQUENCE: Array = [IDLE, PARRY_SUCCESS, STANCE_BREAK, EXECUTE]

## event → current_state 枚举值
const EVENT_TO_STATE: Dictionary = {
	"parry_success": PARRY_SUCCESS,
	"stance_broken": STANCE_BREAK,
	"execute": EXECUTE,
	"hit_landed": HIT_LANDED,
}

## current_state → event（auto_cycle 推进用；IDLE 无事件）
const STATE_TO_EVENT: Dictionary = {
	PARRY_SUCCESS: "parry_success",
	STANCE_BREAK: "stance_broken",
	EXECUTE: "execute",
}

const DEFAULT_IMPACT_POS: Vector2 = Vector2(640, 300)

var current_state: int = IDLE

@export var auto_cycle: bool = false
@export var auto_cycle_frames: int = 30
@export var freeze_effects: bool = false

var _controller = null
var _player: Node2D = null
var _enemy: Node2D = null
var _cycle_index: int = 0
var _cycle_frames_left: int = 0


func _ready() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "Player"
	_player.position = Vector2(420, 400)
	add_child(_player)
	_enemy = PlayerScene.instantiate()
	_enemy.name = "Enemy"
	_enemy.position = Vector2(860, 400)
	add_child(_enemy)
	_controller = get_node_or_null("ReactionController")
	if _controller == null:
		push_warning("E2EFeedbackCapture: missing child 'ReactionController'")
	else:
		var cam: Camera2D = get_node_or_null("Camera2D")
		if cam != null:
			_controller.camera_path = cam.get_path()
	_cycle_frames_left = auto_cycle_frames


func inject_feedback(event: String) -> void:
	## 事件注入: 刀与刀交点（SwordPivot 中点，AC3）+ 法线 Vector2(0,-1) → trigger_feedback。
	## freeze_effects 开启 → 冻结时间栈（hit-stop 停留画面供截图，AC2 兜底）。
	if _controller == null:
		return
	var data: Dictionary = {
		"position": _impact_pos(),
		"normal": Vector2(0, -1),
		"target_entity": _enemy,
		"attacker_entity": _player,
		"source": "test",
	}
	_controller.trigger_feedback(event, data)
	current_state = int(EVENT_TO_STATE.get(event, IDLE))
	if freeze_effects:
		_controller.freeze_time_stack = true


func _unhandled_input(event: InputEvent) -> void:
	## digit 键注入（4→parry_success / 6→stance_broken / 7→execute / 2→hit_landed）
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		match key:
			KEY_4:
				inject_feedback("parry_success")
				get_viewport().set_input_as_handled()
			KEY_6:
				inject_feedback("stance_broken")
				get_viewport().set_input_as_handled()
			KEY_7:
				inject_feedback("execute")
				get_viewport().set_input_as_handled()
			KEY_2:
				inject_feedback("hit_landed")
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	## 仅 auto_cycle 兜底轮询（E2E 具驱动，非战斗逻辑）
	if auto_cycle:
		_cycle_frames_left -= 1
		if _cycle_frames_left <= 0:
			_advance_cycle()


func _advance_cycle() -> void:
	_cycle_frames_left = auto_cycle_frames
	var target: int = CYCLE_SEQUENCE[_cycle_index]
	_cycle_index = (_cycle_index + 1) % CYCLE_SEQUENCE.size()
	if target == IDLE:
		current_state = IDLE
		return
	inject_feedback(STATE_TO_EVENT[target])


func _impact_pos() -> Vector2:
	## 两 SwordPivot 全局位置中点（刀与刀交点）；缺失 → 固定默认值
	var p_pivot: Node = _sword_pivot(_player)
	var e_pivot: Node = _sword_pivot(_enemy)
	if p_pivot != null and e_pivot != null:
		return (p_pivot.global_position + e_pivot.global_position) / 2.0
	return DEFAULT_IMPACT_POS


func _sword_pivot(figure: Node2D) -> Node:
	if figure == null:
		return null
	var pivot: Node = figure.get_node_or_null("StickFigure/TorsoPivot/SwordPivot")
	if pivot == null:
		pivot = figure.get_node_or_null("TorsoPivot/SwordPivot")
	return pivot
