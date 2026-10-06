extends RefCounted
## Pump (A5): lifts liquid. Its mouth, `front`, takes the liquid cells in the `depth` rows in front of it
## (a slice at a time, `rate` cells a scan at most) into its hollow, for a little power a cell, and its
## `out` face passes them on into a Tank or Chute joined there. Hung from a Winch under a Tank in place of
## a Cutter (a shaft is 30 wide, too narrow for both), it clears a flooded or oil-filled shaft ahead of the rig;
## the liquid goes into the Tank and out through the Funnel. It leads the rig the way a Cutter does: it
## reports `room` (none while liquid is in its mouth, the clear rows below once it is dry) and, dry with rock
## right below, `stuck` with a `stop` text, so the Winch lowers it as it drains and brings the rig up when it is
## done. Swapping the digger lifts the Winch's hold (`_key`). It takes
## liquid only (powder is the Cutter's and the Bus Hopper's business, gas will be a Blower's). A Node or the
## Hub has to be in reach.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")
const BH = preload("res://scripts/machines/logistics/bus_hopper.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	# On a rig it is powered through the rig's mover (what carries it has a Node or the Hub in reach),
	# as the Cutter is; anywhere else it needs a Node or the Hub in reach itself.
	m["net"] = bool(m.get("powered", false)) if m.get("rig_of", 0) != 0 else MU.networked(g, m, def)
	m["state"] = ""
	m["room"] = 0
	m["stuck"] = ""
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
	_room(g, m, def, fo)


## What the Winch reads when a Pump leads its rig (as it reads a Cutter's): the rows it may drop,
## which is none while liquid is still in the mouth (it drains first) and the clear rows below
## once the mouth is dry. Dry with rock right below, it is done: the rig is told to go up.
static func _room(g, m: Dictionary, def: Dictionary, fo: Dictionary) -> void:
	var mouth := BH.mouth(g, m, def)
	var wet: int = g.sim.count_in_rect(mouth.position.x, mouth.position.y, mouth.size.x, mouth.size.y, M.mask("liquid"))
	if wet > 0:
		return
	var solid := M.mask("solid")
	var room := 0
	for k in CUT.LOOK:
		var s := CUT.slice(fo["p"], fo["n"], k, int(fo["across"]), 0)
		if g.sim.count_in_rect(s.position.x, s.position.y, s.size.x, s.size.y, solid) > 0:
			break
		room += 1
	m["room"] = room
	if room == 0:
		m["stuck"] = "Rock"
		m["stop"] = "The Pump has drained what it can reach."


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
