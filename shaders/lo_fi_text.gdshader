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
