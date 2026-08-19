// ink_wash.gdshader — 全屏水墨晕染（#582, PRD §4.3 方案 A；AC3 硬约束: edge_alpha ≤ 0.3）
shader_type canvas_item;
uniform float edge_alpha : hint_range(0.0, 0.3) = 0.3;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.62;
uniform float softness : hint_range(0.0, 1.0) = 0.35;
uniform float noise_amount : hint_range(0.0, 0.2) = 0.06;
uniform vec3 ink_color : source_color = vec3(0.102, 0.122, 0.149);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    float edge = smoothstep(inner_radius, inner_radius + softness, dist);
    float noise = (hash(floor(UV * 80.0)) - 0.5) * noise_amount;
    float ink = clamp(edge + noise, 0.0, 1.0);
    COLOR.rgb = mix(COLOR.rgb, ink_color, ink * edge_alpha);
    COLOR.a = max(COLOR.a, ink * edge_alpha);
}
