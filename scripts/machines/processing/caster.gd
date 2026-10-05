extends RefCounted
## Caster (A5): the Press for liquids. A liquid joined into its bottom face (Lava, Slag, Quickmire,
## Water) collects in its hollow, and once it holds a slab of one kind the Caster sets it, after a
## few seconds and some power, as a solid block out of its `front`: Lava becomes Obsidian, Slag a
## crust, Quickmire Mire stone, Water Ice. A block is `slab` wide and tall, one cell of block for
## one cell of liquid, and needs open air all over its footprint in front. The Macerator turns a
## block back into powder.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const PRESS = preload("res://scripts/machines/processing/press.gd")


## The liquid it has the most of that it can cast, or -1.
static func best(m: Dictionary) -> int:
	var pick := -1
	var most := 0
	for mat: int in m["contents"]:
		if M.cast_of(mat) >= 0 and m["contents"][mat] > most:
			most = m["contents"][mat]
			pick = mat
	return pick


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	var need: int = int(p["slab"][0]) * int(p["slab"][1])
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	var mat := best(m)
	m["state"] = ""
	if mat < 0 or m["contents"][mat] < need:
		m["state"] = "Waiting for liquid (%d of %d cells)." % [m["contents"].get(mat, 0) if mat >= 0 else 0, need]
		return
	var r := PRESS.footprint(g, m, def)
	var counts: PackedInt32Array = g.sim.rect_counts(r.position.x, r.position.y, r.size.x, r.size.y)
	if counts[D.AIR] < need:
		m["state"] = "Blocked: no room in front for the block."
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	m["work"] = minf(m.get("work", 0.0) + MU.SCAN_DT, float(p["time"]))
	if m["work"] < float(p["time"]):
		m["state"] = "Casting."
		return
	if not MU.take_power(g, float(p["power"])):
		m["state"] = "Waiting for power."
		return
	var solid := M.cast_of(mat)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g.sim.set_cell(x, y, solid)
	var id: int = g.sim.make_body(r.position.x, r.position.y, r.size.x, r.size.y, 0.0, 0.0, 0.0)
	if id < 0:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				g.sim.set_cell(x, y, D.AIR)
		m["state"] = "Too many loose bodies in the world."
		return
	m["work"] = 0.0
	MU.take(m, mat, need)
	m["blocks"] = m.get("blocks", 0) + 1
	m["state"] = "Cast a block of %s." % M.names[solid]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %d blocks so far." % [m.get("state", ""), MU.stored(m), MU.capacity(m, def), m.get("blocks", 0)]


## Where the block will come out.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	PRESS.draw(ov, g, m, def, z)
