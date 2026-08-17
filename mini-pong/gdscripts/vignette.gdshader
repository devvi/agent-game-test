// vignette.gdshader — 全屏径向暗角 (#527, PRD 4.2-A; headless 编译安全已由 Spike 1 前置验证)
shader_type canvas_item;
uniform float strength : hint_range(0.0, 0.10) = 0.08;   // 峰值暗度上限 0.10（AC2，mechanical）
uniform float inner_radius : hint_range(0.0, 1.0) = 0.62; // 中心不变暗半径（归一化，taste-draft）
uniform float softness : hint_range(0.0, 1.0) = 0.35;     // 边缘过渡柔和度（taste-draft）

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float edge = smoothstep(inner_radius, inner_radius + softness, dist);
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), edge * strength);  // 边缘向黑暗化 ≤10%
	COLOR.a = max(COLOR.a, edge * strength);                  // 暗带自身 alpha（盖住下层 L0）
}
