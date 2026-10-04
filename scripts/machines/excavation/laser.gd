extends RefCounted
## Laser Excavator (A4): a one-pixel beam along its `front` that strips ore off a wall. The
## beam stops on the first solid cell it meets; if that is ore (a material worth more than plain
## rock) the Laser takes the cell, and with Filler on it leaves Stone (paid from the Hub's stock)
## in its place so the wall keeps its shape. Anything else on the end of the beam is left alone, so
## it is aimed by carrying it on a Winch rig, Piston, Gantry or Turntable. What it takes goes up
## through its top face into a Tank, the way the Cutter's does. Click it to switch Filler.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")

const CELLS_PER_SCAN := 4

static var _ore := PackedByteArray()


## Solid materials worth more than plain rock: what the beam takes.
static func ore_mask() -> PackedByteArray:
	if _ore.is_empty():
		M.ensure()
		var solid := M.mask("solid")
		_ore.resize(256)
		for mat in 256:
			_ore[mat] = 1 if solid[mat] == 1 and M.dig_rates[mat] > 0.0 and M.worth_of(mat) >= 2.0 else 0
	return _ore


## Where the beam ends: {cell, mat, from} for the first solid cell in range that isn't the
## Laser's own casing, or {} (another module's casing ends it as {cell, mat: -1}).
static func aim(g, m: Dictionary, def: Dictionary) -> Dictionary:
	var fo := CUT.front_of(g, m, def)
	var solid := M.mask("solid")
	for k in int(def["params"]["range"]):
		var r := CUT.slice(fo["p"], fo["n"], k, 1, 0)
		var x := r.position.x
		var y := r.position.y
		var owner: int = g.sim.get_owner(x, y)
		if owner == m["body"]:
			continue
		if owner != 0:
			return {"cell": Vector2i(x, y), "mat": -1, "from": fo["p"]}
		var c: int = g.sim.get_cell(x, y)
		if solid[c] == 1:
			return {"cell": Vector2i(x, y), "mat": c, "from": fo["p"]}
	return {"from": fo["p"]}


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["state"] = ""
	m["work"] = minf(m.get("work", 0.0) + MU.SCAN_DT, 1.5)
	if not m.has("filler"):
		m["filler"] = false
	if m.get("rig_of", 0) == 0:
		m["state"] = "Hang it from a Winch (through a Tank), or mount it on a Piston, Gantry or Turntable, to work."
		m["beam"] = {}
		return
	var ore := ore_mask()
	var filler := M.id_of(str(p["filler"]))
	var taken := 0
	for _i in CELLS_PER_SCAN:
		var hit := aim(g, m, def)
		m["beam"] = hit
		if not hit.has("cell"):
			m["state"] = "Nothing in range."
			break
		if hit["mat"] < 0:
			m["state"] = "The beam ends on another module."
			break
		var mat: int = hit["mat"]
		if ore[mat] != 1:
			m["state"] = "The beam stops on %s: not ore." % M.names[mat]
			break
		if not m.get("powered", false):
			m["state"] = "No power: what carries it has no Node or Hub in reach."
			break
		var cost := 1.0 / float(p["rate"])
		if m["work"] < cost:
			break
		if MU.capacity(m, def) - MU.stored(m) < 1:
			m["state"] = "Full: nowhere to put what it takes."
			break
		var need := 0.0
		if m["filler"]:
			need = D.cell_units(filler)
			if g.stock[D.R_STONE] < need:
				m["state"] = "No Stone to fill with."
				break
		if not MU.take_power(g, D.power_per_cell(mat) * float(p["power_mult"])):
			m["state"] = "Waiting for power."
			break
		m["work"] -= cost
		var c: Vector2i = hit["cell"]
		var got: PackedInt32Array = g.sim.dig_rect(c.x, c.y, 1, 1, ore, D.SETTLE_RADIUS, int(D.SETTLE_S * D.TICKS_PER_S))
		for k in 256:
			if got[k] > 0:
				MU.add(m, def, k, got[k])
				taken += got[k]
		if m["filler"]:
			g.stock[D.R_STONE] -= need
			g.sim.set_cell(c.x, c.y, filler)
	if taken > 0:
		m["taken"] = m.get("taken", 0) + taken
		m["state"] = "Stripping."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


## A click switches Filler.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	m["filler"] = not m.get("filler", false)
	g.show_banner("%s: filler %s." % [def["name"], "on" if m["filler"] else "off"], 1.5)


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s Filler %s (click to switch). %d cells stripped so far." % [m.get("state", ""), "on" if m.get("filler", false) else "off", m.get("taken", 0)]


## The beam, from the front wall to what it stops on.
static func draw(ov, g, m: Dictionary, _def: Dictionary, z: float) -> void:
	var beam: Dictionary = m.get("beam", {})
	if m.get("rig_of", 0) == 0 or not beam.has("cell"):
		return
	var to := Vector2(beam["cell"]) + Vector2(0.5, 0.5)
	ov.draw_line(g.to_screen(beam["from"]), g.to_screen(to), Color(1.0, 0.45, 0.2, 0.8), maxf(1.0, z * 0.8))
