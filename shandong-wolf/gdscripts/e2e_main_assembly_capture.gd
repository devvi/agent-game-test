extends Node2D
class_name E2EMainAssemblyCapture
## E2EMainAssemblyCapture — #585 组装闭环截图 rig（assembly 组）。
## 归属: docs/DESIGN/585-mvp-combat-loop-assembly.md §3.6
## 职责: instance Main.tscn（BattleAssembler 完整闭环装配）驱动 4 态——
##   01_spawn_combat 出生遇敌 / 02_parry_execute 弹反崩解处决 / 03_fail_subtitle
##   失败字幕 / 04_afterglow 击杀余韵雪幕——current_state 可轮询、auto_cycle 兜底。
##
## 驱动契约（与 e2e_battle_stage_capture / e2e_feedback_capture 兼容）:
##   - current_state: int（SPAWN_COMBAT=0 / PARRY_EXECUTE=1 / FAIL_SUBTITLE=2 /
##     AFTERGLOW=3）—— shot plan 的 state_node/state_property 轮询目标
##   - digit 键 1-4 → _drive_state(...)（_unhandled_input，人工/脚本注入备选）
##   - auto_cycle 兜底（#574 同路径）: shot plan 经 autoplay.tweaks 开启，
##     每态停留 auto_cycle_frames 帧自循环
## 驱动手法: 只经 BattleAssembler 公有成员（player/enemy/player_entity/enemy_entity/
##   reaction/fail_label/_fail_subtitle_timer/_is_final_dead...）与既有组件公开接口
##   （take_stance_damage / request_transition / execute_kill / trigger_feedback /
##   revive / _process 手动推进）驱动，零改动任何既有组件脚本。
## 硬约束（4.7.1 --script 安全风格）: 组件一律经 load()/get_node_or_null 运行时访问，
##   禁止 class_name 标识符引用；禁止 := 类型推断（警告即硬错误）。

enum { SPAWN_COMBAT = 0, PARRY_EXECUTE = 1, FAIL_SUBTITLE = 2, AFTERGLOW = 3 }

## auto-cycle 状态序列（出生遇敌 → 弹反崩解处决 → 失败字幕 → 击杀余韵）
const CYCLE_SEQUENCE: Array = [SPAWN_COMBAT, PARRY_EXECUTE, FAIL_SUBTITLE, AFTERGLOW]

var current_state: int = SPAWN_COMBAT

@export var auto_cycle: bool = false
@export var auto_cycle_frames: int = 30

var _assembler = null       # MainBattle（BattleAssembler，Main/MainBattle）
var _camera = null          # BattleStage/StageCamera（构图）
var _cycle_index: int = 0
var _cycle_frames_left: int = 0


func _ready() -> void:
	_assembler = get_node_or_null("Main/MainBattle")
	_camera = get_node_or_null("Main/BattleStage/StageCamera")
	if _assembler == null:
		push_warning("E2EMainAssemblyCapture: missing child 'Main/MainBattle'")
	if _camera == null:
		push_warning("E2EMainAssemblyCapture: missing child 'Main/BattleStage/StageCamera'")
	_cycle_frames_left = auto_cycle_frames
	_drive_state(SPAWN_COMBAT)


func _unhandled_input(event: InputEvent) -> void:
	## digit 键 1-4 → 对应组装态（人工/脚本注入备选）
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		match key:
			KEY_1:
				_drive_state(SPAWN_COMBAT)
				get_viewport().set_input_as_handled()
			KEY_2:
				_drive_state(PARRY_EXECUTE)
				get_viewport().set_input_as_handled()
			KEY_3:
				_drive_state(FAIL_SUBTITLE)
				get_viewport().set_input_as_handled()
			KEY_4:
				_drive_state(AFTERGLOW)
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	## 仅 auto_cycle 兜底轮询（E2E 具驱动，非战斗逻辑）
	if auto_cycle:
		_cycle_frames_left -= 1
		if _cycle_frames_left <= 0:
			_advance_cycle()


func _drive_state(state: int) -> void:
	## 状态就位（current_state 轮询契约）+ 组装态驱动
	current_state = state
	if _assembler == null:
		return
	match state:
		SPAWN_COMBAT:
			_framing(Vector2(670.0, 480.0))
		PARRY_EXECUTE:
			_framing(Vector2(670.0, 480.0))
			_drive_parry_execute()
		FAIL_SUBTITLE:
			_framing(Vector2(670.0, 480.0))
			_drive_fail_subtitle()
		AFTERGLOW:
			_framing(Vector2(1000.0, 360.0))
			_drive_afterglow()


func _framing(pos: Vector2) -> void:
	## StageCamera 构图（position_smoothing_enabled=false，直接落位无插值）
	if _camera != null:
		_camera.position = pos


func _drive_parry_execute() -> void:
	## 弹反崩解处决: 敌架势打崩（stance_break，stick figure anim_stance_break）
	##   → 处决姿态（request_transition("execute")，anim_execute）→ S 级处决反馈
	##   （trigger_feedback("execute") = 火花/hit-stop/慢动作/刀光）。
	## 稳定性裁决: 不调 execute_kill（#580 _trigger_execution 路径）——execute_kill 会
	##   emit died(true) 触发 assembler AFTERGLOW 干扰本态构图；本 rig 只摆处决姿态
	##   + 演出，敌人保持 execute 态供 settle_frames 内截图。
	var a = _assembler
	var enemy_entity = a.enemy_entity
	if enemy_entity == null:
		return
	enemy_entity.facing = -1
	enemy_entity.take_stance_damage(999.0)
	if enemy_entity.state_name != "execute":
		enemy_entity.request_transition("execute")
	if a.reaction != null:
		var data: Dictionary = {
			"position": _impact_pos(),
			"normal": Vector2(0.0, -1.0),
			"target_entity": enemy_entity,
			"attacker_entity": a.player_entity,
			"source": "rig",
		}
		a.reaction.trigger_feedback("execute", data)


func _drive_fail_subtitle() -> void:
	## 失败字幕: 玩家双死（照 test_main_assembly._drive_player_final_death）→ assembler
	##   FAIL 态 + 输入冻结 + AI 停止 → 字幕延迟 Timer 到期（timeout.emit）→ 淡入 tween
	##   custom_step(2.0) 同步推进 → fail_label 可见（文案 ∈ FAIL_SUBTITLE_CANDIDATES）。
	##   画面: 雪夜 + 居中失败字幕 + 输入冻结。
	var a = _assembler
	if a.player_entity == null:
		return
	if a.player_entity.get("_is_final_dead") != true:
		a.player_entity.take_damage(100.0)
		a.player_entity.revive()
		a.player_entity.set("_invincible_until_sec", 0.0)
		a.player_entity._process(1.1)
		a.player_entity.take_damage(100.0)
	var t = a._fail_subtitle_timer
	if t != null and is_instance_valid(t):
		t.timeout.emit()
	var tree = a.get_tree()
	if tree != null and tree.has_method("get_processed_tweens"):
		var tweens: Array = tree.get_processed_tweens()
		for tw_obj in tweens:
			var tw: Tween = tw_obj as Tween
			if tw != null and tw.is_valid():
				tw.custom_step(2.0)


func _drive_afterglow() -> void:
	## 击杀余韵: 清理 shot 03 失败字幕残留（FAIL 终态字幕仍在画面上，隐藏供余韵构图）
	##   → 敌人进处决姿态后终杀（execute_kill，emit died(true) → assembler
	##   KILL→AFTERGLOW）→ 雪花由 Atmosphere 天然持续。画面: 击杀余韵雪幕。
	var a = _assembler
	var enemy_entity = a.enemy_entity
	if enemy_entity == null:
		return
	if a.fail_label != null:
		a.fail_label.visible = false
	if enemy_entity.get("_is_final_dead") != true:
		if enemy_entity.state_name != "stance_break" and enemy_entity.state_name != "execute":
			enemy_entity.take_stance_damage(999.0)
		if enemy_entity.state_name != "execute":
			enemy_entity.request_transition("execute")
		enemy_entity.execute_kill()


func _impact_pos() -> Vector2:
	## 刀与刀交点（两 SwordPivot 全局位置中点，reaction 层 AC3 语义）；缺 pivot
	##   → 敌实体位置（反馈层自行推导兜底）
	var a = _assembler
	if a == null:
		return Vector2.ZERO
	var p_pivot = null
	if a.player != null:
		p_pivot = a.player.get_node_or_null("PlayerStickFigure/StickFigure/TorsoPivot/SwordPivot")
	var e_pivot = null
	if a.enemy != null:
		e_pivot = a.enemy.get_node_or_null("EnemyStickFigure/StickFigure/TorsoPivot/SwordPivot")
	if p_pivot != null and e_pivot != null:
		return (p_pivot.global_position + e_pivot.global_position) / 2.0
	var enemy_entity = a.enemy_entity
	if enemy_entity != null:
		return enemy_entity.global_position
	return Vector2.ZERO


func _advance_cycle() -> void:
	## auto-cycle 兜底：依 CYCLE_SEQUENCE 推进
	_cycle_frames_left = auto_cycle_frames
	var target: int = CYCLE_SEQUENCE[_cycle_index]
	_cycle_index = (_cycle_index + 1) % CYCLE_SEQUENCE.size()
	_drive_state(target)
