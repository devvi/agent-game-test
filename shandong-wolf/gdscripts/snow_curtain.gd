extends Node2D
## SnowCurtain — 三层雪幕控制器（#582）。
## 硬约束红线: amount 只在 .tscn 静态声明（60/60/80），运行时禁改（rain_curtain 教训:
## Godot 改 amount 重启粒子系统→可见跳变）。
## 层级约定: CanvasLayer 3/4/5 = 雪幕远/中/近。

const C = preload("res://gdscripts/constants.gd")

@export var velocity_min: float = C.SNOW_VELOCITY_MIN
@export var velocity_max: float = C.SNOW_VELOCITY_MAX
@export var scale_far: float = C.SNOW_SCALE_FAR
@export var scale_near: float = C.SNOW_SCALE_NEAR
@export var alpha_min: float = C.SNOW_ALPHA_MIN
@export var alpha_max: float = C.SNOW_ALPHA_MAX
@export var wind: float = C.SNOW_WIND_DEFAULT

@onready var _far_parallax: Parallax2D = $LayerFar/Parallax
@onready var _far_particles: GPUParticles2D = $LayerFar/Parallax/Particles
@onready var _far_material: ParticleProcessMaterial = $LayerFar/Parallax/Particles.process_material as ParticleProcessMaterial
@onready var _mid_parallax: Parallax2D = $LayerMid/Parallax
@onready var _mid_particles: GPUParticles2D = $LayerMid/Parallax/Particles
@onready var _mid_material: ParticleProcessMaterial = $LayerMid/Parallax/Particles.process_material as ParticleProcessMaterial
@onready var _near_parallax: Parallax2D = $LayerNear/Parallax
@onready var _near_particles: GPUParticles2D = $LayerNear/Parallax/Particles
@onready var _near_material: ParticleProcessMaterial = $LayerNear/Parallax/Particles.process_material as ParticleProcessMaterial


func apply_tunables() -> void:
	_apply_layer(_far_parallax, _far_particles, _far_material, scale_far, alpha_min)
	_apply_layer(_mid_parallax, _mid_particles, _mid_material, 1.0, (alpha_min + alpha_max) * 0.5)
	_apply_layer(_near_parallax, _near_particles, _near_material, scale_near, alpha_max)


func set_wind(intensity: float) -> void:
	wind = intensity
	apply_tunables()


func _apply_layer(parallax: Parallax2D, particles: GPUParticles2D, material: ParticleProcessMaterial, scale: float, alpha: float) -> void:
	var drift_x: float = wind * parallax.scroll_scale.x
	material.direction = Vector3(drift_x, 1.0, 0.0).normalized()
	material.initial_velocity_min = velocity_min
	material.initial_velocity_max = velocity_max
	material.scale_min = scale
	material.scale_max = scale
	particles.modulate.a = alpha
