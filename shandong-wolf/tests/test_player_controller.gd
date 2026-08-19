extends Object
## Test suite for PlayerController (#573) — acceleration movement (AC6),
## movement edge cases, and InputController integration.
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/573-input-map-player-controller.md §8 Scenario F-H
##
## PlayerController is a CharacterBody2D; instances are spawned into the
## SceneTree root (self.root = SceneTree.root) so _ready / add_to_group("player")
## run and move_and_slide() has a valid world, then driven by manually calling
## _physics_process(1/60) — synchronous, no await.
## NOTE: class_name may not resolve in --script mode, so the script is accessed
## via preload. The InputController autoload global name resolves at runtime
## once it is registered in project.godot [autoload].

const PlayerControllerScript = preload("res://gdscripts/player_controller.gd")
const WolfConstantsScript = preload("res://gdscripts/constants.gd")

const DELTA: float = 1.0 / 60.0
const STEPS_2S: int = 120

var passed: int = 0
var failed: int = 0

var root: Node = null


func run() -> void:
	print("\n=== PlayerController Tests ===")
	_test_f1_displacement()
	_test_f2_acceleration_model()
	_test_f3_velocity_cap()
	_test_g1_left_right_cancel()
	_test_g2_idle_stillness()
	_test_g3_group_membership()
	_test_h1_autoload_resolves()
	_test_h2_edge_events_not_swallowed()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _get_root() -> Node:
	if root == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		root = tree.root
	return root


func _spawn_player() -> CharacterBody2D:
	var p = PlayerControllerScript.new()
	_get_root().add_child(p)
	return p


func _cleanup_player(p: Node) -> void:
	_get_root().remove_child(p)
	p.queue_free()


# ── Scenario F: movement / acceleration ──

func _test_f1_displacement() -> void:
	var p: CharacterBody2D = _spawn_player()
	Input.action_press("game_move_right")
	for i in range(STEPS_2S):
		p._physics_process(DELTA)
	_assert(p.position.x >= 100.0, "F1: 120 steps (2s @ 60fps) of move_right → position.x >= 100px (AC6)")
	Input.action_release("game_move_right")
	_cleanup_player(p)


func _test_f2_acceleration_model() -> void:
	var p: CharacterBody2D = _spawn_player()
	Input.action_press("game_move_right")
	p._physics_process(DELTA)
	_assert(p.velocity.x > 0.0, "F2: velocity.x > 0 after first step (accelerates from standstill)")
	var increasing: bool = true
	var prev: float = 0.0
	for i in range(15):
		p._physics_process(DELTA)
		if p.velocity.x < prev:
			increasing = false
		prev = p.velocity.x
	_assert(increasing, "F2: velocity.x increases across early steps (move_toward ramp)")
	_assert(p.velocity.x <= WolfConstantsScript.MOVE_MAX_SPEED + 0.0001, "F2: velocity.x never exceeds MOVE_MAX_SPEED during ramp")
	for i in range(104):
		p._physics_process(DELTA)
	_assert(abs(p.velocity.x - WolfConstantsScript.MOVE_MAX_SPEED) < 1.0, "F2: velocity.x converges toward MOVE_MAX_SPEED")
	Input.action_release("game_move_right")
	_cleanup_player(p)


func _test_f3_velocity_cap() -> void:
	var p: CharacterBody2D = _spawn_player()
	Input.action_press("game_move_right")
	for i in range(STEPS_2S):
		p._physics_process(DELTA)
	_assert(p.velocity.x <= WolfConstantsScript.MOVE_MAX_SPEED + 0.0001, "F3: velocity.x <= MOVE_MAX_SPEED after 2s (no overspeed)")
	Input.action_release("game_move_right")
	_cleanup_player(p)


# ── Scenario G: movement edge cases ──

func _test_g1_left_right_cancel() -> void:
	var p: CharacterBody2D = _spawn_player()
	Input.action_press("game_move_left")
	Input.action_press("game_move_right")
	for i in range(5):
		p._physics_process(DELTA)
	_assert(abs(p.velocity.x) < 1.0, "G1: left+right pressed → get_axis() == 0 → velocity.x ≈ 0 (no crash)")
	Input.action_release("game_move_left")
	Input.action_release("game_move_right")
	_cleanup_player(p)


func _test_g2_idle_stillness() -> void:
	var p: CharacterBody2D = _spawn_player()
	Input.action_press("game_move_right")
	for i in range(10):
		p._physics_process(DELTA)
	Input.action_release("game_move_right")
	for i in range(20):
		p._physics_process(DELTA)  # velocity decays to 0
	var pos_before: Vector2 = p.position
	for i in range(5):
		p._physics_process(DELTA)
	_assert(p.velocity.x < 0.001, "G2: velocity.x decays toward 0 after release")
	_assert(p.position == pos_before, "G2: position does not drift once velocity reaches 0")
	_cleanup_player(p)


func _test_g3_group_membership() -> void:
	var p: CharacterBody2D = _spawn_player()
	_assert(p.is_in_group("player"), "G3: player is in group 'player' after add_child (_ready ran)")
	_cleanup_player(p)


# ── Scenario H: player-input integration ──

func _test_h1_autoload_resolves() -> void:
	var singleton = InputController
	_assert(singleton != null, "H1: InputController autoload global name resolves (non-null)")
	_assert(singleton != null and singleton.has_method("get_move_axis"), "H1: autoload exposes get_move_axis() (movement is driven through it, not raw polling)")


func _test_h2_edge_events_not_swallowed() -> void:
	var p: CharacterBody2D = _spawn_player()
	var cap: AttackCapture = AttackCapture.new()
	InputController.attack_pressed.connect(cap.on_attack)
	Input.action_press("game_move_right")
	for i in range(3):
		p._physics_process(DELTA)  # movement is active
	Input.action_press("game_light_attack")
	InputController._process(0.016)  # autoload edge detection
	_assert(cap.count == 1, "H2: attack_pressed captured while player is moving (PlayerController does not swallow edge events)")
	Input.action_release("game_light_attack")
	InputController._process(0.016)
	InputController.attack_pressed.disconnect(cap.on_attack)
	Input.action_release("game_move_right")
	_cleanup_player(p)


class AttackCapture:
	extends RefCounted

	var count: int = 0

	func on_attack() -> void:
		count += 1
