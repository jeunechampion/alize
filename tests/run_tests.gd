## Tests sans fenêtre : `godot --headless --path . -s tests/run_tests.gd`
## Vérifie le déterminisme du générateur, la forme de l'île, et le modèle de vol.
extends SceneTree

const GameScript = preload("res://scripts/game.gd")

var failures := 0
var checks := 0


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


var _done := false


## Les nœuds (oiseau, océan) ont besoin d'un arbre de scène prêt : on lance tout à la première image.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	run_all()
	return true


func run_all() -> void:
	print("== Générateur d'île ==")
	var t0 := Time.get_ticks_msec()
	var g1 := IslandGenerator.new(GameScript.seed_from_text("alize"))
	g1.generate()
	var t1 := Time.get_ticks_msec()
	print("  génération : %d ms" % (t1 - t0))
	var g2 := IslandGenerator.new(GameScript.seed_from_text("alize"))
	g2.generate()
	check(g1.fingerprint() == g2.fingerprint(), "même seed -> même île (%s)" % g1.fingerprint())
	var g3 := IslandGenerator.new(GameScript.seed_from_text("autre"))
	g3.generate()
	check(g1.fingerprint() != g3.fingerprint(), "seed différente -> île différente")
	var s: Dictionary = g1.stats()
	print("  stats : ", s)
	check(s.land_fraction > 0.10 and s.land_fraction < 0.45, "part de terre raisonnable (%.2f)" % s.land_fraction)
	check(s.max_height > 550.0 and s.max_height < 1150.0, "sommet entre 550 et 1150 m (%.0f)" % s.max_height)
	check(s.beach_fraction > 0.004, "il y a des plages (%.3f)" % s.beach_fraction)
	check(s.min_height < -100.0, "il y a du grand fond (%.0f)" % s.min_height)
	check(absf(g1.height_at(0.0, 0.0) - g1.sample(320, 320)) < 0.01, "interpolation exacte sur un nœud")
	check(g1.height_at(-3000.0, 0.0) == IslandGenerator.DEEP_SEA, "hors du champ : grand fond")
	var n := g1.normal_at(g1.params.volcano_pos.x + 300.0, g1.params.volcano_pos.y)
	check(n.y < 0.999 and n.length() > 0.999, "normale sur le flanc du volcan inclinée")
	check(GameScript.seed_from_text("alize") == GameScript.seed_from_text(" alize "), "seed insensible aux espaces")
	check(GameScript.seed_from_text("12345") == 12345, "seed numérique littérale")

	print("== Modèle de vol ==")
	var m := FlightModel.new()
	print("  finesse théorique %.1f, vitesse de décrochage %.1f m/s" % [m.best_glide_ratio(), m.stall_speed()])
	check(m.best_glide_ratio() > 11.0 and m.best_glide_ratio() < 16.0, "finesse théorique entre 11 et 16")
	check(m.stall_speed() > 7.0 and m.stall_speed() < 10.0, "décrochage entre 7 et 10 m/s")

	# Plané rectiligne sans vent : 20 s.
	m.position = Vector3(0, 500, 0)
	m.velocity = Vector3(0, 0, -12)
	m.aim_yaw = 0.0
	m.aim_pitch = deg_to_rad(-4.0)
	var dt := 1.0 / 60.0
	for i in 300:
		m.step(dt, Vector3.ZERO)
	var p0 := m.position
	for i in 900:
		m.step(dt, Vector3.ZERO)
	var dx := Vector2(m.position.x - p0.x, m.position.z - p0.z).length()
	var dy := p0.y - m.position.y
	var ratio := dx / maxf(dy, 0.01)
	print("  plané : %.0f m pour %.0f m de descente, finesse %.1f, vitesse %.1f m/s" % [dx, dy, ratio, m.velocity.length()])
	check(ratio > 8.0 and ratio < 18.0, "finesse mesurée entre 8 et 18")
	check(m.velocity.length() > 9.0 and m.velocity.length() < 18.0, "vitesse de plané entre 9 et 18 m/s")
	check(absf(m.bank) < 0.05, "pas de roulis parasite en ligne droite")
	check(absf(m.position.x) < 5.0, "trajectoire droite")

	# Virage : cap visé +90°, doit tourner à droite.
	var h0 := m.heading
	m.aim_yaw = h0 + deg_to_rad(90.0)
	var turned := 0.0
	var tturn := -1.0
	for i in 600:
		m.step(dt, Vector3.ZERO)
		turned = wrapf(m.heading - h0, -PI, PI)
		if tturn < 0.0 and turned > deg_to_rad(85.0):
			tturn = i * dt
	print("  virage de 90° en %.1f s, roulis max attendu > 30°" % tturn)
	check(tturn > 0.0 and tturn < 8.0, "virage de 90° en moins de 8 s")
	check(turned > 0.0, "un cap visé à droite fait tourner à droite")

	# Battement : doit monter.
	m.aim_yaw = m.heading
	m.aim_pitch = deg_to_rad(6.0)
	m.flapping = true
	var y0 := m.position.y
	var e0 := m.energy
	for i in 480:
		m.step(dt, Vector3.ZERO)
	print("  battement 8 s : %+.0f m, énergie %.0f -> %.0f" % [m.position.y - y0, e0, m.energy])
	check(m.position.y > y0 + 5.0, "le battement fait monter")
	check(m.energy < e0, "le battement coûte de l'énergie")
	m.flapping = false

	# Piqué : accélère.
	m.diving = true
	m.aim_pitch = deg_to_rad(-40.0)
	var vmax := 0.0
	for i in 360:
		m.step(dt, Vector3.ZERO)
		vmax = maxf(vmax, m.velocity.length())
	print("  piqué 6 s : vitesse max %.1f m/s (%.0f km/h)" % [vmax, vmax * 3.6])
	check(vmax > 22.0, "le piqué dépasse 22 m/s")
	m.diving = false

	# Décrochage : trop lent avec forte incidence -> stalled puis reprise.
	m.velocity = Vector3(0, 0, -5.0)
	m.aim_pitch = deg_to_rad(30.0)
	var saw_stall := false
	for i in 240:
		m.step(dt, Vector3.ZERO)
		saw_stall = saw_stall or m.stalled
	print("  décrochage observé : ", saw_stall)
	check(saw_stall, "un vol trop lent cabré décroche")

	# Thermique : l'air monte au centre, descend en couronne, rien au-dessus du sommet.
	print("== Vent ==")
	var th := Thermal.new(Vector2(100, 100), 0.0, 1000.0, 80.0, 3.0)
	check(th.sample(Vector3(100, 300, 100), Vector3.ZERO).y > 2.5, "thermique : montée au centre")
	check(th.sample(Vector3(100 + 95, 300, 100), Vector3.ZERO).y < 0.0, "thermique : couronne descendante")
	check(th.sample(Vector3(100, 1200, 100), Vector3.ZERO).y == 0.0, "thermique : rien au-dessus du sommet")
	var w := WindField.new(g1)
	var far_sea := w.sample(Vector3(-2400, 100, 0))
	check(absf(far_sea.y) < 0.01, "en mer, pas de vent vertical")

	print("== Atmosphère ==")
	var noon := Atmosphere.sun_direction(12.0, 15.0)
	check(noon.y > 0.96 and absf(noon.x) < 0.01, "à midi le soleil est presque au zénith (lat. 15°)")
	var dawn := Atmosphere.sun_direction(6.0, 15.0)
	check(absf(dawn.y) < 0.01 and dawn.x > 0.99, "à 6 h le soleil se lève à l'est")
	var zen_noon := Atmosphere.atmosphere_color(Vector3.UP, noon)
	check(zen_noon.z > zen_noon.x and zen_noon.z > zen_noon.y, "le zénith de midi est bleu")
	var tr_low := Atmosphere.sun_transmittance(Atmosphere.sun_direction(6.5, 15.0))
	check(tr_low.x > tr_low.z * 3.0, "le soleil bas est rougi par l'atmosphère")
	var hz_noon := Atmosphere.atmosphere_color(Vector3(1.0, 0.03, 0.0).normalized(), noon)
	var lum := func(c: Vector3) -> float: return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
	# Diffusion simple : l'horizon de midi est à peu près aussi lumineux que le zénith (la diffusion
	# multiple, absente ici, l'éclaircirait encore ; à faire dans l'étape ciel).
	check(lum.call(hz_noon) > 0.8 * lum.call(zen_noon), "l'horizon de midi n'est pas plus sombre que le zénith")

	print("== Océan ==")
	var ocean := Ocean.new()
	get_root().add_child(ocean)
	ocean.setup(ImageTexture.create_from_image(g1.make_height_image()), g1)
	var center: Vector2 = g1.params.center
	var dir := Vector2(1.0, 0.0)
	var coast := center
	for i in 400:
		coast += dir * 10.0
		if g1.height_at(coast.x, coast.y) < IslandGenerator.SEA_LEVEL:
			break
	var lagoon := coast + dir * 60.0
	var lo := 1e9
	var hi := -1e9
	for i in 240:
		var hgt := ocean.surface_height(lagoon.x, lagoon.y, i * 0.1)
		lo = minf(lo, hgt)
		hi = maxf(hi, hgt)
	print("  lagon (fond %.1f m) : vagues de %.2f m crête à creux" % [g1.height_at(lagoon.x, lagoon.y), hi - lo])
	check(hi - lo < 0.9, "le lagon est calme (amortissement par la profondeur)")
	lo = 1e9
	hi = -1e9
	for i in 240:
		var hgt := ocean.surface_height(-2400.0, 300.0, i * 0.1)
		lo = minf(lo, hgt)
		hi = maxf(hi, hgt)
	print("  grand large : vagues de %.2f m crête à creux" % (hi - lo))
	check(hi - lo > 1.5 and hi - lo < 3.2, "la houle du large fait entre 1,5 et 3,2 m")

	print("== Décollage ==")
	var wf := WindField.new(g1)
	var bird := Bird.new()
	get_root().add_child(bird)
	bird.setup(wf, g1, ocean)
	bird.input_enabled = false
	var crashes := 0
	bird.crashed.connect(func(_hard: bool): crashes += 1)
	var beach := coast - dir * 25.0
	var bh := g1.height_at(beach.x, beach.y)
	print("  plage à h = %.2f m, vent %s" % [bh, wf.base_wind])
	bird.spawn(Vector3(beach.x, bh + 0.22, beach.y), FlightModel.heading_of(Vector3(wf.base_wind.x, 0.0, wf.base_wind.z)), 0.0)
	bird._land()
	check(bird.state == Bird.State.LANDED, "posé sur la plage, face au vent arrière")
	bird.model.flapping = true
	bird.model.aim_pitch = 0.0
	for i in 360:
		bird.model.aim_yaw = bird.model.heading   # le joueur ne tire pas sur la visée
		bird._physics_process(dt)
	print("  après 6 s : état %s, altitude %.1f m, %d crash(s)" % [bird.state_name(), bird.model.position.y - bh, crashes])
	check(bird.state == Bird.State.FLYING, "décollage vent arrière depuis la plage : en vol")
	check(crashes == 0, "décollage sans crash")
	# Depuis l'eau.
	bird.model.flapping = false
	var sea_pt := coast + dir * 250.0
	print("  point en mer : fond à %.1f m" % g1.height_at(sea_pt.x, sea_pt.y))
	bird.spawn(Vector3(sea_pt.x, 0.3, sea_pt.y), 0.0, 3.0)
	bird.model.velocity = Vector3(0, -1.0, 0)
	for i in 30:
		bird._physics_process(dt)
	check(bird.state == Bird.State.ON_WATER, "un contact lent avec la mer : à l'eau (%s)" % bird.state_name())
	crashes = 0
	bird.model.flapping = true
	for i in 360:
		bird.model.aim_yaw = bird.model.heading
		bird._physics_process(dt)
	check(bird.state == Bird.State.FLYING and crashes == 0, "décollage depuis l'eau sans crash (%s, %d)" % [bird.state_name(), crashes])
	bird.queue_free()
	ocean.queue_free()

	print("\n%d vérifications, %d échec(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)

