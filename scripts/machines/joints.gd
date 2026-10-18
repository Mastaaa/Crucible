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
const M = preload("res://scripts/materials.gd")

## What each kind is in the engine (joints.cpp's types), whether the rig walk crosses it, the load it
## carries before it snaps (impulse a tick, the engine's `load`; a hanging module reads a quarter
## of its cells) and the stretch it takes (cells).
const KINDS := {
	"bolt": {"type": 2, "rigid": true, "name": "Bolt", "max_load": 900.0, "limit": 14.0, "cost": [1, 0, 0, 0, 0], "tech": "joints",
			"blurb": "Joins two parts rigidly where they meet. Click again on a joint to take it off."},
	"hinge": {"type": 0, "rigid": false, "name": "Hinge", "max_load": 700.0, "limit": 14.0, "cost": [1, 0, 0, 0, 0], "tech": "joints",
			"blurb": "Joins two parts, or a part and the rock, so they swing about the spot. Click again on a joint to take it off."},
	"motor": {"type": 3, "rigid": false, "name": "Motor", "max_load": 700.0, "limit": 14.0, "cost": [4, 0, 0, 0, 0], "tech": "motor",
			"blurb": "A hinge that turns. Click it once to turn right, again to turn left, again to hold. It draws power while it turns."},
	"piton": {"type": 2, "rigid": false, "name": "Piton", "max_load": 1100.0, "limit": 14.0, "cost": [1, 0, 0, 0, 0], "tech": "joints",
			"blurb": "Fixes a part to the rock beside it, rigidly. Click again on a joint to take it off."},
	"rope": {"type": 1, "rigid": false, "name": "Rope", "max_load": 500.0, "limit": 1e9, "cost": [1, 0, 0, 0, 0]},
	"slide": {"type": 4, "rigid": false, "name": "Slide", "max_load": 900.0, "limit": 14.0, "cost": [0, 0, 0, 0, 0]},
}
const TOOLS := ["bolt", "hinge", "motor", "piton"]      # what the Build list offers
const SNAP_RADIUS := 8.0        # cells: how far from a click an attach point or a body's surface is taken
const GAP := 6.0                # cells: the most two parts (or a part and the rock) may be apart where a joint goes
const TAKE_OFF_RADIUS := 2.5    # a click this near a joint's anchor takes it off
const MOTOR_RATE := 1.2         # radians a second
const MOTOR_POWER := 0.05       # power a second while a motor is turning
const COLOURS := {"bolt": Color(0.75, 0.75, 0.8), "hinge": Color(0.95, 0.95, 0.6), "motor": Color(1.0, 0.6, 0.25),
		"piton": Color(0.7, 0.5, 0.35), "rope": Color(0.8, 0.7, 0.5), "slide": Color(0.6, 0.8, 1.0)}


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
	g.joints[id] = {"id": id, "kind": kind, "a": a, "b": b, "eng": eng, "rigid": k["rigid"], "mode": 0, "set": 0,
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
	for jid: int in g.joints:
		if g.joints[jid]["kind"] == "motor":
			_drive(g, g.joints[jid])
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


# --- Motors ------------------------------------------------------------------------

## Keeps a motor's engine joint to what its record asks: turning (mode 1 right, -1 left) while the
## Hub has the power, holding its angle otherwise.
static func _drive(g, j: Dictionary) -> void:
	var want: int = j["mode"]
	if want != 0 and not MU.take_power(g, MOTOR_POWER / 60.0):
		want = 0
	if want == j["set"]:
		return
	j["set"] = want
	g.sim.set_joint(j["eng"], {"rate": float(want) * MOTOR_RATE} if want != 0 else {"hold": true})


## A click on a motor's anchor, with nothing picked: off, right, left, off. True if one was there.
static func use(g, cell: Vector2i) -> bool:
	var p := Vector2(cell) + Vector2(0.5, 0.5)
	var best := 4.0
	var hit := 0
	for jid: int in g.joints:
		if g.joints[jid]["kind"] != "motor":
			continue
		var a: Array = anchors(g, jid)
		if not a.is_empty() and p.distance_to(a[0]) <= best:
			best = p.distance_to(a[0])
			hit = jid
	if hit == 0:
		return false
	var j: Dictionary = g.joints[hit]
	j["mode"] = {0: 1, 1: -1, -1: 0}[j["mode"]]
	g.show_banner("Motor: %s." % {0: "holding", 1: "turning right", -1: "turning left"}[j["mode"]], 1.5)
	return true


# --- Putting joints down -------------------------------------------------------------

static func unlocked(g, kind: String) -> bool:
	return not KINDS[kind].has("tech") or g.researched.has(KINDS[kind]["tech"])


## Whether the cell is rock a rooted joint can hold on to: a static material no body owns.
static func is_ground(g, x: int, y: int) -> bool:
	if x < 2 or y < 2 or x >= g.sim.get_width() - 2 or y >= g.sim.get_height() - 2:
		return false
	return g.sim.get_owner(x, y) == 0 and M.KINDS[M.kind_of(g.sim.get_cell(x, y))] == "static"


## What a click at world point `p` would join, for a tool of `kind`: {a, b, at} (b 0 is the rock,
## `at` the spot) or {why}. Two parts a hand apart are joined half way between; one part and the
## rock beside it are joined at the rock.
static func grab(g, p: Vector2, kind: String) -> Dictionary:
	var by_body := {}
	for id: int in g.modules:
		by_body[g.modules[id]["body"]] = id
	var near := {}
	var rock := Vector2.ZERO
	var rock_d := 1e9
	var r := int(ceil(SNAP_RADIUS))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx := int(floor(p.x)) + dx
			var cy := int(floor(p.y)) + dy
			if cx < 0 or cy < 0 or cx >= g.sim.get_width() or cy >= g.sim.get_height():
				continue
			var cell := Vector2(cx + 0.5, cy + 0.5)
			var d := p.distance_to(cell)
			if d > SNAP_RADIUS:
				continue
			var owner: int = g.sim.get_owner(cx, cy)
			if owner != 0:
				if by_body.has(owner) and (not near.has(by_body[owner]) or d < near[by_body[owner]]["d"]):
					near[by_body[owner]] = {"d": d, "pos": cell}
			elif d < rock_d and is_ground(g, cx, cy):
				rock_d = d
				rock = cell
	var ids: Array = near.keys()
	ids.sort_custom(func(x: int, y: int) -> bool: return near[x]["d"] < near[y]["d"])
	if ids.is_empty():
		return {"why": "Nothing here to join."}
	var a: int = ids[0]
	if ids.size() >= 2 and kind != "piton":
		var b: int = ids[1]
		var pa: Vector2 = near[a]["pos"]
		var pb: Vector2 = near[b]["pos"]
		if pa.distance_to(pb) > GAP:
			return {"why": "Those parts are too far apart for a %s." % KINDS[kind]["name"].to_lower()}
		return {"a": a, "b": b, "at": (pa + pb) * 0.5}
	if rock_d < 1e9:
		if (near[a]["pos"] as Vector2).distance_to(rock) > GAP:
			return {"why": "The rock is too far from that part."}
		return {"a": a, "b": 0, "at": rock}
	return {"why": "A piton needs rock beside the part." if kind == "piton" else "Click where two parts meet, or a part meets the rock."}


## The joint whose anchor is within TAKE_OFF_RADIUS of `p` (record id), or 0.
static func joint_near(g, p: Vector2) -> int:
	var best := TAKE_OFF_RADIUS
	var hit := 0
	for jid: int in g.joints:
		var a: Array = anchors(g, jid)
		if not a.is_empty() and p.distance_to(a[0]) <= best:
			best = p.distance_to(a[0])
			hit = jid
	return hit


static func affordable(g, cost: Array) -> bool:
	for r in cost.size():
		if g.stock[r] < cost[r]:
			return false
	return true


## A left click with a joint tool picked: on a joint it takes it off (and gives back its price),
## otherwise it joins what is there, for the price.
static func click(g, cell: Vector2i) -> void:
	var kind: String = g.joint_pick
	if not unlocked(g, kind):
		g.joint_pick = ""
		return
	var p := Vector2(cell) + Vector2(0.5, 0.5)
	var old := joint_near(g, p)
	if old != 0:
		var ok: String = g.joints[old]["kind"]
		for r in KINDS[ok]["cost"].size():
			g.stock[r] += KINDS[ok]["cost"][r]
		detach(g, old)
		g.show_banner("Took off a %s." % KINDS[ok]["name"].to_lower(), 1.5)
		return
	var gr := grab(g, p, kind)
	if gr.has("why"):
		g.show_banner(gr["why"], 2.0)
		return
	var cost: Array = KINDS[kind]["cost"]
	if not affordable(g, cost):
		g.show_banner("Needs %s in the stockpile." % MU.cost_text(cost), 2.0)
		return
	if attach(g, kind, gr["a"], gr["b"], gr["at"]) == 0:
		g.show_banner("That can't be joined.", 2.0)
		return
	for r in cost.size():
		g.stock[r] -= cost[r]


## Adds the joint tools under the Build list; the research that opens them shows them.
static func add_buttons(hud, vb: VBoxContainer) -> void:
	for kind: String in TOOLS:
		var k: Dictionary = KINDS[kind]
		var b: Button = hud._button("   %s  [%s]" % [k["name"], MU.cost_text(k["cost"])])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = "%s\nClick where two parts meet, or a part meets the rock. Esc cancels." % k["blurb"]
		b.pressed.connect(func() -> void:
			hud.game.cancel_tool()
			hud.game.joint_pick = kind
			hud.game.show_banner("%s: click where two parts meet. Esc cancels." % k["name"], 3.0))
		b.visible = unlocked(hud.game, kind)
		hud.module_buttons.append({"button": b, "def": {"tech": k["tech"]}})
		vb.add_child(b)


# --- Drawing -----------------------------------------------------------------------

## Every joint as a dot at its anchor; with a tool picked, where a click would join and why not.
static func draw(ov, g, z: float) -> void:
	for jid: int in g.joints:
		var a: Array = anchors(g, jid)
		if a.is_empty():
			continue
		var j: Dictionary = g.joints[jid]
		var at: Vector2 = g.to_screen(a[0])
		var col: Color = COLOURS.get(j["kind"], Color.WHITE)
		ov.draw_circle(at, maxf(2.5, 2.2 * z), Color(0, 0, 0, 0.7))
		ov.draw_circle(at, maxf(1.8, 1.6 * z), col)
		if j["kind"] == "motor" and j["mode"] != 0:
			ov.draw_arc(at, maxf(4.0, 4.0 * z), 0.0, TAU * 0.75 * float(j["mode"]), 16, col, 1.5)
	if g.joint_pick != "":
		var gr := grab(g, Vector2(g.hover) + Vector2(0.5, 0.5), g.joint_pick)
		var ok := not gr.has("why")
		var col: Color = ov.OK_COL if ok else ov.BAD_COL
		var at: Vector2 = g.to_screen(gr["at"] if ok else Vector2(g.hover) + Vector2(0.5, 0.5))
		ov.draw_arc(at, maxf(5.0, 5.0 * z), 0.0, TAU, 20, col, 1.5)
		if not ok and ov.font != null:
			ov.draw_string(ov.font, at + Vector2(10.0, 18.0), gr["why"], HORIZONTAL_ALIGNMENT_LEFT, 320.0, 13, Color(1, 1, 1, 0.9))
