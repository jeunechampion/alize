// Couche de nuages : bruit fractal sur un plan haut, éclairé par le soleil, qui dérive avec l'alizé.
// (Version légère, en attendant les nuages volumétriques de l'étape suivante.)
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.42;
uniform float softness = 0.28;
uniform vec2 wind = vec2(-1.0, 0.25);
uniform float wind_speed = 9.0;      // m/s
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.9);
uniform vec3 shade_color : source_color = vec3(0.55, 0.62, 0.75);
uniform float cloud_time = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 drift = normalize(wind) * wind_speed * cloud_time;
	vec2 p = (wpos.xz + drift) * 0.00016;
	float n = texture(noise_tex, p).r;
	n = n * 0.72 + texture(noise_tex, p * 3.1 + vec2(0.13, 0.41)).r * 0.28;
	float d = smoothstep(1.0 - coverage, 1.0 - coverage + softness, n);

	// Ombrage : le bord fin est lumineux, le cœur épais plus sombre ; teinte du soleil.
	float thick = smoothstep(1.0 - coverage + softness * 0.3, 1.0, n);
	float lit = 0.55 + 0.45 * clamp(sun_dir.y * 1.4, 0.0, 1.0);
	vec3 col = mix(sun_color * 1.05 * lit, shade_color * lit, thick * 0.8);

	// Fondu vers l'horizon et transparence par densité.
	float dist = distance(wpos.xz, CAMERA_POSITION_WORLD.xz);
	float horizon_fade = 1.0 - smoothstep(14000.0, 32000.0, dist);
	ALBEDO = col;
	ALPHA = d * 0.92 * horizon_fade;
}
