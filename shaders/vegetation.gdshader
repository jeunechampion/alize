// Végétation : couleurs par sommet, deux faces, balancement par le vent (Sousa, GPU Gems 3 ch. 16 :
// déplacement proportionnel à la hauteur, phase propre à chaque instance).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec2 wind_dir = vec2(-1.0, 0.25);
uniform float wind_strength = 1.0;   // amplitude du balancement en haut de l'arbre (m)
uniform float sway_time = 0.0;
uniform float translucency = 0.35;    // lumière qui traverse les feuilles

varying vec3 vcol;
varying float leafness;

void vertex() {
	vcol = COLOR.rgb;
	// INSTANCE_CUSTOM : x = phase, y = hauteur de l'arbre, z = 1 si feuillage sinon 0 (par surface).
	float phase = INSTANCE_CUSTOM.x;
	float tree_h = max(INSTANCE_CUSTOM.y, 1.0);
	float t = clamp(VERTEX.y / tree_h, 0.0, 1.0);
	float sway = sin(sway_time * 1.4 + phase) * 0.7 + sin(sway_time * 3.1 + phase * 1.7) * 0.3;
	vec2 w = normalize(wind_dir);
	VERTEX.xz += w * sway * wind_strength * t * t;
	// Frémissement des feuilles.
	leafness = COLOR.a;
	VERTEX.xyz += vec3(sin(sway_time * 6.0 + phase + VERTEX.x * 3.0), 0.0, cos(sway_time * 5.0 + phase + VERTEX.z * 3.0)) * 0.03 * leafness * wind_strength;
}

void fragment() {
	ALBEDO = vcol;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	// Les faces arrière reçoivent la lumière comme les faces avant (feuilles fines).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = vec3(translucency * leafness);
}
