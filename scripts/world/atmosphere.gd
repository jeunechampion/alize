## Modèle d'atmosphère, sans dépendance au moteur : position du soleil (Meeus 1991, latitude
## tropicale, équinoxe), transmittance et couleur du ciel par diffusion simple de Rayleigh et de Mie
## (Nishita 1993 ; O'Neil 2005). Le shader sky.gdshader implémente le même modèle sur le GPU.
class_name Atmosphere
extends RefCounted

const PLANET_R := 6371000.0
const ATMO_R := 6471000.0
const BETA_R := Vector3(5.8e-6, 13.5e-6, 33.1e-6)
const BETA_M := 21e-6
const SUN_INTENSITY := 12.0


## Position du soleil pour une latitude, à l'équinoxe (déclinaison 0), depuis l'heure locale.
static func sun_direction(time_of_day: float, latitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var hour_angle := (time_of_day / 24.0 - 0.5) * TAU   # 0 à midi
	var east := -sin(hour_angle)
	var up := cos(hour_angle) * cos(lat)
	var south := cos(hour_angle) * sin(lat)
	# Godot : +X = est, +Z = sud (donc -Z = nord).
	return Vector3(east, up, south).normalized()


static func exp_t(u: float, t_max: float, k: float) -> float:
	return t_max * (exp(k * u) - 1.0) / (exp(k) - 1.0)


## Transmittance de l'atmosphère le long du rayon vers le soleil, depuis le sol (Rayleigh + Mie).
static func sun_transmittance(dir: Vector3) -> Vector3:
	var planet_r := 6371000.0
	var atmo_r := 6471000.0
	var beta_r := Vector3(5.8e-6, 13.5e-6, 33.1e-6)
	var beta_m := 21e-6 * 1.1
	var origin := Vector3(0.0, planet_r + 10.0, 0.0)
	var b := origin.dot(dir)
	var c := origin.dot(origin) - atmo_r * atmo_r
	var d := b * b - c
	if d < 0.0:
		return Vector3.ZERO
	var t_max := -b + sqrt(d)
	var cg := origin.dot(origin) - planet_r * planet_r
	var dg := b * b - cg
	if dg > 0.0 and -b - sqrt(dg) > 0.0:
		return Vector3.ZERO   # le soleil est sous l'horizon
	var n := 16
	var opt_r := 0.0
	var opt_m := 0.0
	for i in n:
		var t0 := exp_t(float(i) / n, t_max, 3.0)
		var t1 := exp_t(float(i + 1) / n, t_max, 3.0)
		var seg := t1 - t0
		var p := origin + dir * (t0 + seg * 0.5)
		var h := maxf(p.length() - planet_r, 0.0)
		opt_r += exp(-h / 8000.0) * seg
		opt_m += exp(-h / 1200.0) * seg
	var tau := beta_r * opt_r + Vector3(beta_m, beta_m, beta_m) * opt_m
	return Vector3(exp(-tau.x), exp(-tau.y), exp(-tau.z))


## Couleur du ciel dans une direction (même modèle que le shader, 16x6 échantillons) : sert à la brume.
static func atmosphere_color(dir: Vector3, sun_dir: Vector3) -> Vector3:
	var planet_r := 6371000.0
	var atmo_r := 6471000.0
	var beta_r := Vector3(5.8e-6, 13.5e-6, 33.1e-6)
	var beta_m := 21e-6
	var g := 0.76
	var origin := Vector3(0.0, planet_r + 10.0, 0.0)
	var b := origin.dot(dir)
	var c := origin.dot(origin) - atmo_r * atmo_r
	var d := b * b - c
	if d < 0.0:
		return Vector3.ZERO
	var t_max := -b + sqrt(d)
	var cg := origin.dot(origin) - planet_r * planet_r
	var dg := b * b - cg
	if dg > 0.0 and -b - sqrt(dg) > 0.0:
		t_max = -b - sqrt(dg)
	var mu := dir.dot(sun_dir)
	var phase_r := 3.0 / (16.0 * PI) * (1.0 + mu * mu)
	var g2 := g * g
	var phase_m := 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu)) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * mu, 1.5))
	var sum_r := Vector3.ZERO
	var sum_m := Vector3.ZERO
	var opt_r := 0.0
	var opt_m := 0.0
	var n := 16
	for i in n:
		var t0 := exp_t(float(i) / n, t_max, 5.0)
		var t1 := exp_t(float(i + 1) / n, t_max, 5.0)
		var seg := t1 - t0
		var p := origin + dir * (t0 + seg * 0.5)
		var h := maxf(p.length() - planet_r, 0.0)
		var hr := exp(-h / 8000.0) * seg
		var hm := exp(-h / 1200.0) * seg
		opt_r += hr
		opt_m += hm
		var bl := p.dot(sun_dir)
		var cl := p.dot(p) - atmo_r * atmo_r
		var tl_max := -bl + sqrt(maxf(bl * bl - cl, 0.0))
		var clg := p.dot(p) - planet_r * planet_r
		var dlg := bl * bl - clg
		if dlg > 0.0 and -bl - sqrt(dlg) > 0.0:
			continue   # point dans l'ombre de la planète
		var nl := 6
		var opt_lr := 0.0
		var opt_lm := 0.0
		for j in nl:
			var l0 := exp_t(float(j) / nl, tl_max, 3.0)
			var l1 := exp_t(float(j + 1) / nl, tl_max, 3.0)
			var segl := l1 - l0
			var q := p + sun_dir * (l0 + segl * 0.5)
			var hq := maxf(q.length() - planet_r, 0.0)
			opt_lr += exp(-hq / 8000.0) * segl
			opt_lm += exp(-hq / 1200.0) * segl
		var tau := beta_r * (opt_r + opt_lr) + Vector3.ONE * (beta_m * 1.1 * (opt_m + opt_lm))
		var attn := Vector3(exp(-tau.x), exp(-tau.y), exp(-tau.z))
		sum_r += attn * hr
		sum_m += attn * hm
	return (sum_r * beta_r * phase_r + sum_m * beta_m * phase_m) * SUN_INTENSITY
