extends RefCounted
## Floodlight (A9 tools): a tool bolted to the side of a machine (any base, machine, interior or exterior part: `needs`
## ["host"]) that throws a long cone of light out of its `front` while the Hub's stock pays its power. It needs a Node or
## the Hub in reach of itself or of the part it stands on. The Lamp is the other light: it stands on its own and lights the
## area round it. The light itself is machines.gd's `lights` (one circle per entry of `beam`), read each time the game works
## out what is lit; the engine's light is a flood of circles, so the cone is a chain of circles inscribed in it.

const D = preload("res://scripts/defs.gd")
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


## The cone as circles [centre, radius]: `range` cells (v2 units, times D.S) along the front, `spread` degrees either side
## of the axis. Circles inscribed in the cone, each about twice as far out as the last and as wide as the cone is there, so
## they overlap and the chain reads as one cone; a small one at the lens lights the part it stands on.
static func beam(g, m: Dictionary, def: Dictionary) -> Array:
	var ps: Dictionary = def["params"]
	var s := sin(deg_to_rad(float(ps["spread"])))
	var reach := float(ps["range"]) * D.S
	var out: Array = [[m["at"], float(ps["lens"]) * D.S]]
	var foot: Dictionary = MT.foot_of(g, m, def)
	var axis: Vector2 = -(foot["dir"] as Vector2).normalized()
	var t := float(ps["lens"]) * D.S * 2.0
	while t * (1.0 + s) <= reach:
		out.append([(foot["pos"] as Vector2) + axis * t, t * s])
		t *= 1.7
	out.append([(foot["pos"] as Vector2) + axis * reach / (1.0 + s), reach / (1.0 + s) * s])      # the last circle ends at the range
	return out


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return str(m.get("state", ""))


## The cone, faintly, while lit.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	if not m.get("lit", false):
		return
	var c: Vector2 = g.to_screen(m["at"])
	var foot: Dictionary = MT.foot_of(g, m, def)
	var axis: Vector2 = -(foot["dir"] as Vector2).normalized()
	var half := deg_to_rad(float(def["params"]["spread"]))
	var span := 60.0 * z
	ov.draw_colored_polygon(PackedVector2Array([c, c + axis.rotated(half) * span, c + axis.rotated(-half) * span]), Color(1.0, 0.97, 0.78, 0.22))
