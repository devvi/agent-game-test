extends ColorRect
## L0 暗角控制器 (#527, PRD 4.2-A)。全屏 ColorRect（透明底色），
## CanvasItem shader 径向暗化边缘：峰值暗度 VIGNETTE_MAX_STRENGTH ≤ 0.10（AC2 硬约束，
## 非黑断言安全——基底 #0a0a12 透出 90% 不变）。参数由常量单一事实源注入，
## human-review 调参零代码改动（taste-draft）。随 AtmosphereLayer 在 MENU 态结构性隐藏。
## Design: docs/DESIGN/527-visual-enrichment.md §3.2

const CONSTS = preload("res://gdscripts/constants.gd")

func _ready() -> void:
	if material != null and material is ShaderMaterial:
		material.set_shader_parameter("strength", CONSTS.VIGNETTE_MAX_STRENGTH)
		material.set_shader_parameter("inner_radius", CONSTS.VIGNETTE_INNER_RADIUS)
		material.set_shader_parameter("softness", CONSTS.VIGNETTE_SOFTNESS)
