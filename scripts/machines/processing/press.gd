extends RefCounted
## Press (A4): takes powder in through its pixel face and, once it holds enough of one kind,
## squeezes it into a solid block, a rigid body, out of its `front`: Rubble becomes Stone, Loose
## dirt becomes Dirt, shards become the rock they came from, Sand becomes Glass. A block is
## `slab` wide and tall, one cell of block for one cell of powder. It needs power for each block
## and room in front of it (open air all over the block's footprint). The Macerator turns it back.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


## The powder it has the most of that it can press, or -1.
static func best(m: Dictionary) -> int:
	var pick := -1
	var most := 0
	for mat: int in m["contents"]:
		if M.pressed_of(mat) >= 0 and m["contents"][mat] > most:
			most = m["contents"][mat]
			pick = mat
	return pick


## The block's footprint in front of the module: its top left and size.
static func footprint(g, m: Dictionary, def: Dictionary) -> Rect2i:
	var fo := CUT.front_of(g, m, def)
	var sw: int = def["params"]["slab"][0]
	var sh: int = def["params"]["slab"][1]
	var px := int(roundf(fo["p"].x))
	var py := int(roundf(fo["p"].y))
	var n: Vector2i = fo["n"]
	var x0 := px if n.x > 0 else (px - sw if n.x < 0 else px - (sw >> 1))
	var y0 := py if n.y > 0 else (py - sh if n.y < 0 else py - (sh >> 1))
	return Rect2i(x0, y0, sw, sh)


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	var need: int = int(p["slab"][0]) * int(p["slab"][1])
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	var mat := best(m)
	m["state"] = ""
	if mat < 0 or m["contents"][mat] < need:
		m["state"] = "Waiting for powder (%d of %d cells)." % [m["contents"].get(mat, 0) if mat >= 0 else 0, need]
		return
	var r := footprint(g, m, def)
	var counts: PackedInt32Array = g.sim.rect_counts(r.position.x, r.position.y, r.size.x, r.size.y)
	if counts[D.AIR] < need:
		m["state"] = "Blocked: no room in front for the block."
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	m["work"] = minf(m.get("work", 0.0) + MU.SCAN_DT, float(p["time"]))
	if m["work"] < float(p["time"]):
		m["state"] = "Pressing."
		return
	if not MU.take_power(g, float(p["power"])):
		m["state"] = "Waiting for power."
		return
	var rock := M.pressed_of(mat)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g.sim.set_cell(x, y, rock)
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
	m["state"] = "Pressed a block of %s." % M.names[rock]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %d blocks so far." % [m.get("state", ""), MU.stored(m), MU.capacity(m, def), m.get("blocks", 0)]


## Where the block will come out.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var r := footprint(g, m, def)
	var tl: Vector2 = g.to_screen(Vector2(r.position))
	var br: Vector2 = g.to_screen(Vector2(r.end))
	ov.draw_rect(Rect2(tl, br - tl), Color(0.9, 0.7, 0.4, 0.35), false, maxf(1.0, z * 0.5))
