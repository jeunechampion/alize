## Colonne d'air chaud. Modèle d'Allen (NASA 2006) simplifié : profil en cloche dans le rayon,
## léger courant descendant en couronne, montée progressive depuis la base, affaiblissement au sommet,
## et colonne inclinée par le vent.
class_name Thermal
extends RefCounted

var center := Vector2.ZERO   # position au sol (x, z)
var base_y := 0.0            # altitude de la base
var top := 1200.0            # altitude où la colonne s'éteint
var radius := 90.0           # rayon du cœur
var core := 3.0              # vitesse verticale au centre (m/s)


func _init(p_center: Vector2, p_base: float, p_top: float, p_radius: float, p_core: float) -> void:
	center = p_center
	base_y = p_base
	top = p_top
	radius = p_radius
	core = p_core


## Centre de la colonne à une altitude donnée (elle penche avec le vent).
func center_at(y: float, wind: Vector3) -> Vector2:
	var lean := Vector2(wind.x, wind.z) * 0.22 * maxf(y - base_y, 0.0) / maxf(core, 0.5)
	return center + lean * 0.1


func sample(pos: Vector3, wind: Vector3) -> Vector3:
	if pos.y > top or pos.y < base_y - 20.0:
		return Vector3.ZERO
	var c := center_at(pos.y, wind)
	var r := Vector2(pos.x, pos.z).distance_to(c) / radius
	if r > 1.5:
		return Vector3.ZERO
	var prof: float
	if r <= 1.0:
		prof = 1.0 - r * r
	else:
		# Couronne descendante, continue en r = 1 (0), maximale vers r = 1.15, nulle en r = 1.5.
		prof = -0.18 * smoothstep(1.0, 1.15, r) * (1.0 - smoothstep(1.15, 1.5, r))
	var hz := smoothstep(base_y - 20.0, base_y + 80.0, pos.y) * (1.0 - smoothstep(top - 200.0, top, pos.y))
	return Vector3(0.0, core * prof * hz, 0.0)
