extends Object

var passed: int = 0
var failed: int = 0

func _approx(a: float, b: float, epsilon: float = 0.001) -> bool:
    return abs(a - b) < epsilon

func run() -> void:
    print("\n=== Text Component Library Tests ===\n")

    # TC-49-1: Normal path — tier→variant mapping
    _test_tier_low_maps_to_index_0()
    _test_tier_mid_maps_to_index_1()
    _test_tier_high_maps_to_index_2()
    _test_direct_variant_selection()

    # TC-49-2: Edge cases — boundary behavior
    _test_empty_variant_data_no_crash()
    _test_variant_index_clamped_out_of_bounds()
    _test_fragment_text_replaces_at_low_tier()

    # TC-49-3: Signal wiring
    _test_on_state_changed_updates_tier()
    _test_tone_override_affects_emissive()

    print("\n--- Text Component Library Results ---")
    print("Passed: ", passed)
    print("Failed: ", failed)

# ===== TC-49-1: Normal Path =====

func _create_component_with_variants() -> TextComponentBase:
    var comp: TextComponentBase = load("res://gdscripts/text_component_base.gd").new()

    var shallow: TextVariantData = TextVariantData.new()
    shallow.text = "shallow text"
    shallow.emissive_color = Color(1, 0, 0)
    shallow.emissive_strength = 1.0
    shallow.pixel_factor = 0.3
    shallow.color_bits = 8
    shallow.scanline_intensity = 0.1
    shallow.fragment_text = ""

    var middle: TextVariantData = TextVariantData.new()
    middle.text = "middle text"
    middle.emissive_color = Color(0, 1, 0)
    middle.emissive_strength = 2.0
    middle.pixel_factor = 0.5
    middle.color_bits = 6
    middle.scanline_intensity = 0.2
    middle.fragment_text = ""

    var deep: TextVariantData = TextVariantData.new()
    deep.text = "deep text"
    deep.emissive_color = Color(0, 0, 1)
    deep.emissive_strength = 3.0
    deep.pixel_factor = 0.7
    deep.color_bits = 4
    deep.scanline_intensity = 0.3
    deep.fragment_text = "fragment"

    comp.variant_data = [shallow, middle, deep]
    return comp

func _test_tier_low_maps_to_index_0() -> void:
    var comp := _create_component_with_variants()
    comp.set_state_tier("low")
    var expected: String = comp.variant_data[0].text
    _assert(comp.text == expected, "TC-49-1-1: set_state_tier('low') maps to variant index 0")

func _test_tier_mid_maps_to_index_1() -> void:
    var comp := _create_component_with_variants()
    comp.set_state_tier("mid")
    var expected: String = comp.variant_data[1].text
    _assert(comp.text == expected, "TC-49-1-2: set_state_tier('mid') maps to variant index 1")

func _test_tier_high_maps_to_index_2() -> void:
    var comp := _create_component_with_variants()
    comp.set_state_tier("high")
    var expected: String = comp.variant_data[2].text
    _assert(comp.text == expected, "TC-49-1-3: set_state_tier('high') maps to variant index 2")

func _test_direct_variant_selection() -> void:
    var comp := _create_component_with_variants()
    comp.set_text_variant(1)
    var expected: String = comp.variant_data[1].text
    _assert(comp.text == expected, "TC-49-1-4: set_text_variant(1) directly selects variant index 1")

# ===== TC-49-2: Edge Cases =====

func _test_empty_variant_data_no_crash() -> void:
    var comp: TextComponentBase = load("res://gdscripts/text_component_base.gd").new()
    comp.variant_data = []
    comp.set_state_tier("low")
    comp.set_state_tier("mid")
    comp.set_state_tier("high")
    comp.set_text_variant(0)
    _assert(true, "TC-49-2-1: Empty variant_data array does not crash")

func _test_variant_index_clamped_out_of_bounds() -> void:
    var comp := _create_component_with_variants()
    comp.set_text_variant(99)
    var expected: String = comp.variant_data[2].text
    _assert(comp.text == expected, "TC-49-2-2: set_text_variant(99) clamps to last index (2)")

func _test_fragment_text_replaces_at_low_tier() -> void:
    var comp := _create_component_with_variants()
    comp.set_state_tier("low")
    _assert(comp.text == "fragment", "TC-49-2-5: fragment_text replaces text at low tier when non-empty")

# ===== TC-49-3: Signal Wiring =====

func _test_on_state_changed_updates_tier() -> void:
    var comp := _create_component_with_variants()
    comp._on_state_changed({"hope": 2.0})
    _assert(comp.text == "fragment", "TC-49-3-1: _on_state_changed with hope=2 triggers low tier")

func _test_tone_override_affects_emissive() -> void:
    var comp := _create_component_with_variants()
    comp.set_state_tier("mid")
    var base_color: Color = comp.emissive_color
    var base_strength: float = comp.emissive_strength
    comp.set_tone("despair")
    _assert(comp.emissive_color == base_color and _approx(comp.emissive_strength, base_strength),
            "TC-49-3-3: tone override re-applies base variant emissive params")

# ===== Helpers =====

func _assert(condition: bool, name: String) -> void:
    if condition:
        passed += 1
        print("  ✅ ", name)
    else:
        failed += 1
        print("  ❌ ", name)
