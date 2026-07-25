extends RefCounted

# Unit tests for NavigationController — per-scene navigation orchestrator (Issue #226)
# Tests: condition timers, H-key hint routing, fallback detection, exit zone scanning

var passed: int = 0
var failed: int = 0

# Signal tracking
var _hint_signal_text: String = ""
var _fallback_reason: String = ""
var _condition_text: String = ""
var _hint_signal_fired: bool = false
var _fallback_fired: bool = false
var _condition_fired: bool = false


func run() -> void:
	print("  === NavigationController Unit Tests ====")

	# Condition Timer Tests
	print("  --- TC-NC-T: Timer Detection ---")
	_test_nc_t_1_stay_timer_increments()
	_test_nc_t_2_stay_trigger_at_threshold()
	_test_nc_t_3_hint_cooldown_prevents_spam()

	# Fallback Detection Tests
	print("  --- TC-NC-F: Fallback Detection ---")
	_test_nc_f_1_height_fall_trigger()
	_test_nc_f_2_stuck_detection()
	_test_nc_f_3_stuck_reset_on_movement()

	# Hint Text Tests
	print("  --- TC-NC-H: Hint Text ---")
	_test_nc_h_1_hint_text_office_neutral()
	_test_nc_h_2_hint_text_office_despair()
	_test_nc_h_3_hint_text_generic_fallback()
	_test_nc_h_4_hint_blocked_during_dialogue()

	# Stay/Wrong-Dir Warning Tests
	print("  --- TC-NC-W: Warning Text ---")
	_test_nc_w_1_stay_warning_text()
	_test_nc_w_2_wrong_dir_warning_text()
	_test_nc_w_3_generic_warning_fallback()

	# Signal Tests
	print("  --- TC-NC-S: Signal Routing ---")
	_test_nc_s_1_navigation_hint_requested_signal()
	_test_nc_s_2_fallback_triggered_signal()
	_test_nc_s_3_condition_text_updated_signal()

	print("  NavigationController Unit Tests: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


func _make_nav_controller() -> Node:
	var nav = load("res://gdscripts/navigation_controller.gd").new()
	nav.name = "NavigationController"
	nav.scene_id = "office"
	# Connect signals for tracking
	if nav.has_signal("navigation_hint_requested"):
		nav.navigation_hint_requested.connect(_on_nav_hint)
	if nav.has_signal("fallback_triggered"):
		nav.fallback_triggered.connect(_on_fallback)
	if nav.has_signal("condition_text_updated"):
		nav.condition_text_updated.connect(_on_condition_text)
	return nav


func _make_player() -> Node:
	var PlayerControllerScript = load("res://gdscripts/player_controller.gd")
	var pc = PlayerControllerScript.new()
	pc.name = "PlayerController"
	pc.head = Node3D.new()
	pc.head.name = "Head"
	pc.add_child(pc.head)
	pc.camera = Camera3D.new()
	pc.camera.name = "Camera3D"
	pc.head.add_child(pc.camera)
	pc.interaction_area = Area3D.new()
	pc.interaction_area.name = "InteractionArea"
	pc.add_child(pc.interaction_area)
	return pc


func _reset_signals() -> void:
	_hint_signal_text = ""
	_fallback_reason = ""
	_condition_text = ""
	_hint_signal_fired = false
	_fallback_fired = false
	_condition_fired = false


func _on_nav_hint(text: String) -> void:
	_hint_signal_fired = true
	_hint_signal_text = text


func _on_fallback(reason: String) -> void:
	_fallback_fired = true
	_fallback_reason = reason


func _on_condition_text(hint: String) -> void:
	_condition_fired = true
	_condition_text = hint


# ===== TC-NC-T: Timer Detection =====

func _test_nc_t_1_stay_timer_increments() -> void:
	# Verify stay timer increments with _physics_process delta
	var nav = _make_nav_controller()
	var pc = _make_player()
	nav._setup(pc, Vector3.ZERO)

	# Run several physics frames to accumulate stay time
	for i in range(10):
		nav._physics_process(1.0)

	_assert(nav._stay_timer >= 9.5,
		"TC-NC-T-1: Stay timer increments with delta (~10s after 10 frames)")

	nav.queue_free()
	pc.queue_free()


func _test_nc_t_2_stay_trigger_at_threshold() -> void:
	# Verify stay warning triggers at NAV_STAY_THRESHOLD (60s)
	_reset_signals()
	var nav = _make_nav_controller()
	var pc = _make_player()
	nav._setup(pc, Vector3.ZERO)

	# Simulate 61 seconds of standing
	for i in range(61):
		nav._physics_process(1.0)

	_assert(_condition_fired,
		"TC-NC-T-2: Stay warning triggered after 60s")
	_assert(_condition_text.length() > 0,
		"TC-NC-T-2: Condition text is non-empty")
	_assert(nav._stay_triggered,
		"TC-NC-T-2: _stay_triggered flag set to true")

	nav.queue_free()
	pc.queue_free()


func _test_nc_t_3_hint_cooldown_prevents_spam() -> void:
	# Verify hint cooldown (8s) prevents re-trigger
	_reset_signals()
	var nav = _make_nav_controller()
	nav._setup(null, Vector3.ZERO)

	# First hint
	nav._handle_hint_key()
	var first_hint = _hint_signal_fired

	_reset_signals()
	# Second hint immediately — should be blocked by cooldown
	nav._handle_hint_key()

	_assert(first_hint,
		"TC-NC-T-3: First hint triggers")
	_assert(not _hint_signal_fired,
		"TC-NC-T-3: Second hint blocked by cooldown")
	_assert(nav._hint_cooldown > 0,
		"TC-NC-T-3: Cooldown timer active after hint")

	nav.queue_free()


# ===== TC-NC-F: Fallback Detection =====

func _test_nc_f_1_height_fall_trigger() -> void:
	# Verify height fall detection (y < -10 triggers fallback)
	_reset_signals()
	var nav = _make_nav_controller()
	var pc = _make_player()
	nav._setup(pc, Vector3.ZERO)

	# Move player below threshold
	pc.global_position = Vector3(0, -15, 0)
	nav._physics_process(1.0)

	_assert(_fallback_fired,
		"TC-NC-F-1: Fallback triggered for height fall")
	_assert(_fallback_reason == "fell",
		"TC-NC-F-1: Fallback reason is 'fell'")

	nav.queue_free()
	pc.queue_free()


func _test_nc_f_2_stuck_detection() -> void:
	# Verify stuck detection (velocity < 0.01 for 3s triggers fallback)
	_reset_signals()
	var nav = _make_nav_controller()
	var pc = _make_player()
	# Position player at origin
	pc.global_position = Vector3.ZERO
	nav._setup(pc, Vector3.ZERO)

	# Simulate 4 seconds of not moving (stuck)
	for i in range(4):
		nav._physics_process(1.0)

	_assert(_fallback_fired,
		"TC-NC-F-2: Fallback triggered for stuck detection")
	_assert(_fallback_reason == "stuck",
		"TC-NC-F-2: Fallback reason is 'stuck'")

	nav.queue_free()
	pc.queue_free()


func _test_nc_f_3_stuck_reset_on_movement() -> void:
	# Verify stuck timer resets when player moves
	_reset_signals()
	var nav = _make_nav_controller()
	var pc = _make_player()
	pc.global_position = Vector3.ZERO
	nav._setup(pc, Vector3.ZERO)

	# Stand still for 2 seconds
	nav._physics_process(1.0)
	nav._physics_process(1.0)
	_assert(nav._stuck_timer > 1.5,
		"TC-NC-F-3: Stuck timer accumulating after 2s standing")

	# Move player to new position
	pc.global_position = Vector3(5, 0, 0)
	nav._physics_process(1.0)

	_assert(nav._stuck_timer < 0.01,
		"TC-NC-F-3: Stuck timer reset after player moves")

	nav.queue_free()
	pc.queue_free()


# ===== TC-NC-H: Hint Text =====

func _test_nc_h_1_hint_text_office_neutral() -> void:
	# Verify office neutral hint text
	var nav = _make_nav_controller()
	nav.scene_id = "office"

	var hint = nav._get_hint_text()
	# In headless tests without NarrativeManager, falls back to GENERIC_HINT
	_assert(hint.length() > 0,
		"TC-NC-H-1: Hint text is non-empty for office scene")

	nav.queue_free()


func _test_nc_h_2_hint_text_office_despair() -> void:
	# Verify that HINT_TEXT_TEMPLATES contains correct despair text for office
	var templates = load("res://gdscripts/navigation_controller.gd").HINT_TEXT_TEMPLATES
	var office_hints: Dictionary = templates.get("office", {})
	var despair_text: String = office_hints.get("despair", "")

	_assert(despair_text == "The door is ahead. / Go outside. / Nothing else.",
		"TC-NC-H-2: Office despair hint text matches DESIGN document")

	var neutral_text: String = office_hints.get("neutral", "")
	_assert(neutral_text == "The door is ahead. / Go outside.",
		"TC-NC-H-2: Office neutral hint text matches DESIGN document")


func _test_nc_h_3_hint_text_generic_fallback() -> void:
	# Verify fallback to GENERIC_HINT for unknown scenes
	var nav = _make_nav_controller()
	nav.scene_id = "nonexistent_scene"

	var hint = nav._get_hint_text()
	_assert(hint == "The exit is nearby. / Look around.",
		"TC-NC-H-3: Generic hint fallback for unknown scene")

	nav.queue_free()


func _test_nc_h_4_hint_blocked_during_dialogue() -> void:
	# Verify H-key hint blocked during dialogue
	_reset_signals()
	var nav = _make_nav_controller()
	nav._setup(null, Vector3.ZERO)
	nav.set_dialogue_active(true)

	nav._handle_hint_key()

	_assert(not _hint_signal_fired,
		"TC-NC-H-4: Hint blocked during dialogue")

	nav.queue_free()


# ===== TC-NC-W: Warning Text =====

func _test_nc_w_1_stay_warning_text() -> void:
	var nav = _make_nav_controller()
	nav.scene_id = "office"
	var text = nav._get_stay_warning_text()
	_assert(text == "You've been here a while. / The door is still there.",
		"TC-NC-W-1: Office stay warning text matches DESIGN")

	# Test another scene
	nav.scene_id = "lobby"
	text = nav._get_stay_warning_text()
	_assert(text == "The lobby echoes. / You've been standing here.",
		"TC-NC-W-1: Lobby stay warning text matches DESIGN")

	nav.queue_free()


func _test_nc_w_2_wrong_dir_warning_text() -> void:
	var nav = _make_nav_controller()
	nav.scene_id = "office"
	var text = nav._get_wrong_dir_text()
	_assert(text == "The door is behind you. / Turn around.",
		"TC-NC-W-2: Office wrong-dir warning text matches DESIGN")

	nav.queue_free()


func _test_nc_w_3_generic_warning_fallback() -> void:
	var nav = _make_nav_controller()
	nav.scene_id = ""

	var stay = nav._get_stay_warning_text()
	_assert(stay == "You've been here a while. / The exit is somewhere.",
		"TC-NC-W-3: Generic stay warning for empty scene_id")

	var wrong_dir = nav._get_wrong_dir_text()
	_assert(wrong_dir == "Maybe the other way. / Try turning around.",
		"TC-NC-W-3: Generic wrong-dir warning for empty scene_id")

	nav.queue_free()


# ===== TC-NC-S: Signal Routing =====

func _test_nc_s_1_navigation_hint_requested_signal() -> void:
	# Verify navigation_hint_requested signal fires with text
	_reset_signals()
	var nav = _make_nav_controller()
	nav._setup(null, Vector3.ZERO)

	nav._handle_hint_key()

	_assert(_hint_signal_fired,
		"TC-NC-S-1: navigation_hint_requested signal emitted")
	_assert(_hint_signal_text.length() > 0,
		"TC-NC-S-1: Hint text in signal is non-empty")

	nav.queue_free()


func _test_nc_s_2_fallback_triggered_signal() -> void:
	# Verify fallback_triggered signal fires with reason
	_reset_signals()
	var nav = _make_nav_controller()
	var pc = _make_player()
	nav._setup(pc, Vector3.ZERO)

	pc.global_position = Vector3(0, -15, 0)
	nav._physics_process(1.0)

	_assert(_fallback_fired,
		"TC-NC-S-2: fallback_triggered signal emitted")
	_assert(_fallback_reason == "fell",
		"TC-NC-S-2: Fallback reason is 'fell'")

	nav.queue_free()
	pc.queue_free()


func _test_nc_s_3_condition_text_updated_signal() -> void:
	# Verify condition_text_updated signal fires with hint text
	_reset_signals()
	var nav = _make_nav_controller()
	var pc = _make_player()
	nav._setup(pc, Vector3.ZERO)

	# Accumulate 61 seconds to trigger stay warning
	for i in range(61):
		nav._physics_process(1.0)

	_assert(_condition_fired,
		"TC-NC-S-3: condition_text_updated signal emitted")
	_assert(_condition_text.length() > 0,
		"TC-NC-S-3: Condition text is non-empty")

	nav.queue_free()
	pc.queue_free()
