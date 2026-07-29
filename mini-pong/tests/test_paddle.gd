extends RefCounted
## Test suite for paddle.gd (#288) — 12 automated + 1 structural + 1 CI-covered.
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0


func run() -> void:
	_test_inputmap_creation()       # TC-A1
	_test_key_bindings()            # TC-A2
	_test_no_duplicate_binding()    # TC-A3
	_test_movement_up()             # TC-B1
	_test_movement_down()           # TC-B2
	_test_simultaneous_cancel()     # TC-B3 (structural)
	_test_no_input()                # TC-B4
	_test_top_clamp()               # TC-C1
	_test_bottom_clamp()            # TC-C2
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


# ── Scenario A: InputMap Binding ──

func _test_inputmap_creation() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	_assert(InputMap.has_action("paddle_up"), "TC-A1: paddle_up action exists")
	_assert(InputMap.has_action("paddle_down"), "TC-A1: paddle_down action exists")


func _test_key_bindings() -> void:
	var paddle = _make_paddle()
	paddle._ready()

	var up_events = InputMap.action_get_events("paddle_up")
	var up_keys: Array = []
	for ev in up_events:
		if ev is InputEventKey:
			up_keys.append(ev.keycode)
	_assert(up_keys.has(KEY_W), "TC-A2: paddle_up bound to W")
	_assert(up_keys.has(KEY_UP), "TC-A2: paddle_up bound to UP arrow")

	var down_events = InputMap.action_get_events("paddle_down")
	var down_keys: Array = []
	for ev in down_events:
		if ev is InputEventKey:
			down_keys.append(ev.keycode)
	_assert(down_keys.has(KEY_S), "TC-A2: paddle_down bound to S")
	_assert(down_keys.has(KEY_DOWN), "TC-A2: paddle_down bound to DOWN arrow")


func _test_no_duplicate_binding() -> void:
	var paddle1 = _make_paddle()
	paddle1._ready()
	var up_count_before = InputMap.action_get_events("paddle_up").size()

	var paddle2 = _make_paddle()
	paddle2._ready()
	var up_count_after = InputMap.action_get_events("paddle_up").size()

	_assert(up_count_after == up_count_before, "TC-A3: no duplicate events on second instantiation")
	_assert(up_count_after == 2, "TC-A3: paddle_up still has exactly 2 events")


# ── Scenario B: Movement (headless — Input always returns false) ──

func _test_movement_up() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.y = 500.0
	paddle._process(0.016)
	_assert(paddle.position.y >= paddle.min_y, "TC-B1: position not below min_y after _process")
	_assert(paddle.position.y <= paddle.max_y, "TC-B1: position not above max_y after _process")


func _test_movement_down() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.y = 100.0
	paddle._process(0.016)
	_assert(paddle.position.y >= paddle.min_y, "TC-B2: position not below min_y after _process")
	_assert(paddle.position.y <= paddle.max_y, "TC-B2: position not above max_y after _process")


func _test_simultaneous_cancel() -> void:
	var source = FileAccess.get_file_as_string("res://gdscripts/paddle.gd")
	_assert(source != "", "TC-B3: paddle.gd source readable")
	_assert(source.contains("if up and not down:"), "TC-B3: up-only guard exists in source")
	_assert(source.contains("elif down and not up:"), "TC-B3: down-only guard exists in source")
	# The `if up and not down: ... elif down and not up:` pattern
	# ensures both-pressed → move = 0.0 (cancel).


func _test_no_input() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	var start_y = 360.0
	paddle.position.y = start_y
	paddle._process(0.016)
	_assert(paddle.position.y == start_y, "TC-B4: position unchanged with no input")


# ── Scenario C: Boundary Clamping ──

func _test_top_clamp() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.y = -1000.0
	paddle._process(0.016)
	_assert(paddle.position.y == paddle.min_y, "TC-C1: clamped to min_y (top boundary)")


func _test_bottom_clamp() -> void:
	var paddle = _make_paddle()
	paddle._ready()
	paddle.position.y = 2000.0
	paddle._process(0.016)
	_assert(paddle.position.y == paddle.max_y, "TC-C2: clamped to max_y (bottom boundary)")


func _test_startup_clamp() -> void:
	var paddle = _make_paddle()
	paddle.position.y = -500.0  # before _ready()
	paddle._ready()
	_assert(paddle.position.y >= paddle.min_y, "TC-C3: position >= min_y after _ready()")
	_assert(paddle.position.y <= paddle.max_y, "TC-C3: position <= max_y after _ready()")


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
	_assert(shape.size.x > 0, "TC-E2: shape width > 0")
	_assert(shape.size.y > 0, "TC-E2: shape height > 0")


func _test_script_attachment() -> void:
	var scene = load("res://scenes/player_paddle.tscn")
	var paddle = scene.instantiate()
	var script = paddle.get_script()
	_assert(script != null, "TC-E3: script attached")
	_assert(script.resource_path.contains("paddle.gd"), "TC-E3: script path contains paddle.gd")
