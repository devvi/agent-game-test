extends SceneTree
## Smoke test for shandong-wolf — verifies project loads headless + #573 AC6 输入/移动链路.
## Usage: godot --path shandong-wolf/ --headless --script tests/smoke_test.gd
## Exit 0 = OK.
## Scenario I (AC6): I1 移动位移 ≥100px；I2 边沿信号捕获（attack/guard/dash）。
## NOTE: GDScript lambdas capture by value, so signal capture uses instance methods.

var _attack_cap: int = 0
var _guard_cap: int = 0
var _dash_cap: int = 0
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _on_attack() -> void:
	_attack_cap += 1


func _on_guard(_timestamp_ms: int) -> void:
	_guard_cap += 1


func _on_dash() -> void:
	_dash_cap += 1


func _run() -> void:
	# InputController 是 lazy autoload（project.godot 中 "*res://gdscripts/input_controller.gd"）：
	# --script 主脚本编译早于 autoload 注册，标识符 "InputController" 不可解析（CI smoke 失败根因），
	# 且 Engine.get_singleton() 对 lazy autoload 返回 null —— 必须用 root.get_node_or_null() 运行时获取。
	var ic: Node = root.get_node_or_null("InputController")
	if ic == null:
		print("SMOKE FAIL: InputController autoload not available")
		_failed = true
		quit(1)
		return

	# I1: 位移（AC6）——120 physics frames = 2s @ 60fps
	# 用 load() 而非 preload()：preload 在脚本编译期解析，会再次触发 autoload 标识符编译错误。
	var PlayerControllerScript = load("res://gdscripts/player_controller.gd")
	var p = PlayerControllerScript.new()
	root.add_child(p)
	Input.action_press("game_move_right")
	for i in range(120):
		await physics_frame
	if p.position.x < 100.0:
		print("SMOKE FAIL: I1 displacement %.1f px < 100 px after 2s move_right (AC6)" % p.position.x)
		_failed = true
	Input.action_release("game_move_right")

	# I2: 边沿信号捕获——用真实 InputController autoload（不新建实例、不释放）。
	# 确定性驱动: 手动 _process(0.016)（与 test_input_controller.gd 同款），
	# 规避 headless 下 physics/idle 帧序竞态（await physics_frame 曾随机漏采边沿）。
	ic.attack_pressed.connect(_on_attack)
	ic.guard_pressed.connect(_on_guard)
	ic.dash_pressed.connect(_on_dash)

	Input.action_press("game_light_attack")
	ic._process(0.016)
	Input.action_release("game_light_attack")
	ic._process(0.016)
	if _attack_cap == 0:
		print("SMOKE FAIL: I2 attack_pressed not captured")
		_failed = true

	Input.action_press("game_guard")
	ic._process(0.016)
	Input.action_release("game_guard")
	ic._process(0.016)
	if _guard_cap == 0:
		print("SMOKE FAIL: I2 guard_pressed not captured")
		_failed = true

	Input.action_press("game_dash")
	ic._process(0.016)
	Input.action_release("game_dash")
	ic._process(0.016)
	if _dash_cap == 0:
		print("SMOKE FAIL: I2 dash_pressed not captured (light press = step)")
		_failed = true

	ic.attack_pressed.disconnect(_on_attack)
	ic.guard_pressed.disconnect(_on_guard)
	ic.dash_pressed.disconnect(_on_dash)

	root.remove_child(p)
	p.queue_free()
	print("SMOKE OK: shandong-wolf skeleton loads + #573 input/movement AC6")
	quit(1 if _failed else 0)
