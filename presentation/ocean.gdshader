shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.10, 0.35, 0.42);
uniform vec3 deep_color : source_color = vec3(0.02, 0.08, 0.16);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.35;
uniform float wave_scale : hint_range(0.1, 10.0) = 2.2;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	float t = TIME * wave_speed;
	float h = sin(VERTEX.x * wave_scale + t) * 0.12;
	h += sin(VERTEX.z * wave_scale * 0.7 - t * 1.3) * 0.09;
	VERTEX.y += h;
}

void fragment() {
	float depth_mix = clamp(sin(UV.x * 12.0 + TIME * 0.2) * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(deep_color, shallow_color, depth_mix * 0.4 + 0.3);
	ROUGHNESS = roughness_val;
	SPECULAR = 0.6;
}
