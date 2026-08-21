extends Object
## Test suite for WolfConstants (#572) — draft section existence, draft markers,
## and mechanical constants.
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/572-scaffold-main-entry.md §2.1 / §8 Scenario E
##         docs/DESIGN/584-combat-tuning-draft.md §8 Scenario A (#584 扩展:
##         14 参数存在性 + 三行注释格式 + 候选集 + 防误定稿守卫)
##
## NOTE: class_name may not resolve in --script mode, so the constants script is
## accessed via preload and its constants read through the loaded resource.
## The preload const is named WolfConstantsScript to avoid colliding with the
## class_name WolfConstants (a same-named const resolves to the class in 4.7.1,
## which breaks resource-method calls like get_script_constant_map()).

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

## #584 Scenario A: 14 个 tunable DRAFT 参数（唯一事实清单，A1/A2/A3/A6 共用）
const EXPECTED_PARAMS: Array[String] = [
	"PARRY_WINDOW_FRAMES",
	"POSTURE_RECOVERY_PER_SEC",
	"POSTURE_RECOVERY_DELAY",
	"POSTURE_BLOCK_COST",
	"PARRY_COST",
	"POSTURE_HIT_COST",
	"POSTURE_BREAK_THRESHOLD",
	"LIFE_1_MAX",
	"LIFE_2_ABS",
	"SWORD_DAMAGE_LIGHT",
	"SWORD_DAMAGE_HEAVY",
	"ENEMY_ATTACK_WINDUP",
	"EXECUTE_RANGE",
	"SLOWMO_COEFF",
]

## #584 Scenario A: 候选集断言豁免名单（机械语义参数，可不检查候选集 >= 2）
const EXEMPT_CANDIDATES: Array[String] = [
	"LIFE_TOTAL",
	"SWORD_DAMAGE_EXECUTE",
]

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Constants Tests ===")
	_test_e1_draft_sections_exist()
	_test_e2_draft_markers()
	_test_e3_mechanical_constants()
	_test_a1_14_params_exist()
	_test_a2_three_line_comment_format()
	_test_a3_candidate_sets()
	_test_a4_finalization_guard()
	_test_a5_new_section_and_consts()
	_test_a6_default_values()
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


# ── Scenario A: 14 参数 DRAFT 完整性（#584，DESIGN §8 Scenario A）──

func _read_constants_text() -> String:
	var f: FileAccess = FileAccess.open("res://gdscripts/constants.gd", FileAccess.READ)
	if f == null:
		_assert(false, "constants.gd opens for reading")
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func _const_line_index(lines: PackedStringArray, name: String) -> int:
	for i in range(lines.size()):
		if lines[i].begins_with("const %s:" % name):
			return i
	return -1


## 候选集行（"候选集:" 后首个 [..] 括弧内）的候选个数
func _candidate_count(line: String) -> int:
	var lb: int = line.find("[")
	if lb == -1:
		return 0
	var rb: int = line.find("]", lb)
	if rb == -1 or rb <= lb:
		return 0
	var inside: String = line.substr(lb + 1, rb - lb - 1)
	var re: RegEx = RegEx.new()
	re.compile("[-+]?\\d+(\\.\\d+)?")
	return re.search_all(inside).size()


func _test_a1_14_params_exist() -> void:
	var script: GDScript = load("res://gdscripts/constants.gd")
	var consts: Dictionary = script.get_script_constant_map()
	for name in EXPECTED_PARAMS:
		_assert(consts.has(name), "A1: %s exists (14 参数存在性)" % name)


func _test_a2_three_line_comment_format() -> void:
	var text: String = _read_constants_text()
	if text == "":
		return
	var lines: PackedStringArray = text.split("\n")
	for name in EXPECTED_PARAMS:
		var idx: int = _const_line_index(lines, name)
		if idx == -1:
			_assert(false, "A2: const %s declaration line found" % name)
			continue
		var has_sekiro: bool = false
		var has_candidate: bool = false
		var has_deviation: bool = false
		var start: int = maxi(0, idx - 6)
		for j in range(start, idx):
			var line: String = lines[j]
			if line.find("只狼基准:") != -1:
				has_sekiro = true
			if line.find("候选集:") != -1:
				has_candidate = true
			if line.find("偏离理由:") != -1:
				has_deviation = true
		_assert(has_sekiro, "A2: %s 上方注释块含『只狼基准:』" % name)
		_assert(has_candidate or has_deviation, "A2: %s 上方注释块含『候选集:』或『偏离理由:』" % name)


func _test_a3_candidate_sets() -> void:
	var text: String = _read_constants_text()
	if text == "":
		return
	var lines: PackedStringArray = text.split("\n")
	for name in EXPECTED_PARAMS:
		if name in EXEMPT_CANDIDATES:
			continue
		var idx: int = _const_line_index(lines, name)
		if idx == -1:
			_assert(false, "A3: const %s declaration line found" % name)
			continue
		var start: int = maxi(0, idx - 6)
		var cand_line: String = ""
		for j in range(idx - 1, start - 1, -1):
			if lines[j].find("候选集:") != -1:
				cand_line = lines[j]
				break
		if cand_line == "":
			_assert(false, "A3: %s 上方注释含『候选集:』行" % name)
			continue
		var count: int = _candidate_count(cand_line)
		_assert(count >= 2, "A3: %s 候选集 >= 2 (got %d, line: %s)" % [name, count, cand_line])


func _test_a4_finalization_guard() -> void:
	var text: String = _read_constants_text()
	if text == "":
		return
	var draft_count: int = 0
	var search_from: int = 0
	while true:
		var idx: int = text.find("# DRAFT", search_from)
		if idx == -1:
			break
		draft_count += 1
		search_from = idx + 1
	_assert(draft_count >= 14, "A4: constants.gd contains >= 14 '# DRAFT' markers (found %d)" % draft_count)
	_assert(text.find("# 定稿") == -1, "A4: constants.gd does NOT contain '# 定稿' (no stealth finalization)")


func _test_a5_new_section_and_consts() -> void:
	var text: String = _read_constants_text()
	if text == "":
		return
	_assert(text.find("受击/敌人/处决") != -1, "A5: 源码含『受击/敌人/处决』分区注释行")
	var script: GDScript = load("res://gdscripts/constants.gd")
	var consts: Dictionary = script.get_script_constant_map()
	var new_consts: Array = [
		"POSTURE_HIT_COST",
		"PARRY_COST",
		"POSTURE_RECOVERY_DELAY",
		"ENEMY_ATTACK_WINDUP",
		"EXECUTE_RANGE",
		"SLOWMO_COEFF",
		"LIFE_2_ABS",
	]
	for name in new_consts:
		_assert(consts.has(name), "A5: 新增常量 %s 存在" % name)


func _test_a6_default_values() -> void:
	var script: GDScript = load("res://gdscripts/constants.gd")
	var consts: Dictionary = script.get_script_constant_map()
	_assert(consts.get("PARRY_WINDOW_FRAMES", -1) == 12, "A6: PARRY_WINDOW_FRAMES == 12 (got %s)" % str(consts.get("PARRY_WINDOW_FRAMES", "MISSING")))
	_assert(consts.get("POSTURE_RECOVERY_PER_SEC", -1.0) == 25, "A6: POSTURE_RECOVERY_PER_SEC == 25 (got %s)" % str(consts.get("POSTURE_RECOVERY_PER_SEC", "MISSING")))
	_assert(consts.get("POSTURE_RECOVERY_PER_SEC", -1.0) != 0.8, "A6: 旧占位 0.8 必须消失")
	_assert(consts.get("POSTURE_HIT_COST", -1.0) == 18.0, "A6: POSTURE_HIT_COST == 18.0 (got %s)" % str(consts.get("POSTURE_HIT_COST", "MISSING")))
	_assert(consts.get("LIFE_2_ABS", -1.0) == 50, "A6: LIFE_2_ABS == 50 (got %s)" % str(consts.get("LIFE_2_ABS", "MISSING")))
	_assert(consts.get("ENEMY_ATTACK_WINDUP", -1) == 12, "A6: ENEMY_ATTACK_WINDUP == 12 (AC1 对齐, #581 裁决点 1, got %s)" % str(consts.get("ENEMY_ATTACK_WINDUP", "MISSING")))
	_assert(consts.get("EXECUTE_RANGE", -1.0) == 1.2, "A6: EXECUTE_RANGE == 1.2 (got %s)" % str(consts.get("EXECUTE_RANGE", "MISSING")))
	_assert(consts.get("SLOWMO_COEFF", -1.0) == 0.2, "A6: SLOWMO_COEFF == 0.2 (got %s)" % str(consts.get("SLOWMO_COEFF", "MISSING")))
