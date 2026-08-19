extends Object
## Test suite for InputController (#573) — input buffer no-swallow (AC4/AC5),
## guard same-key dual meaning (AC2), buffer consume semantics, dash dual meaning,
## and validation / illegal-value tolerance (PRD §5.3).
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/573-input-map-player-controller.md §8 Scenario A-E
##
## Instances are created fresh via preload.new() and driven manually by calling
## _process(0.016) — they are NOT added to the tree (no _ready, no engine loop).
## NOTE: class_name may not resolve in --script mode, so the script is accessed
## via preload. GDScript lambdas capture by value, so signal capture uses inner
## RefCounted handler classes connected with .connect(cap.on_...).

const InputControllerScript = preload("res://gdscripts/input_controller.gd")
const WolfConstantsScript = preload("res://gdscripts/constants.gd")

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== InputController Tests ===")
	_test_e1_missing_action_validation()  # runs first: restores the Input Map for later tests
	_test_a1_buffer_no_swallow()
	_test_a2_poll_within_window()
	_test_a3_expired_cleanup()
	_test_a4_buffer_max_reject_new()
	_test_a5_fifo_multi_action()
	_test_b1_guard_edge_and_hold()
	_test_b2_guard_release_repress()
	_test_b3_guard_timestamp_semantics()
	_test_b4_parry_window_readonly()
	_test_c1_poll_consumes()
	_test_c2_peek_readonly()
	_test_c3_empty_buffer_safe()
	_test_d1_quick_dash()
	_test_d2_long_press_sprint()
	_test_d3_dash_threshold_boundary()
	_test_e2_safe_window_clamp()
	_test_e3_no_consumers_no_crash()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _new_input() -> Object:
	return InputControllerScript.new()


func _wait_ms(ms: int) -> void:
	## Deterministic wait on the monotonic clock. OS.delay_msec on macOS can
	## overshoot several-fold (measured: 60ms request → 60–208ms actual), which
	## would push spaced inputs past the 150ms buffer window. Busy-waiting on
	## Time.get_ticks_msec() keeps the spacing within ~1ms of the requested value.
	var deadline: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		pass


func _press_buffer(ic: Object, action: String) -> void:
	Input.action_press(action)
	ic._process(0.016)
	Input.action_release(action)
	ic._process(0.016)


# ── Scenario E (validation) runs first so later tests see a clean Input Map ──

func _test_e1_missing_action_validation() -> void:
	var ic: Object = _new_input()
	if InputMap.has_action("game_jump"):
		InputMap.erase_action("game_jump")
	var missing = ic._validate_input_map()
	_assert(missing.has(&"game_jump"), "E1: erased game_jump reported as missing by _validate_input_map()")
	if not InputMap.has_action("game_jump"):
		InputMap.add_action("game_jump")
	var missing_after = ic._validate_input_map()
	_assert(not missing_after.has(&"game_jump"), "E1: game_jump no longer missing after restore (clean map for later tests)")
	ic.free()


# ── Scenario A: input buffer no-swallow ──

func _test_a1_buffer_no_swallow() -> void:
	var ic: Object = _new_input()
	var wait_ms: int = int(int(WolfConstantsScript.INPUT_BUFFER_WINDOW_MS) / 2.0) - 15  # 60ms: 3 presses stay inside the window (AC5)
	for i in range(3):
		Input.action_press("game_light_attack")
		ic._process(0.016)
		Input.action_release("game_light_attack")
		ic._process(0.016)
		if i < 2:
			_wait_ms(wait_ms)
	_assert(ic.buffer_size() == 3, "A1: 3 presses within window → buffer_size() == 3 (no swallow)")
	var ok: bool = true
	for i in range(3):
		var entry: Dictionary = ic.poll_buffer()
		if entry.is_empty() or entry["action"] != &"game_light_attack":
			ok = false
	_assert(ok, "A1: poll_buffer() 3 times → all game_light_attack in FIFO order")
	_assert(ic.poll_buffer().is_empty(), "A1: 4th poll → {} (buffer drained)")
	ic.free()


func _test_a2_poll_within_window() -> void:
	var ic: Object = _new_input()
	Input.action_press("game_light_attack")
	ic._process(0.016)
	Input.action_release("game_light_attack")
	ic._process(0.016)
	_wait_ms(int(int(WolfConstantsScript.INPUT_BUFFER_WINDOW_MS) / 2.0))  # 75ms, still inside the 150ms window
	var entry: Dictionary = ic.poll_buffer()
	_assert(not entry.is_empty() and entry["action"] == &"game_light_attack", "A2: poll within window returns the buffered attack entry")
	_assert(ic.poll_buffer().is_empty(), "A2: buffer drained after poll")
	ic.free()


func _test_a3_expired_cleanup() -> void:
	var ic: Object = _new_input()
	Input.action_press("game_light_attack")
	ic._process(0.016)
	Input.action_release("game_light_attack")
	ic._process(0.016)
	OS.delay_msec(int(WolfConstantsScript.INPUT_BUFFER_WINDOW_MS) + 10)  # 160ms > window (overshoot only strengthens expiry)
	ic._process(0.016)  # expiry cleanup runs
	_assert(ic.buffer_size() == 0, "A3: entry expired after > window → buffer_size() == 0")
	_assert(ic.poll_buffer().is_empty(), "A3: poll after expiry → {} (cleanup is not swallowing)")
	ic.free()


func _test_a4_buffer_max_reject_new() -> void:
	var ic: Object = _new_input()
	for i in range(9):
		Input.action_press("game_light_attack")
		ic._process(0.016)
		Input.action_release("game_light_attack")
		ic._process(0.016)
	_assert(ic.buffer_size() == WolfConstantsScript.INPUT_BUFFER_MAX, "A4: 9 rapid presses → buffer_size() == INPUT_BUFFER_MAX (reject new, keep old)")
	var ok: bool = true
	for i in range(int(WolfConstantsScript.INPUT_BUFFER_MAX)):
		if ic.poll_buffer().is_empty():
			ok = false
	_assert(ok, "A4: poll INPUT_BUFFER_MAX times → all succeed")
	_assert(ic.poll_buffer().is_empty(), "A4: poll beyond max → {} (9th press was rejected)")
	ic.free()


func _test_a5_fifo_multi_action() -> void:
	var ic: Object = _new_input()
	_press_buffer(ic, "game_light_attack")
	_press_buffer(ic, "game_guard")
	var first: Dictionary = ic.poll_buffer()
	var second: Dictionary = ic.poll_buffer()
	_assert(not first.is_empty() and first["action"] == &"game_light_attack", "A5: FIFO poll #1 → game_light_attack (pressed first)")
	_assert(not second.is_empty() and second["action"] == &"game_guard", "A5: FIFO poll #2 → game_guard (pressed second)")
	ic.free()


# ── Scenario B: guard = parry same-key dual meaning (AC2) ──

func _test_b1_guard_edge_and_hold() -> void:
	var ic: Object = _new_input()
	var cap: GuardCapture = GuardCapture.new()
	ic.guard_pressed.connect(cap.on_guard_pressed)
	ic.guard_held.connect(cap.on_guard_held)
	Input.action_press("game_guard")  # hold, no release
	for i in range(3):
		ic._process(0.016)
	_assert(cap.pressed_count == 1, "B1: guard_pressed emitted exactly once on the press edge")
	_assert(cap.last_timestamp_ms > 0, "B1: guard_pressed carries timestamp_ms > 0 (int)")
	_assert(cap.held_count >= 2, "B1: guard_held emitted on every held frame (>= 2 of 3)")
	Input.action_release("game_guard")
	ic._process(0.016)
	ic.free()


func _test_b2_guard_release_repress() -> void:
	var ic: Object = _new_input()
	var cap: GuardCapture = GuardCapture.new()
	ic.guard_pressed.connect(cap.on_guard_pressed)
	Input.action_press("game_guard")
	ic._process(0.016)
	Input.action_release("game_guard")
	ic._process(0.016)
	Input.action_press("game_guard")
	ic._process(0.016)
	_assert(cap.pressed_count == 2, "B2: press → release → press → guard_pressed emitted again (edge state reset)")
	Input.action_release("game_guard")
	ic._process(0.016)
	ic.free()


func _test_b3_guard_timestamp_semantics() -> void:
	var ic: Object = _new_input()
	var cap: GuardCapture = GuardCapture.new()
	ic.guard_pressed.connect(cap.on_guard_pressed)
	for i in range(2):
		Input.action_press("game_guard")
		ic._process(0.016)
		Input.action_release("game_guard")
		ic._process(0.016)
		_wait_ms(10)  # distinct milliseconds so timestamps are strictly increasing
	_assert(cap.timestamps.size() == 2, "B3: two press events → two timestamps captured")
	_assert(cap.timestamps.size() == 2 and typeof(cap.timestamps[0]) == TYPE_INT, "B3: timestamp is an int (milliseconds)")
	_assert(cap.timestamps.size() == 2 and cap.timestamps[1] > cap.timestamps[0], "B3: timestamps strictly increasing across presses")
	_assert(cap.pressed_count == 2 and cap.held_count == 0, "B3: signal carries only the timestamp (handler arity = one int, no judgement result)")
	ic.free()


func _test_b4_parry_window_readonly() -> void:
	_assert(WolfConstantsScript.PARRY_WINDOW_FRAMES == 12, "B4: WolfConstants.PARRY_WINDOW_FRAMES == 12 (read-only, unchanged by input layer)")


# ── Scenario C: buffer consume semantics ──

func _test_c1_poll_consumes() -> void:
	var ic: Object = _new_input()
	_press_buffer(ic, "game_light_attack")
	_press_buffer(ic, "game_guard")
	_assert(ic.buffer_size() == 2, "C1: two entries enqueued")
	var first: Dictionary = ic.poll_buffer()
	_assert(not first.is_empty() and first["action"] == &"game_light_attack", "C1: first poll returns the first enqueued entry")
	_assert(ic.buffer_size() == 1, "C1: poll consumes → buffer_size() == 1")
	ic.free()


func _test_c2_peek_readonly() -> void:
	var ic: Object = _new_input()
	_press_buffer(ic, "game_light_attack")
	var before: int = ic.buffer_size()
	var peeked: Dictionary = ic.peek_buffer()
	_assert(not peeked.is_empty() and peeked["action"] == &"game_light_attack", "C2: peek returns the buffer head")
	_assert(ic.buffer_size() == before, "C2: peek does not consume → buffer_size() unchanged")
	var popped: Dictionary = ic.poll_buffer()
	_assert(not popped.is_empty() and popped["action"] == peeked["action"], "C2: peek value == next poll value")
	ic.free()


func _test_c3_empty_buffer_safe() -> void:
	var ic: Object = _new_input()
	var polled: Dictionary = ic.poll_buffer()
	var peeked: Dictionary = ic.peek_buffer()
	_assert(polled.is_empty(), "C3: poll on empty buffer → {} (no crash)")
	_assert(peeked.is_empty(), "C3: peek on empty buffer → {} (no crash)")
	_assert(ic.buffer_size() == 0, "C3: buffer_size() == 0 on empty buffer")
	ic.free()


# ── Scenario D: dash = step / sprint dual meaning ──

func _test_d1_quick_dash() -> void:
	var ic: Object = _new_input()
	var cap: DashCapture = DashCapture.new()
	ic.dash_pressed.connect(cap.on_dash)
	Input.action_press("game_dash")
	ic._process(0.016)
	_wait_ms(int(int(WolfConstantsScript.DASH_HOLD_THRESHOLD_MS) / 2.0))  # 100ms < 200ms threshold
	Input.action_release("game_dash")
	ic._process(0.016)
	_assert(cap.count == 1, "D1: light press (< threshold) → dash_pressed exactly once")
	_assert(ic.is_sprinting() == false, "D1: is_sprinting() == false after light press")
	ic.free()


func _test_d2_long_press_sprint() -> void:
	var ic: Object = _new_input()
	var cap: DashCapture = DashCapture.new()
	ic.dash_pressed.connect(cap.on_dash)
	Input.action_press("game_dash")
	ic._process(0.016)
	OS.delay_msec(int(WolfConstantsScript.DASH_HOLD_THRESHOLD_MS) + 50)  # 250ms >= 200ms threshold (overshoot only strengthens)
	ic._process(0.016)
	_assert(ic.is_sprinting() == true, "D2: hold >= threshold → is_sprinting() == true")
	_assert(cap.count == 0, "D2: no dash_pressed while holding (sprint is not a step)")
	Input.action_release("game_dash")
	ic._process(0.016)
	_assert(ic.is_sprinting() == false, "D2: release → is_sprinting() == false")
	_assert(cap.count == 0, "D2: still no dash_pressed after release (>= threshold → sprint semantics)")
	ic.free()


func _test_d3_dash_threshold_boundary() -> void:
	var ic: Object = _new_input()
	var cap: DashCapture = DashCapture.new()
	ic.dash_pressed.connect(cap.on_dash)
	Input.action_press("game_dash")
	ic._process(0.016)
	ic._dash_press_time_ms = Time.get_ticks_msec() - int(WolfConstantsScript.DASH_HOLD_THRESHOLD_MS)  # white-box: exactly at threshold
	Input.action_release("game_dash")
	ic._process(0.016)
	_assert(cap.count == 0, "D3: release at exactly threshold (>= 200ms) → NO dash_pressed (sprint boundary)")
	_assert(ic.is_sprinting() == false, "D3: is_sprinting() == false after release at boundary")
	ic.free()


# ── Scenario E: illegal values / degradation ──

func _test_e2_safe_window_clamp() -> void:
	var ic: Object = _new_input()
	_assert(ic._safe_window_ms() >= 1.0, "E2: _safe_window_ms() clamps INPUT_BUFFER_WINDOW_MS to >= 1.0")
	for i in range(5):
		ic._process(0.016)
	_assert(true, "E2: _process over several frames with clamped window → no crash")
	ic.free()


func _test_e3_no_consumers_no_crash() -> void:
	var ic: Object = _new_input()
	for i in range(5):
		ic._process(0.016)
	_assert(true, "E3: _process with zero signal connections → no crash (signal no-op safe)")
	ic.free()


class GuardCapture:
	extends RefCounted

	var pressed_count: int = 0
	var held_count: int = 0
	var last_timestamp_ms: int = 0
	var timestamps: Array = []

	func on_guard_pressed(ts: int) -> void:
		pressed_count += 1
		last_timestamp_ms = ts
		timestamps.append(ts)

	func on_guard_held() -> void:
		held_count += 1


class DashCapture:
	extends RefCounted

	var count: int = 0

	func on_dash() -> void:
		count += 1
