shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back;

uniform vec4 glow_color : source_color = vec4(1.0, 0.667, 0.333, 0.3);
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float outline_width : hint_range(0.001, 0.1) = 0.02;

void fragment() {
	vec3 normal_view = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);
	float fresnel = 1.0 - max(dot(normal_view, view_dir), 0.0);
	float outline = smoothstep(1.0 - outline_width, 1.0, fresnel);
	vec3 glow = glow_color.rgb * glow_intensity * outline;
	EMISSION = glow;
	ALPHA = glow_color.a * outline * glow_intensity;
}
