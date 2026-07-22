extends Object

var passed: int = 0
var failed: int = 0

# Helper to compare floats with tolerance
func _approx(a: float, b: float, epsilon: float = 0.001) -> bool:
    return abs(a - b) < epsilon

func run() -> void:
    print("\n=== LoFiText3D Tests ===\n")

    # TC-44-1: Normal path — parameter get/set cycle
    _test_pixel_factor_set_get()
    _test_color_bits_set_get()
    _test_scanline_intensity_set_get()
    _test_emissive_color_set_get()
    _test_emissive_strength_set_get()

    # TC-44-2: Edge cases — clamping at boundaries
    _test_pixel_factor_clamp_below()
    _test_pixel_factor_clamp_above()
    _test_color_bits_clamp_below()
    _test_color_bits_clamp_above()
    _test_scanline_intensity_maximum()
    _test_emissive_strength_clamp_above()

    # TC-44-3: ShaderMaterial creation and parameter sync
    _test_material_auto_created()
    _test_pixel_size_zero()
    _test_shader_param_sync()

    # TC-44-4: Failure path — edge cases with invalid/empty values
    _test_default_emissive_no_glow()
    _test_long_text()
    _test_empty_text()

    print("\n--- LoFiText3D Results ---")
    print("Passed: ", passed)
    print("Failed: ", failed)

# ===== TC-44-1: Normal Path =====

func _test_pixel_factor_set_get() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.pixel_factor = 0.7
    _assert(_approx(node.pixel_factor, 0.7), "TC-44-1-1: pixel_factor set to 0.7")

func _test_color_bits_set_get() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.color_bits = 12
    _assert(node.color_bits == 12, "TC-44-1-2: color_bits set to 12")

func _test_scanline_intensity_set_get() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.scanline_intensity = 0.5
    _assert(_approx(node.scanline_intensity, 0.5), "TC-44-1-3: scanline_intensity set to 0.5")

func _test_emissive_color_set_get() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.emissive_color = Color(1.0, 0.76, 0.03)
    _assert(node.emissive_color == Color(1.0, 0.76, 0.03), "TC-44-1-4: emissive_color set to amber")

func _test_emissive_strength_set_get() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.emissive_strength = 2.5
    _assert(_approx(node.emissive_strength, 2.5), "TC-44-1-5: emissive_strength set to 2.5")

# ===== TC-44-2: Edge Cases — Clamping =====

func _test_pixel_factor_clamp_below() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.pixel_factor = -0.5
    _assert(_approx(node.pixel_factor, 0.0), "TC-44-2-1: pixel_factor -0.5 clamped to 0.0")

func _test_pixel_factor_clamp_above() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.pixel_factor = 2.0
    _assert(_approx(node.pixel_factor, 1.0), "TC-44-2-2: pixel_factor 2.0 clamped to 1.0")

func _test_color_bits_clamp_below() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.color_bits = 0
    _assert(node.color_bits == 2, "TC-44-2-3: color_bits 0 clamped to 2")

func _test_color_bits_clamp_above() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.color_bits = 32
    _assert(node.color_bits == 24, "TC-44-2-4: color_bits 32 clamped to 24")

func _test_scanline_intensity_maximum() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.scanline_intensity = 1.0
    _assert(_approx(node.scanline_intensity, 1.0), "TC-44-2-5: scanline_intensity 1.0 == 1.0")

func _test_emissive_strength_clamp_above() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.emissive_strength = 10.0
    _assert(_approx(node.emissive_strength, 5.0), "TC-44-2-6: emissive_strength 10.0 clamped to 5.0")

# ===== TC-44-3: ShaderMaterial =====

func _test_material_auto_created() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node._ready()
    _assert(node.material_override is ShaderMaterial, "TC-44-3-1: material_override is ShaderMaterial after _ready")

func _test_pixel_size_zero() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node._ready()
    _assert(_approx(node.pixel_size, 0.0), "TC-44-3-2: pixel_size forced to 0.0 after _ready")

func _test_shader_param_sync() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node._ready()
    node.pixel_factor = 0.9
    var shader_param = node.material_override.get_shader_parameter("pixel_factor")
    _assert(shader_param != null and _approx(shader_param, 0.9), "TC-44-3-3: shader param pixel_factor == 0.9")

# ===== TC-44-4: Failure Path =====

func _test_default_emissive_no_glow() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    _assert(_approx(node.emissive_strength, 0.0), "TC-44-4-1: default emissive_strength is 0.0")

func _test_long_text() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    var long_text = ""
    for i in range(200):
        long_text += "e"
    node.text = long_text
    _assert(len(node.text) == 200, "TC-44-4-2: 200-char text accepted")

func _test_empty_text() -> void:
    var node = load("res://gdscripts/lo_fi_text_3d.gd").new()
    node.text = ""
    _assert(node.text == "", "TC-44-4-3: empty text accepted")

# ===== Helpers =====

func _assert(condition: bool, name: String) -> void:
    if condition:
        passed += 1
        print("  ✅ ", name)
    else:
        failed += 1
        print("  ❌ ", name)
