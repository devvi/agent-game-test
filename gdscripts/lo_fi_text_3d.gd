extends Label3D
class_name LoFiText3D

# --- Exported Parameters ---

# Pixelation intensity: 0.0 = no pixelation, 1.0 = max pixelation
@export var pixel_factor: float = 0.5:
    set(value):
        pixel_factor = clampf(value, 0.0, 1.0)
        _update_shader()

# Color depth: 2–24 bits per channel (24 = full color, 2 = extreme lo-fi)
@export var color_bits: int = 8:
    set(value):
        color_bits = clampi(value, 2, 24)
        _update_shader()

# Scanline overlay intensity: 0.0 = none, 1.0 = full CRT scanlines
@export var scanline_intensity: float = 0.15:
    set(value):
        scanline_intensity = clampf(value, 0.0, 1.0)
        _update_shader()

# Emissive tint color (for neon glow effect)
@export var emissive_color: Color = Color(0, 0, 0, 0):
    set(value):
        emissive_color = value
        _update_shader()

# Emissive strength multiplier: 0.0 = none, 5.0 = max bloom
@export var emissive_strength: float = 0.0:
    set(value):
        emissive_strength = clampf(value, 0.0, 5.0)
        _update_shader()

# --- Internal ---

var _lo_fi_material: ShaderMaterial
var _shader_loaded: bool = false


func _ready() -> void:
    _setup_material()
    _update_shader()
    # Disable Label3D's built-in pixel_size to avoid compounding with shader pixelation
    pixel_size = 0.0


func _setup_material() -> void:
    var shader: Shader = preload("res://shaders/lo_fi_text.gdshader")
    _lo_fi_material = ShaderMaterial.new()
    _lo_fi_material.shader = shader
    material_override = _lo_fi_material
    _shader_loaded = true


func _update_shader() -> void:
    if not _shader_loaded:
        return
    _lo_fi_material.set_shader_parameter("pixel_factor", pixel_factor)
    _lo_fi_material.set_shader_parameter("color_bits", float(color_bits))
    _lo_fi_material.set_shader_parameter("scanline_intensity", scanline_intensity)
    _lo_fi_material.set_shader_parameter("emissive_color", emissive_color)
    _lo_fi_material.set_shader_parameter("emissive_strength", emissive_strength)
