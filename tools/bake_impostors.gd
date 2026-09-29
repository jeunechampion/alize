## Cuisson des imposteurs : pour chaque espèce d'arbre, un atlas de vues (N_AZ azimuts × N_EL
## élévations) de l'albédo et des normales, rendu en orthographique sans lumière. Le shader
## d'imposteur (shaders/impostor.gdshader) recompose l'arbre lointain à partir de ces vues.
## Astuce : au lieu de déplacer la caméra, chaque vue est une copie du modèle tournée pour que la
## direction de vue voulue regarde la caméra ; les copies sont posées en grille et rendues en une fois.
## Lancement (sous xvfb) : godot --path . --rendering-method gl_compatibility tools/bake_impostors.tscn
extends Node3D

const N_AZ := 8
const N_EL := 5
const CELL_PX := 128        # taille finale d'une cellule
const SUPERSAMPLE := 4      # rendu à 4x, puis réduction avec alpha prémultiplié (couverture)
const OUT_DIR := "res://assets/impostors/"

var _sub: SubViewport
var _cam: Camera3D
var _meta := {}
var _tex_is_linear := false    # une texture source_color relue donne-t-elle des valeurs linéaires ?
var _out_is_encoded := false   # une constante écrite est-elle relue encodée en sRGB ?


## Direction de vue (du centre de l'arbre vers la caméra) pour une cellule ; même formule côté shader.
static func cell_dir(ia: int, ie: int) -> Vector3:
	var az := float(ia) / float(N_AZ) * TAU
	var el := minf(float(ie) / float(N_EL - 1) * (PI / 2.0), deg_to_rad(89.9))
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))


static func cell_frame(d: Vector3) -> Array:
	var r := Vector3.UP.cross(d).normalized()
	var u := d.cross(r).normalized()
	return [r, u]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_sub = SubViewport.new()
	_sub.size = Vector2i(N_AZ * CELL_PX * SUPERSAMPLE, N_EL * CELL_PX * SUPERSAMPLE)
	_sub.transparent_bg = true
	_sub.own_world_3d = true
	_sub.world_3d = World3D.new()
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sub.msaa_3d = Viewport.MSAA_DISABLED
	_sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(_sub)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_sub.add_child(_cam)
	await _calibrate()
	_bake_all()


## Mire : un panneau texturé (source_color) et un panneau à couleur constante, relus pour savoir
## dans quel espace de couleur le pilote rend et relit le SubViewport.
func _calibrate() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color8(128, 128, 128, 255))
	var tex := ImageTexture.create_from_image(img)
	var w := float(_sub.size.x)
	var h := float(_sub.size.y)
	_cam.size = h
	_cam.near = 0.1
	_cam.far = 100.0
	_cam.transform = Transform3D(Basis.IDENTITY, Vector3(w * 0.5, h * 0.5, 10.0))
	for i in 2:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w * 0.4, h)
		mi.mesh = qm
		mi.position = Vector3(w * (0.25 + 0.5 * i), h * 0.5, 0.0)
		var sh := Shader.new()
		if i == 0:
			sh.code = "shader_type spatial; render_mode unshaded; uniform sampler2D t : source_color; void fragment() { ALBEDO = texture(t, UV).rgb; }"
		else:
			sh.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(0.5); }"
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("t", tex)
		mi.material_override = m
		_sub.add_child(mi)
	_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := _sub.get_texture().get_image()
	var a := shot.get_pixel(int(w * 0.25), int(h * 0.5)).r
	var b := shot.get_pixel(int(w * 0.75), int(h * 0.5)).r
	_out_is_encoded = absf(b - 0.735) < absf(b - 0.5)
	# Valeur de texture 0.502 (sRGB) = 0.216 linéaire. Relue : sRGB brut 0.502, linéaire brut 0.216,
	# linéaire ré-encodé 0.502, sRGB ré-encodé 0.735.
	if _out_is_encoded:
		_tex_is_linear = absf(a - 0.502) < absf(a - 0.735)
	else:
		_tex_is_linear = absf(a - 0.216) < absf(a - 0.502)
	print("calibration : texture relue %.3f, constante 0,5 relue %.3f -> textures %s, sortie %s" % [a, b, "linéaires" if _tex_is_linear else "sRGB", "encodée" if _out_is_encoded else "brute"])
	for c in _sub.get_children():
		if c != _cam:
			c.queue_free()
	await get_tree().process_frame


func _bake_all() -> void:
	var albedo_shader: Shader = load("res://shaders/impostor_bake_albedo.gdshader")
	var normal_shader: Shader = load("res://shaders/impostor_bake_normal.gdshader")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--species="):
			only = a.get_slice("=", 1)
	for name in Vegetation.SPECIES:
		var s: Dictionary = Vegetation.SPECIES[name]
		if not s.get("tree", false) or (only != "" and name != only):
			continue
		var opts := {"scale": s.scale}
		if s.has("include"):
			opts["include"] = s.include
		var m := AssetLibrary.get_model(s.path, opts)
		if m.is_empty():
			continue
		var center: Vector3 = m.sphere_center
		var radius: float = m.sphere_radius * 1.02
		_meta[name] = {"radius": radius, "center_y": center.y, "n_az": N_AZ, "n_el": N_EL}
		for pass_name in ["albedo", "normal"]:
			var shader := albedo_shader if pass_name == "albedo" else normal_shader
			_layout(m.mesh, center, radius, shader)
			_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := _sub.get_texture().get_image()
			# Correction d'espace de couleur (voir _calibrate) : le PNG doit contenir l'albédo en sRGB
			# et les normales telles qu'encodées.
			if pass_name == "albedo":
				if _tex_is_linear and not _out_is_encoded:
					img.linear_to_srgb()
				elif not _tex_is_linear and _out_is_encoded:
					img.srgb_to_linear()
			elif _out_is_encoded:
				img.srgb_to_linear()
			# Réduction : couleurs prémultipliées par l'alpha, l'alpha devient une couverture.
			img.premultiply_alpha()
			img.resize(N_AZ * CELL_PX, N_EL * CELL_PX, Image.INTERPOLATE_CUBIC)
			var path := OUT_DIR + "%s_%s.png" % [name, pass_name]
			img.save_png(path)
			print("imposteur %s (%s) : %s, rayon %.1f m" % [name, pass_name, path, radius])
			for c in _sub.get_children():
				if c != _cam:
					c.queue_free()
			await get_tree().process_frame
	var f := FileAccess.open(OUT_DIR + "impostors.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_meta, "\t"))
	f.close()
	print("cuisson terminée : %d espèces" % _meta.size())
	get_tree().quit()


## Pose N_AZ × N_EL copies tournées du modèle dans le plan de la caméra.
func _layout(mesh: ArrayMesh, center: Vector3, radius: float, shader: Shader) -> void:
	var cell := radius * 2.0
	var mats: Array = []
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i) as ShaderMaterial
		var dup := ShaderMaterial.new()
		dup.shader = shader
		if src:
			for u in shader.get_shader_uniform_list():
				var v = src.get_shader_parameter(u.name)
				if v != null:
					dup.set_shader_parameter(u.name, v)
		mats.append(dup)
	for ie in N_EL:
		for ia in N_AZ:
			var d := cell_dir(ia, ie)
			var fr := cell_frame(d)
			var rot := Basis(fr[0], fr[1], d).inverse()   # r -> X, u -> Y, d -> Z
			var cell_center := Vector3((ia + 0.5) * cell, (N_EL - 1 - ie + 0.5) * cell, 0.0)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			for i in mats.size():
				mi.set_surface_override_material(i, mats[i])
			mi.transform = Transform3D(rot, cell_center - rot * center)
			_sub.add_child(mi)
	var w := N_AZ * cell
	var h := N_EL * cell
	_cam.size = h
	_cam.near = 0.1
	_cam.far = radius * 8.0
	_cam.transform = Transform3D(Basis.IDENTITY, Vector3(w * 0.5, h * 0.5, radius * 4.0))
