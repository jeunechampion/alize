## Océan : un plan dense qui suit la caméra (vagues) et un plan lointain jusqu'à l'horizon.
class_name Ocean
extends Node3D

const NEAR_SIZE := 4000.0
const NEAR_SUBDIV := 400
const FAR_SIZE := 400000.0

var material: ShaderMaterial
var far_material: ShaderMaterial
var near: MeshInstance3D
var far: MeshInstance3D
var generator: IslandGenerator
var wave_scale := 1.0
var _near_spacing: float = NEAR_SIZE / float(NEAR_SUBDIV + 1)
var wind_dir := Vector2(-1.0, 0.25)
var sea_time: float = 0.0


func setup(height_tex: Texture2D, gen: IslandGenerator) -> void:
	generator = gen
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/ocean.gdshader")
	material.set_shader_parameter("height_tex", height_tex)
	material.set_shader_parameter("extent", IslandGenerator.EXTENT)
	material.set_shader_parameter("tex_size", float(IslandGenerator.SIZE))
	material.set_shader_parameter("wave_scale", wave_scale)
	material.set_shader_parameter("sea_level", IslandGenerator.SEA_LEVEL)
	material.set_shader_parameter("deep_sea", IslandGenerator.DEEP_SEA)
	material.set_shader_parameter("wind_dir", wind_dir)
	var detail := NoiseTexture2D.new()
	detail.width = 512
	detail.height = 512
	detail.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 11
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.fractal_octaves = 3
	detail.noise = n
	material.set_shader_parameter("detail_noise", detail)

	var near_mesh := PlaneMesh.new()
	near_mesh.size = Vector2(NEAR_SIZE, NEAR_SIZE)
	near_mesh.subdivide_width = NEAR_SUBDIV
	near_mesh.subdivide_depth = NEAR_SUBDIV
	near = MeshInstance3D.new()
	near.mesh = near_mesh
	near.material_override = material
	near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	near.extra_cull_margin = 16.0
	near.name = "Near"
	add_child(near)

	var far_mesh := PlaneMesh.new()
	far_mesh.size = Vector2(FAR_SIZE, FAR_SIZE)
	far_mesh.subdivide_width = 40
	far_mesh.subdivide_depth = 40
	far = MeshInstance3D.new()
	far.mesh = far_mesh
	# Le plan lointain est plat (pas de vagues) et sous les creux du plan proche.
	far_material = material.duplicate()
	far_material.set_shader_parameter("wave_scale", 0.0)
	far.material_override = far_material
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.position.y = -2.5
	far.name = "Far"
	add_child(far)


func _process(delta: float) -> void:
	sea_time += delta
	if material:
		material.set_shader_parameter("sea_time", sea_time)
	if far_material:
		far_material.set_shader_parameter("sea_time", sea_time)


## Le plan dense suit la caméra, calé sur la grille de ses sommets (pas de flottement).
func follow(cam_pos: Vector3) -> void:
	var sx := roundf(cam_pos.x / _near_spacing) * _near_spacing
	var sz := roundf(cam_pos.z / _near_spacing) * _near_spacing
	near.position = Vector3(sx, IslandGenerator.SEA_LEVEL, sz)
	var fs := 5000.0
	far.position = Vector3(roundf(cam_pos.x / fs) * fs, IslandGenerator.SEA_LEVEL - 2.5, roundf(cam_pos.z / fs) * fs)


## Facteur d'amplitude des vagues en un point : amortissement dans les eaux peu profondes
## (même formule que le vertex shader).
func wave_factor(x: float, z: float) -> float:
	var depth := maxf(IslandGenerator.SEA_LEVEL - generator.height_at(x, z), 0.0) if generator else 100.0
	return wave_scale * lerpf(0.2, 1.0, smoothstep(1.5, 22.0, depth))


static func _gerstner(p: Vector2, t: float, d: Vector2, L: float, A: float, Q: float) -> Vector3:
	var k := TAU / L
	var c := sqrt(9.81 / k)
	var f := k * (d.dot(p) - c * t)
	return Vector3(Q * A * d.x * cos(f), A * sin(f), Q * A * d.y * cos(f))


func _displace(p: Vector2, t: float, s: float) -> Vector3:
	var w := wind_dir.normalized()
	var w2 := (w + Vector2(-w.y, w.x) * 0.45).normalized()
	var w3 := (w + Vector2(w.y, -w.x) * 0.6).normalized()
	var o := Vector3.ZERO
	o += _gerstner(p, t, w, 110.0, 0.85 * s, 0.35)
	o += _gerstner(p, t, w2, 55.0, 0.45 * s, 0.45)
	o += _gerstner(p, t, w3, 26.0, 0.22 * s, 0.5)
	return o


## Hauteur de la surface au point (x, z) du monde : mêmes vagues que le shader (trains, amortissement
## par la profondeur), avec inversion du déplacement horizontal de Gerstner (point fixe, 2 itérations).
func surface_height(x: float, z: float, t: float) -> float:
	var s := wave_factor(x, z)
	var target := Vector2(x, z)
	var p := target
	for i in 2:
		var d := _displace(p, t, s)
		p = target - Vector2(d.x, d.z)
	return IslandGenerator.SEA_LEVEL + _displace(p, t, s).y
