extends RefCounted
## Piston and Gantry (A4): a bolted-down module whose mechanical face holds a load, which it
## slides along a straight line. A Piston pushes the load out along its face's normal; a Gantry
## carries it along its rail, at right angles to the face. The load is the module joined at the
## face and everything joined to that (the Winch's rig, `MU.rig`); the mover adds its velocity to
## all of them (`MU.drive`), so a Gantry can carry a Piston's load too. Clicking a mover cycles
## its mode: run (out and back with a pause at each end), out, back. Moving costs power.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")

const ARRIVED := 0.05           # cells from the goal that count as there
const MODES := ["run", "out", "back"]


## The line the load slides along, in the world: the face's normal (a Piston) or at right
## angles to it (a Gantry), as a unit vector.
static func _axis(fr: Dictionary, def: Dictionary) -> Vector2:
	var fl: Array = fr["lay"]["faces"]
	var d := Vector2(fl[MU.face_index(def, def["params"]["face"])]["dir"])
	if def["params"]["axis"] == "along":
		d = Vector2(d.y, -d.x)
	return MU.turn(fr, d)


## Where the load sits relative to the mover (body centres), in the world.
static func _rel(g, m: Dictionary, t: int) -> Vector2:
	var a: PackedFloat32Array = g.sim.body_state(m["body"])
	var b: PackedFloat32Array = g.sim.body_state(g.modules[t]["body"])
	if a.size() < 2 or b.size() < 2:
		return Vector2.ZERO
	return Vector2(b[0] - a[0], b[1] - a[1])


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var t: int = MU.partner(g, m, def, def["params"]["face"]).get("id", 0)
	if t != m.get("tether", 0):
		_release(g, m)
		m["tether"] = t
		m["pos"] = 0.0
		m["last_pos"] = 0.0
		m["wait"] = -1
		m["dir"] = 1
		m["stall"] = 0
		if t != 0:
			m["rel0"] = _rel(g, m, t)
	if not m.has("mode"):
		m["mode"] = "run"
		m["tether"] = t
		m["rig"] = []
	m["net"] = MU.networked(g, m, def)
	if t == 0:
		return
	var rig := MU.rig(g, t, m["id"])
	for id: int in m.get("rig", []):
		if not rig.has(id) and g.modules.has(id):
			g.modules[id]["powered"] = false
	m["rig"] = rig
	for id: int in rig:
		g.modules[id]["powered"] = m["net"]


static func _release(g, m: Dictionary) -> void:
	for id: int in m.get("rig", []):
		if g.modules.has(id):
			g.modules[id]["powered"] = false
	m["rig"] = []


static func step(g, m: Dictionary, def: Dictionary) -> void:
	var t: int = m.get("tether", 0)
	if t == 0 or not g.modules.has(t) or m.get("rig", []).is_empty():
		return
	var p: Dictionary = def["params"]
	var axis := _axis(MU.frame(g, m, def), def)
	var pos: float = (_rel(g, m, t) - m["rel0"]).dot(axis)
	m["pos"] = pos
	var stroke := float(p["stroke"])
	var goal := 0.0
	match m["mode"]:
		"out":
			goal = stroke
		"run":
			goal = stroke if m["dir"] > 0 else 0.0
	var v := 0.0
	var why := ""
	if absf(goal - pos) <= ARRIVED:
		if m["mode"] == "run":
			if m["wait"] < 0:
				m["wait"] = int(p["dwell"])
			elif m["wait"] == 0:
				m["wait"] = -1
				m["dir"] = -m["dir"]
			else:
				m["wait"] -= 1
	elif not m["net"]:
		why = "No Node or Hub within reach."
	elif MU.take_power(g, float(p["power"]) * D.DT):
		v = clampf(goal - pos, -float(p["speed"]), float(p["speed"]))
	else:
		why = "Waiting for power."
	# A load that is meant to move and doesn't (something solid in the way) is blocked.
	if v != 0.0 and absf(pos - m["last_pos"]) < absf(v) * 0.25:
		m["stall"] += 1
	else:
		m["stall"] = 0
	if m["stall"] > int(p["stall_ticks"]):
		why = "Blocked."
		if m["mode"] == "run":
			m["stall"] = 0
			m["dir"] = -m["dir"]
	m["last_pos"] = pos
	m["why"] = why
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if not mm.is_empty():
			MU.drive(mm, axis * v)


## A click on the module: run, then out, then back, then run again.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	m["mode"] = MODES[(MODES.find(m.get("mode", "run")) + 1) % MODES.size()]
	m["wait"] = -1
	g.show_banner("%s: %s." % [def["name"], m["mode"]], 1.5)


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	if m.get("tether", 0) == 0:
		return "Nothing mounted. Click it to change its mode."
	var s := "%s, %d of %d out. Click to change mode." % [str(m.get("mode", "run")).capitalize(), roundi(m.get("pos", 0.0)), int(def["params"]["stroke"])]
	var why: String = m.get("why", "")
	return s + (" " + why if why != "" else "")


## The rod, from the mover's face to the load's.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var t: int = m.get("tether", 0)
	if t == 0 or not g.modules.has(t):
		return
	var fi := MU.face_index(def, def["params"]["face"])
	var load_m: Dictionary = g.modules[t]
	var ldef: Dictionary = MU.defs[load_m["def"]]
	var a := MU.world(MU.frame(g, m, def), MU.F.layout(def, m["turns"])["faces"][fi]["centre"])
	var b := MU.world(MU.frame(g, load_m, ldef), MU.F.layout(ldef, load_m["turns"])["faces"][m["faces"][fi]["link_f"]]["centre"])
	ov.draw_line(g.to_screen(a), g.to_screen(b), Color(0.62, 0.64, 0.68, 0.95), maxf(1.0, z * 3.0))
