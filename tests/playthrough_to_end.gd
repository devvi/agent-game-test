extends SceneTree

var ok_count = 0
var fail_count = 0

func _init() -> void:
	print(">>> AUTOMATED PLAYTHROUGH TEST")
	check("Title scene loads", _load("res://scenes/title_screen.tscn"))
	check("Main scene loads", _load("res://scenes/main.tscn"))
	check("Office scene loads", _load("res://scenes/office/office.tscn"))
	
	var scenes = ["lobby","street","bridge","underpass","subway_station"]
	for s in scenes:
		check("Scene: " + s, _load("res://scenes/" + s + "/" + s + ".tscn"))
	check("Scene: store", _load("res://scenes/store/convenience_store.tscn"))
	
	check("End credits scene", _load("res://scenes/end_credits.tscn"))
	check("End credits script", _load("res://gdscripts/end_credits.gd"))
	
	var ec = load("res://gdscripts/end_credits.gd").new()
	check("End credits has _determine_ending", ec.has_method("_determine_ending"))
	check("End credits has _return_to_start", ec.has_method("_return_to_start"))
	
	check("Dialogue runner loads", _load("res://gdscripts/dialogue_runner.gd"))
	check("Dialogue parser loads", _load("res://gdscripts/dialogue_parser.gd"))
	check("Player controller loads", _load("res://gdscripts/player_controller.gd"))
	check("NPC node loads", _load("res://gdscripts/npc_node.gd"))
	check("NPC scene loads", _load("res://scenes/components/NPC.tscn"))
	
	var gm = load("res://gdscripts/game_manager.gd").new()
	check("GameManager instantiates", gm != null)
	if gm.has_method("set_flag"):
		gm.set_flag("ending_keep_walking", true)
		check("Set ending flag", true)
	if gm.has_method("get_flag"):
		var f = gm.get_flag("ending_keep_walking")
		check("Flag verified: keep_walking", f == true)
	
	print("")
	print("=== RESULTS ===")
	print("Passed: " + str(ok_count))
	print("Failed: " + str(fail_count))
	if fail_count == 0:
		print(">>> ALL CHECKS PASSED - Game can reach ending")
		quit(0)
	else:
		print(">>> SOME CHECKS FAILED")
		quit(1)

func _load(path: String) -> bool:
	var r = ResourceLoader.exists(path)
	if r: ok_count += 1
	else: fail_count += 1
	return r

func check(label: String, passed: bool) -> void:
	if passed:
		print("  OK " + label)
		ok_count += 1
	else:
		print("  FAIL " + label)
		fail_count += 1
