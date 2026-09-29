// Sol de l'île : textures Poly Haven (CC0) empilées en tableaux (albédo, normales, AO/rugosité),
// une couche par type de sol, choisie par altitude, pente et bruit ; projection au sol par les
// coordonnées monde, triplanaire pour la roche des falaises. Chaque couche est recalée sur la
// palette « réalisme stylisé tropical » : le détail de la texture est gardé, sa couleur moyenne
// est remplacée par celle de la palette (voir document de conception).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D river_tex : filter_linear, repeat_disable;   // distance aux rivières (m), FORMAT_RF
uniform float extent = 5000.0;
uniform float river_tex_size = 641.0;
uniform bool has_rivers = false;
uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_layers : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray arm_layers : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 layer_mean[9] : source_color;   // couleur moyenne (sRGB) de chaque texture
uniform vec3 layer_tint[9] : source_color;   // couleur cible (palette, sRGB)
uniform float layer_hue[9];      // 1 = garder la teinte de la texture, 0 = seulement sa luminance
uniform float layer_tile[9];     // taille d'un carreau (m)
uniform bool textured = true;

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

const int L_SAND = 0;
const int L_WET = 1;
const int L_GRASS = 2;
const int L_JUNGLE = 3;
const int L_HIGH = 4;
const int L_ROCK = 5;
const int L_BASALT = 6;
const int L_SEABED = 7;
const int L_ASH = 8;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Une couche échantillonnée à plat (projection XZ) : albédo recalé, normale monde, ARM.
void sample_flat(int layer, vec3 p, vec3 N, out vec3 alb, out vec3 nrm, out vec3 arm) {
	vec2 uv = p.xz / layer_tile[layer];
	vec3 t = texture(albedo_layers, vec3(uv, float(layer))).rgb;
	vec3 detail = t / max(layer_mean[layer], vec3(0.01));
	float luma = dot(detail, vec3(0.3333));
	alb = layer_tint[layer] * mix(vec3(luma), detail, layer_hue[layer]);
	vec3 n = texture(normal_layers, vec3(uv, float(layer))).rgb * 2.0 - 1.0;
	// Repère de la projection au sol : u = +X (tangente), haut de l'image = -Z (binormale),
	// plaqué sur la normale du relief.
	vec3 T = normalize(vec3(1.0, 0.0, 0.0) - N * N.x);
	vec3 B = normalize(cross(N, T));
	nrm = normalize(T * n.x + B * n.y + N * n.z);
	arm = texture(arm_layers, vec3(uv, float(layer))).rgb;
}

// Roche : triplanaire (les falaises sont verticales, la projection au sol s'y étirerait).
void sample_triplanar(int layer, vec3 p, vec3 n, out vec3 alb, out vec3 nrm, out vec3 arm) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float tile = layer_tile[layer];
	vec3 ax = texture(albedo_layers, vec3(p.zy / tile, float(layer))).rgb;
	vec3 ay = texture(albedo_layers, vec3(p.xz / tile, float(layer))).rgb;
	vec3 az = texture(albedo_layers, vec3(p.xy / tile, float(layer))).rgb;
	vec3 t = ax * w.x + ay * w.y + az * w.z;
	vec3 detail = t / max(layer_mean[layer], vec3(0.01));
	float luma = dot(detail, vec3(0.3333));
	alb = layer_tint[layer] * mix(vec3(luma), detail, layer_hue[layer]);
	vec3 nx = texture(normal_layers, vec3(p.zy / tile, float(layer))).rgb * 2.0 - 1.0;
	vec3 ny = texture(normal_layers, vec3(p.xz / tile, float(layer))).rgb * 2.0 - 1.0;
	vec3 nz = texture(normal_layers, vec3(p.xy / tile, float(layer))).rgb * 2.0 - 1.0;
	// Normales tangentes ramenées dans le monde par plan (approximation « whiteout » simplifiée).
	vec3 wx = vec3(nx.z * sign(n.x), nx.y, nx.x);
	vec3 wy = vec3(ny.x, ny.z * sign(n.y), -ny.y);
	vec3 wz = vec3(nz.x, nz.y, nz.z * sign(n.z));
	nrm = normalize(wx * w.x + wy * w.y + wz * w.z);
	arm = texture(arm_layers, vec3(p.zy / tile, float(layer))).rgb * w.x
		+ texture(arm_layers, vec3(p.xz / tile, float(layer))).rgb * w.y
		+ texture(arm_layers, vec3(p.xy / tile, float(layer))).rgb * w.z;
}

void fragment() {
	float h = wpos.y - sea_level;
	vec3 N = normalize(wnormal);
	float slope = 1.0 - clamp(N.y, 0.0, 1.0); // 0 = plat, 1 = vertical

	float n_big = texture(detail_noise, wpos.xz * 0.0018).r;   // ~550 m
	float n_mid = texture(detail_noise, wpos.xz * 0.012).r;    // ~80 m
	float n_small = texture(detail_noise, wpos.xz * 0.09).r;   // ~11 m

	// Poids des couches (même logique que la palette plate d'origine).
	float hn = h + (n_mid - 0.5) * 60.0 + (n_big - 0.5) * 120.0;
	float w_jungle = smoothstep(8.0, 90.0, hn);
	float w_high = smoothstep(260.0, 560.0, hn);
	float beach_w = 3.0 + n_mid * 4.0;
	float beach = 1.0 - smoothstep(2.5 + beach_w, 7.5 + beach_w, h);
	float wet = 1.0 - smoothstep(-0.6, 1.6, h);
	float sea = 1.0 - smoothstep(-1.5, -0.2, h);
	float rock_t = smoothstep(0.30 + n_mid * 0.12, 0.52 + n_mid * 0.12, slope);
	float dv = distance(wpos.xz, volcano_pos.xz) / volcano_radius;
	float volc = 1.0 - smoothstep(0.55, 1.1, dv);
	float ash_t = volc * smoothstep(0.45, 0.85, h / volcano_height) * (1.0 - rock_t);
	// Berges des rivières : boue sombre et humide.
	float mud_t = 0.0;
	if (has_rivers) {
		vec2 ruv = (wpos.xz + vec2(extent * 0.5)) / extent;
		ruv = (ruv * (river_tex_size - 1.0) + 0.5) / river_tex_size;
		float rd = texture(river_tex, ruv).r;
		mud_t = (1.0 - smoothstep(0.5, 5.0, rd)) * step(0.3, h);
	}

	// Empilement : végétation -> plage -> mouillé -> fond marin -> roche -> cendres.
	float w[9];
	float veg_g = (1.0 - w_jungle) * (1.0 - w_high);
	float veg_j = w_jungle * (1.0 - w_high);
	float veg_h = w_high;
	w[L_GRASS] = veg_g;
	w[L_JUNGLE] = veg_j;
	w[L_HIGH] = veg_h;
	for (int i = 2; i < 5; i++) { w[i] *= (1.0 - beach); }
	w[L_SAND] = beach;
	for (int i = 0; i < 5; i++) { w[i] *= (1.0 - wet); }
	w[L_WET] = wet;
	for (int i = 0; i < 5; i++) { w[i] *= (1.0 - sea); }
	w[L_SEABED] = sea;
	float rock_all = rock_t * mix(0.5, 1.0, step(-0.2, h));
	for (int i = 0; i < 8; i++) { w[i] *= (1.0 - rock_all); }
	w[L_ROCK] = rock_all * (1.0 - volc);
	w[L_BASALT] = rock_all * volc;
	for (int i = 0; i < 8; i++) { w[i] *= (1.0 - ash_t); }
	w[L_ASH] = ash_t;
	for (int i = 0; i < 9; i++) { w[i] *= (1.0 - mud_t); }
	w[L_ASH] += mud_t;

	vec3 col = vec3(0.0);
	vec3 nrm = vec3(0.0);
	vec3 arm = vec3(0.0);
	if (textured) {
		for (int i = 0; i < 9; i++) {
			if (w[i] < 0.003) { continue; }
			vec3 a; vec3 nn; vec3 ar;
			if (i == L_ROCK || i == L_BASALT) {
				sample_triplanar(i, wpos, N, a, nn, ar);
			} else {
				sample_flat(i, wpos, N, a, nn, ar);
			}
			col += a * w[i];
			nrm += nn * w[i];
			arm += ar * w[i];
		}
		// Variation à grande échelle pour casser la répétition des carreaux.
		col *= 0.86 + 0.28 * n_small;
		col *= 0.9 + 0.2 * n_mid;
	} else {
		vec3 veg = mix(col_grass, col_jungle, w_jungle);
		veg = mix(veg, col_high, w_high);
		veg *= 0.82 + 0.36 * n_small;
		col = mix(veg, col_sand * (0.94 + 0.12 * n_small), beach);
		col = mix(col, col_wet_sand, wet);
		vec3 seabed = mix(col_seabed, col_seabed * 0.55, smoothstep(-6.0, -40.0, h));
		col = mix(col, seabed, sea);
		vec3 rockc = mix(col_rock, col_basalt, volc) * (0.85 + 0.3 * n_small);
		col = mix(col, rockc, rock_all);
		col = mix(col, col_ash * (0.85 + 0.3 * n_small), ash_t);
		nrm = N;
		arm = vec3(1.0, 0.9, 0.0);
	}
	// Fond marin : s'assombrit avec la profondeur (l'eau fait le reste).
	col = mix(col, col * 0.55, sea * smoothstep(-6.0, -40.0, h));

	if (debug_flat) {
		col = vec3(0.16, 0.52, 0.22);
		nrm = N;
	}
	ALBEDO = col;
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(nrm));
	col = mix(col, col * 0.6, mud_t);   // boue humide plus sombre
	ROUGHNESS = mix(clamp(arm.g, 0.5, 1.0), 0.7, max(wet, mud_t) * 0.6); // sable et boue mouillés un peu brillants
	AO = clamp(arm.r, 0.4, 1.0);
	AO_LIGHT_AFFECT = 0.25;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
