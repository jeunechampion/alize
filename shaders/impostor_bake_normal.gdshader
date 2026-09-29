// Cuisson des imposteurs, passe normales : normale géométrique dans l'espace du modèle (faces
// arrière retournées vers la caméra), encodée n*0.5+0.5. Le rendu dans un SubViewport (rendu
// Compatibility) est relu tel quel, sans conversion linéaire -> sRGB : le PNG contient l'encodage.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;
uniform float leaf : hint_range(0.0, 1.0) = 0.0;
uniform float translucency = 0.3;
uniform float alpha_boost = 0.35;

void fragment() {
	vec4 col = texture(albedo_tex, UV) * tint;
	if (alpha_scissor > 0.0) {
		vec2 ts = vec2(textureSize(albedo_tex, 0));
		vec2 dx = dFdx(UV) * ts;
		vec2 dy = dFdy(UV) * ts;
		float lod = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1.0));
		ALPHA = col.a * (1.0 + lod * alpha_boost);
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	vec3 n = NORMAL;
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 n_world = mat3(INV_VIEW_MATRIX) * n;
	vec3 n_model = normalize(transpose(mat3(MODEL_MATRIX)) * n_world);
	ALBEDO = n_model * 0.5 + 0.5;
}
