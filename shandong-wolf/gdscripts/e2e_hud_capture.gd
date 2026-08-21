extends Node2D
class_name E2EHudCapture
## E2EHudCapture — HUD 截图像具驱动（#576）。
## 归属: docs/DESIGN/576-hud-stance-bars.md §2.3（E2E 截图 + 驱动契约）
## 职责（AC3）: 提供「可被 e2e_capture.gd 驱动」的截图场景——HUD 4 态可注入、
##   current_state 可轮询、auto_cycle 兜底。零战斗场景依赖——直接走 Hud 公有
##   debug API（set_debug_* / show_debug_hint），信号源（#577/#580）未合入也能截全。
##
## 驱动契约（与 framework/templates/e2e_capture.gd 兼容）:
##   - current_state: int（NORMAL=0 / LOW_HP=1 / EXECUTE_HINT=2 / KILL_HINT=3 /
##     BOSS_BAR=4 / STANCE_BREAK_FLASH=5 / MINION_MODE=6）——shot plan 的
##     state_node/state_property 轮询目标
##   - digit 键 0-6 → _drive_state(...)（_unhandled_input）
##   - auto_cycle 兜底（#574 同路径）: e2e_capture.gd 的 press 仅支持
##     enter/space/esc/方向键，digit 键注入不兼容 → shot plan 经 autoplay.tweaks
##     开启 auto_cycle（每态停留 auto_cycle_frames 帧自循环），capture 驱动只轮询
##     current_state 截图。

enum { NORMAL = 0, LOW_HP = 1, EXECUTE_HINT = 2, KILL_HINT = 3, BOSS_BAR = 4, STANCE_BREAK_FLASH = 5, MINION_MODE = 6 }

## auto-cycle 状态序列（常态 → 低血 → 处决提示 → 击杀提示 → Boss 条 → 崩解闪白 → 杂兵档）
const CYCLE_SEQUENCE: Array = [NORMAL, LOW_HP, EXECUTE_HINT, KILL_HINT, BOSS_BAR, STANCE_BREAK_FLASH, MINION_MODE]

var current_state: int = NORMAL

@export var auto_cycle: bool = false
@export var auto_cycle_frames: int = 30

var _hud = null
var _enemy = null
var _cycle_index: int = 0
var _cycle_frames_left: int = 0
var _normal_seeded: bool = false  # 敌人桩只受一次架势伤害（防跨周期叠加）


func _ready() -> void:
	_hud = get_node_or_null("Hud")
	_enemy = get_node_or_null("EnemyStub")
	if _hud == null:
		push_warning("E2EHudCapture: missing child 'Hud'")
	if _enemy == null:
		push_warning("E2EHudCapture: missing child 'EnemyStub'")
	_cycle_frames_left = auto_cycle_frames
	_drive_state(NORMAL)


func _unhandled_input(event: InputEvent) -> void:
	## digit 键 0-6 → 对应 HUD 状态（人工/脚本注入备选）
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		match key:
			KEY_0:
				_drive_state(NORMAL)
				get_viewport().set_input_as_handled()
			KEY_1:
				_drive_state(LOW_HP)
				get_viewport().set_input_as_handled()
			KEY_2:
				_drive_state(EXECUTE_HINT)
				get_viewport().set_input_as_handled()
			KEY_3:
				_drive_state(KILL_HINT)
				get_viewport().set_input_as_handled()
			KEY_4:
				_drive_state(BOSS_BAR)
				get_viewport().set_input_as_handled()
			KEY_5:
				_drive_state(STANCE_BREAK_FLASH)
				get_viewport().set_input_as_handled()
			KEY_6:
				_drive_state(MINION_MODE)
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	## 仅 auto_cycle 兜底轮询（E2E 具驱动，非 hud.gd）
	if auto_cycle:
		_cycle_frames_left -= 1
		if _cycle_frames_left <= 0:
			_advance_cycle()


func _drive_state(state: int) -> void:
	current_state = state
	if _hud == null:
		return
	match state:
		NORMAL:
			if not _normal_seeded:
				_normal_seeded = true
				if _enemy != null:
					_enemy.take_stance_damage(40.0)
			_hud.set_target_enemy(null)
			_hud.set_target_enemy(_enemy)
			_hud.set_debug_hp(80.0, 50.0, 1)
			_hud.set_debug_stance(40.0, 100.0)
		LOW_HP:
			_hud.set_debug_hp(20.0, 50.0, 1)
		EXECUTE_HINT:
			_hud.show_debug_hint("execute")
		KILL_HINT:
			_hud.show_debug_hint("kill")
		BOSS_BAR:
			_hud.set_target_enemy(_enemy)
			_hud.set_boss_mode(true)
			_hud.set_enemy_display_name("雪夜刀客")
			_hud.set_debug_hp(80.0, 50.0, 1)
			_hud.set_debug_stance(40.0, 100.0)
		STANCE_BREAK_FLASH:
			_hud.set_target_enemy(_enemy)
			_hud.set_boss_mode(true)
			_hud.set_enemy_display_name("雪夜刀客")
			_hud.set_debug_hp(80.0, 50.0, 1)
			_hud.set_debug_stance(40.0, 100.0)
			_hud.set_debug_stance_break()
		MINION_MODE:
			_hud.set_target_enemy(_enemy)
			_hud.set_boss_mode(false)
			_hud.set_debug_stance(40.0, 100.0)


func _advance_cycle() -> void:
	## auto-cycle 兜底：依 CYCLE_SEQUENCE 推进
	_cycle_frames_left = auto_cycle_frames
	var target: int = CYCLE_SEQUENCE[_cycle_index]
	_cycle_index = (_cycle_index + 1) % CYCLE_SEQUENCE.size()
	_drive_state(target)
