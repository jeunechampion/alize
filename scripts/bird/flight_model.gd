## Modèle de vol : portance et traînée réelles (Pennycuick, Modelling the Flying Bird, 2008),
## polaire parabolique CD = CD0 + CL²/(π·e·AR), décrochage au-delà de l'incidence critique,
## virage par inclinaison (la portance inclinée fournit la force centripète), battement = poussée
## limitée par la puissance musculaire disponible. Valeurs d'un fou à pieds rouges adulte.
##
## Indépendant du moteur : pas de nœud, pas de rendu. Testable sans fenêtre.
class_name FlightModel
extends RefCounted

const RHO := 1.225
const G := 9.81

# --- Morphologie ---
var mass := 1.0            # kg
var wing_area := 0.14      # m²
var aspect_ratio := 8.0
var oswald := 0.85
var cd0 := 0.012        # traînée de profil de l'aile (rapportée à la surface alaire)
var body_drag_area := 0.0035   # m² : surface de traînée du corps (ne change pas quand les ailes se replient)
var cl_alpha := 0.088      # par degré
var alpha0 := -2.0         # incidence de portance nulle (degrés)
var alpha_stall := 15.0
var alpha_min := -6.0
var alpha_max := 18.0     # on peut tirer au-delà du décrochage : c'est le risque
var flap_power := 32.0     # W
var flap_min_speed := 4.0
var max_bank := deg_to_rad(68.0)
var bank_rate := deg_to_rad(160.0)
var aoa_rate := 70.0       # degrés par seconde
var yaw_gain := 1.6
var pitch_gain := 0.8
var trim_aoa := 3.5

# --- Énergie ---
var energy := 100.0
var energy_max := 100.0
var flap_cost := 1.7
var glide_regen := 0.55

# --- État ---
var position := Vector3.ZERO
var velocity := Vector3(0.0, 0.0, -12.0)
var bank := 0.0                 # radians, positif = virage à droite
var aoa := 4.0                  # degrés
var forward := Vector3.FORWARD  # direction de la vitesse air
var lift_dir := Vector3.UP
var air_speed := 12.0
var heading := 0.0              # radians, 0 = -Z, positif vers +X
var flight_path_angle := 0.0    # radians
var stalled := false
var last_lift := 0.0
var last_drag := 0.0
var last_thrust := 0.0

# --- Commandes ---
var aim_yaw := 0.0
var aim_pitch := 0.0
var roll_input := 0.0
var flapping := false
var braking := false
var diving := false


static func dir_from_heading(h: float) -> Vector3:
	return Vector3(sin(h), 0.0, -cos(h))


static func heading_of(v: Vector3) -> float:
	return atan2(v.x, -v.z)


## Un pas de simulation. [param wind] est le vent local (m/s).
func step(dt: float, wind: Vector3) -> void:
	var v_air := velocity - wind
	air_speed = v_air.length()
	if air_speed < 0.05:
		v_air = forward * 0.05
		air_speed = 0.05
	forward = v_air / air_speed
	heading = heading_of(forward)
	flight_path_angle = asin(clampf(forward.y, -1.0, 1.0))

	# --- Pilotage : on vise une direction, l'oiseau s'incline et ajuste son incidence. ---
	var yaw_err := wrapf(aim_yaw - heading, -PI, PI)
	var bank_target := clampf(yaw_err * yaw_gain, -max_bank, max_bank) + roll_input * deg_to_rad(45.0)
	bank_target = clampf(bank_target, -deg_to_rad(80.0), deg_to_rad(80.0))
	var agility := clampf(air_speed / 10.0, 0.3, 1.2)
	bank = move_toward(bank, bank_target, bank_rate * agility * dt)

	var pitch_err := aim_pitch - flight_path_angle
	var aoa_target := trim_aoa + rad_to_deg(pitch_err) * pitch_gain
	if braking:
		aoa_target = alpha_max
	if diving:
		aoa_target = alpha_min + 1.0
	aoa_target = clampf(aoa_target, alpha_min, alpha_max)
	aoa = move_toward(aoa, aoa_target, aoa_rate * dt)

	# --- Aérodynamique ---
	var q := 0.5 * RHO * air_speed * air_speed
	var cl := cl_alpha * (aoa - alpha0)
	stalled = false
	if aoa > alpha_stall:
		var over := aoa - alpha_stall
		cl = cl_alpha * (alpha_stall - alpha0) * maxf(1.0 - over / 8.0, 0.3)
		stalled = true
	var cd := cd0 + cl * cl / (PI * oswald * aspect_ratio)
	var body_area := body_drag_area
	if braking:
		cd += 0.10          # ailes en parachute
		body_area *= 2.2    # pattes et queue déployées
	var area := wing_area
	if diving:
		area *= 0.55        # ailes repliées : moins de portance, moins de traînée d'aile
	last_lift = q * area * cl
	last_drag = q * (area * cd + body_area)

	var up0 := Vector3.UP - forward * forward.dot(Vector3.UP)
	if up0.length_squared() < 1e-6:
		up0 = Vector3.FORWARD
	up0 = up0.normalized()
	lift_dir = up0.rotated(forward, bank)

	var force := lift_dir * last_lift - forward * last_drag
	last_thrust = 0.0
	if flapping and energy > 0.0:
		last_thrust = flap_power / maxf(air_speed, flap_min_speed)
		force += forward * last_thrust
		energy = maxf(energy - flap_cost * dt, 0.0)
	else:
		energy = minf(energy + glide_regen * dt, energy_max)

	var acc := force / mass + Vector3(0.0, -G, 0.0)
	velocity += acc * dt
	position += velocity * dt


## Orientation du corps : le nez est relevé de l'incidence par rapport au vent relatif.
func body_basis() -> Basis:
	var right := forward.cross(lift_dir).normalized()
	var body_fwd := forward.rotated(right, deg_to_rad(aoa))
	var up := lift_dir.rotated(right, deg_to_rad(aoa))
	return Basis.looking_at(body_fwd, up)


## Finesse théorique au meilleur plané (L/D max) : pour les tests et l'équilibrage.
func best_glide_ratio() -> float:
	var k := 1.0 / (PI * oswald * aspect_ratio)
	var cd_parasite := cd0 + body_drag_area / wing_area
	return 0.5 / sqrt(cd_parasite * k)


## Vitesse de décrochage en palier (m/s).
func stall_speed() -> float:
	var cl_max := cl_alpha * (alpha_stall - alpha0)
	return sqrt(2.0 * mass * G / (RHO * wing_area * cl_max))
