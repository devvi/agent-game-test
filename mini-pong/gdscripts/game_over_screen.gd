extends CanvasLayer
## GameOverScreen — end-of-run screen with win/fail dual branches (#391).
## win branch (winner == "player"): "YOU WIN!" + pulse glow (preserved from #292).
## fail branch (winner == "ai"): failure phrase (tiered from wave_failure_text.json,
## mechanical consumption per #396) + player-side run stats (wave / bricks / pierces,
## all from GameManager query API). Restrained: no pulse animation on fail.
## Parent Issues: #292, #391

# ── Constants ──
const CONSTS = preload("res://gdscripts/constants.gd")
const COLOR_PLAYER: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const COLOR_AI: Color     = Color(1.0, 0.2, 0.33, 1.0)      # #ff3355
const TEXT_PLAYER_WIN: String = "YOU WIN!"
const TEXT_AI_WIN: String     = "AI WINS!"
const RUN_STATS_FORMAT: String = "波次 %d · 拆砖 %d · 穿墙 %d"   # #391 AC2：玩家单侧三项

# ── Exported ──
@export var winner_pulse_duration: float = 1.0   # Seconds for one pulse cycle
@export var prompt_blink_period: float = 0.8      # Seconds for one blink cycle

# ── Node References ──
@onready var winner_label: Label = $CenterContainer/VBoxContainer/WinnerLabel
@onready var restart_label: Label = $CenterContainer/VBoxContainer/RestartPromptLabel
# #391 新增引用：get_node_or_null 容错（#385 RunStatsLabel 容错模式延续，节点缺失静默跳过）
@onready var failure_phrase_label: Label = get_node_or_null("CenterContainer/VBoxContainer/FailurePhraseLabel") as Label
@onready var run_stats_label: Label = get_node_or_null("CenterContainer/VBoxContainer/RunStatsLabel") as Label

# ── State ──
var _winner_tween: Tween = null
var _prompt_tween: Tween = null
var _transitioning: bool = false
var _failure_json_warn_count: int = 0   # #391 warn-once：JSON 加载失败只警告一次


# ── Lifecycle ──
func _ready() -> void:
	# Guard: skip if nodes missing
	if not winner_label or not restart_label:
		return

	# Connect to GameManager.match_over signal
	if is_instance_valid(GameManager):
		if GameManager.has_signal("match_over"):
			GameManager.match_over.connect(_on_match_over)

	visible = false


# REMOVED: _input() — FSM (#294) handles SPACE in GAME_OVER state


# ── Signal Handlers ──
func _on_match_over(winner: String) -> void:
	"""Called when GameManager.match_over fires. win/fail dual-branch (#391)."""
	if not winner_label or not restart_label:
		return

	var is_fail := winner == "ai"
	winner_label.visible = not is_fail                          # fail 分支隐藏胜者宣告
	if failure_phrase_label:
		failure_phrase_label.visible = is_fail
	if run_stats_label:
		run_stats_label.visible = is_fail

	match winner:
		"player":
			winner_label.text = TEXT_PLAYER_WIN
			winner_label.modulate = COLOR_PLAYER
			if is_inside_tree() and get_tree():
				_start_winner_pulse()                           # win 分支保留 #292 脉冲
		"ai":
			if failure_phrase_label:
				if is_instance_valid(GameManager) and GameManager.has_method("get_wave_index"):
					failure_phrase_label.text = _select_failure_phrase(GameManager.get_wave_index())
			_render_run_stats()                                 # 玩家单侧三项（#391 替换 #385 P/A 双区）
			# 克制：fail 分支不启动脉冲（Issue 原文「保持克制、不堆特效」）
		_:
			return

	# Hide HUD
	var hud := _get_sibling("GameHUD")
	if hud:
		hud.visible = false

	# Show this screen
	visible = true
	_transitioning = false

	# Start prompt blink (headless-safe); both branches keep restart prompt
	if is_inside_tree() and get_tree():
		_start_prompt_blink()


# ── Run Stats (#391 AC2) ──

## 玩家单侧三项 run 数据：波次 / 拆砖 / 穿墙（数据单一来源 = GameManager 查询 API，无本地缓存）
func _render_run_stats() -> void:
	if not is_instance_valid(GameManager):
		return
	if not run_stats_label:
		return
	var stats: String = RUN_STATS_FORMAT % [
		GameManager.get_wave_index() if GameManager.has_method("get_wave_index") else GameManager.wave_index,
		GameManager.get_brick_count("player") if GameManager.has_method("get_brick_count") else 0,
		GameManager.get_pierce_count("player") if GameManager.has_method("get_pierce_count") else 0,
	]
	run_stats_label.text = stats


# ── Failure Phrase Selection (#391 AC3) ──

## 分档选句：wave_index <=2→fp1；<=5→fp2；>=6→fp3；else→fp4 兜底（PRD §8 契约）。
## 返回 String，永不返回空串；JSON 全链路失败 → FAILURE_TEXT_DEFAULT_PHRASE。
## path 可选参数便于测试注入缺失/损坏文件（默认 CONSTS.FAILURE_TEXT_PATH）。
func _select_failure_phrase(wave_index: int, path: String = CONSTS.FAILURE_TEXT_PATH) -> String:
	var phrases: Array = _load_failure_phrases(path)
	if phrases.is_empty():
		return CONSTS.FAILURE_TEXT_DEFAULT_PHRASE
	var tier: int = _pick_tier(wave_index)
	# 档内优先 recommended；按 id 后缀约定匹配（fp1/fp2/fp3=档1/2/3，fp4=兜底档，schema 契约）
	var candidates: Array = phrases.filter(func(p): return _phrase_tier(p) == tier)
	for p in candidates:
		if p.get("recommended", false):
			return String(p.get("text", CONSTS.FAILURE_TEXT_DEFAULT_PHRASE))
	if not candidates.is_empty():
		return String(candidates[0].get("text", CONSTS.FAILURE_TEXT_DEFAULT_PHRASE))
	return CONSTS.FAILURE_TEXT_DEFAULT_PHRASE


## JSON 只读消费（#395 先例）：FileAccess + JSON.parse_string + schema 检查 + warn-once。
## 空文件 / 解析失败 / schema != "wave-failure-text/v1" / failure_phrases 非数组
## → warn-once push_warning + 返回 []（调用方走默认句兜底）。
func _load_failure_phrases(path: String = CONSTS.FAILURE_TEXT_PATH) -> Array:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		_warn_failure_once("GameOverScreen: %s 缺失或为空 — 使用默认短句" % path)
		return []
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_warn_failure_once("GameOverScreen: %s JSON 解析失败 — 使用默认短句" % path)
		return []
	if String(parsed.get("schema", "")) != "wave-failure-text/v1":
		_warn_failure_once("GameOverScreen: %s schema 不符 — 使用默认短句" % path)
		return []
	var phrases = parsed.get("failure_phrases", [])
	if typeof(phrases) != TYPE_ARRAY or phrases.is_empty():
		_warn_failure_once("GameOverScreen: %s failure_phrases 缺失或为空 — 使用默认短句" % path)
		return []
	return phrases


## 档位判定：返回 0/1/2/3；异常（0、负数、非 int）→ 3 兜底
func _pick_tier(wave_index: int) -> int:
	if wave_index <= 0:
		return 3                     # 首波未开始即败 / 异常 → 兜底档（边界 1，PRD §5）
	if wave_index <= CONSTS.FAILURE_WAVE_TIER1_MAX:
		return 0
	if wave_index <= CONSTS.FAILURE_WAVE_TIER2_MAX:
		return 1
	if wave_index >= CONSTS.FAILURE_WAVE_TIER3_MIN:
		return 2
	return 3


## id → 档位（schema 契约：fp1/fp2/fp3 → 0/1/2；fp4 或未知 → 3）
func _phrase_tier(phrase: Dictionary) -> int:
	var pid := String(phrase.get("id", ""))
	match pid:
		"fp1":
			return 0
		"fp2":
			return 1
		"fp3":
			return 2
		_:
			return 3


func _warn_failure_once(msg: String) -> void:
	if _failure_json_warn_count > 0:
		return
	_failure_json_warn_count += 1
	push_warning(msg)


# ── Animation ──
func _start_winner_pulse() -> void:
	_kill_tween(_winner_tween)
	_winner_tween = create_tween()
	_winner_tween.set_loops()
	_winner_tween.tween_property(winner_label, "modulate:a", 0.4, winner_pulse_duration * 0.5)
	_winner_tween.tween_property(winner_label, "modulate:a", 1.0, winner_pulse_duration * 0.5)


func _start_prompt_blink() -> void:
	_kill_tween(_prompt_tween)
	_prompt_tween = create_tween()
	_prompt_tween.set_loops()
	_prompt_tween.tween_property(restart_label, "modulate:a", 0.0, prompt_blink_period * 0.5)
	_prompt_tween.tween_property(restart_label, "modulate:a", 1.0, prompt_blink_period * 0.5)


# ── Internal ──
func _on_restart_pressed() -> void:
	_transitioning = true
	_kill_tweens()
	visible = false

	# Return to start menu
	var menu := _get_sibling("StartMenu")
	if menu and menu.has_method("show_menu"):
		menu.show_menu()

	# Reset match state
	GameManager.reset_match()


func _get_sibling(node_name: String) -> CanvasLayer:
	var parent := get_parent()
	if not parent:
		return null
	return parent.get_node_or_null(node_name)


func _kill_tween(tween: Tween) -> void:
	if tween and is_instance_valid(tween):
		tween.kill()


func _kill_tweens() -> void:
	_kill_tween(_winner_tween)
	_kill_tween(_prompt_tween)
	_winner_tween = null
	_prompt_tween = null
