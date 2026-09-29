// Végétation (modèles d'artistes) : textures d'origine, découpe alpha des feuilles, deux faces,
// balancement par le vent (Sousa, GPU Gems 3 ch. 16 : déplacement proportionnel au carré de la
// hauteur, phase propre à chaque instance) et frémissement des feuilles.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;   // 0 = surface opaque
uniform float leaf : hint_range(0.0, 1.0) = 0.0;            // 1 = feuillage : frémit, translucide
uniform float translucency = 0.3;
uniform float alpha_boost = 0.35;   // relèvement de l'alpha par niveau de mipmap (anti-érosion des feuilles)

global uniform float wind_time;
global uniform vec2 wind_dir;
global uniform float wind_gust;   // 0..1 : force du vent (rafales)

varying vec4 instance_tint;

void vertex() {
	instance_tint = COLOR;
	// INSTANCE_CUSTOM : x = phase, y = hauteur du modèle, z = amplitude du balancement en haut (m),
	// w = amplitude du frémissement des feuilles (m).
	float phase = INSTANCE_CUSTOM.x;
	float model_h = max(INSTANCE_CUSTOM.y, 0.5);
	float t = clamp(VERTEX.y / model_h, 0.0, 1.0);
	float sway = sin(wind_time * 1.4 + phase) * 0.7 + sin(wind_time * 3.1 + phase * 1.7) * 0.3;
	float strength = 0.5 + wind_gust;
	vec2 w = normalize(wind_dir);
	// Le balancement est appliqué dans l'espace du modèle : on ramène la direction du vent.
	vec3 w_local = (inverse(mat3(MODEL_MATRIX)) * vec3(w.x, 0.0, w.y));
	VERTEX += w_local * sway * INSTANCE_CUSTOM.z * strength * t * t;
	// Frémissement des feuilles.
	VERTEX += vec3(sin(wind_time * 6.0 + phase + VERTEX.x * 3.0), 0.0, cos(wind_time * 5.0 + phase + VERTEX.z * 3.0))
		* INSTANCE_CUSTOM.w * leaf * strength;
}

void fragment() {
	vec4 col = texture(albedo_tex, UV) * tint;
	if (alpha_scissor > 0.0) {
		// Les mipmaps moyennent l'alpha : au loin les feuilles s'érodent et l'arbre paraît nu.
		// On relève l'alpha avec le niveau de mipmap (calculé depuis les dérivées des UV).
		vec2 ts = vec2(textureSize(albedo_tex, 0));
		vec2 dx = dFdx(UV) * ts;
		vec2 dy = dFdy(UV) * ts;
		float lod = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1.0));
		ALPHA = col.a * (1.0 + lod * alpha_boost);
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	ALBEDO = col.rgb * instance_tint.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	// Les faces arrière reçoivent la lumière comme les faces avant (feuilles fines).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = vec3(translucency * leaf);
}
