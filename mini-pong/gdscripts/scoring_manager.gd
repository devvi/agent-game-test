extends Node
## ScoringManager — 场景侧事件消费（双得分制 #385）。
## 消费 ball.score(side) 与 BreakoutGrid.brick_destroyed(brick, pos)，
## 判定归属/分值/类型 → GameManager.add_score(winner, amount, kind)。
## 终局判定唯一权威在 GameManager（is_run_over() 守卫）；本节点只做事件路由。
##
## Signal chain:
##   Ball._process() → ball.score(side)
##     → ScoringManager._on_ball_score(side)
##       ├── ball._crossed_wall → add_score(winner, 3, "pierce")   (穿墙分 AC2)
##       └── 否则               → add_score(winner, 1, "boundary") (普通出界兜底)
##       → scored(winner)  ← 仅出界分触发 → FSM SCORED 暂停流；拆砖分不触发（边界 8）
##   BreakoutGrid.brick_destroyed(brick, pos)   [#384 未接线时容错跳过（失败路径 1）]
##     → ScoringManager._on_brick_destroyed
##       → ball.last_toucher 非空 → add_score(toucher, 1, "brick") (拆砖分 AC1)
## 同帧去重（AC4）: _brick_destroyed_this_frame 帧守卫 —— _process 帧首复位，
## _on_brick_destroyed 置位，_on_ball_score 检查（同帧只计拆砖分）。
##
## Design: docs/DESIGN/291-scoring-system.md §2.1 + docs/DESIGN/385-dual-scoring-system.md §2.3
## Parent Issue: #291, #385

# ── Configuration (via GameConstants #295 / Dual Scoring #385) ──
const CONSTS = preload("res://gdscripts/constants.gd")
const BRICK_SCORE: int = CONSTS.BRICK_SCORE
const PIERCE_SCORE: int = CONSTS.PIERCE_SCORE

# ── Signals ──
signal scored(winner: String)   # 仅出界分（普通/穿墙）触发 → FSM SCORED 暂停流；拆砖分不触发（比赛继续）

# ── Node References ──
@onready var ball: Area2D = $"../Ball"
@onready var score_flash: Node = get_node_or_null("../ScoreFlash")
@onready var breakout_grid: Node = get_node_or_null("../BreakoutGrid")   # #384 容错：#393 接线前为 null

# ── State ──
var _brick_destroyed_this_frame: bool = false   # 同帧去重帧守卫（AC4，Flow 5）


func _ready() -> void:
	if ball == null:
		push_error("ScoringManager: Ball node not found — scoring disabled")
		return
	ball.score.connect(_on_ball_score)
	if score_flash != null and score_flash.has_method("_on_score_changed"):
		scored.connect(score_flash._on_score_changed)
	# #384 容错连接：grid 不存在/信号未实现 → 跳过并警告一次，不崩（失败路径 1）
	if breakout_grid != null and breakout_grid.has_signal("brick_destroyed"):
		breakout_grid.brick_destroyed.connect(_on_brick_destroyed)
	else:
		push_warning("ScoringManager: BreakoutGrid 未接线（#393 前）— 拆砖分暂不可用")


func _process(_delta: float) -> void:
	# 帧首复位（AC4 帧守卫）：每帧开始时清掉上一帧的拆砖标记
	_brick_destroyed_this_frame = false


func _on_ball_score(side: int) -> void:
	if is_instance_valid(GameManager) and GameManager.is_run_over():
		return                       # 终局守卫（失败路径 2）
	# 同帧去重（AC4）：同帧砖碎 + 出界 → 只计拆砖分（该帧出界不计 3 分，边界 1）
	# 守卫消费即复位：本帧后续出界事件恢复正常计分（D-3 / 失败路径防护）
	if _brick_destroyed_this_frame:
		_brick_destroyed_this_frame = false
		return
	var winner: String = "ai" if side == 1 else "player"
	# 穿墙判定：ball 已穿越墙带 → 3 分（AC2）；否则普通出界 1 分兜底（无墙时期游戏不坏，边界 3）
	var crossed: bool = ball != null and bool(ball.get("_crossed_wall"))
	var amount: int = PIERCE_SCORE if crossed else 1
	var kind: String = "pierce" if crossed else "boundary"
	GameManager.add_score(winner, amount, kind)
	scored.emit(winner)              # 出界分走 SCORED → 重发球流（边界 8）


func _on_brick_destroyed(brick: Node2D, pos: Vector2) -> void:
	if is_instance_valid(GameManager) and GameManager.is_run_over():
		return
	if ball == null:
		return
	var toucher = ball.get("last_toucher")
	if toucher == null or toucher == "":
		return                       # 发球直撞砖：无归属，不计拆砖分（边界 2）；砖仍碎/反弹（#384 行为不变）
	_brick_destroyed_this_frame = true
	GameManager.add_score(toucher, BRICK_SCORE, "brick")
	# 不 emit scored —— 拆砖不触发 FSM SCORED，比赛继续（边界 8）
