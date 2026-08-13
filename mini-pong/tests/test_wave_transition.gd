extends RefCounted
## Wave Transition test suite (#390 契约 PRD #429 §5；实现随 #393 组装落地)。
## AC1: wave_started → 「第 N 道墙」+ 分档副句（1-2→ws1 / 3-5→ws2 / 6+→ws3 /
##      任一方 ≥18 → ws4 决胜波覆盖）
## AC2: 三段时长和恒 == 2.0；转场结束后覆盖层隐藏（短时长注入测试）
## AC3: 转场期间 ball + 双拍冻结，结束后解锁（兜底必达）
## AC5: 副句来自 JSON（脚本零硬编码 —— 断言脚本源码不含任何 JSON 副句文本）
## Runs under godot --headless --script via run_tests.gd (_run_async)。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")

var _json_data: Dictionary = {}
var _json_loaded: bool = false


func run() -> void:
	print("\n=== Wave Transition Tests (#390) ===")
	_load_json()
	await _test_ac1_title_and_band_subtitles()
	await _test_ac1_decisive_overrides()
	await _test_ac2_duration_and_hide()
	await _test_ac3_freeze_unfreeze()
	await _test_ac5_json_source_no_hardcode()
	print("  Wave Transition: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout


func _load_json() -> void:
	var text: String = FileAccess.get_file_as_string(CONSTS.WAVE_TRANSITION_JSON_PATH)
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_json_data = parsed
		_json_loaded = true


func _subtitle_text_by_id(id: String) -> String:
	if not _json_loaded:
		return ""
	var subs = _json_data.get("wave_subtitles", [])
	for entry in subs:
		if entry.get("id", "") == id:
			return entry.get("text", "")
	return ""


func _all_subtitle_texts() -> Array:
	var out: Array = []
	if not _json_loaded:
		return out
	var subs = _json_data.get("wave_subtitles", [])
	for entry in subs:
		out.append(entry.get("text", ""))
	return out


func _make_mock_ball() -> Node2D:
	var code = GDScript.new()
	code.source_code = """extends Node2D
## Mock Ball (test_wave_transition.gd 内部使用)
var frozen: bool = false
func set_frozen(value: bool) -> void:
	frozen = value
"""
	code.reload()
	var ball = Node2D.new()
	ball.name = "Ball"
	ball.set_script(code)
	ball.add_to_group("balls")
	(Engine.get_main_loop() as SceneTree).root.add_child(ball)
	return ball


func _make_mock_paddle(pname: String) -> Node2D:
	var code = GDScript.new()
	code.source_code = """extends Node2D
## Mock Paddle (test_wave_transition.gd 内部使用)
var frozen: bool = false
func set_frozen(value: bool) -> void:
	frozen = value
"""
	code.reload()
	var paddle = Node2D.new()
	paddle.name = pname
	paddle.set_script(code)
	paddle.add_to_group("paddles")
	(Engine.get_main_loop() as SceneTree).root.add_child(paddle)
	return paddle


## 构建测试环境：真实 wave_transition.tscn + mock 球/双拍；注入短时长。
func _make_fx() -> Dictionary:
	var scene = load("res://scenes/wave_transition.tscn")
	var ctrl = scene.instantiate()
	ctrl.name = "WaveTransition"
	(Engine.get_main_loop() as SceneTree).root.add_child(ctrl)
	ctrl.fade_in = 0.01
	ctrl.hold = 0.01
	ctrl.fade_out = 0.01
	var ball = _make_mock_ball()
	var p1 = _make_mock_paddle("PlayerPaddle")
	var p2 = _make_mock_paddle("AIPaddle")
	return {"ctrl": ctrl, "ball": ball, "p1": p1, "p2": p2}


func _cleanup(fx: Dictionary) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	for key in ["ctrl", "ball", "p1", "p2"]:
		var n = fx.get(key)
		if n != null and is_instance_valid(n) and n.get_parent() != null:
			n.get_parent().remove_child(n)
			n.queue_free()
	await _wait(0.05)


# ── AC1: 大字 + 分档副句 ──

func _test_ac1_title_and_band_subtitles() -> void:
	GameManager.reset_match()
	var fx = _make_fx()
	await _wait(0.02)   # _ready 完成接线

	# 波 1（0:0）→ ws1
	GameManager.begin_wave()
	var title: Label = fx.ctrl.get_node("Overlay/Center/VBox/TitleLabel")
	var sub: Label = fx.ctrl.get_node("Overlay/Center/VBox/SubtitleLabel")
	_assert(title.text == "第 1 道墙", "AC1: 大字 == '第 1 道墙' (got '%s')" % title.text)
	_assert(sub.text == _subtitle_text_by_id("ws1"), "AC1: 波 1 → ws1 副句 (got '%s')" % sub.text)
	await _wait(0.2)   # 转场结束

	# 波 4 → ws2（波次分档 3-5）
	GameManager.reset_match()
	GameManager.wave_index = 3
	GameManager.begin_wave()   # → 4
	_assert(sub.text == _subtitle_text_by_id("ws2"), "AC1: 波 4 → ws2 副句 (got '%s')" % sub.text)
	await _wait(0.2)

	# 波 6 → ws3（波次分档 6+）
	GameManager.reset_match()
	GameManager.wave_index = 5
	GameManager.begin_wave()   # → 6
	_assert(sub.text == _subtitle_text_by_id("ws3"), "AC1: 波 6 → ws3 副句 (got '%s')" % sub.text)
	await _wait(0.2)

	await _cleanup(fx)


## 决胜波覆盖：任一方 ≥18 时即使波 1 也取 ws4
func _test_ac1_decisive_overrides() -> void:
	GameManager.reset_match()
	for i in range(18):
		GameManager.add_score("player")
	var fx = _make_fx()
	await _wait(0.02)
	GameManager.wave_index = 0
	GameManager.begin_wave()   # 波 1，但 player=18 → ws4
	var sub: Label = fx.ctrl.get_node("Overlay/Center/VBox/SubtitleLabel")
	_assert(sub.text == _subtitle_text_by_id("ws4"), "AC1: 决胜波 → ws4 覆盖 (got '%s')" % sub.text)
	await _wait(0.2)
	await _cleanup(fx)


# ── AC2: 三段和 == 2.0；结束后隐藏 ──

func _test_ac2_duration_and_hide() -> void:
	_assert(abs((CONSTS.WAVE_TRANSITION_FADE_IN + CONSTS.WAVE_TRANSITION_HOLD + CONSTS.WAVE_TRANSITION_FADE_OUT) - 2.0) < 0.001,
		"AC2: 三段时长和恒 == 2.0")
	GameManager.reset_match()
	var fx = _make_fx()
	await _wait(0.02)
	GameManager.begin_wave()
	_assert(fx.ctrl.visible == true, "AC2: 转场中覆盖层可见")
	await _wait(0.3)
	_assert(fx.ctrl.visible == false, "AC2: 转场结束覆盖层隐藏")
	_assert(fx.ctrl._transitioning == false, "AC2: 转场锁复位")
	var overlay = fx.ctrl.get_node("Overlay")
	_assert(abs(overlay.modulate.a - 0.0) < 0.01, "AC2: 覆盖层透明度归零")
	await _cleanup(fx)


# ── AC3: 冻结/解锁 ──

func _test_ac3_freeze_unfreeze() -> void:
	GameManager.reset_match()
	var fx = _make_fx()
	await _wait(0.02)
	GameManager.begin_wave()
	_assert(fx.ball.frozen == true, "AC3: 转场中球冻结")
	_assert(fx.p1.frozen == true and fx.p2.frozen == true, "AC3: 转场中双拍冻结")
	await _wait(0.3)
	_assert(fx.ball.frozen == false, "AC3: 转场后球解锁")
	_assert(fx.p1.frozen == false and fx.p2.frozen == false, "AC3: 转场后双拍解锁")
	await _cleanup(fx)


# ── AC5: 副句零硬编码（来源 = JSON）──

func _test_ac5_json_source_no_hardcode() -> void:
	_assert(_json_loaded, "AC5: wave_failure_text.json 可读")
	var src: String = FileAccess.get_file_as_string("res://gdscripts/wave_transition_controller.gd")
	for t in _all_subtitle_texts():
		_assert(not src.contains(t), "AC5: 脚本不含硬编码副句 '%s'" % t)
	_assert(src.contains(CONSTS.WAVE_TRANSITION_JSON_PATH),
		"AC5: 脚本引用 WAVE_TRANSITION_JSON_PATH 常量")
