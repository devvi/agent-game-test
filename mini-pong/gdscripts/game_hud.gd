extends CanvasLayer
## GameHUD — 三区霓虹 HUD (#392)。
## 顶部 AI 红区（总分 + 拆砖/穿墙双子区）、中立信息条（「第 N 波 · 剩余 x」）、
## 底部玩家蓝区（总分 + 拆砖/穿墙双子区）。全部数字 Label 走 ui_neon_style 描边+微投影。
## 更新全部由信号驱动（AC5，零轮询）：GameManager score_changed / brick_scored /
## pierce_scored / wave_started + BreakoutGrid brick_destroyed / wall_cleared /
## wall_generated（#384 契约，容错消费：未接线显示「—」）。
## Design: docs/DESIGN/392-neon-ui-upgrade.md §4
## Parent Issue: #292, #392

const CONSTS = preload("res://gdscripts/constants.gd")
const NeonStyle = preload("res://gdscripts/ui_neon_style.gd")

# ── Node References ──
@onready var ai_score_label: Label = $TopZone/VBoxContainer/AIScoreLabel
@onready var ai_brick_label: Label = $TopZone/VBoxContainer/AISubRow/AIBrickLabel
@onready var ai_pierce_label: Label = $TopZone/VBoxContainer/AISubRow/AIPierceLabel
@onready var info_label: Label = $InfoBar
@onready var player_score_label: Label = $BottomZone/HBoxContainer/PlayerScoreLabel
@onready var player_brick_label: Label = $BottomZone/HBoxContainer/PlayerBrickLabel
@onready var player_pierce_label: Label = $BottomZone/HBoxContainer/PlayerPierceLabel

# GameManager 引用（autoload；测试可注入 mock，见 test_hud.gd）
var game_manager

var _warned: bool = false   # grid 缺失只 push_warning 一次（防刷屏）


# ── Lifecycle ──
func _ready() -> void:
	game_manager = _resolve_game_manager()
	if game_manager == null:
		push_warning("HUD: GameManager 未找到，跳过样式/接线/播种")
		return
	_apply_neon()
	_connect_signals()
	_seed_initial_values()
	visible = false  # Hidden until StartMenu triggers show


# ── Internal ──

func _resolve_game_manager():
	if game_manager != null:
		return game_manager
	if is_instance_valid(GameManager):   # autoload（lazy `*` 前缀：标识符访问即实例化）
		game_manager = GameManager
	return game_manager


func _wave_index() -> int:
	var gm = game_manager
	if gm == null:
		return 0
	var w = gm.get("wave_index")
	return int(w) if w != null else 0


## 全部 Label 套霓虹样式（单一事实源 ui_neon_style.gd）
func _apply_neon() -> void:
	NeonStyle.apply(ai_score_label, CONSTS.AI_NEON_RED)
	NeonStyle.apply(ai_brick_label, CONSTS.AI_NEON_RED)
	NeonStyle.apply(ai_pierce_label, CONSTS.AI_NEON_RED)
	NeonStyle.apply(info_label, CONSTS.HUD_INFO_COLOR)
	NeonStyle.apply(player_score_label, CONSTS.PLAYER_NEON_BLUE)
	NeonStyle.apply(player_brick_label, CONSTS.PLAYER_NEON_BLUE)
	NeonStyle.apply(player_pierce_label, CONSTS.PLAYER_NEON_BLUE)


## 信号接线：GameManager 4 信号 + BreakoutGrid 3 信号（has_signal 守卫，容错）
func _connect_signals() -> void:
	var gm = game_manager
	if gm != null:
		if gm.has_signal("score_changed"):
			gm.score_changed.connect(_on_score_changed)
		if gm.has_signal("brick_scored"):
			gm.brick_scored.connect(_on_brick_scored)
		if gm.has_signal("pierce_scored"):
			gm.pierce_scored.connect(_on_pierce_scored)
		if gm.has_signal("wave_started"):
			gm.wave_started.connect(_on_wave_started)
	var grid = get_node_or_null("../BreakoutGrid")
	if grid != null:
		if grid.has_signal("brick_destroyed"):
			grid.brick_destroyed.connect(_on_grid_brick_destroyed)
		if grid.has_signal("wall_cleared"):
			grid.wall_cleared.connect(_on_grid_wall_cleared)
		if grid.has_signal("wall_generated"):
			grid.wall_generated.connect(_on_grid_wall_generated)


## 初始播种（#292 惯例）：总分/双区计数/波次/剩余砖数从 GameManager 读
func _seed_initial_values() -> void:
	var gm = game_manager
	if gm == null:
		return
	var p = gm.get("player_score")
	var a = gm.get("ai_score")
	_on_score_changed(int(p) if p != null else 0, int(a) if a != null else 0)
	if gm.has_method("get_brick_count"):
		if player_brick_label:
			player_brick_label.text = "拆 " + str(gm.get_brick_count("player"))
		if ai_brick_label:
			ai_brick_label.text = "拆 " + str(gm.get_brick_count("ai"))
	if gm.has_method("get_pierce_count"):
		if player_pierce_label:
			player_pierce_label.text = "穿 " + str(gm.get_pierce_count("player"))
		if ai_pierce_label:
			ai_pierce_label.text = "穿 " + str(gm.get_pierce_count("ai"))
	_refresh_info_bar(_wave_index())
	_refresh_remaining()


# ── Signal Handlers (GameManager) ──

func _on_score_changed(player_score: int, ai_score: int) -> void:
	if ai_score_label:
		ai_score_label.text = "AI: " + str(ai_score)
	if player_score_label:
		player_score_label.text = "Player: " + str(player_score)


func _on_brick_scored(side: String) -> void:
	var gm = game_manager
	if gm == null or not gm.has_method("get_brick_count"):
		return
	if side == "player":
		if player_brick_label:
			player_brick_label.text = "拆 " + str(gm.get_brick_count("player"))
	else:
		if ai_brick_label:
			ai_brick_label.text = "拆 " + str(gm.get_brick_count("ai"))


func _on_pierce_scored(side: String) -> void:
	var gm = game_manager
	if gm == null or not gm.has_method("get_pierce_count"):
		return
	if side == "player":
		if player_pierce_label:
			player_pierce_label.text = "穿 " + str(gm.get_pierce_count("player"))
	else:
		if ai_pierce_label:
			ai_pierce_label.text = "穿 " + str(gm.get_pierce_count("ai"))


func _on_wave_started(index: int) -> void:
	_refresh_info_bar(index)
	# wave_started 先于 generate_wave 同帧发出 → 禁止同步读剩余数；
	# call_deferred 帧末读（回退路径；wall_generated 为首选路径）
	_refresh_remaining.call_deferred()


# ── Signal Handlers (BreakoutGrid 契约，容错) ──

func _on_grid_brick_destroyed(_brick, _pos) -> void:
	_refresh_remaining()   # 即时单读 grid.remaining_bricks


func _on_grid_wall_cleared() -> void:
	if info_label:
		info_label.text = "第 %d 波 · 剩余 0" % _wave_index()


func _on_grid_wall_generated(remaining: int) -> void:
	if info_label:
		info_label.text = "第 %d 波 · 剩余 %d" % [_wave_index(), remaining]


# ── Info Bar ──

func _refresh_info_bar(index: int) -> void:
	if info_label:
		info_label.text = "第 %d 波 · 剩余 —" % index


func _refresh_remaining() -> void:
	var grid = get_node_or_null("../BreakoutGrid")
	if grid == null or not grid.has_method("get") or not ("remaining_bricks" in grid):
		_warn_once()
		if info_label:
			info_label.text = "第 %d 波 · 剩余 —" % _wave_index()
		return
	if info_label:
		info_label.text = "第 %d 波 · 剩余 %d" % [_wave_index(), grid.remaining_bricks]


func _warn_once() -> void:
	if _warned:
		return
	_warned = true
	push_warning("HUD: BreakoutGrid 未接线 (#384/#393)，剩余砖数显示占位符")
