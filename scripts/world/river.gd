## Surface des rivières : un ruban de triangles par cours d'eau, au niveau de l'eau, avec un shader
## d'eau courante simple (reflets, scintillement, transparence). Le lit est creusé dans le relief
## par IslandGenerator ; ici on ne fait que poser l'eau dessus.
class_name River
extends Node3D

var material: ShaderMaterial


func build(gen: IslandGenerator) -> void:
	for c in get_children():
		c.queue_free()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/river.gdshader")
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.as_normal_map = true
	noise.bump_strength = 6.0
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.05
	n.fractal_octaves = 3
	noise.noise = n
	material.set_shader_parameter("ripple_normal", noise)
	for r in gen.rivers:
		var mi := MeshInstance3D.new()
		mi.mesh = _ribbon(r.points, r.widths)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


static func _ribbon(points: PackedVector3Array, widths: PackedFloat32Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var along := 0.0
	var verts: Array = []
	for k in n:
		var p := points[k]
		var prev := points[maxi(k - 1, 0)]
		var next := points[mini(k + 1, n - 1)]
		var dir := Vector2(next.x - prev.x, next.z - prev.z).normalized()
		var right := Vector2(dir.y, -dir.x)
		var w := widths[k] * 1.05
		if k > 0:
			along += Vector2(p.x - prev.x, p.z - prev.z).length()
		var y := p.y - 0.12
		verts.append([Vector3(p.x - right.x * w, y, p.z - right.y * w), Vector3(p.x + right.x * w, y, p.z + right.y * w), along, w])
	for k in n:
		var v = verts[k]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, v[2] / 8.0))
		st.add_vertex(v[0])
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, v[2] / 8.0))
		st.add_vertex(v[1])
	for k in n - 1:
		# Sens horaire vu de dessus (face avant vers le haut, comme le relief).
		var a := k * 2
		st.add_index(a)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 3)
		st.add_index(a + 2)
	st.generate_tangents()
	return st.commit()
