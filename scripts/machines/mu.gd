extends RefCounted
## Helpers the machine registry (machines.gd) and every module group's behaviour script
## share: a module's pose in the world, its contents, the network it draws power from.
## Nothing here preloads machines.gd, so a behaviour script can use it without a cycle.

const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const F = preload("res://scripts/machines/faces.gd")

const SCAN := 6                 # ticks between scans (machines.gd runs the kinds' `scan` this often)
const SCAN_DT := SCAN * D.DT

## Every registered definition (id -> definition); machines.gd fills it.
static var defs := {}

const FRONT_DIRS := {"up": F.UP, "down": F.DOWN, "left": F.LEFT, "right": F.RIGHT}


# --- Pose ------------------------------------------------------------------------

## What module `m` (of definition `def`) looks like now: pose, centre of mass, layout.
static func frame(g, m: Dictionary, def: Dictionary) -> Dictionary:
	return {"st": g.sim.body_state(m["body"]), "info": g.sim.body_info(m["body"]),
			"lay": F.layout(def, m["turns"])}


## A local pixel's place in the world.
static func world(fr: Dictionary, local: Vector2) -> Vector2:
	var st: PackedFloat32Array = fr["st"]
	var info: PackedFloat32Array = fr["info"]
	var c := local - Vector2(info[2], info[3])
	var cs := cos(st[2])
	var sn := sin(st[2])
	return Vector2(st[0] + cs * c.x - sn * c.y, st[1] + sn * c.x + cs * c.y)


## A direction in the module's frame, turned into the world's.
static func turn(fr: Dictionary, d: Vector2) -> Vector2:
	var a: float = fr["st"][2]
	return Vector2(cos(a) * d.x - sin(a) * d.y, sin(a) * d.x + cos(a) * d.y)


## Where `def["front"]` points once the module is placed with `turns` quarter turns.
static func front(def: Dictionary, turns: int) -> Vector2i:
	var d: Vector2i = FRONT_DIRS[def.get("front", "down")]
	for _i in posmod(turns, 4):
		d = Vector2i(-d.y, d.x)
	return d


## The world's nearest axis for a direction: (0, 1) for anything mostly down, and so on.
static func axis(d: Vector2) -> Vector2i:
	if absf(d.y) >= absf(d.x):
		return Vector2i(0, 1 if d.y >= 0.0 else -1)
	return Vector2i(1 if d.x >= 0.0 else -1, 0)


## The index of the face called `name` in `def`, or -1.
static func face_index(def: Dictionary, name: String) -> int:
	var fl: Array = def["faces"]
	for i in fl.size():
		if fl[i].get("name", "") == name:
			return i
	return -1


## The module joined at `m`'s face called `name` (its dictionary), or {}.
static func partner(g, m: Dictionary, def: Dictionary, name: String) -> Dictionary:
	var i := face_index(def, name)
	if i < 0 or i >= m["faces"].size():
		return {}
	return g.modules.get(m["faces"][i]["link_m"], {})


## Axis-aligned bounds of the module's body, from its centre and (turned) size.
static func bounds(m: Dictionary, def: Dictionary) -> Rect2i:
	var size: Vector2i = F.layout(def, m["turns"])["size"]
	var c: Vector2 = m["at"]
	return Rect2i(int(round(c.x - size.x * 0.5)), int(round(c.y - size.y * 0.5)), size.x, size.y)


# --- Rigs and drives ---------------------------------------------------------------

## Ids of the modules a mover carries: `start` (the one it is tethered to) and whatever is
## joined to it, walking through links but not back through `stop` (the mover itself) or
## through bolted-down modules.
static func rig(g, start: int, stop: int) -> Array:
	var out: Array = []
	if start == 0 or not g.modules.has(start):
		return out
	var queue: Array = [start]
	var seen := {start: true, stop: true}
	while not queue.is_empty():
		var id: int = queue.pop_back()
		out.append(id)
		var mm: Dictionary = g.modules[id]
		for f: Dictionary in mm["faces"]:
			var o: int = f["link_m"]
			if o == 0 or seen.has(o) or not g.modules.has(o):
				continue
			seen[o] = true
			if defs[g.modules[o]["def"]].get("anchored", false):
				continue
			queue.append(o)
	return out


## Adds a velocity (cells a tick) and a turn (radians a tick) to what module `m` is driven at this
## tick. Movers call it from `step`; machines.gd hands the sums to the engine once every mover has
## run, so a Piston on a Gantry carries its load along the rail and out along its own stroke at
## once. A module nobody drives falls like any body.
static func drive(m: Dictionary, v: Vector2, spin := 0.0) -> void:
	m["dv"] = m.get("dv", Vector2.ZERO) + v
	m["dspin"] = m.get("dspin", 0.0) + spin


# --- Contents --------------------------------------------------------------------

## Units the module holds at most: the cavity, or what its behaviour set as `cap`.
static func capacity(m: Dictionary, def: Dictionary) -> int:
	if m.has("cap"):
		return m["cap"]
	if def.get("params", {}).has("cap"):
		return int(def["params"]["cap"])      # a vessel's box is its size from the first scan
	return F.layout(def, m["turns"])["cavity"]


static func stored(m: Dictionary) -> int:
	var n := 0
	for k in m["contents"]:
		n += m["contents"][k]
	return n


## Puts up to n units of material `mat` in `m`; returns how many fit. A module with an
## interior (interior.gd) takes them as cells in its own sim; otherwise it is a count.
static func add(m: Dictionary, def: Dictionary, mat: int, n: int) -> int:
	if def.has("accepts") and not accepts(def["accepts"], mat):
		return 0
	var put := clampi(capacity(m, def) - stored(m), 0, n)
	if put > 0 and m.get("sim") != null:
		var b: Rect2i = m["box"]
		if M.kind_of(mat) == M.K_STATIC:
			put = _lay(m["sim"], b, mat, put)
		else:
			put = m["sim"].put_cells(b.position.x, b.position.y, b.size.x, b.size.y, mat, put)
	if put > 0:
		m["contents"][mat] = m["contents"].get(mat, 0) + put
	return put


## Sets up to n cells of a solid in the box of an interior, from the floor up and out from the
## middle of each row (powder and liquid fall to the floor on their own, a solid does not).
static func _lay(sim: RefCounted, b: Rect2i, mat: int, n: int) -> int:
	var put := 0
	for y in range(b.end.y - 1, b.position.y - 1, -1):
		for k in b.size.x:
			if put >= n:
				return put
			var x := b.position.x + (b.size.x >> 1) + (-((k + 1) >> 1) if (k & 1) else (k >> 1))
			if x < b.position.x or x >= b.end.x or sim.get_cell(x, y) != D.AIR:
				continue
			sim.set_cell(x, y, mat)
			put += 1
	return put


## Whether a module's `pass` rule lets material `mat` out: `mats` names the ones it moves, `kinds`
## the states of matter ("gas", "liquid", "powder", "static"), `heavy` only the densest material
## the module holds and `light` only the lightest (`held` is its contents; with only one material
## left, only `heavy` takes it); with none of them, everything goes.
static func passes(rule: Dictionary, mat: int, held: Dictionary = {}) -> bool:
	if rule.has("mats"):
		return M.name_of(mat) in rule["mats"]
	if rule.has("kinds"):
		return M.KINDS[M.kind_of(mat)] in rule["kinds"]
	if rule.get("heavy", false) or rule.get("light", false):
		if held.size() < 2:
			return rule.get("heavy", false)          # one material left: nothing to sort, it goes out the heavy way
		var want := M.density_of(mat)
		for other: int in held:
			if rule.get("heavy", false) and M.density_of(other) > want:
				return false
			if rule.get("light", false) and M.density_of(other) < want:
				return false
	return true


## Whether a definition's `accepts` rule (the filters of `passes`, and `pressable`: a Press could squeeze it)
## lets material `mat` in. What it refuses stays in whatever was passing it on.
static func accepts(rule: Dictionary, mat: int) -> bool:
	if rule.get("pressable", false) and M.pressed_of(mat) < 0:
		return false
	return passes(rule, mat)


## Takes up to n units of `mat` out of `m` (the topmost cells of its interior, when it has
## one); returns how many came out.
static func take(m: Dictionary, mat: int, n: int) -> int:
	var have: int = m["contents"].get(mat, 0)
	var k := mini(n, have)
	if k <= 0:
		return 0
	if m.get("sim") != null:
		var b: Rect2i = m["box"]
		k = m["sim"].take_cells(b.position.x, b.position.y, b.size.x, b.size.y, mat, k)
	if have - k <= 0:
		m["contents"].erase(mat)
	else:
		m["contents"][mat] = have - k
	return k


# --- The network -----------------------------------------------------------------

## Whether `m` is in reach of a connected Node or the Hub, the way a machine is.
static func networked(g, m: Dictionary, def: Dictionary) -> bool:
	return g.find_link(-1, bounds(m, def), null) != null


## Mk upgrades (A5): every level of Throughput speeds each module's moves by MK_RATE, and
## every level of Efficiency takes MK_POWER off what a module costs in power.
const MK_RATE := 0.5
const MK_POWER := 0.1


## `base` moves a scan, as the Throughput upgrade has it.
static func rate(g, base: int) -> int:
	return roundi(float(base) * (1.0 + MK_RATE * float(g.level("throughput"))))


## Takes `amount` power from the Hub's stock if it's all there (less with Efficiency).
static func take_power(g, amount: float) -> bool:
	amount *= 1.0 - MK_POWER * float(g.level("efficiency"))
	if g.stock[D.R_POWER] < amount:
		return false
	g.stock[D.R_POWER] -= amount
	g.used_acc += amount
	return true
