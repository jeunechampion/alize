// Océan : vagues de Gerstner (Gerstner 1802 ; Tessendorf 2001, GPU Gems ch. 1) dans le vertex
// shader, couleur par profondeur réelle (lue dans le champ de hauteurs de l'île), écume de rivage
// et de crête, vaguelettes par normales de bruit, reflets du ciel par PBR.
shader_type spatial;
render_mode cull_disabled, depth_draw_always, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform float extent = 5000.0;
uniform float sea_level = 0.0;
uniform float deep_sea = -160.0;

uniform vec3 col_shallow : source_color = vec3(0.12, 0.78, 0.77);
uniform vec3 col_deep : source_color = vec3(0.03, 0.22, 0.55);
uniform vec3 col_foam : source_color = vec3(0.96, 0.98, 0.98);
uniform vec2 wind_dir = vec2(-1.0, 0.25);
uniform float wave_scale = 1.0;
uniform float fade_start = 1500.0;
uniform float fade_end = 1950.0;
uniform float sea_time = 0.0;
uniform float detail_strength = 0.06;

varying vec3 wpos;
varying float wave_h;
varying vec3 wnorm;

const float MAX_AMP = 1.62;

vec3 gerstner(vec2 p, float t, vec2 d, float L, float A, float Q) {
	float k = 6.2831853 / L;
	float c = sqrt(9.81 / k);
	float f = k * (dot(d, p) - c * t);
	return vec3(Q * A * d.x * cos(f), A * sin(f), Q * A * d.y * cos(f));
}

vec3 displace(vec2 p, float t, float s) {
	vec2 w = normalize(wind_dir);
	vec2 w2 = normalize(w + vec2(-w.y, w.x) * 0.45);
	vec2 w3 = normalize(w + vec2(w.y, -w.x) * 0.6);
	vec2 w4 = normalize(w + vec2(-w.y, w.x) * 1.1);
	vec3 o = vec3(0.0);
	o += gerstner(p, t, w, 110.0, 0.85 * s, 0.35);
	o += gerstner(p, t, w2, 55.0, 0.45 * s, 0.45);
	o += gerstner(p, t, w3, 26.0, 0.22 * s, 0.5);
	o += gerstner(p, t, w4, 13.0, 0.10 * s, 0.5);
	return o;
}

void vertex() {
	float t = sea_time;
	float dist = distance(VERTEX.xz, CAMERA_POSITION_WORLD.xz);
	float s = wave_scale * (1.0 - smoothstep(fade_start, fade_end, dist));
	vec2 p = VERTEX.xz;
	// Les vagues s'amortissent dans les eaux peu profondes : le lagon est calme, la houle brise au récif.
	vec2 uv0 = p / extent + 0.5;
	float inside0 = step(0.0, uv0.x) * step(uv0.x, 1.0) * step(0.0, uv0.y) * step(uv0.y, 1.0);
	float terr0 = mix(deep_sea, textureLod(height_tex, clamp(uv0, vec2(0.0), vec2(1.0)), 0.0).r, inside0);
	float depth0 = max(sea_level - terr0, 0.0);
	s *= mix(0.2, 1.0, smoothstep(1.5, 22.0, depth0));
	vec3 d = displace(p, t, s);
	float e = 1.5;
	vec3 dx = displace(p + vec2(e, 0.0), t, s) - displace(p - vec2(e, 0.0), t, s);
	vec3 dz = displace(p + vec2(0.0, e), t, s) - displace(p - vec2(0.0, e), t, s);
	vec3 tx = vec3(2.0 * e, 0.0, 0.0) + dx;
	vec3 tz = vec3(0.0, 0.0, 2.0 * e) + dz;
	wnorm = normalize(cross(tz, tx));
	VERTEX += d;
	NORMAL = wnorm;
	wpos = VERTEX;
	wave_h = d.y / max(MAX_AMP * wave_scale, 0.001);
}

void fragment() {
	// Profondeur d'eau réelle sous ce point, à partir du relief de l'île.
	vec2 uv = wpos.xz / extent + 0.5;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float terr = mix(deep_sea, texture(height_tex, clamp(uv, vec2(0.0), vec2(1.0))).r, inside);
	float border = max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0;
	terr = mix(terr, deep_sea, smoothstep(0.86, 1.0, border));
	float depth = max(wpos.y - terr, 0.0);

	float absorb = 1.0 - exp(-depth / 13.0);
	vec3 col = mix(col_shallow, col_deep, absorb);

	float dist = distance(wpos, CAMERA_POSITION_WORLD);
	float t = sea_time;
	vec2 w = normalize(wind_dir);

	// Vaguelettes : gradient de deux couches de bruit qui défilent avec le vent.
	float e = 0.35;
	vec2 p1 = wpos.xz * 0.11 + w * t * 0.06;
	vec2 p2 = wpos.xz * 0.31 - w * t * 0.10 + vec2(0.37, 0.71);
	float n0 = texture(detail_noise, p1).r + texture(detail_noise, p2).r * 0.5;
	float nx = texture(detail_noise, p1 + vec2(e * 0.11, 0.0)).r + texture(detail_noise, p2 + vec2(e * 0.31, 0.0)).r * 0.5;
	float nz = texture(detail_noise, p1 + vec2(0.0, e * 0.11)).r + texture(detail_noise, p2 + vec2(0.0, e * 0.31)).r * 0.5;
	float detail_amp = detail_strength * (1.0 - smoothstep(500.0, 3500.0, dist));
	vec3 pert = vec3(-(nx - n0), 0.0, -(nz - n0)) * (detail_amp / e);
	vec3 nw = normalize(wnorm + pert);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// Écume : rivage (eau de moins de 3 m) et crêtes.
	float foam_n = texture(detail_noise, wpos.xz * 0.035 + w * t * 0.02).r;
	float foam_f = texture(detail_noise, wpos.xz * 0.16 - w * t * 0.05 + vec2(0.5, 0.2)).r;
	float shore = 1.0 - smoothstep(0.2, 3.0, depth);
	float pulse = 0.12 * sin(t * 1.1 + wpos.x * 0.03 + wpos.z * 0.02);
	float shore_foam = shore * smoothstep(0.42, 0.62, foam_n + pulse) * (0.5 + 0.5 * foam_f);
	float crest_foam = smoothstep(0.7, 1.0, wave_h) * smoothstep(0.62, 0.8, foam_n * 0.5 + foam_f * 0.5) * wave_scale * 0.7;
	float foam = clamp(shore_foam + crest_foam, 0.0, 1.0);
	col = mix(col, col_foam, foam);

	ALBEDO = col;
	ALPHA = mix(0.55, 0.96, absorb);
	ALPHA = mix(ALPHA, 1.0, foam);
	ROUGHNESS = mix(0.06, 0.7, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// Lumière qui traverse les crêtes (diffusion sous la surface, approximation).
	EMISSION = col_shallow * 0.08 * smoothstep(0.2, 1.0, wave_h) * (1.0 - absorb * 0.5) * (1.0 - foam);
}
