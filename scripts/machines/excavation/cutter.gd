extends RefCounted
## Cutter Excavator (A3 starter kit): hangs from a Winch at the bottom of a rig and cuts a
## tunnel ahead of its `front`, a row at a time. It digs only what its hardness allows (soft
## ground to begin with: Drill Bit research raises it), drinks the water that seeps in, pays
## power for every row and passes what it takes up through its top face into the Tank.
## The tunnel is wider than the rig and its edge wobbles. The Winch lowers the rig as rows
## open up (`room` says how many are clear).

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")

const SLICES_PER_SCAN := 3
const LOOK := 4                 # rows ahead checked for clearance and lava
const WADE := ["Slick", "Brine"]  # liquids besides a stockpile's that the rig sinks into and drinks: oil only burns, brine only salts

static var _soft := {}          # hardness threshold and hot rock -> mask of what it digs
static var _bad := PackedByteArray()
static var _drink := PackedByteArray()


static func level(g) -> int:
	return g.level("drill_bit")


## What an Excavator at hardness `lvl` digs: solid cells whose dig rate is at least the
## level's threshold, bar Obsidian (the Laser's) and Hot rock until the bit is `hot_level`.
static func soft_mask(def: Dictionary, lvl: int) -> PackedByteArray:
	var hard: Array = def["params"]["hardness"]
	var thr := float(hard[mini(lvl, hard.size() - 1)])
	var hot: bool = lvl >= int(def["params"]["hot_level"])
	var key := "%s/%s" % [thr, hot]
	if _soft.has(key):
		return _soft[key]
	M.ensure()
	var out := PackedByteArray()
	out.resize(256)
	for mat in 256:
		var k: int = M.kinds[mat]
		var rate: float = M.dig_rates[mat]
		var ok := (k == M.K_STATIC or k == M.K_POWDER) and rate > 0.0 and rate >= thr
		if M.names[mat] == "Obsidian" or (M.names[mat] == "Hot rock" and not hot):
			ok = false
		out[mat] = 1 if ok else 0
	_soft[key] = out
	return out


## Liquids the rig drinks as it sinks: a stockpile's water, and what WADE adds.
static func drinkable() -> PackedByteArray:
	if _drink.is_empty():
		_drink = M.mask("worth_liquid").duplicate()
		for nm: String in WADE:
			_drink[M.id_of(nm)] = 1
	return _drink


## Liquids the rig must not be lowered into: everything liquid that it can't drink.
static func bad_liquids() -> PackedByteArray:
	if _bad.is_empty():
		var liquid := M.mask("liquid")
		var drink := drinkable()
		_bad.resize(256)
		for mat in 256:
			_bad[mat] = 1 if liquid[mat] == 1 and drink[mat] == 0 else 0
	return _bad


## Speed in rows a second at full dig rate.
static func speed(g, def: Dictionary) -> float:
	var p: Dictionary = def["params"]
	return float(p["speed"]) * pow(float(p["bit_speed"]), level(g))


## The slice `k` cells past the front (point `p` on the wall, axis `n`), `width` across and
## shifted `off` sideways.
static func slice(p: Vector2, n: Vector2i, k: int, width: int, off: int) -> Rect2i:
	if n.y != 0:
		var y0 := int(round(p.y)) + k if n.y > 0 else int(round(p.y)) - 1 - k
		return Rect2i(int(round(p.x)) - (width >> 1) + off, y0, width, 1)
	var x0 := int(round(p.x)) + k if n.x > 0 else int(round(p.x)) - 1 - k
	return Rect2i(x0, int(round(p.y)) - (width >> 1) + off, 1, width)


## The cell counts of `r` less the cells this module owns. A tilted body's front edge, half a row off a row
## boundary, can round one corner pixel of its own casing into the slice just past the front, and the rig
## then stops for a wall that is itself (the A5 bot's "Obsidian ahead" at depth 2256).
static func counts_ahead(g, m: Dictionary, r: Rect2i) -> PackedInt32Array:
	var counts: PackedInt32Array = g.sim.rect_counts(r.position.x, r.position.y, r.size.x, r.size.y)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if g.sim.get_owner(x, y) == m["id"]:
				counts[g.sim.get_cell(x, y)] -= 1
	return counts


## Whether `counts` holds any cell of the `mask`.
static func holds(counts: PackedInt32Array, mask: PackedByteArray) -> bool:
	for mat in range(1, 256):
		if counts[mat] > 0 and mask[mat] == 1:
			return true
	return false


## Where the front wall is in the world: {p: its middle, n: the way it faces (an axis),
## across: the module's width along the front}.
static func front_of(g, m: Dictionary, def: Dictionary) -> Dictionary:
	var fr := MU.frame(g, m, def)
	var size: Vector2i = fr["lay"]["size"]
	var fl := MU.front(def, m["turns"])
	var local := Vector2(size) * 0.5 + Vector2(fl) * Vector2(size) * 0.5
	var n := MU.axis(MU.turn(fr, Vector2(fl)))
	return {"p": MU.world(fr, local), "n": n, "across": size.x if fl.y != 0 else size.y}


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["state"] = ""
	m["room"] = 0
	m["work"] = minf(m.get("work", 0.0) + MU.SCAN_DT, 1.5)
	if m.get("rig_of", 0) == 0:
		m["state"] = "Hang it from a Winch (through a Tank), or mount it on a Piston, Gantry or Turntable, to work."
		return
	var fo := front_of(g, m, def)
	var pt: Vector2 = fo["p"]
	var n: Vector2i = fo["n"]
	var lvl := level(g)
	var soft := soft_mask(def, lvl)
	var water := drinkable()
	var solid := M.mask("solid")
	var bad := bad_liquids()
	# Clearance ahead, over the body's own width: how many rows the rig may drop.
	var room := 0
	for k in LOOK:
		var ahead := counts_ahead(g, m, slice(pt, n, k, fo["across"], 0))
		if holds(ahead, solid) or holds(ahead, bad):
			break
		room += 1
	m["room"] = room
	# Water seeping in is drunk first, up to what the intake and the room allow.
	var zone := slice(pt, n, 0, int(p["width"]), 0)
	if n.y != 0:
		zone.size.y = 3
		if n.y < 0:
			zone.position.y -= 2
	else:
		zone.size.x = 3
		if n.x < 0:
			zone.position.x -= 2
	# Oil (a good) is drunk only while the bank has room for it: a full bank holds goods back at the
	# Funnel, and a Tank of Slick that cannot be emptied would hold the rig at the dock for good.
	var sip := water if g.goods_room() >= 1.0 else M.mask("worth_liquid")
	var wet: int = g.sim.count_in_rect(zone.position.x, zone.position.y, zone.size.x, zone.size.y, sip)
	if wet > 0 and wet <= mini(int(p["intake"]), MU.capacity(m, def) - MU.stored(m)):
		var got: PackedInt32Array = g.sim.dig_rect(zone.position.x, zone.position.y, zone.size.x, zone.size.y, sip, 0, 0)
		for mat in 256:
			if got[mat] > 0:
				MU.add(m, def, mat, got[mat])
	if not m.get("powered", false):
		m["state"] = "No power: what carries it has no Node or Hub in reach."
		return
	var dug := 0
	for _i in SLICES_PER_SCAN:
		var off: int = m.get("off", 0)
		var r := slice(pt, n, 0, int(p["width"]), off)
		var counts := counts_ahead(g, m, r)
		var slowest := INF
		var power := 0.0
		var units := 0
		var blocker := -1
		for mat in range(1, 256):
			var c: int = counts[mat]
			if c == 0:
				continue
			var k: int = M.kinds[mat]
			if k == M.K_GAS or k == M.K_EMPTY or water[mat] == 1:
				continue
			if soft[mat] == 1:
				slowest = minf(slowest, M.dig_rates[mat])
				power += c * D.power_per_cell(mat)
				units += c
			else:
				blocker = mat
		if blocker >= 0:
			m["state"] = "Stopped: %s ahead is too hard or too hot for it." % M.names[blocker]
			m["stuck"] = M.names[blocker]
			break
		m["stuck"] = ""
		if units == 0:
			break
		var depth_rows := maxf(0.0, pt.y - D.GROUND_Y)
		power *= pow(float(p["bit_power"]), lvl) * (1.0 + depth_rows / float(p["deep_rows"]))
		var cost := 1.0 / (slowest * speed(g, def))
		if m["work"] < cost:
			break
		if MU.capacity(m, def) - MU.stored(m) < units:
			m["state"] = "Full: nowhere to put what it digs."
			break
		if not MU.take_power(g, power):
			m["state"] = "Waiting for power."
			break
		m["work"] -= cost
		var got: PackedInt32Array = g.sim.dig_rect(r.position.x, r.position.y, r.size.x, r.size.y, soft,
				D.SETTLE_RADIUS, int(D.SETTLE_S * D.TICKS_PER_S))
		for mat in 256:
			if got[mat] > 0:
				MU.add(m, def, mat, got[mat])
		dug += units
		# The edge wanders, but never so far that the window stops covering the rig's width.
		var reach := mini(int(p["wobble"]), (int(p["width"]) - int(fo["across"])) >> 1)
		m["off"] = clampi(off + g.rng.randi_range(-1, 1), -reach, reach)
	if dug > 0:
		m["dug"] = m.get("dug", 0) + dug
		m["state"] = "Digging."
	elif m["state"] == "" and room > 0:
		m["state"] = "Digging."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	var s: String = m.get("state", "")
	return "%s %d cells cut so far." % [s, m.get("dug", 0)]


static func draw(ov, g, m: Dictionary, def: Dictionary, _z: float) -> void:
	if m.get("rig_of", 0) == 0:
		return
	var fo := front_of(g, m, def)
	var s := slice(fo["p"], fo["n"], 0, int(def["params"]["width"]), m.get("off", 0))
	var a: Vector2 = g.to_screen(Vector2(s.position))
	var b: Vector2 = g.to_screen(Vector2(s.end))
	ov.draw_rect(Rect2(a, b - a).abs(), Color(1.0, 0.8, 0.35, 0.55), false, 1.0)
