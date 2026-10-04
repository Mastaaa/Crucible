extends RefCounted
## Helpers the machine registry (machines.gd) and every module group's behaviour script
## share: a module's pose in the world, its contents, the network it draws power from.
## Nothing here preloads machines.gd, so a behaviour script can use it without a cycle.

const D = preload("res://scripts/defs.gd")
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


# --- Contents --------------------------------------------------------------------

## Units the module holds at most: the cavity, or what its behaviour set as `cap`.
static func capacity(m: Dictionary, def: Dictionary) -> int:
	if m.has("cap"):
		return m["cap"]
	return F.layout(def, m["turns"])["cavity"]


static func stored(m: Dictionary) -> int:
	var n := 0
	for k in m["contents"]:
		n += m["contents"][k]
	return n


## Puts up to n units of material `mat` in `m`; returns how many fit.
static func add(m: Dictionary, def: Dictionary, mat: int, n: int) -> int:
	var put := clampi(capacity(m, def) - stored(m), 0, n)
	if put > 0:
		m["contents"][mat] = m["contents"].get(mat, 0) + put
	return put


# --- The network -----------------------------------------------------------------

## Whether `m` is in reach of a connected Node or the Hub, the way a machine is.
static func networked(g, m: Dictionary, def: Dictionary) -> bool:
	return g.find_link(-1, bounds(m, def), null) != null


## Takes `amount` power from the Hub's stock if it's all there.
static func take_power(g, amount: float) -> bool:
	if g.stock[D.R_POWER] < amount:
		return false
	g.stock[D.R_POWER] -= amount
	g.used_acc += amount
	return true
