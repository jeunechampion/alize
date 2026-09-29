## Fabrique des arbres en maillages, sans aucune ressource externe.
##
## Arbres à feuilles (banian, manguier, arbre à pain) : algorithme de colonisation d'espace
## (Runions, Lane & Prusinkiewicz, « Modeling Trees with a Space Colonization Algorithm », 2007) :
## des points de lumière sont semés dans le volume de la couronne, les branches poussent vers les
## points les plus proches et les consomment. Les rayons suivent le modèle des tubes (Murray) :
## le rayon d'un parent vaut la racine n-ième de la somme des rayons^n de ses enfants.
## Palmiers : tronc courbé par le vent, palmes en arceau.
class_name TreeBuilder
extends RefCounted

# L'alpha de la couleur des sommets vaut 1 pour le feuillage (frémit, translucide) et 0 pour le bois.
const LEAF_GREENS := [Color(0.20, 0.55, 0.22, 1.0), Color(0.28, 0.66, 0.26, 1.0), Color(0.16, 0.48, 0.20, 1.0), Color(0.36, 0.70, 0.30, 1.0)]
const PALM_GREEN := Color(0.30, 0.62, 0.24, 1.0)
const TRUNK_BROWN := Color(0.36, 0.26, 0.17, 0.0)
const PALM_TRUNK := Color(0.52, 0.42, 0.28, 0.0)


class Node2:
	var pos: Vector3
	var parent: int = -1
	var radius: float = 0.03
	var children: Array[int] = []
	var attractors: Array[Vector3] = []


## Génère un arbre à feuilles. Retourne un ArrayMesh à deux surfaces (tronc, feuillage).
static func build_broadleaf(rng: RandomNumberGenerator, height: float = 9.0, crown_radius: float = 4.5) -> ArrayMesh:
	# 1. Points d'attraction dans une couronne ellipsoïdale.
	var attractors: Array[Vector3] = []
	var crown_center := Vector3(0.0, height * 0.62, 0.0)
	var n_attr := 110
	while attractors.size() < n_attr:
		var p := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.55, 0.55), rng.randf_range(-1.0, 1.0))
		if p.length() > 1.0:
			continue
		attractors.append(crown_center + Vector3(p.x * crown_radius, p.y * height * 0.55, p.z * crown_radius))

	# 2. Croissance depuis le tronc.
	var nodes: Array[Node2] = []
	var root := Node2.new()
	root.pos = Vector3.ZERO
	nodes.append(root)
	var trunk_top := height * 0.38
	var y := 0.0
	var step := 0.75
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08))
	while y < trunk_top:
		y += step
		var n := Node2.new()
		n.pos = nodes[-1].pos + (Vector3.UP + lean).normalized() * step
		n.parent = nodes.size() - 1
		nodes[-1].children.append(nodes.size())
		nodes.append(n)

	var influence := 3.6
	var kill := 1.05
	for iter in 70:
		for n in nodes:
			n.attractors.clear()
		for a in attractors:
			var best := -1
			var best_d := influence
			for i in nodes.size():
				var d := nodes[i].pos.distance_to(a)
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				nodes[best].attractors.append(a)
		var grew := false
		var count := nodes.size()
		for i in count:
			var n := nodes[i]
			if n.attractors.is_empty():
				continue
			var dir := Vector3.ZERO
			for a in n.attractors:
				dir += (a - n.pos).normalized()
			dir += Vector3.UP * 0.15   # phototropisme léger
			if dir.length_squared() < 1e-6:
				continue
			var child := Node2.new()
			child.pos = n.pos + dir.normalized() * step
			child.parent = i
			n.children.append(nodes.size())
			nodes.append(child)
			grew = true
		# Les points atteints sont consommés.
		var remaining: Array[Vector3] = []
		for a in attractors:
			var eaten := false
			for i in range(count, nodes.size()):
				if nodes[i].pos.distance_to(a) < kill:
					eaten = true
					break
			if not eaten:
				remaining.append(a)
		attractors = remaining
		if not grew or attractors.is_empty():
			break

	# 3. Rayons par le modèle des tubes (des feuilles vers la racine).
	var tip_r := 0.025
	var order: Array[int] = []
	order.resize(nodes.size())
	for i in nodes.size():
		order[i] = i
	order.reverse()
	for i in order:
		var n := nodes[i]
		if n.children.is_empty():
			n.radius = tip_r
		else:
			var s := 0.0
			for c in n.children:
				s += pow(nodes[c].radius, 2.5)
			n.radius = pow(s, 1.0 / 2.5)
	nodes[0].radius = maxf(nodes[0].radius, 0.12)

	# 4. Maillage : cylindres coniques pour les branches, feuillage aux extrémités.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, nodes.size()):
		var n := nodes[i]
		var p := nodes[n.parent]
		if n.radius <= tip_r * 1.01 and n.children.is_empty():
			continue   # les brindilles terminales sont cachées par le feuillage
		var sides := 6 if p.radius > 0.06 else (4 if p.radius > 0.035 else 3)
		_add_branch(st, p.pos, n.pos, p.radius * 1.05, n.radius, sides, TRUNK_BROWN)
	st.generate_normals()
	var mesh := st.commit()

	var lf := SurfaceTool.new()
	lf.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, nodes.size()):
		var n := nodes[i]
		if n.children.size() <= 1 and n.radius <= tip_r * 1.6:
			var col: Color = LEAF_GREENS[rng.randi() % LEAF_GREENS.size()]
			_add_leaf_cluster(lf, n.pos, rng.randf_range(0.9, 1.5), col, rng)
	lf.generate_normals()
	lf.commit(mesh)
	return mesh


## Génère un cocotier : tronc courbé, couronne de palmes.
static func build_palm(rng: RandomNumberGenerator, height: float = 11.0, wind_dir := Vector2(-1.0, 0.25)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 9
	var bend := rng.randf_range(0.10, 0.28)
	var w := wind_dir.normalized()
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / segs
		var off := bend * height * t * t   # courbe parabolique, penchée sous le vent
		pts.append(Vector3(w.x * off, height * t, w.y * off))
	for i in segs:
		var r0 := lerpf(0.22, 0.12, float(i) / segs)
		var r1 := lerpf(0.22, 0.12, float(i + 1) / segs)
		_add_branch(st, pts[i], pts[i + 1], r0, r1, 6, PALM_TRUNK)
	st.generate_normals()
	var mesh := st.commit()

	var lf := SurfaceTool.new()
	lf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := pts[-1]
	var n_fronds := rng.randi_range(9, 13)
	for f in n_fronds:
		var ang := TAU * f / n_fronds + rng.randf_range(-0.15, 0.15)
		var tilt := rng.randf_range(0.15, 0.75)   # 0 = horizontale, 1 = tombante
		_add_frond(lf, top, ang, tilt, rng.randf_range(2.6, 3.6), PALM_GREEN.lerp(LEAF_GREENS[1], rng.randf() * 0.5))
	# Noix de coco.
	for c in 3:
		var a := rng.randf() * TAU
		_add_sphere(lf, top + Vector3(cos(a) * 0.25, -0.15, sin(a) * 0.25), 0.11, Color(0.45, 0.36, 0.2, 0.0))
	lf.generate_normals()
	lf.commit(mesh)
	return mesh


static func _add_branch(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color) -> void:
	var axis := (b - a)
	if axis.length_squared() < 1e-8:
		return
	axis = axis.normalized()
	var ref := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u)
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in sides:
		var t := TAU * i / sides
		var d := u * cos(t) + v * sin(t)
		ring_a.append(a + d * ra)
		ring_b.append(b + d * rb)
	for i in sides:
		var j := (i + 1) % sides
		st.set_color(col)
		# Deux triangles par face, sens horaire vu de l'extérieur.
		st.add_vertex(ring_a[i])
		st.add_vertex(ring_b[i])
		st.add_vertex(ring_b[j])
		st.add_vertex(ring_a[i])
		st.add_vertex(ring_b[j])
		st.add_vertex(ring_a[j])


## Feuillage : trois quads croisés, légèrement inclinés, colorés.
static func _add_leaf_cluster(st: SurfaceTool, center: Vector3, size: float, col: Color, rng: RandomNumberGenerator) -> void:
	for k in 2:
		var ang := TAU * k / 2.0 + rng.randf() * 0.9
		var d := Vector3(cos(ang), 0.0, sin(ang)) * size
		var up := Vector3(0.0, size * 0.75, 0.0)
		var tilt := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)) * size
		var p0 := center - d - up * 0.4 + tilt
		var p1 := center + d - up * 0.4 - tilt
		var p2 := center + d + up * 0.6
		var p3 := center - d + up * 0.6
		var c2 := col.darkened(rng.randf() * 0.25)
		_add_quad_double(st, p0, p1, p2, p3, c2, col)


## Palme : lame en arceau, deux moitiés inclinées en V, largeur décroissante.
static func _add_frond(st: SurfaceTool, base: Vector3, ang: float, tilt: float, length: float, col: Color) -> void:
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3(-sin(ang), 0.0, cos(ang))
	var n := 7
	var prev_c := base
	var prev_l := base
	var prev_r := base
	for i in range(1, n + 1):
		var t := float(i) / n
		var rise := (0.45 - tilt) * t - 1.1 * t * t   # monte un peu puis retombe
		var c := base + dir * (length * t) + Vector3.UP * (length * rise)
		var half_w := 0.42 * (1.0 - t * 0.8) * (0.4 + 0.6 * sin(t * PI))
		var droop := Vector3.DOWN * half_w * 0.6   # les folioles pendent : forme en V
		var l := c + side * half_w + droop
		var r := c - side * half_w + droop
		var c_mid := col.darkened(0.12 * t)
		if i > 1:
			_add_quad_double(st, prev_l, prev_c, c, l, c_mid, col)
			_add_quad_double(st, prev_c, prev_r, r, c, c_mid, col)
		prev_c = c
		prev_l = l
		prev_r = r


static func _add_quad_double(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, ca: Color, cb: Color) -> void:
	st.set_color(ca)
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)
	# Face arrière (visible des deux côtés).
	st.set_color(cb)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p1)
	st.add_vertex(p0)
	st.add_vertex(p3)
	st.add_vertex(p2)


static func _add_sphere(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var rings := 3
	var segs := 5
	st.set_color(col)
	for i in rings:
		var t0 := PI * i / rings
		var t1 := PI * (i + 1) / rings
		for j in segs:
			var p0 := TAU * j / segs
			var p1 := TAU * (j + 1) / segs
			var a := c + Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0)) * r
			var b := c + Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1)) * r
			var d := c + Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0)) * r
			var e := c + Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1)) * r
			st.add_vertex(a)
			st.add_vertex(d)
			st.add_vertex(e)
			st.add_vertex(a)
			st.add_vertex(e)
			st.add_vertex(b)


## Silhouette lointaine d'un arbre à feuilles (quelques triangles) : tronc et couronne.
static func build_far_broadleaf(height: float = 9.0, crown_radius: float = 4.5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_branch(st, Vector3.ZERO, Vector3(0.0, height * 0.45, 0.0), 0.16, 0.12, 3, TRUNK_BROWN)
	st.generate_normals()
	var mesh := st.commit()
	var lf := SurfaceTool.new()
	lf.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_octahedron(lf, Vector3(0.0, height * 0.66, 0.0), Vector3(crown_radius, height * 0.36, crown_radius), LEAF_GREENS[0].darkened(0.18))
	lf.generate_normals()
	lf.commit(mesh)
	return mesh


## Silhouette lointaine d'un palmier : tronc et étoile de palmes.
static func build_far_palm(height: float = 11.0, wind_dir := Vector2(-1.0, 0.25)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := wind_dir.normalized()
	var top := Vector3(w.x * 0.18 * height, height, w.y * 0.18 * height)
	_add_branch(st, Vector3.ZERO, top, 0.2, 0.12, 3, PALM_TRUNK)
	st.generate_normals()
	var mesh := st.commit()
	var lf := SurfaceTool.new()
	lf.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := TAU * k / 3.0
		var d := Vector3(cos(a), 0.0, sin(a)) * 3.0
		var s2 := Vector3(-sin(a), 0.0, cos(a)) * 0.9
		_add_quad_double(lf, top - s2, top + s2, top + d - Vector3(0.0, 1.4, 0.0) + s2, top + d - Vector3(0.0, 1.4, 0.0) - s2, PALM_GREEN, PALM_GREEN)
	lf.generate_normals()
	lf.commit(mesh)
	return mesh


static func _add_octahedron(st: SurfaceTool, c: Vector3, r: Vector3, col: Color) -> void:
	var top := c + Vector3(0.0, r.y, 0.0)
	var bot := c - Vector3(0.0, r.y, 0.0)
	var ring := [c + Vector3(r.x, 0.0, 0.0), c + Vector3(0.0, 0.0, r.z), c - Vector3(r.x, 0.0, 0.0), c - Vector3(0.0, 0.0, r.z)]
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		st.set_color(col.darkened(0.1 * i))
		st.add_vertex(top)
		st.add_vertex(b)
		st.add_vertex(a)
		st.set_color(col.darkened(0.25))
		st.add_vertex(bot)
		st.add_vertex(a)
		st.add_vertex(b)
