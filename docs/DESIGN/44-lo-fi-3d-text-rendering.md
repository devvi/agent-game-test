# Design: #44 — Lo-Fi 3D Text Rendering

> Parent Issue: #44
> Agent: plan-agent
> Date: 2026-07-22

---

## 1. Architecture Overview

### Core Idea

Provide a lo-fi 3D text rendering system that places text anywhere in the 3D world with a characteristically lo-fi aesthetic: pixelated edges, reduced color depth (limited palette), subtle CRT/scanline artifacts, and optional emissive glow/neon. The system uses Godot 4.7's native **Label3D** node as the base and applies lo-fi effects via a custom **ShaderMaterial** fragment shader.

Three rendering modes are supported:
1. **Billboard Mode** — text always faces the camera (neon signs, location markers)
2. **Flat Sign Mode** — text rendered on a fixed plane (wall placards, storefront signs)
3. **Emissive Neon Mode** — billboard text with emissive glow pass (neon bar signs)

Wall decals (graffiti) are deferred to a future implementation using Approach B (Viewport → Decal) from the PRD.

### Data Flow

```
Godot 4.7 3D World
    │
    ├── WorldEnvironment (Glow enabled — for neon emission)
    │
    ├── Camera3D (main scene camera)
    │
    └── LoFiText3D (extends Label3D)
            │
            ├── [text] → string content
            ├── [font] → PixelFont resource (res://assets/fonts/pixel_font.tres)
            ├── [pixel_factor] → float 0.0–1.0 (pixelation intensity)
            ├── [color_bits] → int 2–24 (color quantization)
            ├── [scanline_intensity] → float 0.0–1.0
            ├── [emissive_color] → Color
            └── [emissive_strength] → float 0.0–5.0
                    │
                    └── ShaderMaterial (shaders/lo_fi_text.gdshader)
                            ├── pixelation (UV quantization)
                            ├── color quantization (per-channel bit reduction)
                            ├── scanline overlay (alpha-masked to text only)
                            └── emissive glow (optional, requires WorldEnvironment)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base node | Label3D (Godot 4.7 native) | Mature, handles billboarding, font layout, line breaks natively. Minimal GDScript — material assignment + text setting is ~5 lines |
| Lo-fi effects | Fragment shader in ShaderMaterial | Decouples aesthetic from text engine; parameters are exportable for per-instance tuning |
| Billboarding | Label3D.billboard = true | Native property — zero custom code |
| Font | Pixel-art bitmap font (FontFile .fnt) | Low-resolution source text avoids needing aggressive shader pixelation for the lo-fi look |
| Neon glow | WorldEnvironment Glow pass + emissive_color | Godot native post-processing; no custom bloom shader needed |
| Label3D pixel_size | 0.0 (disabled) | Shader pixelation takes over; compounded pixelation would look broken |
| Wall decals | Deferred (future Viewport + Decal approach) | 80% use cases covered by Approach A; decals add complexity without immediate need |

---

## 2. Node / Scene Tree Layer

### New Scene: `scenes/test_3d_text.tscn`

A test scene for verifying 3D text rendering in all three modes.

- **Root:** `Node3D` (spatial root)
- **Children:**
  - `Camera3D` — positioned at (0, 2, 5), looking at origin
  - `WorldEnvironment` — with `Environment` resource:
    - Background: `clear_color`, dark gray (#1a1a2e)
    - Glow: enabled, `glow_levels/01` = 0.5, `glow_intensity` = 1.0
  - `DirectionalLight3D` — dim ambient light for visibility
  - `BillboardSign` (Label3D) — `text="BAR"`, billboard=true, pixel_factor=0.6, color_bits=6, emissive
  - `FlatSign` (Label3D) — `text="ELM ST."`, billboard=false, rotation to face camera, pixel_factor=0.4, color_bits=4
  - `NeonTitle` (Label3D) — `text="DAY 17"`, billboard=true, strong emissive, scanline_intensity=0.3

### Existing Scene Modifications: `scenes/main.tscn`

- No changes required in this phase. The test scene exists independently. Future integration into `main.tscn` will add 3D nodes when the 3D world is built.

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/lo_fi_text_3d.gd`

**Extends:** `Label3D`

**Purpose:** Controls lo-fi text rendering with exported parameters that map to shader uniforms. Auto-creates and assigns the ShaderMaterial.

```gdscript
extends Label3D

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
```

### Usage Example

```gdscript
# In any scene script:
var sign := LoFiText3D.new()
sign.text = "BAR"
sign.pixel_factor = 0.6
sign.color_bits = 6
sign.emissive_color = Color.AMBER
sign.emissive_strength = 2.0
sign.billboard = true
add_child(sign)
sign.position = Vector3(0, 2, -3)
```

---

## 4. Resource / Config Layer

### New Font Resource: `assets/fonts/pixel_font.tres`

- **Type:** `FontFile` referencing a bitmap font atlas
- **Format:** `.fnt` (AngelCode BMFont format) with `.png` texture atlas
- **Character set:** ASCII printable (32–126) + selected UTF-8 (ä, ö, ü, é, è, ê for signage)
- **Glyph size:** 8×8 pixels (pixel-art style)
- **Creation method:** Generated via `bmGlyph` or a Python script using Pillow to render each glyph at 8×8

### New Shader Resource: `shaders/lo_fi_text.gdshader`

- **Type:** `Shader` (GLES3 / forward_plus compatible)
- **Path:** `res://shaders/lo_fi_text.gdshader` (detailed in §5 Asset/Visual Layer)
- **Uniforms:** `pixel_factor`, `color_bits`, `scanline_intensity`, `emissive_color`, `emissive_strength`

### Project Configuration: `project.godot`

No changes required in this phase. The shader and script are self-contained (no new Autoloads, no new input actions).

---

## 5. Asset / Visual Layer

### New Shader: `shaders/lo_fi_text.gdshader`

```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// --- Uniforms ---
uniform float pixel_factor : hint_range(0.0, 1.0) = 0.5;
uniform float color_bits : hint_range(2.0, 24.0) = 8.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform vec4 emissive_color : source_color = vec4(0.0);
uniform float emissive_strength : hint_range(0.0, 5.0) = 0.0;

// --- Fragment Shader ---
void fragment() {
    // 1. Sample the font atlas texture
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 2. Pixelation: quantize UV coordinates
    vec2 uv_pixel = UV;
    if (pixel_factor > 0.001) {
        float steps = mix(256.0, 16.0, pixel_factor);
        uv_pixel = floor(UV * steps) / steps;
        tex_color = texture(TEXTURE, uv_pixel);
    }
    
    // 3. Color quantization: reduce per-channel bit depth
    if (color_bits < 23.9) {
        float levels = pow(2.0, color_bits);
        tex_color.rgb = floor(tex_color.rgb * levels) / levels;
    }
    
    // 4. Scanline overlay (only on visible text pixels, not transparent areas)
    if (scanline_intensity > 0.001 && tex_color.a > 0.01) {
        float scanline = sin(UV.y * 480.0 * 3.14159) * 0.5 + 0.5;
        scanline = mix(1.0, scanline, scanline_intensity);
        tex_color.rgb *= scanline;
    }
    
    // 5. Emissive glow (additive blend for neon effect)
    if (emissive_strength > 0.001 && length(emissive_color.rgb) > 0.001) {
        vec3 emissive = emissive_color.rgb * emissive_strength * tex_color.a;
        tex_color.rgb += emissive;
        // Note: true glow/bloom requires WorldEnvironment Glow pass in scene
    }
    
    ALBEDO = tex_color.rgb;
    ALPHA = tex_color.a;
}
```

### Pixel Font Generation

A Python script (`scripts/generate_pixel_font.py`) generates the `.fnt` bitmap font:

- Renders each ASCII glyph (32–126) at 8×8 pixels using a monospace bitmap style
- Outputs: `assets/fonts/pixel_font.fnt` + `assets/fonts/pixel_font_0.png`
- Optionally generates a `.tres` FontFile resource for direct Godot import
- Uses Pillow (`pip install Pillow`) for rendering

### Script: `scripts/generate_pixel_font.py`

```python
#!/usr/bin/env python3
"""Generate a pixel-art bitmap font (.fnt + .png) for Godot 4.7."""

import argparse
from PIL import Image, ImageDraw, ImageFont

GLYPH_W = 8
GLYPH_H = 8
GLYPH_COLS = 16
CHARS = [chr(i) for i in range(32, 127)]  # ASCII printable


def generate_font(output_stem: str, font_path: str | None, font_size: int) -> None:
    """Render each glyph onto an atlas and write BMFont-compatible .fnt."""
    if font_path:
        font = ImageFont.truetype(font_path, font_size)
    else:
        font = ImageFont.load_default()

    rows = (len(CHARS) + GLYPH_COLS - 1) // GLYPH_COLS
    atlas_w = GLYPH_COLS * GLYPH_W
    atlas_h = rows * GLYPH_H
    atlas = Image.new("L", (atlas_w, atlas_h), 0)
    draw = ImageDraw.Draw(atlas)

    lines = []
    lines.append(f'info face="PixelFont" size={GLYPH_H} bold=0 italic=0 charset=""')
    lines.append(f'common lineHeight={GLYPH_H} base={GLYPH_H - 1} scaleW={atlas_w} scaleH={atlas_h} pages=1')
    lines.append(f'page id=0 file="{output_stem}_0.png"')
    lines.append(f'chars count={len(CHARS)}')

    for idx, ch in enumerate(CHARS):
        col = idx % GLYPH_COLS
        row = idx // GLYPH_COLS
        x = col * GLYPH_W
        y = row * GLYPH_H
        draw.text((x, y), ch, fill=255, font=font)
        lines.append(f'char id={ord(ch)} x={x} y={y} width={GLYPH_W} height={GLYPH_H} xoffset=0 yoffset=0 xadvance={GLYPH_W} page=0 chnl=15')

    atlas.save(f"{output_stem}_0.png")
    with open(f"{output_stem}.fnt", "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Generated: {output_stem}.fnt + {output_stem}_0.png ({atlas_w}x{atlas_h})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate pixel-art bitmap font")
    parser.add_argument("--output", default="assets/fonts/pixel_font", help="Output stem path")
    parser.add_argument("--font", help="Path to TTF/OTF font to rasterize (default: PIL default)")
    parser.add_argument("--size", type=int, default=8, help="Font size in pixels (default: 8)")
    args = parser.parse_args()
    generate_font(args.output, args.font, args.size)
```

### WorldEnvironment Setup

The test scene includes a `WorldEnvironment` node with:
- Background: ClearColor (dark #1a1a2e)
- Tonemap: ACES (standard, preserves lo-fi color palette)
- Glow: Enabled, Levels=01, Intensity=1.0, Strength=0.8
- Bloom: not used (Glow is sufficient for neon)

---

## 6. Input / UI Layer

**No new input handling in this phase.** The 3D text is purely visual — it does not receive input or interact with the UI system. Future phases may add:
- Mouse hover highlight on interactive signs
- Click-to-read sign content (tooltip or dialogue popup)
- State-driven text changes based on GameManager state

---

## 7. Test Layer

### Test Structure

New test file: `tests/test_lo_fi_text_3d.gd` — validates lo-fi text script logic without scene tree dependencies.

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| LoFiText3D.parameter clamping | ✅ | ≥3 | ✅ |
| ShaderMaterial creation | ✅ | ≥2 | ✅ |
| Shader parameter propagation | ✅ | ≥2 | ✅ |
| Emissive color handling | ✅ | ≥2 | ✅ |

### Test Case Descriptions

**Normal Path (TC-44-1): Parameter clamping and get/set cycle**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-44-1-1 | pixel_factor set and get | Create LoFiText3D, set `pixel_factor = 0.7` | pixel_factor == 0.7 | `_assert(node.pixel_factor == 0.7)` |
| TC-44-1-2 | color_bits set and get | Set `color_bits = 12` | color_bits == 12 | `_assert(node.color_bits == 12)` |
| TC-44-1-3 | scanline_intensity set and get | Set `scanline_intensity = 0.5` | scanline_intensity == 0.5 | `_assert(node.scanline_intensity == 0.5)` |
| TC-44-1-4 | emissive_color set and get | Set `emissive_color = Color.AMBER` | emissive_color == Color.AMBER | `_assert(node.emissive_color == Color.AMBER)` |
| TC-44-1-5 | emissive_strength set and get | Set `emissive_strength = 2.5` | emissive_strength == 2.5 | `_assert(node.emissive_strength == 2.5)` |

**Edge Case (TC-44-2): Clamping at boundaries**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-44-2-1 | pixel_factor below minimum | Set `pixel_factor = -0.5` | clamped to 0.0 | `_assert(node.pixel_factor == 0.0)` |
| TC-44-2-2 | pixel_factor above maximum | Set `pixel_factor = 2.0` | clamped to 1.0 | `_assert(node.pixel_factor == 1.0)` |
| TC-44-2-3 | color_bits below minimum | Set `color_bits = 0` | clamped to 2 | `_assert(node.color_bits == 2)` |
| TC-44-2-4 | color_bits above maximum | Set `color_bits = 32` | clamped to 24 | `_assert(node.color_bits == 24)` |
| TC-44-2-5 | scanline_intensity maximum | Set `scanline_intensity = 1.0` | value == 1.0 | `_assert(node.scanline_intensity == 1.0)` |
| TC-44-2-6 | emissive_strength maximum | Set `emissive_strength = 10.0` | clamped to 5.0 | `_assert(node.emissive_strength == 5.0)` |

**Edge Case (TC-44-3): ShaderMaterial creation and parameter sync**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-44-3-1 | Material auto-created on _ready | Create LoFiText3D, add to tree | material_override is ShaderMaterial | `_assert(node.material_override is ShaderMaterial)` |
| TC-44-3-2 | pixel_size is 0.0 after _ready | Create LoFiText3D, add to tree | pixel_size == 0.0 | `_assert(node.pixel_size == 0.0)` |
| TC-44-3-3 | Shader parameter sync after set | Set pixel_factor=0.9, check shader | shader param matches set value | `_assert(shader_param == 0.9)` |

**Failure Path (TC-44-4): Edge cases with invalid values**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-44-4-1 | Default emissive (no glow) | Create node, don't set emissive | shader emissive_strength == 0.0 | `_assert(node.emissive_strength == 0.0)` |
| TC-44-4-2 | Very long text string | Set text to 200-char string | No error, text set correctly | `_assert(len(node.text) == 200)` |
| TC-44-4-3 | Empty text string | Set text to "" | No error, text is empty | `_assert(node.text == "")` |

---

## 8. Files Changed (per-layer summary)

### GDScript / Logic Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/lo_fi_text_3d.gd` | **New** — LoFiText3D script extending Label3D | +85 |

### Shader / Visual Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `shaders/lo_fi_text.gdshader` | **New** — Fragment shader with pixelation, color quantization, scanlines, emissive | +50 |

### Scene Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/test_3d_text.tscn` | **New** — Test scene with Camera3D, WorldEnvironment, 3 Label3D instances | +100 |

### Asset Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `assets/fonts/pixel_font.fnt` | **New** — Bitmap font atlas descriptor | +95 |
| `assets/fonts/pixel_font_0.png` | **New** — Bitmap font texture atlas | — |
| `assets/fonts/pixel_font.tres` | **New** — Godot FontFile resource | +10 |

### Scripts / Tooling

| File | Change | Est. Lines |
|------|--------|-----------|
| `scripts/generate_pixel_font.py` | **New** — Python script to generate pixel font | +45 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_lo_fi_text_3d.gd` | **New** — Tests for LoFiText3D parameter clamping, material creation, shader sync | +120 |

---

## 9. Verification Checklist

- [ ] `shaders/lo_fi_text.gdshader` compiles without errors in `forward_plus` renderer
- [ ] `gdscripts/lo_fi_text_3d.gd` extends Label3D with all exported parameters
- [ ] Shader parameters (`pixel_factor`, `color_bits`, `scanline_intensity`, `emissive_color`, `emissive_strength`) propagate correctly to ShaderMaterial
- [ ] `pixel_size` is forced to 0.0 on Label3D when lo-fi shader is active
- [ ] `assets/fonts/pixel_font.fnt` + `_0.png` generate correctly via `generate_pixel_font.py`
- [ ] `scenes/test_3d_text.tscn` displays three text elements (billboard, flat sign, neon emissive)
- [ ] WorldEnvironment Glow pass enables neon emissive effect on emissive text nodes
- [ ] `scripts/generate_pixel_font.py --output assets/fonts/pixel_font` produces valid `.fnt` file
- [ ] All tests in `tests/test_lo_fi_text_3d.gd` pass: `godot --headless --script tests/run_tests.gd 2>&1 | tail -10`
