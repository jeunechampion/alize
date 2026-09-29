## Rend un thermique visible : poussières et feuilles qui montent, et une colonne d'air qui tremble.
class_name ThermalVisual
extends Node3D

var thermal: Thermal
var particles: CPUParticles3D
var column: MeshInstance3D


func setup(t: Thermal) -> void:
	thermal = t
	position = Vector3(t.center.x, t.base_y, t.center.y)
	var height := t.top - t.base_y

	# Poussières, graines et feuilles emportées.
	particles = CPUParticles3D.new()
	particles.amount = 260
	particles.lifetime = 14.0
	particles.preprocess = 14.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(t.radius * 0.75, height * 0.35, t.radius * 0.75)
	particles.position.y = height * 0.35
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 8.0
	particles.initial_velocity_min = t.core * 0.6
	particles.initial_velocity_max = t.core * 1.1
	particles.gravity = Vector3.ZERO
	particles.orbit_velocity_min = 0.02
	particles.orbit_velocity_max = 0.06
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.3
	particles.angular_velocity_min = -90.0
	particles.angular_velocity_max = 90.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	particles.mesh = quad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_color = Color(1.0, 0.95, 0.8, 0.55)
	pm.vertex_color_use_as_albedo = true
	particles.mesh.material = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.8, 0.0))
	grad.set_color(1, Color(1.0, 0.9, 0.7, 0.0))
	grad.add_point(0.15, Color(1.0, 0.95, 0.85, 0.6))
	grad.add_point(0.8, Color(1.0, 0.95, 0.85, 0.5))
	particles.color_ramp = grad
	add_child(particles)

	# Colonne translucide qui ondule.
	var cyl := CylinderMesh.new()
	cyl.top_radius = t.radius * 1.15
	cyl.bottom_radius = t.radius * 0.8
	cyl.height = height
	cyl.radial_segments = 24
	cyl.rings = 8
	column = MeshInstance3D.new()
	column.mesh = cyl
	column.position.y = height * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/thermal.gdshader")
	mat.set_shader_parameter("height", height)
	column.material_override = mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(column)
