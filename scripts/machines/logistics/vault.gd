extends RefCounted
## Vault cell (A5): a bolted storage cell that joins its neighbours by contact (a power face on every
## side) into a cluster, the way EnderIO's capacitors form a bank. A cluster that has a Node or the
## Hub in reach adds to the Hub's stores: each cell raises the power cap and the goods cap. Lose a cell
## and its share of the cap goes with it, along with whatever no longer fits (game.gd `_trim_to_caps`).

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")

## The caps the live cells add: {power, goods}.
static func caps(g) -> Dictionary:
	var power := 0.0
	var goods := 0.0
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		var def: Dictionary = MU.defs.get(m["def"], {})
		if def.get("kind", "") != "vault" or not m.get("live", false):
			continue
		power += float(def["params"]["power"])
		goods += float(def["params"]["goods"])
	return {"power": power, "goods": goods}


## Ids of the cells joined to `m` (itself included), walking through links between vault cells.
static func cluster(g, m: Dictionary) -> Array:
	var out: Array = [m["id"]]
	var queue: Array = [m["id"]]
	while not queue.is_empty():
		var cur: Dictionary = g.modules[queue.pop_back()]
		for f: Dictionary in cur["faces"]:
			var o: int = f["link_m"]
			if o == 0 or out.has(o) or not g.modules.has(o):
				continue
			if MU.defs[g.modules[o]["def"]].get("kind", "") != "vault":
				continue
			out.append(o)
			queue.append(o)
	return out


static func scan(g, m: Dictionary, _def: Dictionary) -> void:
	var ids := cluster(g, m)
	var live := false
	for id: int in ids:
		var mm: Dictionary = g.modules[id]
		if MU.networked(g, mm, MU.defs[mm["def"]]):
			live = true
			break
	m["live"] = live
	m["size_of"] = ids.size()


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	var n: int = m.get("size_of", 1)
	var p: Dictionary = def["params"]
	if not m.get("live", false):
		return "A cluster of %d, not counted: no Node or Hub in reach of any of it." % n
	return "A cluster of %d: +%d power and +%d units of goods held for the Hub, %d and %d of them its own." % [
			n, int(p["power"]) * n, int(p["goods"]) * n, int(p["power"]), int(p["goods"])]


## The Hub's power in the cell's hollow, as a level.
static func draw(ov, g, m: Dictionary, def: Dictionary, _z: float) -> void:
	if not m.get("live", false):
		return
	var level := clampf(g.stock[D.R_POWER] / maxf(1.0, g.power_cap()), 0.0, 1.0)
	if level <= 0.0:
		return
	var fr := MU.frame(g, m, def)
	var size: Vector2i = fr["lay"]["size"]
	var t := float(def["wall"])
	var bottom := float(size.y) - t
	var top := bottom - (float(size.y) - 2.0 * t) * level
	var pts := PackedVector2Array()
	for c: Vector2 in [Vector2(t, bottom), Vector2(size.x - t, bottom), Vector2(size.x - t, top), Vector2(t, top)]:
		pts.append(g.to_screen(MU.world(fr, c)))
	ov.draw_colored_polygon(pts, Color(0.96, 0.82, 0.35, 0.55))
