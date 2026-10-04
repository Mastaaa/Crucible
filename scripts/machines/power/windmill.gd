extends RefCounted
## Windmill (A3 starter kit): turns in open sky and feeds the Hub's stockpile while a
## Conduit or the Hub is within reach. The wind comes in gusts. The first real generator.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")


## Power a second the wind gives now, before the sky and the network are checked.
static func gust(g, m: Dictionary, def: Dictionary) -> float:
	var p: Dictionary = def["params"]
	var phase := float(m["id"]) * 2.3
	var k: float = 1.0 + float(p["gust"]) * sin(g.game_time / float(p["period"]) * TAU + phase)
	return float(p["power"]) * maxf(k, 0.0)


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	var r := MU.bounds(m, def)
	var sky: int = p["sky"]
	var blocked: int = g.sim.count_in_rect(r.position.x, r.position.y - sky, r.size.x, sky, M.mask("solid"))
	m["flow"] = 0.0
	if blocked > 0:
		m["why"] = "The sky over it is blocked."
		return
	if not MU.networked(g, m, def):
		m["why"] = "No Conduit or Hub within reach."
		return
	m["why"] = ""
	var rate := gust(g, m, def)
	var made := rate * MU.SCAN_DT
	var room: float = D.HUB_POWER_CAP - g.stock[D.R_POWER]
	g.stock[D.R_POWER] += clampf(made, 0.0, maxf(room, 0.0))
	m["flow"] = rate
	m["spin"] = fmod(m.get("spin", 0.0) + rate * 0.2, TAU)


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	if m.get("why", "") != "":
		return m["why"]
	return "%.2f power/s" % m.get("flow", 0.0)


## The rotor, drawn over the top of the tower.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var r := MU.bounds(m, def)
	var hub := Vector2(r.position.x + r.size.x * 0.5, r.position.y + 6.0)
	var a: float = m.get("spin", 0.0)
	var c: Vector2 = g.to_screen(hub)
	for k in 3:
		var ang := a + k * TAU / 3.0
		ov.draw_line(c, c + Vector2(cos(ang), sin(ang)) * 14.0 * z, Color(0.85, 0.92, 1.0, 0.9), maxf(1.0, z))
