extends Object
## Test suite for StateMachineBase (#572) — transition call order, same-state guard,
## re-entrancy lock, and null-state safety.
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/572-scaffold-main-entry.md §2.2 / §8 Scenario A-D
##
## Mock states are inner RefCounted classes that record enter/exit/update calls
## into a shared log Array (update() also records the received delta value).
## NOTE: class_name may not resolve in --script mode, so the base script is
## accessed via preload and instantiated with .new().

const StateMachineBaseScript = preload("res://gdscripts/state_machine.gd")

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== StateMachine Tests ===")
	_test_a1_transition_order()
	_test_a2_initial_transition()
	_test_a3_update_forwards_delta()
	_test_b1_same_state_guard()
	_test_b2_update_after_same_state()
	_test_c1_reentrant_transition_blocked()
	_test_c2_lock_released()
	_test_d1_null_update_no_crash()
	_test_d2_transition_to_null()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _new_fsm() -> Object:
	return StateMachineBaseScript.new()


# ── Scenario A: three-interface call order ──

func _test_a1_transition_order() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var b = _MockStateB.new(log)
	var fsm: Object = _new_fsm()
	fsm.transition_to(a)
	log.clear()
	fsm.transition_to(b)
	_assert(log == ["A.exit()", "B.enter()"], "A1: transition_to(B) → [A.exit(), B.enter()] (exit before enter)")
	_assert(fsm.current_state == b, "A1: current_state == B after transition")


func _test_a2_initial_transition() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var fsm: Object = _new_fsm()
	fsm.transition_to(a)
	_assert(log == ["A.enter()"], "A2: from null transition_to(A) → only A.enter(), no exit")
	_assert(fsm.current_state == a, "A2: current_state == A")


func _test_a3_update_forwards_delta() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var fsm: Object = _new_fsm()
	fsm.transition_to(a)
	log.clear()
	fsm.update(0.016)
	_assert(log == ["A.update(0.016)"], "A3: update(0.016) forwarded to current state")
	_assert(abs(a.last_delta - 0.016) < 0.0001, "A3: A.update received delta == 0.016")


# ── Scenario B: same-state guard ──

func _test_b1_same_state_guard() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var fsm: Object = _new_fsm()
	fsm.transition_to(a)
	log.clear()
	fsm.transition_to(a)
	_assert(log.is_empty(), "B1: transition_to(A) twice → second call no callbacks")
	_assert(fsm.current_state == a, "B1: current_state still A")


func _test_b2_update_after_same_state() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var fsm: Object = _new_fsm()
	fsm.transition_to(a)
	fsm.transition_to(a)
	log.clear()
	fsm.update(0.016)
	_assert(log == ["A.update(0.016)"], "B2: update still forwarded after same-state guard")


# ── Scenario C: re-entrancy lock ──

func _test_c1_reentrant_transition_blocked() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var b = _MockStateB.new(log)
	var fsm: Object = _new_fsm()
	a.sm = fsm
	a.b_target = b
	a.reentrant_enter = true
	fsm.transition_to(a)
	# Warning (push_warning) is an implementation side-effect; observable contract
	# is that the nested transition_to(B) inside A.enter() is blocked entirely.
	_assert(log == ["A.enter()"], "C1: B.enter NOT called (re-entrant transition blocked)")
	_assert(fsm.current_state == a, "C1: current_state still A after blocked re-entrant call")
	_assert(fsm._transition_locked == false, "C1: lock released after transition completes")
	a.sm = null
	a.b_target = null


func _test_c2_lock_released() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var b = _MockStateB.new(log)
	var fsm: Object = _new_fsm()
	a.sm = fsm
	a.b_target = b
	a.reentrant_enter = true
	fsm.transition_to(a)
	log.clear()
	fsm.transition_to(b)
	_assert(log == ["A.exit()", "B.enter()"], "C2: transition_to(B) works after re-entrant block (lock released)")
	_assert(fsm.current_state == b, "C2: current_state == B")
	a.sm = null
	a.b_target = null


# ── Scenario D: null-state safety ──

func _test_d1_null_update_no_crash() -> void:
	var fsm: Object = _new_fsm()
	_assert(fsm.current_state == null, "D1: current_state starts as null")
	fsm.update(0.016)
	_assert(true, "D1: update(0.016) with null current → no crash (no-op)")


func _test_d2_transition_to_null() -> void:
	var log: Array = []
	var a = _MockStateA.new(log)
	var fsm: Object = _new_fsm()
	fsm.transition_to(a)
	log.clear()
	fsm.transition_to(null)
	_assert(log == ["A.exit()"], "D2: transition_to(null) → only exit, no enter")
	_assert(fsm.current_state == null, "D2: current_state == null after transition to null")


class _MockStateA:
	extends RefCounted

	var log: Array
	var sm: Object = null
	var b_target: Object = null
	var reentrant_enter: bool = false
	var last_delta: float = 0.0

	func _init(log_ref: Array) -> void:
		log = log_ref

	func enter() -> void:
		log.append("A.enter()")
		if reentrant_enter and sm != null and b_target != null:
			sm.transition_to(b_target)

	func exit() -> void:
		log.append("A.exit()")

	func update(delta: float) -> void:
		last_delta = delta
		log.append("A.update(%s)" % str(delta))


class _MockStateB:
	extends RefCounted

	var log: Array
	var last_delta: float = 0.0

	func _init(log_ref: Array) -> void:
		log = log_ref

	func enter() -> void:
		log.append("B.enter()")

	func exit() -> void:
		log.append("B.exit()")

	func update(delta: float) -> void:
		last_delta = delta
		log.append("B.update(%s)" % str(delta))
