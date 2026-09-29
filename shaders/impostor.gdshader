// Imposteur : arbre lointain rendu sur un panneau face à la caméra à partir d'un atlas de vues
// pré-calculées (N_AZ azimuts × N_EL élévations, cuit par tools/bake_impostors.gd). Pour la
// direction de vue courante, on prend les quatre vues voisines, on reprojette le point du panneau
// dans le repère de chaque vue et on mélange (bilinéaire en azimut/élévation). L'atlas des normales
// (espace du modèle) permet un éclairage cohérent avec le soleil et l'heure.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform float radius = 8.0;       // rayon de la sphère cuite (m, échelle 1)
uniform float center_y = 6.0;     // hauteur du centre de la sphère (m, échelle 1)
uniform int n_az = 8;
uniform int n_el = 5;
uniform float alpha_boost = 0.35;

varying vec3 v_local;   // point du panneau, espace modèle, en unités de rayon
varying vec3 v_dir;     // direction vers la caméra, espace modèle
varying vec4 v_tint;

vec3 cell_dir(float ia, float ie) {
	float az = ia / float(n_az) * TAU;
	float el = min(ie / float(n_el - 1) * (PI * 0.5), radians(89.9));
	return vec3(cos(el) * sin(az), sin(el), cos(el) * cos(az));
}

void vertex() {
	v_tint = COLOR;
	mat3 basis = mat3(MODEL_MATRIX);
	float s = length(basis[0]);
	mat3 rot = mat3(basis[0] / s, basis[1] / s, basis[2] / s);
	vec3 center_w = (MODEL_MATRIX * vec4(0.0, center_y, 0.0, 1.0)).xyz;
	vec3 d_w = normalize(CAMERA_POSITION_WORLD - center_w);
	vec3 d = normalize(transpose(rot) * d_w);
	vec3 r = abs(d.y) < 0.999 ? normalize(cross(vec3(0.0, 1.0, 0.0), d)) : vec3(1.0, 0.0, 0.0);
	vec3 u = cross(d, r);
	vec2 q = VERTEX.xy;   // quad ±1
	vec3 p = r * q.x + u * q.y;
	VERTEX = vec3(0.0, center_y, 0.0) + p * radius;
	NORMAL = d;
	v_local = p;
	v_dir = d;
}

void fragment() {
	vec3 d = normalize(v_dir);
	float el = clamp(asin(clamp(d.y, -1.0, 1.0)), 0.0, PI * 0.5);
	float az = atan(d.x, d.z);
	if (az < 0.0) {
		az += TAU;
	}
	float fa = az / TAU * float(n_az);
	float fe = el / (PI * 0.5) * float(n_el - 1);
	float ia0 = floor(fa);
	float ie0 = min(floor(fe), float(n_el - 2));
	float wa = fa - ia0;
	float we = clamp(fe - ie0, 0.0, 1.0);
	vec2 cell_size = 1.0 / vec2(float(n_az), float(n_el));
	vec4 col = vec4(0.0);
	vec4 nrm = vec4(0.0);
	float wsum = 0.0;
	for (int k = 0; k < 4; k++) {
		float ia = ia0 + float(k & 1);
		float ie = ie0 + float(k >> 1);
		float w = ((k & 1) == 0 ? 1.0 - wa : wa) * ((k >> 1) == 0 ? 1.0 - we : we);
		vec3 dc = cell_dir(ia, ie);
		vec3 rc = normalize(cross(vec3(0.0, 1.0, 0.0), dc));
		vec3 uc = cross(dc, rc);
		vec2 uv = vec2(dot(v_local, rc), dot(v_local, uc)) * 0.5 + 0.5;
		uv = clamp(uv, 0.002, 0.998);
		uv.y = 1.0 - uv.y;
		vec2 auv = (vec2(mod(ia, float(n_az)), ie) + uv) * cell_size;
		col += texture(albedo_atlas, auv) * w;
		nrm += texture(normal_atlas, auv) * w;
		wsum += w;
	}
	// Couleurs prémultipliées dans l'atlas : on divise par la couverture.
	float cov = col.a;
	// Niveau de mipmap estimé depuis les dérivées du point du panneau (en texels de cellule).
	float px = float(textureSize(albedo_atlas, 0).x) / float(n_az) * 0.5;
	vec3 dlx = dFdx(v_local) * px;
	vec3 dly = dFdy(v_local) * px;
	float lod = 0.5 * log2(max(max(dot(dlx, dlx), dot(dly, dly)), 1.0));
	ALPHA = cov * (1.0 + lod * alpha_boost);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = col.rgb / max(cov, 0.001) * v_tint.rgb;
	vec3 n_model = nrm.rgb / max(nrm.a, 0.001) * 2.0 - 1.0;
	if (dot(n_model, n_model) < 0.05) {
		n_model = d;
	}
	// Normales dans l'espace du modèle -> monde -> vue.
	vec3 n_world = normalize(mat3(MODEL_MATRIX) * n_model);
	NORMAL = normalize(mat3(VIEW_MATRIX) * n_world);
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	// Occlusion approchée : le bas de la couronne et le tronc reçoivent moins de ciel.
	AO = 0.7 + 0.3 * clamp(v_local.y * 0.5 + 0.5, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.5;
}
