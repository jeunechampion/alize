## Affichage discret : arc d'énergie autour du réticule, vitesse et altitude, heure et seed,
## indicateur d'ascendance, aide (H).
class_name Hud
extends CanvasLayer

var bird: Bird
var show_help := false
var message := ""
var message_timer := 0.0
var _draw_node: Control
var _font: Font
var _fade_speed := 0.0
var _last_speed := 0.0
var _last_alt := 0.0


func _ready() -> void:
	_draw_node = Control.new()
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	_font = ThemeDB.fallback_font


func setup(p_bird: Bird) -> void:
	bird = p_bird


func flash(text: String, seconds: float = 3.0) -> void:
	message = text
	message_timer = seconds


func _process(dt: float) -> void:
	if message_timer > 0.0:
		message_timer -= dt
	_draw_node.queue_redraw()


func _on_draw() -> void:
	if bird == null:
		return
	var size := _draw_node.size
	var center := size * 0.5
	var m := bird.model
	var flying := bird.state == Bird.State.FLYING

	# Réticule + arc d'énergie.
	var white := Color(1, 1, 1, 0.75)
	var dim := Color(1, 1, 1, 0.22)
	_draw_node.draw_circle(center, 2.2, white)
	var r := 26.0
	var start := deg_to_rad(120.0)
	var span := deg_to_rad(300.0)
	_draw_node.draw_arc(center, r, start, start + span, 48, dim, 2.5, true)
	var frac := clampf(m.energy / m.energy_max, 0.0, 1.0)
	if frac > 0.0:
		var col := white if frac > 0.25 else Color(1.0, 0.55, 0.35, 0.9)
		_draw_node.draw_arc(center, r, start, start + span * frac, 48, col, 2.5, true)

	# Ascendance : une petite flèche à droite de l'arc quand l'air monte ou descend.
	if flying and absf(bird.last_updraft) > 0.4:
		var up := bird.last_updraft > 0.0
		var col2 := Color(0.55, 1.0, 0.7, 0.85) if up else Color(1.0, 0.7, 0.5, 0.7)
		var n := clampi(int(absf(bird.last_updraft) / 1.2) + 1, 1, 4)
		for i in n:
			var y := center.y + (i - (n - 1) * 0.5) * 9.0
			var tip := Vector2(center.x + r + 16.0, y + (-4.0 if up else 4.0))
			var base_y := y + (4.0 if up else -4.0)
			_draw_node.draw_polyline(PackedVector2Array([Vector2(tip.x - 5.0, base_y), tip, Vector2(tip.x + 5.0, base_y)]), col2, 1.5, true)

	# Vitesse et altitude, en bas à gauche.
	var speed := m.velocity.length() if flying else 0.0
	var alt := maxf(bird.model.position.y, 0.0)
	var text_col := Color(1, 1, 1, 0.8)
	var fs := 15
	_draw_node.draw_string(_font, Vector2(24, size.y - 52), "%3.0f km/h" % (speed * 3.6), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
	_draw_node.draw_string(_font, Vector2(24, size.y - 30), "%4.0f m  (%.0f m sol)" % [alt, maxf(bird.altitude_agl, 0.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
	if m.stalled and flying:
		_draw_node.draw_string(_font, Vector2(center.x - 40, center.y + 60), "décrochage", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.6, 0.4, 0.9))

	# Heure, seed, état, en haut à gauche.
	var top := "%s   seed %s" % [Game.time_string(), Game.seed_text]
	if Game.time_speed > 1.0:
		top += "   x%d" % int(Game.time_speed)
	_draw_node.draw_string(_font, Vector2(24, 34), top, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
	if not flying:
		_draw_node.draw_string(_font, Vector2(24, 56), bird.state_name() + "  (Espace pour décoller)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
	if message_timer > 0.0:
		var a := clampf(message_timer, 0.0, 1.0)
		_draw_node.draw_string(_font, Vector2(center.x - 160, size.y * 0.22), message, HORIZONTAL_ALIGNMENT_CENTER, 320, 20, Color(1, 1, 1, 0.85 * a))

	var help_lines: Array[String] = []
	if show_help:
		help_lines = [
			"Souris : diriger      Espace : battre des ailes",
			"S / clic droit : freiner      W : piquer      A-Q / D : roulis",
			"E : se poser      V : caméra      T : vitesse du temps",
			"N : nouvelle île      R : recommencer      H : aide      Échap : souris",
		]
	else:
		help_lines = ["H : aide"]
	var y := size.y - 30.0 - (help_lines.size() - 1) * 20.0
	for line in help_lines:
		_draw_node.draw_string(_font, Vector2(size.x - 24 - _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.55))
		y += 20.0
