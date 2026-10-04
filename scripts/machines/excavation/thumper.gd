extends RefCounted
## Tethered Thumper (A4): a heavy block that hangs from a Winch cable and hits the ground. Any
## hard landing sets off a blast in a 90 degree cone out of its `front`: the harder it lands, the
## stronger the blast, so a long drop breaks what a short one only dents (Obsidian wants a drop
## of ten cells or more). The rubble is shoved aside (and lost) as the Winch lowers the Thumper
## into the hole, so it works down through rock on its own. The Winch runs the lift and drop
## (see winch.gd); the Thumper only feels the landing.

const MU = preload("res://scripts/machines/mu.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")

const VY := 4                   # body_state's downward speed, cells a second
const COOLDOWN := 30            # ticks between blasts


## Whether `m` is a Thumper.
static func is_thumper(def: Dictionary) -> bool:
	return def.get("kind", "") == "thumper"


static func scan(_g, m: Dictionary, _def: Dictionary) -> void:
	if m.get("thumps", 0) == 0:
		m["state"] = "Hang it from a Winch: it lifts the Thumper and lets it fall."


## Every tick: a landing is a sudden loss of speed along the front.
static func step(g, m: Dictionary, def: Dictionary) -> void:
	var st: PackedFloat32Array = g.sim.body_state(m["body"])
	if st.size() < 10:
		return
	var p: Dictionary = def["params"]
	var vy: float = st[VY]
	var prev: float = m.get("vy", 0.0)
	m["vy"] = vy
	m["cool"] = maxi(m.get("cool", 0) - 1, 0)
	if m["cool"] > 0 or prev < float(p["min_speed"]) or vy > prev * 0.5:
		return
	m["cool"] = COOLDOWN
	var fo := CUT.front_of(g, m, def)
	var n: Vector2i = fo["n"]
	# The cone's tip sits half the Thumper's width behind its front, so the hole is as wide as the
	# Thumper by the time it gets there and the rig can follow the blast down.
	var at: Vector2 = fo["p"] - Vector2(n) * (float(fo["across"]) * 0.5)
	var power := clampi(int(prev / float(p["speed_per_power"])), 1, int(p["max_power"]))
	var broke: int = g.sim.explode_cone(int(floorf(at.x)), int(floorf(at.y)), float(p["radius"]), power, atan2(float(n.y), float(n.x)), PI * 0.25)
	m["thumps"] = m.get("thumps", 0) + 1
	m["last"] = {"power": power, "broke": broke, "speed": prev, "tick": g.ticks}
	m["flash"] = 12
	m["state"] = "Thump: power %d, %d cells broken." % [power, broke]


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d thumps so far." % [m.get("state", ""), m.get("thumps", 0)]


## The cone for a few frames after a blast.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var left: int = m.get("flash", 0)
	if left <= 0:
		return
	m["flash"] = left - 1
	var fo := CUT.front_of(g, m, def)
	var n := Vector2(fo["n"])
	var r := float(def["params"]["radius"]) - float(fo["across"]) * 0.5
	var o: Vector2 = fo["p"]
	var a := n.angle()
	var col := Color(1.0, 0.7, 0.3, 0.6 * float(left) / 12.0)
	for s in [-1.0, 1.0]:
		ov.draw_line(g.to_screen(o), g.to_screen(o + Vector2.from_angle(a + s * PI * 0.25) * r), col, maxf(1.0, z * 0.8))
