extends Node2D
## E2EStickFigureCapture — 火柴人动画截图像具驱动（#574）。
## 归属: docs/DESIGN/574-stick-figure-silhouette-animation.md §2.7（E2E 截图 + 驱动契约）
## 职责（AC4）: 提供「可被 e2e_capture.gd 驱动」的截图场景——角色摆进画面、
##   每个动画状态可注入触发、状态可轮询。不修改 Main.tscn（PRD §8.3 独立测试场景）。
##
## 驱动契约（与 framework/templates/e2e_capture.gd 兼容）:
##   - current_state: int 属性（IDLE=0 … DEAD=11）——shot plan 的 state_node/state_property 轮询目标
##   - digit 键 1-9/0 映射 → consume_state(...)（_unhandled_input；attack 三段为 3 个独立 shot state，
##     由 attack 序列的动画相位派生: WINDUP→BURST→RECOVERY）
##   - auto_cycle 兜底（DESIGN §2.7 回退路径）: e2e_capture.gd 的 press 仅支持 enter/space/esc/方向键，
##     digit 键注入不兼容 → shot plan 经 autoplay.tweaks 开启 auto_cycle（每态停留 auto_cycle_frames 帧
##     自循环），capture 驱动只轮询 current_state 截图，零游戏代码改动。
##
## digit → canonical 状态映射（1-9/0 共 10 键；attack 触发后由相位派生出 3 个 shot state）:
##   0→idle 1→move 2→attack 3→guard 4→parry_success 5→stagger
##   6→stance_break 7→execute 8→revive 9→dead

class_name E2EStickFigureCapture

const C = preload("res://gdscripts/constants.gd")
const PlayerScene = preload("res://scenes/player_stick_figure.tscn")

enum {
	IDLE = 0,
	MOVE = 1,
	ATTACK_WINDUP = 2,
	ATTACK_BURST = 3,
	ATTACK_RECOVERY = 4,
	GUARD = 5,
	PARRY_SUCCESS = 6,
	STAGGER = 7,
	STANCE_BREAK = 8,
	EXECUTE = 9,
	REVIVE = 10,
	DEAD = 11,
}

## digit 键（1-9/0）→ canonical 状态名
const DIGIT_TO_STATE: Dictionary = {
	KEY_0: "idle",
	KEY_1: "move",
	KEY_2: "attack",
	KEY_3: "guard",
	KEY_4: "parry_success",
	KEY_5: "stagger",
	KEY_6: "stance_break",
	KEY_7: "execute",
	KEY_8: "revive",
	KEY_9: "dead",
}

## canonical → current_state 枚举值（attack 由相位派生，不在表中）
const CANONICAL_TO_STATE: Dictionary = {
	"idle": IDLE,
	"move": MOVE,
	"guard": GUARD,
	"parry_success": PARRY_SUCCESS,
	"stagger": STAGGER,
	"stance_break": STANCE_BREAK,
	"execute": EXECUTE,
	"revive": REVIVE,
	"dead": DEAD,
}

## auto-cycle 状态序列（attack 作为 3 相位整体，停留期间相位派生 WINDUP/BURST/RECOVERY）
const CYCLE_SEQUENCE: Array = [IDLE, MOVE, ATTACK_WINDUP, GUARD, PARRY_SUCCESS, STAGGER, STANCE_BREAK, EXECUTE, REVIVE, DEAD]

var current_state: int = IDLE

@export var auto_cycle: bool = false
@export var auto_cycle_frames: int = 30

var _player: Node2D = null
var _attack_seq_active: bool = false
var _cycle_index: int = 0
var _cycle_frames_left: int = 0


func _ready() -> void:
	_player = get_node_or_null("Player")
	if _player == null:
		push_warning("E2EStickFigureCapture: missing child 'Player'")
	_cycle_frames_left = auto_cycle_frames
	_drive_state("idle")


func _unhandled_input(event: InputEvent) -> void:
	## digit 键 1-9/0 → consume_state（attack 三段由动画相位派生为独立 shot state）
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		if DIGIT_TO_STATE.has(key):
			_drive_state(DIGIT_TO_STATE[key])
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if auto_cycle:
		_cycle_frames_left -= 1
		if _cycle_frames_left <= 0:
			_advance_cycle()
	_update_attack_phase()


func _drive_state(canonical: String) -> void:
	## 注入 canonical 状态: attack 启动攻击序列（相位派生）；其余直接置 current_state + consume
	if _player == null:
		return
	if canonical == "attack":
		_attack_seq_active = true
		_player.consume_state("attack")
		return
	_attack_seq_active = false
	current_state = CANONICAL_TO_STATE.get(canonical, IDLE)
	_player.consume_state(canonical)


func _update_attack_phase() -> void:
	## attack 序列中: 依动画当前相位把 current_state 派生为 WINDUP/BURST/RECOVERY；
	## 动画播完 → 回到 IDLE
	if not _attack_seq_active or _player == null:
		return
	var pos: float = _player.get_animation_position()
	if not _player.is_animation_playing():
		_attack_seq_active = false
		current_state = IDLE
		return
	if pos < _player.attack_windup_end:
		current_state = ATTACK_WINDUP
	elif pos < _player.attack_burst_end:
		current_state = ATTACK_BURST
	else:
		current_state = ATTACK_RECOVERY


func _advance_cycle() -> void:
	## auto-cycle 兜底: 依 CYCLE_SEQUENCE 推进；attack 单元停留 = 基础帧 + 攻击全长 + 余量
	_cycle_frames_left = auto_cycle_frames
	var target: int = CYCLE_SEQUENCE[_cycle_index]
	_cycle_index = (_cycle_index + 1) % CYCLE_SEQUENCE.size()
	if target == ATTACK_WINDUP:
		if _player != null:
			var attack_frames: int = int(round(_player.attack_total_end * float(C.FRAME_RHYTHM_BASE)))
			_cycle_frames_left = auto_cycle_frames + attack_frames + 5
			_drive_state("attack")
	else:
		var canonical: String = _canonical_for_state(target)
		_drive_state(canonical)


func _canonical_for_state(state: int) -> String:
	match state:
		MOVE:
			return "move"
		GUARD:
			return "guard"
		PARRY_SUCCESS:
			return "parry_success"
		STAGGER:
			return "stagger"
		STANCE_BREAK:
			return "stance_break"
		EXECUTE:
			return "execute"
		REVIVE:
			return "revive"
		DEAD:
			return "dead"
		_:
			return "idle"
