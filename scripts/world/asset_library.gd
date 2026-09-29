## Bibliothèque des modèles d'artistes (glTF importés depuis Sketchfab et Poly Haven).
## Un modèle est chargé une fois, ses nœuds sont aplatis dans un seul maillage (transformations
## cuites dans les sommets, surfaces regroupées par matériau), ses matériaux sont convertis vers
## le shader de végétation (textures conservées, vent ajouté) et des niveaux de détail sont
## générés (meshoptimizer via ImporterMesh). Le résultat sert aux MultiMesh de la végétation.
class_name AssetLibrary
extends RefCounted

static var _meshes := {}      # clé -> Dictionary {mesh, height, radius, aabb}
static var _materials := {}   # id du matériau source -> ShaderMaterial
static var _shader: Shader


## Charge et prépare un modèle. Options :
##   include : liste de morceaux de noms ; seuls les nœuds dont le nom en contient un sont gardés
##   exclude : liste de morceaux de noms à écarter
##   scale   : facteur d'échelle uniforme
##   recenter: recale la base à y = 0 et le centre horizontal à l'origine (défaut : vrai)
##   lods    : génère des niveaux de détail (défaut : vrai)
## Retourne {mesh: ArrayMesh, height: float, radius: float, aabb: AABB, tris: int}.
static func get_model(path: String, opts: Dictionary = {}) -> Dictionary:
	var key := path + "|" + JSON.stringify(opts)
	if _meshes.has(key):
		return _meshes[key]
	var t0 := Time.get_ticks_msec()
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("Modèle introuvable : " + path)
		return {}
	var root := scene.instantiate()
	var include: Array = opts.get("include", [])
	var exclude: Array = opts.get("exclude", [])
	var scale: float = opts.get("scale", 1.0)

	# 1. Récolte des surfaces avec leur transformation globale.
	var items: Array = []   # [mesh, surface, xf, material]
	var aabb := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and _name_ok(n.name, include, exclude):
			var mi := n as MeshInstance3D
			var box := xf * mi.mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
			for s in mi.mesh.get_surface_count():
				items.append([mi.mesh, s, xf, mi.get_active_material(s)])
		for c in n.get_children():
			stack.append([c, xf])
	root.free()
	if items.is_empty():
		push_error("Aucune surface dans %s (include=%s)" % [path, str(include)])
		return {}

	# 2. Recalage : base au sol, centre horizontal à l'origine, échelle.
	var offset := Vector3.ZERO
	if opts.get("recenter", true):
		var c := aabb.get_center()
		offset = Vector3(-c.x, -aabb.position.y, -c.z)
	var fix := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), offset * scale)

	# 3. Regroupement par matériau, cuisson des transformations, matériaux convertis.
	var groups := {}   # id matériau -> {items: [], mat: Material}
	var order: Array = []
	for it in items:
		var src: Material = it[3]
		var id := src.get_instance_id() if src else 0
		if not groups.has(id):
			groups[id] = {"items": [], "src": src}
			order.append(id)
		groups[id].items.append(it)
	var importer := ImporterMesh.new()
	var tris := 0
	var center := aabb.get_center() * scale + offset * scale
	var sphere_r2 := 0.0
	for id in order:
		var g: Dictionary = groups[id]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for it in g.items:
			st.append_from(it[0], it[1], fix * it[2])
		var mat := convert_material(g.src)
		if mat.get_shader_parameter("use_normal"):
			st.generate_tangents()
		var arrays := st.commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		# On ne garde que ce que le shader lit : positions, normales, tangentes, UV, indices.
		for ai in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			arrays[ai] = null
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if nrm != null:
			for vi in nrm.size():
				nrm[vi] = nrm[vi].normalized()
			arrays[Mesh.ARRAY_NORMAL] = nrm
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		tris += (idx.size() if idx.size() > 0 else verts.size()) / 3
		for v in verts:
			sphere_r2 = maxf(sphere_r2, v.distance_squared_to(center))
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat, g.src.resource_name if g.src else "")
	if opts.get("lods", true):
		importer.generate_lods(25.0, 60.0, [])
	var mesh := importer.get_mesh()
	var final_aabb := AABB(aabb.position * scale + offset * scale, aabb.size * scale)
	var radius := maxf(maxf(-final_aabb.position.x, final_aabb.end.x), maxf(-final_aabb.position.z, final_aabb.end.z))
	var result := {"mesh": mesh, "height": final_aabb.size.y, "radius": radius, "aabb": final_aabb, "tris": tris,
		"sphere_center": center, "sphere_radius": sqrt(sphere_r2)}
	_meshes[key] = result
	print("Modèle %s : %d triangles, %d surfaces, %.1f m de haut (%d ms)" % [path.get_file(), tris, mesh.get_surface_count(), final_aabb.size.y, Time.get_ticks_msec() - t0])
	return result


static func _name_ok(name: String, include: Array, exclude: Array) -> bool:
	for e in exclude:
		if name.contains(e):
			return false
	if include.is_empty():
		return true
	for i in include:
		if name.contains(i):
			return true
	return false


## Convertit un matériau importé (StandardMaterial3D) vers le shader de végétation : mêmes
## textures (couleur, normales), même seuil de découpe alpha ; les surfaces découpées (feuilles,
## palmes) reçoivent le frémissement et la translucidité.
static func convert_material(src: Material) -> ShaderMaterial:
	var id := src.get_instance_id() if src else 0
	if _materials.has(id):
		return _materials[id]
	if _shader == null:
		_shader = load("res://shaders/vegetation.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		mat.resource_name = b.resource_name
		if b.albedo_texture:
			mat.set_shader_parameter("albedo_tex", b.albedo_texture)
		mat.set_shader_parameter("tint", b.albedo_color)
		if b.normal_enabled and b.normal_texture:
			mat.set_shader_parameter("normal_tex", b.normal_texture)
			mat.set_shader_parameter("use_normal", true)
			mat.set_shader_parameter("normal_scale", b.normal_scale)
		mat.set_shader_parameter("roughness", clampf(b.roughness, 0.6, 1.0))
		var cut := 0.0
		if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			cut = clampf(b.alpha_scissor_threshold, 0.2, 0.7)
		elif b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			cut = 0.5
		mat.set_shader_parameter("alpha_scissor", cut)
		mat.set_shader_parameter("leaf", 1.0 if cut > 0.0 else 0.0)
	_materials[id] = mat
	return mat


## Vide les caches (nouvelle partie, tests).
static func clear() -> void:
	_meshes.clear()
	_materials.clear()
