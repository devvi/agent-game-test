extends CanvasLayer
## DebugCanvas — shandong-wolf 战斗数值调参面板（#584 DRAFT）。
## 纯 Control 程序化构建（零 .tscn 零图片资产），F1 物理键 toggle，仅 debug build。
## 消费方读值: DebugCanvas.get_value("NAME", C.NAME)（debug 热更新优先，release 回落 const）。
## Design: docs/DESIGN/584-combat-tuning-draft.md §2.1 / §2.2

class_name DebugCanvas

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

## 面板唯一数据源：驱动 UI 生成 + 一致性自检（C1-C3）+ dump 全量导出（D5）
const PARAMS: Array[Dictionary] = [
	{"name": "PARRY_WINDOW_FRAMES",      "label": "弹反窗口(帧)",  "min": 4,  "max": 30, "step": 1,   "candidates": [8, 10, 12, 14],   "default": 12},
	{"name": "POSTURE_RECOVERY_PER_SEC", "label": "架势回复/s",   "min": 5,  "max": 50, "step": 1,   "candidates": [20, 25, 30, 35],  "default": 25},
	{"name": "POSTURE_RECOVERY_DELAY",   "label": "回复延迟(s)",  "min": 0.5,"max": 3.0,"step": 0.1, "candidates": [1.0, 1.5, 2.0],    "default": 1.5},
	{"name": "POSTURE_BLOCK_COST",       "label": "格挡扣架势",   "min": 1,  "max": 30, "step": 1,   "candidates": [8, 10, 12],       "default": 10},
	{"name": "PARRY_COST",               "label": "弹反扣架势",   "min": 0,  "max": 5,  "step": 1,   "candidates": [0, 1, 2],         "default": 1},
	{"name": "POSTURE_HIT_COST",         "label": "受击扣架势",   "min": 5,  "max": 60, "step": 1,   "candidates": [30, 35, 40],      "default": 35},
	{"name": "POSTURE_BREAK_THRESHOLD",  "label": "架势上限",     "min": 50, "max": 200,"step": 5,   "candidates": [],                "default": 100, "derived": true},
	{"name": "LIFE_1_MAX",               "label": "第一条命HP",   "min": 50, "max": 200,"step": 5,   "candidates": [100, 120],        "default": 100},
	{"name": "LIFE_2_ABS",               "label": "回生后HP",     "min": 20, "max": 100,"step": 5,   "candidates": [40, 50, 60],      "default": 50},
	{"name": "SWORD_DAMAGE_LIGHT",       "label": "轻击架势伤",   "min": 1,  "max": 30, "step": 1,   "candidates": [10, 12, 15],      "default": 12},
	{"name": "SWORD_DAMAGE_HEAVY",       "label": "重击架势伤",   "min": 10, "max": 80, "step": 1,   "candidates": [25, 30, 40],      "default": 30},
	{"name": "ENEMY_ATTACK_WINDUP",      "label": "敌前摇(帧)",   "min": 4,  "max": 30, "step": 1,   "candidates": [12, 15, 18],      "default": 15},
	{"name": "EXECUTE_RANGE",            "label": "处决距离(m)",  "min": 0.5,"max": 3.0,"step": 0.1, "candidates": [1.0, 1.2, 1.5],    "default": 1.2},
	{"name": "SLOWMO_COEFF",             "label": "慢动作系数",   "min": 0.1,"max": 0.5,"step": 0.05, "candidates": [0.1, 0.2, 0.3],   "default": 0.2},
]

static var _overrides: Dictionary = {}

var _rows: Dictionary = {}
var _syncing: bool = false


## 读值入口（PRD §4.3-A「Tuning」）：release 首行回落 const，零 dict 查询零分支污染。
static func get_value(param_name: String, default_value: Variant) -> Variant:
	if not OS.is_debug_build():
		return default_value
	if _overrides.has(param_name):
		return _overrides[param_name]
	return default_value


## 纯函数裁决（可测缝隙，test_debug_canvas.gd 直接喂 dict 断言）
static func _resolve_value(param_name: String, default_value: Variant, overrides: Dictionary) -> Variant:
	if overrides.has(param_name):
		return overrides[param_name]
	elif param_name == "POSTURE_BREAK_THRESHOLD" and overrides.has("LIFE_1_MAX"):
		return overrides["LIFE_1_MAX"]
	else:
		return default_value


static func is_available() -> bool:
	return OS.is_debug_build()


func _init() -> void:
	visible = false
	layer = 100


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		visible = not visible


func _on_param_changed(param: Dictionary, value: float) -> void:
	var name: String = str(param["name"])
	if name == "SLOWMO_COEFF" and value < 0.1:
		value = 0.1
	elif value < float(param["min"]) or value > float(param["max"]):
		return
	_overrides[name] = value
	_apply_derived_rules(name, value)


func _apply_derived_rules(changed: String, value: float) -> void:
	if changed == "LIFE_1_MAX":
		_overrides["POSTURE_BREAK_THRESHOLD"] = value
		_sync_row("POSTURE_BREAK_THRESHOLD", value)
	elif changed == "POSTURE_BREAK_THRESHOLD":
		_overrides["LIFE_1_MAX"] = value
		_sync_row("LIFE_1_MAX", value)


func _sync_row(param_name: String, value: float) -> void:
	if not _rows.has(param_name):
		return
	var widgets: Dictionary = _rows[param_name]
	var slider: HSlider = widgets["slider"]
	var spin: SpinBox = widgets["spin"]
	_syncing = true
	slider.value = value
	spin.value = value
	_syncing = false


func _reset_defaults() -> void:
	_overrides.clear()
	for p in PARAMS:
		_sync_row(str(p["name"]), float(p["default"]))


func _export_dump() -> String:
	var ts := Time.get_datetime_string_from_system()
	var params: Dictionary = {}
	for p in PARAMS:
		var name: String = str(p["name"])
		params[name] = _resolve_value(name, p["default"], _overrides)
	var data := {
		"meta": {
			"game_version": WolfConstantsScript.GAME_VERSION,
			"ts": ts,
			"group": "manual",
		},
		"params": params,
	}
	var path := "user://tuning_dump_%s.json" % ts.replace(":", "-")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("DebugCanvas: 无法写入 dump 文件: %s" % path)
		return ""
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return path


func _build_ui() -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.8)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(12, 12)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(440, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "战斗数值调参 #584 (DRAFT)"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 400)
	vbox.add_child(scroll)

	var rows_box := VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)

	for p in PARAMS:
		var param: Dictionary = p
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)
		rows_box.add_child(row)

		var name_label := Label.new()
		name_label.text = "%s %s" % [str(param["label"]), str(param["candidates"])]
		name_label.custom_minimum_size = Vector2(170, 0)
		row.add_child(name_label)

		var slider := HSlider.new()
		slider.min_value = param["min"]
		slider.max_value = param["max"]
		slider.step = param["step"]
		slider.value = param["default"]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)

		var spin := SpinBox.new()
		spin.min_value = param["min"]
		spin.max_value = param["max"]
		spin.step = param["step"]
		spin.value = param["default"]
		spin.custom_minimum_size = Vector2(70, 0)
		row.add_child(spin)

		slider.value_changed.connect(_on_slider_changed.bind(param))
		spin.value_changed.connect(_on_slider_changed.bind(param))
		_rows[str(param["name"])] = {"slider": slider, "spin": spin}

	var tools := HBoxContainer.new()
	vbox.add_child(tools)

	var export_btn := Button.new()
	export_btn.text = "导出 JSON"
	export_btn.pressed.connect(_export_dump)
	tools.add_child(export_btn)

	var reset_btn := Button.new()
	reset_btn.text = "重置默认"
	reset_btn.pressed.connect(_reset_defaults)
	tools.add_child(reset_btn)

	var hide_btn := Button.new()
	hide_btn.text = "隐藏 (F1)"
	hide_btn.pressed.connect(func() -> void: visible = false)
	tools.add_child(hide_btn)


func _on_slider_changed(value: float, param: Dictionary) -> void:
	if _syncing:
		return
	_on_param_changed(param, value)
