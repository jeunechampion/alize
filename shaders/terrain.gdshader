// Couleurs du sol par altitude, pente et bruit : sable, végétation, roche, basalte, cendres.
// Palette "réalisme stylisé tropical" (voir document de conception).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 volcano_pos = vec3(0.0);
uniform float volcano_radius = 700.0;
uniform float volcano_height = 850.0;
uniform float sea_level = 0.0;
uniform bool debug_flat = false;

uniform vec3 col_sand : source_color = vec3(0.945, 0.890, 0.722);
uniform vec3 col_wet_sand : source_color = vec3(0.78, 0.70, 0.52);
uniform vec3 col_grass : source_color = vec3(0.38, 0.74, 0.30);
uniform vec3 col_jungle : source_color = vec3(0.16, 0.52, 0.22);
uniform vec3 col_high : source_color = vec3(0.47, 0.52, 0.28);
uniform vec3 col_rock : source_color = vec3(0.52, 0.48, 0.42);
uniform vec3 col_basalt : source_color = vec3(0.27, 0.25, 0.24);
uniform vec3 col_ash : source_color = vec3(0.36, 0.32, 0.30);
uniform vec3 col_seabed : source_color = vec3(0.70, 0.66, 0.50);

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float h = wpos.y - sea_level;
	float slope = 1.0 - clamp(wnormal.y, 0.0, 1.0); // 0 = plat, 1 = vertical

	float n_big = texture(detail_noise, wpos.xz * 0.0018).r;   // ~550 m
	float n_mid = texture(detail_noise, wpos.xz * 0.012).r;    // ~80 m
	float n_small = texture(detail_noise, wpos.xz * 0.09).r;   // ~11 m

	// Végétation selon l'altitude, avec un tramage pour éviter les bandes.
	float hn = h + (n_mid - 0.5) * 60.0 + (n_big - 0.5) * 120.0;
	vec3 veg = mix(col_grass, col_jungle, smoothstep(8.0, 90.0, hn));
	veg = mix(veg, col_high, smoothstep(260.0, 560.0, hn));
	veg *= 0.82 + 0.36 * n_small;

	// Plage : sable sec puis sable mouillé au bord de l'eau.
	float beach_w = 3.0 + n_mid * 4.0;
	float beach = 1.0 - smoothstep(2.5 + beach_w, 7.5 + beach_w, h);
	vec3 col = mix(veg, col_sand * (0.94 + 0.12 * n_small), beach);
	col = mix(col, col_wet_sand, 1.0 - smoothstep(-0.6, 1.6, h));

	// Fond marin : sable clair dans le lagon, s'assombrit avec la profondeur.
	vec3 seabed = mix(col_seabed, col_seabed * 0.55, smoothstep(-6.0, -40.0, h));
	seabed = mix(seabed, col_rock * 0.8, smoothstep(0.35, 0.6, slope) * 0.6);
	col = mix(col, seabed, 1.0 - smoothstep(-1.5, -0.2, h));

	// Roche sur les pentes fortes ; basalte près du volcan.
	float rock_t = smoothstep(0.30 + n_mid * 0.12, 0.52 + n_mid * 0.12, slope);
	float dv = distance(wpos.xz, volcano_pos.xz) / volcano_radius;
	float volc = 1.0 - smoothstep(0.55, 1.1, dv);
	vec3 rockc = mix(col_rock, col_basalt, volc) * (0.85 + 0.3 * n_small);
	col = mix(col, rockc, rock_t * step(-0.2, h) + rock_t * 0.5 * (1.0 - step(-0.2, h)));

	// Cendres et sol nu vers le sommet du volcan.
	float ash_t = volc * smoothstep(0.45, 0.85, h / volcano_height) * (1.0 - rock_t);
	col = mix(col, col_ash * (0.85 + 0.3 * n_small), ash_t);

	if (debug_flat) {
		col = vec3(0.16, 0.52, 0.22);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, (1.0 - smoothstep(-0.6, 1.6, h)) * 0.6); // sable mouillé un peu brillant
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
