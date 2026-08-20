extends Node2D
class_name E2EMainAssemblyCapture
## E2EMainAssemblyCapture — #585 组装闭环截图 rig（assembly 组）+ #586 e2e_script 剧本组。
## 归属: docs/DESIGN/585-mvp-combat-loop-assembly.md §3.6 + docs/DESIGN/586-e2e-script-adjudication.md §2.2
## 职责: instance Main.tscn（BattleAssembler 完整闭环装配）驱动 7 态——
##   01_spawn_combat 出生遇敌 / 02_player_move 玩家移动 / 03_first_parry 首次弹反火花 /
##   04_clash 拼刀 / 05_execute_closeup 崩解+处决特写 / 06_fail_subtitle 失败字幕 /
##   07_afterglow 击杀余韵雪幕——current_state 可轮询、auto_cycle 兜底。
##   0-3 编号与 #585 四态 rig 向后兼容（assembly 组既有 shot 引用 0-3）；
##   4-6 为 #586 e2e_script 剧本组新增（MOVE/CLASH/EXECUTE；PARRY=1 只含弹反火花，
##   原「崩解+处决」语义由 EXECUTE=6 承接）。
##
## 驱动契约（与 e2e_battle_stage_capture / e2e_feedback_capture 兼容）:
##   - current_state: int（SPAWN_COMBAT=0 / PARRY=1 / FAIL_SUBTITLE=2 / AFTERGLOW=3 /
##     MOVE=4 / CLASH=5 / EXECUTE=6）—— shot plan 的 state_node/state_property 轮询目标
##   - move_displacement_px: float（MOVE 态内每帧更新 = 玩家 global_position.x 相对进入
##     MOVE 态起点之差，供 shot require 断言: {node: /root/CaptureRig, prop:
##     move_displacement_px, min: 100}，AC2 位移证据）
##   - clash_source（results.json 驱动来源标注: "judge" = judge.clash 信号主路径 /
##     "rig_fallback" = 直接注入 fallback，E1 报告记录成功率）
##   - digit 键 1-7 → _drive_state(...)（_unhandled_input，人工/脚本注入备选；剧本组
##     shot 不依赖键位，仅 auto_cycle + dwell 驱动）
##   - auto_cycle 兜底（#574 同路径）: shot plan 经 autoplay.tweaks 开启，每态停留
##     CYCLE_DWELL_FRAMES[state] 帧（#586 缺口 4 修复，settle 不跨态）
## 每态 dwell 表（帧，dwell > 对应 shot settle_frames + 10 帧裕量）:
##   SPAWN_COMBAT: 40（01_village_open settle 30）   MOVE: 170（02_player_move settle 120）
##   PARRY: 40（03_first_parry settle 20）           CLASH: 40（04_clash settle 20）
##   EXECUTE: 90（05_execute_closeup settle 60）     FAIL_SUBTITLE: 40（06_fail_subtitle settle 30）
##   AFTERGLOW: 40（assembly 04_afterglow settle 30）
## 驱动手法: 只经 BattleAssembler 公有成员（player/enemy/player_entity/enemy_entity/
##   judge/hud/reaction/fail_label/_fail_subtitle_timer/...）与既有组件公开接口
##   （take_stance_damage / request_transition / execute_kill / trigger_feedback /
##   revive / _process 手动推进）驱动，零改动任何既有组件脚本。
## 硬约束（4.7.1 --script 安全风格）: 组件一律经 load()/get_node_or_null 运行时访问，
##   禁止 class_name 标识符引用；禁止 := 类型推断（警告即硬错误）。

enum { SPAWN_COMBAT = 0, PARRY = 1, FAIL_SUBTITLE = 2, AFTERGLOW = 3, MOVE = 4, CLASH = 5, EXECUTE = 6 }

## auto-cycle 状态序列（出生遇敌 → 移动 → 弹反 → 拼刀 → 处决特写 → 失败字幕 → 击杀余韵）
const CYCLE_SEQUENCE: Array = [SPAWN_COMBAT, MOVE, PARRY, CLASH, EXECUTE, FAIL_SUBTITLE, AFTERGLOW]

## 每态定长停留（帧）——settle 不跨态的关键（#586 缺口 4 修复）
const CYCLE_DWELL_FRAMES: Dictionary = {
	SPAWN_COMBAT: 40, MOVE: 170, PARRY: 40, CLASH: 40, EXECUTE: 90,
	FAIL_SUBTITLE: 40, AFTERGLOW: 40,
}

var current_state: int = SPAWN_COMBAT
## MOVE 态位移证据（公有，shot require 轮询目标）
var move_displacement_px: float = 0.0

@export var auto_cycle: bool = false
@export var auto_cycle_frames: int = 30

var _assembler = null       # MainBattle（BattleAssembler，Main/MainBattle）
var _camera = null          # BattleStage/StageCamera（构图）
var _cycle_index: int = 0
var _dwell_frames_left: int = 0
var _move_drive: bool = false
var _move_start_x: float = 0.0
var _clash_source: String = ""
var _clash_connected: bool = false
var _clash_detected: bool = false


func _ready() -> void:
	_assembler = get_node_or_null("Main/MainBattle")
	_camera = get_node_or_null("Main/BattleStage/StageCamera")
	if _assembler == null:
		push_warning("E2EMainAssemblyCapture: missing child 'Main/MainBattle'")
	if _camera == null:
		push_warning("E2EMainAssemblyCapture: missing child 'Main/BattleStage/StageCamera'")
	_dwell_frames_left = int(CYCLE_DWELL_FRAMES.get(SPAWN_COMBAT, 40))
	_drive_state(SPAWN_COMBAT)


func _unhandled_input(event: InputEvent) -> void:
	## digit 键 1-7 → 对应组装态（人工/脚本注入备选）
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		match key:
			KEY_1:
				_drive_state(SPAWN_COMBAT)
				get_viewport().set_input_as_handled()
			KEY_2:
				_drive_state(PARRY)
				get_viewport().set_input_as_handled()
			KEY_3:
				_drive_state(FAIL_SUBTITLE)
				get_viewport().set_input_as_handled()
			KEY_4:
				_drive_state(AFTERGLOW)
				get_viewport().set_input_as_handled()
			KEY_5:
				_drive_state(MOVE)
				get_viewport().set_input_as_handled()
			KEY_6:
				_drive_state(CLASH)
				get_viewport().set_input_as_handled()
			KEY_7:
				_drive_state(EXECUTE)
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	## 仅 auto_cycle 兜底轮询 + MOVE 位移证据更新（E2E 具驱动，非战斗逻辑）
	if auto_cycle:
		_dwell_frames_left -= 1
		if _dwell_frames_left <= 0:
			_advance_cycle()
	if _move_drive and current_state == MOVE:
		move_displacement_px = _player_x() - _move_start_x


func _drive_state(state: int) -> void:
	## 状态就位（current_state 轮询契约）+ 组装态驱动
	current_state = state
	_dwell_frames_left = int(CYCLE_DWELL_FRAMES.get(state, 40))
	if _assembler == null:
		return
	_release_move_drive()              # 离开 MOVE 态必释放（防串态）
	_unfreeze_effects()                # 离开演出态必恢复时间栈（防冻结泄漏到后续 shot）
	match state:
		SPAWN_COMBAT:
			_framing(Vector2(670.0, 480.0))
		MOVE:
			_framing(Vector2(670.0, 480.0))
			_start_move_drive()        # 内部按住 game_move_right + 记录起点
		PARRY:
			_framing(Vector2(670.0, 480.0))
			_drive_first_parry()
		CLASH:
			_framing(Vector2(670.0, 480.0))
			_drive_clash()
		EXECUTE:
			_framing(Vector2(670.0, 480.0))
			_drive_execute_closeup()
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


func _drive_first_parry() -> void:
	## ③ 首次弹反火花: 注入 parry_success 反馈（level A 火花/顿帧/慢动作），
	##    冻结时间栈锁定效果帧（#579 feedback rig 同款，reaction_controller.freeze_time_stack）
	var a = _assembler
	if a.reaction == null:
		return
	if a.reaction.get("freeze_time_stack") != true:
		a.reaction.set("freeze_time_stack", true)
	a.reaction.trigger_feedback("parry_success", {
		"position": _impact_pos(), "normal": Vector2(0.0, -1.0),
		"target_entity": a.enemy_entity, "attacker_entity": a.player_entity,
		"source": "rig",
	})


func _drive_clash() -> void:
	## ④ 拼刀: 主路径 = 双实体同帧进 attack → judge 窗口登记 → clash 信号 →
	##    reaction clash 反馈（E1 实验对象）；fallback = 直接注入（构图一致）
	var a = _assembler
	if a.reaction == null:
		return
	if a.reaction.get("freeze_time_stack") != true:
		a.reaction.set("freeze_time_stack", true)
	if _drive_clash_via_judge():          # E1 主路径（judge.clash 信号驱动）
		_clash_source = "judge"           # results.json 驱动来源标注
	else:
		a.reaction.trigger_feedback("clash", {
			"position": _impact_pos(), "normal": Vector2(0.0, -1.0),
			"target_entity": a.enemy_entity, "attacker_entity": a.player_entity,
			"source": "rig_fallback",
		})
		_clash_source = "rig_fallback"


func _drive_clash_via_judge() -> bool:
	## E1 实验主路径: 双实体同帧 request_transition("attack")，监听 judge.clash。
	## rig 内无法真 await 帧循环（_drive_state 非协程，同步上下文），故采用
	## 「注入后立即检查 clash 信号是否已 emit」——signal emit 是同步的：reaction 已连
	## judge.clash → _on_clash → trigger_feedback；若同帧窗口错帧未触发（如状态守卫
	## 拒绝 request_transition），返回 false 走 fallback（构图一致，来源不同）。
	var a = _assembler
	if a.judge == null or a.player_entity == null or a.enemy_entity == null:
		return false
	if not a.judge.has_signal("clash"):
		return false
	if not _clash_connected:
		a.judge.clash.connect(_on_clash_detected)
		_clash_connected = true
	_clash_detected = false
	a.player_entity.request_transition("attack")
	a.enemy_entity.request_transition("attack")
	return _clash_detected


func _on_clash_detected(_a, _b, _stance_cost) -> void:
	_clash_detected = true


func _drive_execute_closeup() -> void:
	## ⑤ 崩解 + 处决特写: 承接原 _drive_parry_execute 逻辑（崩解 → 处决姿态 →
	##    S 级处决反馈 + 冻结时间栈），StageCamera 推近特写构图；不调 execute_kill
	##    （防 died(true) 触发 assembler AFTERGLOW 干扰本态，原稳定性裁决保留）
	var a = _assembler
	var enemy_entity = a.enemy_entity
	if enemy_entity == null:
		return
	enemy_entity.facing = -1
	enemy_entity.take_stance_damage(999.0)
	if enemy_entity.state_name != "execute":
		enemy_entity.request_transition("execute")
	if a.reaction != null:
		if a.reaction.get("freeze_time_stack") != true:
			a.reaction.set("freeze_time_stack", true)
		a.reaction.trigger_feedback("execute", {
			"position": _impact_pos(), "normal": Vector2(0.0, -1.0),
			"target_entity": enemy_entity, "attacker_entity": a.player_entity,
			"source": "rig",
		})


func _unfreeze_effects() -> void:
	## 离开演出态恢复时间栈（freeze_time_stack = false），防冻结泄漏到后续 shot
	var a = _assembler
	if a != null and a.reaction != null and a.reaction.get("freeze_time_stack") == true:
		a.reaction.set("freeze_time_stack", false)


func _start_move_drive() -> void:
	## ② 玩家移动: 内部按住 game_move_right（smoke I1 同路径，InputController 已 bind）
	var p = _assembler.player
	if p == null:
		return
	_move_start_x = p.global_position.x
	move_displacement_px = 0.0
	_move_drive = true
	Input.action_press("game_move_right")


func _release_move_drive() -> void:
	if _move_drive:
		Input.action_release("game_move_right")
		_move_drive = false


func _player_x() -> float:
	var p = _assembler.player
	return p.global_position.x if p != null else 0.0


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
	## auto-cycle 兜底：依 CYCLE_SEQUENCE 推进，停留由 CYCLE_DWELL_FRAMES 定长
	var target: int = CYCLE_SEQUENCE[_cycle_index]
	_cycle_index = (_cycle_index + 1) % CYCLE_SEQUENCE.size()
	_dwell_frames_left = int(CYCLE_DWELL_FRAMES.get(target, 40))
	_drive_state(target)
