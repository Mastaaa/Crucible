extends RefCounted
## Lamp (A3, survivor of the cut): lights LIGHT_LAMP cells round it while the Hub's stockpile
## can pay its LAMP_POWER_PER_S and a Node or the Hub is in reach. The light itself is
## machines.gd's `lights`, read each time the game works out what's lit.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	m["lit"] = false
	m["why"] = ""
	if not MU.networked(g, m, def):
		m["why"] = "No Node or Hub within reach."
		return
	if not MU.take_power(g, D.LAMP_POWER_PER_S * MU.SCAN_DT):
		m["why"] = "No power in the Hub's stockpile."
		return
	m["lit"] = true


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return m["why"] if m.get("why", "") != "" else "Lit."


## A warm halo while lit.
static func draw(ov, g, m: Dictionary, _def: Dictionary, z: float) -> void:
	if not m.get("lit", false):
		return
	var c: Vector2 = g.to_screen(m["at"])
	ov.draw_circle(c, 9.0 * z, Color(1.0, 0.94, 0.63, 0.22))
