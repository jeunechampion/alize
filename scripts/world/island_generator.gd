## Génère le relief d'une île à partir d'une seed, de façon déterministe.
##
## Algorithmes : bruit fractal (Perlin 1985, Musgrave 1989) avec déformation de domaine
## (domain warping, Quilez) pour le relief et le trait de côte ; cône volcanique analytique ;
## compression des basses altitudes pour former les plages ; plateau récifal puis tombant
## pour le fond marin. L'érosion hydraulique arrivera dans le module natif (étape 4).
##
## Rivières : tracées par descente de pente depuis les flancs du volcan jusqu'à la mer, puis
## creusées dans le champ de hauteurs (niveau d'eau strictement décroissant vers l'aval).
##
## Le relief est un champ de hauteurs de SIZE x SIZE échantillons couvrant EXTENT mètres.
class_name IslandGenerator
extends RefCounted

const SIZE := 641                 # échantillons par côté (640 quads)
const EXTENT := 5000.0            # mètres couverts par le champ de hauteurs
const SEA_LEVEL := 0.0
const DEEP_SEA := -160.0          # profondeur du fond hors de l'île

var world_seed: int
var spacing: float = EXTENT / float(SIZE - 1)
var heights := PackedFloat32Array()
var params := {}
var rivers: Array = []             # [{points: PackedVector3Array (x, niveau d'eau, z), widths: PackedFloat32Array}]
var river_dist := PackedFloat32Array()   # par échantillon : distance (m) à la rivière la plus proche, bornée
const RIVER_DIST_MAX := 60.0

var _n_warp_x: FastNoiseLite
var _n_warp_z: FastNoiseLite
var _n_coast: FastNoiseLite
var _n_mount: FastNoiseLite
var _n_low: FastNoiseLite
var _n_reef: FastNoiseLite

var _center := Vector2.ZERO
var _radius := 1400.0
var _coast_warp := 0.32
var _peak := 650.0
var _volcano_pos := Vector2.ZERO
var _volcano_height := 850.0
var _volcano_radius := 700.0
var _crater_radius := 90.0
var _crater_depth := 110.0
var _warp_amp := 220.0


func _init(seed_value: int) -> void:
	world_seed = seed_value
	_setup()


func _setup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	_center = Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0))
	_radius = rng.randf_range(1250.0, 1500.0)
	_coast_warp = rng.randf_range(0.26, 0.40)
	_peak = rng.randf_range(520.0, 780.0)
	var vdir := rng.randf() * TAU
	_volcano_pos = _center + Vector2.from_angle(vdir) * rng.randf_range(250.0, 480.0)
	_volcano_height = rng.randf_range(720.0, 1000.0)
	_volcano_radius = rng.randf_range(620.0, 820.0)
	_crater_radius = rng.randf_range(70.0, 115.0)
	_crater_depth = rng.randf_range(80.0, 140.0)
	_warp_amp = rng.randf_range(160.0, 260.0)
	params = {
		"center": _center, "radius": _radius, "peak": _peak,
		"volcano_pos": _volcano_pos, "volcano_height": _volcano_height,
		"volcano_radius": _volcano_radius, "crater_radius": _crater_radius,
	}

	_n_warp_x = _make_noise(rng.randi(), 1.0 / 1100.0, FastNoiseLite.FRACTAL_FBM, 2)
	_n_warp_z = _make_noise(rng.randi(), 1.0 / 1100.0, FastNoiseLite.FRACTAL_FBM, 2)
	_n_coast = _make_noise(rng.randi(), 1.0 / 700.0, FastNoiseLite.FRACTAL_FBM, 3)
	_n_mount = _make_noise(rng.randi(), 1.0 / 900.0, FastNoiseLite.FRACTAL_RIDGED, 5)
	_n_low = _make_noise(rng.randi(), 1.0 / 260.0, FastNoiseLite.FRACTAL_FBM, 4)
	_n_reef = _make_noise(rng.randi(), 1.0 / 55.0, FastNoiseLite.FRACTAL_FBM, 2)


static func _make_noise(seed_value: int, frequency: float, fractal: int, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.05
	n.fractal_gain = 0.5
	return n


## Hauteur analytique en un point du monde (mètres), avant échantillonnage.
func height_function(x: float, z: float) -> float:
	# Déformation de domaine : casse la régularité du bruit.
	var wx := x + _n_warp_x.get_noise_2d(x, z) * _warp_amp
	var wz := z + _n_warp_z.get_noise_2d(x, z) * _warp_amp

	var d := Vector2(wx, wz) - _center
	var r := d.length() / _radius
	var coast := _n_coast.get_noise_2d(wx, wz)          # [-1, 1]
	var rw := r * (1.0 + _coast_warp * coast)            # rayon déformé : le trait de côte

	# Masque terre : 1 au centre, 0 à la côte (rw = 1) ; jamais de terre près du bord du champ.
	var land := 1.0 - smoothstep(0.78, 1.0, rw)
	land *= 1.0 - smoothstep(2100.0, 2350.0, Vector2(x, z).length())

	# Poids radial pour la montagne centrale (0 à la côte, 1 au centre).
	var mfac: float = clampf((1.0 - rw) / 0.85, 0.0, 1.0)
	mfac = mfac * mfac * (3.0 - 2.0 * mfac)

	var mount := _n_mount.get_noise_2d(wx, wz) * 0.5 + 0.5   # [0, 1], crêtes
	var low := _n_low.get_noise_2d(wx, wz) * 0.5 + 0.5       # [0, 1], collines
	var h_land := _peak * pow(mfac, 1.7) * (0.45 + 0.55 * mount)
	h_land += 70.0 * low * land + 22.0 * mfac

	# Volcan : cône lissé avec cratère.
	var rv := (Vector2(wx, wz) - _volcano_pos).length()
	var cone_t: float = clampf(1.0 - rv / _volcano_radius, 0.0, 1.0)
	var cone := _volcano_height * pow(cone_t, 1.35)
	cone += 40.0 * low * cone_t                           # flancs texturés
	h_land = maxf(h_land, cone)
	if rv < _crater_radius:
		h_land -= _crater_depth * smoothstep(_crater_radius, _crater_radius * 0.3, rv)

	# Plages : compression des basses altitudes (continue en 20 m).
	if h_land > 0.0 and h_land < 20.0:
		h_land = 20.0 * pow(h_land / 20.0, 2.1)

	# Fond marin : plateau récifal (lagon) puis tombant, puis grand fond.
	var sea := -2.5
	sea -= 10.0 * smoothstep(1.0, 1.28, rw)
	sea -= 95.0 * smoothstep(1.28, 1.75, rw)
	sea -= (-DEEP_SEA - 107.5) * smoothstep(1.75, 2.8, rw)
	var reef := _n_reef.get_noise_2d(wx, wz)
	sea += 3.2 * reef * (1.0 - smoothstep(1.18, 1.36, rw)) * smoothstep(0.98, 1.1, rw)  # patates de corail

	return lerpf(sea, h_land, land)


## Calcule tout le champ de hauteurs (en parallèle par lignes).
func generate() -> void:
	heights.resize(SIZE * SIZE)
	var rows: Array = []
	rows.resize(SIZE)
	var task := WorkerThreadPool.add_group_task(_compute_row.bind(rows), SIZE, -1, true, "IslandHeights")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for j in SIZE:
		var row: PackedFloat32Array = rows[j]
		for i in SIZE:
			heights[j * SIZE + i] = row[i]
	_carve_rivers()


func _compute_row(j: int, rows: Array) -> void:
	var row := PackedFloat32Array()
	row.resize(SIZE)
	var z := -EXTENT * 0.5 + j * spacing
	for i in SIZE:
		var x := -EXTENT * 0.5 + i * spacing
		row[i] = height_function(x, z)
	rows[j] = row


## Rivières : sources sur les flancs du volcan et les hautes collines, descente de pente avec un peu
## d'inertie, arrêt à la mer. Le niveau d'eau ne remonte jamais ; si le relief barre la route de plus
## de 30 m, la rivière s'arrête (elle serait un lac). Le lit est ensuite creusé : chenal au centre,
## berges en pente douce. Déterministe : générateur propre à la seed.
func _carve_rivers() -> void:
	rivers.clear()
	river_dist.resize(SIZE * SIZE)
	river_dist.fill(RIVER_DIST_MAX)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x52495645
	var wanted := rng.randi_range(3, 5)
	var tries := 0
	while rivers.size() < wanted and tries < 40:
		tries += 1
		var ang := rng.randf() * TAU
		var src := _volcano_pos + Vector2.from_angle(ang) * _volcano_radius * rng.randf_range(0.42, 0.8)
		if rng.randf() < 0.3:   # parfois depuis les collines centrales
			src = _center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(200.0, 700.0)
		var h0 := height_at(src.x, src.y)
		if h0 < 110.0:
			continue
		# Pas deux sources trop proches.
		var too_close := false
		for r in rivers:
			var p0: Vector3 = r.points[0]
			if Vector2(p0.x, p0.z).distance_to(src) < 350.0:
				too_close = true
		if too_close:
			continue
		var river := _trace_river(src, h0, rng)
		if river.is_empty():
			continue
		rivers.append(river)
	for r in rivers:
		_carve_one(r)


func _trace_river(src: Vector2, h0: float, rng: RandomNumberGenerator) -> Dictionary:
	var step := 6.0
	var points := PackedVector3Array()
	var widths := PackedFloat32Array()
	var surfaces := PackedFloat32Array()   # hauteur d'origine du relief le long du tracé
	var p := src
	var level := h0
	var dir := Vector2.ZERO
	var dist := 0.0
	var wobble := FastNoiseLite.new()
	wobble.seed = rng.randi()
	wobble.frequency = 1.0 / 90.0
	for k in 2500:
		var g := gradient_at(p.x, p.y)
		var down := -g
		if down.length() < 1e-4:
			down = dir if dir != Vector2.ZERO else Vector2.from_angle(rng.randf() * TAU)
		down = down.normalized()
		# Inertie et méandres : la rivière ne suit pas exactement la ligne de plus grande pente.
		var w := wobble.get_noise_2d(p.x, p.y)
		down = down.rotated(w * 0.7)
		dir = (dir * 0.55 + down * 0.45).normalized() if dir != Vector2.ZERO else down
		p += dir * step
		dist += step
		if absf(p.x) > EXTENT * 0.5 - 20.0 or absf(p.y) > EXTENT * 0.5 - 20.0:
			return {}
		var hp := height_at(p.x, p.y)
		# Niveau d'eau strictement décroissant, collé au relief (0,3 m sous la surface d'origine).
		level = minf(level - 0.001, hp - 0.3)
		if hp - level > 30.0:
			return {}   # barré par le relief : ce serait un lac, on abandonne
		var width := clampf(2.5 + dist * 0.0045, 2.5, 11.0)
		points.append(Vector3(p.x, level, p.y))
		widths.append(width)
		surfaces.append(hp)
		if hp < SEA_LEVEL + 0.3 or level < SEA_LEVEL + 0.2:
			break
	if points.size() < 40 or points[points.size() - 1].y > SEA_LEVEL + 3.0:
		return {}
	return {"points": points, "widths": widths, "surfaces": surfaces}


func _carve_one(river: Dictionary) -> void:
	var points: PackedVector3Array = river.points
	var widths: PackedFloat32Array = river.widths
	var surfaces: PackedFloat32Array = river.surfaces
	var half := EXTENT * 0.5
	for k in points.size():
		var pt := points[k]
		var w := widths[k]
		# Portée du creusement : berges à 30 % jusqu'à rejoindre le relief d'origine (pas de mur).
		var reach := w * 1.5 + 14.0 + maxf(surfaces[k] - pt.y, 0.0) / 0.30
		var depth := 1.0 + w * 0.22
		var ci := int((pt.x + half) / spacing)
		var cj := int((pt.z + half) / spacing)
		var n := int(ceil(reach / spacing)) + 1
		for j in range(cj - n, cj + n + 1):
			if j < 0 or j >= SIZE:
				continue
			for i in range(ci - n, ci + n + 1):
				if i < 0 or i >= SIZE:
					continue
				var sx := -half + i * spacing
				var sz := -half + j * spacing
				var d := Vector2(sx - pt.x, sz - pt.z).length()
				if d > reach:
					continue
				var idx := j * SIZE + i
				var target: float
				if d < w:
					# Chenal : profil parabolique sous le niveau de l'eau.
					target = pt.y - depth * (1.0 - (d / w) * (d / w))
				else:
					# Berges : pente douce depuis le bord de l'eau, sans dépasser le relief existant.
					target = pt.y + (d - w) * 0.30
				if target < heights[idx]:
					heights[idx] = target
				elif d >= w and d <= w * 1.3 and heights[idx] < pt.y + 0.05:
					heights[idx] = pt.y + 0.05   # petite levée : le bord de l'eau ne flotte pas sur une berge basse
				var rd := maxf(d - w, 0.0)
				if rd < river_dist[idx]:
					river_dist[idx] = rd


## Distance (m) à la rivière la plus proche (bord de l'eau), bornée à RIVER_DIST_MAX.
func river_distance_at(x: float, z: float) -> float:
	if river_dist.is_empty():
		return RIVER_DIST_MAX
	var fx := (x + EXTENT * 0.5) / spacing
	var fz := (z + EXTENT * 0.5) / spacing
	if fx < 0.0 or fz < 0.0 or fx > SIZE - 1 or fz > SIZE - 1:
		return RIVER_DIST_MAX
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := river_dist[clampi(j, 0, SIZE - 1) * SIZE + clampi(i, 0, SIZE - 1)]
	var b := river_dist[clampi(j, 0, SIZE - 1) * SIZE + clampi(i + 1, 0, SIZE - 1)]
	var c := river_dist[clampi(j + 1, 0, SIZE - 1) * SIZE + clampi(i, 0, SIZE - 1)]
	var d := river_dist[clampi(j + 1, 0, SIZE - 1) * SIZE + clampi(i + 1, 0, SIZE - 1)]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Image (FORMAT_RF) de la distance aux rivières, pour le shader de terrain.
func make_river_image() -> Image:
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, river_dist.to_byte_array())


## Hauteur d'un échantillon de la grille (indices bornés).
func sample(i: int, j: int) -> float:
	i = clampi(i, 0, SIZE - 1)
	j = clampi(j, 0, SIZE - 1)
	return heights[j * SIZE + i]


## Hauteur interpolée (bilinéaire) en un point du monde. Hors du champ : grand fond.
func height_at(x: float, z: float) -> float:
	var fx := (x + EXTENT * 0.5) / spacing
	var fz := (z + EXTENT * 0.5) / spacing
	if fx < 0.0 or fz < 0.0 or fx > SIZE - 1 or fz > SIZE - 1:
		return DEEP_SEA
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := sample(i, j)
	var h10 := sample(i + 1, j)
	var h01 := sample(i, j + 1)
	var h11 := sample(i + 1, j + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Normale du sol en un point du monde.
func normal_at(x: float, z: float) -> Vector3:
	var e := spacing
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(-(hr - hl) / (2.0 * e), 1.0, -(hu - hd) / (2.0 * e)).normalized()


## Gradient horizontal (dh/dx, dh/dz) en un point du monde.
func gradient_at(x: float, z: float) -> Vector2:
	var e := spacing
	return Vector2((height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e),
		(height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e))


## Image flottante (FORMAT_RF) du champ de hauteurs, pour les shaders (eau, brume).
func make_height_image() -> Image:
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, heights.to_byte_array())


## Empreinte tolérante (arrondie) : comparable entre machines même si un bit de bruit diffère.
func fingerprint_coarse() -> String:
	var s: Dictionary = stats()
	var sum := 0.0
	for h in heights:
		sum += h
	return "%.4f|%.1f|%.1f|%.0f" % [s.land_fraction, s.max_height, s.min_height, sum / 1000.0]


## Empreinte exacte du relief (déterminisme sur une même machine).
func fingerprint() -> String:
	return String.num_uint64(_hash_heights())


func _hash_heights() -> int:
	# FNV-1a sur les octets, tronqué : identique sur toutes les plateformes.
	var bytes := heights.to_byte_array()
	var h: int = 2166136261
	var n := bytes.size()
	var i := 0
	while i < n:
		h = ((h ^ int(bytes[i])) * 16777619) & 0xFFFFFFFF
		i += 37  # échantillonnage : suffisant pour détecter une différence, rapide
	return h


## Statistiques utiles (tests et réglages).
func stats() -> Dictionary:
	var land := 0
	var beach := 0
	var maxh := -1e9
	var minh := 1e9
	for h in heights:
		if h > SEA_LEVEL:
			land += 1
			if h < 6.0:
				beach += 1
		maxh = maxf(maxh, h)
		minh = minf(minh, h)
	var total := float(heights.size())
	var river_len := 0.0
	for r in rivers:
		river_len += (r.points as PackedVector3Array).size() * 6.0
	return {
		"land_fraction": land / total,
		"beach_fraction": beach / total,
		"max_height": maxh,
		"min_height": minh,
		"land_km2": land / total * (EXTENT / 1000.0) * (EXTENT / 1000.0),
		"rivers": rivers.size(),
		"river_km": river_len / 1000.0,
	}
