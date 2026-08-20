extends Node
class_name ScreenShake
## ScreenShake — 屏震（#579，PRD 实验 2）。
## 归属: docs/DESIGN/579-combat-feedback-system.md §2.4
## 职责: Camera2D offset trauma² 衰减 —— 单调衰减、终值回 0、方向沿攻击向量（D1/D2 STRICT）。
## 设计要点:
##   - @export camera_path 解耦（战斗场景 #583 / E2E rig 注入；null/失效 → no-op + push_warning 一次）
##   - shake(max_offset_px, direction): trauma 取 max 不叠加（边界 1，不爆震）；per-shake 恒定噪声
##     （_noise_mag/_noise_sign 每次 shake 采样一次 → 确定性包络，非逐帧随机）
##   - _process: offset = direction × sign × mag × trauma² × max_offset；trauma 指数衰减 → 0
## 全部 # DRAFT 候补值（FEEDBACK_SHAKE_DECAY 等），定稿归 #584/用户。

const C = preload("res://gdscripts/constants.gd")

@export var camera_path: NodePath
var _trauma: float = 0.0
var _max_offset_px: float = 0.0
var _direction: Vector2 = Vector2.ZERO
var _noise_mag: float = 1.0
var _noise_sign: float = 1.0
var _warned: bool = false


func shake(max_offset_px: float, direction: Vector2) -> void:
	## 触发屏震: trauma 增量 0.6 叠加取 max（cap 1.0）；max offset 取 max 非求和。
	## 每次 shake 重采样恒定噪声（确定性包络，D1 单调衰减可断言）。
	_trauma = min(1.0, _trauma + 0.6)
	_max_offset_px = max(_max_offset_px, max_offset_px)
	if direction != Vector2.ZERO:
		_direction = direction
	_noise_mag = randf_range(0.6, 1.0)
	_noise_sign = 1.0 if randf() > 0.5 else -1.0


func _process(delta: float) -> void:
	## 每帧衰减: 相机缺失 → no-op（push_warning 一次，不崩）；trauma 极低 → offset 归零。
	var cam: Camera2D = _resolve_camera()
	if cam == null:
		if not _warned:
			push_warning("ScreenShake: no camera at path '%s'" % str(camera_path))
			_warned = true
		return
	if _trauma <= 0.01:
		cam.offset = Vector2.ZERO
		return
	cam.offset = _direction * _noise_sign * _noise_mag * (_trauma * _trauma) * _max_offset_px
	_trauma -= _trauma * C.FEEDBACK_SHAKE_DECAY * delta


func _resolve_camera() -> Camera2D:
	## camera_path 解析: 空路径 / 失效 / 非 Camera2D → null（no-op）
	if camera_path == null or camera_path.is_empty():
		return null
	var node: Node = get_node_or_null(camera_path)
	if node is Camera2D:
		return node as Camera2D
	return null
