## Global game state (autoload "Game").
## Holds the world seed, the clock of the day, and a few settings.
extends Node

signal seed_changed(new_seed: int)

## Mot ou nombre tapé par le joueur ; converti en entier par [method seed_from_text].
var seed_text: String = "alize"
var world_seed: int = 0

## Heure du jour, en heures décimales (0..24). 8.5 = 8h30.
var spawn_dist := 900.0
var spawn_alt := 240.0
var spawn_side := 0.0
var spawn_river := -1      # >= 0 : départ au-dessus de cette rivière, face à l'amont
var time_of_day: float = 8.5
## Durée d'une journée complète en secondes réelles (3600 = 1 h, comme décidé).
var day_length_seconds: float = 3600.0
## Multiplicateur de vitesse du temps (touche T).
var time_speed: float = 1.0
const TIME_SPEEDS := [1.0, 30.0, 240.0]
var _time_speed_index := 0

var autotest: bool = false
var shot_only: bool = false
var autotest_dir: String = ""
var start_time_msec: int = 0

func _ready() -> void:
	start_time_msec = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--autotest":
			autotest = true
		elif a == "--shot-only":
			autotest = true
			shot_only = true
		elif a.begins_with("--autotest-dir="):
			autotest_dir = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			seed_text = a.get_slice("=", 1)
		elif a.begins_with("--time="):
			time_of_day = float(a.get_slice("=", 1))
		elif a.begins_with("--spawn-dist="):   # distance à la côte le long de l'approche (négatif : au-dessus de l'île)
			spawn_dist = float(a.get_slice("=", 1))
		elif a.begins_with("--spawn-alt="):
			spawn_alt = float(a.get_slice("=", 1))
		elif a.begins_with("--spawn-side="):   # décalage latéral (m)
			spawn_side = float(a.get_slice("=", 1))
		elif a.begins_with("--spawn-river="):
			spawn_river = int(a.get_slice("=", 1))
	world_seed = seed_from_text(seed_text)

## Même texte -> même graine, sur toutes les machines (hachage FNV-1a 32 bits, sans dépendre de la plateforme).
static func seed_from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_valid_int():
		return int(t)
	var h: int = 2166136261
	for b in t.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return h

func set_seed_text(text: String) -> void:
	seed_text = text
	world_seed = seed_from_text(text)
	seed_changed.emit(world_seed)

## Niveau de détail de la végétation (touche G) : 0 léger, 1 normal, 2 riche.
var detail_level := 1
const DETAIL_NAMES := ["léger", "normal", "riche"]

func cycle_detail() -> void:
	detail_level = (detail_level + 1) % 3


func cycle_time_speed() -> void:
	_time_speed_index = (_time_speed_index + 1) % TIME_SPEEDS.size()
	time_speed = TIME_SPEEDS[_time_speed_index]

func advance_time(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta * time_speed * 24.0 / day_length_seconds, 24.0)

func time_string() -> String:
	var h := int(time_of_day)
	var m := int((time_of_day - h) * 60.0)
	return "%02d:%02d" % [h, m]
