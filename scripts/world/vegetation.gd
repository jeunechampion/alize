## Place la végétation sur l'île à partir des modèles d'artistes (Sketchfab CC-BY, Poly Haven CC0).
## Placement par grille tremblée déterministe (seed) ; chaque emplacement reçoit une espèce selon
## l'altitude, la pente, un bruit d'humidité et la distance au cratère. Rendu par MultiMesh, un par
## morceau de 200 m et par espèce, ce qui donne au moteur des boîtes englobantes petites : tri de
## frustum et niveaux de détail automatiques (générés à l'import) par morceau. Au-delà de
## FAR_SWITCH les maillages s'effacent (les imposteurs prennent le relais). Le sous-bois (fougères,
## plantes, herbes, rochers) n'existe qu'autour de la caméra : morceaux de 64 m créés à la volée.
class_name Vegetation
extends Node3D

const CELL := 6.5             # m entre deux emplacements d'arbres candidats (canopée fermée)
const UNDER_CELL := 4.5       # m pour le sous-bois
const CHUNK := 200.0          # m, morceaux d'arbres
const UNDER_CHUNK := 64.0     # m, morceaux de sous-bois
const UNDER_RADIUS := 160.0   # m autour de la caméra
const FAR_SWITCH := 320.0     # m : au-delà, maillages effacés (imposteurs) au niveau de détail normal
const DETAIL_SWITCH := [180.0, 320.0, 520.0]   # par niveau de détail (touche G)
const LOD_BIAS := 0.6         # < 1 : niveaux de détail plus tôt (forêt dense)
const STRIDE := 20            # floats par instance : transformation 12, couleur 4, données 4

const SKETCHFAB := "res://assets/sketchfab/"
const POLYHAVEN := "res://assets/polyhaven/models/"

## Espèces : modèle, échelle, balancement (m en haut du modèle), frémissement des feuilles (m).
const SPECIES := {
	# Arbres (toute l'île)
	"cocotier": {"path": SKETCHFAB + "coconut_palm.glb", "scale": 1.3, "sway": 0.55, "flutter": 0.02, "tree": true},
	"dattier": {"path": SKETCHFAB + "date_palm.glb", "scale": 1.15, "sway": 0.4, "flutter": 0.02, "tree": true},
	"canopee": {"path": SKETCHFAB + "tree_gn.glb", "scale": 0.75, "sway": 0.35, "flutter": 0.03, "tree": true},
	"vieil_arbre": {"path": SKETCHFAB + "old_tree.glb", "scale": 1.3, "sway": 0.25, "flutter": 0.03, "tree": true},
	"acacia": {"path": SKETCHFAB + "acacia_tree.glb", "scale": 1.2, "sway": 0.2, "flutter": 0.03, "tree": true},
	"cypres": {"path": SKETCHFAB + "jungle_tree.glb", "scale": 0.55, "sway": 0.3, "flutter": 0.03, "tree": true},
	"frangipanier": {"path": SKETCHFAB + "frangipani_tree.glb", "scale": 3.0, "sway": 0.15, "flutter": 0.02, "tree": true},
	"bananier": {"path": SKETCHFAB + "banana_plant.glb", "scale": 1.3, "sway": 0.3, "flutter": 0.04, "tree": true},
	"bambou": {"path": SKETCHFAB + "bamboo.glb", "scale": 1.6, "sway": 0.5, "flutter": 0.03, "tree": true},
	"hetre": {"path": SKETCHFAB + "beech_tree.glb", "scale": 2.3, "sway": 0.3, "flutter": 0.03, "tree": true},
	"chene": {"path": SKETCHFAB + "oak_tree.glb", "scale": 1.3, "sway": 0.25, "flutter": 0.03, "tree": true},
	"figuier": {"path": SKETCHFAB + "fig_tree.glb", "scale": 2.6, "sway": 0.2, "flutter": 0.03, "tree": true},
	# Sous-bois (autour de la caméra)
	"fougere": {"path": SKETCHFAB + "fern.glb", "scale": 1.0, "sway": 0.05, "flutter": 0.02},
	"fougere2": {"path": POLYHAVEN + "fern_02/fern_02_1k.gltf", "include": ["fern_02_d"], "scale": 1.4, "sway": 0.05, "flutter": 0.015},
	"monstera": {"path": SKETCHFAB + "monstera.glb", "scale": 1.6, "sway": 0.05, "flutter": 0.02},
	"monstera2": {"path": SKETCHFAB + "tropical_plants_pack.glb", "include": ["Monstera_B071_"], "scale": 1.0, "sway": 0.05, "flutter": 0.02},
	"plante": {"path": SKETCHFAB + "tropical_plant_2.glb", "scale": 1.3, "sway": 0.05, "flutter": 0.015},
	"palmier_nain": {"path": SKETCHFAB + "curly_palm.glb", "scale": 1.3, "sway": 0.1, "flutter": 0.02},
	"petit_palmier": {"path": SKETCHFAB + "tropical_plants_pack.glb", "include": ["SM_MZRa_Palm_B081_"], "scale": 1.0, "sway": 0.15, "flutter": 0.02},
	"petit_bananier": {"path": SKETCHFAB + "tropical_plants_pack.glb", "include": ["SM_MZRa_Banana_B091_"], "scale": 1.0, "sway": 0.1, "flutter": 0.03},
	"hibiscus": {"path": SKETCHFAB + "hibiscus.glb", "scale": 2.2, "sway": 0.05, "flutter": 0.015},
	"calathea": {"path": POLYHAVEN + "calathea_orbifolia_01/calathea_orbifolia_01_1k.gltf", "include": ["calathea_orbifolia_01_e"], "scale": 1.5, "sway": 0.05, "flutter": 0.015},
	"arbuste": {"path": POLYHAVEN + "shrub_03/shrub_03_1k.gltf", "include": ["shrub_03_a"], "scale": 2.2, "sway": 0.08, "flutter": 0.015},
	"arbuste2": {"path": POLYHAVEN + "shrub_03/shrub_03_1k.gltf", "include": ["shrub_03_c"], "scale": 2.0, "sway": 0.08, "flutter": 0.015},
	"herbe": {"path": POLYHAVEN + "grass_medium_02/grass_medium_02_1k.gltf", "include": ["grass_medium_02_a"], "scale": 1.8, "sway": 0.08, "flutter": 0.015},
	"herbe2": {"path": POLYHAVEN + "grass_medium_02/grass_medium_02_1k.gltf", "include": ["grass_medium_02_c"], "scale": 1.6, "sway": 0.08, "flutter": 0.015},
	"rocher": {"path": POLYHAVEN + "rock_07/rock_07_1k.gltf", "scale": 7.0, "sway": 0.0, "flutter": 0.0, "rock": true},
	"gros_rocher": {"path": POLYHAVEN + "boulder_01/boulder_01_1k.gltf", "scale": 2.5, "sway": 0.0, "flutter": 0.0, "rock": true},
}

var generator: IslandGenerator
var seed_value := 0
var tree_count := 0
var models := {}             # espèce -> {mesh, height, radius}
var _humidity: FastNoiseLite
var _tree_nodes: Array = []  # MultiMeshInstance3D des arbres
var _impostor_nodes: Array = []
var _under_enabled := true
var _under_chunks := {}      # Vector2i -> Node3D
var _under_timer := 0.0
var _wind_time := 0.0
var _last_under_center := Vector2i(1 << 30, 0)
var _tree_chunks := {}       # Vector2i -> {espèce: PackedFloat32Array}
var _rows_mutex := Mutex.new()
var _impostor_mats := {}     # espèce -> ShaderMaterial (atlas cuits par tools/bake_impostors.gd)
var _impostor_quad: ArrayMesh


func build(gen: IslandGenerator, seed_v: int, wind_dir: Vector2) -> void:
	generator = gen
	seed_value = seed_v
	for c in get_children():
		c.queue_free()
	_tree_nodes.clear()
	_impostor_nodes.clear()
	_under_chunks.clear()
	_tree_chunks.clear()
	_last_under_center = Vector2i(1 << 30, 0)
	tree_count = 0
	RenderingServer.global_shader_parameter_set("wind_dir", wind_dir)
	var t0 := Time.get_ticks_msec()

	for name in SPECIES:
		var s: Dictionary = SPECIES[name]
		var opts := {"scale": s.scale}
		if s.has("include"):
			opts["include"] = s.include
		models[name] = AssetLibrary.get_model(s.path, opts)
	var t1 := Time.get_ticks_msec()

	_humidity = FastNoiseLite.new()
	_humidity.seed = seed_value ^ 0x77
	_humidity.frequency = 1.0 / 420.0
	_humidity.fractal_octaves = 3

	# Arbres : toute l'île, rangés par morceau de CHUNK m. Une tâche par rangée de cellules,
	# sur tous les cœurs (lecture seule du relief et du bruit).
	var n := int(IslandGenerator.EXTENT / CELL)
	var rows: Array = []
	rows.resize(n)
	var group := WorkerThreadPool.add_group_task(_place_row.bind(rows, n), n, -1, true, "Végétation")
	WorkerThreadPool.wait_for_group_task_completion(group)
	for j in n:
		if rows[j] == null:
			continue
		var row: Dictionary = rows[j]
		if row.is_empty():
			continue
		for key in row:
			if not _tree_chunks.has(key):
				_tree_chunks[key] = {}
			var chunk: Dictionary = _tree_chunks[key]
			for name in row[key]:
				if not chunk.has(name):
					chunk[name] = PackedFloat32Array()
				# Pas de conversion « as » ici : elle copierait le tableau au lieu de le partager.
				var buf: PackedFloat32Array = chunk[name]
				var part: PackedFloat32Array = row[key][name]
				buf.append_array(part)
				tree_count += part.size() / STRIDE
	_load_impostors()
	for key in _tree_chunks:
		for name in _tree_chunks[key]:
			var buf: PackedFloat32Array = _tree_chunks[key][name]
			var mmi := _make_instance(name, buf, true)
			mmi.name = "%s_%d_%d" % [name, key.x, key.y]   # noms uniques (sinon Godot renomme en @...)
			mmi.lod_bias = LOD_BIAS
			if _impostor_mats.has(name):
				mmi.visibility_range_end = FAR_SWITCH
				mmi.visibility_range_end_margin = 60.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				var far := _make_impostor(name, buf)
				far.name = "%s_%d_%d_loin" % [name, key.x, key.y]
				far.visibility_range_begin = FAR_SWITCH
				far.visibility_range_begin_margin = 60.0
				far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				add_child(far)
				_impostor_nodes.append(far)
			add_child(mmi)
			_tree_nodes.append(mmi)
	var t2 := Time.get_ticks_msec()
	apply_detail(_current_detail())
	print("Végétation : %d arbres dans %d morceaux (%d ms de modèles, %d ms de placement)" % [tree_count, _tree_chunks.size(), t1 - t0, t2 - t1])


## Niveau de détail demandé par le jeu (autoload Game), 1 hors jeu (tests, outils).
static func _current_detail() -> int:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var game := (loop as SceneTree).root.get_node_or_null("Game")
		if game and "detail_level" in game:
			return game.detail_level
	return 1


## Niveau de détail : distance de bascule vers les imposteurs, ombres des arbres, sous-bois.
func apply_detail(level: int) -> void:
	level = clampi(level, 0, DETAIL_SWITCH.size() - 1)
	var far: float = DETAIL_SWITCH[level]
	var shadows := level >= 1 and OS.get_environment("ALIZE_TREESHADOW") != "0"
	for mmi in _tree_nodes:
		if mmi.visibility_range_end > 0.0:
			mmi.visibility_range_end = far
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for far_node in _impostor_nodes:
		far_node.visibility_range_begin = far
	_under_enabled = level >= 1
	if not _under_enabled:
		for key in _under_chunks.keys():
			var node: Node = _under_chunks[key]
			if node:
				node.queue_free()
		_under_chunks.clear()
		_last_under_center = Vector2i(1 << 30, 0)


## Une rangée de cellules d'arbres (exécutée dans un fil du WorkerThreadPool).
func _place_row(j: int, rows: Array, n: int) -> void:
	var half := IslandGenerator.EXTENT * 0.5
	var out := {}
	for i in n:
		var hsh := _hash(i, j, seed_value)
		var jx := float((hsh >> 8) & 0xFFFF) / 65535.0
		var jz := float((hsh >> 24) & 0xFFFF) / 65535.0
		var x := -half + (i + jx) * CELL
		var z := -half + (j + jz) * CELL
		var name := _pick_tree(x, z, hsh)
		if name == "":
			continue
		var key := Vector2i(int(floor((x + half) / CHUNK)), int(floor((z + half) / CHUNK)))
		if not out.has(key):
			out[key] = {}
		if not out[key].has(name):
			out[key][name] = PackedFloat32Array()
		_append_instance(out[key][name], name, x, z, hsh)
	_rows_mutex.lock()
	rows[j] = out
	_rows_mutex.unlock()


## Choisit l'espèce d'arbre d'un emplacement ("" : rien). Probabilités par cellule de 6,5 m
## (42 m²) : une forêt fermée demande ~0,5 arbre par cellule avec des couronnes de 8-18 m.
func _pick_tree(x: float, z: float, hsh: int) -> String:
	var h := generator.height_at(x, z)
	if h < 1.0:
		return ""
	var slope := 1.0 - generator.normal_at(x, z).y
	if slope > 0.6:
		return _pick_rock(h, slope, hsh)
	var rd := generator.river_distance_at(x, z)
	if rd < 1.0:
		return ""   # dans l'eau
	var bank := 1.0 - smoothstep(2.0, 14.0, rd)   # berges : bananiers, bambous, moins de grands arbres
	var wet := _humidity.get_noise_2d(x, z) * 0.5 + 0.5
	wet = maxf(wet, bank)
	var ash := _ash_at(x, z)
	var r := float(_hash2(hsh) & 0xFFFF) / 65535.0
	var gentle := (1.0 - smoothstep(0.3, 0.55, slope)) * (1.0 - bank * 0.6)
	var beach := 1.0 - smoothstep(9.0, 16.0, h)
	var low := smoothstep(5.0, 14.0, h) * (1.0 - smoothstep(120.0, 200.0, h))
	var hill := smoothstep(90.0, 160.0, h) * (1.0 - smoothstep(380.0, 470.0, h))
	var high := smoothstep(380.0, 470.0, h)
	var live := (1.0 - ash * 0.95)
	# Forêt humide (basse et collines) : canopée fermée ; versants secs : plus clairsemé.
	var forest := (low + hill) * (0.35 + 0.65 * wet)
	var dry := (low + hill) * (1.0 - wet)
	var table := [
		["cocotier", beach * (1.0 - smoothstep(0.2, 0.4, slope)) * 0.30],
		["dattier", beach * gentle * 0.04],
		["frangipanier", beach * (1.0 - smoothstep(4.0, 9.0, h)) * gentle * 0.03],
		["bananier", (beach * 0.03 + low * wet * 0.06) * gentle + bank * 0.22],
		["bambou", low * wet * gentle * 0.04 + bank * 0.14],
		["canopee", (forest * 0.16 + low * 0.04) * gentle],
		["chene", (forest * 0.18 + dry * 0.06) * gentle],
		["hetre", (forest * 0.06 + dry * 0.04 + high * 0.05) * gentle],
		["figuier", (forest * 0.04 + beach * 0.02) * gentle],
		["cypres", low * smoothstep(0.55, 0.8, wet) * gentle * 0.08],
		["acacia", (dry * 0.12 + high * 0.06) * gentle],
		["vieil_arbre", (forest * 0.008 + dry * 0.01 + high * 0.02) * gentle],
	]
	var acc := 0.0
	for e in table:
		acc += e[1] * live
		if r < acc:
			return e[0]
	if slope > 0.3:
		return _pick_rock(h, slope, hsh)
	return ""


func _pick_rock(h: float, slope: float, hsh: int) -> String:
	var r := float((_hash2(hsh) >> 16) & 0xFFFF) / 65535.0
	var p := smoothstep(0.25, 0.5, slope) * 0.08 + (1.0 - smoothstep(1.0, 4.0, h)) * 0.06
	if r < p * 0.6:
		return "rocher"
	if r < p:
		return "gros_rocher"
	return ""


## Sous-bois : probabilités par cellule de 4,5 m.
func _pick_under(x: float, z: float, hsh: int) -> String:
	var h := generator.height_at(x, z)
	if h < 0.9:
		return ""
	var slope := 1.0 - generator.normal_at(x, z).y
	if slope > 0.55:
		return ""
	var rd := generator.river_distance_at(x, z)
	if rd < 0.8:
		return ""
	var wet := _humidity.get_noise_2d(x, z) * 0.5 + 0.5
	wet = maxf(wet, 1.0 - smoothstep(2.0, 12.0, rd))
	var ash := _ash_at(x, z)
	var r := float(_hash2(hsh) & 0xFFFF) / 65535.0
	var beach := 1.0 - smoothstep(6.0, 14.0, h)
	var low := smoothstep(4.0, 12.0, h) * (1.0 - smoothstep(120.0, 220.0, h))
	var hill := smoothstep(100.0, 180.0, h) * (1.0 - smoothstep(380.0, 470.0, h))
	var high := smoothstep(380.0, 470.0, h)
	var live := (1.0 - ash * 0.95)
	var table := [
		["herbe", beach * 0.06 + low * 0.10 + hill * 0.16 + high * 0.10],
		["herbe2", beach * 0.04 + low * 0.08 + hill * 0.12 + high * 0.06],
		["fougere", beach * 0.04 + low * wet * 0.14 + hill * wet * 0.05],
		["fougere2", low * wet * 0.10 + hill * wet * 0.04],
		["monstera", low * wet * 0.06],
		["monstera2", low * wet * 0.03],
		["calathea", low * wet * 0.05],
		["plante", low * 0.05 + beach * 0.02],
		["palmier_nain", beach * 0.04 + low * 0.02],
		["petit_palmier", beach * 0.04 + low * 0.03],
		["petit_bananier", low * wet * 0.03],
		["hibiscus", beach * 0.015 + low * 0.015],
		["arbuste", low * 0.05 + hill * 0.12 + high * 0.04],
		["arbuste2", low * 0.04 + hill * 0.10 + high * 0.03],
	]
	var acc := 0.0
	for e in table:
		acc += e[1] * live
		if r < acc:
			return e[0]
	return ""


func _ash_at(x: float, z: float) -> float:
	var vpos: Vector2 = generator.params.volcano_pos
	var vrad: float = generator.params.volcano_radius
	var dv := Vector2(x, z).distance_to(vpos) / vrad
	return 1.0 - smoothstep(0.5, 0.95, dv)


func _append_instance(arr: PackedFloat32Array, name: String, x: float, z: float, hsh: int) -> void:
	var m: Dictionary = models[name]
	var s: Dictionary = SPECIES[name]
	var yaw := float((hsh >> 44) & 0xFFF) / 4095.0 * TAU
	var scale := 0.82 + 0.36 * float((hsh >> 56) & 0xFF) / 255.0
	var tint := 0.92 + 0.16 * float((_hash2(hsh) >> 20) & 0xFF) / 255.0
	var phase := float((hsh >> 32) & 0xFF) / 255.0 * TAU
	var h := generator.height_at(x, z)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	var sink := 0.25 * scale if s.get("tree", false) else 0.06
	if s.get("rock", false):
		# Les rochers épousent la pente et s'enfoncent un peu.
		var nrm := generator.normal_at(x, z)
		var tilt := Basis(Vector3.UP.cross(nrm).normalized(), Vector3.UP.angle_to(nrm)) if nrm.y < 0.999 else Basis.IDENTITY
		basis = tilt * basis
		sink = 0.35 * scale * float(m.height)
	var origin := Vector3(x, h - sink, z)
	arr.append_array(PackedFloat32Array([
		basis.x.x, basis.y.x, basis.z.x, origin.x,
		basis.x.y, basis.y.y, basis.z.y, origin.y,
		basis.x.z, basis.y.z, basis.z.z, origin.z,
		tint, tint * (0.97 + 0.06 * float((hsh >> 8) & 0xFF) / 255.0), tint * (0.95 + 0.08 * float((hsh >> 24) & 0xFF) / 255.0), 1.0,
		phase, float(m.height) * scale, float(s.sway) * scale, float(s.flutter)]))


static func _hash32(x: int) -> int:
	# Mélange entier sur 32 bits (Wang) : aucun débordement signé, identique partout.
	x = x & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	return ((x >> 16) ^ x) & 0xFFFFFFFF


## Second mot indépendant dérivé du hachage (espèce, teinte, rochers) : ne partage aucun bit
## avec le tremblement de position.
static func _hash2(hsh: int) -> int:
	return _hash32(((hsh ^ (hsh >> 32)) & 0xFFFFFFFF) ^ 0x5bd1e995)


static func _hash(i: int, j: int, seed_v: int) -> int:
	var base: int = (i * 73856093) ^ (j * 19349663) ^ ((seed_v & 0xFFFFFFFF) * 83492791)
	var h1 := _hash32(base)
	var h2 := _hash32(base ^ 0x9E3779B9 ^ h1)
	return h1 | (h2 << 32)


func _make_instance(name: String, buf: PackedFloat32Array, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = models[name].mesh
	mm.instance_count = buf.size() / STRIDE
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shadows and OS.get_environment("ALIZE_TREESHADOW") == "0":
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Atlas d'imposteurs (albédo + normales par espèce), s'ils ont été cuits.
func _load_impostors() -> void:
	_impostor_mats = load_impostor_materials()
	if _impostor_quad == null:
		_impostor_quad = make_impostor_quad()


static func load_impostor_materials() -> Dictionary:
	var mats := {}
	var meta_path := "res://assets/impostors/impostors.json"
	if not FileAccess.file_exists(meta_path):
		print("Végétation : pas d'imposteurs (assets/impostors/impostors.json absent)")
		return mats
	var meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if typeof(meta) != TYPE_DICTIONARY:
		return mats
	var shader: Shader = load("res://shaders/impostor.gdshader")
	for name in meta:
		var alb_path := "res://assets/impostors/%s_albedo.png" % name
		var nrm_path := "res://assets/impostors/%s_normal.png" % name
		if not ResourceLoader.exists(alb_path) or not ResourceLoader.exists(nrm_path) or not SPECIES.has(name):
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_atlas", load(alb_path))
		mat.set_shader_parameter("normal_atlas", load(nrm_path))
		mat.set_shader_parameter("radius", float(meta[name].radius))
		mat.set_shader_parameter("center_y", float(meta[name].center_y))
		mat.set_shader_parameter("n_az", int(meta[name].n_az))
		mat.set_shader_parameter("n_el", int(meta[name].n_el))
		mat.set_shader_parameter("decode_srgb", RenderingServer.get_current_rendering_method() != "gl_compatibility")
		mats[name] = mat
	return mats


## Panneau ±1 : le shader d'imposteur le tourne vers la caméra et le dimensionne au rayon.
static func make_impostor_quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(v.x, -v.y) * 0.5 + Vector2(0.5, 0.5))
		st.add_vertex(v)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_index(i)
	var quad := st.commit()
	# Boîte englobante généreuse : le panneau tourne et s'étend jusqu'au rayon de la plus grande espèce.
	quad.custom_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50))
	return quad


func _make_impostor(name: String, buf: PackedFloat32Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _impostor_quad
	mm.instance_count = buf.size() / STRIDE
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name + "_loin"
	mmi.multimesh = mm
	mmi.material_override = _impostor_mats[name]
	# Le panneau se tourne aussi vers la « caméra » de la passe d'ombre : l'ombre portée est la
	# silhouette de l'arbre vue du soleil.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if OS.get_environment("ALIZE_TREESHADOW") == "0":
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Sous-bois : crée les morceaux autour de la caméra, supprime les autres.
func update_undergrowth(cam_pos: Vector3) -> void:
	var half := IslandGenerator.EXTENT * 0.5
	var center := Vector2i(int(floor((cam_pos.x + half) / UNDER_CHUNK)), int(floor((cam_pos.z + half) / UNDER_CHUNK)))
	if center == _last_under_center:
		return
	_last_under_center = center
	var reach := int(ceil(UNDER_RADIUS / UNDER_CHUNK))
	var wanted := {}
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var key := center + Vector2i(di, dj)
			var cx := -half + (key.x + 0.5) * UNDER_CHUNK
			var cz := -half + (key.y + 0.5) * UNDER_CHUNK
			if Vector2(cx, cz).distance_to(Vector2(cam_pos.x, cam_pos.z)) > UNDER_RADIUS + UNDER_CHUNK * 0.7:
				continue
			wanted[key] = true
			if not _under_chunks.has(key):
				_under_chunks[key] = _build_under_chunk(key)
	for key in _under_chunks.keys():
		if not wanted.has(key):
			var node: Node = _under_chunks[key]
			if node:
				node.queue_free()
			_under_chunks.erase(key)


func _build_under_chunk(key: Vector2i) -> Node3D:
	var half := IslandGenerator.EXTENT * 0.5
	var n := int(UNDER_CHUNK / UNDER_CELL)
	var cell := UNDER_CHUNK / n   # les cellules couvrent exactement le morceau
	var lists := {}
	for j in n:
		for i in n:
			var gi := key.x * n + i
			var gj := key.y * n + j
			var hsh := _hash(gi + 100000, gj + 100000, seed_value ^ 0x5B5B)
			var jx := float((hsh >> 8) & 0xFFFF) / 65535.0
			var jz := float((hsh >> 24) & 0xFFFF) / 65535.0
			var x := -half + key.x * UNDER_CHUNK + (i + jx) * cell
			var z := -half + key.y * UNDER_CHUNK + (j + jz) * cell
			if absf(x) > half or absf(z) > half:
				continue
			var name := _pick_under(x, z, hsh)
			if name == "":
				continue
			if not lists.has(name):
				lists[name] = PackedFloat32Array()
			_append_instance(lists[name], name, x, z, hsh)
	if lists.is_empty():
		return null
	var node := Node3D.new()
	node.name = "Sousbois_%d_%d" % [key.x, key.y]
	for name in lists:
		var mmi := _make_instance(name, lists[name], false)
		mmi.visibility_range_end = UNDER_RADIUS
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mmi)
	add_child(node)
	return node


func _process(delta: float) -> void:
	_wind_time += delta
	RenderingServer.global_shader_parameter_set("wind_time", _wind_time)
	_under_timer -= delta
	if _under_timer <= 0.0:
		_under_timer = 0.25
		var cam := get_viewport().get_camera_3d()
		if cam and generator and _under_enabled:
			update_undergrowth(cam.global_position)
