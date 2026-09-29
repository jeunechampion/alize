## Catalogue des modèles : chaque espèce posée en ligne sur un sol plat, capture d'écran.
## xvfb-run godot --path . --rendering-method gl_compatibility tests/catalog.tscn -- --out=/tmp/x.png [--species=nom] [--time=h]
extends Node3D

var frames := 0
var out_path := "user://catalog.png"
var only := ""
var rows: Array = []
var with_impostors := false
var bird_mode := false
var far_view := 1.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.get_slice("=", 1)
		elif a.begins_with("--species="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--time="):
			Game.time_of_day = float(a.get_slice("=", 1))
		elif a == "--impostors":
			with_impostors = true
		elif a == "--bird":
			bird_mode = true
		elif a.begins_with("--far="):
			far_view = float(a.get_slice("=", 1))
	var sky := SkyDome.new()
	add_child(sky)
	sky.setup()
	# Sol
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.5, 0.35)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)

	if bird_mode:
		_bird_catalog()
		return
	var names: Array = Vegetation.SPECIES.keys() if only == "" else [only]
	var imp_mats := Vegetation.load_impostor_materials() if with_impostors else {}
	var quad := Vegetation.make_impostor_quad()
	var x := 0.0
	var max_h := 0.0
	for name in names:
		var s: Dictionary = Vegetation.SPECIES[name]
		var opts := {"scale": s.scale}
		if s.has("include"):
			opts["include"] = s.include
		var m := AssetLibrary.get_model(s.path, opts)
		if m.is_empty():
			continue
		var r: float = maxf(m.radius, 1.0)
		x += r
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = m.mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(0.0, m.height, s.sway, s.flutter))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		rows.append({"name": name, "x": x, "h": m.height, "r": r, "tris": m.tris})
		max_h = maxf(max_h, m.height)
		x += r + 1.5
		if with_impostors and imp_mats.has(name):
			# Le même arbre en imposteur, juste à côté (même orientation).
			x += r
			var mm2 := MultiMesh.new()
			mm2.transform_format = MultiMesh.TRANSFORM_3D
			mm2.use_colors = true
			mm2.use_custom_data = true
			mm2.mesh = quad
			mm2.instance_count = 1
			mm2.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
			mm2.set_instance_color(0, Color.WHITE)
			var mmi2 := MultiMeshInstance3D.new()
			mmi2.multimesh = mm2
			mmi2.material_override = imp_mats[name]
			mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi2)
			x += r + 1.5
	var cam := Camera3D.new()
	add_child(cam)
	if names.size() == 1:
		var h: float = rows[0].h
		var r: float = rows[0].r
		var cx: float = rows[0].x + (r * 2.0 + 1.5 if with_impostors else 0.0)
		cam.position = Vector3(cx + r * 0.3, h * (0.55 + far_view * 0.4), maxf(r, h * 0.6) * (2.4 + 1.6 * far_view) * (2.0 if with_impostors else 1.0))
		cam.look_at(Vector3(cx, h * 0.45, 0))
		cam.fov = 45.0
	else:
		cam.position = Vector3(x * 0.5, max_h * 0.9, x * 0.62)
		cam.look_at(Vector3(x * 0.5, max_h * 0.3, 0))
		cam.fov = 60.0
	RenderingServer.global_shader_parameter_set("wind_time", 0.0)
	for r in rows:
		print("%-16s %6d tris  %5.1f m de haut  rayon %4.1f m" % [r.name, r.tris, r.h, r.r])


## L'oiseau sous quatre poses : plané, battement, freinage, posé.
func _bird_catalog() -> void:
	var fake := Node.new()
	fake.set_script(load("res://tests/fake_bird.gd"))
	add_child(fake)
	var poses := ["plane", "battement", "frein", "pose"]
	for i in poses.size():
		var bm := BirdModel.new()
		add_child(bm)
		bm.build()
		bm.position = Vector3(i * 1.6, 1.0, 0.0)
		bm.rotation_degrees = Vector3(0.0, 150.0, 0.0)
		fake.set("pose", poses[i])
		for k in 40:
			bm.update_pose(1.0 / 60.0, fake)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(2.4, 1.6, 3.2)
	cam.look_at(Vector3(2.4, 0.9, 0.0))
	cam.fov = 50.0


func _process(_dt: float) -> void:
	frames += 1
	if frames == 6:
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_path)
		print("catalogue écrit : ", out_path)
		get_tree().quit()
