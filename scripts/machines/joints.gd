extends RefCounted
## Joints in the game (A8): the records behind the engine's joints (native/src/joints.cpp), keyed to
## module ids so they survive a module's definition being renamed or merged. `g.joints` maps a
## record id to {id, kind, a, b, eng, rigid, la, lb}: the modules it holds (b 0 is the world), the
## engine joint's id, whether the rig walk (`MU.rig`) crosses it, and the anchors, in each body's
## bitmap frame (a world point when b is 0). The engine owns the physics and the save of the
## joints themselves; these records are what the game draws, lists and clears.
##
## Attach points: every module can be held at the middle of its edges, at its corners and at the
## middle of each face (`points`). A definition may list more under `attach` (`{"face": name,
## "kind": "anchor"}`); A9's Hookups declare theirs the same way. `snap` also takes a bare spot on
## a body's surface, which is what a line or a bolt ends on when nothing is declared there.

const MU = preload("res://scripts/machines/mu.gd")
const F = preload("res://scripts/machines/faces.gd")

## What each kind is in the engine (joints.cpp's types), whether the rig walk crosses it, the load it
## carries before it snaps (impulse a tick, the engine's `load`; a hanging module reads a quarter
## of its cells) and the stretch it takes (cells).
const KINDS := {
	"bolt": {"type": 2, "rigid": true, "name": "Bolt", "max_load": 900.0, "limit": 14.0},
	"hinge": {"type": 0, "rigid": false, "name": "Hinge", "max_load": 700.0, "limit": 14.0},
	"motor": {"type": 3, "rigid": false, "name": "Motor", "max_load": 700.0, "limit": 14.0},
	"rope": {"type": 1, "rigid": false, "name": "Rope", "max_load": 500.0, "limit": 1e9},
	"slide": {"type": 4, "rigid": false, "name": "Slide", "max_load": 900.0, "limit": 14.0},
}
const SNAP_RADIUS := 8.0        # cells: how far from a click an attach point or a body's surface is taken


static func reset(g) -> void:
	g.joints.clear()
	g.next_joint = 1


# --- Making and unmaking ----------------------------------------------------------

## A body's local (bitmap) point for a world point, at the pose the body has now.
static func _local(g, m: Dictionary, p: Vector2) -> Vector2:
	var st: PackedFloat32Array = g.sim.body_state(m["body"])
	var info: PackedFloat32Array = g.sim.body_info(m["body"])
	return (p - Vector2(st[0], st[1])).rotated(-st[2]) + Vector2(info[2], info[3])


## Joins module `a` to module `b` (0 for the world's rock) of kind `kind` at world point `at_a` on
## a and `at_b` on b (default the same spot). `extra` goes to the engine as it is (rate, lag, lo,
## hi, goal, drive, len ... see joints.cpp), over the kind's defaults. Returns the record id, or 0
## when a module is missing or the engine refuses.
static func attach(g, kind: String, a: int, b: int, at_a: Vector2, at_b := Vector2(-1.0, -1.0), extra := {}) -> int:
	if not KINDS.has(kind) or not g.modules.has(a) or (b != 0 and not g.modules.has(b)) or a == b:
		return 0
	if at_b.x < 0.0:
		at_b = at_a
	var k: Dictionary = KINDS[kind]
	var p := {"type": k["type"], "a": g.modules[a]["body"], "b": g.modules[b]["body"] if b != 0 else 0,
			"ax": at_a.x, "ay": at_a.y, "bx": at_b.x, "by": at_b.y,
			"max_load": k["max_load"], "limit": k["limit"], "rooted": b == 0}
	p.merge(extra, true)
	var eng: int = g.sim.add_joint(p)
	if eng <= 0:
		return 0
	var id: int = g.next_joint
	g.next_joint += 1
	g.joints[id] = {"id": id, "kind": kind, "a": a, "b": b, "eng": eng, "rigid": k["rigid"],
			"la": _local(g, g.modules[a], at_a), "lb": _local(g, g.modules[b], at_b) if b != 0 else at_b}
	return id


## Takes joint `id` away (the engine's joint too). False if there is no such joint.
static func detach(g, id: int) -> bool:
	if not g.joints.has(id):
		return false
	g.sim.remove_joint(g.joints[id]["eng"])
	g.joints.erase(id)
	return true


## Every joint touching module `id` goes; the engine drops its own with the body, this clears the
## records at once.
static func drop_module(g, id: int) -> void:
	for jid: int in g.joints.keys():
		var j: Dictionary = g.joints[jid]
		if j["a"] == id or j["b"] == id:
			g.sim.remove_joint(j["eng"])
			g.joints.erase(jid)


## The joints touching module `id` (record ids).
static func of_module(g, id: int) -> Array:
	var out: Array = []
	for jid: int in g.joints:
		if g.joints[jid]["a"] == id or g.joints[jid]["b"] == id:
			out.append(jid)
	return out


## Every tick: joints the engine let go (snapped, a body lost, an anchor whose rock went) leave the
## list, and the player is told about the ones that matter.
static func tick(g) -> void:
	if g.joints.is_empty():
		return
	var ev: PackedInt32Array = g.sim.take_joint_events()
	for i in range(0, ev.size(), 2):
		for jid: int in g.joints.keys():
			var j: Dictionary = g.joints[jid]
			if j["eng"] != ev[i]:
				continue
			g.joints.erase(jid)
			if ev[i + 1] == 1:
				g.show_banner("A %s snapped." % KINDS[j["kind"]]["name"].to_lower(), 2.0)
			elif ev[i + 1] == 3:
				g.show_banner("A %s lost its hold: the rock went." % KINDS[j["kind"]]["name"].to_lower(), 2.0)
			break
	# After a load the engine and the records must agree: a record whose joint is gone is dropped.
	if g.ticks % 60 == 0:
		var live := {}
		for e: int in g.sim.joint_ids():
			live[e] = true
		for jid: int in g.joints.keys():
			if not live.has(g.joints[jid]["eng"]):
				g.joints.erase(jid)


# --- Reading ---------------------------------------------------------------------

## Where joint `id`'s anchors are in the world now: [on a, on b], or [] if it is gone.
static func anchors(g, id: int) -> Array:
	var j: Dictionary = g.joints.get(id, {})
	if j.is_empty() or not g.modules.has(j["a"]):
		return []
	var ma: Dictionary = g.modules[j["a"]]
	var pa := MU.world(MU.frame(g, ma, MU.defs[ma["def"]]), j["la"])
	if j["b"] == 0:
		return [pa, j["lb"]]
	if not g.modules.has(j["b"]):
		return []
	var mb: Dictionary = g.modules[j["b"]]
	return [pa, MU.world(MU.frame(g, mb, MU.defs[mb["def"]]), j["lb"])]


## The engine's reading of joint `id`: {strain, load, angle, extent, target}, or {}.
static func state(g, id: int) -> Dictionary:
	var j: Dictionary = g.joints.get(id, {})
	if j.is_empty():
		return {}
	var s: PackedFloat32Array = g.sim.joint_state(j["eng"])
	if s.size() < 5:
		return {}
	return {"strain": s[0], "load": s[1], "angle": s[2], "extent": s[3], "target": s[4]}


## The modules joined to `id` by joints the rig walk crosses (bolts).
static func rigid_partners(g, id: int) -> Array:
	var out: Array = []
	for jid: int in g.joints:
		var j: Dictionary = g.joints[jid]
		if not j["rigid"]:
			continue
		if j["a"] == id and j["b"] != 0:
			out.append(j["b"])
		elif j["b"] == id:
			out.append(j["a"])
	return out


# --- Attach points -----------------------------------------------------------------

## The spots module `m` can be held at, in the world: [{pos, dir, kind, name}]. The middles of the four
## edges and the four corners ("edge", "corner"), the middle of each face (its type name), and what
## the definition lists under `attach`.
static func points(g, m: Dictionary) -> Array:
	var def: Dictionary = MU.defs[m["def"]]
	var fr := MU.frame(g, m, def)
	var lay: Dictionary = fr["lay"]
	var size: Vector2i = lay["size"]
	var out: Array = []
	var w := float(size.x)
	var h := float(size.y)
	for e: Array in [[Vector2(w * 0.5, 0.0), Vector2(0, -1)], [Vector2(w, h * 0.5), Vector2(1, 0)],
			[Vector2(w * 0.5, h), Vector2(0, 1)], [Vector2(0.0, h * 0.5), Vector2(-1, 0)]]:
		out.append({"pos": MU.world(fr, e[0]), "dir": MU.turn(fr, e[1]), "kind": "edge", "name": ""})
	for c: Vector2 in [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]:
		out.append({"pos": MU.world(fr, c), "dir": MU.turn(fr, (c - Vector2(w, h) * 0.5).normalized()), "kind": "corner", "name": ""})
	var fl: Array = lay["faces"]
	for i in fl.size():
		out.append({"pos": MU.world(fr, fl[i]["centre"]), "dir": MU.turn(fr, Vector2(fl[i]["dir"])),
				"kind": F.TYPE_NAMES[fl[i]["type"]], "name": fl[i].get("name", "")})
	for a: Dictionary in def.get("attach", []):
		var fi := MU.face_index(def, a.get("face", ""))
		if fi >= 0:
			out.append({"pos": MU.world(fr, fl[fi]["centre"]), "dir": MU.turn(fr, Vector2(fl[fi]["dir"])),
					"kind": a.get("kind", "anchor"), "name": a.get("face", "")})
	return out


## What a click at world point `p` takes hold of, within `radius` cells: the nearest attach point of
## any module, else the nearest bit of a module's body surface. {module, pos, dir, kind}, or {}.
static func snap(g, p: Vector2, radius := SNAP_RADIUS) -> Dictionary:
	var best := {}
	var best_d := radius
	var by_body := {}
	for id: int in g.modules:
		by_body[g.modules[id]["body"]] = id
		for pt: Dictionary in points(g, g.modules[id]):
			var d: float = p.distance_to(pt["pos"])
			if d <= best_d:
				best_d = d
				best = {"module": id, "pos": pt["pos"], "dir": pt["dir"], "kind": pt["kind"]}
	if not best.is_empty():
		return best
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := Vector2(floor(p.x) + dx + 0.5, floor(p.y) + dy + 0.5)
			var d := p.distance_to(cell)
			if d > best_d:
				continue
			var owner: int = g.sim.get_owner(int(cell.x), int(cell.y))
			if owner != 0 and by_body.has(owner):
				best_d = d
				best = {"module": by_body[owner], "pos": cell, "dir": Vector2.ZERO, "kind": "surface"}
	return best
