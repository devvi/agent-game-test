extends Node2D
class_name MainBattle
## MainBattle — MVP 战斗闭环组装编排脚本（BattleAssembler，#585）。
## 归属: docs/DESIGN/585-mvp-combat-loop-assembly.md §2.1
## 职责: 13 步同步装配（玩家/敌人/Judge/HUD/Reaction/Revive/Execution 程序化实例化
##   + bind 接线，全部首帧前就绪）+ 轻量游戏状态机（IDLE→COMBAT→KILL→AFTERGLOW→FAIL）
##   + 失败字幕 / 教学提示 / 余韵时序编排。
## 红线: 零改动既有 17 组件——只消费 bind/subscribe 契约；Engine.time_scale 不经本层
##   （慢动作归 #579 TimeScaleStack，经 reaction 触发）。
## 事件源（只读）: InputController 意图信号 / CombatEntity 6 信号 / CombatJudge 结果事件
##   / Hud.low_health_changed——本层只接线 + 状态编排，不判定不演出。

const C = preload("res://gdscripts/constants.gd")

## 组件脚本运行时加载（class_name 禁止按标识符引用——headless --script 类缓存为空；
## load() 惰性解析，安全风格）
var CombatEntityScript = load("res://gdscripts/combat_entity.gd")
var PlayerControllerScript = load("res://gdscripts/player_controller.gd")
var EnemyAIScript = load("res://gdscripts/enemy_ai.gd")
var CombatJudgeScript = load("res://gdscripts/combat_judge.gd")
var HudScript = load("res://gdscripts/hud.gd")
var ReactionScript = load("res://gdscripts/reaction_controller.gd")
var ReviveScript = load("res://gdscripts/revive_orchestrator.gd")
var ExecutionScript = load("res://gdscripts/execution_orchestrator.gd")
var StickFigureScene = load("res://scenes/player_stick_figure.tscn")


## 游戏状态机（idle/combat/kill 为被动观察态；afterglow 由 Timer 驱动；fail 为终态）
enum GameState { IDLE, COMBAT, KILL, AFTERGLOW, FAIL }

## 状态迁移广播（test/E2E 断言用，参数为枚举名字符串）
signal game_state_changed(from_state: String, to_state: String)
## 失败字幕显示完成（测试断言恰好一次）
signal fail_subtitle_shown()

## 组件引用缓存（test 断言 bind 目标非 null，AC5「无 pending 组件」）
var player
var enemy
var player_entity
var enemy_entity
var judge
var hud
var reaction
var execution
var revive
var atmosphere

## 当前游戏状态（public 供测试/E2E 读取）
var game_state: int = GameState.IDLE
## 失败字幕 Label（public 供测试断言，挂在 Main/CanvasLayer）
var fail_label: Label
## 教学提示 Label（public 供测试断言，挂在 Main/CanvasLayer）
var tutorial_label: Label

var _canvas_layer: CanvasLayer = null
var _fail_handled: bool = false       # 失败路径幂等守卫（二次 died(true) 不再重演）
var _afterglow_started: bool = false  # 余韵幂等守卫（二次 died(true) 不重启 Timer）
var _afterglow_timer: Timer = null      # 余韵 5s Timer（public 供测试驱动 timeout）
var _fail_subtitle_timer: Timer = null  # 失败字幕延迟 Timer（public 供测试驱动 timeout）

## 视觉 stick 引用（#683 §3.4 facing 接线）——翻转目标 = StickFigure 子节点，
## 绝不 scale 物理根/controller 根（MA2 红线，PlayerController/EnemyAI 根 scale 保持 1.0）
var _player_stick_figure = null
var _enemy_stick_figure = null
## facing 翻转缓存（每帧轮询比对，变化才设 scale.x——防重复写 + 翻转恰好一次）
var _last_player_facing: float = 1.0
var _last_enemy_facing: float = 1.0


func _ready() -> void:
	## 13 步装配全链路（§4 Flow 4 顺序契约，全部同步完成、首帧前就绪）
	## ① 定位既有节点（Main.tscn 已含 BattleStage 实例 + Atmosphere 实例 + 标题 CanvasLayer）
	var stage = get_node_or_null("../BattleStage")
	_canvas_layer = get_node_or_null("../CanvasLayer") as CanvasLayer
	atmosphere = get_node_or_null("../Atmosphere")
	var ic = get_node_or_null("/root/InputController")

	## ② 玩家装配（PlayerController + StickFigure + CombatEntity + 输入桥 + 动画链）
	_build_player(ic)

	## ③ 玩家定位 PlayerSpawn
	if stage != null:
		var spawn = stage.get_node_or_null("PlayerSpawn")
		if spawn != null:
			player.position = spawn.position

	## ⑤ Judge 节点先于敌人创建（敌人装配的 judge 引用依赖）
	judge = CombatJudgeScript.new()
	judge.name = "Judge"
	add_child(judge)

	## ④ 敌人装配（EnemyAI + StickFigure + CombatEntity + bind_entity + player/judge 注入）
	_build_enemy(stage)

	## ⑤ Judge bind（必须先于首帧 resolve）
	judge.bind_entities(player_entity, enemy_entity)
	judge.bind_input(ic)

	## ⑥ HUD 实例挂 CanvasLayer + bind 双实体
	_build_hud()

	## ⑦ Reaction bind（camera_path 必须先于入树设置——其 _ready 读取）
	_build_reaction()

	## ⑧ Revive.bind_player
	revive = ReviveScript.new()
	revive.name = "Revive"
	add_child(revive)
	revive.bind_player(player_entity)

	## ⑨ Execution 5 项 bind
	execution = ExecutionScript.new()
	execution.name = "Execution"
	add_child(execution)
	execution.bind_player(player_entity)
	execution.bind_enemy(enemy_entity)
	execution.bind_judge(judge)
	execution.bind_input(ic)
	execution.bind_feedback(reaction)

	## ⑩ 低血氛围单点接线（hud.low_health_changed → atmosphere.set_low_health；
	##    headless 免 Main 树时引用为 null → no-op 不崩溃）
	if hud != null and atmosphere != null and hud.has_signal("low_health_changed") \
			and atmosphere.has_method("set_low_health"):
		hud.low_health_changed.connect(atmosphere.set_low_health)

	## ⑪ 失败路径（玩家 died(final=true) → FAIL）
	player_entity.died.connect(_on_player_final_death)

	## ⑫ 余韵路径（敌人 died(final=true) → KILL → AFTERGLOW）
	enemy_entity.died.connect(_on_enemy_final_death)

	## ⑬ 教学提示 + 隐藏标题卡 + 初始状态
	_setup_tutorial_hint()
	_set_game_state(GameState.IDLE)
	## ⑭ 初始 facing 落位（装配完成即按当前 facing 设一次 scale.x，防首帧朝向错误）
	_sync_visual_facing()


func _build_player(ic) -> void:
	## 玩家装配: PlayerController(CharacterBody2D, 组 player) 根 → StickFigure 视觉
	##   + CombatEntity(is_player=true, life_total=2) 数据；state_changed→consume_state(to)
	player = PlayerControllerScript.new()
	player.name = "Player"
	add_child(player)
	var stick = StickFigureScene.instantiate()
	stick.name = "PlayerStickFigure"
	player.add_child(stick)
	_player_stick_figure = stick
	player_entity = CombatEntityScript.new({"is_player": true, "life_total": 2})
	player_entity.name = "PlayerEntity"
	player.add_child(player_entity)
	if ic != null and player_entity.get("_ic") == null:
		player_entity.bind_input_controller(ic)
	## state_changed 双参 (from,to) → 只转发 to 给 consume_state（lambda 转发第二参）
	player_entity.state_changed.connect(func(_from: String, to: String): stick.consume_state(to))


func _build_enemy(stage) -> void:
	## 敌人装配: EnemyAI(CharacterBody2D) 根 → StickFigure 视觉 + CombatEntity(is_player=false,
	##   life_total=1)；bind_entity + player/judge 注入 + waypoints 由 EnemySpawnA/B 派生
	enemy = EnemyAIScript.new()
	enemy.name = "Enemy"
	enemy.player = player
	enemy.judge = judge
	add_child(enemy)
	var stick = StickFigureScene.instantiate()
	stick.name = "EnemyStickFigure"
	enemy.add_child(stick)
	_enemy_stick_figure = stick
	enemy_entity = CombatEntityScript.new({"is_player": false, "life_total": 1, "life_1_max": C.ENEMY_HP_MAX})
	enemy_entity.name = "EnemyEntity"
	enemy.add_child(enemy_entity)
	enemy.bind_entity(enemy_entity)
	enemy.elite_mode = true   # MVP 单敌人即精英（#682: 蓄力重斩出招启用，HP 慢线接通）
	## #720 自动面向: 玩家攻击瞬间转向最近敌人（消除站桩挥空；装配注入 target 引用）
	if player_entity != null:
		player_entity._auto_face_target = enemy_entity
	enemy_entity.state_changed.connect(func(_from: String, to: String): stick.consume_state(to))
	## 遇敌 → COMBAT 态（首次攻击接战，仅 IDLE→COMBAT）
	enemy_entity.state_changed.connect(_on_enemy_entity_state_changed)
	var waypoints: Array = []
	if stage != null:
		var spawn_a = stage.get_node_or_null("EnemySpawnA")
		var spawn_b = stage.get_node_or_null("EnemySpawnB")
		if spawn_a != null:
			waypoints.append(spawn_a.position)
			enemy.position = spawn_a.position
		if spawn_b != null:
			waypoints.append(spawn_b.position)
	enemy.waypoints = waypoints


func _build_hud() -> void:
	## HUD: HudLayer(CanvasLayer) → Hud（bind_player + set_target_enemy 双实体）
	var hud_layer: CanvasLayer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	add_child(hud_layer)
	hud = HudScript.new()
	hud_layer.add_child(hud)
	hud.bind_player(player_entity)
	hud.set_target_enemy(enemy_entity)
	hud.set_boss_mode(true)          # MVP 唯一敌人 = 精英 → Boss 档（名字+血条+架势条全显）
	hud.set_enemy_display_name("雪夜刀客")   # # DRAFT 占位文案（taste 候选进 PR 待用户定稿）


func _build_reaction() -> void:
	## Reaction: camera_path 必须设置于 add_child 之前（_ready 读取注入 ScreenShake）
	reaction = ReactionScript.new()
	reaction.camera_path = ^"../BattleStage/StageCamera"
	reaction.name = "Reaction"
	add_child(reaction)
	reaction.bind_judge(judge)
	reaction.subscribe_entity(player_entity)
	reaction.subscribe_entity(enemy_entity)


func _process(_delta: float) -> void:
	## 每帧轮询同步（#683 §3.4 装配接线，零信号依赖——facing 可能从多源变化）
	_sync_visual_facing()
	_sync_move_speed()


func _sync_visual_facing() -> void:
	## 朝向 → 视觉翻转（Flow 1）: 缓存比对 facing 变化，变化时设 StickFigure.scale.x。
	## 数据源: player_entity.facing（输入轴同步）/ enemy_entity.facing（AI 同步）——
	##   单一事实源（不读 enemy_ai 私有状态）；翻转目标 = StickFigure 视觉子节点，
	##   绝不 scale 物理根/controller 根（红线 §4.3-C，PlayerController/EnemyAI 根 scale
	##   保持 1.0，MA2 断言）；null 引用 guard（headless 测试某些节点可能缺失）。
	if player_entity != null:
		var pf: int = player_entity.facing
		if pf != _last_player_facing:
			_last_player_facing = float(pf)
			_apply_facing_flip(_player_stick_figure, pf)
	if enemy_entity != null:
		var ef: int = enemy_entity.facing
		if ef != _last_enemy_facing:
			_last_enemy_facing = float(ef)
			_apply_facing_flip(_enemy_stick_figure, ef)


func _apply_facing_flip(stick_root, facing: int) -> void:
	## 翻转执行: 仅作用于 StickFigure 子节点（get_node_or_null 容错，节点缺失 no-op）
	if stick_root == null:
		return
	var figure = stick_root.get_node_or_null("StickFigure")
	if figure != null:
		figure.scale.x = float(facing)


func _sync_move_speed() -> void:
	## 步频 → 速度同步（Flow 2）: set_move_speed(|v|/MOVE_MAX_SPEED)——
	##   非 move clip 内部 no-op，可直接每帧调；velocity 为 CharacterBody2D 属性
	if _player_stick_figure != null and player != null and _player_stick_figure.has_method("set_move_speed"):
		_player_stick_figure.set_move_speed(player.velocity.x)
	if _enemy_stick_figure != null and enemy != null and _enemy_stick_figure.has_method("set_move_speed"):
		_enemy_stick_figure.set_move_speed(enemy.velocity.x)


func _setup_tutorial_hint() -> void:
	## 教学提示: 隐藏标题 CenterContainer（节点保留，#572 语义可回归）+ 顶部提示 Label
	##   + TUTORIAL_HINT_DELAY 后浮现（文案取候选清单首项，taste-draft 待用户定稿）
	if _canvas_layer == null:
		return
	var center: Control = _canvas_layer.get_node_or_null("CenterContainer")
	if center != null:
		center.visible = false
	tutorial_label = Label.new()
	_canvas_layer.add_child(tutorial_label)
	tutorial_label.anchors_preset = Control.PRESET_CENTER_TOP
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.add_theme_font_size_override("font_size", 24)
	tutorial_label.add_theme_color_override("font_color", C.HUD_MOON_WHITE)
	tutorial_label.modulate.a = 0.0
	tutorial_label.visible = false
	var hint_timer: Timer = Timer.new()
	hint_timer.one_shot = true
	hint_timer.wait_time = float(C.TUTORIAL_HINT_DELAY)
	hint_timer.timeout.connect(_show_tutorial_hint)
	add_child(hint_timer)
	hint_timer.start()


func _on_enemy_entity_state_changed(_from: String, to: String) -> void:
	## 遇敌接战: 敌人首次进入 attack 态（IDLE 时）→ COMBAT
	if to != "attack":
		return
	if game_state != GameState.IDLE:
		return
	_set_game_state(GameState.COMBAT)


func _on_player_final_death(_entity, final: bool) -> void:
	## 失败路径（AC2）: final==true → FAIL 终态 + 输入冻结 + AI 停止 → 延迟字幕淡入
	if not final:
		return
	if _fail_handled:
		return
	_fail_handled = true
	_set_game_state(GameState.FAIL)
	var ic = get_node_or_null("/root/InputController")
	if ic != null:
		ic.set_process(false)
	if enemy != null and is_instance_valid(enemy):
		enemy.set_physics_process(false)
	_show_fail_subtitle_delayed()


func _show_fail_subtitle_delayed() -> void:
	## 字幕时序: 先建 Label（初始隐藏）→ FAIL_SUBTITLE_DELAY 后淡入
	_create_fail_label()
	_fail_subtitle_timer = Timer.new()
	_fail_subtitle_timer.one_shot = true
	_fail_subtitle_timer.wait_time = float(C.FAIL_SUBTITLE_DELAY)
	_fail_subtitle_timer.timeout.connect(_fade_in_fail_subtitle)
	add_child(_fail_subtitle_timer)
	_fail_subtitle_timer.start()


func _create_fail_label() -> void:
	## 失败字幕 Label（挂在 Main/CanvasLayer，anchors 全屏居中，初始隐藏透明）
	if fail_label != null or _canvas_layer == null:
		return
	fail_label = Label.new()
	_canvas_layer.add_child(fail_label)
	fail_label.anchors_preset = Control.PRESET_FULL_RECT
	fail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fail_label.add_theme_font_size_override("font_size", 36)
	fail_label.add_theme_color_override("font_color", Color.WHITE)
	fail_label.modulate.a = 0.0
	fail_label.visible = false


func _fade_in_fail_subtitle() -> void:
	## 淡入 FAIL_SUBTITLE_FADE_SECONDS 后常驻 + 广播 fail_subtitle_shown（恰好一次）
	if fail_label != null:
		fail_label.text = str(C.FAIL_SUBTITLE_CANDIDATES[0])
		fail_label.visible = true
		var tween: Tween = create_tween()
		tween.tween_property(fail_label, "modulate:a", 1.0, float(C.FAIL_SUBTITLE_FADE_SECONDS))
		tween.finished.connect(func(): fail_subtitle_shown.emit())
	else:
		fail_subtitle_shown.emit()


func _on_enemy_final_death(_entity, final: bool) -> void:
	## 余韵路径（AC3）: final==true → KILL（HUD 击杀提示自动触发）→ AFTERGLOW
	##   → AFTERGLOW_SECONDS 到期回 IDLE（敌人重生不在 MVP 范围）
	if not final:
		return
	if _afterglow_started:
		return
	_afterglow_started = true
	_set_game_state(GameState.KILL)
	_set_game_state(GameState.AFTERGLOW)
	_afterglow_timer = Timer.new()
	_afterglow_timer.one_shot = true
	_afterglow_timer.wait_time = float(C.AFTERGLOW_SECONDS)
	_afterglow_timer.timeout.connect(func(): _set_game_state(GameState.IDLE))
	add_child(_afterglow_timer)
	_afterglow_timer.start()


func _show_tutorial_hint() -> void:
	## 教学提示浮现: 淡入 0.5s → 停留 2.5s → 淡出 0.5s → 隐藏（文案候选首项，待定稿）
	if tutorial_label == null:
		return
	tutorial_label.text = str(C.TUTORIAL_HINT_CANDIDATES[0])
	tutorial_label.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(tutorial_label, "modulate:a", 1.0, 0.5)
	tween.tween_interval(2.5)
	tween.tween_property(tutorial_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): tutorial_label.visible = false)


func _set_game_state(next_state: int) -> void:
	## 状态迁移唯一入口: 同态幂等 + FAIL 终态守卫（不再迁移）+ 广播名字符串
	if next_state == game_state:
		return
	if game_state == GameState.FAIL:
		return
	var from_state: String = _state_name(game_state)
	game_state = next_state
	game_state_changed.emit(from_state, _state_name(game_state))


func _state_name(state: int) -> String:
	## 枚举 → 名字符串（test/E2E 断言用）
	match state:
		GameState.IDLE:
			return "IDLE"
		GameState.COMBAT:
			return "COMBAT"
		GameState.KILL:
			return "KILL"
		GameState.AFTERGLOW:
			return "AFTERGLOW"
		GameState.FAIL:
			return "FAIL"
	return "IDLE"
