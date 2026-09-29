## Ciel physique (diffusion de Rayleigh et de Mie, voir Atmosphere et sky.gdshader),
## soleil à la position astronomique d'une latitude tropicale (Meeus 1991), brume de distance,
## cycle jour/nuit, et une couche de nuages.
class_name SkyDome
extends Node3D

const LATITUDE_DEG := 15.0   # latitude tropicale (nord)

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: WorldEnvironment
var sky_material: ShaderMaterial
var clouds: MeshInstance3D
var cloud_material: ShaderMaterial
var sun_dir := Vector3(0.0, 1.0, 0.0)   # pointe vers le soleil


func setup() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 1800.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 3.0
	sun.light_angular_distance = 0.6
	sun.light_energy = 1.3
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_energy = 0.0
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.shadow_enabled = false
	add_child(moon)

	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader")

	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if Game.autotest else Sky.PROCESS_MODE_INCREMENTAL

	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	# Lumière ambiante : couleur du ciel calculée par le même modèle que le shader (zénith + horizon),
	# identique dans tous les moteurs de rendu, plutôt que déduite de la carte de radiance.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.6, 0.85)
	e.ambient_light_sky_contribution = 0.0
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.3
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.72, 0.82, 0.92)
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.25
	e.fog_density = 0.00004
	e.fog_aerial_perspective = 0.55
	e.fog_sky_affect = 0.2
	e.fog_height = -100.0
	e.fog_height_density = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.03

	env = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = e
	add_child(env)

	_setup_clouds()
	update_sun()


func _setup_clouds() -> void:
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = load("res://shaders/clouds.gdshader")
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 1024
	tex.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 23
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.004
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	tex.noise = n
	cloud_material.set_shader_parameter("noise_tex", tex)
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000.0, 60000.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	clouds = MeshInstance3D.new()
	clouds.mesh = plane
	clouds.material_override = cloud_material
	clouds.position.y = 1900.0
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.name = "Clouds"
	add_child(clouds)


var cloud_time: float = 0.0


func _process(delta: float) -> void:
	Game.advance_time(delta)
	update_sun()
	cloud_time += delta
	if cloud_material:
		cloud_material.set_shader_parameter("cloud_time", cloud_time)
		cloud_material.set_shader_parameter("sun_dir", sun_dir)
		cloud_material.set_shader_parameter("sun_color", sun.light_color * clampf(sun.light_energy / 1.3, 0.05, 1.0))


func update_sun() -> void:
	sun_dir = Atmosphere.sun_direction(Game.time_of_day, LATITUDE_DEG)
	var elev := sun_dir.y
	var up_ref := Vector3.UP if absf(elev) < 0.98 else Vector3.BACK
	sun.basis = Basis.looking_at(-sun_dir, up_ref)
	var day := smoothstep(-0.03, 0.12, elev)
	# Couleur et intensité du soleil : transmittance de l'atmosphère (même modèle que le ciel).
	var tr := Atmosphere.sun_transmittance(sun_dir)
	var tmax: float = maxf(tr.x, maxf(tr.y, tr.z))
	var tint := Vector3(1, 1, 1) if tmax < 1e-4 else tr / tmax
	sun.light_color = Color(tint.x, tint.y, tint.z).linear_to_srgb()   # les Color du moteur sont en sRGB
	sun.light_energy = 1.15 * day * clampf(0.35 + 0.65 * tmax, 0.0, 1.0)
	if OS.get_environment("ALIZE_SUN") == "0":
		sun.light_energy = 0.0
	sun.shadow_enabled = elev > 0.02 and OS.get_environment("ALIZE_NOSHADOW") != "1"

	var night := 1.0 - smoothstep(-0.12, 0.05, elev)
	moon.basis = Basis.looking_at(sun_dir, up_ref)   # opposé au soleil, éclairage de lune symbolique
	moon.light_energy = 0.12 * night

	var e := env.environment
	# Brume de la couleur du ciel à l'horizon, à 90° du soleil (moyenne des deux côtés).
	var side := Vector3(-sun_dir.z, 0.0, sun_dir.x).normalized()
	var hz := (Atmosphere.atmosphere_color(Vector3(side.x, 0.03, side.z).normalized(), sun_dir) + Atmosphere.atmosphere_color(Vector3(-side.x, 0.03, -side.z).normalized(), sun_dir)) * 0.5
	hz = Vector3(1.0 - exp(-hz.x), 1.0 - exp(-hz.y), 1.0 - exp(-hz.z))   # compression douce
	var fog_col := Color(hz.x, hz.y, hz.z).lerp(Color(0.02, 0.03, 0.06), night)
	e.fog_light_color = fog_col.linear_to_srgb()
	var zen := Atmosphere.atmosphere_color(Vector3.UP, sun_dir)
	zen = Vector3(1.0 - exp(-zen.x), 1.0 - exp(-zen.y), 1.0 - exp(-zen.z))
	var amb := zen * 0.55 + hz * 0.45
	var amb_col := Color(amb.x, amb.y, amb.z).lerp(Color(0.05, 0.07, 0.14), night)
	e.ambient_light_color = amb_col.linear_to_srgb()
	e.ambient_light_energy = 1.0
	e.tonemap_exposure = 1.0 + 0.6 * night
