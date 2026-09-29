## Corps de l'oiseau, construit par primitives (aucune ressource externe), et son animation :
## battement, plané, freinage ailes en parachute, piqué ailes repliées.
## Fou à pieds rouges, forme blanche : corps blanc, rémiges noires, bec bleu pâle, pieds rouges.
class_name BirdMesh
extends Node3D

const FLAP_HZ := 3.4

var wing_l: Node3D
var wing_r: Node3D
var outer_l: Node3D
var outer_r: Node3D
var tail: Node3D
var head: Node3D
var flap_phase := 0.0
var flap_blend := 0.0     # 0 = plané, 1 = battement
var brake_blend := 0.0
var dive_blend := 0.0
var _sway_t := 0.0

var mat_white: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_beak: StandardMaterial3D
var mat_feet: StandardMaterial3D


static func _mat(color: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func build() -> void:
	mat_white = _mat(Color(0.96, 0.96, 0.94))
	mat_dark = _mat(Color(0.12, 0.11, 0.11))
	mat_beak = _mat(Color(0.62, 0.74, 0.82), 0.5)
	mat_feet = _mat(Color(0.88, 0.22, 0.18), 0.6)

	# Corps : ellipsoïde allongé selon -Z.
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.062
	body_mesh.height = 0.34
	body_mesh.radial_segments = 24
	body_mesh.rings = 12
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = mat_white
	body.rotation_degrees.x = 90.0
	add_child(body)

	# Tête et bec.
	head = Node3D.new()
	head.position = Vector3(0.0, 0.035, -0.165)
	add_child(head)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.046
	head_mesh.height = 0.092
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head_mesh
	head_mi.material_override = mat_white
	head.add_child(head_mi)
	var beak_mesh := CylinderMesh.new()
	beak_mesh.top_radius = 0.004
	beak_mesh.bottom_radius = 0.02
	beak_mesh.height = 0.1
	beak_mesh.radial_segments = 10
	var beak := MeshInstance3D.new()
	beak.mesh = beak_mesh
	beak.material_override = mat_beak
	beak.rotation_degrees.x = -90.0
	beak.position = Vector3(0.0, -0.008, -0.085)
	head.add_child(beak)
	# Yeux.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.008
	eye_mesh.height = 0.016
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = mat_dark
		eye.position = Vector3(sx * 0.03, 0.012, -0.03)
		head.add_child(eye)

	# Queue.
	tail = Node3D.new()
	tail.position = Vector3(0.0, 0.0, 0.16)
	add_child(tail)
	_box(Vector3(0.075, 0.008, 0.13), Vector3(0.0, 0.0, 0.06), mat_white, tail)
	_box(Vector3(0.06, 0.009, 0.035), Vector3(0.0, 0.0, 0.115), mat_dark, tail)

	# Ailes : pivot d'épaule -> aile interne -> pivot de coude -> aile externe.
	wing_l = _make_wing(-1.0)
	wing_r = _make_wing(1.0)

	# Pattes repliées sous le corps.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.025, 0.008, 0.04), Vector3(sx * 0.02, -0.05, 0.06), mat_feet, self)


func _make_wing(side: float) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(side * 0.045, 0.03, -0.02)
	add_child(shoulder)
	# Aile interne (bras) : blanche, bord de fuite sombre.
	_box(Vector3(0.24, 0.012, 0.15), Vector3(side * 0.12, 0.0, 0.0), mat_white, shoulder)
	_box(Vector3(0.24, 0.004, 0.04), Vector3(side * 0.12, 0.0075, 0.058), mat_dark, shoulder)
	_box(Vector3(0.24, 0.004, 0.04), Vector3(side * 0.12, -0.0075, 0.058), mat_dark, shoulder)
	var elbow := Node3D.new()
	elbow.position = Vector3(side * 0.24, 0.0, 0.0)
	shoulder.add_child(elbow)
	# Aile externe (main) : rémiges noires, plus étroite vers la pointe.
	_box(Vector3(0.20, 0.01, 0.11), Vector3(side * 0.10, 0.0, 0.01), mat_white, elbow)
	_box(Vector3(0.20, 0.004, 0.055), Vector3(side * 0.10, 0.0065, 0.04), mat_dark, elbow)
	_box(Vector3(0.20, 0.004, 0.055), Vector3(side * 0.10, -0.0065, 0.04), mat_dark, elbow)
	_box(Vector3(0.09, 0.011, 0.07), Vector3(side * 0.245, 0.0, 0.02), mat_dark, elbow)
	if side < 0.0:
		outer_l = elbow
	else:
		outer_r = elbow
	return shoulder


## Pose des ailes selon l'état du vol.
func update_pose(dt: float, bird: Node) -> void:
	var m: FlightModel = bird.model
	var flying: bool = bird.state == Bird.State.FLYING
	var want_flap := 1.0 if (flying and m.flapping and m.energy > 0.0) else 0.0
	flap_blend = move_toward(flap_blend, want_flap, 4.0 * dt)
	brake_blend = move_toward(brake_blend, 1.0 if (flying and m.braking) else 0.0, 5.0 * dt)
	dive_blend = move_toward(dive_blend, 1.0 if (flying and m.diving) else 0.0, 3.0 * dt)
	_sway_t += dt
	if flap_blend > 0.0:
		flap_phase += TAU * FLAP_HZ * dt
	else:
		# revenir doucement à la position de plané
		flap_phase = lerpf(flap_phase, roundf(flap_phase / TAU) * TAU, 3.0 * dt)

	var stroke := sin(flap_phase)
	var flap_angle := stroke * 42.0                      # degrés, + = aile relevée
	var glide_angle := 7.0 + sin(_sway_t * 1.3) * 2.5     # dièdre du plané
	var rest_angle := 0.0
	if not flying:
		rest_angle = 20.0
	var base_angle := lerpf(glide_angle, flap_angle, flap_blend)
	base_angle = lerpf(base_angle, rest_angle, 0.0 if flying else 1.0)
	base_angle = lerpf(base_angle, 28.0, brake_blend)      # ailes relevées en parachute
	base_angle = lerpf(base_angle, -12.0, dive_blend)      # ailes plaquées

	var sweep := lerpf(0.0, -48.0, dive_blend) + lerpf(0.0, 18.0, brake_blend)   # recul des ailes
	if not flying:
		sweep = -35.0
	var elbow_fold := lerpf(-4.0, -12.0, flap_blend) + lerpf(0.0, -70.0, dive_blend) + (-45.0 if not flying else 0.0)
	var outer_lag := sin(flap_phase - 0.7) * 30.0 * flap_blend

	# Rotation autour de l'axe Z (avant-arrière) : lever l'aile. Signe opposé à droite et à gauche.
	wing_l.rotation_degrees = Vector3(0.0, -sweep, -base_angle)
	wing_r.rotation_degrees = Vector3(0.0, sweep, base_angle)
	outer_l.rotation_degrees = Vector3(0.0, -elbow_fold, -outer_lag * 0.6 - lerpf(0.0, 8.0, dive_blend))
	outer_r.rotation_degrees = Vector3(0.0, elbow_fold, outer_lag * 0.6 + lerpf(0.0, 8.0, dive_blend))

	# Queue : s'ouvre et se baisse au freinage, se relève au piqué.
	tail.rotation_degrees.x = lerpf(2.0, 22.0, brake_blend) - lerpf(0.0, 8.0, dive_blend)
	tail.scale.x = 1.0 + 0.6 * brake_blend + 0.25 * absf(sin(m.bank)) * (1.0 if flying else 0.0)
	# Tête : regarde vers la visée, légèrement.
	if flying:
		head.rotation_degrees.y = clampf(rad_to_deg(wrapf(m.aim_yaw - m.heading, -PI, PI)) * 0.25, -35.0, 35.0)
		head.rotation_degrees.x = -rad_to_deg(m.aim_pitch - m.flight_path_angle) * 0.2
