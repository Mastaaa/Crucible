extends RefCounted
## The machine framework's registry (A3). A module is a rigid body whose walls are real
## casing cells (casing.gd) with typed faces (faces.gd). The game keeps one Dictionary per
## module in `game.modules` (plain data, so the save takes it as it is) and calls `tick`.
##
## What a module does here: it connects by contact (faces of one type and width touching
## square on, a multiple of 90 degrees apart), opens its two faces while joined and closes
## them when the contact ends; it has an integrity number; a breach spills its contents;
## below Casing.DEAD it drops as wreckage, and so does one the engine broke up. Contents
## are counted units of a material, not cells. What a module is for is each module group's
## own business, hooked in through its definition (test_modules.gd is the shape).
##
## All of it is GDScript on the engine's body calls (set_module, body_info, body_pixels,
## body_set_pixel); the GDScript fallback sim has no bodies, so `check_place` refuses.

const D = preload("res://scripts/defs.gd")
const F = preload("res://scripts/machines/faces.gd")
const CS = preload("res://scripts/machines/casing.gd")
const TM = preload("res://scripts/machines/test_modules.gd")
const MU = preload("res://scripts/machines/mu.gd")
const MD = preload("res://scripts/machines/module_data.gd")
const INT = preload("res://scripts/machines/interior.gd")
# The module groups' behaviour scripts, by the `kind` a definition names. A group adds its own here.
const K_TANK = preload("res://scripts/machines/logistics/tank.gd")
const K_FUNNEL = preload("res://scripts/machines/logistics/funnel.gd")
const K_CUTTER = preload("res://scripts/machines/excavation/cutter.gd")
const K_LASER = preload("res://scripts/machines/excavation/laser.gd")
const K_THUMPER = preload("res://scripts/machines/excavation/thumper.gd")
const K_MACERATOR = preload("res://scripts/machines/processing/macerator.gd")
const K_PRESS = preload("res://scripts/machines/processing/press.gd")
const K_THERMAL = preload("res://scripts/machines/processing/thermal.gd")
const K_CASTER = preload("res://scripts/machines/processing/caster.gd")
const K_SEPARATOR = preload("res://scripts/machines/processing/separator.gd")
const K_PUMP = preload("res://scripts/machines/logistics/pump.gd")
const K_SHORER = preload("res://scripts/machines/support/shorer.gd")
const K_COMBUSTOR = preload("res://scripts/machines/power/combustor.gd")
const K_CHUTE = preload("res://scripts/machines/logistics/chute.gd")
const K_CONVEYOR = preload("res://scripts/machines/logistics/conveyor.gd")
const K_BUS_HOPPER = preload("res://scripts/machines/logistics/bus_hopper.gd")
const K_VAULT = preload("res://scripts/machines/logistics/vault.gd")
const K_DRONE_CAGE = preload("res://scripts/machines/haulers/drone_cage.gd")
const K_WINCH = preload("res://scripts/machines/movers/winch.gd")
const K_SLIDE = preload("res://scripts/machines/movers/slide.gd")
const K_TURNTABLE = preload("res://scripts/machines/movers/turntable.gd")
const K_WINDMILL = preload("res://scripts/machines/power/windmill.gd")
const K_LAB = preload("res://scripts/machines/support/lab.gd")
const K_LAMP = preload("res://scripts/machines/support/lamp.gd")

const SCAN := MU.SCAN           # ticks between scans
const CONNECT_DIST := 3.5       # faces this near (cells) and square on join
const BREAK_DIST := 6.5         # ... and leave when they're this far apart
const SQUARE := -0.99           # facing normals' dot product at most this
const SPILL_SPEED := 30.0
const WRECK_SPILL := 200        # particles a wreck throws at most

static var defs := MU.defs      # id -> definition (shared with the behaviours, which can't preload this file)
static var kinds := {}          # kind -> behaviour script: scan, step, info, draw (see tank.gd)


static func register(def: Dictionary) -> void:
	defs[def["id"]] = def


## The module data files' definitions, then the throwaway test modules, registered once.
static func ensure_defs() -> void:
	if defs.is_empty():
		kinds = {"tank": K_TANK, "funnel": K_FUNNEL, "cutter": K_CUTTER, "winch": K_WINCH, "windmill": K_WINDMILL,
				"lab": K_LAB, "lamp": K_LAMP, "slide": K_SLIDE, "turntable": K_TURNTABLE, "laser": K_LASER, "thumper": K_THUMPER,
				"macerator": K_MACERATOR, "press": K_PRESS, "thermal": K_THERMAL, "caster": K_CASTER, "combustor": K_COMBUSTOR, "separator": K_SEPARATOR, "pump": K_PUMP, "shorer": K_SHORER,
				"chute": K_CHUTE, "conveyor": K_CONVEYOR, "bus_hopper": K_BUS_HOPPER, "vault": K_VAULT,
				"drone_cage": K_DRONE_CAGE}
		for d: Dictionary in MD.defs():
			register(d)
		for d: Dictionary in TM.defs():
			d["test"] = true
			register(d)


static func reset(g) -> void:
	g.modules.clear()
	g.next_module = 1


# --- Placing ---------------------------------------------------------------------

## "" if module `def_id` can be placed with its top left at `at`, turned `turns` quarter
## turns, else why not. The whole footprint has to be open air.
static func check_place(g, def_id: String, at: Vector2i, turns: int) -> String:
	ensure_defs()
	if g.sim.get_script() != null:
		return "Modules need the native engine."
	if not defs.has(def_id):
		return "No such module."
	var lay := F.layout(defs[def_id], turns)
	var size: Vector2i = lay["size"]
	if at.x < 4 or at.y < 4 or at.x + size.x > g.sim.get_width() - 4 or at.y + size.y > g.sim.get_height() - 4:
		return "Out of bounds."
	for y in size.y:
		for x in size.x:
			if g.sim.get_cell(at.x + x, at.y + y) != 0:
				return "Not enough room."
	return ""


## Places a module and returns its id, or 0 if it can't be (check_place says why).
static func place(g, def_id: String, at: Vector2i, turns: int) -> int:
	if check_place(g, def_id, at, turns) != "":
		return 0
	var def: Dictionary = defs[def_id]
	var lay := F.layout(def, turns)
	var size: Vector2i = lay["size"]
	var cells: PackedByteArray = lay["cells"]
	for y in size.y:
		for x in size.x:
			if cells[y * size.x + x] == F.CASING:
				g.sim.set_cell(at.x + x, at.y + y, CS.MATERIAL)
	var body: int = g.sim.make_body(at.x, at.y, size.x, size.y, 0.0, 0.0, 0.0)
	if body <= 0:
		_clear_footprint(g, at, size, cells)
		return 0
	g.sim.set_module(body, true)
	var fl: Array = []
	for _f in lay["faces"]:
		fl.append({"open": false, "link_m": 0, "link_f": -1})
	var id: int = g.next_module
	g.next_module += 1
	g.modules[id] = {
		"id": id, "def": def_id, "turns": posmod(turns, 4), "body": body,
		"designed": lay["designed"], "opened": 0, "count": lay["designed"], "dirty": true,
		"integrity": 1.0, "breach": Vector2i(-1, -1), "faces": fl, "contents": {},
		"at": Vector2(at) + Vector2(size) * 0.5, "sim": null, "box": Rect2i(),
	}
	INT.ensure(g.modules[id], def)
	if not g.firsts.has(def_id):
		g.firsts[def_id] = true
		g.mark("First %s built" % def["name"], false)
	_attach(g, id)
	return id


# A module just placed joins the free faces it touches at once, instead of at the next scan, so a
# load put against a mover is already hooked when the mover's own scan comes round.
static func _attach(g, id: int) -> void:
	var m: Dictionary = g.modules[id]
	var fr := _frame(g, m)
	for oid: int in g.modules:
		if oid != id:
			_try_pair(g, m, fr, g.modules[oid], _frame(g, g.modules[oid]))


static func _clear_footprint(g, at: Vector2i, size: Vector2i, cells: PackedByteArray) -> void:
	for y in size.y:
		for x in size.x:
			if cells[y * size.x + x] == F.CASING and g.sim.get_cell(at.x + x, at.y + y) == CS.MATERIAL:
				g.sim.set_cell(at.x + x, at.y + y, 0)


## Takes a module down: its body goes, its contents are lost, its partners close up.
static func remove(g, id: int) -> void:
	var m: Dictionary = g.modules.get(id, {})
	if m.is_empty():
		return
	_unlink_all(g, m, false)
	g.sim.remove_body(m["body"])
	g.modules.erase(id)


# --- Contents --------------------------------------------------------------------

static func capacity(m: Dictionary) -> int:
	return MU.capacity(m, defs[m["def"]])


static func stored(m: Dictionary) -> int:
	return MU.stored(m)


## Puts up to n units of material `mat` in module `id`; returns how many fit.
static func add_contents(g, id: int, mat: int, n: int) -> int:
	var m: Dictionary = g.modules.get(id, {})
	if m.is_empty():
		return 0
	return MU.add(m, defs[m["def"]], mat, n)


# --- The tick --------------------------------------------------------------------

static func tick(g) -> void:
	if g.modules.is_empty():
		return
	ensure_defs()
	_motion(g)
	if g.ticks % SCAN != 0:
		return
	var live := {}
	var bl: PackedInt32Array = g.sim.get_bodies()
	for k in range(0, bl.size(), 7):
		live[bl[k]] = k
	var frames := {}
	for id: int in g.modules.keys():
		var m: Dictionary = g.modules[id]
		if not live.has(m["body"]):
			_lost(g, m)
			continue
		var k: int = live[m["body"]]
		m["at"] = Vector2(bl[k + 1] + bl[k + 3], bl[k + 2] + bl[k + 4]) * 0.5
		if bl[k + 6] != m["count"] or m["dirty"]:
			m["count"] = bl[k + 6]
			m["dirty"] = false
			_assess(g, m)
			if m["integrity"] < CS.DEAD:
				_wreck(g, m)
				continue
		frames[id] = _frame(g, m)
		if m["breach"].x >= 0:
			_spill(g, m, frames[id])
	_connections(g, frames)
	for id: int in g.modules.keys():
		_pass(g, g.modules[id])
	for id: int in g.modules.keys():
		var m: Dictionary = g.modules[id]
		if m.get("rig_of", 0) != 0 and not g.modules.has(m["rig_of"]):
			m["rig_of"] = 0          # its Winch is gone
			m["powered"] = false
		var kind: Variant = kinds.get(defs[m["def"]].get("kind", ""))
		if kind != null:
			kind.scan(g, m, defs[m["def"]])
		INT.ensure(m, defs[m["def"]])
		INT.sync(m)
		CS.wear(g, m, defs[m["def"]])


# Every tick: bolted-down modules hold still, and each behaviour moves what it moves.
static func _motion(g) -> void:
	for id: int in g.modules:
		g.modules[id].erase("dv")
		g.modules[id].erase("dspin")
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		var def: Dictionary = defs[m["def"]]
		var kind: Variant = kinds.get(def.get("kind", ""))
		if kind != null:
			kind.step(g, m, def)
		INT.step(m)
	# What the movers added up (MU.drive) goes to the engine once.
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		if defs[m["def"]].get("anchored", false):
			g.sim.drive_body(m["body"], 0.0, 0.0, m.get("dspin", 0.0))
		elif m.has("dv"):
			g.sim.drive_body(m["body"], m["dv"].x, m["dv"].y, m["dspin"])


# What the module's body looks like now: pose, centre of mass, layout.
static func _frame(g, m: Dictionary) -> Dictionary:
	return MU.frame(g, m, defs[m["def"]])


# A local pixel's place in the world.
static func _world(fr: Dictionary, local: Vector2) -> Vector2:
	return MU.world(fr, local)


static func _turn(fr: Dictionary, d: Vector2) -> Vector2:
	return MU.turn(fr, d)


# Integrity and breach from the body's bitmap.
static func _assess(g, m: Dictionary) -> void:
	m["integrity"] = CS.integrity(m, m["count"])
	var pixels: PackedByteArray = g.sim.body_pixels(m["body"])
	if pixels.is_empty():
		return
	m["breach"] = CS.breach_at(m, F.layout(defs[m["def"]], m["turns"]), pixels)


static func _spill(g, m: Dictionary, fr: Dictionary) -> void:
	var at := _world(fr, Vector2(m["breach"]) + Vector2(0.5, 0.5))
	var out := (at - Vector2(fr["st"][0], fr["st"][1])).normalized()
	for _i in CS.leak(m["integrity"]):
		var mat := _most(m)
		if mat < 0:
			return
		MU.take(m, mat, 1)
		var v := out * SPILL_SPEED + Vector2(g.rng.randf_range(-10.0, 10.0), g.rng.randf_range(-10.0, 10.0))
		g.sim.add_particle(at.x, at.y, v.x, v.y, mat)


static func _most(m: Dictionary) -> int:
	var best := -1
	var n := 0
	for k: int in m["contents"]:
		if m["contents"][k] > n:
			best = k
			n = m["contents"][k]
	return best


# A dead module: everything inside goes, ports close, and the body carries on as
# ordinary rigid wreckage (the engine settles it into ground or breaks it up).
static func _wreck(g, m: Dictionary) -> void:
	_dump(g, m)
	_unlink_all(g, m, false)
	g.sim.set_module(m["body"], false)
	g.modules.erase(m["id"])
	g.alert("module", "%s wrecked." % defs[m["def"]]["name"], m["at"])


# The engine lost the body (it shattered, or settled into ground).
static func _lost(g, m: Dictionary) -> void:
	_dump(g, m)
	_unlink_all(g, m, false)
	g.modules.erase(m["id"])
	g.alert("module", "%s lost." % defs[m["def"]]["name"], m["at"])


static func _dump(g, m: Dictionary) -> void:
	var at: Vector2 = m["at"]
	var n := 0
	for mat: int in m["contents"]:
		for _i in m["contents"][mat]:
			if n >= WRECK_SPILL:
				break
			n += 1
			g.sim.add_particle(at.x + g.rng.randf_range(-4.0, 4.0), at.y + g.rng.randf_range(-4.0, 4.0),
					g.rng.randf_range(-SPILL_SPEED, SPILL_SPEED), g.rng.randf_range(-SPILL_SPEED, 0.0), mat)
	m["contents"].clear()


# --- Connecting ------------------------------------------------------------------

static func _face_world(fr: Dictionary, fi: int) -> Dictionary:
	var f: Dictionary = fr["lay"]["faces"][fi]
	return {"p": _world(fr, f["centre"]), "n": _turn(fr, Vector2(f["dir"]))}


static func _connections(g, frames: Dictionary) -> void:
	# Joined faces that have drifted apart or turned away close again.
	for id: int in frames:
		var m: Dictionary = g.modules[id]
		for fi in m["faces"].size():
			var fs: Dictionary = m["faces"][fi]
			if fs["link_m"] == 0 or id > fs["link_m"]:
				continue
			var other: Dictionary = g.modules.get(fs["link_m"], {})
			if other.is_empty() or not frames.has(fs["link_m"]):
				_leave(g, m, fi)
				continue
			if defs[m["def"]].get("tether", false) or defs[other["def"]].get("tether", false):
				continue            # a cable stays hooked however far the rig goes
			var a := _face_world(frames[id], fi)
			var b := _face_world(frames[fs["link_m"]], fs["link_f"])
			if a["p"].distance_to(b["p"]) > BREAK_DIST or a["n"].dot(b["n"]) > SQUARE:
				_leave(g, m, fi)
	# Free faces that touch join.
	var ids: Array = frames.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			_try_pair(g, g.modules[ids[i]], frames[ids[i]], g.modules[ids[j]], frames[ids[j]])


static func _try_pair(g, ma: Dictionary, fa: Dictionary, mb: Dictionary, fb: Dictionary) -> void:
	if ma["at"].distance_to(mb["at"]) > 120.0:
		return
	var la: Array = fa["lay"]["faces"]
	var lb: Array = fb["lay"]["faces"]
	for i in la.size():
		if ma["faces"][i]["link_m"] != 0:
			continue
		var wa := _face_world(fa, i)
		for j in lb.size():
			if mb["faces"][j]["link_m"] != 0:
				continue
			if not F.compatible(la[i]["type"], la[i]["w"], lb[j]["type"], lb[j]["w"]):
				continue
			var wb := _face_world(fb, j)
			if wa["p"].distance_to(wb["p"]) <= CONNECT_DIST and wa["n"].dot(wb["n"]) <= SQUARE:
				_join(g, ma, i, mb, j)
				break


static func _join(g, ma: Dictionary, i: int, mb: Dictionary, j: int) -> void:
	ma["faces"][i]["link_m"] = mb["id"]
	ma["faces"][i]["link_f"] = j
	mb["faces"][j]["link_m"] = ma["id"]
	mb["faces"][j]["link_f"] = i
	if defs[ma["def"]].get("tether", false) or defs[mb["def"]].get("tether", false):
		return              # a cable's hook stays shut: nothing passes through it, and sand would
	_set_open(g, ma, i, true)
	_set_open(g, mb, j, true)


# Opens or closes a face: its wall pixels leave the body or come back.
static func _set_open(g, m: Dictionary, fi: int, open: bool) -> void:
	var fs: Dictionary = m["faces"][fi]
	if fs["open"] == open:
		return
	fs["open"] = open
	var cells: Array = F.layout(defs[m["def"]], m["turns"])["faces"][fi]["cells"]
	for c: Vector2i in cells:
		g.sim.body_set_pixel(m["body"], c.x, c.y, 0 if open else CS.MATERIAL)
	m["opened"] += cells.size() if open else -cells.size()
	m["dirty"] = true


# Closes face `fi` of m and the face it was joined to.
static func _leave(g, m: Dictionary, fi: int) -> void:
	var fs: Dictionary = m["faces"][fi]
	var other: Dictionary = g.modules.get(fs["link_m"], {})
	if not other.is_empty():
		other["faces"][fs["link_f"]]["link_m"] = 0
		other["faces"][fs["link_f"]]["link_f"] = -1
		_set_open(g, other, fs["link_f"], false)
	fs["link_m"] = 0
	fs["link_f"] = -1
	_set_open(g, m, fi, false)


# Every face of m closes (and its partners'). With `restore`, m's own pixels come back.
static func _unlink_all(g, m: Dictionary, restore: bool) -> void:
	for fi in m["faces"].size():
		var fs: Dictionary = m["faces"][fi]
		if fs["link_m"] == 0:
			continue
		var other: Dictionary = g.modules.get(fs["link_m"], {})
		if not other.is_empty():
			other["faces"][fs["link_f"]]["link_m"] = 0
			other["faces"][fs["link_f"]]["link_f"] = -1
			_set_open(g, other, fs["link_f"], false)
		fs["link_m"] = 0
		fs["link_f"] = -1
		if restore:
			_set_open(g, m, fi, false)
		else:
			fs["open"] = false


# A module's `pass` rule (or rules, as a list): contents move out of the rule's face into what is
# joined there. A rule may filter what goes (MU.passes) and charge `power` a cell moved.
static func _pass(g, m: Dictionary) -> void:
	var rules: Variant = defs[m["def"]].get("pass", {})
	if rules is Dictionary:
		rules = [rules] if not rules.is_empty() else []
	for rule: Dictionary in rules:
		_pass_rule(g, m, rule)


static func _pass_rule(g, m: Dictionary, rule: Dictionary) -> void:
	var fs: Dictionary = m["faces"][rule["face"]]
	if fs["link_m"] == 0:
		return
	var power := float(rule.get("power", 0.0))
	if power > 0.0 and not MU.networked(g, m, defs[m["def"]]):
		return
	var left: int = rule["rate"]
	var held: Dictionary = m["contents"].duplicate()
	for mat: int in held:
		if not MU.passes(rule, mat, held):
			continue
		var want := mini(left, m["contents"].get(mat, 0))
		if want <= 0:
			continue
		if power > 0.0:
			while want > 0 and not MU.take_power(g, power * want):
				want = want >> 1
			if want <= 0:
				return
		# Take first: a reaction inside may have used cells since the last count.
		var got := MU.take(m, mat, want)
		var moved := add_contents(g, fs["link_m"], mat, got)
		if moved < got:
			MU.add(m, defs[m["def"]], mat, got - moved)
		left -= moved
		m["passed"] = m.get("passed", 0) + moved
		if left <= 0:
			break


# --- Damage (for tests, and later for heat and corrosion) -------------------------

## Knocks the given local pixels out of module `id`'s casing.
static func knock_out(g, id: int, pixels: Array) -> void:
	var m: Dictionary = g.modules.get(id, {})
	if m.is_empty():
		return
	for c: Vector2i in pixels:
		g.sim.body_set_pixel(m["body"], c.x, c.y, 0)
	m["dirty"] = true


# --- Build list and input ---------------------------------------------------------

const SNAP_DIST := 12.0         # a face this near (cells) to a free matching one snaps to it
const COST_NAMES := ["Stone", "Glimmer", "Obsidian", "Water", "Power"]


## "6 Stone, 2 Glimmer" for a cost array.
static func cost_text(cost: Array) -> String:
	var parts: Array = []
	for r in cost.size():
		if cost[r] > 0:
			parts.append("%d %s" % [cost[r], COST_NAMES[r]])
	return ", ".join(parts) if not parts.is_empty() else "free"


static func affordable(g, def: Dictionary) -> bool:
	var cost: Array = def.get("cost", [])
	for r in cost.size():
		if g.stock[r] < cost[r]:
			return false
	return true


## Adds a button per registered module under the HUD's Build list (the catalogue first,
## the framework's test modules after).
static func add_build_buttons(hud, vb: VBoxContainer) -> void:
	ensure_defs()
	for pass_test in [false, true]:
		for id: String in defs:
			var def: Dictionary = defs[id]
			if def.get("test", false) != pass_test:
				continue
			var label := "   %s (module)" % def["name"] if pass_test else "   %s  [%s]" % [def["name"], cost_text(def.get("cost", []))]
			var b: Button = hud._button(label)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 13)
			b.tooltip_text = "%s\nR turns it before placing, Esc cancels. It snaps onto a free matching face nearby." \
					% def.get("blurb", "A framework test module.")
			b.pressed.connect(func() -> void:
				hud.game.cancel_tool()
				hud.game.module_pick = id
				hud.game.show_banner("%s: click to place, R turns it, Esc cancels." % defs[id]["name"], 3.0))
			b.visible = pass_test or unlocked(hud.game, def)
			hud.module_buttons.append({"button": b, "def": def})
			vb.add_child(b)


## Shows a module's Build button once its tech is researched.
static func refresh_buttons(hud) -> void:
	for e: Dictionary in hud.module_buttons:
		var open: bool = e["def"].get("test", false) or unlocked(hud.game, e["def"])
		if e["button"].visible != open:
			e["button"].visible = open


## Where a module picked for placement goes with the cursor on `cell`: its top left, and
## whether it snapped onto a free face (its own face meeting a matching one of a placed
## module, within SNAP_DIST).
static func snap(g, def_id: String, turns: int, cell: Vector2i) -> Dictionary:
	var def: Dictionary = defs[def_id]
	var lay := F.layout(def, turns)
	var size: Vector2i = lay["size"]
	var at := cell - Vector2i(size.x >> 1, size.y >> 1)
	var best := SNAP_DIST
	var delta := Vector2.ZERO
	var hit := false
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		var fr := _frame(g, m)
		for j in m["faces"].size():
			if m["faces"][j]["link_m"] != 0:
				continue
			var wb := _face_world(fr, j)
			var fb: Dictionary = fr["lay"]["faces"][j]
			for f: Dictionary in lay["faces"]:
				if not F.compatible(f["type"], f["w"], fb["type"], fb["w"]):
					continue
				if Vector2(f["dir"]).dot(wb["n"]) > SQUARE:
					continue
				# Walls touch: the two faces sit half a wall of each apart.
				var gap := (float(def["wall"]) + float(defs[m["def"]]["wall"])) * 0.5
				var goal: Vector2 = wb["p"] + wb["n"] * gap
				var mine: Vector2 = Vector2(at) + f["centre"]
				var d: float = mine.distance_to(goal)
				if d < best:
					best = d
					delta = goal - mine
					hit = true
	if hit:
		var moved := at + Vector2i(roundi(delta.x), roundi(delta.y))
		if check_place(g, def_id, moved, turns) == "":
			return {"at": moved, "snapped": true}
	return {"at": at, "snapped": false}


## A left click while a module is picked places it centred on `cell`. True if handled.
static func click(g, cell: Vector2i) -> bool:
	if g.module_pick == "":
		return use(g, cell)
	var def: Dictionary = defs[g.module_pick]
	if not unlocked(g, def):
		g.module_pick = ""
		return true
	var at: Vector2i = snap(g, g.module_pick, g.module_turns, cell)["at"]
	var why := check_place(g, g.module_pick, at, g.module_turns)
	if why == "" and not affordable(g, def):
		why = "Needs %s in the stockpile." % cost_text(def.get("cost", []))
	if why != "":
		g.show_banner(why, 2.0)
	elif place(g, g.module_pick, at, g.module_turns) > 0:
		var cost: Array = def.get("cost", [])
		for r in cost.size():
			g.stock[r] -= cost[r]
	return true


## A click on a placed module whose behaviour takes clicks (`use`: a Piston's or Gantry's mode)
## hands it over, when no tool or placing is active. True if one took it.
static func use(g, cell: Vector2i) -> bool:
	if g.tool_type >= 0 or g.brush_mode:
		return false
	var m := module_at(g, cell)
	if m.is_empty():
		return false
	var def: Dictionary = defs[m["def"]]
	var kind: Variant = kinds.get(def.get("kind", ""))
	if kind == null or not kind.has_method("use"):
		return false
	kind.use(g, m, def)
	return true


## R turns the picked module, Esc drops it. True if handled.
static func key(g, k: int) -> bool:
	if g.module_pick == "":
		return false
	if k == KEY_R:
		g.module_turns = posmod(g.module_turns + 1, 4)
		return true
	if k == KEY_ESCAPE:
		g.module_pick = ""
		return true
	return false


# --- What the game asks of the modules ----------------------------------------------

## Whether the Build list offers module `def` and it can be placed: it names a tech, or
## doesn't need one.
static func unlocked(g, def: Dictionary) -> bool:
	return not def.has("tech") or g.researched.has(def["tech"])


## The axis-aligned bounds of module `m`.
static func bounds(m: Dictionary) -> Rect2i:
	return MU.bounds(m, defs[m["def"]])


## The module whose bottom edge is deepest ({} with none).
static func deepest_module(g) -> Dictionary:
	var best := {}
	var best_y := -1
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		var y := bounds(m).end.y
		if y > best_y:
			best_y = y
			best = m
	return best


## How deep the modules have got (the bottom edge of the deepest), 0 with none.
static func deepest(g) -> int:
	var m := deepest_module(g)
	return 0 if m.is_empty() else bounds(m).end.y


## Where the first module of `kind` is, else `fallback`.
static func first_at(g, kind: String, fallback: Vector2) -> Vector2:
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		if defs[m["def"]].get("kind", "") == kind:
			return m["at"]
	return fallback


## Modules built so far under `name` (a definition's name, "Lab"); `built` ones only matter for
## the goal layer's "built" check.
static func count_named(g, name: String) -> int:
	var n := 0
	for id: int in g.modules:
		if defs[g.modules[id]["def"]]["name"] == name:
			n += 1
	return n


## Light and sight the modules give, as [position, light radius, sight radius]: every module
## carries a pilot light (enough to see it work), and a running Lamp lights its whole pool.
static func lights(g) -> Array:
	var out: Array = []
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		if defs[m["def"]].get("kind", "") == "lamp" and m.get("lit", false):
			out.append([m["at"], D.LIGHT_LAMP, D.LIGHT_LAMP])
		else:
			out.append([m["at"], D.LIGHT_PILOT, D.SIGHT_MACHINE])
	return out


## Where modules that feel hidden pockets (the Cutter) are.
static func sensing(g) -> Array:
	var out: Array = []
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		if defs[m["def"]].get("sense", false):
			out.append(m["at"])
	return out


# --- Overlay and readings -----------------------------------------------------------

## The module whose body owns world cell `c`, or {}.
static func module_at(g, c: Vector2i) -> Dictionary:
	if g.modules.is_empty() or c.x < 0 or c.y < 0 or c.x >= g.sim.get_width() or c.y >= g.sim.get_height():
		return {}
	var body: int = g.sim.get_owner(c.x, c.y)
	if body == 0:
		return {}
	for id: int in g.modules:
		if g.modules[id]["body"] == body:
			return g.modules[id]
	return {}


## What the module's behaviour has to say about it ("" if nothing).
static func info(g, m: Dictionary) -> String:
	var def: Dictionary = defs[m["def"]]
	var kind: Variant = kinds.get(def.get("kind", ""))
	var s := "%s (%d%%)" % [def["name"], roundi(float(m["integrity"]) * 100.0)]
	if kind != null:
		s += "\n" + kind.info(g, m, def)
	return s


## Power a second the modules are making now (the Hub's figure adds it).
static func generating(g) -> float:
	var n := 0.0
	for id: int in g.modules:
		n += float(g.modules[id].get("flow", 0.0))
	return n


## The overlay's hook: each behaviour's drawing, the placement ghost, and a readout over
## the module under the cursor.
static func draw(ov, g, z: float) -> void:
	if g.modules.is_empty() and g.module_pick == "":
		return
	ensure_defs()
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		var def: Dictionary = defs[m["def"]]
		var kind: Variant = kinds.get(def.get("kind", ""))
		if kind != null:
			kind.draw(ov, g, m, def, z)
	if g.module_pick != "":
		var sn := snap(g, g.module_pick, g.module_turns, g.hover)
		var size: Vector2i = F.layout(defs[g.module_pick], g.module_turns)["size"]
		var at: Vector2i = sn["at"]
		var why := check_place(g, g.module_pick, at, g.module_turns)
		var col: Color = ov.OK_COL if why == "" else ov.BAD_COL
		var a: Vector2 = g.to_screen(Vector2(at))
		var b: Vector2 = g.to_screen(Vector2(at + size))
		ov.draw_rect(Rect2(a, b - a), Color(col, 0.18))
		ov.draw_rect(Rect2(a, b - a), col, false, 2.0 if sn["snapped"] else 1.0)
	elif g.tool_type < 0 and not g.brush_mode:
		var m := module_at(g, g.hover)
		if not m.is_empty() and ov.font != null:
			var lines := info(g, m).split("\n")
			var pos: Vector2 = g.to_screen(Vector2(g.hover)) + Vector2(14.0, 14.0)
			var y := 0.0
			for line: String in lines:
				ov.draw_string(ov.font, pos + Vector2(1, y + 1), line, HORIZONTAL_ALIGNMENT_LEFT, 360.0, 13, Color(0, 0, 0, 0.8))
				ov.draw_string(ov.font, pos + Vector2(0, y), line, HORIZONTAL_ALIGNMENT_LEFT, 360.0, 13, Color(1, 1, 1, 0.95))
				y += 16.0
