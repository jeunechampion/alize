## Place la végétation sur l'île : palmiers sur les plages, arbres à feuilles dans les vallées et
## les collines, rien sur les pentes fortes, les cendres ou sous l'eau. Placement par grille
## tremblée déterministe (seed), densité selon l'altitude, la pente et un bruit d'humidité.
## Rendu par MultiMesh : quelques variantes d'arbres, des milliers d'instances, avec deux niveaux
## de détail (maillage complet près de la caméra, silhouette au loin) répartis toutes les 0,5 s.
class_name Vegetation
extends Node3D

const CELL := 13.0            # m entre deux emplacements candidats
const VARIANTS := 4
const LOD_DISTANCE := 650.0   # m : au-delà, silhouette simplifiée
const STRIDE := 20            # floats par instance : transformation 12, couleur 4, données 4

var generator: IslandGenerator
var material: ShaderMaterial
var wind_time := 0.0
var tree_count := 0
var _groups: Array = []       # par variante : {near: MultiMeshInstance3D, far: ..., data: PackedFloat32Array, pos: PackedVector3Array}
var _lod_timer := 0.0
var _last_cam := Vector3(1e9, 0, 0)


func build(gen: IslandGenerator, seed_value: int, wind_dir: Vector2) -> void:
	generator = gen
	for c in get_children():
		c.queue_free()
	_groups.clear()
	tree_count = 0
	var t0 := Time.get_ticks_msec()

	material = ShaderMaterial.new()
	material.shader = load("res://shaders/vegetation.gdshader")
	material.set_shader_parameter("wind_dir", wind_dir)

	# Variantes d'arbres (déterministes) : maillage complet et silhouette lointaine.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5EED7EE
	var kinds: Array = []   # {near: ArrayMesh, far: ArrayMesh, h: float, palm: bool}
	for v in VARIANTS:
		var h := rng.randf_range(8.0, 13.0)
		kinds.append({"near": TreeBuilder.build_palm(rng, h, wind_dir), "far": TreeBuilder.build_far_palm(h, wind_dir), "h": h, "palm": true})
	for v in VARIANTS:
		var h := rng.randf_range(7.0, 12.0)
		kinds.append({"near": TreeBuilder.build_broadleaf(rng, h, h * 0.5), "far": TreeBuilder.build_far_broadleaf(h, h * 0.5), "h": h, "palm": false})
	var t1 := Time.get_ticks_msec()

	# Emplacements.
	var humidity := FastNoiseLite.new()
	humidity.seed = seed_value ^ 0x77
	humidity.frequency = 1.0 / 420.0
	humidity.fractal_octaves = 3
	var data: Array = []   # par espèce : PackedFloat32Array des instances
	var positions: Array = []
	for k in kinds.size():
		data.append(PackedFloat32Array())
		positions.append(PackedVector3Array())
	var half := IslandGenerator.EXTENT * 0.5
	var n := int(IslandGenerator.EXTENT / CELL)
	var vpos: Vector2 = gen.params.volcano_pos
	var vrad: float = gen.params.volcano_radius
	for j in n:
		for i in n:
			var hsh := _hash(i, j, seed_value)
			var jx := float((hsh >> 8) & 0xFFFF) / 65535.0
			var jz := float((hsh >> 24) & 0xFFFF) / 65535.0
			var x := -half + (i + jx) * CELL
			var z := -half + (j + jz) * CELL
			var h := gen.height_at(x, z)
			if h < 1.2:
				continue
			var nrm := gen.normal_at(x, z)
			var slope := 1.0 - nrm.y
			var dv := Vector2(x, z).distance_to(vpos) / vrad
			var ash := 1.0 - smoothstep(0.5, 0.95, dv)
			var wet := humidity.get_noise_2d(x, z) * 0.5 + 0.5
			var r := float(hsh & 0xFF) / 255.0
			var variant := (hsh >> 40) & (VARIANTS - 1)
			var yaw := float((hsh >> 44) & 0xFFF) / 4095.0 * TAU
			var scale := 0.8 + 0.4 * float((hsh >> 56) & 0xFF) / 255.0
			var tint := 0.9 + 0.2 * float((hsh >> 16) & 0xFF) / 255.0
			var phase := float((hsh >> 32) & 0xFF) / 255.0 * TAU
			# Palmiers : bande côtière basse et plate.
			var palm_p := (1.0 - smoothstep(14.0, 30.0, h)) * (1.0 - smoothstep(0.25, 0.4, slope)) * 0.5
			# Arbres : collines humides, pas trop haut, pas trop raide, pas dans les cendres.
			var broad_p := smoothstep(4.0, 12.0, h) * (1.0 - smoothstep(320.0, 520.0, h)) * (1.0 - smoothstep(0.35, 0.55, slope)) * (0.15 + 0.85 * wet) * (1.0 - ash * 0.9) * 0.6
			var kind := -1
			if r < palm_p:
				kind = variant
			elif r < palm_p + broad_p:
				kind = VARIANTS + variant
			if kind < 0:
				continue
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
			var origin := Vector3(x, h - 0.15, z)
			var arr: PackedFloat32Array = data[kind]
			arr.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, origin.x,
				basis.x.y, basis.y.y, basis.z.y, origin.y,
				basis.x.z, basis.y.z, basis.z.z, origin.z,
				tint, tint * (0.97 + 0.06 * jx), tint * (0.95 + 0.1 * jz), 1.0,
				phase, kinds[kind].h * scale, 0.0, 0.0]))
			data[kind] = arr
			var pa: PackedVector3Array = positions[kind]
			pa.append(origin)
			positions[kind] = pa
			tree_count += 1

	for k in kinds.size():
		var g := {"data": data[k], "pos": positions[k], "count": positions[k].size()}
		g["near"] = _make_instance(kinds[k].near, true)
		g["far"] = _make_instance(kinds[k].far, false)
		_groups.append(g)
	var t2 := Time.get_ticks_msec()
	print("Végétation : %d arbres (%d ms de maillages, %d ms de placement)" % [tree_count, t1 - t0, t2 - t1])


static func _hash32(x: int) -> int:
	# Mélange entier sur 32 bits (Wang/« hash32 ») : aucun débordement signé, identique partout.
	x = x & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	return ((x >> 16) ^ x) & 0xFFFFFFFF


static func _hash(i: int, j: int, seed_value: int) -> int:
	var base: int = (i * 73856093) ^ (j * 19349663) ^ ((seed_value & 0xFFFFFFFF) * 83492791)
	var h1 := _hash32(base)
	var h2 := _hash32(base ^ 0x9E3779B9 ^ h1)
	return h1 | (h2 << 32)


func _make_instance(mesh: ArrayMesh, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true        # nécessaire avec custom_data (le rendu Compatibility perd la couleur sinon)
	mm.use_custom_data = true   # x = phase du vent, y = hauteur de l'arbre
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shadows and OS.get_environment("ALIZE_TREESHADOW") == "0":
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## Répartit les instances entre le maillage détaillé (près de la caméra) et la silhouette (loin).
func update_lod(cam_pos: Vector3) -> void:
	_last_cam = cam_pos
	var d2 := LOD_DISTANCE * LOD_DISTANCE
	for g in _groups:
		var count: int = g.count
		if count == 0:
			continue
		var data: PackedFloat32Array = g.data
		var pos: PackedVector3Array = g.pos
		var near := PackedFloat32Array()
		var far := PackedFloat32Array()
		var near_n := 0
		var far_n := 0
		for i in count:
			var s := i * STRIDE
			if pos[i].distance_squared_to(cam_pos) < d2:
				near.append_array(data.slice(s, s + STRIDE))
				near_n += 1
			else:
				far.append_array(data.slice(s, s + STRIDE))
				far_n += 1
		_apply(g.near, near, near_n)
		_apply(g.far, far, far_n)


static func _apply(mmi: MultiMeshInstance3D, buf: PackedFloat32Array, n: int) -> void:
	var mm := mmi.multimesh
	if mm.instance_count != n:
		mm.instance_count = n
	if n > 0:
		mm.buffer = buf
	mmi.visible = n > 0


func _process(delta: float) -> void:
	wind_time += delta
	if material:
		material.set_shader_parameter("sway_time", wind_time)
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(_last_cam) > 25.0:
			update_lod(cam.global_position)
