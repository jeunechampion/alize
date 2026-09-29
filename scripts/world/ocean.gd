## Océan : un plan dense qui suit la caméra (vagues) et un plan lointain jusqu'à l'horizon.
class_name Ocean
extends Node3D

const NEAR_SIZE := 4000.0
const NEAR_SUBDIV := 400
const FAR_SIZE := 400000.0

var material: ShaderMaterial
var near: MeshInstance3D
var far: MeshInstance3D
var _near_spacing: float = NEAR_SIZE / float(NEAR_SUBDIV + 1)
var wind_dir := Vector2(-1.0, 0.25)
var sea_time: float = 0.0


func setup(height_tex: Texture2D) -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/ocean.gdshader")
	material.set_shader_parameter("height_tex", height_tex)
	material.set_shader_parameter("extent", IslandGenerator.EXTENT)
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
	far.material_override = material
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.position.y = -0.4
	far.name = "Far"
	add_child(far)


func _process(delta: float) -> void:
	sea_time += delta
	if material:
		material.set_shader_parameter("sea_time", sea_time)


## Le plan dense suit la caméra, calé sur la grille de ses sommets (pas de flottement).
func follow(cam_pos: Vector3) -> void:
	var sx := roundf(cam_pos.x / _near_spacing) * _near_spacing
	var sz := roundf(cam_pos.z / _near_spacing) * _near_spacing
	near.position = Vector3(sx, IslandGenerator.SEA_LEVEL, sz)
	var fs := 5000.0
	far.position = Vector3(roundf(cam_pos.x / fs) * fs, IslandGenerator.SEA_LEVEL - 0.4, roundf(cam_pos.z / fs) * fs)


## Hauteur approximative de la surface (mêmes vagues que le shader, pour poser l'oiseau).
func surface_height(x: float, z: float, t: float) -> float:
	var w := wind_dir.normalized()
	var w2 := (w + Vector2(-w.y, w.x) * 0.45).normalized()
	var w3 := (w + Vector2(w.y, -w.x) * 0.6).normalized()
	var w4 := (w + Vector2(-w.y, w.x) * 1.1).normalized()
	var p := Vector2(x, z)
	var h := 0.0
	h += _gerstner_y(p, t, w, 110.0, 0.85)
	h += _gerstner_y(p, t, w2, 55.0, 0.45)
	h += _gerstner_y(p, t, w3, 26.0, 0.22)
	h += _gerstner_y(p, t, w4, 13.0, 0.10)
	return IslandGenerator.SEA_LEVEL + h


static func _gerstner_y(p: Vector2, t: float, d: Vector2, L: float, A: float) -> float:
	var k := TAU / L
	var c := sqrt(9.81 / k)
	return A * sin(k * (d.dot(p) - c * t))
