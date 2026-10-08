extends RefCounted
## Waterwheel (A6): water falling onto its top runs through it and out underneath, and every cell
## makes `per_cell` power for the Hub's stockpile while a Node or the Hub is in reach. It looks at
## the `catch` rows over its casing, takes up to `cells` of Water a second (more with Throughput)
## and sets each one down in the first open cell along its bottom edge. Water pooled under it, or
## nothing falling, stalls it. It needs no sky, so it works at depth under a spring: the Fen's pockets
## have them (A6).

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")


## The Water in the catch rows over the casing, lowest row first.
static func feed(g, r: Rect2i, wall: int, rows: int) -> Array:
	var out: Array = []
	for y in range(r.position.y - 1, r.position.y - 1 - rows, -1):
		for x in range(r.position.x + wall, r.end.x - wall):
			if g.sim.get_cell(x, y) == D.WATER:
				out.append(Vector2i(x, y))
	return out


## The first open cell in the row under the casing, trying from column `from`, or (-1, -1).
static func exit_cell(g, r: Rect2i, wall: int, from: int) -> Vector2i:
	var n := r.size.x - 2 * wall
	for k in n:
		var x := r.position.x + wall + (from + k) % n
		if D.is_thin(g.sim.get_cell(x, r.end.y)):
			return Vector2i(x, r.end.y)
	return Vector2i(-1, -1)


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	var r := MU.bounds(m, def)
	var wall: int = def["wall"]
	m["flow"] = 0.0
	if not MU.networked(g, m, def):
		m["why"] = "No Node or Hub within reach."
		return
	var per_scan := float(MU.rate(g, int(p["cells"]))) * MU.SCAN_DT
	m["tok"] = minf(float(m.get("tok", 0.0)) + per_scan, maxf(3.0, per_scan * 2.0))
	var wet := feed(g, r, wall, int(p["catch"]))
	m["why"] = "No water falls on it." if wet.is_empty() else ""
	var made := 0.0
	var moved := 0
	var room: float = g.power_cap() - g.stock[D.R_POWER]
	for c: Vector2i in wet:
		if m["tok"] < 1.0 or made + float(p["per_cell"]) > room:
			break
		var e := exit_cell(g, r, wall, int(m.get("out", 0)))
		if e.x < 0:
			m["why"] = "Water is pooled under it."
			break
		g.sim.set_cell(c.x, c.y, D.AIR)
		g.sim.set_cell(e.x, e.y, D.WATER)
		m["out"] = e.x - r.position.x - wall + 1
		m["tok"] -= 1.0
		made += float(p["per_cell"])
		moved += 1
		m["passed"] = int(m.get("passed", 0)) + 1
	g.stock[D.R_POWER] += made
	var rate := made / MU.SCAN_DT
	m["flow"] = lerpf(float(m.get("avg", 0.0)), rate, 0.2) if moved > 0 else lerpf(float(m.get("avg", 0.0)), 0.0, 0.2)
	m["avg"] = m["flow"]
	if m["flow"] < 0.005:
		m["flow"] = 0.0
	m["spin"] = fmod(float(m.get("spin", 0.0)) + float(m["flow"]) * 1.5, TAU)


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	if m.get("why", "") != "" and m.get("flow", 0.0) == 0.0:
		return m["why"]
	return "%.2f power/s, %d cells passed." % [m.get("flow", 0.0), int(m.get("passed", 0))]


## The wheel, drawn in the middle of the casing.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var r := MU.bounds(m, def)
	var c: Vector2 = g.to_screen(Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5))
	var rad := minf(r.size.x, r.size.y) * 0.4 * z
	var a: float = m.get("spin", 0.0)
	for k in 4:
		var ang := a + k * TAU / 4.0
		ov.draw_line(c, c + Vector2(cos(ang), sin(ang)) * rad, Color(0.6, 0.8, 1.0, 0.9), maxf(1.0, z))
