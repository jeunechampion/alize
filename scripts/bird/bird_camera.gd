## Caméra de vol : 3e personne derrière l'oiseau, orientée par la visée (souris), avec du lissage,
## un champ de vision qui s'ouvre avec la vitesse et un léger roulis. 1re personne en option (V).
class_name BirdCamera
extends Node3D

var camera: Camera3D
var bird: Bird
var first_person := false
var _offset := Vector3.ZERO
var _look_offset := Vector3.ZERO
var _fov := 72.0
var _roll := 0.0
var initialized := false

const DIST := 3.4
const HEIGHT := 0.75
const LOOKAHEAD := 7.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 160000.0
	camera.fov = _fov
	camera.current = true
	add_child(camera)


func setup(p_bird: Bird) -> void:
	bird = p_bird


func snap() -> void:
	initialized = false


func toggle_view() -> void:
	first_person = not first_person
	initialized = false


func _process(dt: float) -> void:
	if bird == null:
		return
	var m := bird.model
	var flying := bird.state == Bird.State.FLYING
	var aim_dir := FlightModel.dir_from_heading(m.aim_yaw)
	aim_dir = Vector3(aim_dir.x * cos(m.aim_pitch), sin(m.aim_pitch), aim_dir.z * cos(m.aim_pitch)).normalized()

	if first_person:
		var head_pos: Vector3 = bird.global_transform * Vector3(0.0, 0.06, -0.14)
		var fwd: Vector3 = -bird.global_transform.basis.z
		var up: Vector3 = bird.global_transform.basis.y
		camera.global_transform = Transform3D(Basis.looking_at(fwd, up), head_pos)
		camera.fov = lerpf(camera.fov, 85.0, 4.0 * dt)
		return

	var target_pos: Vector3 = bird.global_position - aim_dir * DIST + Vector3.UP * HEIGHT
	var target_look: Vector3 = bird.global_position + aim_dir * LOOKAHEAD
	if not flying:
		# Posé : la caméra tourne autour de l'oiseau, un peu plus haut.
		var around := FlightModel.dir_from_heading(m.aim_yaw)
		target_pos = bird.global_position - around * 2.2 + Vector3.UP * 0.9
		target_look = bird.global_position + around * 3.0
	# Ne pas passer sous le sol ni sous les vagues.
	var floor_h: float = maxf(bird.generator.height_at(target_pos.x, target_pos.z) + 0.6, IslandGenerator.SEA_LEVEL + 2.2)
	target_pos.y = maxf(target_pos.y, floor_h)

	# On lisse le décalage par rapport à l'oiseau, pas sa position : pas de retard à grande vitesse.
	var target_offset := target_pos - bird.global_position
	var target_look_offset := target_look - bird.global_position
	if not initialized:
		_offset = target_offset
		_look_offset = target_look_offset
		initialized = true
	else:
		var k_pos := 1.0 - exp(-7.0 * dt)
		var k_look := 1.0 - exp(-10.0 * dt)
		_offset = _offset.lerp(target_offset, k_pos)
		_look_offset = _look_offset.lerp(target_look_offset, k_look)
	var _pos := bird.global_position + _offset
	var _look := bird.global_position + _look_offset
	# Le décalage lissé ne doit jamais mettre la caméra sous le sol ni sous l'eau.
	var floor_now: float = maxf(bird.generator.height_at(_pos.x, _pos.z) + 0.6, IslandGenerator.SEA_LEVEL + 1.2)
	if _pos.y < floor_now:
		_pos.y = floor_now
		_offset = _pos - bird.global_position

	var speed := m.velocity.length() if flying else 0.0
	var target_fov := 72.0 + clampf((speed - 10.0) * 0.9, 0.0, 22.0)
	_fov = lerpf(_fov, target_fov, 3.0 * dt)
	camera.fov = _fov
	_roll = lerpf(_roll, m.bank * 0.22 if flying else 0.0, 4.0 * dt)

	var fwd := (_look - _pos).normalized()
	var up := Vector3.UP.rotated(fwd, _roll)
	camera.global_transform = Transform3D(Basis.looking_at(fwd, up), _pos)
