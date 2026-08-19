extends Object
## Test suite for DebugCanvas tuning panel (#584) — Scenario B (读值回落链路),
## C (PARAMS ↔ constants 一致性), D (面板行为).
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/584-combat-tuning-draft.md §2.1 / §8 Scenario B/C/D
##
## NOTE: debug_canvas.gd declares class_name DebugCanvas, so it is preloaded as
## DebugCanvasScript to avoid the class_name collision pattern used elsewhere.
## _overrides is a static var (process-wide), so every D-test clears it first.

const DebugCanvasScript = preload("res://gdscripts/debug_canvas.gd")

## #584 Scenario A/C: 14 个 tunable DRAFT 参数（C1 双向一致性 + D5 dump 断言共用）
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

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== DebugCanvas Tests ===")
	_test_b1_override_hit()
	_test_b2_no_override_fallback()
	_test_b3_unknown_param_silent()
	_test_b4_debug_only()
	_test_b5_derived_resolution()
	_test_c1_params_constants_consistency()
	_test_c2_range_covers_default()
	_test_c3_candidates_in_range()
	_test_d1_f1_toggle()
	_test_d2_out_of_range_rejected()
	_test_d3_slowmo_clamp()
	_test_d4_linked_write()
	_test_d5_dump_json()
	_test_d6_reset_defaults()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _clear_overrides() -> void:
	DebugCanvasScript._overrides.clear()


## 重置契约：DESIGN §2.1「重置默认」= 清空 override dict；实现若提供
## 独立 reset 方法，这里直接清静态 dict 语义等价（测试不依赖方法命名）。
func _reset_overrides() -> void:
	DebugCanvasScript._overrides.clear()


func _find_param(name: String) -> Dictionary:
	for p in DebugCanvasScript.PARAMS:
		if p["name"] == name:
			return p
	return {}


func _make_key_event(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = keycode
	return ev


# ── Scenario B: 读值回落链路（AC2/AC3）──

func _test_b1_override_hit() -> void:
	var got: Variant = DebugCanvasScript._resolve_value("PARRY_WINDOW_FRAMES", 12, {"PARRY_WINDOW_FRAMES": 8})
	_assert(got == 8, "B1: override 命中 → 返回 8 (got %s)" % str(got))


func _test_b2_no_override_fallback() -> void:
	var got: Variant = DebugCanvasScript._resolve_value("PARRY_WINDOW_FRAMES", 12, {})
	_assert(got == 12, "B2: 无 override → 回落默认 12 (got %s)" % str(got))


func _test_b3_unknown_param_silent() -> void:
	var got: Variant = DebugCanvasScript._resolve_value("TYPO_NAME", 12, {"PARRY_WINDOW_FRAMES": 8})
	_assert(got == 12, "B3: 未知参数名 → 静默回落 12 (got %s)" % str(got))


func _test_b4_debug_only() -> void:
	_assert(DebugCanvasScript.is_available(), "B4: is_available() 当前 debug 环境为 true")
	var f: FileAccess = FileAccess.open("res://gdscripts/debug_canvas.gd", FileAccess.READ)
	if f == null:
		_assert(false, "B4: debug_canvas.gd opens for reading")
		return
	var text: String = f.get_as_text()
	f.close()
	_assert(text.find("OS.is_debug_build()") != -1, "B4: debug_canvas.gd 源码含 OS.is_debug_build() 判定")


func _test_b5_derived_resolution() -> void:
	var got1: Variant = DebugCanvasScript._resolve_value("POSTURE_BREAK_THRESHOLD", 100, {"LIFE_1_MAX": 150})
	_assert(got1 == 150, "B5: 无本键 → 派生回落 LIFE_1_MAX → 150 (got %s)" % str(got1))
	var got2: Variant = DebugCanvasScript._resolve_value("POSTURE_BREAK_THRESHOLD", 100, {"POSTURE_BREAK_THRESHOLD": 90})
	_assert(got2 == 90, "B5: override 有本键 → 优先 90 (got %s)" % str(got2))


# ── Scenario C: 参数表一致性自检（PRD §5.3-2 防拼写错误）──

func _test_c1_params_constants_consistency() -> void:
	var params_array: Array = DebugCanvasScript.PARAMS
	_assert(params_array.size() == 14, "C1: PARAMS 共 14 行 (got %d)" % params_array.size())
	var constants_script: GDScript = load("res://gdscripts/constants.gd")
	var const_map: Dictionary = constants_script.get_script_constant_map()
	var params_names: Dictionary = {}
	for p in params_array:
		params_names[p["name"]] = true
	var missing_in_constants: Array = []
	for n in params_names:
		if not const_map.has(n):
			missing_in_constants.append(n)
	_assert(missing_in_constants.is_empty(), "C1: 每个 PARAMS name 都真实存在于 constants.gd (missing: %s)" % str(missing_in_constants))
	var missing_in_params: Array = []
	for expected in EXPECTED_PARAMS:
		if not params_names.has(expected):
			missing_in_params.append(expected)
	_assert(missing_in_params.is_empty(), "C1: 14 个 tunable 常量都有面板行 (missing: %s)" % str(missing_in_params))
	_assert(params_names.size() == EXPECTED_PARAMS.size() and missing_in_params.is_empty(), "C1: PARAMS name 集合 == 期望 14（双向集合相等, size %d）" % params_names.size())


func _test_c2_range_covers_default() -> void:
	for p in DebugCanvasScript.PARAMS:
		var ok: bool = float(p["min"]) <= float(p["default"]) and float(p["default"]) <= float(p["max"]) and float(p["step"]) > 0.0
		_assert(ok, "C2: %s min<=default<=max 且 step>0 (min=%s default=%s max=%s step=%s)" % [str(p["name"]), str(p["min"]), str(p["default"]), str(p["max"]), str(p["step"])])


func _test_c3_candidates_in_range() -> void:
	for p in DebugCanvasScript.PARAMS:
		var candidates: Array = p["candidates"]
		if candidates.is_empty():
			continue
		for c in candidates:
			_assert(float(c) >= float(p["min"]) and float(c) <= float(p["max"]), "C3: %s 候选 %s 落在 [%s, %s]" % [str(p["name"]), str(c), str(p["min"]), str(p["max"])])


# ── Scenario D: 面板行为（AC2）──

func _test_d1_f1_toggle() -> void:
	var panel = DebugCanvasScript.new()
	_assert(panel.visible == false, "D1: 初始 visible == false")
	panel._unhandled_input(_make_key_event(KEY_F1))
	_assert(panel.visible == true, "D1: KEY_F1 pressed+非echo → visible 翻转为 true")
	panel._unhandled_input(_make_key_event(KEY_F2))
	_assert(panel.visible == true, "D1: KEY_F2 不响应 → visible 仍为 true")
	panel.free()


func _test_d2_out_of_range_rejected() -> void:
	_clear_overrides()
	var panel = DebugCanvasScript.new()
	var first: Dictionary = DebugCanvasScript.PARAMS[0]
	_assert(str(first["name"]) == "PARRY_WINDOW_FRAMES", "D2: PARAMS[0] 为 PARRY_WINDOW_FRAMES (got %s)" % str(first["name"]))
	panel._on_param_changed(first, 100.0)
	_assert(not DebugCanvasScript._overrides.has("PARRY_WINDOW_FRAMES"), "D2: 越界 100 > max 30 → 拒绝写入 override")
	panel.free()


func _test_d3_slowmo_clamp() -> void:
	_clear_overrides()
	var panel = DebugCanvasScript.new()
	var row: Dictionary = _find_param("SLOWMO_COEFF")
	_assert(not row.is_empty(), "D3: 找到 SLOWMO_COEFF 参数行")
	panel._on_param_changed(row, 0.0)
	_assert(DebugCanvasScript._overrides.get("SLOWMO_COEFF", -1.0) == 0.1, "D3: SLOWMO 0.0 → clamp 下限 0.1 (got %s)" % str(DebugCanvasScript._overrides.get("SLOWMO_COEFF", -1.0)))
	panel._on_param_changed(row, 0.4)
	_assert(DebugCanvasScript._overrides.get("SLOWMO_COEFF", -1.0) == 0.4, "D3: SLOWMO 0.4 上限内 → 0.4 (got %s)" % str(DebugCanvasScript._overrides.get("SLOWMO_COEFF", -1.0)))
	panel.free()


func _test_d4_linked_write() -> void:
	_clear_overrides()
	var panel = DebugCanvasScript.new()
	var row: Dictionary = _find_param("LIFE_1_MAX")
	_assert(not row.is_empty(), "D4: 找到 LIFE_1_MAX 参数行")
	panel._on_param_changed(row, 150.0)
	_assert(DebugCanvasScript._overrides.get("POSTURE_BREAK_THRESHOLD", -1.0) == 150.0, "D4: LIFE_1_MAX=150 → POSTURE_BREAK_THRESHOLD 联动 = 150 (got %s)" % str(DebugCanvasScript._overrides.get("POSTURE_BREAK_THRESHOLD", -1.0)))
	panel.free()


func _test_d5_dump_json() -> void:
	_clear_overrides()
	var panel = DebugCanvasScript.new()
	panel._on_param_changed(_find_param("PARRY_WINDOW_FRAMES"), 10.0)
	var dump_result: Variant = panel._export_dump()
	var path: String = ""
	if typeof(dump_result) == TYPE_STRING and str(dump_result) != "":
		path = str(dump_result)
	else:
		path = _newest_dump_path()
	_assert(path != "", "D5: dump 路径解析成功")
	if path == "":
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	_assert(f != null, "D5: dump 文件可读 (%s)" % path)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	var err: Error = json.parse(text)
	_assert(err == OK, "D5: JSON.parse 成功 (err %d)" % err)
	if err != OK:
		return
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		_assert(false, "D5: dump 根对象为 Dictionary")
		return
	var data_dict: Dictionary = data
	var params: Variant = data_dict.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		_assert(false, "D5: dump.params 为 Dictionary")
		return
	var params_dict: Dictionary = params
	for name in EXPECTED_PARAMS:
		_assert(params_dict.has(name), "D5: params 含全部 14 参数（缺 %s）" % name)
	_assert(float(params_dict.get("PARRY_WINDOW_FRAMES", -1.0)) == 10.0, "D5: dump 反映 override 值 (PARRY_WINDOW_FRAMES=10, got %s)" % str(params_dict.get("PARRY_WINDOW_FRAMES", -1.0)))
	var meta: Variant = data_dict.get("meta", {})
	if typeof(meta) != TYPE_DICTIONARY:
		_assert(false, "D5: dump.meta 为 Dictionary")
		return
	var meta_dict: Dictionary = meta
	_assert(str(meta_dict.get("game_version", "")) == "v0.1.0", "D5: meta.game_version == v0.1.0 (got %s)" % str(meta_dict.get("game_version", "")))
	panel.free()


func _newest_dump_path() -> String:
	var da: DirAccess = DirAccess.open("user://")
	if da == null:
		return ""
	var newest: String = ""
	var newest_mtime: int = -1
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and fn.begins_with("tuning_dump_") and fn.ends_with(".json"):
			var mtime: int = da.get_modified_time(fn)
			if mtime >= newest_mtime:
				newest_mtime = mtime
				newest = fn
		fn = da.get_next()
	da.list_dir_end()
	if newest == "":
		return ""
	return "user://" + newest


func _test_d6_reset_defaults() -> void:
	_clear_overrides()
	var panel = DebugCanvasScript.new()
	panel._on_param_changed(_find_param("PARRY_WINDOW_FRAMES"), 14.0)
	panel._on_param_changed(_find_param("LIFE_1_MAX"), 150.0)
	_assert(DebugCanvasScript._overrides.has("PARRY_WINDOW_FRAMES"), "D6: 重置前 override 已写入")
	_assert(DebugCanvasScript._overrides.has("POSTURE_BREAK_THRESHOLD"), "D6: 重置前联动 override 已写入")
	_reset_overrides()
	_assert(DebugCanvasScript._overrides.is_empty(), "D6: 重置后 _overrides 为空")
	_assert(DebugCanvasScript.get_value("PARRY_WINDOW_FRAMES", 12) == 12, "D6: 重置后 get_value 回落默认 12")
	panel.free()
