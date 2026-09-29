// Colonne d'air chaud : voile très léger qui monte et ondule, plus visible sur les bords (Fresnel).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.75);
uniform float strength = 0.05;
uniform float height = 1000.0;

varying vec3 wpos;
varying vec3 wnormal;
varying float vfrac;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vfrac = VERTEX.y / height + 0.5;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = pow(1.0 - abs(dot(normalize(wnormal), view_dir)), 2.2);
	float n = vnoise(vec2(atan(wpos.z, wpos.x) * 3.0, wpos.y * 0.02 - TIME * 0.35));
	n = n * 0.6 + 0.4 * vnoise(vec2(wpos.x * 0.05, wpos.y * 0.05 - TIME * 0.6));
	float band = smoothstep(0.35, 0.8, n);
	float vfade = smoothstep(0.0, 0.12, vfrac) * (1.0 - smoothstep(0.65, 1.0, vfrac));
	ALBEDO = tint * strength * (0.35 + fres) * band * vfade;
	ALPHA = 1.0;
}
