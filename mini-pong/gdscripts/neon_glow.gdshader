shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.29, 0.56, 0.85, 1.0); // #4a90d9 default
uniform float glow_width : hint_range(0.0, 0.5) = 0.25;
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec4 src_color = tex * COLOR;

	// Distance from nearest edge (0 = edge, 0.5 = center)
	float dx = min(UV.x, 1.0 - UV.x);
	float dy = min(UV.y, 1.0 - UV.y);
	float edge_dist = min(dx, dy);

	// Glow: strongest at edge, fading inward
	float glow = 1.0 - smoothstep(0.0, glow_width, edge_dist);
	glow *= glow_intensity;

	// Blend glow color over the source color
	COLOR.rgb = mix(src_color.rgb, glow_color.rgb, glow * glow_color.a);
	COLOR.a = max(src_color.a, glow * glow_color.a);
}
