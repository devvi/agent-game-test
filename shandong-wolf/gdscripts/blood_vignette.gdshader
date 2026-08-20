// blood_vignette.gdshader — 血色低血 vignette（#582, PRD §4.4 方案 A；AC4: 视觉 alpha 0→0.35）
shader_type canvas_item;
uniform float strength : hint_range(0.0, 0.35) = 0.35;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.55;
uniform float softness : hint_range(0.0, 1.0) = 0.4;
uniform vec3 blood_color : source_color = vec3(0.55, 0.05, 0.05);
void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    float edge = smoothstep(inner_radius, inner_radius + softness, dist);
    COLOR.rgb = mix(COLOR.rgb, blood_color, edge * strength);
    COLOR.a = max(COLOR.a, edge * strength);
}
