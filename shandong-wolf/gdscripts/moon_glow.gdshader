// moon_glow.gdshader — 苍月悬顶冷白月晕（#583）。
// 同心 alpha 衰减: radius_ratio=1.0 & strength=1.0 → 近似实心苍白圆盘（Moon 本体）；
//   radius_ratio=2.2 & strength=0.35 → 自中心向外扩散的冷白光晕（MoonGlow）。
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform float radius_ratio : hint_range(1.0, 4.0) = 2.2;
uniform vec4 glow_color : source_color = vec4(0.72, 0.77, 0.85, 1.0);

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * 2.0;
	float d = length(uv);
	float core = clamp(1.0 - d, 0.0, 1.0);
	float halo = pow(clamp(1.0 - d / radius_ratio, 0.0, 1.0), 2.0);
	float alpha = strength * max(core, halo);
	COLOR = vec4(glow_color.rgb, glow_color.a * alpha);
}
