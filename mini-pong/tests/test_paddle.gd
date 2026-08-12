extends RefCounted
## Test suite for paddle.gd (#288) — 12 automated + 1 structural + 1 CI-covered.
## Runs under godot --headless --script via run_tests.gd.
## 竖屏重写 (#383): 输入 A/D + ←/→ (paddle_left/paddle_right)，旧 paddle_up/paddle_down
## 必须不存在；移动轴 X；夹取 min_x=60 / max_x=660。

var passed: int = 0
var failed: int = 0


func run() -> void:
	_test_inputmap_creation()       # TC-A1
	_test_key_bindings()            # TC-A2
	_test_no_duplicate_binding()    # TC-A3
	_test_movement_left()           # TC-B1
	_test_movement_right()          # TC-B2
	_test_simultaneous_cancel()     # TC-B3 (structural)
	_test_no_input()                # TC-B4
	_test_left_clamp()              # TC-C1
	_test_right_clamp()             # TC-C2
	_test_startup_clamp()           # TC-C3
	_test_node_hierarchy()          # TC-E1
	_test_collision_shape()         # TC-E2
	_test_script_attachment()       # TC-E3
	# TC-D1 (zero exit code) and TC-D2 (no script errors) are covered by CI.


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_paddle():
	var paddle = Area2D.new()
	paddle.set_script(load("res://gdscripts/paddle.gd"))
	return paddle


# ── Scenario A: InputMap Binding (竖屏 A/D + ←/→, #383) ──

func _test_inputmap_creation() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	_assert(InputMap.has_action("paddle_left"), "TC-A1: paddle_left action exists")
	_assert(InputMap.has_action("paddle_right"), "TC-A1: paddle_right action exists")
	# 旧动作必须删除（不是只加不删）— 验收条件 AC3
	_assert(not InputMap.has_action("paddle_up"), "TC-A1: paddle_up action REMOVED")
	_assert(not InputMap.has_action("paddle_down"), "TC-A1: paddle_down action REMOVED")


func _test_key_bindings() -> void:
	var paddle = _make_paddle()
	paddle._ready()

	var left_events = InputMap.action_get_events("paddle_left")
	var left_keys: Array = []
	for ev in left_events:
		if ev is InputEventKey:
			left_keys.append(ev.keycode)
	_assert(left_keys.has(KEY_A), "TC-A2: paddle_left bound to A")
	_assert(left_keys.has(KEY_LEFT), "TC-A2: paddle_left bound to LEFT arrow")

	var right_events = InputMap.action_get_events("paddle_right")
	var right_keys: Array = []
	for ev in right_events:
		if ev is InputEventKey:
			right_keys.append(ev.keycode)
	_assert(right_keys.has(KEY_D), "TC-A2: paddle_right bound to D")
	_assert(right_keys.has(KEY_RIGHT), "TC-A2: paddle_right bound to RIGHT arrow")


func _test_no_duplicate_binding() -> void:
	var paddle1 = _make_paddle()
	paddle1._ready()
	var left_count_before = InputMap.action_get_events("paddle_left").size()

	var paddle2 = _make_paddle()
	paddle2._ready()
	var left_count_after = InputMap.action_get_events("paddle_left").size()

	_assert(left_count_after == left_count_before, "TC-A3: no duplicate events on second instantiation")
	_assert(left_count_after == 2, "TC-A3: paddle_left still has exactly 2 events")


# ── Scenario B: Movement (headless — Input always returns false) ──

func _test_movement_left() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.x = 500.0
	paddle._process(0.016)
	_assert(paddle.position.x >= paddle.min_x, "TC-B1: position not below min_x after _process")
	_assert(paddle.position.x <= paddle.max_x, "TC-B1: position not above max_x after _process")


func _test_movement_right() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.x = 100.0
	paddle._process(0.016)
	_assert(paddle.position.x >= paddle.min_x, "TC-B2: position not below min_x after _process")
	_assert(paddle.position.x <= paddle.max_x, "TC-B2: position not above max_x after _process")


func _test_simultaneous_cancel() -> void:
	var source = FileAccess.get_file_as_string("res://gdscripts/paddle.gd")
	_assert(source != "", "TC-B3: paddle.gd source readable")
	_assert(source.contains("if left and not right:"), "TC-B3: left-only guard exists in source")
	_assert(source.contains("elif right and not left:"), "TC-B3: right-only guard exists in source")
	# The `if left and not right: ... elif right and not left:` pattern
	# ensures both-pressed → move = 0.0 (cancel).


func _test_no_input() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	var start_x = 360.0
	paddle.position.x = start_x
	paddle._process(0.016)
	_assert(paddle.position.x == start_x, "TC-B4: position unchanged with no input")


# ── Scenario C: Boundary Clamping (min_x=60 / max_x=660, #383) ──

func _test_left_clamp() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.x = -1000.0
	paddle._process(0.016)
	_assert(paddle.position.x == paddle.min_x, "TC-C1: clamped to min_x (left boundary)")
	_assert(abs(paddle.min_x - 60.0) < 0.01, "TC-C1: min_x == 60")


func _test_right_clamp() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.x = 2000.0
	paddle._process(0.016)
	_assert(paddle.position.x == paddle.max_x, "TC-C2: clamped to max_x (right boundary)")
	_assert(abs(paddle.max_x - 660.0) < 0.01, "TC-C2: max_x == 660")


func _test_startup_clamp() -> void:
	var paddle = _make_paddle()
	paddle.position.x = -500.0  # before _ready()
	paddle._ready()
	_assert(paddle.position.x >= paddle.min_x, "TC-C3: position >= min_x after _ready()")
	_assert(paddle.position.x <= paddle.max_x, "TC-C3: position <= max_x after _ready()")


# ── Scenario E: Scene Integrity ──

func _test_node_hierarchy() -> void:
	var scene = load("res://scenes/player_paddle.tscn")
	_assert(scene != null, "TC-E1: player_paddle.tscn loaded")
	var paddle = scene.instantiate()
	_assert(paddle is Area2D, "TC-E1: root is Area2D")
	_assert(paddle.has_node("ColorRect"), "TC-E1: has ColorRect child")
	_assert(paddle.has_node("CollisionShape2D"), "TC-E1: has CollisionShape2D child")


func _test_collision_shape() -> void:
	var scene = load("res://scenes/player_paddle.tscn")
	var paddle = scene.instantiate()
	var cs = paddle.get_node("CollisionShape2D")
	_assert(cs != null, "TC-E2: CollisionShape2D node found")
	var shape = cs.shape
	_assert(shape is RectangleShape2D, "TC-E2: shape is RectangleShape2D")
	# 竖屏横置 (#383): 120 长 × 20 厚
	_assert(abs(shape.size.x - 120.0) < 0.01, "TC-E2: shape width == 120 (横向长度)")
	_assert(abs(shape.size.y - 20.0) < 0.01, "TC-E2: shape height == 20 (纵向厚度)")


func _test_script_attachment() -> void:
	var scene = load("res://scenes/player_paddle.tscn")
	var paddle = scene.instantiate()
	var script = paddle.get_script()
	_assert(script != null, "TC-E3: script attached")
	_assert(script.resource_path.contains("paddle.gd"), "TC-E3: script path contains paddle.gd")
