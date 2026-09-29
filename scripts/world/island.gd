## Construit le maillage de l'île (par morceaux) à partir d'un [IslandGenerator].
class_name Island
extends Node3D

const CHUNK_QUADS := 64

var generator: IslandGenerator
var material: ShaderMaterial
var height_texture: ImageTexture


func build(gen: IslandGenerator) -> void:
	generator = gen
	for c in get_children():
		c.queue_free()

	height_texture = ImageTexture.create_from_image(gen.make_height_image())

	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var detail := NoiseTexture2D.new()
	detail.width = 512
	detail.height = 512
	detail.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.02
	n.fractal_octaves = 4
	detail.noise = n
	material.set_shader_parameter("detail_noise", detail)
	material.set_shader_parameter("volcano_pos", Vector3(gen.params.volcano_pos.x, 0.0, gen.params.volcano_pos.y))
	material.set_shader_parameter("volcano_radius", gen.params.volcano_radius)
	material.set_shader_parameter("volcano_height", gen.params.volcano_height)
	material.set_shader_parameter("debug_flat", OS.get_environment("ALIZE_FLAT") == "1")

	var chunks_per_side := (IslandGenerator.SIZE - 1) / CHUNK_QUADS
	for cj in chunks_per_side:
		for ci in chunks_per_side:
			var mi := MeshInstance3D.new()
			mi.mesh = _build_chunk(ci * CHUNK_QUADS, cj * CHUNK_QUADS)
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.name = "Chunk_%d_%d" % [ci, cj]
			add_child(mi)


func _build_chunk(i0: int, j0: int) -> ArrayMesh:
	var gen := generator
	var n := CHUNK_QUADS + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	var sp := gen.spacing
	var half := IslandGenerator.EXTENT * 0.5
	var k := 0
	for j in n:
		var gj := j0 + j
		var z := -half + gj * sp
		for i in n:
			var gi := i0 + i
			var x := -half + gi * sp
			var h := gen.sample(gi, gj)
			verts[k] = Vector3(x, h, z)
			var hl := gen.sample(gi - 1, gj)
			var hr := gen.sample(gi + 1, gj)
			var hd := gen.sample(gi, gj - 1)
			var hu := gen.sample(gi, gj + 1)
			normals[k] = Vector3(-(hr - hl) / (2.0 * sp), 1.0, -(hu - hd) / (2.0 * sp)).normalized()
			uvs[k] = Vector2((x + half) / IslandGenerator.EXTENT, (z + half) / IslandGenerator.EXTENT)
			k += 1

	var indices := PackedInt32Array()
	indices.resize(CHUNK_QUADS * CHUNK_QUADS * 6)
	var q := 0
	for j in CHUNK_QUADS:
		for i in CHUNK_QUADS:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Godot : faces avant dans le sens horaire (vu de dessus, +Y).
			indices[q] = a; indices[q + 1] = b; indices[q + 2] = d
			indices[q + 3] = a; indices[q + 4] = d; indices[q + 5] = c
			q += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
