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
	# I1: 位移（AC6）——120 physics frames = 2s @ 60fps
	var PlayerControllerScript = preload("res://gdscripts/player_controller.gd")
	var p = PlayerControllerScript.new()
	root.add_child(p)
	Input.action_press("game_move_right")
	for i in range(120):
		await physics_frame
	if p.position.x < 100.0:
		print("SMOKE FAIL: I1 displacement %.1f px < 100 px after 2s move_right (AC6)" % p.position.x)
		_failed = true
	Input.action_release("game_move_right")

	# I2: 边沿信号捕获（实例方法捕获，避免 lambda 值捕获）
	InputController.attack_pressed.connect(_on_attack)
	InputController.guard_pressed.connect(_on_guard)
	InputController.dash_pressed.connect(_on_dash)

	Input.action_press("game_light_attack")
	await physics_frame
	Input.action_release("game_light_attack")
	await physics_frame
	if _attack_cap == 0:
		print("SMOKE FAIL: I2 attack_pressed not captured")
		_failed = true

	Input.action_press("game_guard")
	await physics_frame
	Input.action_release("game_guard")
	await physics_frame
	if _guard_cap == 0:
		print("SMOKE FAIL: I2 guard_pressed not captured")
		_failed = true

	Input.action_press("game_dash")
	await physics_frame
	await physics_frame
	Input.action_release("game_dash")
	await physics_frame
	if _dash_cap == 0:
		print("SMOKE FAIL: I2 dash_pressed not captured (light press = step)")
		_failed = true

	InputController.attack_pressed.disconnect(_on_attack)
	InputController.guard_pressed.disconnect(_on_guard)
	InputController.dash_pressed.disconnect(_on_dash)

	root.remove_child(p)
	p.queue_free()
	print("SMOKE OK: shandong-wolf skeleton loads + #573 input/movement AC6")
	quit(1 if _failed else 0)
