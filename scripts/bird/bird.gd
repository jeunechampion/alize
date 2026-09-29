## L'oiseau du joueur : relie le modèle de vol au monde (vent, sol, mer), gère les états
## (vol, posé, à l'eau, sonné), les entrées et le corps animé.
class_name Bird
extends Node3D

signal crashed(hard: bool)
signal state_changed(new_state: int)

enum State { FLYING, LANDED, ON_WATER, STUNNED }

const MOUSE_SENSITIVITY := 0.0022
const CLEARANCE := 0.22

var model := FlightModel.new()
var state: int = State.FLYING
var wind: WindField
var generator: IslandGenerator
var ocean: Ocean
var body: BirdModel

var stun_timer := 0.0
var input_enabled := true
var mouse_captured := false
var distance_flown := 0.0
var max_altitude := 0.0
var last_updraft := 0.0
var ground_height := 0.0
var altitude_agl := 0.0
var time_on_water := 0.0
var time_on_ground := 0.0
var takeoff_timer := 0.0

var _land_heading := 0.0


func _ready() -> void:
	body = BirdModel.new()
	body.name = "Body"
	add_child(body)
	body.build()


func setup(p_wind: WindField, p_gen: IslandGenerator, p_ocean: Ocean) -> void:
	wind = p_wind
	generator = p_gen
	ocean = p_ocean


func spawn(pos: Vector3, heading: float, speed: float) -> void:
	model.position = pos
	model.velocity = FlightModel.dir_from_heading(heading) * speed
	model.forward = FlightModel.dir_from_heading(heading)
	model.heading = heading
	model.aim_yaw = heading
	model.aim_pitch = 0.0
	model.bank = 0.0
	model.aoa = 4.0
	model.energy = model.energy_max
	global_position = pos
	_set_state(State.FLYING)
	global_transform.basis = model.body_basis()


func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func capture_mouse(on: bool) -> void:
	mouse_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and mouse_captured:
		model.aim_yaw = wrapf(model.aim_yaw + event.relative.x * MOUSE_SENSITIVITY, -PI, PI)
		model.aim_pitch = clampf(model.aim_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-75.0), deg_to_rad(60.0))
	elif event is InputEventMouseButton and event.pressed and not mouse_captured:
		capture_mouse(true)


func _read_inputs(dt: float) -> void:
	if not input_enabled:
		return
	# Manette : stick gauche = direction, stick droit = aussi la direction (les deux marchent).
	var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X) + Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var jy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y) + Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(jx) > 0.15:
		model.aim_yaw = wrapf(model.aim_yaw + jx * 2.2 * dt, -PI, PI)
	if absf(jy) > 0.15:
		model.aim_pitch = clampf(model.aim_pitch - jy * 1.4 * dt, deg_to_rad(-75.0), deg_to_rad(60.0))
	model.flapping = Input.is_action_pressed("flap")
	model.braking = Input.is_action_pressed("brake") or Input.is_action_pressed("land")
	model.diving = Input.is_action_pressed("dive") and not model.braking
	model.roll_input = Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")


func _physics_process(dt: float) -> void:
	_read_inputs(dt)
	match state:
		State.FLYING:
			_fly(dt)
		State.STUNNED:
			_stunned(dt)
		State.LANDED:
			_grounded(dt)
		State.ON_WATER:
			_floating(dt)
	body.update_pose(dt, self)


func _fly(dt: float) -> void:
	var w := wind.sample(model.position)
	last_updraft = w.y
	if takeoff_timer > 0.0:
		# Phase de montée protégée juste après le décollage.
		takeoff_timer -= dt
		model.aim_pitch = maxf(model.aim_pitch, deg_to_rad(8.0))
	var before := model.position
	model.step(dt, w)
	distance_flown += before.distance_to(model.position)
	max_altitude = maxf(max_altitude, model.position.y)
	global_position = model.position
	global_transform.basis = model.body_basis()
	_check_surface()


func _surface_at(p: Vector3) -> Dictionary:
	ground_height = generator.height_at(p.x, p.z)
	var sea := ocean.surface_height(p.x, p.z, ocean.sea_time) if ocean else IslandGenerator.SEA_LEVEL
	var over_water := ground_height < IslandGenerator.SEA_LEVEL - 0.3
	var surf := sea if over_water else ground_height
	altitude_agl = p.y - surf
	return {"height": surf, "water": over_water}


func _check_surface() -> void:
	var p := model.position
	var s := _surface_at(p)
	var surf: float = s.height
	if p.y - CLEARANCE > surf:
		return
	var speed := model.velocity.length()
	model.position.y = surf + CLEARANCE
	global_position = model.position
	if s.water:
		if speed > 10.0:
			# Amerrissage brutal : la mer freine fort, l'oiseau flotte sonné.
			model.velocity *= 0.2
			crashed.emit(false)
		else:
			model.velocity *= 0.5
		_set_state(State.ON_WATER)
		time_on_water = 0.0
		_land_heading = model.heading
	else:
		var n := generator.normal_at(p.x, p.z)
		var vn := model.velocity.dot(n)
		var slope := 1.0 - n.y
		if speed < 10.0 and vn > -4.5 and slope < 0.45:
			_land()
		else:
			_crash(n, speed)


func _land() -> void:
	model.velocity = Vector3.ZERO
	time_on_ground = 0.0
	_land_heading = model.heading
	_set_state(State.LANDED)
	_orient_on_ground()


func _crash(n: Vector3, speed: float) -> void:
	var hard := speed > 22.0
	model.velocity = model.velocity.bounce(n) * 0.25 + n * 1.5
	model.bank = 0.0
	stun_timer = 1.2 if not hard else 2.5
	_set_state(State.STUNNED)
	crashed.emit(hard)


func _stunned(dt: float) -> void:
	stun_timer -= dt
	# Chute balistique freinée.
	model.velocity += Vector3(0.0, -FlightModel.G, 0.0) * dt
	model.velocity -= model.velocity * 0.6 * dt
	model.position += model.velocity * dt
	global_position = model.position
	var s := _surface_at(model.position)
	if model.position.y - CLEARANCE <= s.height:
		model.position.y = s.height + CLEARANCE
		global_position = model.position
		model.velocity = Vector3.ZERO
		if s.water:
			_set_state(State.ON_WATER)
			time_on_water = 0.0
		else:
			time_on_ground = 0.0
			_set_state(State.LANDED)
			_orient_on_ground()
	if stun_timer <= 0.0 and state == State.STUNNED:
		# On reprend le contrôle en l'air.
		model.forward = model.velocity.normalized() if model.velocity.length() > 1.0 else model.forward
		model.aim_yaw = FlightModel.heading_of(model.forward)
		model.aim_pitch = 0.0
		_set_state(State.FLYING)


func _orient_on_ground() -> void:
	var n := generator.normal_at(model.position.x, model.position.z)
	var fwd := FlightModel.dir_from_heading(_land_heading)
	fwd = fwd - n * fwd.dot(n)
	if fwd.length_squared() < 1e-4:
		return
	global_transform.basis = Basis.looking_at(fwd.normalized(), n)


func _grounded(dt: float) -> void:
	time_on_ground += dt
	model.energy = minf(model.energy + 6.0 * dt, model.energy_max)
	# Tourner sur place avec la visée, décoller avec un battement (après une courte pause).
	_land_heading = lerp_angle(_land_heading, model.aim_yaw, 3.0 * dt)
	_orient_on_ground()
	if model.flapping and model.energy > 5.0 and time_on_ground > 0.6:
		_take_off(false)


func _floating(dt: float) -> void:
	time_on_water += dt
	model.energy = minf(model.energy + 3.0 * dt, model.energy_max)
	var p := model.position
	var sea := ocean.surface_height(p.x, p.z, ocean.sea_time)
	model.position.y = sea + 0.16
	# Dérive avec le vent et le courant de surface ; échoué sur la plage, on est posé.
	var w := wind.sample(model.position)
	model.position += Vector3(w.x, 0.0, w.z) * 0.06 * dt
	global_position = model.position
	if generator.height_at(model.position.x, model.position.z) > IslandGenerator.SEA_LEVEL - 0.3:
		_land()
		return
	_land_heading = lerp_angle(_land_heading, model.aim_yaw, 2.0 * dt)
	var fwd := FlightModel.dir_from_heading(_land_heading)
	var tilt := (ocean.surface_height(p.x + 1.0, p.z, ocean.sea_time) - sea) * 0.35
	global_transform.basis = Basis.looking_at(fwd, Vector3(tilt, 1.0, 0.0).normalized())
	if model.flapping and model.energy > 5.0 and time_on_water > 0.6:
		_take_off(true)


func _take_off(from_water: bool) -> void:
	var w := wind.sample(model.position)
	var wind_h := Vector3(w.x, 0.0, w.z)
	# Comme un vrai oiseau, on décolle face au vent quand il souffle : la vitesse air compte.
	if wind_h.length() > 2.0:
		_land_heading = FlightModel.heading_of(-wind_h)
	var fwd := FlightModel.dir_from_heading(_land_heading)
	# Vitesse air de décollage : on emporte la dérive du vent.
	model.velocity = wind_h + fwd * (5.5 if from_water else 6.5) + Vector3(0.0, 2.8, 0.0)
	model.position.y += 0.5
	model.forward = (model.velocity - w).normalized()
	model.aim_yaw = _land_heading
	model.aim_pitch = deg_to_rad(8.0)
	model.bank = 0.0
	model.aoa = 10.0
	takeoff_timer = 1.5
	global_position = model.position
	_set_state(State.FLYING)


func state_name() -> String:
	match state:
		State.FLYING:
			return "vol"
		State.LANDED:
			return "posé"
		State.ON_WATER:
			return "à l'eau"
		State.STUNNED:
			return "sonné"
	return ""
