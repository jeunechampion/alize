## Vol automatique : enchaîne des manœuvres, mesure le comportement (finesse, montée, vitesse),
## prend des captures d'écran et écrit un rapport JSON. Lancé avec `-- --autotest`.
## Le rendu est coupé entre les captures pour que le test soit rapide même sans carte graphique.
extends Node

var main: Node
var bird: Bird
var tick := 0
var phase := ""
var report := {}
var shots: Array = []
var out_dir := ""
var _log: Array = []
var _glide_start := {}
var _climb_start := {}
var _max_speed := 0.0
var _dive_max_speed := 0.0
var _turn_start_heading := 0.0
var _turn_max_bank := 0.0
var _turn_time := -1.0
var _shot_pending := false
var _first_person_done := false


func start(p_main: Node) -> void:
	main = p_main
	bird = main.bird
	bird.input_enabled = false
	out_dir = Game.autotest_dir if Game.autotest_dir != "" else "res://autotest_out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	RenderingServer.render_loop_enabled = false
	report["seed"] = Game.seed_text
	report["island"] = main.generator.stats()
	report["island_fingerprint"] = main.generator.fingerprint()
	report["island_fingerprint_coarse"] = main.generator.fingerprint_coarse()
	report["model"] = {
		"best_glide_ratio_theory": bird.model.best_glide_ratio(),
		"stall_speed_theory": bird.model.stall_speed(),
	}
	print("[autotest] démarrage, sortie dans ", ProjectSettings.globalize_path(out_dir))


func _t() -> float:
	return tick / 60.0


func _physics_process(_dt: float) -> void:
	if _shot_pending:
		return
	var t := _t()
	var m := bird.model
	var flying := bird.state == Bird.State.FLYING
	if flying:
		_max_speed = maxf(_max_speed, m.velocity.length())

	if t < 1.5:
		_set_phase("plané initial")
		m.aim_yaw = main.spawn_heading
		m.aim_pitch = 0.0
		if tick == 60:
			if Game.shot_only:
				await _shoot("01_depart")
				_finish()
				return
			_shoot("01_depart")
	elif t < 13.5:
		_set_phase("plané rectiligne")
		m.aim_pitch = deg_to_rad(-4.0)
		if tick == 210:
			_glide_start = {"pos": m.position, "t": t, "energy": m.energy}
		if tick == 809:
			var dx := Vector2(m.position.x - _glide_start.pos.x, m.position.z - _glide_start.pos.z).length()
			var dy: float = _glide_start.pos.y - m.position.y
			report["glide"] = {
				"horizontal_m": dx, "descent_m": dy,
				"ratio": dx / maxf(dy, 0.01),
				"speed_ms": m.velocity.length(),
				"sink_ms": -m.velocity.y,
				"energy_gain": m.energy - _glide_start.energy,
			}
	elif t < 21.0:
		_set_phase("virage")
		if tick == 810:
			_turn_start_heading = m.heading
			m.aim_yaw = wrapf(m.heading + deg_to_rad(110.0), -PI, PI)
		m.aim_pitch = deg_to_rad(-3.0)
		_turn_max_bank = maxf(_turn_max_bank, absf(m.bank))
		if _turn_time < 0.0 and absf(wrapf(m.heading - _turn_start_heading, -PI, PI)) > deg_to_rad(100.0):
			_turn_time = t - 13.5
			report["turn"] = {"time_for_100deg_s": _turn_time, "max_bank_deg": rad_to_deg(_turn_max_bank), "speed_ms": m.velocity.length()}
		if tick == 1020:
			_shoot("02_virage")
	elif t < 29.0:
		_set_phase("battement")
		m.flapping = true
		m.aim_pitch = deg_to_rad(6.0)
		if tick == 1260:
			_climb_start = {"y": m.position.y, "energy": m.energy}
		if tick == 1500:
			_shoot("03_battement")
		if tick == 1739:
			report["flap"] = {
				"climb_m_in_8s": m.position.y - _climb_start.y,
				"climb_rate_ms": (m.position.y - _climb_start.y) / 8.0,
				"energy_used": _climb_start.energy - m.energy,
				"speed_ms": m.velocity.length(),
			}
	elif t < 37.0:
		_set_phase("piqué")
		m.flapping = false
		m.diving = true
		m.aim_pitch = deg_to_rad(-32.0)
		if m.position.y < 60.0:
			m.diving = false
			m.aim_pitch = deg_to_rad(15.0)
		_dive_max_speed = maxf(_dive_max_speed, m.velocity.length())
		if tick == 1980:
			_shoot("04_pique")
		if tick == 2219:
			report["dive"] = {"max_speed_ms": _dive_max_speed, "altitude_m": m.position.y}
	elif t < 45.0:
		_set_phase("ressource et freinage")
		m.diving = false
		m.aim_pitch = deg_to_rad(12.0)
		m.braking = t > 39.0 and t < 41.5
		if tick == 2460:
			_shoot("05_freinage")
		if tick == 2580 and not _first_person_done:
			_first_person_done = true
			main.cam.toggle_view()
		if tick == 2640:
			await _shoot("06_premiere_personne")
			main.cam.toggle_view()
	elif t < 60.0:
		_set_phase("thermique")
		# On vise le thermique de plage et on tourne dedans.
		var th: Thermal = main.wind.thermals[1]
		var to := Vector2(th.center.x - m.position.x, th.center.y - m.position.z)
		if to.length() > th.radius * 0.7:
			m.aim_yaw = FlightModel.heading_of(Vector3(to.x, 0.0, to.y))
		else:
			m.aim_yaw = wrapf(m.heading + deg_to_rad(60.0), -PI, PI)
		m.aim_pitch = deg_to_rad(-2.0)
		if bird.state != Bird.State.FLYING:
			m.flapping = true
			m.aim_pitch = deg_to_rad(10.0)
		else:
			m.flapping = m.position.y < 40.0
		if tick == 3300:
			_shoot("07_thermique")
	else:
		_finish()

	if flying and tick % 60 == 0:
		_log.append({"t": t, "phase": phase, "x": m.position.x, "y": m.position.y, "z": m.position.z,
			"speed": m.velocity.length(), "vy": m.velocity.y, "bank_deg": rad_to_deg(m.bank), "aoa": m.aoa,
			"energy": m.energy, "updraft": bird.last_updraft, "stalled": m.stalled, "state": bird.state_name()})
	tick += 1


func _set_phase(p: String) -> void:
	if p != phase:
		phase = p
		print("[autotest] t=%.1f  %s" % [_t(), p])


func _shoot(name: String) -> void:
	_shot_pending = true
	RenderingServer.render_loop_enabled = true
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	shots.append(path)
	print("[autotest] capture ", name, " ", img.get_size())
	RenderingServer.render_loop_enabled = false
	_shot_pending = false


func _finish() -> void:
	_shot_pending = true
	report["max_speed_ms"] = _max_speed
	report["distance_flown_m"] = bird.distance_flown
	report["final_state"] = bird.state_name()
	report["final_energy"] = bird.model.energy
	report["log"] = _log
	report["shots"] = shots
	report["render"] = {
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
	}
	var f := FileAccess.open("%s/report.json" % out_dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[autotest] rapport écrit. Finesse mesurée : %.1f" % report.get("glide", {}).get("ratio", -1.0))
	get_tree().quit()
