extends RefCounted
## Filler (A7): lines the loose ground round it with Grout. Each scan it sweeps a few rows of the circle of
## `radius` cells about its centre and turns every powder cell (Sand, Loose dirt, Rubble, shards) that has
## open space beside or below it into Grout, a cell for a cell and in place, so nothing moves and the ground
## round and above it is left alone. Only that one skin is changed: the cell behind it is not open any more.
## A cell whose only open side is its top (the surface of a dune) is left as it is.
## It pays 1 Stone from the Hub's stockpile for every `per_stone` cells and `power` a cell, and needs a Node
## or the Hub in reach. Sand pours the moment it is opened (a fresh face holds for SETTLE_S first), so it
## must be standing by when a shaft goes through sand.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["why"] = ""
	m["working"] = false
	if not MU.networked(g, m, def):
		m["why"] = "No Node or Hub within reach."
		return
	var grout := M.id_of("Grout")
	var r := int(p["radius"])
	var cx := int(m["at"].x)
	var cy := int(m["at"].y)
	var laid := 0
	var left := MU.rate(g, int(p["rate"]))
	var starved := ""
	for _k in int(p["rows"]):
		var y: int = cy - r + int(m.get("sweep", 0))
		m["sweep"] = (int(m.get("sweep", 0)) + 1) % (2 * r + 1)
		if y < 1 or y >= D.H - 1:
			continue
		var half := int(sqrt(float(r * r - (y - cy) * (y - cy))))
		for x in range(maxi(cx - half, 1), mini(cx + half + 1, D.W - 1)):
			if laid >= left:
				break
			if M.kinds[g.sim.get_cell(x, y)] != M.K_POWDER or not _exposed(g, x, y):
				continue
			if int(m.get("credit", 0)) <= 0:
				if g.stock[D.R_STONE] < 1.0:
					starved = "No Stone in the Hub's stockpile."
					break
				g.stock[D.R_STONE] -= 1.0
				m["credit"] = int(p["per_stone"])
			if not MU.take_power(g, float(p["power"])):
				starved = "No power in the Hub's stockpile."
				break
			g.sim.set_cell(x, y, grout)
			m["credit"] = int(m["credit"]) - 1
			laid += 1
		if starved != "":
			break
	# The sweep passes rows with nothing to do, so the last thing that stopped it is kept until it lays again.
	if laid > 0:
		m["laid"] = int(m.get("laid", 0)) + laid
		m["working"] = true
		m["blocked"] = ""
	elif starved != "":
		m["blocked"] = starved
	m["why"] = m.get("blocked", "")


## Open space (air, gas or liquid) at the cell's left, right or underneath. The cell above does not count.
static func _exposed(g, x: int, y: int) -> bool:
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var k: int = M.kinds[g.sim.get_cell(x + d.x, y + d.y)]
		if k == M.K_EMPTY or k == M.K_GAS or k == M.K_LIQUID:
			return true
	return false


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	var s: String = m.get("why", "")
	if s == "":
		s = "Lining loose ground." if m.get("working", false) else "Nothing loose to line."
	return "%s %d cells set so far." % [s, m.get("laid", 0)]


## The circle it works in, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var c: Vector2 = g.to_screen(m["at"])
	ov.draw_arc(c, float(def["params"]["radius"]) * z, 0.0, TAU, 48, Color(0.75, 0.75, 0.7, 0.3), maxf(1.0, z * 0.5))
