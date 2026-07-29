shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.29, 0.56, 0.85, 1.0); // #4a90d9 default
uniform float glow_width : hint_range(1.0, 10.0) = 3.0;
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // Detect edge: alpha difference between current pixel and neighbors
    float alpha_diff = 0.0;
    for (float dx = -glow_width; dx <= glow_width; dx += glow_width / 5.0) {
        for (float dy = -glow_width; dy <= glow_width; dy += glow_width / 5.0) {
            if (dx == 0.0 && dy == 0.0) continue;
            float neighbor = texture(TEXTURE, UV + vec2(dx / 100.0, dy / 100.0)).a;
            alpha_diff = max(alpha_diff, tex.a - neighbor);
        }
    }
    // Outer glow: overlay glow_color outside the edge
    float glow = alpha_diff * glow_intensity;
    COLOR = tex + glow_color * glow;
    // Preserve original alpha
    COLOR.a = tex.a + glow * glow_color.a;
}
