## Textures de sol Poly Haven (CC0) empilées en tableaux de textures (albédo, normales, ARM) pour
## le shader de terrain : un seul échantillonneur par carte, et une couche par type de sol.
## Construit une fois au lancement : décompression, mipmaps, compression S3TC si disponible.
class_name TerrainTextures
extends RefCounted

const DIR := "res://assets/polyhaven/textures/"
## Ordre des couches (indices utilisés par le shader).
const LAYERS := [
	"coast_sand_01",        # 0 sable sec
	"damp_beach_sand",      # 1 sable mouillé
	"grass_ground",         # 2 herbe
	"forest_floor",         # 3 sous-bois
	"aerial_grass_rock",    # 4 hauteurs
	"dark_rock",            # 5 roche (cliff_side a des strates trop régulières en carreaux)
	"dark_rock",            # 6 basalte (même texture, teinte et échelle différentes)
	"coral_ground_02",      # 7 fond du lagon
	"brown_mud_leaves_01",  # 8 cendres / boue
]
const SIZE := 1024

static var _cache := {}


## Retourne {albedo: Texture2DArray, normal: Texture2DArray, arm: Texture2DArray, mean: PackedVector3Array}
## (mean : couleur moyenne sRGB de chaque couche, pour recaler la teinte dans le shader).
static func build() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var t0 := Time.get_ticks_msec()
	var result := {"mean": PackedVector3Array()}
	for map in ["Diffuse", "nor_gl", "arm"]:
		var images: Array[Image] = []
		for slug in LAYERS:
			var path := "%s%s/%s_%s_1k.jpg" % [DIR, slug, slug, map]
			var img := _load_image(path)
			if img == null:
				img = Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
				img.fill(Color(0.5, 0.5, 1.0) if map == "nor_gl" else Color(0.5, 0.5, 0.5))
			if map == "Diffuse":
				result.mean.append(_mean_srgb(img))
			images.append(img)
		# Compression VRAM (S3TC via etcpak dans les modèles d'export) : toutes les couches ou aucune.
		var compressed: Array[Image] = []
		for img in images:
			var c := img.duplicate() as Image
			if c.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC) != OK or not c.is_compressed():
				compressed.clear()
				break
			compressed.append(c)
		if compressed.size() == images.size():
			images = compressed
		var arr := Texture2DArray.new()
		var err := arr.create_from_images(images)
		if err != OK:
			push_error("Tableau de textures %s : erreur %d" % [map, err])
		result[{"Diffuse": "albedo", "nor_gl": "normal", "arm": "arm"}[map]] = arr
	_cache = result
	print("Textures de terrain : %d couches, %d ms" % [LAYERS.size(), Time.get_ticks_msec() - t0])
	return result


static func _load_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		push_warning("Texture de sol absente : " + path)
		return null
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	if img.get_width() != SIZE or img.get_height() != SIZE:
		img.resize(SIZE, SIZE, Image.INTERPOLATE_CUBIC)
	if not img.has_mipmaps():
		img.generate_mipmaps()
	return img


static func _mean_srgb(img: Image) -> Vector3:
	var small := img.duplicate() as Image
	if small.is_compressed():
		small.decompress()
	small.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var acc := Vector3.ZERO
	for y in 32:
		for x in 32:
			var c := small.get_pixel(x, y)
			acc += Vector3(c.r, c.g, c.b)
	return acc / 1024.0
