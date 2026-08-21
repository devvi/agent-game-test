extends CanvasLayer
class_name PauseMenu
## PauseMenu — ESC 暂停菜单 + 操作手册（#719）。
## 归属: docs/DESIGN/719-esc-pause-menu.md §2.1/§2.2/§2.3
## 职责: 系统级输入（ESC）→ 树级暂停（get_tree().paused）的唯一持有者 + 菜单 UI
##   + 运行时从 InputMap 生成操作手册（AC3 机器保证）。
## 红线: InputController 零改动（A2）——ESC 由本层自检，暂停即自然冻结战斗意图层；
##   缓冲清空走既有公共 API（buffer_size()/poll_buffer()），不新增方法。
## 语义: 暂停是树状态而非组件状态——战斗侧（InputController/CombatEntity/EnemyAI/
##   Atmosphere/HUD）全部 INHERIT 默认，paused=true 一帧冻结全部，天然满足 AC4。
## 唯一入口: toggle_pause()（幂等 + FAIL 守卫）——「继续」按钮与再次 ESC 走同一函数同一分支。

const C = preload("res://gdscripts/constants.gd")
const GAME_STATE_FAIL: int = 4  # matches MainBattle.GameState.FAIL (#585)

## 手册动态条目：固定有序 9 战斗/移动动作（排除 game_pause）+ 中文标签（taste 域，供展示）
const MANUAL_ACTIONS: Array = [
	["game_move_left", "移动"],
	["game_move_right", "移动"],
	["game_light_attack", "轻攻击"],
	["game_heavy_attack", "重攻击"],
	["game_guard", "格挡"],
	["game_dash", "闪避"],
	["game_jump", "跳跃"],
	["game_interact", "互动"],
	["game_revive", "复活"],
]
## 键名展示映射（physical_keycode -> 展示名；# DRAFT 美观名候选）
const KEY_DISPLAY: Dictionary = {
	65: "A",
	68: "D",
	4194319: "←",
	4194321: "→",
	74: "J",
	75: "K",
	76: "L",
	4194325: "Shift",
	32: "空格",
	69: "E",
	70: "F",
	4194305: "ESC",
}

## 状态
var _paused: bool = false                 # 当前暂停态（toggle 幂等基准）
var _manual_visible: bool = false         # 手册面板可见态（ESC 恢复优先关闭）
var _game_state_getter: Callable = Callable()  # 注入的 game_state 只读闭包（FAIL 守卫）
var _input_controller: Node = null        # /root/InputController 引用（恢复时清缓冲）
var _was_pause_pressed: bool = false            # ESC 边沿检测状态（同 input_controller.gd 模式）

## 公有节点成员（_ready 代码创建，tests 直接访问，Hud 同构）
var DimOverlay: ColorRect
var MenuRoot: VBoxContainer
var TitleLabel: Label
var ResumeButton: Button
var ManualButton: Button
var HintLabel: Label
var ManualPanel: VBoxContainer
var ManualTitle: Label
var ManualLines: VBoxContainer

## 内部节点成员（测试不断言，仅本类使用）
var _manual_scroll: ScrollContainer = null


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS      # 战斗冻结时菜单仍响应（AC4）
	if not InputMap.has_action("game_pause"):
		push_error("PauseMenu: missing Input Map action 'game_pause'")  # fail-safe: 禁用菜单不崩溃
		set_process(false)
		return
	_create_nodes()                               # 零 tscn 代码建树（Hud 同构）
	add_to_group("pause_menu")                    # 装配重入幂等守卫（首实例保留）
	var first: Node = get_tree().get_first_node_in_group("pause_menu")
	if first != null and first != self:
		queue_free()
		return
	_input_controller = get_node_or_null("/root/InputController")


func _process(_delta: float) -> void:
	## A2: PauseMenu 自检 ESC 边沿（ALWAYS 常驻，暂停中仍响应）。
	## 边沿检测用 is_action_pressed + _was_pause_pressed（同 input_controller.gd 模式），
	## 不用 is_action_just_pressed —— 后者依赖引擎处理帧计数，在 --script 手动驱动
	## _process 的测试环境下恒为 false（Godot 4.7.1 headless 陷阱，见 #719 CI 失败）。
	var now_pressed: bool = Input.is_action_pressed("game_pause")
	if now_pressed and not _was_pause_pressed:
		toggle_pause()
	_was_pause_pressed = now_pressed


# ── 唯一暂停/恢复入口（幂等 + FAIL 守卫）──────────────────────────────────

func toggle_pause() -> void:
	## 唯一暂停/恢复入口：FAIL 终态忽略；其余按当前 _paused 分支翻转。
	## 「继续」按钮与再次 ESC 走同一函数同一分支，杜绝两处恢复代码漂移。
	if _game_state_getter.is_valid() and int(_game_state_getter.call()) == GAME_STATE_FAIL:
		return                                    # FAIL 终态: 不弹菜单（幂等）
	if _paused:
		_resume()
	else:
		_pause()


func _pause() -> void:
	_paused = true
	get_tree().paused = true                      # 全局冻结（INHERIT 全覆盖）
	DimOverlay.visible = true
	MenuRoot.visible = true


func _resume() -> void:
	## 唯一恢复路径（禁止散点 paused=false 直写）
	_paused = false
	_manual_visible = false
	ManualPanel.visible = false
	_manual_scroll.visible = false
	DimOverlay.visible = false
	MenuRoot.visible = false
	_clear_input_buffer()                         # 防恢复瞬间「隔空出刀」（§3.4）
	get_tree().paused = false                     # 唯一恢复路径


func _clear_input_buffer() -> void:
	## InputController 零改动方案: 走既有公共 API 循环清空（poll_buffer 内含 _clear_expired）
	if _input_controller == null:
		return
	while _input_controller.buffer_size() > 0:
		_input_controller.poll_buffer()


func bind_game_state(getter: Callable) -> void:
	## 注入 game_state 只读闭包（FAIL 守卫用；不暴露写接口）
	_game_state_getter = getter


# ── 操作手册 ────────────────────────────────────────────────────────────

func _toggle_manual() -> void:
	_manual_visible = not _manual_visible
	ManualPanel.visible = _manual_visible
	_manual_scroll.visible = _manual_visible
	if _manual_visible and ManualLines.get_child_count() == 0:
		_populate_manual_lines()                  # 首开懒生成，避免每帧重建


func _populate_manual_lines() -> void:
	for row in manual_text():
		var line: Label = Label.new()
		line.text = str(row["label"]) + "　" + str(row["keys"])
		line.add_theme_font_size_override("font_size", C.PAUSE_MANUAL_FONT_SIZE)
		line.add_theme_color_override("font_color", C.HUD_MOON_WHITE)
		ManualLines.add_child(line)


func manual_text() -> Array:
	## 运行时从 InputMap 生成 [动作, 键名列表] 行（AC3 机器保证）。
	## 动态: MANUAL_ACTIONS 遍历 action_get_events() → keycode 映射（§2.4 表）。
	## 静态: 追加处决说明行（# DRAFT 文案候选, 不参与一致性断言）。
	var rows: Array = []
	for entry in MANUAL_ACTIONS:
		var action: StringName = StringName(entry[0])
		var label: String = str(entry[1])
		var keys: PackedStringArray = _action_key_names(action)
		rows.append({"action": action, "label": label, "keys": " / ".join(keys)})
	rows.append({
		"action": &"game_execute",
		"label": "处决",
		"keys": str(C.PAUSE_EXECUTE_LINE_CANDIDATES[0]),
	})
	return rows


func _action_key_names(action: StringName) -> PackedStringArray:
	## 遍历 InputMap 事件 → 展示键名（防映射表漏项：映射失败回退 OS.get_keycode_string）
	var names: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		var name: String = _event_display_name(event)
		if name != "":
			names.append(name)
	return names


func _event_display_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var key: InputEventKey = event
		var code: int = key.physical_keycode
		if KEY_DISPLAY.has(code):
			return str(KEY_DISPLAY[code])
		return OS.get_keycode_string(code)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			1:
				return "鼠标左键"
			2:
				return "鼠标右键"
	return ""


# ── 节点创建（零 tscn 零贴图，纯代码）─────────────────────────────────────

func _create_nodes() -> void:
	DimOverlay = ColorRect.new()
	DimOverlay.color = C.PAUSE_DIM_COLOR
	DimOverlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	DimOverlay.visible = false
	add_child(DimOverlay)

	MenuRoot = VBoxContainer.new()
	MenuRoot.set_anchors_preset(Control.PRESET_CENTER)
	MenuRoot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	MenuRoot.grow_vertical = Control.GROW_DIRECTION_BOTH
	MenuRoot.add_theme_constant_override("separation", 12)
	MenuRoot.visible = false
	add_child(MenuRoot)

	TitleLabel = Label.new()
	TitleLabel.text = str(C.PAUSE_TITLE_CANDIDATES[0])
	TitleLabel.add_theme_font_size_override("font_size", C.PAUSE_TITLE_FONT_SIZE)
	TitleLabel.add_theme_color_override("font_color", C.HUD_MOON_WHITE)
	TitleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuRoot.add_child(TitleLabel)

	ResumeButton = Button.new()
	ResumeButton.text = str(C.PAUSE_BTN_RESUME_TEXT)
	ResumeButton.add_theme_font_size_override("font_size", C.PAUSE_BTN_FONT_SIZE)
	ResumeButton.custom_minimum_size = Vector2(220.0, 44.0)
	ResumeButton.pressed.connect(func() -> void: toggle_pause())      # 「继续」= 同一 toggle 入口
	MenuRoot.add_child(ResumeButton)

	ManualButton = Button.new()
	ManualButton.text = str(C.PAUSE_BTN_MANUAL_TEXT)
	ManualButton.add_theme_font_size_override("font_size", C.PAUSE_BTN_FONT_SIZE)
	ManualButton.custom_minimum_size = Vector2(220.0, 44.0)
	ManualButton.pressed.connect(func() -> void: _toggle_manual())    # 手册面板 visible 翻转
	MenuRoot.add_child(ManualButton)

	HintLabel = Label.new()
	HintLabel.text = str(C.PAUSE_HINT_TEXT)
	HintLabel.add_theme_font_size_override("font_size", 14)
	HintLabel.add_theme_color_override("font_color", C.HUD_MOON_WHITE)
	HintLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuRoot.add_child(HintLabel)

	_manual_scroll = ScrollContainer.new()
	_manual_scroll.set_anchors_preset(Control.PRESET_CENTER)
	_manual_scroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_manual_scroll.grow_vertical = Control.GROW_DIRECTION_BOTH
	_manual_scroll.custom_minimum_size = Vector2(560.0, 420.0)
	_manual_scroll.visible = false
	add_child(_manual_scroll)

	ManualPanel = VBoxContainer.new()
	ManualPanel.add_theme_constant_override("separation", 8)
	_manual_scroll.add_child(ManualPanel)

	ManualTitle = Label.new()
	ManualTitle.text = str(C.PAUSE_MANUAL_TITLE_TEXT)
	ManualTitle.add_theme_font_size_override("font_size", C.PAUSE_MANUAL_FONT_SIZE)
	ManualTitle.add_theme_color_override("font_color", C.HUD_MOON_WHITE)
	ManualTitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ManualPanel.add_child(ManualTitle)

	ManualLines = VBoxContainer.new()
	ManualLines.add_theme_constant_override("separation", 4)
	ManualPanel.add_child(ManualLines)
