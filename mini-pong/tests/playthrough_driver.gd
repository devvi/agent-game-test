extends Node
## playthrough_driver.gd — L2 运行时驱动（run-e2e-review.sh L2 层激活，PRD §4.4）。
## 实例化真实 Main.tscn 全链路（FSM/HUD/转场/失败屏），autoplay 双 AI（mode=1、
## ai_position_error=200 镜像 e2e_shots.json），馈送 ui_accept 开局（FSM MENU→SERVING→
## PLAYING，PLAYING 入口触发 start_first_wave，#393 B.1）+ 每波升级窗口确认（焦点 0），
## 墙钟 DEADLINE_MS 内打完一局（is_run_over + match_over 胜者非空）→ quit(0)；超时/异常 → quit(1)。
## Runs: godot --path mini-pong/ --headless tests/playthrough_test.tscn
## Design: docs/DESIGN/394-e2e-playability.md §3.2 / §9 Scenario G

const SEED: int = 20260813
const DEADLINE_MS: int = 300_000
const MAX_FRAMES: int = 60000
const AI_ERROR_AI: float = 200.0

var _winner: String = ""


func _ready() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	game.name = "Game"
	add_child(game)
	GameManager.match_over.connect(_on_match_over)
	call_deferred("_drive")


func _on_match_over(winner: String) -> void:
	_winner = winner


func _feed_accept() -> void:
	var ev = InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)


func _drive() -> void:
	GameManager.reset_match()
	UpgradePool.rng.seed = SEED
	UpgradePool.stacks = {}
	UpgradePool.stub_activated = {}
	UpgradePool._available = UpgradePool.get_definitions().duplicate()
	var player = get_node_or_null("Game/PlayerPaddle")
	var ai = get_node_or_null("Game/AIPaddle")
	if player == null or ai == null:
		printerr("[L2] paddles missing — Main.tscn 结构异常")
		get_tree().quit(1)
		return
	player.mode = 1
	ai.mode = 1
	ai.ai_position_error = AI_ERROR_AI
	_feed_accept()                        # FSM MENU → SERVING（开局）
	var start_ms: int = Time.get_ticks_msec()
	var frame: int = 0
	while not GameManager.is_run_over() and frame < MAX_FRAMES \
			and Time.get_ticks_msec() - start_ms < DEADLINE_MS:
		var ui = get_node_or_null("Game/UpgradePickUI")
		if ui != null and ui.visible:
			_feed_accept()                # 升级窗口确认（焦点 0，确定性）
		await get_tree().process_frame
		frame += 1
	var ok: bool = GameManager.is_run_over() and _winner != "" \
		and Time.get_ticks_msec() - start_ms < DEADLINE_MS
	print("[L2 playthrough] run_over=%s winner='%s' score=%d:%d frames=%d elapsed=%dms → %s" % [
		GameManager.is_run_over(), _winner, GameManager.player_score, GameManager.ai_score,
		frame, Time.get_ticks_msec() - start_ms, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
