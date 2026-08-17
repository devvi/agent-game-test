extends CanvasLayer
## PauseOverlay — semi-transparent mask + "暂停" label + score/wave info, shown during PAUSED state.
## Follows the CanvasLayer + ColorRect + Label pattern from StartMenu/GameOverScreen (#292).
##
## Design: docs/DESIGN/296-pause-and-sound.md §2.1, docs/DESIGN/513-pause-score-wave.md
## Parent Issue: #296, #513

const CONSTS = preload("res://gdscripts/constants.gd")
const NeonStyle = preload("res://gdscripts/ui_neon_style.gd")

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var score_label: Label = $ScoreLabel
@onready var wave_label: Label = $WaveLabel

## GameManager 引用（autoload；测试可注入 mock，见 test_pause_overlay.gd）
var game_manager

var _warned_gm: bool = false


func _ready() -> void:
	hide()


func show_overlay() -> void:
	visible = true
	_read_state()


func hide_overlay() -> void:
	visible = false


func _resolve_game_manager():
	if game_manager != null:
		return game_manager
	var gm_singleton = Engine.get_singleton("GameManager")
	if is_instance_valid(gm_singleton):
		game_manager = gm_singleton
	elif game_manager == null:
		var root_gm = get_node_or_null("/root/GameManager")
		if is_instance_valid(root_gm):
			game_manager = root_gm
	return game_manager


func _read_state() -> void:
	var gm = _resolve_game_manager()
	if gm == null:
		if not _warned_gm:
			push_warning("PauseOverlay: GameManager 未找到，显示占位符")
			_warned_gm = true
		_set_texts("—", "—")
		return
	var p = gm.get("player_score")
	var a = gm.get("ai_score")
	var w = gm.get("wave_index")
	var score_text = CONSTS.HUD_SCORE_PREFIX_PLAYER + str(int(p) if p != null else 0) + "   " + CONSTS.HUD_SCORE_PREFIX_AI + str(int(a) if a != null else 0)
	var wave_text = CONSTS.HUD_WAVE_PREFIX + str(int(w) if w != null else 0) + CONSTS.HUD_WAVE_SUFFIX
	_set_texts(score_text, wave_text)


func _set_texts(score_text: String, wave_text: String) -> void:
	if score_label:
		score_label.text = score_text
		NeonStyle.apply(score_label, CONSTS.HUD_INFO_COLOR)
	if wave_label:
		wave_label.text = wave_text
		NeonStyle.apply(wave_label, CONSTS.HUD_INFO_COLOR)
