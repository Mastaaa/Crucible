extends RefCounted
## Shorer (A5): lays its own supports. Powder joined into its `in` face (Rubble, Loose dirt, Sand,
## shards: anything the Press could squeeze; `pressed_of`) is set, a cell for a cell, into the open air
## of a strip along its `front` side, `depth` cells deep and as long as the module is, as the rock
## that powder presses to (Rubble to Stone). It fills air only: liquid, ground and other bodies are
## never displaced. Hung on a rig beside the shaft wall it lines the gap the rig leaves, so the
## spoil the Cutter digs shores the shaft behind it. It needs a Node or the Hub in reach and a
## little power a cell. Turn it with R before placing to pick the side.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


## The strip it lays into: `depth` rows past the front wall, the wall's length along.
static func strip(g, m: Dictionary, def: Dictionary) -> Rect2i:
	var fo := CUT.front_of(g, m, def)
	var depth := int(def["params"]["depth"])
	var r: Rect2i = CUT.slice(fo["p"], fo["n"], 0, int(fo["across"]), 0)
	return r.merge(CUT.slice(fo["p"], fo["n"], depth - 1, int(fo["across"]), 0))


## The powder it holds the most of that can be set, or -1.
static func best(m: Dictionary) -> int:
	var pick := -1
	var most := 0
	for mat: int in m["contents"]:
		if M.pressed_of(mat) >= 0 and m["contents"][mat] > most:
			most = m["contents"][mat]
			pick = mat
	return pick


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	var mat := best(m)
	if mat < 0:
		m["state"] = "No powder to set."
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var r := strip(g, m, def)
	var rock := M.pressed_of(mat)
	var left := mini(int(p["rate"]), int(m["contents"][mat]))
	var laid := 0
	for y in range(r.end.y - 1, r.position.y - 1, -1):
		for x in range(r.position.x, r.end.x):
			if laid >= left:
				break
			if g.sim.get_cell(x, y) != D.AIR:
				continue
			if not MU.take_power(g, float(p["power"])):
				m["state"] = "Waiting for power."
				_done(m, mat, laid)
				return
			g.sim.set_cell(x, y, rock)
			laid += 1
	_done(m, mat, laid)
	m["state"] = "Laying %s." % M.names[rock] if laid > 0 else "Nothing to shore: the strip is full."


## Spends the `laid` cells of powder it set.
static func _done(m: Dictionary, mat: int, laid: int) -> void:
	if laid > 0:
		MU.take(m, mat, laid)
		m["laid"] = m.get("laid", 0) + laid


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %d laid so far." % [m.get("state", ""), MU.stored(m), MU.capacity(m, def), m.get("laid", 0)]


## The strip, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var r := strip(g, m, def)
	var a: Vector2 = g.to_screen(Vector2(r.position))
	var b: Vector2 = g.to_screen(Vector2(r.end))
	ov.draw_rect(Rect2(a, b - a), Color(0.9, 0.7, 0.4, 0.4), false, maxf(1.0, z * 0.5))
