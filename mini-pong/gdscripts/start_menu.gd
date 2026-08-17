extends CanvasLayer
## StartMenu — neon title screen with pulsing glow and SPACE-to-start prompt.
## Parent Issue: #292

# ── Constants (via GameConstants, #358) ──
const CONSTS = preload("res://gdscripts/constants.gd")

# ── Exported ──
@export var title_pulse_min: float = 0.6       # Minimum alpha during pulse
@export var title_pulse_max: float = 1.0       # Maximum alpha during pulse
@export var title_pulse_duration: float = 1.5  # Seconds for one full pulse cycle
@export var prompt_blink_period: float = 0.8   # Seconds for one full blink cycle

# ── Node References ──
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var prompt_label: Label = $CenterContainer/VBoxContainer/PromptLabel
@onready var version_label: Label = get_node_or_null("VersionLabel")  # #358 — fallback ref, null-safe

# ── State ──
var _title_tween: Tween = null
var _prompt_tween: Tween = null
var _transitioning: bool = false

# ── 模式选择 (#543 §3.1) ──
var _mode_index: int = 0              # 0 = SINGLE（默认），1 = LOCAL_2P（与 GameManager.GameMode 同值对齐）
var _mode_labels: Array = []          # _ready 收集 ModeOption1/2（append only 非 null）
var _mode_tween: Tween = null         # 高亮切换动效句柄（keep simple，未强制启用）


# ── Lifecycle ──
func _ready() -> void:
	# Guard: run only if nodes exist
	if not title_label or not prompt_label:
		return

	# Version text — single source of truth GameConstants.GAME_VERSION (#358)
	if version_label:
		version_label.text = CONSTS.GAME_VERSION

	# Start glow/pulse animations (headless-safe)
	if is_inside_tree() and get_tree():
		_start_title_pulse()
		_start_prompt_blink()

	# #543: 收集模式选项行 + 默认高亮单人（节点缺失静默跳过，headless 容错）
	_mode_labels = []
	var opt1 = get_node_or_null("CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption1")
	var opt2 = get_node_or_null("CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption2")
	if opt1 != null:
		_mode_labels.append(opt1)
	if opt2 != null:
		_mode_labels.append(opt2)
	_apply_mode_highlight()

	visible = true


# REMOVED: _input() — FSM (#294) handles SPACE in MENU state


# ── Public ──
func get_selected_mode() -> int:
	return _mode_index


func show_menu() -> void:
	"""Called by state machine (#294) to re-show the start screen."""
	visible = true
	_transitioning = false
	_apply_mode_highlight()            # #543: 重绘高亮（保留上次选择，§6-8）
	if is_inside_tree() and get_tree():
		_start_title_pulse()
		_start_prompt_blink()


func hide_menu() -> void:
	"""Cleanup animations and hide."""
	_kill_tweens()
	_kill_tween(_mode_tween)           # #543: 模式高亮动效一并清理
	_mode_tween = null
	visible = false


## #543: 模式切换（↑/↓）。仅 visible（MENU 态）响应；不消费 ui_accept（FSM 继续处理）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_up"):
		_mode_index = posmod(_mode_index - 1, 2)
		_apply_mode_highlight()
		if is_instance_valid(GameManager) and GameManager.has_method("set_game_mode"):
			GameManager.set_game_mode(_mode_index)
	elif event.is_action_pressed("ui_down"):
		_mode_index = posmod(_mode_index + 1, 2)
		_apply_mode_highlight()
		if is_instance_valid(GameManager) and GameManager.has_method("set_game_mode"):
			GameManager.set_game_mode(_mode_index)


## #543: 高亮重绘 — 选中行 PADDLE_NEON + 字号 24；未选中 0.4 透明度 + 字号 20
## （色值距 #4a90d9 远离 tol 32，E2E 01_title theme_absent 保护；Tween 150ms 可选，keep simple）。
func _apply_mode_highlight() -> void:
	for i in _mode_labels.size():
		var lbl: Label = _mode_labels[i]
		if lbl == null:
			continue
		if i == _mode_index:
			lbl.modulate = CONSTS.PADDLE_NEON
			lbl.add_theme_font_size_override("font_size", 24)
		else:
			lbl.modulate = Color(1, 1, 1, 0.4)
			lbl.add_theme_font_size_override("font_size", 20)


# ── Animation ──
func _start_title_pulse() -> void:
	_kill_tween(_title_tween)
	_title_tween = create_tween()
	_title_tween.set_loops()  # infinite
	_title_tween.tween_property(title_label, "modulate:a", title_pulse_min, title_pulse_duration * 0.5)
	_title_tween.tween_property(title_label, "modulate:a", title_pulse_max, title_pulse_duration * 0.5)


func _start_prompt_blink() -> void:
	_kill_tween(_prompt_tween)
	_prompt_tween = create_tween()
	_prompt_tween.set_loops()
	_prompt_tween.tween_property(prompt_label, "modulate:a", 0.0, prompt_blink_period * 0.5)
	_prompt_tween.tween_property(prompt_label, "modulate:a", 1.0, prompt_blink_period * 0.5)


# ── Internal ──
func _on_start_pressed() -> void:
	_transitioning = true
	_kill_tweens()
	visible = false

	# Show HUD layer
	var hud := _get_sibling("GameHUD")
	if hud:
		hud.visible = true

	# Trigger game start via GameManager
	GameManager.reset_match()


func _get_sibling(node_name: String) -> CanvasLayer:
	"""Find a sibling CanvasLayer by name. Returns null if not found."""
	var parent := get_parent()
	if not parent:
		return null
	return parent.get_node_or_null(node_name)


func _kill_tween(tween: Tween) -> void:
	if tween and is_instance_valid(tween):
		tween.kill()


func _kill_tweens() -> void:
	_kill_tween(_title_tween)
	_kill_tween(_prompt_tween)
	_title_tween = null
	_prompt_tween = null
