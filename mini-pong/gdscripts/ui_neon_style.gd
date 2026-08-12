extends RefCounted
## NeonStyle — 霓虹 Label 样式单一事实源 (#392)。
## 默认字体 + Label 主题覆盖（font_outline_color/outline_size 描边 +
## font_shadow_color/shadow_offset 微投影），headless 安全。
## 供 #388/#390/#391 复用（视觉一致性）；纯静态函数无状态。
## Design: docs/DESIGN/392-neon-ui-upgrade.md §4.2
## Parent Issue: #392

class_name NeonStyle

const CONSTS = preload("res://gdscripts/constants.gd")


## 应用霓虹样式到 Label（默认字体 + 主题覆盖；headless 安全）
static func apply(label: Label, color: Color, opts: Dictionary = {}) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color",
		opts.get("outline_color", color))                          # 描边色默认 = 本体色（霓虹感）
	label.add_theme_constant_override("outline_size",
		opts.get("outline_size", CONSTS.HUD_OUTLINE_SIZE))         # 默认 6（taste-draft 可调 4–6）
	label.add_theme_color_override("font_shadow_color",
		opts.get("shadow_color", CONSTS.HUD_SHADOW_COLOR))
	label.add_theme_constant_override("shadow_offset_x",
		opts.get("shadow_offset_x", CONSTS.HUD_SHADOW_OFFSET_X))   # 默认 2
	label.add_theme_constant_override("shadow_offset_y",
		opts.get("shadow_offset_y", CONSTS.HUD_SHADOW_OFFSET_Y))   # 默认 2
