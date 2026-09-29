extends SceneTree
## Inspecte les modèles importés : nœuds, surfaces, matériaux, textures, boîte englobante.
## godot --headless --path . -s tests/asset_probe.gd [-- nom.glb]

func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".glb"):
			only = a
	var dirs := ["res://assets/sketchfab"]
	for d in DirAccess.get_directories_at("res://assets/polyhaven/models"):
		dirs.append("res://assets/polyhaven/models/" + d)
	for dpath in dirs:
		var dir := DirAccess.open(dpath)
		for f in dir.get_files():
			if not (f.ends_with(".glb") or f.ends_with(".gltf")) or (only != "" and f != only):
				continue
			_probe(dpath + "/" + f)
	quit()


func _probe(path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		print("!! %s : chargement impossible" % path)
		return
	var root := scene.instantiate()
	var aabb := AABB()
	var first := true
	var tris := 0
	var lines: Array[String] = []
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			var box := xf * mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var nt := (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				tris += nt
				var mat := mi.get_active_material(s)
				var desc := "?"
				if mat is BaseMaterial3D:
					var b := mat as BaseMaterial3D
					var tex := b.albedo_texture
					var ts := ""
					if tex != null:
						ts = "%dx%d" % [tex.get_width(), tex.get_height()]
					desc = "%s alb=%s transp=%d cull=%d nrm=%s rough=%.2f metal=%.2f" % [b.resource_name, ts, b.transparency, b.cull_mode, "oui" if b.normal_enabled else "non", b.roughness, b.metallic]
				lines.append("    %s[%d] %d tris skin=%s : %s" % [n.name, s, nt, "oui" if mi.skin != null else "non", desc])
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			for b in sk.get_bone_count():
				if sk.get_bone_name(b).containsn("head") or sk.get_bone_name(b).containsn("tail"):
					var g := xf * sk.get_bone_global_rest(b)
					lines.append("    os %s : %s" % [sk.get_bone_name(b), g.origin])
		if n is AnimationPlayer:
			var ap := n as AnimationPlayer
			for a in ap.get_animation_list():
				lines.append("    animation %s : %.2f s" % [a, ap.get_animation(a).length])
		for c in n.get_children():
			stack.append([c, xf])
	print("== %s : %d tris, boîte %s -> %s (%.2f x %.2f x %.2f)" % [path.get_file(), tris, aabb.position, aabb.end, aabb.size.x, aabb.size.y, aabb.size.z])
	for l in lines:
		print(l)
	root.free()
