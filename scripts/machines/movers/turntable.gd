extends RefCounted
## Turntable (A4): a pinned hub with a mechanical face on each side. The hub turns about its own
## middle and takes with it everything joined to its faces (and what those are joined to, the
## Winch's rig walk in `MU.rig`), the way a rigid arm swings. Each rig module is driven along the
## chord of its own arc and spun by the same angle (`MU.drive`), so faces that met stay met.
## Click it to cycle hold (rests at the nearest quarter turn), step (a quarter turn, a pause,
## another) and spin (clockwise, round and round). Turning costs power.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")

const QUARTER := PI * 0.5
const ARRIVED := 0.01           # radians from the goal that count as there
const MODES := ["hold", "step", "spin"]


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	if not m.has("mode"):
		m["mode"] = "hold"
		m["goal"] = 0.0
		m["wait"] = -1
		m["bdir"] = 0
		m["rig"] = []
		m["pose"] = {}
	m["net"] = MU.networked(g, m, def)
	var rig: Array = []
	for fs: Dictionary in m["faces"]:
		for id: int in MU.rig(g, fs["link_m"], m["id"]):
			if not rig.has(id):
				rig.append(id)
	for id: int in m["rig"]:
		if not rig.has(id) and g.modules.has(id):
			g.modules[id]["powered"] = false
	m["rig"] = rig
	var st: PackedFloat32Array = g.sim.body_state(m["body"])
	for id: int in rig:
		g.modules[id]["powered"] = m["net"]
		# Where each joined module sits in the hub's frame when it joins; the swing keeps it there.
		if not m["pose"].has(id) and st.size() >= 3:
			var bs: PackedFloat32Array = g.sim.body_state(g.modules[id]["body"])
			m["pose"][id] = {"rel": (Vector2(bs[0], bs[1]) - Vector2(st[0], st[1])).rotated(-st[2]), "base": bs[2] - st[2]}
	for id: int in m["pose"].keys():
		if not rig.has(id):
			m["pose"].erase(id)


static func _snap(a: float) -> float:
	return roundf(a / QUARTER) * QUARTER


static func step(g, m: Dictionary, def: Dictionary) -> void:
	if not m.has("mode"):
		return
	var p: Dictionary = def["params"]
	var st: PackedFloat32Array = g.sim.body_state(m["body"])
	if st.size() < 3:
		return
	var ang := st[2]
	var pivot := Vector2(st[0], st[1])
	var speed := float(p["speed"])
	var want := 0.0
	match m["mode"]:
		"spin":
			want = speed
		"step":
			if absf(m["goal"] - ang) <= ARRIVED:
				if m["wait"] < 0:
					m["wait"] = int(p["dwell"])
				elif m["wait"] == 0:
					m["wait"] = -1
					m["goal"] = _snap(ang) + QUARTER
				else:
					m["wait"] -= 1
			if absf(m["goal"] - ang) > ARRIVED:
				want = clampf(m["goal"] - ang, -speed, speed)
		_:
			if absf(m["goal"] - ang) > ARRIVED:
				want = clampf(m["goal"] - ang, -speed, speed)
	# How far the joined modules lag behind the pose the hub's angle asks of them: something solid
	# in the arm's way holds them back, and the hub then waits (or backs away) rather than
	# winding on without them.
	var lag := 0.0
	var poses: Array = []
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if mm.is_empty() or not m["pose"].has(id):
			continue
		var bs: PackedFloat32Array = g.sim.body_state(mm["body"])
		if bs.size() < 3:
			continue
		var c := Vector2(bs[0], bs[1])
		lag = maxf(lag, (pivot + m["pose"][id]["rel"].rotated(ang) - c).length())
		poses.append([mm, c, bs[2], m["pose"][id]])
	if lag > float(p["lag"]):
		if m["bdir"] == 0:
			m["bdir"] = signf(want)
	elif lag < float(p["lag"]) * 0.5:
		m["bdir"] = 0
	var w := 0.0
	var why := ""
	if want != 0.0 and m["bdir"] != 0 and signf(want) == m["bdir"]:
		why = "Blocked."
	elif want != 0.0:
		if not m["net"]:
			why = "No Node or Hub within reach."
		elif MU.take_power(g, float(p["power"]) * D.DT):
			w = want
		else:
			why = "Waiting for power."
	m["why"] = why
	m["ang"] = ang
	MU.drive(m, Vector2.ZERO, w)
	for e: Array in poses:
		var target: Vector2 = pivot + e[3]["rel"].rotated(ang + w)
		MU.drive(e[0], target - e[1], clampf(ang + w + e[3]["base"] - e[2], -0.05, 0.05))


## A click on the module: hold, then step, then spin, then hold again.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	m["mode"] = MODES[(MODES.find(m.get("mode", "hold")) + 1) % MODES.size()]
	m["goal"] = _snap(m.get("ang", 0.0))
	m["wait"] = -1
	g.show_banner("%s: %s." % [def["name"], m["mode"]], 1.5)


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	var s := "%s, turned %d degrees. Click to change mode." % [str(m.get("mode", "hold")).capitalize(), roundi(rad_to_deg(m.get("ang", 0.0)))]
	var why: String = m.get("why", "")
	return s + (" " + why if why != "" else "")


## A dot on the pin.
static func draw(ov, g, m: Dictionary, _def: Dictionary, z: float) -> void:
	ov.draw_circle(g.to_screen(m["at"]), maxf(2.0, z * 2.5), Color(0.62, 0.64, 0.68, 0.95))
