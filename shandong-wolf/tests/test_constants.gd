extends Object
## Test suite for WolfConstants (#572) — draft section existence, draft markers,
## and mechanical constants.
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/572-scaffold-main-entry.md §2.1 / §8 Scenario E
##
## NOTE: class_name may not resolve in --script mode, so the constants script is
## accessed via preload and its constants read through the loaded resource.
## The preload const is named WolfConstantsScript to avoid colliding with the
## class_name WolfConstants (a same-named const resolves to the class in 4.7.1,
## which breaks resource-method calls like get_script_constant_map()).

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Constants Tests ===")
	_test_e1_draft_sections_exist()
	_test_e2_draft_markers()
	_test_e3_mechanical_constants()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


# ── Scenario E: constants draft sections existence ──

func _test_e1_draft_sections_exist() -> void:
	var script: GDScript = load("res://gdscripts/constants.gd")
	var consts: Dictionary = script.get_script_constant_map()
	_assert(consts.has("PARRY_WINDOW_FRAMES"), "E1: PARRY_WINDOW_FRAMES exists (弹反窗口)")
	_assert(consts.has("POSTURE_RECOVERY_PER_SEC"), "E1: POSTURE_RECOVERY_PER_SEC exists (架势回复)")
	_assert(consts.has("LIFE_TOTAL"), "E1: LIFE_TOTAL exists (两条命数值)")
	_assert(consts.has("SWORD_DAMAGE_LIGHT"), "E1: SWORD_DAMAGE_LIGHT exists (刀伤害)")
	_assert(consts.has("FRAME_ATTACK_WINDUP"), "E1: FRAME_ATTACK_WINDUP exists (帧节奏)")


func _test_e2_draft_markers() -> void:
	var f: FileAccess = FileAccess.open("res://gdscripts/constants.gd", FileAccess.READ)
	if f == null:
		_assert(false, "E2: constants.gd opens for reading")
		return
	var text: String = f.get_as_text()
	f.close()
	var draft_count: int = 0
	var search_from: int = 0
	while true:
		var idx: int = text.find("# DRAFT", search_from)
		if idx == -1:
			break
		draft_count += 1
		search_from = idx + 1
	_assert(draft_count >= 5, "E2: constants.gd contains >= 5 '# DRAFT' markers (found %d)" % draft_count)
	_assert(text.find("# 定稿") == -1, "E2: constants.gd does NOT contain '# 定稿' (no stealth finalization)")


func _test_e3_mechanical_constants() -> void:
	_assert(WolfConstantsScript.GAME_VERSION == "v0.1.0", "E3: GAME_VERSION == 'v0.1.0'")
	_assert(WolfConstantsScript.SCREEN_WIDTH == 1280, "E3: SCREEN_WIDTH == 1280")
	_assert(WolfConstantsScript.SCREEN_HEIGHT == 720, "E3: SCREEN_HEIGHT == 720")
