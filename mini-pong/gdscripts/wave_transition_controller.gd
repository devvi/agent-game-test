extends CanvasLayer
## WaveTransitionController — 波次转场（#390 契约 PRD #429；实现随 #393 组装落地）。
## 消费 GameManager.wave_started(wave_index)（#386 AC3 预留的「第 N 道墙」消费方）：
##   冻结球 + 双拍（Approach A 演员冻结，#296 惯例，不设 get_tree().paused）→
##   读 res://content/wave_failure_text.json 按波次分档选副句（决胜波 ws4 覆盖）→
##   2.0s Tween（淡入-停留-淡出，三段和恒 == 2.0）→ 兜底解锁（_finish 必达）。
##
## 时序事实（PRD #429 §4.4）: wave_started 与 generate_wave 同帧（WaveController 同步调用）
## ——新墙在覆盖层背后已生成，属预期，不改 WaveController 调用顺序。
##
## 内容红线（AC5）: 副句文本零硬编码——唯一内容源 = WAVE_TRANSITION_JSON_PATH（#396 schema）。
## 测试: 时长可注入（fade_in/hold/fade_out 成员，仿 wave_controller.settle_delay 模式）。
##
## Design: docs/PRD/390-wave-transition.md §3/§4（推荐组合: 演员冻结 + Tween 三段式 + 分档选句）
## Parent Issue: #390 (实现随 #393 组装落地)

const CONSTS = preload("res://gdscripts/constants.gd")

signal transition_finished()   # 测试/未来扩展锚点（解锁兜底完成的显式通知）

# ── 时长（测试可注入短值；生产默认三段和 == 2.0，AC2 断言）──
var fade_in: float = CONSTS.WAVE_TRANSITION_FADE_IN
var hold: float = CONSTS.WAVE_TRANSITION_HOLD
var fade_out: float = CONSTS.WAVE_TRANSITION_FADE_OUT

var _transitioning: bool = false      # 重入守卫（wave_started 连发忽略，边界 5）
var _subtitles: Array = []            # wave_subtitles 条目缓存（id/text/context/...）
var _json_warned: bool = false

@onready var overlay: Control = $Overlay
@onready var title_label: Label = $Overlay/Center/VBox/TitleLabel
@onready var subtitle_label: Label = $Overlay/Center/VBox/SubtitleLabel


func _ready() -> void:
	overlay.modulate.a = 0.0
	visible = false
	_load_subtitles()
	if is_instance_valid(GameManager) and GameManager.has_signal("wave_started"):
		GameManager.wave_started.connect(_on_wave_started)


func _exit_tree() -> void:
	if is_instance_valid(GameManager) and GameManager.has_signal("wave_started"):
		GameManager.wave_started.disconnect(_on_wave_started)


# ── 主入口 ──

func _on_wave_started(index: int) -> void:
	if _transitioning:
		return                             # 边界 5/7: 转场中忽略重复信号
	_transitioning = true
	var p_score: int = GameManager.player_score if is_instance_valid(GameManager) else 0
	var a_score: int = GameManager.ai_score if is_instance_valid(GameManager) else 0
	title_label.text = "第 %d 道墙" % index
	subtitle_label.text = _pick_subtitle(index, p_score, a_score)
	overlay.modulate.a = 0.0
	visible = true
	_freeze(true)                          # AC3: 冻结球 + 双拍（演员冻结，不设全局暂停）
	var tween = create_tween()
	tween.tween_property(overlay, "modulate:a", 1.0, fade_in)
	tween.tween_interval(hold)
	tween.tween_property(overlay, "modulate:a", 0.0, fade_out)
	tween.tween_callback(_finish)          # 兜底解锁（结束回调必达，失败路径 2）


func _finish() -> void:
	_freeze(false)                         # AC3: 解锁（幂等）
	visible = false
	_transitioning = false
	transition_finished.emit()


# ── 副句选择（PRD #429 §4.3 Approach A: 波次分档 + 决胜波覆盖）──

func _pick_subtitle(index: int, p_score: int, a_score: int) -> String:
	if p_score >= CONSTS.WAVE_TRANSITION_DECISIVE_SCORE or a_score >= CONSTS.WAVE_TRANSITION_DECISIVE_SCORE:
		return _subtitle_text("ws4")        # 决胜波覆盖（任一方 ≥18）
	if index <= CONSTS.WAVE_TRANSITION_BAND1_MAX:
		return _subtitle_text("ws1")        # 波 1-2（开局）
	if index <= CONSTS.WAVE_TRANSITION_BAND2_MAX:
		return _subtitle_text("ws2")        # 波 3-5（中段加压）
	return _subtitle_text("ws3")            # 波 6+（后期高压）


func _subtitle_text(id: String) -> String:
	for entry in _subtitles:
		if entry.get("id", "") == id:
			return entry.get("text", "")
	return ""                               # JSON 缺失/损坏 → 副句留空（只显示大字，不 crash）


## AC5: 从统一文本配置读取（#396 schema wave-failure-text/v1）
func _load_subtitles() -> void:
	_subtitles = []
	var text: String = FileAccess.get_file_as_string(CONSTS.WAVE_TRANSITION_JSON_PATH)
	if text.is_empty():
		_warn_json_once("WaveTransition: %s 缺失或为空 — 副句留空" % CONSTS.WAVE_TRANSITION_JSON_PATH)
		return
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_warn_json_once("WaveTransition: %s 解析失败 — 副句留空" % CONSTS.WAVE_TRANSITION_JSON_PATH)
		return
	var subs = parsed.get("wave_subtitles")
	if subs is Array:
		_subtitles = subs


func _warn_json_once(msg: String) -> void:
	if _json_warned:
		return
	_json_warned = true
	push_warning(msg)


# ── AC3: 演员冻结（Approach A，#296 惯例）──

## AC3: 演员冻结（Approach A，#296 惯例）。DESIGN §3.3: ../Ball + ../PlayerPaddle/../AIPaddle
## 节点路径（get_node_or_null + has_method 守卫；Main.tscn 三者为 Game 根平级兄弟）。
func _freeze(freeze: bool) -> void:
	if not is_inside_tree():
		return
	var ball = get_node_or_null("../Ball")
	if ball != null and ball.has_method("set_frozen"):
		ball.set_frozen(freeze)
	for pname in ["../PlayerPaddle", "../AIPaddle"]:
		var paddle = get_node_or_null(pname)
		if paddle != null and paddle.has_method("set_frozen"):
			paddle.set_frozen(freeze)
