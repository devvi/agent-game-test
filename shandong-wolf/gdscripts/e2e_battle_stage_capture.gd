extends Node2D
class_name E2EBattleStageCapture
## E2EBattleStageCapture — battle_stage 截图像具驱动（#583）。
## 归属: docs/DESIGN/583-snowy-shandong-village-battle-stage.md §E2E（截图组）
## 职责: 提供「可被 e2e_capture.gd 驱动」的截图场景——3 个静态构图
##   （PANORAMA 全景 / CLOSEUP 平台特写 / MOON 月亮构图），current_state
##   可轮询、auto_cycle 兜底。零战斗逻辑依赖，只驱动 StageCamera 位置/缩放。
##
## 驱动契约（与 framework/templates/e2e_capture.gd 兼容）:
##   - current_state: int（PANORAMA=0 / CLOSEUP=1 / MOON=2）——
##     shot plan 的 state_node/state_property 轮询目标
##   - digit 键 1-3 → _drive_state(...)（_unhandled_input）
##   - auto_cycle 兜底（#574 同路径）: shot plan 经 autoplay.tweaks 开启，
##     每态停留 auto_cycle_frames 帧自循环

enum { PANORAMA = 0, CLOSEUP = 1, MOON = 2 }

## auto-cycle 状态序列（全景 → 平台特写 → 月亮构图）
const CYCLE_SEQUENCE: Array = [PANORAMA, CLOSEUP, MOON]

var current_state: int = PANORAMA

@export var auto_cycle: bool = false
@export var auto_cycle_frames: int = 30

var _camera = null
var _cycle_index: int = 0
var _cycle_frames_left: int = 0


func _ready() -> void:
	_camera = get_node_or_null("BattleStage/StageCamera")
	if _camera == null:
		push_warning("E2EBattleStageCapture: missing child 'BattleStage/StageCamera'")
	_cycle_frames_left = auto_cycle_frames
	_drive_state(PANORAMA)


func _unhandled_input(event: InputEvent) -> void:
	## digit 键 1-3 → 对应构图（人工/脚本注入备选）
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		match key:
			KEY_1:
				_drive_state(PANORAMA)
				get_viewport().set_input_as_handled()
			KEY_2:
				_drive_state(CLOSEUP)
				get_viewport().set_input_as_handled()
			KEY_3:
				_drive_state(MOON)
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	## 仅 auto_cycle 兜底轮询（E2E 具驱动，非战斗逻辑）
	if auto_cycle:
		_cycle_frames_left -= 1
		if _cycle_frames_left <= 0:
			_advance_cycle()


func _drive_state(state: int) -> void:
	current_state = state
	if _camera == null:
		return
	match state:
		PANORAMA:
			_camera.position = Vector2(1200.0, 360.0)
			_camera.zoom = Vector2(1.0, 1.0)
		CLOSEUP:
			_camera.position = Vector2(600.0, 480.0)
			_camera.zoom = Vector2(1.8, 1.8)
		MOON:
			_camera.position = Vector2(1400.0, 140.0)
			_camera.zoom = Vector2(2.5, 2.5)


func _advance_cycle() -> void:
	## auto-cycle 兜底：依 CYCLE_SEQUENCE 推进
	_cycle_frames_left = auto_cycle_frames
	var target: int = CYCLE_SEQUENCE[_cycle_index]
	_cycle_index = (_cycle_index + 1) % CYCLE_SEQUENCE.size()
	_drive_state(target)
