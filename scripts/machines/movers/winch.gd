extends RefCounted
## Winch (A3 starter kit): bolted in place, its cable face hooked to a Tank. The rig is the
## Tank and everything joined under it that isn't bolted down (the Excavator). The Winch
## moves the whole rig at one velocity (the engine's `drive_body`), so the modules stay
## square to each other. The Tank's fill runs it: empty goes down while the Excavator
## opens rows, full goes up, and at the top the Tank meets the Funnel and empties. The
## cable is as long as Drill Shaft research allows. A rig that can't go on says why.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")

const EMPTY := 0.02             # a Tank this full or less counts as empty


# --- The rig ---------------------------------------------------------------------

## Ids of the modules the Winch moves: the tethered one and whatever is joined to it,
## bolted-down modules (the Funnel) left out.
static func rig_of(g, m: Dictionary) -> Array:
	var out: Array = []
	var t: int = m.get("tether", 0)
	if t == 0 or not g.modules.has(t):
		return out
	var queue: Array = [t]
	var seen := {t: true, m["id"]: true}
	while not queue.is_empty():
		var id: int = queue.pop_back()
		out.append(id)
		var mm: Dictionary = g.modules[id]
		for f: Dictionary in mm["faces"]:
			var o: int = f["link_m"]
			if o == 0 or seen.has(o) or not g.modules.has(o):
				continue
			seen[o] = true
			if MU.defs[g.modules[o]["def"]].get("anchored", false):
				continue
			queue.append(o)
	return out


static func _release(g, m: Dictionary) -> void:
	for id: int in m.get("rig", []):
		var mm: Dictionary = g.modules.get(id, {})
		if not mm.is_empty() and mm.get("rig_of", 0) == m["id"]:
			mm["rig_of"] = 0
			mm["powered"] = false
	m["rig"] = []


static func _y(g, id: int) -> float:
	var st: PackedFloat32Array = g.sim.body_state(g.modules[id]["body"])
	return st[1] if st.size() > 1 else 0.0


## The Excavator of the rig (the module that reports `room`), or {}.
static func _digger(g, m: Dictionary) -> Dictionary:
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if mm.has("room"):
			return mm
	return {}


# --- Scan: hooking, the rig, the readings the motion uses --------------------------

static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var partner := MU.partner(g, m, def, "cable")
	var t: int = partner.get("id", 0)
	if t != m.get("tether", 0):
		_release(g, m)
		m["tether"] = t
		m["state"] = "idle" if t == 0 else "docked"
		m["cable"] = 0.0
		m["halt"] = ""
		if t != 0:
			m["cm0"] = _y(g, t)
	if t == 0:
		return
	m["net"] = MU.networked(g, m, def)
	var rig := rig_of(g, m)
	for id in m.get("rig", []):
		if not rig.has(id) and g.modules.has(id):
			g.modules[id]["rig_of"] = 0
	m["rig"] = rig
	for id: int in rig:
		g.modules[id]["rig_of"] = m["id"]
		g.modules[id]["powered"] = m["net"]
	m["limit"] = g.max_reach()
	var tank: Dictionary = g.modules[t]
	var cap: int = maxi(1, MU.capacity(tank, MU.defs[tank["def"]]))
	m["fill"] = float(MU.stored(tank)) / float(cap)


# --- Step: the motion, every tick ---------------------------------------------------

static func step(g, m: Dictionary, def: Dictionary) -> void:
	var t: int = m.get("tether", 0)
	if t == 0 or not g.modules.has(t) or m["rig"].is_empty():
		return
	var p: Dictionary = def["params"]
	m["cable"] = _y(g, t) - float(m["cm0"])
	var dig := _digger(g, m)
	var v := 0.0
	var why := ""
	match m["state"]:
		"docked":
			if m["fill"] <= EMPTY:
				var stale: bool = m["halt"] != "" and m.get("halt_key", "") == _key(g)
				if stale:
					why = m["halt"]
				elif m["limit"] <= 0:
					why = "The cable has no length yet."
				else:
					m["halt"] = ""
					m["state"] = "down"
			else:
				why = "Emptying."
		"down":
			if m["fill"] >= float(p["full"]):
				m["state"] = "up"
			elif m["cable"] >= float(m["limit"]):
				_stop(g, m, "The cable is out: Drill Shaft research lengthens it.")
			elif not dig.is_empty() and dig.get("stuck", "") != "" and dig["room"] == 0:
				_stop(g, m, "The Excavator stopped: %s ahead." % dig["stuck"])
			elif not m["net"]:
				why = "No Node or Hub within reach."
			else:
				var room: int = dig.get("room", 0)
				var speed := float(p["down"]) * (1.0 if room >= 2 else 0.5 if room == 1 else 0.0)
				if speed > 0.0:
					if MU.take_power(g, float(p["power"]) * D.DT):
						v = speed
					else:
						why = "Waiting for power."
		"up":
			if m["cable"] <= 0.02:
				m["state"] = "docked"
			elif not m["net"]:
				why = "No Node or Hub within reach."
			elif MU.take_power(g, float(p["power"]) * D.DT):
				v = -minf(float(p["up"]), maxf(m["cable"], 0.0))
			else:
				why = "Waiting for power."
	m["why"] = why
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if not mm.is_empty():
			g.sim.drive_body(mm["body"], 0.0, v)
	# A rig that is meant to move and doesn't (something solid in the way) is stuck.
	if v != 0.0:
		var last: float = m.get("last_cable", m["cable"])
		if absf(m["cable"] - last) < absf(v) * 0.25:
			m["stall"] = m.get("stall", 0) + 1
		else:
			m["stall"] = 0
		if m["stall"] > int(p["stall_ticks"]):
			m["stall"] = 0
			if m["state"] == "down":
				_stop(g, m, "The rig is jammed.")
			else:
				m["why"] = "The rig is jammed on the way up."
	m["last_cable"] = m["cable"]


## What would change the reason a halt holds: Drill Bit (hardness) and Drill Shaft (length).
static func _key(g) -> String:
	return "%d/%d" % [g.level("drill_bit"), g.max_reach()]


# Goes back up (to unload), and stays docked afterwards until research changes.
static func _stop(g, m: Dictionary, why: String) -> void:
	m["halt"] = why
	m["halt_key"] = _key(g)
	m["state"] = "up"
	g.alert("module", "Winch: %s" % why, m["at"])


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	if m.get("tether", 0) == 0:
		return "Nothing hooked on."
	var s := "%s, cable out %d of %d." % [str(m["state"]).capitalize(), int(m.get("cable", 0.0)), m.get("limit", 0)]
	var why: String = m.get("why", "")
	if why == "" and m.get("halt", "") != "" and m["state"] == "docked":
		why = m["halt"]
	return s + (" " + why if why != "" else "")


## The cable, from the Winch's face to the Tank's hook.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var t: int = m.get("tether", 0)
	if t == 0 or not g.modules.has(t):
		return
	var tank: Dictionary = g.modules[t]
	var tdef: Dictionary = MU.defs[tank["def"]]
	var a := MU.world(MU.frame(g, m, def), m_face(def, m, "cable"))
	var b := MU.world(MU.frame(g, tank, tdef), m_face(tdef, tank, "hook"))
	ov.draw_line(g.to_screen(a), g.to_screen(b), Color(0.82, 0.8, 0.7, 0.9), maxf(1.0, z * 0.6))


static func m_face(def: Dictionary, m: Dictionary, name: String) -> Vector2:
	return MU.F.layout(def, m["turns"])["faces"][MU.face_index(def, name)]["centre"]
