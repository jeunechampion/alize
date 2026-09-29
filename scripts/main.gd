## Scène principale : construit le monde depuis la seed, place l'oiseau, gère les touches globales.
extends Node3D

var generator: IslandGenerator
var island: Island
var vegetation: Vegetation
var ocean: Ocean
var sky: SkyDome
var wind: WindField
var bird: Bird
var cam: BirdCamera
var hud: Hud
var wind_audio: WindAudio
var thermal_visuals: Array = []
var spawn_pos := Vector3.ZERO
var spawn_heading := 0.0
var loading_label: Label
var autotest: Node


func _ready() -> void:
	loading_label = Label.new()
	loading_label.text = "L'île se forme..."
	loading_label.set_anchors_preset(Control.PRESET_CENTER)
	loading_label.add_theme_font_size_override("font_size", 28)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.add_child(loading_label)
	add_child(layer)
	await get_tree().process_frame
	await get_tree().process_frame
	build_world(Game.world_seed)
	layer.queue_free()
	if Game.autotest:
		autotest = load("res://scripts/autotest.gd").new()
		add_child(autotest)
		autotest.call("start", self)
	else:
		bird.capture_mouse(true)
		hud.flash("Alizé — premier vol. H pour l'aide.", 5.0)


func build_world(seed_value: int) -> void:
	var t0 := Time.get_ticks_msec()
	for c in [island, vegetation, ocean, sky, bird, cam, hud, wind_audio]:
		if c:
			c.queue_free()
	for tv in thermal_visuals:
		tv.queue_free()
	thermal_visuals.clear()

	generator = IslandGenerator.new(seed_value)
	generator.generate()
	var t1 := Time.get_ticks_msec()

	island = Island.new()
	island.name = "Island"
	add_child(island)
	island.build(generator)
	var t2 := Time.get_ticks_msec()

	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.build(generator, seed_value, Vector2(-1.0, 0.25))

	ocean = Ocean.new()
	ocean.name = "Ocean"
	add_child(ocean)
	ocean.setup(island.height_texture, generator)

	sky = SkyDome.new()
	sky.name = "Sky"
	add_child(sky)
	sky.setup()

	wind = WindField.new(generator)
	_place_thermals()

	bird = Bird.new()
	bird.name = "Bird"
	add_child(bird)
	bird.setup(wind, generator, ocean)
	bird.crashed.connect(_on_bird_crashed)
	bird.state_changed.connect(_on_bird_state)

	cam = BirdCamera.new()
	cam.name = "CameraRig"
	add_child(cam)
	cam.setup(bird)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(bird)

	wind_audio = WindAudio.new()
	wind_audio.name = "WindAudio"
	add_child(wind_audio)
	wind_audio.setup(bird)

	_choose_spawn()
	respawn()
	var t3 := Time.get_ticks_msec()
	print("Monde %d prêt : relief %d ms, maillage %d ms, reste %d ms. %s" % [seed_value, t1 - t0, t2 - t1, t3 - t2, str(generator.stats())])


## Départ : au-dessus du lagon, à 900 m de la côte, face au volcan.
func _choose_spawn() -> void:
	var center: Vector2 = generator.params.center
	var vpos: Vector2 = generator.params.volcano_pos
	var dir := (center - vpos).normalized()   # on part du côté opposé au volcan pour le voir en face
	var coast := _find_coast(center, dir)
	var start := coast + dir * 900.0
	spawn_pos = Vector3(start.x, 240.0, start.y)
	spawn_heading = FlightModel.heading_of(Vector3(-dir.x, 0.0, -dir.y))


## Premier point le long d'un rayon depuis le centre où le sol passe sous la mer.
func _find_coast(from: Vector2, dir: Vector2) -> Vector2:
	var p := from
	for i in 400:
		p += dir * 10.0
		if generator.height_at(p.x, p.y) < IslandGenerator.SEA_LEVEL:
			return p
	return p


func _place_thermals() -> void:
	wind.thermals.clear()
	var vpos: Vector2 = generator.params.volcano_pos
	var center: Vector2 = generator.params.center
	# Grand thermique sur le flanc ensoleillé (sud-est) du volcan, à mi-pente.
	var flank := vpos + Vector2(0.6, 0.7).normalized() * float(generator.params.volcano_radius) * 0.55
	var flank_h := generator.height_at(flank.x, flank.y)
	wind.thermals.append(Thermal.new(flank, flank_h, flank_h + 1500.0, 130.0, 4.2))
	# Thermique de plage, du côté du départ.
	var dir := (center - vpos).normalized()
	var coast := _find_coast(center, dir)
	var beach := coast - dir * 70.0
	var beach_h := generator.height_at(beach.x, beach.y)
	wind.thermals.append(Thermal.new(beach, beach_h, beach_h + 800.0, 80.0, 2.6))
	# Un troisième au-dessus des collines du centre.
	var hill := center + Vector2(-dir.y, dir.x) * 500.0
	var hill_h := generator.height_at(hill.x, hill.y)
	if hill_h > 5.0:
		wind.thermals.append(Thermal.new(hill, hill_h, hill_h + 1100.0, 100.0, 3.2))
	for t in wind.thermals:
		var tv := ThermalVisual.new()
		add_child(tv)
		tv.setup(t)
		thermal_visuals.append(tv)


var _respawn_serial := 0


func respawn() -> void:
	_respawn_serial += 1
	bird.spawn(spawn_pos, spawn_heading, 13.0)
	cam.snap()


func _on_bird_crashed(hard: bool) -> void:
	if hard:
		hud.flash("Trop vite... L'oiseau se réveille au point de départ.", 4.0)
		var serial := _respawn_serial
		await get_tree().create_timer(2.0).timeout
		if serial == _respawn_serial:   # pas de double réapparition si R a déjà été pressé
			respawn()
	else:
		hud.flash("Aïe.", 1.5)


func _on_bird_state(s: int) -> void:
	if s == Bird.State.LANDED:
		hud.flash("Posé. Espace pour repartir.", 3.0)
	elif s == Bird.State.ON_WATER:
		hud.flash("À l'eau. Espace pour décoller.", 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("time_speed"):
		Game.cycle_time_speed()
	elif event.is_action_pressed("reset"):
		respawn()
	elif event.is_action_pressed("camera_toggle"):
		cam.toggle_view()
	elif event.is_action_pressed("help"):
		hud.show_help = not hud.show_help
	elif event.is_action_pressed("release_mouse"):
		bird.capture_mouse(false)
	elif event.is_action_pressed("new_seed"):
		Game.set_seed_text(str((Game.world_seed * 1103515245 + 12345) & 0x7FFFFFFF))
		build_world(Game.world_seed)
		hud.flash("Nouvelle île : seed %s" % Game.seed_text, 4.0)
	elif event.is_action_pressed("screenshot"):
		var img := get_viewport().get_texture().get_image()
		var path := "user://capture_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
		img.save_png(path)
		hud.flash("Capture enregistrée", 2.0)


func _process(_dt: float) -> void:
	if ocean and cam:
		ocean.follow(cam.camera.global_position)
