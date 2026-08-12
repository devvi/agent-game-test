extends RefCounted
## 组装集成回归（#393 AC5）— 真实 BreakoutGrid + WaveController + GameManager 10 局循环。
## 覆盖 AC2 完整循环: 墙生成 → 逐砖销毁（wall_cleared）→ 结算（wave_settled）→
## 升级确认推进（advance_settlement，即 UpgradePickUI close() 的接管路径）→
## 新墙更厚 + AI 收紧。断言: 信号计数正确、每墙砖数 == 预期、无残留砖节点
## （旧墙 queue_free 后零残留）、重开（reset → start_first_wave）场景树无泄漏。
## Runs under godot --headless --script via run_tests.gd (_run_async)。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")

var _started: Array = []
var _settled: Array = []
var _cleared: int = 0

func _on_started(index: int) -> void:
	_started.append(index)

func _on_settled(index: int) -> void:
	_settled.append(index)

func _on_cleared() -> void:
	_cleared += 1


func run() -> void:
	print("\n=== Assembly Integration Tests (#393, 10 rounds) ===")
	GameManager.wave_started.connect(_on_started)
	GameManager.wave_settled.connect(_on_settled)
	await _test_ten_round_loop()
	await _test_restart_no_leak()
	GameManager.wave_started.disconnect(_on_started)
	GameManager.wave_settled.disconnect(_on_settled)
	print("  Assembly Integration: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout


## GAPS 布局每行砖数: cols=10 − 2 缝列 == 8
func _expected_bricks(thickness: int) -> int:
	return 8 * thickness


func _make_fx() -> Dictionary:
	## 真实 mini-tree: host + 真实 BreakoutGrid + mock AIPaddle/RainCurtain + 真实 WaveController。
	var tree = Engine.get_main_loop() as SceneTree
	var host = Node2D.new()
	host.name = "TestHost"
	tree.root.add_child(host)

	var grid = Node2D.new()
	grid.set_script(load("res://gdscripts/breakout_grid.gd"))
	grid.name = "BreakoutGrid"
	host.add_child(grid)
	grid.wall_cleared.connect(_on_cleared)

	var atmosphere = Node2D.new()
	atmosphere.name = "AtmosphereLayer"
	host.add_child(atmosphere)
	var rain_code = GDScript.new()
	rain_code.source_code = """extends Node2D
## Mock RainCurtain (#389 契约，test_integration_393.gd 内部使用)
var wave_factor: int = -1
func set_wave_factor(index: int) -> void:
	wave_factor = index
"""
	rain_code.reload()
	var rain = Node2D.new()
	rain.name = "RainCurtain"
	rain.set_script(rain_code)
	atmosphere.add_child(rain)

	var paddle_code = GDScript.new()
	paddle_code.source_code = """extends Node2D
## Mock AIPaddle (test_integration_393.gd 内部使用)
var ai_reaction_delay_min: float = 0.15
var ai_reaction_delay_max: float = 0.4
var ai_position_error: float = 24.0
"""
	paddle_code.reload()
	var paddle = Node2D.new()
	paddle.name = "AIPaddle"
	paddle.set_script(paddle_code)
	paddle.ai_reaction_delay_min = CONSTS.AI_REACTION_DELAY_MIN
	paddle.ai_reaction_delay_max = CONSTS.AI_REACTION_DELAY_MAX
	paddle.ai_position_error = CONSTS.AI_POSITION_ERROR
	host.add_child(paddle)

	var controller = Node.new()
	controller.set_script(load("res://gdscripts/wave_controller.gd"))
	controller.name = "WaveController"
	host.add_child(controller)
	controller.settle_delay = 0.01
	controller.settle_hold = true   # #388 推进接管路径（等价 UpgradePickUI open() 后）——推进由 advance_settlement 显式驱动

	return {"host": host, "grid": grid, "paddle": paddle, "rain": rain, "controller": controller}


func _cleanup(fx: Dictionary) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var host = fx.get("host")
	if host != null and is_instance_valid(host) and host.get_parent() != null:
		host.get_parent().remove_child(host)
		host.queue_free()
	await _wait(0.05)


func _brick_count(grid: Node2D) -> int:
	var n: int = 0
	for child in grid.get_children():
		if child.is_in_group("bricks"):
			n += 1
	return n


## 10 局循环（AC2 + AC5）
func _test_ten_round_loop() -> void:
	GameManager.reset_match()
	_started.clear()
	_settled.clear()
	_cleared = 0
	var fx = _make_fx()
	var ctrl = fx.controller
	var grid = fx.grid
	var paddle = fx.paddle
	var min0: float = paddle.ai_reaction_delay_min

	# 首波经 start_first_wave（#393 首波触发入口）
	ctrl.start_first_wave()
	_assert(GameManager.wave_index == 1, "LOOP: 首波 wave_index == 1 (got %d)" % GameManager.wave_index)
	_assert(grid.remaining_bricks == _expected_bricks(1), "LOOP: 第 1 墙砖数 == 8 (got %d)" % grid.remaining_bricks)
	_assert(fx.rain.wave_factor == 1, "LOOP: 雨幕波次因子 == 1 (#389 契约)")

	for round_idx in range(10):
		var wave: int = round_idx + 1
		_assert(GameManager.wave_index == wave,
			"LOOP: 第 %d 轮 wave_index == %d (got %d)" % [round_idx + 1, wave, GameManager.wave_index])
		# 逐砖销毁 → wall_cleared 恰好一次 → 结算
		var bricks: Array = []
		for child in grid.get_children():
			if child.is_in_group("bricks"):
				bricks.append(child)
		var cleared_before: int = _cleared
		for b in bricks:
			b.destroy()
		_assert(_cleared == cleared_before + 1,
			"LOOP: 第 %d 墙清空 wall_cleared 一次 (got %d)" % [wave, _cleared - cleared_before])
		_assert(GameManager.wave_state == GameManager.WaveState.SETTLED,
			"LOOP: 第 %d 墙清空 → SETTLED" % wave)
		_assert(_settled.size() == wave, "LOOP: wave_settled 累计 %d 次 (got %d)" % [wave, _settled.size()])
		# 升级确认推进（UpgradePickUI close() → advance_settlement 等价路径）
		if wave < 10:
			ctrl.advance_settlement()
			_assert(GameManager.wave_index == wave + 1,
				"LOOP: advance_settlement → wave_index == %d (got %d)" % [wave + 1, GameManager.wave_index])
			await _wait(0.02)   # 旧砖 queue_free 生效
			_assert(_brick_count(grid) == _expected_bricks(wave + 1),
				"LOOP: 第 %d 墙零残留、新墙 %d 砖 (got %d)" % [wave + 1, _expected_bricks(wave + 1), _brick_count(grid)])
			_assert(grid.remaining_bricks == _expected_bricks(wave + 1),
				"LOOP: remaining_bricks == %d (got %d)" % [_expected_bricks(wave + 1), grid.remaining_bricks])
		else:
			# 第 10 轮: 清空后推进到第 11 波（验证 21 分前波次不封顶）
			ctrl.advance_settlement()
			await _wait(0.02)
			_assert(GameManager.wave_index == 11, "LOOP: 第 10 轮推进 → wave_index == 11 (got %d)" % GameManager.wave_index)

	# 汇总断言
	_assert(_started.size() == 11, "LOOP: wave_started 累计 11 次 (got %d)" % _started.size())
	_assert(_settled.size() == 10, "LOOP: wave_settled 累计 10 次 (got %d)" % _settled.size())
	_assert(_cleared == 10, "LOOP: wall_cleared 累计 10 次 (got %d)" % _cleared)
	_assert(paddle.ai_reaction_delay_min < min0, "LOOP: AI 参数收紧（难度杠杆生效）")
	_assert(paddle.ai_reaction_delay_min >= CONSTS.AI_REACTION_DELAY_MIN_FLOOR, "LOOP: AI 收紧不越 FLOOR")

	await _cleanup(fx)


## 重开（GAME_OVER → MENU → SPACE）: reset → start_first_wave → 首波从 1 起、无残留
func _test_restart_no_leak() -> void:
	GameManager.reset_match()
	_started.clear()
	_settled.clear()
	_cleared = 0
	var fx = _make_fx()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl.start_first_wave()
	_assert(GameManager.wave_index == 1, "RESTART: 重开首波 wave_index == 1")
	_assert(grid.remaining_bricks == _expected_bricks(1), "RESTART: 新墙 8 砖")
	await _wait(0.02)
	_assert(_brick_count(grid) == _expected_bricks(1),
		"RESTART: 场景树无残留砖节点（上一 run 旧墙已清）(got %d)" % _brick_count(grid))
	# 手动触发重开路径: 清空 → 结算 → reset → 再首波（模拟 MENU 重开）
	var bricks: Array = []
	for child in grid.get_children():
		if child.is_in_group("bricks"):
			bricks.append(child)
	for b in bricks:
		b.destroy()
	await _wait(0.02)
	_assert(_cleared == 1, "RESTART: 重开前清空 wall_cleared 一次")
	GameManager.reset_match()
	ctrl.start_first_wave()
	_assert(GameManager.wave_index == 1, "RESTART: reset 后再首波 == 1")
	await _wait(0.02)
	_assert(_brick_count(grid) == _expected_bricks(1), "RESTART: 二次重开无残留 (got %d)" % _brick_count(grid))
	await _cleanup(fx)
