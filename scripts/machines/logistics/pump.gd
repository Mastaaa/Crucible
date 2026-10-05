extends RefCounted
## Pump (A5): lifts liquid. Its mouth, `front`, takes the liquid cells in the `depth` rows in front of it
## (a slice at a time, `rate` cells a scan at most) into its hollow, for a little power a cell, and its
## `out` face passes them on into a Tank or Chute joined there. Hung from a Winch under a Tank in place of
## a Cutter, it clears a flooded or oil-filled shaft ahead of the rig; the liquid goes into the Tank. It takes
## liquid only (powder is the Cutter's and the Bus Hopper's business, gas will be a Blower's). A Node or the
## Hub has to be in reach.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")
const BH = preload("res://scripts/machines/logistics/bus_hopper.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var budget := mini(MU.rate(g, int(p["rate"])), MU.capacity(m, def) - MU.stored(m))
	if budget <= 0:
		m["state"] = "Full: nowhere to put the liquid."
		return
	var fo := CUT.front_of(g, m, def)
	var mask := M.mask("liquid")
	var did := 0
	for k in int(p["depth"]):
		var r := CUT.slice(fo["p"], fo["n"], k, int(fo["across"]), 0)
		var there: int = g.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)
		if there == 0 or there > budget - did:
			continue
		if not MU.take_power(g, float(p["power"]) * there):
			m["state"] = "Waiting for power."
			break
		var got: PackedInt32Array = g.sim.dig_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask, 0, 0)
		for mat in 256:
			if got[mat] > 0:
				MU.add(m, def, mat, got[mat])
				did += got[mat]
	m["lifted"] = m.get("lifted", 0) + did
	m["state"] = "Pumping." if did > 0 else "Nothing to pump."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %d lifted so far." % [m.get("state", ""), MU.stored(m), MU.capacity(m, def), m.get("lifted", 0)]


## The mouth, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var r := BH.mouth(g, m, def)
	var a: Vector2 = g.to_screen(Vector2(r.position))
	var b: Vector2 = g.to_screen(Vector2(r.end))
	var col := Color(0.4, 0.7, 0.95, 0.5)
	var w := maxf(1.0, z * 0.5)
	ov.draw_line(a, Vector2(b.x, a.y), col, w)
	ov.draw_line(Vector2(b.x, a.y), b, col, w)
	ov.draw_line(b, Vector2(a.x, b.y), col, w)
	ov.draw_line(Vector2(a.x, b.y), a, col, w)
