extends RefCounted
## Conveyor (A4): a bolted belt. Loose powder lying on its top surface (and whatever a joined module
## passes in at either end) rides to the far end, and loose rigid bodies lying on it are driven along
## at belt speed. What reaches the end goes into a module joined there (a Tank, a Funnel, a
## Macerator's mouth below) or, with nothing joined, is let fall off the end a few cells at a time
## (a cell waits while the spot is taken, so a full pile backs the belt up). Straight along its
## length, four directions with the module's turns; click it to reverse. It draws a little power
## while it carries anything, from a Node or the Hub in reach.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")

const RIDE := 4                 # rows above the belt that count as lying on it


## The belt's geometry in the world: {dir: the way it carries (an axis), zone: the Rect2i above it,
## end: the cell where it lets go, n: the way up off the belt}.
static func geometry(g, m: Dictionary, def: Dictionary) -> Dictionary:
	var fo := CUT.front_of(g, m, def)
	var n: Vector2i = fo["n"]
	var d := Vector2i(-n.y, n.x) * int(m.get("dir", 1))
	var length: int = def["size"].x if def["size"].x >= def["size"].y else def["size"].y
	var p: Vector2 = fo["p"]
	var half := length >> 1
	var rect: Rect2i
	if n.y != 0:
		var y0 := int(roundf(p.y)) if n.y > 0 else int(roundf(p.y)) - RIDE
		rect = Rect2i(int(roundf(p.x)) - half, y0, length, RIDE)
	else:
		var x0 := int(roundf(p.x)) if n.x > 0 else int(roundf(p.x)) - RIDE
		rect = Rect2i(x0, int(roundf(p.y)) - half, RIDE, length)
	var end := Vector2i(roundi(p.x), roundi(p.y)) + d * (half + 1)
	return {"dir": d, "zone": rect, "end": end, "n": n}


static func _dest(g, m: Dictionary, def: Dictionary) -> int:
	# `end_b` is the belt's far end when it runs the way it is built; reversed, it is `end_a`.
	var face := "end_b" if int(m.get("dir", 1)) > 0 else "end_a"
	return MU.partner(g, m, def, face).get("id", 0)


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	if not m.has("queue"):
		m["queue"] = []
	var geo := geometry(g, m, def)
	var queued := 0
	for q: Array in m["queue"]:
		queued += int(q[1])
	var room: int = MU.capacity(m, def) - MU.stored(m) - queued
	var travel := int(float(def["size"].x if def["size"].x >= def["size"].y else def["size"].y) / float(p["speed"]) * 60.0)
	var due: int = g.ticks + travel
	# Powder lying on the belt, and what is passed in at the ends, goes on the queue. The belt draws power
	# for the scan when there is any of it to lift.
	var z: Rect2i = geo["zone"]
	var live: bool = m["net"]
	if live and (queued > 0 or m["contents"].size() > 0 or g.sim.count_in_rect(z.position.x, z.position.y, z.size.x, z.size.y, M.mask("powder")) > 0):
		live = MU.take_power(g, float(p["power"]) * MU.SCAN_DT)
		if not live:
			m["state"] = "Waiting for power."
	if live:
		if room > 0:
			var got: PackedInt32Array = g.sim.dig_rect(z.position.x, z.position.y, z.size.x, z.size.y, M.mask("powder"), 0, 0)
			for mat in 256:
				if got[mat] > 0:
					m["queue"].append([mat, got[mat], due])
					room -= got[mat]
		for mat: int in m["contents"].keys():
			var n := mini(int(p["rate"]), m["contents"][mat])
			if n > 0:
				m["queue"].append([mat, n, due])
				MU.take(m, mat, n)
		# Loose bodies lying on it ride.
		var mods := {}
		for id: int in g.modules:
			mods[g.modules[id]["body"]] = true
		var riders: Array = []
		for y in range(z.position.y, z.end.y):
			for x in range(z.position.x, z.end.x):
				var o: int = g.sim.get_owner(x, y)
				if o != 0 and not mods.has(o) and not riders.has(o):
					riders.append(o)
		m["riders"] = riders
	else:
		m["riders"] = []
	# Delivery: what has had its travel time goes into the module joined at the end, or off the end.
	if not live and m["net"]:
		return
	var dest := _dest(g, m, def)
	var spill := 0
	var rest: Array = []
	for q: Array in m["queue"]:
		if int(q[2]) > g.ticks:
			rest.append(q)
			continue
		var n: int = q[1]
		if dest != 0:
			n -= MU.add(g.modules[dest], MU.defs[g.modules[dest]["def"]], q[0], n)
		else:
			var e: Vector2i = geo["end"]
			var up: Vector2i = geo["n"]
			for k in RIDE:
				if n <= 0:
					break
				var c := e + up * k
				if g.sim.get_cell(c.x, c.y) == D.AIR and g.sim.get_owner(c.x, c.y) == 0:
					g.sim.set_cell(c.x, c.y, q[0])
					n -= 1
					spill += 1
		if n > 0:
			q[1] = n
			rest.append(q)
	m["queue"] = rest
	m["carried"] = m.get("carried", 0) + spill
	var cargo := queued + (m["riders"] as Array).size()
	m["state"] = "Carrying %d cells and %d bodies." % [queued, (m["riders"] as Array).size()] if cargo > 0 else "Empty."
	if not m["net"] and cargo > 0:
		m["state"] = "No power: no Node or Hub in reach."


## Every tick: loose bodies on the belt are driven along it; the belt draws power while it has a load.
static func step(g, m: Dictionary, def: Dictionary) -> void:
	var riders: Array = m.get("riders", [])
	if riders.is_empty() or not m.get("net", false):
		return
	if not MU.take_power(g, float(def["params"]["power"]) * D.DT):
		m["state"] = "Waiting for power."
		return
	var geo := geometry(g, m, def)
	var v := Vector2(geo["dir"]) * float(def["params"]["speed"]) / 60.0
	for id: int in riders:
		g.sim.drive_body(id, v.x, v.y, 0.0)


## A click reverses the belt.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	m["dir"] = -int(m.get("dir", 1))
	g.show_banner("%s: running %s." % [def["name"], "back" if m["dir"] < 0 else "forward"], 1.5)


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %s (click to reverse)." % [m.get("state", ""), "Reversed." if int(m.get("dir", 1)) < 0 else "Forward."]


## An arrow along the belt.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var geo := geometry(g, m, def)
	var zr: Rect2i = geo["zone"]
	var mid := Vector2(zr.position) + Vector2(zr.size) * 0.5
	var d := Vector2(geo["dir"])
	var tip := mid + d * 4.0
	var col := Color(0.9, 0.8, 0.5, 0.7)
	ov.draw_line(g.to_screen(mid - d * 4.0), g.to_screen(tip), col, maxf(1.0, z * 0.6))
	var side := Vector2(d.y, d.x).abs()
	ov.draw_line(g.to_screen(tip), g.to_screen(tip - d * 2.0 + side * 2.0), col, maxf(1.0, z * 0.6))
	ov.draw_line(g.to_screen(tip), g.to_screen(tip - d * 2.0 - side * 2.0), col, maxf(1.0, z * 0.6))
