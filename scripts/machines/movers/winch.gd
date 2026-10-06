extends RefCounted
## Winch (A3 starter kit): bolted in place, its cable face hooked to a Tank. The rig is the
## Tank and everything joined under it that isn't bolted down (the Excavator). The Winch
## moves the whole rig at one velocity (the engine's `drive_body`), so the modules stay
## square to each other. The Tank's fill runs it: empty goes down while the Excavator
## opens rows, full goes up, and at the top the Tank meets the Funnel and empties. The
## cable is as long as Drill Shaft research allows. A rig that can't go on says why.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")

const EMPTY := 0.02             # a Tank this full or less counts as empty
const PLOW_AHEAD := 2           # rows above the rig's modules cleared of loose powder on the way up
const PLOW_BELOW := 4           # rows under each module but the Excavator, cleared of loose powder on the way down
const PLOW_SIDE := 3            # ... and this many columns to either side of it


# --- The rig ---------------------------------------------------------------------

## Ids of the modules the Winch moves: the tethered one and whatever is joined to it,
## bolted-down modules (the Funnel) left out.
static func rig_of(g, m: Dictionary) -> Array:
	return MU.rig(g, m.get("tether", 0), m["id"])


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
	var th := _thumper(g, m)
	if not th.is_empty():
		_thump(g, m, p, th)
		return
	var dig := _digger(g, m)
	var v := 0.0
	var why := ""
	match m["state"]:
		"docked":
			if m["fill"] <= EMPTY:
				var stale: bool = m["halt"] != "" and m.get("halt_key", "") == _key(g, m)
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
				_stop(g, m, dig.get("stop", "The Excavator stopped: %s ahead." % dig["stuck"]))
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
	if v < 0.0:
		_plow(g, m)
	elif m["state"] == "down":
		_plow_down(g, m, dig)
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if not mm.is_empty():
			MU.drive(mm, Vector2(0.0, v))
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


static var _plug_mask := PackedByteArray()


## What a hauled-up rig clears off its path: loose powder, and the static rock of a cave-in plug
## lying over it. Never a casing (Obsidian) or bedrock.
static func plow_mask() -> PackedByteArray:
	if _plug_mask.is_empty():
		_plug_mask = M.mask("solid").duplicate()
		_plug_mask[D.OBSIDIAN] = 0
		_plug_mask[D.BEDROCK] = 0
	return _plug_mask


## A rig hauled up shoves what lies in its way aside. Bodies can't push powder, and sand that has
## slumped onto the Tank's roof or lodged in its casing would hold the rig for good (the seed 7
## jam); a cave-in that has set into a plug of Stone or Dirt would hold it just the same (the A4
## bot's stall at depth 770). All of it goes, inside the rig's own width: the tunnel's walls stay,
## and the spoil is lost.
static func _plow(g, m: Dictionary) -> void:
	var loose := plow_mask()
	var dug := 0
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if mm.is_empty():
			continue
		var r := MU.bounds(mm, MU.defs[mm["def"]])
		var got: PackedInt32Array = g.sim.dig_rect(r.position.x, r.position.y - PLOW_AHEAD, r.size.x, r.size.y + PLOW_AHEAD, loose, 0, 0)
		for mat in 256:
			dug += got[mat]
	m["plowed"] = m.get("plowed", 0) + dug


## A rig let down meets powder the Excavator's own span doesn't reach. The Tank is wider than what
## the Cutter looks at, the shaft only a cell or two wider than the Tank, and rubble lodged along
## the wall (or under the Tank's corner) held the rig at depth 638 and again at 659 while the
## Cutter went on and tore loose (the A5 bot, seed 7). An Excavator clears its own span and keeps
## the spoil, so it is left alone; every other module, a leading Pump included (it takes liquid and
## stops on any solid cell), shoves the powder at its sides and under its bottom edge aside, and
## that is lost, like the climb's. Walls are static and stay. It runs while the rig is let down even
## when it is held, since a Pump that finds powder ahead holds the rig itself.
static func _plow_down(g, m: Dictionary, dig: Dictionary) -> void:
	var powder := M.mask("powder")
	var dug := 0
	var skip: int = dig.get("id", 0) if MU.defs.get(dig.get("def", ""), {}).get("kind", "") != "pump" else 0
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if mm.is_empty() or id == skip:
			continue
		var r := MU.bounds(mm, MU.defs[mm["def"]])
		var got: PackedInt32Array = g.sim.dig_rect(r.position.x - PLOW_SIDE, r.position.y, r.size.x + 2 * PLOW_SIDE, r.size.y + PLOW_BELOW, powder, 0, 0)
		for mat in 256:
			dug += got[mat]
	m["plowed"] = m.get("plowed", 0) + dug


# --- The Thumper's cycle ----------------------------------------------------------
# docked -> down (until the Thumper rests on something) -> lift (the Thumper's own `lift` cells)
# -> drop (the cable goes slack: free fall, and the Thumper blasts when it lands) -> down again.

## The Thumper of the rig, or {}.
static func _thumper(g, m: Dictionary) -> Dictionary:
	for id: int in m["rig"]:
		var mm: Dictionary = g.modules.get(id, {})
		if not mm.is_empty() and MU.defs[mm["def"]].get("kind", "") == "thumper":
			return mm
	return {}


const CONTACT := 12             # ticks a lowered Thumper may make no headway before it counts as resting
const DROP_TICKS := 240         # a drop that hasn't landed by now is given up


static func _thump(g, m: Dictionary, p: Dictionary, th: Dictionary) -> void:
	var tp: Dictionary = MU.defs[th["def"]]["params"]
	var v := 0.0
	var why := ""
	var free := false
	match m["state"]:
		"docked":
			var stale: bool = m["halt"] != "" and m.get("halt_key", "") == _key(g, m)
			if stale:
				why = m["halt"]
			elif m["limit"] <= 0:
				why = "The cable has no length yet."
			else:
				m["halt"] = ""
				m["state"] = "down"
				m["rest"] = 0
				m["spent"] = 0
		"down":
			if m["cable"] >= float(m["limit"]):
				_stop(g, m, "The cable is out: Drill Shaft research lengthens it.")
			elif not m["net"]:
				why = "No Node or Hub within reach."
			elif MU.take_power(g, float(p["power"]) * D.DT):
				v = float(p["down"])
				_plow_below(g, m, th)
				# Resting: a window of CONTACT ticks that gained under half a cell.
				m["rest"] = m.get("rest", 0) + 1
				if m["rest"] == 1:
					m["rest_ref"] = m["cable"]
				elif m["rest"] > CONTACT:
					if m["cable"] - float(m["rest_ref"]) < 0.5:
						m["state"] = "lift"
						m["lift_from"] = m["cable"]
					m["rest"] = 0
			else:
				why = "Waiting for power."
		"lift":
			var top := maxf(float(m["lift_from"]) - float(tp["lift"]), 0.0)
			if m["cable"] <= top + 0.1 or m["cable"] <= 0.02:
				m["state"] = "drop"
				m["drop_t"] = 0
				m["drop_from"] = m["cable"]
				m["seen_thumps"] = th.get("thumps", 0)
			elif not m["net"]:
				why = "No Node or Hub within reach."
			elif MU.take_power(g, float(tp["lift_power"]) * D.DT):
				v = -minf(float(p["up"]), maxf(m["cable"] - top, 0.0))
			else:
				why = "Waiting for power."
		"drop":
			free = true
			m["drop_t"] = m.get("drop_t", 0) + 1
			if th.get("thumps", 0) != m["seen_thumps"]:
				var last: Dictionary = th["last"]
				m["spent"] = m["spent"] + 1 if last["broke"] < int(tp["spent"]) else 0
				m["state"] = "down"
				m["rest"] = 0
				free = false
				if m["spent"] >= 3:
					_stop(g, m, "The Thumper has nothing left below it to break.")
			elif m["cable"] > float(m["drop_from"]) + 3.0 and m["drop_t"] > 30 and th.get("vy", 0.0) < 1.0:
				# Landed with no blast (too soft a landing): lower and try again.
				m["state"] = "down"
				m["rest"] = 0
				free = false
			elif m["drop_t"] > DROP_TICKS:
				m["state"] = "down"
				m["rest"] = 0
				free = false
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
	if not free:
		for id: int in m["rig"]:
			var mm: Dictionary = g.modules.get(id, {})
			if not mm.is_empty():
				MU.drive(mm, Vector2(0.0, v))
	m["last_cable"] = m["cable"]


## Rubble from the blasts (and loose ground) under a Thumper that is being lowered is shoved aside
## and lost, the way a hauled-up rig plows: bodies can't push powder, and the rig would
## otherwise rest on its own debris. Rock stays for the blasts.
static func _plow_below(g, m: Dictionary, th: Dictionary) -> void:
	var r := MU.bounds(th, MU.defs[th["def"]])
	var got: PackedInt32Array = g.sim.dig_rect(r.position.x, r.end.y, r.size.x, PLOW_AHEAD, M.mask("powder"), 0, 0)
	for mat in 256:
		m["plowed"] = m.get("plowed", 0) + got[mat]


## A click restarts a Winch that a halt has docked (a Thumper rig has no research that would).
static func use(g, m: Dictionary, _def: Dictionary) -> void:
	if m.get("halt", "") == "" or _thumper(g, m).is_empty():
		return
	m["halt"] = ""
	g.show_banner("Winch: starting again.", 1.5)


## What would change the reason a halt holds: Drill Bit (hardness), Drill Shaft (length) and which
## module digs (swapping a Cutter for a Pump, or back, lifts the hold).
static func _key(g, m: Dictionary) -> String:
	return "%d/%d/%s" % [g.level("drill_bit"), g.max_reach(), _digger(g, m).get("def", "")]


# Goes back up (to unload), and stays docked afterwards until research changes.
static func _stop(g, m: Dictionary, why: String) -> void:
	m["halt"] = why
	m["halt_key"] = _key(g, m)
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
