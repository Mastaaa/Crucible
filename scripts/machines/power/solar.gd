extends RefCounted
## Solar Panel (A6): lies in the light and feeds the Hub's stockpile while a Node or the Hub is within
## reach. It needs a clear line up to the top of the map, so a panel at the bottom of an open pit works
## and anything that roofs the pit (a cave-in, a Brace, another module) shades it. The light is the
## same all day. What the place gives is the biome under it: `biomes` in the definition's params
## multiplies `power` by the biome's name (Dunes pay best), and 1.0 elsewhere.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")


## What the biome under the panel does to its power: the params' `biomes` entry, or 1.0.
static func factor(g, m: Dictionary, def: Dictionary) -> float:
	var b: Rect2i = MU.bounds(m, def)
	var biome: String = g.biome_at(b.position.x + (b.size.x >> 1), b.position.y + (b.size.y >> 1))
	m["biome"] = biome
	return float(def["params"].get("biomes", {}).get(biome, 1.0))


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	var r := MU.bounds(m, def)
	m["flow"] = 0.0
	var shade: int = g.sim.count_in_rect(r.position.x, 0, r.size.x, r.position.y, M.mask("solid"))
	if shade > 0:
		m["why"] = "Something between it and the sky shades it."
		return
	if not MU.networked(g, m, def):
		m["why"] = "No Node or Hub within reach."
		return
	m["why"] = ""
	var rate := float(p["power"]) * factor(g, m, def)
	var room: float = g.power_cap() - g.stock[D.R_POWER]
	g.stock[D.R_POWER] += clampf(rate * MU.SCAN_DT, 0.0, maxf(room, 0.0))
	m["flow"] = rate


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	if m.get("why", "") != "":
		return m["why"]
	var where: String = m.get("biome", "")
	return "%.2f power/s%s" % [m.get("flow", 0.0), (" (%s)" % where.replace("_", " ")) if where != "" else ""]


## A bright band along the top while it earns, scaled by what it makes.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var r := MU.bounds(m, def)
	var a: Vector2 = g.to_screen(Vector2(r.position.x + 2.0, r.position.y - 1.0))
	var b: Vector2 = g.to_screen(Vector2(r.end.x - 2.0, r.position.y - 1.0))
	var k := clampf(float(m.get("flow", 0.0)) / maxf(float(def["params"]["power"]), 0.001), 0.0, 2.0) * 0.5
	ov.draw_line(a, b, Color(1.0, 0.95, 0.6, 0.25 + 0.5 * k), maxf(1.0, z))
