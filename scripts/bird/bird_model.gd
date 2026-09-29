## Apparence de l'oiseau : le goéland de Dayvable (Sketchfab, CC-BY), squelette animé.
## L'animation d'origine (9,5 s) contient un cycle de battement et une tenue de plané : on en
## découpe trois animations (battement en boucle, plané, freinage ailes relevées) et on les mélange
## selon l'état du vol. Par-dessus, quelques retouches d'os : tête vers la visée, queue au freinage,
## ailes repliées au sol.
class_name BirdModel
extends Node3D

const MODEL := "res://assets/sketchfab/seagull.glb"
const WINGSPAN := 1.15          # m (le modèle fait 2,03 m d'envergure)
const FLAP_SPEED := 2.4         # vitesse de lecture du battement (cycle d'origine : 1,2 s)

var rig: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var flap_blend := 0.0
var brake_blend := 0.0
var dive_blend := 0.0
var fold_blend := 0.0
var _current := ""
var _bone := {}


func build() -> void:
	var scene: PackedScene = load(MODEL)
	rig = scene.instantiate()
	# Le modèle regarde vers -X, ailes le long de Z : on le tourne pour regarder vers -Z (avant Godot).
	var s := WINGSPAN / 2.03
	# L'origine du modèle est à la tête : on recule le corps pour que le centre soit à l'origine.
	rig.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0).scaled(Vector3.ONE * s), Vector3(0.0, -0.03, -0.40 * s))
	add_child(rig)
	player = rig.find_child("AnimationPlayer", true, false)
	for n in rig.find_children("*", "Skeleton3D", true, false):
		skeleton = n
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if player == null or skeleton == null:
		push_error("Goéland : squelette ou animation introuvable")
		return
	for b in skeleton.get_bone_count():
		_bone[skeleton.get_bone_name(b)] = b
	var src_name: String = player.get_animation_list()[0]
	var src := player.get_animation(src_name)
	var lib := AnimationLibrary.new()
	lib.add_animation("battement", _slice(src, 1.2, 2.4, true))
	lib.add_animation("plane", _slice(src, 4.5, 4.5, false))
	lib.add_animation("frein", _slice(src, 0.3, 0.3, false))
	player.add_animation_library("alize", lib)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("alize/plane")
	_current = "alize/plane"
	player.advance(0.0)


## Copie les clés d'une animation entre deux instants (durée nulle : une pose).
static func _slice(src: Animation, t0: float, t1: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = maxf(t1 - t0, 0.05)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for ti in src.get_track_count():
		var type := src.track_get_type(ti)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var t := a.add_track(type)
		a.track_set_path(t, src.track_get_path(ti))
		a.track_set_interpolation_type(t, src.track_get_interpolation_type(ti))
		if t1 - t0 < 0.01:
			# Une seule clé : la valeur interpolée à t0.
			_insert_at(a, t, type, src, ti, t0, 0.0)
			continue
		_insert_at(a, t, type, src, ti, t0, 0.0)
		for k in src.track_get_key_count(ti):
			var kt := src.track_get_key_time(ti, k)
			if kt > t0 and kt < t1:
				_insert_at(a, t, type, src, ti, kt, kt - t0)
		_insert_at(a, t, type, src, ti, t1, t1 - t0)
	return a


static func _insert_at(a: Animation, t: int, type: int, src: Animation, ti: int, src_time: float, dst_time: float) -> void:
	match type:
		Animation.TYPE_POSITION_3D:
			a.position_track_insert_key(t, dst_time, src.position_track_interpolate(ti, src_time))
		Animation.TYPE_ROTATION_3D:
			a.rotation_track_insert_key(t, dst_time, src.rotation_track_interpolate(ti, src_time))
		Animation.TYPE_SCALE_3D:
			a.scale_track_insert_key(t, dst_time, src.scale_track_interpolate(ti, src_time))
		_:
			pass


func _play(name: String, blend: float) -> void:
	if _current == name:
		return
	_current = name
	player.play(name, blend)


func update_pose(dt: float, bird: Node) -> void:
	if player == null:
		return
	var m: FlightModel = bird.model
	var flying: bool = bird.state == Bird.State.FLYING
	var want_flap := flying and m.flapping and m.energy > 0.0
	flap_blend = move_toward(flap_blend, 1.0 if want_flap else 0.0, 4.0 * dt)
	brake_blend = move_toward(brake_blend, 1.0 if (flying and m.braking) else 0.0, 5.0 * dt)
	dive_blend = move_toward(dive_blend, 1.0 if (flying and m.diving) else 0.0, 3.0 * dt)
	fold_blend = move_toward(fold_blend, 0.0 if flying else 1.0, 2.5 * dt)
	if want_flap:
		_play("alize/battement", 0.2)
		player.speed_scale = FLAP_SPEED
	elif flying and m.braking:
		_play("alize/frein", 0.25)
		player.speed_scale = 1.0
	else:
		_play("alize/plane", 0.35)
		player.speed_scale = 1.0
	player.advance(dt)

	# Retouches par-dessus l'animation (espace du squelette : avant = -X, gauche = +Z, haut = +Y).
	if _bone.has("Bn-Head_2") and flying:
		var yaw := clampf(wrapf(m.aim_yaw - m.heading, -PI, PI) * 0.25, deg_to_rad(-35.0), deg_to_rad(35.0))
		var pitch := -(m.aim_pitch - m.flight_path_angle) * 0.2
		_twist("Bn-Head_2", Vector3.UP, -yaw)
		_twist("Bn-Head_2", Vector3.FORWARD, pitch)   # axe Z du squelette = axe des ailes : tangage de la tête
	if _bone.has("Bn-Tail_14"):
		_twist("Bn-Tail_14", Vector3(0, 0, 1), -deg_to_rad(20.0) * brake_blend + deg_to_rad(6.0) * dive_blend)
	if fold_blend > 0.001:
		# Ailes repliées le long du corps : rabattues vers le bas et vers l'arrière.
		# D'abord le recul (+Z -> +X, l'arrière), puis un léger affaissement.
		_twist("Bn-L-Wing-1_8", Vector3(0, 1, 0), deg_to_rad(70.0) * fold_blend)
		_twist("Bn-L-Wing-1_8", Vector3(1, 0, 0), deg_to_rad(25.0) * fold_blend)
		_twist("Bn-R-Wing-1_12", Vector3(0, 1, 0), deg_to_rad(-70.0) * fold_blend)
		_twist("Bn-R-Wing-1_12", Vector3(1, 0, 0), deg_to_rad(-25.0) * fold_blend)
	elif dive_blend > 0.001:
		_twist("Bn-L-Wing-1_8", Vector3(0, 1, 0), deg_to_rad(-35.0) * dive_blend)
		_twist("Bn-R-Wing-1_12", Vector3(0, 1, 0), deg_to_rad(35.0) * dive_blend)


## Tourne un os autour d'un axe exprimé dans l'espace du squelette, en gardant sa position.
func _twist(bone_name: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 1e-4 or not _bone.has(bone_name):
		return
	var b: int = _bone[bone_name]
	var g := skeleton.get_bone_global_pose(b)
	var parent := skeleton.get_bone_parent(b)
	var pg := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var g2 := Transform3D(Basis(axis.normalized(), angle) * g.basis, g.origin)
	var local := pg.affine_inverse() * g2
	skeleton.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
