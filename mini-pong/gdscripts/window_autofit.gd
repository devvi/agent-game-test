extends Node
## WindowAutofit — #544: 启动时按主屏可用区域等比缩放窗口并居中。
## 纯显示层：不改逻辑分辨率 720×1280（constants.gd + 全部测试钉死，#383 地基）。
## 设计: docs/DESIGN/544-window-display-autofit.md

const CONSTS = preload("res://gdscripts/constants.gd")
const LOGICAL_SIZE: Vector2i = Vector2i(CONSTS.SCREEN_WIDTH, CONSTS.SCREEN_HEIGHT)  # 720×1280

## headless/CI 守卫：无真实显示服务时静默跳过（E2E --resolution 720x1280 不受影响）。
## 双保险 1 — 显式 headless 名检查（PRD §8 风险 2 + §5.2 边界 5）。
static func _should_skip() -> bool:
	return DisplayServer.get_name() == "headless"

## 纯函数（可单测）：以可用高度为基准、保持 720:1280 等比计算窗口物理尺寸。
## 目标高 = min(可用高, 1280)（v1 上限，见 §2 gap 1）；目标宽 = floori(高 × 720/1280)。
## 1080p → (607,1080)；768 → (432,768)；1440 → (810,1440)；2160 → (1215,2160)。
## 双保险 2 — 无效矩形 (≤0) 回退默认 720×1280（PRD §5.3 失败路径 2）。
static func compute_window_size(screen_rect: Rect2i) -> Vector2i:
	if screen_rect.size.x <= 0 or screen_rect.size.y <= 0:
		return LOGICAL_SIZE
	var target_h: int = mini(screen_rect.size.y, CONSTS.SCREEN_HEIGHT)
	var target_w: int = floori(target_h * CONSTS.SCREEN_WIDTH / float(CONSTS.SCREEN_HEIGHT))
	return Vector2i(target_w, target_h)

## 纯函数（可单测）：窗口几何中心对齐可用区域中心（整除向下取整，亚像素误差不可见）。
static func compute_centered_position(usable: Rect2i, win: Vector2i) -> Vector2i:
	var x: int = usable.position.x + floori((usable.size.x - win.x) / 2.0)
	var y: int = usable.position.y + floori((usable.size.y - win.y) / 2.0)
	return Vector2i(x, y)

func _ready() -> void:
	if _should_skip():
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(0)   # 主屏（screen 0）可用区域，排除菜单栏/Dock/任务栏
	if usable.size.x <= 0 or usable.size.y <= 0:
		push_warning("WindowAutofit: 无有效屏幕可用区域 (%s)，回退默认窗口 720×1280" % usable)
		return
	var win: Vector2i = compute_window_size(usable)
	DisplayServer.window_set_size(win)
	DisplayServer.window_set_position(compute_centered_position(usable, win))
