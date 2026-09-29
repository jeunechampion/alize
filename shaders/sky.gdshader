// Ciel par diffusion atmosphérique à simple diffusion (Nishita 1993 ; O'Neil, GPU Gems 2 ch. 16) :
// diffusion de Rayleigh (le bleu du ciel, le rouge des couchers) et de Mie (le halo du soleil),
// intégrées le long du rayon de vue dans une atmosphère à densité exponentielle.
// Disque solaire atténué par la transmittance, étoiles et Voie lactée la nuit.
shader_type sky;

uniform float sun_intensity = 12.0;
uniform vec3 rayleigh_beta = vec3(5.8e-6, 13.5e-6, 33.1e-6);   // m^-1
uniform float mie_beta = 21e-6;
uniform float mie_g = 0.76;
uniform float rayleigh_height = 8000.0;
uniform float mie_height = 1200.0;
uniform float planet_radius = 6371000.0;
uniform float atmosphere_radius = 6471000.0;
uniform float sun_angular_radius = 0.0095;   // radians (grossi pour le style)
uniform float sun_disk_intensity = 60.0;
uniform float night_glow = 0.012;
uniform vec3 ground_color : source_color = vec3(0.04, 0.12, 0.24);
uniform float star_density = 0.985;
uniform float milky_way = 0.6;

const int VIEW_SAMPLES = 16;
const int LIGHT_SAMPLES = 6;

float ray_sphere_far(vec3 ro, vec3 rd, float radius) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - radius * radius;
	float d = b * b - c;
	if (d < 0.0) {
		return -1.0;
	}
	return -b + sqrt(d);
}

float ray_sphere_near(vec3 ro, vec3 rd, float radius) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - radius * radius;
	float d = b * b - c;
	if (d < 0.0) {
		return -1.0;
	}
	float t = -b - sqrt(d);
	return t;
}

// Échantillonnage exponentiel le long du rayon : les premiers pas sont courts (là où l'air est dense
// et proche), les derniers longs. Avec un pas uniforme, un rayon horizontal de 1100 km serait
// intégré en dix tranches de 110 km, chacune déjà opaque : l'horizon deviendrait noir.
float exp_t(float u, float t_max, float k) {
	return t_max * (exp(k * u) - 1.0) / (exp(k) - 1.0);
}

vec3 atmosphere(vec3 dir, vec3 sun_dir, float altitude, out vec3 transmittance) {
	vec3 origin = vec3(0.0, planet_radius + max(altitude, 1.0), 0.0);
	float t_max = ray_sphere_far(origin, dir, atmosphere_radius);
	float t_ground = ray_sphere_near(origin, dir, planet_radius);
	if (t_ground > 0.0) {
		t_max = t_ground;
	}
	float mu = dot(dir, sun_dir);
	float phase_r = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g2 = mie_g * mie_g;
	float phase_m = 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu)) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * mie_g * mu, 1.5));

	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float opt_r = 0.0;
	float opt_m = 0.0;
	float kv = 5.0;
	for (int i = 0; i < VIEW_SAMPLES; i++) {
		float t0 = exp_t(float(i) / float(VIEW_SAMPLES), t_max, kv);
		float t1 = exp_t(float(i + 1) / float(VIEW_SAMPLES), t_max, kv);
		float seg = t1 - t0;
		vec3 p = origin + dir * (t0 + seg * 0.5);
		float h = max(length(p) - planet_radius, 0.0);
		float hr = exp(-h / rayleigh_height) * seg;
		float hm = exp(-h / mie_height) * seg;
		opt_r += hr;
		opt_m += hm;
		float t_light = ray_sphere_far(p, sun_dir, atmosphere_radius);
		float opt_lr = 0.0;
		float opt_lm = 0.0;
		bool lit = ray_sphere_near(p, sun_dir, planet_radius) < 0.0;
		if (lit) {
			float kl = 3.0;
			for (int j = 0; j < LIGHT_SAMPLES; j++) {
				float l0 = exp_t(float(j) / float(LIGHT_SAMPLES), t_light, kl);
				float l1 = exp_t(float(j + 1) / float(LIGHT_SAMPLES), t_light, kl);
				float segl = l1 - l0;
				vec3 q = p + sun_dir * (l0 + segl * 0.5);
				float hq = max(length(q) - planet_radius, 0.0);
				opt_lr += exp(-hq / rayleigh_height) * segl;
				opt_lm += exp(-hq / mie_height) * segl;
			}
			vec3 tau = rayleigh_beta * (opt_r + opt_lr) + vec3(mie_beta) * 1.1 * (opt_m + opt_lm);
			vec3 attn = exp(-tau);
			sum_r += attn * hr;
			sum_m += attn * hm;
		}
	}
	transmittance = exp(-(rayleigh_beta * opt_r + vec3(mie_beta) * 1.1 * opt_m));
	return sun_intensity * (sum_r * rayleigh_beta * phase_r + sum_m * vec3(mie_beta) * phase_m);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float stars(vec3 dir) {
	vec3 p = dir * 180.0;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < star_density) {
		return 0.0;
	}
	vec3 center = cell + 0.5 + (vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.3)) - 0.5) * 0.8;
	float d = length(p - center);
	float bright = pow((h - star_density) / (1.0 - star_density), 2.0);
	return smoothstep(0.35, 0.0, d) * (0.4 + 2.5 * bright);
}

float milky(vec3 dir) {
	vec3 n = normalize(vec3(0.35, 0.55, 0.76));   // plan galactique incliné
	float band = exp(-pow(dot(dir, n) * 4.5, 2.0));
	float m = hash13(floor(dir * 40.0)) * 0.5 + hash13(floor(dir * 15.0 + 2.3)) * 0.5;
	return band * (0.35 + 0.65 * m);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float day = smoothstep(-0.12, 0.08, sun_dir.y);
	vec3 tr;
	// Sous l'horizon géométrique, on prolonge la brume de l'horizon (la mer couvre de toute façon
	// cette zone) ; on ne tend vers la couleur sombre de la mer que bien plus bas (reflets, ambiance).
	vec3 dir_h = normalize(vec3(dir.x, max(dir.y, -0.0015), dir.z));
	vec3 col = atmosphere(dir_h, sun_dir, max(POSITION.y, 0.0), tr);
	float below = smoothstep(-0.03, -0.4, dir.y);
	col = mix(col, ground_color * (0.3 + 0.7 * day), below);
	float mu = dot(dir, sun_dir);
	// disque solaire, atténué par l'atmosphère traversée
	float disk = smoothstep(cos(sun_angular_radius * 1.25), cos(sun_angular_radius * 0.9), mu);
	if (dir.y > -0.02) {
		col += LIGHT0_COLOR * sun_disk_intensity * disk * tr * LIGHT0_ENERGY;
	}
	// nuit : étoiles, Voie lactée, faible lueur
	float night = 1.0 - day;
	if (night > 0.0 && dir.y > 0.0) {
		float s = stars(dir);
		float mw = milky(dir) * milky_way;
		col += (vec3(0.85, 0.9, 1.0) * s * 0.9 + vec3(0.55, 0.6, 0.85) * mw * 0.12) * night * smoothstep(0.0, 0.15, dir.y);
		col += vec3(0.05, 0.08, 0.16) * night_glow * (1.0 + 2.0 * (1.0 - dir.y));
	}
	COLOR = col;
}
