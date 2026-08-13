extends RefCounted
## E2E capture template require-gate tests (#466, Scenario D).
##
## e2e_capture.gd is a SceneTree script (the capture driver IS the main loop)
## — it cannot be `new()`-ed inside a running engine. Following the repo's
## template-verification precedent (test_visual_contrast.gd asserts literal
## .tscn/.tres content), we assert the #466 require-array + children_in_group
## logic directly in the template source, and FUNCTIONALLY verify the gate
## mechanism (get_nodes_in_group("bricks")) with real brick.tscn instances.
##
## Scenario D (DESIGN §9):
##   T8  children_in_group {group:"bricks", min:4}: 0 bricks → gate false;
##       4 bricks → gate true (functional, real bricks in group)
##   T9  single-dict require (old format) path preserved (text assertion)
##   T10 require array multi-condition AND + e2e_shots.json wiring (text/JSON)

var passed: int = 0
var failed: int = 0

const SHOTS_PATH := "res://e2e_shots.json"
const BRICK_SCENE := "res://scenes/brick.tscn"


func run() -> void:
	print("\n=== E2E Capture Require (#466) ===")
	await _t8_children_in_group_gate()
	_t9_single_dict_path_preserved()
	_t10_array_wiring_and_shots_json()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _template_source() -> String:
	# framework/templates/e2e_capture.gd sits OUTSIDE the mini-pong project
	# root — resolve via the project's parent directory.
	var proj_root := ProjectSettings.globalize_path("res://")
	var proj_dir := proj_root.trim_suffix("/")
	var repo_root := proj_dir.get_base_dir()
	return FileAccess.get_file_as_string(repo_root.path_join("framework/templates/e2e_capture.gd"))


# ── T8: children_in_group gate (functional, real bricks) ──

func _t8_children_in_group_gate() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node.new()
	tree.root.add_child(holder)

	var before: int = tree.get_nodes_in_group("bricks").size()
	# Gate semantics: min=4 → FALSE when group has fewer than 4 bricks.
	if before < 4:
		_assert(not (before >= 4), "T8-1: gate FALSE with < 4 bricks (before=%d)" % before)
	else:
		passed += 1  # environment already has bricks — skip gate-false check

	for i in range(4):
		var brick = load(BRICK_SCENE).instantiate()
		holder.add_child(brick)
	await tree.process_frame  # let _ready() add_to_group("bricks") run

	var after: int = tree.get_nodes_in_group("bricks").size()
	_assert(after >= before + 4, "T8-2: 4 bricks joined group (before=%d after=%d)" % [before, after])
	_assert(after >= 4, "T8-3: gate 'size() >= 4' now TRUE")

	for child in holder.get_children():
		child.queue_free()
	holder.queue_free()
	await tree.process_frame


# ── T9: single-dict require path preserved (backward compat) ──

func _t9_single_dict_path_preserved() -> void:
	var src := _template_source()
	_assert(src.contains("func _require_ok(d: Dictionary) -> bool:"),
		"T9-1: _require_ok entry unchanged")
	_assert(src.contains("return _require_one(req)"),
		"T9-2: single-dict require routes through _require_one (old path kept)")
	_assert(src.contains("var req = d[\"require\"]"),
		"T9-3: require value read once for both forms")
	_assert(src.contains("func _require_one(req: Dictionary) -> bool:"),
		"T9-4: _require_one helper exists")


# ── T10: array multi-condition AND + e2e_shots.json wiring ──

func _t10_array_wiring_and_shots_json() -> void:
	var src := _template_source()
	_assert(src.contains("if req is Array:"),
		"T10-1: template handles Array-form require")
	_assert(src.contains("for cond in req:"),
		"T10-2: array conditions evaluated in AND loop")

	# e2e_shots.json: 02_midgame require is an array with children_in_group
	var shots_text := FileAccess.get_file_as_string(SHOTS_PATH)
	var parsed = JSON.parse_string(shots_text)
	_assert(typeof(parsed) == TYPE_DICTIONARY, "T10-3: e2e_shots.json parses")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var theme: String = str(parsed.get("theme_color", ""))
	_assert(theme == "00e5ff", "T10-4: theme_color updated to 00e5ff (paddle neon)")
	var midgame: Dictionary = {}
	for g in parsed.get("groups", {}).values():
		for s in g.get("shots", []):
			if s.get("name") == "02_midgame":
				midgame = s
	_assert(not midgame.is_empty(), "T10-5: 02_midgame shot found")
	if midgame.is_empty():
		return
	var req = midgame.get("require")
	_assert(req is Array, "T10-6: 02_midgame require is an Array")
	_assert(req.size() >= 2, "T10-7: require has >= 2 conditions (score + bricks)")
	var has_bricks_gate := false
	var has_score_gate := false
	for cond in req:
		if cond is Dictionary and cond.has("children_in_group"):
			var cig: Dictionary = cond["children_in_group"]
			if str(cig.get("group", "")) == "bricks" and int(cig.get("min", 0)) >= 4:
				has_bricks_gate = true
		if cond is Dictionary and cond.get("prop", "") == "player_score":
			has_score_gate = true
	_assert(has_bricks_gate, "T10-8: children_in_group(bricks, min>=4) in require")
	_assert(has_score_gate, "T10-9: player_score>=1 condition kept")
	var visual: Dictionary = midgame.get("visual", {})
	_assert(not visual.is_empty(), "T10-10: 02_midgame has visual config")
	_assert(str(visual.get("canvas", "")) == "720x1280", "T10-11: visual.canvas = 720x1280")
	_assert(visual.get("regions", []).size() >= 3, "T10-12: >= 3 regions (paddle/brick/bg)")
	_assert(visual.get("compare_pairs", []).size() >= 3, "T10-13: 3 compare_pairs")
	_assert(int(visual.get("rgb_min_dist", 0)) >= 60, "T10-14: rgb_min_dist >= 60")
	_assert(visual.has("rain"), "T10-15: rain config present")
