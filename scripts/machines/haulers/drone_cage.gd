extends RefCounted
## Drone Cage (A4, the Warren reworked): a bolted cage with a few drones. They fly out to loose
## powder anywhere in a square of ground round the cage, scoop up a handful, fly back and drop it
## into the cage's hollow, from where it goes out of its pixel face into a joined Tank, Funnel or
## Chute. Drones fly over anything, so they work through walls and across gaps; they only ever
## lift loose powder (never rock, liquid or a module's casing). A trip costs power from the Hub's
## stock and the cage needs a Node or the Hub in reach. Click it to switch the size of the square.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")

const HOME := 0         # at the cage, waiting for work or room
const OUT := 1          # flying to a spot
const BACK := 2         # flying home with a load

const BLOCK := 6        # cells across a spot a drone scoops


static func _zone(m: Dictionary, def: Dictionary) -> Rect2i:
	var radii: Array = def["params"]["radii"]
	var r: int = radii[int(m.get("size", 1)) % radii.size()]
	var c := Vector2i(roundi(m["at"].x), roundi(m["at"].y))
	return Rect2i(c.x - r, c.y - r, r * 2, r * 2)


## A random spot in `zone` that has loose powder, by halving the square towards one that does, or
## (-1, -1) if there is none.
static func _spot(g, m: Dictionary, zone: Rect2i) -> Vector2i:
	var powder := M.mask("powder")
	var r := zone.intersection(Rect2i(2, 2, 10000, 10000))
	var rng: int = m.get("rng", int(m["id"]) * 7919 + 13)
	while r.size.x > BLOCK or r.size.y > BLOCK:
		var w := maxi(1, r.size.x >> 1) if r.size.x > BLOCK else r.size.x
		var h := maxi(1, r.size.y >> 1) if r.size.y > BLOCK else r.size.y
		var parts: Array = []
		for ox in (2 if r.size.x > BLOCK else 1):
			for oy in (2 if r.size.y > BLOCK else 1):
				var q := Rect2i(r.position.x + ox * w, r.position.y + oy * h, w, h)
				if g.sim.count_in_rect(q.position.x, q.position.y, q.size.x, q.size.y, powder) > 0:
					parts.append(q)
		if parts.is_empty():
			m["rng"] = rng
			return Vector2i(-1, -1)
		rng = (rng * 1103515245 + 12345) & 0x7fffffff
		r = parts[(rng >> 8) % parts.size()]
	m["rng"] = rng
	return r.position + Vector2i(r.size.x >> 1, r.size.y >> 1)


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	if not m.has("drones"):
		var d: Array = []
		for _i in int(p["drones"]):
			d.append({"s": HOME, "p": Vector2(m["at"]), "t": Vector2.ZERO, "cargo": {}})
		m["drones"] = d
	var busy := 0
	var idle := 0
	for dr: Dictionary in m["drones"]:
		if dr["s"] == HOME and dr["cargo"].is_empty():
			idle += 1
		else:
			busy += 1
	var zone := _zone(m, def)
	m["state"] = ""
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	if MU.capacity(m, def) - MU.stored(m) < 1:
		m["state"] = "Full: nowhere to put what the drones bring."
	# Send idle drones to spots with powder, one a scan so the trips spread out.
	for dr: Dictionary in m["drones"]:
		if dr["s"] != HOME or not dr["cargo"].is_empty():
			continue
		var spot := _spot(g, m, zone)
		if spot.x < 0:
			if busy == 0:
				m["state"] = "No loose powder in the square."
			break
		if not MU.take_power(g, float(p["trip_power"])):
			m["state"] = "Waiting for power."
			break
		dr["s"] = OUT
		dr["t"] = Vector2(spot)
		break
	if m["state"] == "":
		m["state"] = "%d of %d drones out." % [(m["drones"] as Array).size() - idle, (m["drones"] as Array).size()]


## Every tick: the drones fly.
static func step(g, m: Dictionary, def: Dictionary) -> void:
	if not m.has("drones"):
		return
	var p: Dictionary = def["params"]
	var home := Vector2(m["at"])
	var v := float(p["speed"]) / 60.0
	for dr: Dictionary in m["drones"]:
		match dr["s"]:
			OUT:
				dr["p"] = (dr["p"] as Vector2).move_toward(dr["t"], v)
				if (dr["p"] as Vector2).distance_to(dr["t"]) < 0.5:
					var t: Vector2i = Vector2i(dr["t"])
					var h := BLOCK >> 1
					var got: PackedInt32Array = g.sim.dig_rect(t.x - h, t.y - h, BLOCK, BLOCK, M.mask("powder"), 0, 0)
					for mat in 256:
						if got[mat] > 0:
							dr["cargo"][mat] = got[mat]
					dr["s"] = BACK
			BACK:
				dr["p"] = (dr["p"] as Vector2).move_toward(home, v)
				if (dr["p"] as Vector2).distance_to(home) < 0.5:
					dr["s"] = HOME
			_:
				pass
		# At home with a load: drop what fits.
		if dr["s"] == HOME and not dr["cargo"].is_empty():
			for mat: int in dr["cargo"].keys():
				var put := MU.add(m, def, mat, dr["cargo"][mat])
				m["hauled"] = m.get("hauled", 0) + put
				dr["cargo"][mat] -= put
				if dr["cargo"][mat] <= 0:
					dr["cargo"].erase(mat)


## A click cycles the square's size.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	var radii: Array = def["params"]["radii"]
	m["size"] = (int(m.get("size", 1)) + 1) % radii.size()
	g.show_banner("%s: working a square %d cells across." % [def["name"], 2 * int(radii[m["size"]])], 1.5)


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	var radii: Array = def["params"]["radii"]
	return "%s Square %d across (click to change), %d cells hauled so far." % [m.get("state", ""), 2 * int(radii[int(m.get("size", 1)) % radii.size()]), m.get("hauled", 0)]


## The drones, and the square when the cage is hovered would be too much: just the drones.
static func draw(ov, g, m: Dictionary, _def: Dictionary, z: float) -> void:
	for dr: Dictionary in m.get("drones", []):
		if dr["s"] == HOME and dr["cargo"].is_empty():
			continue
		var col := Color(0.95, 0.85, 0.4) if dr["s"] == OUT else Color(0.9, 0.6, 0.3)
		ov.draw_circle(g.to_screen(dr["p"]), maxf(1.5, z * 1.2), col)
