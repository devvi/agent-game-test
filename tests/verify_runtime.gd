extends SceneTree

# Runtime physics & layout verification
# Checks that scenes have working collision and objects have positions

var ok = 0
var fail = 0

func _init() -> void:
	print("=== RUNTIME VERIFICATION ===\n")
	
	# 1. Check office scene physics
	check_scene_collision("res://scenes/office/office.tscn")
	check_scene_collision("res://scenes/lobby/lobby.tscn")
	check_scene_collision("res://scenes/street/street.tscn")
	check_scene_collision("res://scenes/bridge/bridge.tscn")
	check_scene_collision("res://scenes/underpass/underpass.tscn")
	check_scene_collision("res://scenes/subway_station/subway_station.tscn")
	
	# 2. Check scene object positions — not at origin
	check_positions("res://scenes/office/office.tscn")
	check_positions("res://scenes/street/street.tscn")
	
	print("\n=== RESULTS ===")
	print("Passed: " + str(ok) + " Failed: " + str(fail))
	if fail > 0:
		quit(1)
	else:
		print("ALL CHECKS PASSED")
		quit(0)

func check_scene_collision(path: String) -> void:
	var scene = load(path)
	if scene == null:
		print("  FAIL Cannot load: " + path)
		fail += 1
		return
	
	var inst = scene.instantiate()
	if inst == null:
		print("  FAIL Cannot instantiate: " + path)
		fail += 1
		return
	
	# Check collision shapes
	var shapes = _find_nodes(inst, "CollisionShape3D")
	var shapes_without_shape = 0
	for s in shapes:
		if s.shape == null:
			shapes_without_shape += 1
	
	var name = path.split("/")[-1].replace(".tscn", "")
	if shapes_without_shape == 0:
		print("  OK " + name + " (" + str(shapes.size()) + " collision shapes)")
		ok += 1
	else:
		print("  FAIL " + name + " — " + str(shapes_without_shape) + "/" + str(shapes.size()) + " CollisionShape3D have no shape")
		fail += 1
	
	inst.free()

func check_positions(path: String) -> void:
	var scene = load(path)
	if scene == null: return
	var inst = scene.instantiate()
	
	var labels = _find_nodes(inst, "Label3D")
	var at_origin = 0
	for l in labels:
		if l.position == Vector3.ZERO and l.visible:
			at_origin += 1
	
	var name = path.split("/")[-1].replace(".tscn", "")
	if at_origin == 0:
		print("  OK " + name + " — all Label3D positioned")
	elif at_origin <= 2:
		print("  WARN " + name + " — " + str(at_origin) + "/" + str(labels.size()) + " Label3D at origin (might be intentional)")
	else:
		print("  FAIL " + name + " — " + str(at_origin) + "/" + str(labels.size()) + " Label3D at origin (piled up!)")
		fail += 1
	
	inst.free()

func _find_nodes(parent: Node, type_name: String) -> Array:
	var result = []
	for child in parent.get_children():
		if child.get_class() == type_name:
			result.append(child)
		result.append_array(_find_nodes(child, type_name))
	return result
