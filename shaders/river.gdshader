// Eau courante : couleur turquoise translucide, vaguelettes qui défilent vers l'aval (UV.y),
// reflets de Fresnel, écume légère sur les bords.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.16, 0.55, 0.60);
uniform vec3 deep_color : source_color = vec3(0.10, 0.40, 0.48);
uniform float flow_speed = 0.9;

void fragment() {
	float t = TIME * flow_speed;
	vec2 uv1 = vec2(UV.x * 2.0, UV.y - t * 0.25);
	vec2 uv2 = vec2(UV.x * 3.1 + 0.3, UV.y * 1.7 - t * 0.4);
	vec3 n1 = texture(ripple_normal, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(ripple_normal, uv2).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3((n1.xy + n2.xy) * 0.35, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);   // 1 au milieu, 0 au bord
	vec3 col = mix(water_color, deep_color, edge * 0.8);
	float foam = (1.0 - edge) * 0.35 * (0.5 + 0.5 * sin(UV.y * 9.0 - t * 3.0 + n1.x * 4.0));
	col = mix(col, vec3(0.85, 0.92, 0.9), foam);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ALPHA = clamp(0.55 + 0.35 * fresnel + foam * 0.3, 0.0, 0.95);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
