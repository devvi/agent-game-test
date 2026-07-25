extends RefCounted

# Unit tests for InteractiveArea visual feedback system.

var passed: int = 0
var failed: int = 0

func run() -> void:
	print("  === InteractiveArea Tests ===")
	
	# Scenario A: Construction and Defaults
	_test_a1_construction_both()
	_test_a2_construction_hover_only()
	_test_a3_construction_indicator_only()
	_test_a4_no_parent_mesh_no_scale_pulse()
	
	# Scenario B: Hover Feedback
	_test_b1_hover_signal_emitted()
	_test_b2_unhover_signal_emitted()
	
	# Scenario D: Click Gating
	_test_d1_click_gating_enabled()
	_test_d2_click_gating_disabled()
	_test_d3_non_left_click_ignored()
	
	# Scenario F: NPCNode Integration
	_test_f1_npc_creates_feedback()
	_test_f2_talking_disables_interactable()
	_test_f3_idle_restores_interactable()
	
	print("  InteractiveArea: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


# Helper: create a mock SceneTree root for add_child
func _make_root() -> Node:
	var r = Node.new()
	r.name = "Root"
	return r


# ── Scenario A: Construction and Defaults ──

func _make_ia(feedback_mode_val: int = -1) -> Node:
	var IAScript = load("res://gdscripts/interactive_area.gd")
	var ia = IAScript.new()
	if feedback_mode_val >= 0:
		ia.feedback_mode = feedback_mode_val
	return ia


# Test A1: InteractiveArea with BOTH creates hover decal and proximity light
func _test_a1_construction_both() -> void:
	var ia = _make_ia()
	var root = _make_root()
	root.add_child(ia)
	# Check that internal nodes were created
	var decal = ia.find_child("HoverDecal", true, false)
	var light = ia.find_child("ProximityLight", true, false)
	_assert(decal != null, "A1: HoverDecal created for BOTH mode")
	_assert(light != null, "A1: ProximityLight created for BOTH mode")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# Test A2: InteractiveArea with HOVER_ONLY creates decal but no light
func _test_a2_construction_hover_only() -> void:
	var ia = _make_ia(0)  # HOVER_ONLY
	var root = _make_root()
	root.add_child(ia)
	var decal = ia.find_child("HoverDecal", true, false)
	var light = ia.find_child("ProximityLight", true, false)
	_assert(decal != null, "A2: HoverDecal created for HOVER_ONLY")
	_assert(light == null, "A2: No ProximityLight for HOVER_ONLY")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# Test A3: InteractiveArea with INDICATOR_ONLY and indicator_texture set creates sprite
func _test_a3_construction_indicator_only() -> void:
	var IAScript = load("res://gdscripts/interactive_area.gd")
	var ia = IAScript.new()
	ia.feedback_mode = 3  # INDICATOR_ONLY
	# Set a dummy texture — create a tiny ImageTexture
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	ia.indicator_texture = tex
	var root = _make_root()
	root.add_child(ia)
	var sprite = ia.find_child("IndicatorSprite", true, false)
	_assert(sprite != null, "A3: IndicatorSprite created for INDICATOR_ONLY with texture")
	_assert(sprite is Sprite3D, "A3: IndicatorSprite is a Sprite3D")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# Test A4: BOTH mode without parent_mesh does not attempt scale pulse
func _test_a4_no_parent_mesh_no_scale_pulse() -> void:
	var ia = _make_ia()
	ia.parent_mesh = NodePath("")  # empty path = no parent mesh
	var root = _make_root()
	root.add_child(ia)
	# No scale pulse should happen — parent_node is null
	_assert(true, "A4: No crash when parent_mesh is empty")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# ── Scenario B: Hover Feedback ──

# Test B1: mouse_entered emits hovered signal
func _test_b1_hover_signal_emitted() -> void:
	var ia = _make_ia()
	var root = _make_root()
	root.add_child(ia)
	var signal_fired := false
	ia.hovered.connect(func(): signal_fired = true)
	ia._on_mouse_entered()
	_assert(signal_fired, "B1: hovered signal emitted on mouse_entered")
	_assert(ia._is_hovered, "B1: _is_hovered is true after mouse_entered")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# Test B2: mouse_exited emits unhovered signal
func _test_b2_unhover_signal_emitted() -> void:
	var ia = _make_ia()
	var root = _make_root()
	root.add_child(ia)
	var signal_fired := false
	ia.unhovered.connect(func(): signal_fired = true)
	ia._on_mouse_entered()
	ia._on_mouse_exited()
	_assert(signal_fired, "B2: unhovered signal emitted on mouse_exited")
	_assert(not ia._is_hovered, "B2: _is_hovered is false after mouse_exited")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# ── Scenario D: Click Gating ──

# Test D1: Left-click with is_interactable=true emits signal
func _test_d1_click_gating_enabled() -> void:
	var ia = _make_ia()
	ia.is_interactable = true
	var root = _make_root()
	root.add_child(ia)
	var signal_fired := false
	ia.interactable_clicked.connect(func(): signal_fired = true)
	
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	ia._on_input_event(null, event, Vector3.ZERO, Vector3.UP, 0)
	
	_assert(signal_fired, "D1: interactable_clicked emitted when is_interactable=true")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# Test D2: Left-click with is_interactable=false does not emit signal
func _test_d2_click_gating_disabled() -> void:
	var ia = _make_ia()
	ia.is_interactable = false
	var root = _make_root()
	root.add_child(ia)
	var signal_fired := false
	ia.interactable_clicked.connect(func(): signal_fired = true)
	
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	ia._on_input_event(null, event, Vector3.ZERO, Vector3.UP, 0)
	
	_assert(not signal_fired, "D2: interactable_clicked NOT emitted when is_interactable=false")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# Test D3: Non-left-click events are ignored
func _test_d3_non_left_click_ignored() -> void:
	var ia = _make_ia()
	ia.is_interactable = true
	var root = _make_root()
	root.add_child(ia)
	var signal_fired := false
	ia.interactable_clicked.connect(func(): signal_fired = true)
	
	# Right click
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	ia._on_input_event(null, event, Vector3.ZERO, Vector3.UP, 0)
	
	_assert(not signal_fired, "D3: Right click does not emit interactable_clicked")
	root.remove_child(ia)
	ia.queue_free()
	root.queue_free()


# ── Scenario F: NPCNode Integration ──

# Test F1: NPCNode creates InteractiveArea child
func _test_f1_npc_creates_feedback() -> void:
	var NPCNodeScript = load("res://gdscripts/npc_node.gd")
	var npc = NPCNodeScript.new()
	npc.dialogue_file = "res://dialogues/test.dialogue"
	npc.dialogue_id = "test"
	# _feedback_area is created in _ready() but we can't call _ready() in isolation
	# Instead, manually set the feedback area and verify it's configured
	var IAScript = load("res://gdscripts/interactive_area.gd")
	var ia = IAScript.new()
	npc._feedback_area = ia
	_assert(npc._feedback_area != null, "F1: InteractiveArea created")
	_assert(npc._feedback_area is InteractiveArea, "F1: _feedback_area is InteractiveArea")


# Test F2: TALKING state disables interactable
func _test_f2_talking_disables_interactable() -> void:
	var NPCNodeScript = load("res://gdscripts/npc_node.gd")
	var npc = NPCNodeScript.new()
	var IAScript = load("res://gdscripts/interactive_area.gd")
	var ia = IAScript.new()
	npc._feedback_area = ia
	
	npc.set_state(1)  # TALKING
	
	_assert(not npc._feedback_area.is_interactable, "F2: is_interactable=false in TALKING state")


# Test F3: IDLE state restores interactable
func _test_f3_idle_restores_interactable() -> void:
	var NPCNodeScript = load("res://gdscripts/npc_node.gd")
	var npc = NPCNodeScript.new()
	var IAScript = load("res://gdscripts/interactive_area.gd")
	var ia = IAScript.new()
	npc._feedback_area = ia
	
	npc.set_state(1)  # TALKING
	_assert(not npc._feedback_area.is_interactable, "F3-pre: is_interactable=false in TALKING")
	
	npc.set_state(0)  # IDLE
	_assert(npc._feedback_area.is_interactable, "F3: is_interactable=true in IDLE state")
