## Génère le relief d'une île à partir d'une seed, de façon déterministe.
##
## Algorithmes : bruit fractal (Perlin 1985, Musgrave 1989) avec déformation de domaine
## (domain warping, Quilez) pour le relief et le trait de côte ; cône volcanique analytique ;
## compression des basses altitudes pour former les plages ; plateau récifal puis tombant
## pour le fond marin. L'érosion hydraulique arrivera dans le module natif (étape 4).
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

	# Masque terre : 1 au centre, 0 à la côte (rw = 1).
	var land := 1.0 - smoothstep(0.78, 1.0, rw)

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


func _compute_row(j: int, rows: Array) -> void:
	var row := PackedFloat32Array()
	row.resize(SIZE)
	var z := -EXTENT * 0.5 + j * spacing
	for i in SIZE:
		var x := -EXTENT * 0.5 + i * spacing
		row[i] = height_function(x, z)
	rows[j] = row


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


## Empreinte du relief (pour vérifier le déterminisme entre machines).
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
	return {
		"land_fraction": land / total,
		"beach_fraction": beach / total,
		"max_height": maxh,
		"min_height": minh,
		"land_km2": land / total * (EXTENT / 1000.0) * (EXTENT / 1000.0),
	}
