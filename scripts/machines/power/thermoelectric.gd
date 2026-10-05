extends RefCounted
## Thermoelectric Plate (A5): turns a difference in temperature into power. Its two long sides each
## read the cells in a strip `depth` cells deep against them; the power a second is `per_degree` for
## every degree between the two averages, up to `max`, added to the Hub's store while a Node or the
## Hub is in reach. It reads the world's cells, so it earns where the ground is hot (hot rock against
## the air of a shaft, lava or magma against water), not from a vessel's inside.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


## The two strips it reads: the front side's and the back side's.
static func sides(g, m: Dictionary, def: Dictionary) -> Array:
	var fo := CUT.front_of(g, m, def)
	var size: Vector2i = MU.F.layout(def, m["turns"])["size"]
	var n: Vector2i = fo["n"]
	var len_n := size.x if n.x != 0 else size.y
	var depth := int(def["params"]["depth"])
	var front := CUT.slice(fo["p"], n, 0, int(fo["across"]), 0).merge(CUT.slice(fo["p"], n, depth - 1, int(fo["across"]), 0))
	var bp: Vector2 = fo["p"] - Vector2(n) * float(len_n)
	var back := CUT.slice(bp, -n, 0, int(fo["across"]), 0).merge(CUT.slice(bp, -n, depth - 1, int(fo["across"]), 0))
	return [front, back]


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["flow"] = 0.0
	var s := sides(g, m, def)
	var tf: Vector3i = g.sim.rect_temp(s[0].position.x, s[0].position.y, s[0].size.x, s[0].size.y)
	var tb: Vector3i = g.sim.rect_temp(s[1].position.x, s[1].position.y, s[1].size.x, s[1].size.y)
	m["diff"] = tf.z - tb.z
	if not MU.networked(g, m, def):
		m["why"] = "No Node or Hub within reach."
		return
	m["why"] = ""
	var rate := minf(float(p["max"]), absf(float(m["diff"])) * float(p["per_degree"]))
	var room: float = g.power_cap() - g.stock[D.R_POWER]
	g.stock[D.R_POWER] += clampf(rate * MU.SCAN_DT, 0.0, maxf(room, 0.0))
	m["flow"] = rate


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	if m.get("why", "") != "":
		return m["why"]
	return "%.2f power/s from %d degrees between its sides." % [m.get("flow", 0.0), absi(int(m.get("diff", 0)))]


## The two strips, outlined (warm one orange, the other blue).
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var s := sides(g, m, def)
	var warm: int = 0 if m.get("diff", 0) >= 0 else 1
	for k in 2:
		var r: Rect2i = s[k]
		var a: Vector2 = g.to_screen(Vector2(r.position))
		var b: Vector2 = g.to_screen(Vector2(r.end))
		ov.draw_rect(Rect2(a, b - a), Color(1.0, 0.6, 0.3, 0.45) if k == warm else Color(0.5, 0.75, 1.0, 0.45), false, maxf(1.0, z * 0.5))
