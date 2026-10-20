extends RefCounted
## Floodlight (A9 tools): a standalone tool that stands on a line and lights a wide pool round it while the Hub's stock
## pays its power. The line carries it into the network: it lights wherever a Cable, Pipe or Strut can be run to a part in
## reach of a Node or the Hub, so a Cable out to a far cave can carry one with it. The Lamp is the plain, fixed light and stays.
## The light itself is machines.gd's `lights`, read each time the game works out what is lit.

const MU = preload("res://scripts/machines/mu.gd")
const MT = preload("res://scripts/machines/tools/mount.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	m["lit"] = false
	if MT.ready(g, m, def).is_empty():
		return
	if not MU.take_power(g, float(def["params"]["power"]) * MU.SCAN_DT):
		m["state"] = "No power in the Hub's stockpile."
		return
	m["lit"] = true
	m["state"] = "Lit."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return str(m.get("state", ""))


## A wide warm halo while lit.
static func draw(ov, g, m: Dictionary, _def: Dictionary, z: float) -> void:
	if not m.get("lit", false):
		return
	var c: Vector2 = g.to_screen(m["at"])
	ov.draw_circle(c, 14.0 * z, Color(1.0, 0.97, 0.78, 0.22))
