extends RefCounted
## Failure Screen test suite (#391) — 失败屏。
## Covers docs/DESIGN/391-failure-screen.md §8 Scenarios A–G（测试契约）。
## 断言风格沿用既有套件：_assert 计数 passed/failed；mock 模式参照 test_pause（FSM + mock 节点装配）
## 与 test_game_state_machine（ball mock 记录 set_frozen）。GameManager 用真实 autoload（reset 隔离）。
##
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const RUN_STATS_FORMAT: String = "波次 %d · 拆砖 %d · 穿墙 %d"

# JSON 分档期望文本（#396 wave-failure-text/v1 草稿值，draft:true；机械选句断言契约 §8 B 组）
const FP1_TEXT: String = "雨还在下"
const FP2_TEXT: String = "雨记住了这一局"
const FP3_TEXT: String = "就差一道墙"
const FP4_TEXT: String = "墙还在，雨未停"

# 测试注入用临时 JSON 路径（user:// 可写；run_tests 每次重写）
const TMP_CFG: String = "user://test_failure_cfg.json"
const TMP_BAD: String = "user://test_failure_bad.json"
const TMP_SCHEMA: String = "user://test_failure_schema.json"
const TMP_EMPTY: String = "user://test_failure_empty.json"


func run() -> void:
	print("\n=== Failure Screen Tests (#391) ===")
	# Scenario A: 失败分支渲染（AC1/AC2/AC3）
	_test_a1_fail_switch()
	_test_a2_three_run_stats()
	_test_a3_stats_from_gamemanager()
	# Scenario B: 短句分档选句（AC3）
	_test_b1_tier1_early_fail()
	_test_b2_tier2_mid_fail()
	_test_b3_tier3_late_fail()
	_test_b4_fallback_tier()
	_test_b5_config_driven_no_hardcode()
	# Scenario C: 配置容错（Flow 2）
	_test_c1_missing_file()
	_test_c2_parse_failure()
	_test_c3_schema_mismatch_empty()
	# Scenario D: 终局暂停（AC4）
	_test_d1_ball_frozen_on_game_over()
	_test_d2_ball_position_unchanged()
	_test_d3_scoring_impossible()
	_test_d4_ball_unfrozen_on_exit()
	# Scenario E: 重开（AC5）
	_test_e1_reset_zeroes()
	_test_e2_new_run_wave_one()
	_test_e3_screen_hidden_after_restart()
	# Scenario F: win 分支回归
	_test_f1_win_branch_preserved()
	# Scenario G: headless 安全
	_test_g1_bare_script_safe()
	_test_g2_missing_labels_safe()
	print("  Failure Screen: %d passed, %d failed" % [passed, failed])


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_screen() -> CanvasLayer:
	"""Create a bare GameOverScreen instance (script attached, not in tree)."""
	var script = load("res://gdscripts/game_over_screen.gd")
	var screen = CanvasLayer.new()
	screen.set_script(script)
	screen.name = "GameOverScreen"
	return screen


func _wire_labels(screen: CanvasLayer, with_stats: bool = true) -> Dictionary:
	"""Manually assign @onready label references (Pattern: test_pause FSM mock assignment)."""
	var winner := Label.new()
	winner.name = "WinnerLabel"
	var restart := Label.new()
	restart.name = "RestartPromptLabel"
	screen.winner_label = winner
	screen.restart_label = restart
	var labels := {"winner": winner, "restart": restart}
	if with_stats:
		var fp := Label.new()
		fp.name = "FailurePhraseLabel"
		var rs := Label.new()
		rs.name = "RunStatsLabel"
		screen.failure_phrase_label = fp
		screen.run_stats_label = rs
		labels["phrase"] = fp
		labels["stats"] = rs
	else:
		screen.failure_phrase_label = null
		screen.run_stats_label = null
	return labels


func _reset_gm() -> void:
	"""Reset the real GameManager autoload between tests."""
	if is_instance_valid(GameManager) and GameManager.has_method("reset_match"):
		GameManager.reset_match()


func _setup_gm_run(wave: int, bricks: int, pierces: int) -> void:
	"""Preset a run state on the real GameManager autoload."""
	_reset_gm()
	GameManager.wave_index = wave
	GameManager.player_brick_count = bricks
	GameManager.player_pierce_count = pierces


func _make_fsm():
	"""FSM instance with mock nodes (test_pause pattern). Returns [fsm, mocks]."""
	var fsm_script = load("res://gdscripts/game_state_machine.gd")
	var fsm = Node.new()
	fsm.set_script(fsm_script)
	fsm.name = "GameStateMachine"

	var ball_script = GDScript.new()
	ball_script.source_code = """extends Area2D
var velocity: Vector2 = Vector2(100, 0)
var frozen: bool = false
var freeze_calls: Array = []
func set_frozen(value: bool) -> void:
	frozen = value
	freeze_calls.append(value)
func _process(delta: float) -> void:
	if frozen:
		return
	position += velocity * delta
"""
	ball_script.reload()
	var ball = Area2D.new()
	ball.set_script(ball_script)
	ball.name = "Ball"
	ball.position = Vector2(640, 360)

	var paddle_script = GDScript.new()
	paddle_script.source_code = """extends Area2D
var frozen: bool = false
func set_frozen(value: bool) -> void:
	frozen = value
"""
	paddle_script.reload()

	var mocks = {
		"start_menu": CanvasLayer.new(),
		"game_hud": CanvasLayer.new(),
		"game_over_screen": CanvasLayer.new(),
		"pause_overlay": CanvasLayer.new(),
		"ball": ball,
		"player_paddle": Area2D.new(),
		"ai_paddle": Area2D.new(),
		"scoring_manager": Node.new(),
	}
	mocks.player_paddle.set_script(paddle_script)
	mocks.ai_paddle.set_script(paddle_script)
	mocks.scoring_manager.add_user_signal("scored", [{"name": "winner", "type": TYPE_STRING}])

	fsm.start_menu = mocks.start_menu
	fsm.game_hud = mocks.game_hud
	fsm.game_over_screen = mocks.game_over_screen
	fsm.pause_overlay = mocks.pause_overlay
	fsm.ball = mocks.ball
	fsm.player_paddle = mocks.player_paddle
	fsm.ai_paddle = mocks.ai_paddle
	fsm.scoring_manager = mocks.scoring_manager
	return [fsm, mocks]


func _make_accept_event() -> InputEventAction:
	var event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	return event


func _write_tmp_json(path: String, content: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()


# ── Scenario A: 失败分支渲染（AC1/AC2/AC3） ──

func _test_a1_fail_switch() -> void:
	"""A-1: 失败切换 — match_over("ai") 后失败屏元素可见、胜者宣告隐藏。"""
	_setup_gm_run(3, 7, 2)
	var screen = _make_screen()
	var labels = _wire_labels(screen)
	screen._on_match_over("ai")
	_assert(labels.winner.visible == false, "A1-1: WinnerLabel hidden on fail")
	_assert(labels.phrase.visible == true, "A1-2: FailurePhraseLabel visible on fail")
	_assert(labels.stats.visible == true, "A1-3: RunStatsLabel visible on fail")
	_assert(screen.visible == true, "A1-4: GameOverScreen visible after match_over")
	_assert(labels.phrase.text.length() > 0, "A1-5: failure phrase non-empty")
	_assert(labels.stats.text.length() > 0, "A1-6: run stats non-empty")
	_reset_gm()


func _test_a2_three_run_stats() -> void:
	"""A-2: 三项 run 数据 — RunStatsLabel 同时含「波次 3」「拆砖 7」「穿墙 2」。"""
	_setup_gm_run(3, 7, 2)
	var screen = _make_screen()
	var labels = _wire_labels(screen)
	screen._on_match_over("ai")
	var text: String = labels.stats.text
	_assert(text.contains("波次 3"), "A2-1: contains 波次 3")
	_assert(text.contains("拆砖 7"), "A2-2: contains 拆砖 7")
	_assert(text.contains("穿墙 2"), "A2-3: contains 穿墙 2")
	_reset_gm()


func _test_a3_stats_from_gamemanager() -> void:
	"""A-3: 数据来自 GameManager — 改 GM 值后渲染随之变化（无本地缓存）。"""
	_setup_gm_run(5, 11, 4)
	var screen = _make_screen()
	var labels = _wire_labels(screen)
	screen._on_match_over("ai")
	var text: String = labels.stats.text
	_assert(text.contains("波次 5"), "A3-1: wave from GameManager (5)")
	_assert(text.contains("拆砖 11"), "A3-2: bricks from GameManager (11)")
	_assert(text.contains("穿墙 4"), "A3-3: pierces from GameManager (4)")
	# 再次改变 GM 值 → 文本变化（证明读取自 GM，非缓存）
	GameManager.wave_index = 9
	GameManager.player_brick_count = 20
	GameManager.player_pierce_count = 1
	screen._on_match_over("ai")
	_assert(labels.stats.text.contains("波次 9"), "A3-4: re-render picks up new wave")
	_assert(labels.stats.text.contains("拆砖 20"), "A3-5: re-render picks up new bricks")
	_reset_gm()


# ── Scenario B: 短句分档选句（AC3） ──

func _test_b1_tier1_early_fail() -> void:
	"""B-1: 档 1（早败）— wave_index 1/2 → fp1；0 走兜底档（fp4）。"""
	var screen = _make_screen()
	_assert(screen._select_failure_phrase(1) == FP1_TEXT, "B1-1: wave 1 → fp1")
	_assert(screen._select_failure_phrase(2) == FP1_TEXT, "B1-2: wave 2 → fp1")
	_assert(screen._select_failure_phrase(0) == FP4_TEXT, "B1-3: wave 0 → fallback fp4 (边界 1)")
	_assert(screen._select_failure_phrase(-1) == FP4_TEXT, "B1-4: negative wave → fallback fp4")


func _test_b2_tier2_mid_fail() -> void:
	"""B-2: 档 2（中败）— wave_index 3/5 → fp2。"""
	var screen = _make_screen()
	_assert(screen._select_failure_phrase(3) == FP2_TEXT, "B2-1: wave 3 → fp2")
	_assert(screen._select_failure_phrase(5) == FP2_TEXT, "B2-2: wave 5 → fp2")


func _test_b3_tier3_late_fail() -> void:
	"""B-3: 档 3（晚败）— wave_index 6/99 → fp3。"""
	var screen = _make_screen()
	_assert(screen._select_failure_phrase(6) == FP3_TEXT, "B3-1: wave 6 → fp3")
	_assert(screen._select_failure_phrase(99) == FP3_TEXT, "B3-2: wave 99 → fp3")


func _test_b4_fallback_tier() -> void:
	"""B-4: 兜底档 — 异常值 → fp4；recommended 优先（同档多条时取 recommended:true）。"""
	var screen = _make_screen()
	_assert(screen._select_failure_phrase(0) == FP4_TEXT, "B4-1: wave 0 → fp4 fallback")
	# recommended 优先：注入同档（兜底档 tier3）两条短语，一条 recommended
	var json := "{\"schema\":\"wave-failure-text/v1\",\"failure_phrases\":[" \
		+ "{\"id\":\"fp4\",\"text\":\"NOT_REC\",\"recommended\":false}," \
		+ "{\"id\":\"fp9\",\"text\":\"REC_TEXT\",\"recommended\":true}]}"
	_write_tmp_json(TMP_CFG, json)
	_assert(screen._select_failure_phrase(0, TMP_CFG) == "REC_TEXT", "B4-2: recommended preferred within tier")


func _test_b5_config_driven_no_hardcode() -> void:
	"""B-5: 配置驱动 + 无硬编码 — 改 JSON text → 屏幕短句变化；代码无文案字面量（默认句除外）。"""
	var screen = _make_screen()
	# 注入改文案的 JSON → 选句随配置变化
	var json := "{\"schema\":\"wave-failure-text/v1\",\"failure_phrases\":[" \
		+ "{\"id\":\"fp1\",\"text\":\"CONFIG_DRIVEN_1\",\"recommended\":true}]}"
	_write_tmp_json(TMP_CFG, json)
	_assert(screen._select_failure_phrase(1, TMP_CFG) == "CONFIG_DRIVEN_1", "B5-1: phrase follows config text")
	# 代码 grep：game_over_screen.gd 不含 fp1-fp4 文案字面量（默认句在 constants.gd，脚本只引用常量）
	var source: String = FileAccess.get_file_as_string("res://gdscripts/game_over_screen.gd")
	_assert(not source.contains(FP1_TEXT), "B5-2: no hardcoded fp1 text in script")
	_assert(not source.contains(FP2_TEXT), "B5-3: no hardcoded fp2 text in script")
	_assert(not source.contains(FP3_TEXT), "B5-4: no hardcoded fp3 text in script")
	_assert(not source.contains(FP4_TEXT), "B5-5: no hardcoded fp4 text in script (default lives in constants.gd)")
	# 默认句红线合规：≤10 字、无感叹号
	_assert(CONSTS.FAILURE_TEXT_DEFAULT_PHRASE.length() <= 10, "B5-6: default phrase <= 10 chars")
	_assert(not CONSTS.FAILURE_TEXT_DEFAULT_PHRASE.contains("!"), "B5-7: default phrase no exclamation")


# ── Scenario C: 配置容错（Flow 2） ──

func _test_c1_missing_file() -> void:
	"""C-1: 文件缺失 — 注入不存在 path → 默认句兜底。"""
	var screen = _make_screen()
	_assert(screen._select_failure_phrase(3, "res://__missing_failure_text__.json") == CONSTS.FAILURE_TEXT_DEFAULT_PHRASE,
		"C1-1: missing file → default phrase")


func _test_c2_parse_failure() -> void:
	"""C-2: 解析失败 — 非法 JSON → 默认句兜底，不崩溃。"""
	var screen = _make_screen()
	_write_tmp_json(TMP_BAD, "this is {not json")
	_assert(screen._select_failure_phrase(3, TMP_BAD) == CONSTS.FAILURE_TEXT_DEFAULT_PHRASE,
		"C2-1: bad JSON → default phrase")


func _test_c3_schema_mismatch_empty() -> void:
	"""C-3: schema 不符 / 空数组 → 默认句兜底。"""
	var screen = _make_screen()
	_write_tmp_json(TMP_SCHEMA, "{\"schema\":\"wrong/v2\",\"failure_phrases\":[{\"id\":\"fp1\",\"text\":\"X\"}]}")
	_assert(screen._select_failure_phrase(3, TMP_SCHEMA) == CONSTS.FAILURE_TEXT_DEFAULT_PHRASE,
		"C3-1: schema mismatch → default phrase")
	_write_tmp_json(TMP_EMPTY, "{\"schema\":\"wave-failure-text/v1\",\"failure_phrases\":[]}")
	_assert(screen._select_failure_phrase(3, TMP_EMPTY) == CONSTS.FAILURE_TEXT_DEFAULT_PHRASE,
		"C3-2: empty failure_phrases → default phrase")


# ── Scenario D: 终局暂停（AC4） ──

func _test_d1_ball_frozen_on_game_over() -> void:
	"""D-1: 冻结调用 — GAME_OVER enter 后 ball mock frozen == true。"""
	var pair = _make_fsm()
	var fsm = pair[0]
	var mocks = pair[1]
	fsm.current_state = fsm.State.GAME_OVER
	fsm.enter_state(fsm.State.GAME_OVER)
	_assert(mocks.ball.frozen == true, "D1-1: ball frozen after GAME_OVER enter")
	_assert(mocks.ball.freeze_calls.size() >= 1 and mocks.ball.freeze_calls[0] == true, "D1-2: set_frozen(true) called")


func _test_d2_ball_position_unchanged() -> void:
	"""D-2: 位置不变 — GAME_OVER 中推进多帧，ball.position 不变（mock _process 带 frozen 早退）。"""
	var pair = _make_fsm()
	var fsm = pair[0]
	var mocks = pair[1]
	fsm.current_state = fsm.State.GAME_OVER
	fsm.enter_state(fsm.State.GAME_OVER)
	var pos_before: Vector2 = mocks.ball.position
	mocks.ball._process(0.016)
	mocks.ball._process(0.016)
	mocks.ball._process(0.016)
	_assert(mocks.ball.position == pos_before, "D2-1: ball position unchanged while frozen")


func _test_d3_scoring_impossible() -> void:
	"""D-3: 计分不可发生 — GAME_OVER 期间 scored 信号被 FSM 忽略。"""
	var pair = _make_fsm()
	var fsm = pair[0]
	fsm.current_state = fsm.State.GAME_OVER
	fsm.enter_state(fsm.State.GAME_OVER)
	fsm._on_scored("player")
	_assert(fsm.current_state == fsm.State.GAME_OVER, "D3-1: state still GAME_OVER (scored ignored)")


func _test_d4_ball_unfrozen_on_exit() -> void:
	"""D-4: 解冻 — SPACE → MENU（GAME_OVER exit）→ set_frozen(false) 被调用；新 run 球可动。"""
	var pair = _make_fsm()
	var fsm = pair[0]
	var mocks = pair[1]
	fsm.current_state = fsm.State.GAME_OVER
	fsm.enter_state(fsm.State.GAME_OVER)
	_assert(mocks.ball.frozen == true, "D4-1: frozen in GAME_OVER")
	# SPACE → MENU
	fsm._input(_make_accept_event())
	_assert(fsm.current_state == fsm.State.MENU, "D4-2: SPACE in GAME_OVER → MENU")
	_assert(mocks.ball.frozen == false, "D4-3: ball unfrozen after exit GAME_OVER")
	_assert(mocks.ball.freeze_calls.size() >= 2 and mocks.ball.freeze_calls[1] == false, "D4-4: set_frozen(false) called")
	# 解冻后 mock _process 位移生效（新 run 球可动）
	var pos_before: Vector2 = mocks.ball.position
	mocks.ball._process(0.016)
	_assert(mocks.ball.position != pos_before, "D4-5: ball moves after unfreeze")


# ── Scenario E: 重开（AC5） ──

func _test_e1_reset_zeroes() -> void:
	"""E-1: 全量归零 — reset_match() 后 wave_index==0、四计数归零、_is_run_over==false。"""
	_setup_gm_run(7, 13, 5)
	GameManager.add_score("ai", 21, "boundary")
	_assert(GameManager.is_run_over() == true, "E1-1: run over preset")
	GameManager.reset_match()
	_assert(GameManager.wave_index == 0, "E1-2: wave_index reset to 0")
	_assert(GameManager.player_brick_count == 0 and GameManager.ai_brick_count == 0, "E1-3: brick counts zeroed")
	_assert(GameManager.player_pierce_count == 0 and GameManager.ai_pierce_count == 0, "E1-4: pierce counts zeroed")
	_assert(GameManager.is_run_over() == false, "E1-5: _is_run_over false after reset")


func _test_e2_new_run_wave_one() -> void:
	"""E-2: 新 run 从波 1 — reset 后首波 begin_wave() → wave_index == 1。"""
	_reset_gm()
	GameManager.begin_wave()
	_assert(GameManager.wave_index == 1, "E2-1: first wave of new run is 1")


func _test_e3_screen_hidden_after_restart() -> void:
	"""E-3: 屏幕复位 — GAME_OVER → MENU 后 GameOverScreen.visible == false（三层切换回归）。"""
	var pair = _make_fsm()
	var fsm = pair[0]
	var mocks = pair[1]
	fsm.current_state = fsm.State.GAME_OVER
	fsm.enter_state(fsm.State.GAME_OVER)
	_assert(mocks.game_over_screen.visible == true, "E3-1: game_over screen visible in GAME_OVER")
	fsm._input(_make_accept_event())
	_assert(mocks.game_over_screen.visible == false, "E3-2: game_over screen hidden after SPACE → MENU")


# ── Scenario F: win 分支回归 ──

func _test_f1_win_branch_preserved() -> void:
	"""F-1: YOU WIN! 保留 — match_over("player") → WinnerLabel 文本/颜色、脉冲；fail 元素隐藏。"""
	_setup_gm_run(3, 7, 2)
	var screen = _make_screen()
	var labels = _wire_labels(screen)
	screen._on_match_over("player")
	_assert(labels.winner.text == "YOU WIN!", "F1-1: winner text preserved")
	var c: Color = labels.winner.modulate
	_assert(abs(c.r - 0.29) < 0.01 and abs(c.g - 0.56) < 0.01 and abs(c.b - 0.85) < 0.01, "F1-2: winner color player blue")
	_assert(labels.phrase.visible == false, "F1-3: FailurePhraseLabel hidden on win")
	_assert(labels.stats.visible == false, "F1-4: RunStatsLabel hidden on win")
	_assert(labels.winner.visible == true, "F1-5: WinnerLabel visible on win")
	_reset_gm()


# ── Scenario G: headless 安全 ──

func _test_g1_bare_script_safe() -> void:
	"""G-1: bare 脚本 — 无树实例 _on_match_over 不崩溃（@onready null → 早退）。"""
	var screen = _make_screen()
	screen._on_match_over("ai")
	screen._on_match_over("player")
	_assert(true, "G1-1: bare script _on_match_over(ai/player) no crash")


func _test_g2_missing_labels_safe() -> void:
	"""G-2: 节点缺失 — 缺 FailurePhraseLabel/RunStatsLabel 时 fail 分支静默跳过、不崩溃（#385 容错延续）。"""
	_setup_gm_run(3, 7, 2)
	var screen = _make_screen()
	_wire_labels(screen, false)
	screen._on_match_over("ai")
	_assert(true, "G2-1: missing stats labels → no crash on fail branch")
	_assert(screen.visible == true, "G2-2: screen still shown")
	_reset_gm()
