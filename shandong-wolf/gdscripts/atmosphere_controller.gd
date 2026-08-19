extends Node2D
## AtmosphereController — 氛围编排统一入口（#582）。
## 层级约定: CanvasLayer layer 1=UI（不动）/ 2=水墨 / 3-5=雪幕（远/中/近）/
## 10=血色 vignette（#583 复用同一 .tscn 照此约定）。

const C = preload("res://gdscripts/constants.gd")

@export var moonlight_color: Color = C.MOONLIGHT_COLOR_APPLIED
@export var ink_edge_alpha: float = C.INK_EDGE_ALPHA_MAX
@export var ink_color: Color = C.INK_COLOR
@export var blood_alpha_max: float = C.BLOOD_VIGNETTE_ALPHA_MAX
@export var blood_fade_seconds: float = C.BLOOD_VIGNETTE_FADE_SECONDS

@onready var _moonlight: CanvasModulate = $Moonlight
@onready var _ink_rect: ColorRect = $InkWashLayer/InkWash
@onready var _blood = $BloodVignette
@onready var _snow = $SnowCurtain


func _ready() -> void:
	_apply_moonlight()
	var mat: Material = _ink_rect.material
	if mat is ShaderMaterial:
		var sm: ShaderMaterial = mat as ShaderMaterial
		sm.set_shader_parameter("edge_alpha", ink_edge_alpha)
		sm.set_shader_parameter("ink_color", ink_color)
	_snow.apply_tunables()


## 冷月光修复（self-correct #613, review D 类缺陷）: CanvasModulate 只调制其所在
## canvas layer。原实现 Moonlight 挂在 Atmosphere 根（layer 0），而全部可见内容位于
## CanvasLayer 1 (UI) / 2 (水墨) / 3-5 (雪幕) / 10 (血色) → 无任何可见色调。
## 现在每个可见 CanvasLayer 下都有同名 Moonlight CanvasModulate（tscn 静态声明，
## Main.tscn 的 UI 层由 Main 场景自带一份），此处统一设色保持单一控制点。
func _apply_moonlight() -> void:
	_moonlight.color = moonlight_color
	for child in find_children("Moonlight", "CanvasModulate", true, false):
		var cm: CanvasModulate = child as CanvasModulate
		if cm != null:
			cm.color = moonlight_color


func set_low_health(enabled: bool) -> void:
	_blood.set_enabled(enabled)


func debug_trigger_low_health() -> void:
	set_low_health(true)


func debug_clear_low_health() -> void:
	set_low_health(false)
