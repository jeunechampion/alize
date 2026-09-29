## Champ de vent autour de l'île : alizé de base, ascendance de pente le long du relief
## (le vent qui rencontre une pente est dévié vers le haut), thermiques (Allen 2006, simplifié).
## Une vraie simulation de fluide (Stam 1999) remplacera l'ascendance de pente à l'étape 4.
class_name WindField
extends RefCounted

## Vent de base en m/s : souffle vers -X (alizé d'est), légèrement vers +Z.
var base_wind := Vector3(-5.0, 0.0, 1.25)
var generator: IslandGenerator
var thermals: Array = []


func _init(gen: IslandGenerator) -> void:
	generator = gen


func sample(pos: Vector3) -> Vector3:
	var w := base_wind
	var ground := generator.height_at(pos.x, pos.z)
	var agl := pos.y - maxf(ground, IslandGenerator.SEA_LEVEL)
	# Ascendance de pente (et rabattant sous le vent).
	if agl < 300.0 and ground > -5.0:
		var g := generator.gradient_at(pos.x, pos.z)
		var up := base_wind.x * g.x + base_wind.z * g.y
		var falloff := 1.0 - smoothstep(20.0, 300.0, agl)
		w.y += clampf(up * 1.3, -4.0, 7.0) * falloff
	# Gradient de vent au ras des vagues (Rayleigh 1883) : moins de vent sous 20 m.
	if ground <= 0.0 and agl < 20.0:
		var shear := 0.45 + 0.55 * clampf(agl / 20.0, 0.0, 1.0)
		w.x *= shear
		w.z *= shear
	for t in thermals:
		w += t.sample(pos, base_wind)
	return w


## Vitesse verticale seule (pour l'affichage et les tests).
func updraft(pos: Vector3) -> float:
	return sample(pos).y
