extends Node
## L2 反馈统一控制器 (#527, PRD 4.3-A+C) — 消费既有信号，统一 Tween 动效（150–300ms）。
## 首期：破砖闪光 + 穿墙脉冲；得分弹出/挡板 squash 留接口（Spike 4 后追加）。
## 颜色纪律：全部避开 #4a90d9（tol 32，E2E theme 保护）；MENU 态无事件源自然静默。
## 普通节点（非 CanvasLayer）：树序靠后 → 默认 layer 0 绘制于世界之上、HUD(layer=1) 之下；
## 不入 game_world 组（MENU 无事件源自然不触发，且不扩张 test_world_visibility E1 组断言面）。
## Design: docs/DESIGN/527-visual-enrichment.md §3.3

const CONSTS = preload("res://gdscripts/constants.gd")

@onready var pierce_rect: ColorRect = $PiercePulseRect
@onready var flash_pool: Node2D = $BrickFlashPool

var _flash_cursor: int = 0
var _pierce_this_frame: bool = false
var _flash_pool: Array = []

func _ready() -> void:
	_build_flash_pool()
	var tree = get_tree() if is_inside_tree() else null
	if tree == null:
		return
	# 事件源 1：破砖（grid 组寻址，未挂载 no-op —— 容错先例同 #384/#388）
	var grid = tree.get_first_node_in_group("breakout_grids")
	if grid != null and grid.has_signal("brick_destroyed"):
		grid.brick_destroyed.connect(_on_brick_destroyed)
	# 事件源 2：穿墙（autoload，无 autoload 环境静默跳过 —— 同 #450 null-safe 先例）
	if is_instance_valid(GameManager) and GameManager.has_signal("pierce_scored"):
		GameManager.pierce_scored.connect(_on_pierce)

func _process(_delta: float) -> void:
	_pierce_this_frame = false        # 帧守卫复位（同 scoring_manager AC4 模式）

func _build_flash_pool() -> void:
	_flash_pool.clear()
	for i in range(CONSTS.FX_FLASH_POOL_SIZE):
		var rect = ColorRect.new()
		rect.name = "FlashRect%02d" % i
		rect.size = CONSTS.BRICK_SIZE
		rect.color = CONSTS.FX_BRICK_FLASH_COLOR
		rect.modulate.a = 0.0
		rect.visible = false
		_flash_pool.append(rect)
		flash_pool.add_child(rect)

func _on_brick_destroyed(brick: Node2D, pos: Vector2) -> void:
	if _pierce_this_frame:
		return                       # 同帧仲裁：脉冲优先（PRD §5.2-8）
	if is_instance_valid(GameManager) and GameManager.is_run_over():
		return                       # 终局守卫（同 scoring_manager 失败路径 2）
	var rect = _flash_pool[_flash_cursor]
	_flash_cursor = (_flash_cursor + 1) % _flash_pool.size()
	rect.global_position = pos
	rect.scale = Vector2(1.3, 1.3)
	rect.modulate.a = 1.0
	rect.show()
	var tw = create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, CONSTS.FX_BRICK_FLASH_DURATION)
	tw.tween_callback(func(): rect.hide())

func _on_pierce(side: String) -> void:
	_pierce_this_frame = true
	if is_instance_valid(GameManager) and GameManager.is_run_over():
		return
	pierce_rect.color = CONSTS.FX_PIERCE_COLOR        # 暖橙系，非 4a90d9
	pierce_rect.modulate.a = CONSTS.FX_PIERCE_PEAK_ALPHA
	pierce_rect.show()
	var tw = create_tween()
	tw.tween_property(pierce_rect, "modulate:a", 0.0, CONSTS.FX_PIERCE_DURATION)
	tw.tween_callback(func(): pierce_rect.hide())

# —— 预留接口（首期不接线；Spike 4 验证后追加）——
func _on_score_changed(_player: int, _ai: int) -> void:
	pass
