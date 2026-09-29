extends Node3D
var frames := 0
var mode := 0
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--mode="): mode = int(a.get_slice("=", 1))
	Game.time_of_day = 8.5
	var sky := SkyDome.new()
	add_child(sky)
	sky.setup()
	var e := sky.env.environment
	sky.sun.light_energy = 0.0
	if mode >= 1: e.fog_enabled = false
	if mode >= 2: e.glow_enabled = false
	if mode >= 3: e.adjustment_enabled = false
	if mode >= 4: e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if mode >= 5: e.background_mode = Environment.BG_COLOR
	if mode == 6: e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; e.adjustment_enabled = true; e.glow_enabled = true; e.fog_enabled = true; e.background_mode = Environment.BG_SKY
	if mode == 7: e.tonemap_mode = Environment.TONE_MAPPER_AGX; e.adjustment_enabled = true; e.glow_enabled = true; e.fog_enabled = true; e.background_mode = Environment.BG_SKY
	if mode == 8: e.tonemap_mode = Environment.TONE_MAPPER_REINHARDT; e.adjustment_enabled = true; e.glow_enabled = true; e.fog_enabled = true; e.background_mode = Environment.BG_SKY
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2, 6)
	cam.look_at(Vector3.ZERO)
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	if mode == 20:
		var bm := BirdMesh.new()
		add_child(bm)
		bm.build()
		bm.rotation_degrees = Vector3(0.0, 35.0, 0.0)
		cam.position = Vector3(0.75, 0.45, 1.1)
		cam.look_at(Vector3(0.0, 0.0, 0.0))
		mesh.visible = false
	elif mode >= 11:
		var trng := RandomNumberGenerator.new()
		trng.seed = 5
		mesh.mesh = TreeBuilder.build_broadleaf(trng, 9.0, 4.5)
		mesh.position = Vector3(0, -4.5, 0)
		mesh.scale = Vector3.ONE * 0.35
		cam.position = Vector3(0, 0.5, 7)
		cam.look_at(Vector3(0, 0, 0))
		if mode == 13 or mode == 14 or mode == 15:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = (mode == 13 or mode == 15)
			mm.use_colors = (mode == 15)
			mm.mesh = mesh.mesh
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.35), Vector3(0, -4.5, 0)))
			if mode == 13 or mode == 15:
				mm.set_instance_custom_data(0, Color(1.0, 9.0, 0.0, 0.0))
			if mode == 15:
				mm.set_instance_color(0, Color(1, 1, 1, 1))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var vm2 := ShaderMaterial.new()
			vm2.shader = load("res://shaders/vegetation.gdshader")
			mmi.material_override = vm2
			add_child(mmi)
			mesh.visible = false
		if mode == 11:
			var vm := ShaderMaterial.new()
			vm.shader = load("res://shaders/vegetation.gdshader")
			mesh.material_override = vm
		else:
			var sm2 := StandardMaterial3D.new()
			sm2.vertex_color_use_as_albedo = true
			sm2.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material_override = sm2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.52, 0.22)
	mesh.material_override = mat
	if mode == 9 or mode == 10:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/terrain.gdshader")
		var detail := NoiseTexture2D.new()
		detail.width = 64; detail.height = 64; detail.noise = FastNoiseLite.new()
		sm.set_shader_parameter("detail_noise", detail)
		sm.set_shader_parameter("sea_level", -100.0)
		mesh.material_override = sm
		if mode == 10:
			sky.sun.light_energy = 1.15
	add_child(mesh)
func _process(_d: float) -> void:
	frames += 1
	if frames == 8:
		var sky: SkyDome = get_child(0)
		var e := sky.env.environment
		print("MODE ", mode, " amb=", e.ambient_light_color, " energy=", e.ambient_light_energy, " src=", e.ambient_light_source, " mix=", e.ambient_light_sky_contribution)
	if frames == 10:
		var img := get_viewport().get_texture().get_image()
		print("MODE ", mode, " lit ", img.get_pixel(760, 330), " dark ", img.get_pixel(520, 330), " center ", img.get_pixel(640, 360), " up ", img.get_pixel(640, 250))
		if mode >= 11:
			img.save_png("/home/claude/shotq/probe_%d.png" % mode)
	if frames == 3 and mode == 20:
		var bm: BirdMesh = get_child(get_child_count() - 1)
		bm.flap_phase = 0.9
		bm.flap_blend = 1.0
		get_tree().quit()
