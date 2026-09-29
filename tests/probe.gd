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
		print("MODE ", mode, " lit ", img.get_pixel(760, 330), " dark ", img.get_pixel(520, 330), " center ", img.get_pixel(640, 360))
		get_tree().quit()
