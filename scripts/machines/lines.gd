extends RefCounted
## Lines (A9 exterior track, "LN"): the Pipe, the Cable and the Network line. A line is a thin module of its own,
## laid between two ends with a two-click tool like the Strut: the Pipe between two Pipe Hookups (or a Pipe
## Router), the Cable between two Energy Ports, the Network line between two Network I/O ports (a Funnel or a
## Bus Hopper). Its ends are held at the ends' attach points by two hinges owned by the line (`auto`), so it goes
## with either end and a hinge that snaps leaves it cut. Each line has an inventory, what is in transit:
##  - Pipe: pixels (`contents`), taken from the base behind its start hookup and put in the base behind its
##    end hookup, or into a Router; a click reverses it.
##  - Cable: power, held as `charge` (not `contents`: that is keyed by material id and spills as pixels). A
##    Cable with a Node or the Hub in reach of one end fills from the Hub's stock; once it holds half its
##    charge the assemblies at both ends count as networked (`g.reach`, read by `MU.networked`).
##  - Network: goods in cells (`contents`) from a port outside the network's reach to one inside it, banked there.
##    The remote port banks into the line (`bank`), the line banks them at the far end, and the far port needs
##    a Node or the Hub in reach.
## A destroyed line hands what it carries back (`rescue`): a Pipe to the base it came from, a Cable's charge to
## the Hub's stock, a Network line's goods to the port they were headed for; what will not fit is gone.

const MU = preload("res://scripts/machines/mu.gd")
const F = preload("res://scripts/machines/faces.gd")
const JT = preload("res://scripts/machines/joints.gd")
const LY = preload("res://scripts/machines/layers.gd")
const M = preload("res://scripts/materials.gd")
const D = preload("res://scripts/defs.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")

const KINDS := ["pipe", "cable", "network"]
const T := 5                    # a line's thickness, cells
const CUT := 1.5                # cells a line's body stops short of the attach point it is hinged at
const CHARGE_RATE := 1.0        # power a scan a Cable can take from the Hub's stock while it fills
const ENERGISED := 0.5          # share of its charge a Cable holds before the far assembly counts as networked
## What each tool starts and ends on: the kinds (or flag) of module a hookup point may belong to.
const ENDS := {
	"pipe": "a Pipe Hookup or a Pipe Router",
	"cable": "an Energy Port",
	"network": "a Funnel or a Bus Hopper",
}


# --- Definitions ----------------------------------------------------------------------

static func is_line(def: Dictionary) -> bool:
	return def.get("layer", "") == "line" and KINDS.has(def.get("kind", ""))


## Registers the line tools with the joint tool router (machines.gd calls it once).
static func register() -> void:
	for kind: String in KINDS:
		var d: Dictionary = MU.defs.get(kind, {})
		if d.is_empty():
			continue
		JT.ext_tools[kind] = {"name": d["name"], "tech": d.get("tech", ""), "click": click, "draw": draw_tool}


## The definition of a `kind` line `l` cells long, registered on first use (and again after a load): the tool's
## definition with a body of that length, no faces, and an inventory scaled to the length.
static func line_def(kind: String, l: int) -> String:
	var id := "%s_%d" % [kind, l]
	if not MU.defs.has(id):
		var base: Dictionary = MU.defs[kind]
		var inv: Dictionary = base["inventory"].duplicate()
		inv["cap"] = maxi(8, int(ceil(float(inv["cap"]) * float(l) / 40.0)))
		var p: Dictionary = base["params"].duplicate()
		p["charge_cap"] = maxf(1.0, float(p.get("charge_per_40", 2.0)) * float(l) / 40.0)
		MU.defs[id] = {"id": id, "name": base["name"], "layer": "line", "kind": kind, "size": Vector2i(l, T), "wall": T,
				"faces": [], "cost": cost_of(kind, float(l)), "hidden": true, "inventory": inv, "params": p, "of": kind}
	return id


## After a load: the definitions of the lines in the game.
static func restore_defs(g) -> void:
	for id: int in g.modules:
		var def_id: String = g.modules[id]["def"]
		if MU.defs.has(def_id):
			continue
		var cut := def_id.rfind("_")
		if cut > 0 and KINDS.has(def_id.substr(0, cut)) and def_id.substr(cut + 1).is_valid_int():
			line_def(def_id.substr(0, cut), int(def_id.substr(cut + 1)))


## The price of a `kind` line `span` cells long.
static func cost_of(kind: String, span: float) -> Array:
	var p: Dictionary = MU.defs[kind]["params"]
	var n: int = maxi(1, int(ceil(span / float(p["per"]))))
	var out: Array = []
	for c in MU.defs[kind]["cost"]:
		out.append(int(c) * n)
	return out


# --- Ends -----------------------------------------------------------------------------

## The line modules of the game (ids).
static func all(g) -> Array:
	var out: Array = []
	for id: int in g.modules:
		if is_line(MU.defs[g.modules[id]["def"]]):
			out.append(id)
	return out


## Whether hookup point `e` (a `JT.hook_point` or `JT.hold` result) is somewhere a `kind` line may end.
static func end_ok(g, kind: String, e: Dictionary) -> bool:
	if not e.get("hit", false) or e.get("mod", 0) == 0 or e.get("kind", "") != "hookup":
		return false
	var def: Dictionary = MU.defs[g.modules[e["mod"]]["def"]]
	match kind:
		"pipe": return def.get("kind", "") == "hookup" or def.get("kind", "") == "router"
		"cable": return def.get("kind", "") == "energy_port"
		"network": return def.get("port", false)
	return false


## The line (id) already ending at module `mod`'s point `name`, or 0.
static func taken(g, mod: int, name: String) -> int:
	for id: int in all(g):
		var m: Dictionary = g.modules[id]
		for k in 2:
			if m.has("ends") and m["ends"][k] == mod and m["end_names"][k] == name:
				return id
	return 0


## The lines (ids) laid to module `mod`.
static func ending_at(g, mod: int) -> Array:
	var out: Array = []
	for id: int in all(g):
		if g.modules[id].has("ends") and g.modules[id]["ends"].has(mod):
			out.append(id)
	return out


## "" if a `kind` line from end `a` to end `b` can be laid, else why not.
static func why(g, kind: String, a: Dictionary, b: Dictionary) -> String:
	var p: Dictionary = MU.defs[kind]["params"]
	if not end_ok(g, kind, a):
		return "A %s starts at %s." % [kind, ENDS[kind]]
	if not end_ok(g, kind, b):
		return "A %s ends at %s." % [kind, ENDS[kind]]
	if a["mod"] == b["mod"]:
		return "Both ends are on the same part."
	var span: float = (a["pos"] as Vector2).distance_to(b["pos"])
	if span < float(p["min"]):
		return "Too short."
	if span > float(p["max"]):
		return "Too long (%d cells at most)." % int(p["max"])
	for e: Dictionary in [a, b]:
		if taken(g, e["mod"], e["name"]) != 0:
			return "That end already has a line."
	if kind == "pipe":
		var ba := LY.bases_of(g, g.modules[a["mod"]])
		var bb := LY.bases_of(g, g.modules[b["mod"]])
		for x: int in ba:
			if bb.has(x):
				return "Both hookups are on the same base."
	if not JT.affordable(g, cost_of(kind, span)):
		return "Needs %s in the stockpile." % MU.cost_text(cost_of(kind, span))
	return ""


## The hinge-held ends of line `m` are both still there.
static func connected(g, m: Dictionary) -> bool:
	if not m.has("ends"):
		return false
	for k in 2:
		if not g.modules.has(m["ends"][k]) or not g.joints.has(m["joints"][k]):
			return false
	return true


# --- Laying ---------------------------------------------------------------------------

## Lays a `kind` line from end `s` to end `e` (`why` said it could be). Returns the new line's module id, or 0.
static func lay(g, kind: String, s: Dictionary, e: Dictionary) -> int:
	if not JT.module_maker.is_valid() or not JT.module_remover.is_valid():
		return 0
	var d: Vector2 = ((e["pos"] as Vector2) - s["pos"]).normalized()
	for extra in 4:
		var cut := CUT + float(extra)
		var p1: Vector2 = s["pos"] + d * cut
		var p2: Vector2 = e["pos"] - d * cut
		var l := int(round(p1.distance_to(p2)))
		if l < 4:
			return 0
		var id: int = JT.module_maker.call(g, line_def(kind, l), (p1 + p2) * 0.5, d.angle())
		if id == 0:
			continue
		if not JT._whole(g, id):
			JT.module_remover.call(g, id)
			continue
		var m: Dictionary = g.modules[id]
		m["ends"] = [s["mod"], e["mod"]]
		m["end_names"] = [s["name"], e["name"]]
		m["dir"] = 1
		m["joints"] = [0, 0]
		for k in 2:
			var end: Dictionary = s if k == 0 else e
			var j := JT.attach(g, "hinge", id, end["mod"], end["pos"], end["pos"])
			if j != 0:
				g.joints[j]["auto"] = id
			m["joints"][k] = j
		if m["joints"][0] == 0 or m["joints"][1] == 0:
			JT.module_remover.call(g, id)
			continue
		return id
	return 0


# --- The tool -------------------------------------------------------------------------

static func click(g, kind: String, p: Vector2) -> void:
	var e := JT.hold(g, p)
	if g.joint_from.is_empty():
		g.joint_from = e
		g.show_banner("%s: now click where it ends." % MU.defs[kind]["name"], 2.0)
		return
	var s: Dictionary = g.joint_from
	g.joint_from = {}
	var bad := why(g, kind, s, e)
	if bad != "":
		g.show_banner(bad, 2.5)
		return
	var span: float = (s["pos"] as Vector2).distance_to(e["pos"])
	var cost := cost_of(kind, span)
	if lay(g, kind, s, e) == 0:
		g.show_banner("There is no room for that %s." % kind, 2.0)
		return
	for r in cost.size():
		g.stock[r] -= cost[r]


static func draw_tool(ov, g, z: float, kind: String) -> void:
	var e := JT.hold(g, Vector2(g.hover) + Vector2(0.5, 0.5))
	var bad := ""
	if not g.joint_from.is_empty():
		bad = why(g, kind, g.joint_from, e)
	var at: Vector2 = g.to_screen(e["pos"])
	ov.draw_arc(at, maxf(5.0, 5.0 * z), 0.0, TAU, 20, ov.OK_COL if end_ok(g, kind, e) else Color(1.0, 1.0, 1.0, 0.5), 1.5)
	if g.joint_from.is_empty():
		return
	var col: Color = ov.OK_COL if bad == "" else ov.BAD_COL
	var from: Vector2 = g.to_screen(g.joint_from["pos"])
	ov.draw_line(from, at, Color(col, 0.8), 1.5)
	ov.draw_arc(from, maxf(5.0, 5.0 * z), 0.0, TAU, 20, ov.OK_COL, 1.5)
	var span: float = (g.joint_from["pos"] as Vector2).distance_to(e["pos"])
	var txt := bad if bad != "" else "%d cells, %s" % [roundi(span), MU.cost_text(cost_of(kind, span))]
	if ov.font != null:
		ov.draw_string(ov.font, at + Vector2(10.0, 18.0), txt, HORIZONTAL_ALIGNMENT_LEFT, 320.0, 13, Color(1, 1, 1, 0.9))


## The Build list's line buttons (under the "Lines" heading, next to the Chute and Conveyor).
static func add_buttons(hud, vb: VBoxContainer) -> Array:
	var out: Array = []
	for kind: String in KINDS:
		var d: Dictionary = MU.defs.get(kind, {})
		if d.is_empty():
			continue
		var b: Button = hud._button("   %s  [%s per %d cells]" % [d["name"], MU.cost_text(d["cost"]), int(d["params"]["per"])])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = "%s\nClick the start, then the end. Esc cancels." % d["blurb"]
		b.pressed.connect(func() -> void:
			hud.game.cancel_tool()
			hud.game.joint_pick = kind
			hud.game.show_banner("%s: click where it starts, then where it ends. Esc cancels." % d["name"], 3.0))
		b.visible = JT.unlocked(hud.game, kind)
		hud.module_buttons.append({"button": b, "def": {"tech": d.get("tech", "")}})
		vb.add_child(b)
		out.append(b)
	return out


# --- The network's reach ------------------------------------------------------------------

## Every machine scan, after the assemblies are found (`LY.scan`): which parts a live Cable or Network line puts
## in the network's reach (`g.reach`), and which lines are live (a Node or the Hub in reach of an end).
static func scan(g) -> void:
	g.reach.clear()
	var lines := all(g)
	if lines.is_empty():
		return
	var direct := {}
	for id: int in g.modules:
		var mm: Dictionary = g.modules[id]
		direct[id] = MU.direct(g, mm, MU.defs[mm["def"]])
	var comp := _components(g)
	var live := {}
	for id: int in direct:
		if direct[id]:
			live[comp[id]] = true
	# A Cable that is full enough carries reach from one assembly to the other.
	var changed := true
	while changed:
		changed = false
		for lid: int in lines:
			var m: Dictionary = g.modules[lid]
			if MU.defs[m["def"]]["kind"] == "cable" and m.get("energised", false) and connected(g, m):
				var ca: int = comp[m["ends"][0]]
				var cb: int = comp[m["ends"][1]]
				if live.has(ca) != live.has(cb):
					live[ca] = true
					live[cb] = true
					changed = true
	for id: int in g.modules:
		if live.has(comp[id]) and not direct[id]:
			g.reach[id] = true
	for lid: int in lines:
		var m: Dictionary = g.modules[lid]
		var kind: String = MU.defs[m["def"]]["kind"]
		if not connected(g, m):
			m["live"] = false
			continue
		var a: int = m["ends"][0]
		var b: int = m["ends"][1]
		if kind == "cable":
			m["live"] = live.has(comp[a]) or live.has(comp[b])
		elif kind == "network":
			var src: int = a if m.get("dir", 1) > 0 else b
			var dst: int = b if m.get("dir", 1) > 0 else a
			m["live"] = direct[dst]
			if direct[dst] and not direct[src]:
				g.reach[src] = true
		else:
			m["live"] = true


## Module id -> a representative id of the group of modules joined by face links.
static func _components(g) -> Dictionary:
	var comp := {}
	for id: int in g.modules:
		if comp.has(id):
			continue
		var queue: Array = [id]
		comp[id] = id
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for l: Dictionary in LY.links(g, g.modules[cur]):
				if not comp.has(l["other"]):
					comp[l["other"]] = id
					queue.append(l["other"])
	return comp


# --- Network ports ----------------------------------------------------------------------

## The Network line (id) that starts at port `port` and is joined and live, or 0.
static func line_from(g, port: int) -> int:
	for id: int in all(g):
		var m: Dictionary = g.modules[id]
		if MU.defs[m["def"]]["kind"] != "network" or not connected(g, m):
			continue
		var src: int = m["ends"][0] if m.get("dir", 1) > 0 else m["ends"][1]
		if src == port:
			return id
	return 0


## Whether port `m` banks through a Network line: it has one, and no Node or the Hub in reach of its own.
static func via_line(g, m: Dictionary, def: Dictionary) -> int:
	if MU.direct(g, m, def):
		return 0
	return line_from(g, m["id"])


## How many cells port `m` can bank now: any number with the network in reach (or no line to use), else the
## room left in its Network line.
static func bank_room(g, m: Dictionary, def: Dictionary) -> int:
	var line := via_line(g, m, def)
	if line == 0:
		return 1 << 30
	var lm: Dictionary = g.modules[line]
	return MU.capacity(lm, MU.defs[lm["def"]]) - MU.stored(lm)


## Banks `n` cells of `mat` for port `m`: into the Hub's stock when the network is in reach, else into its
## Network line. Returns how many were taken (the rest stay with the caller).
static func bank(g, m: Dictionary, def: Dictionary, mat: int, n: int) -> int:
	if n <= 0:
		return 0
	var line := via_line(g, m, def)
	if line == 0:
		g.bank_cells(m["at"], mat, n)
		return n
	var lm: Dictionary = g.modules[line]
	return MU.add(lm, MU.defs[lm["def"]], mat, n)


# --- The lines at work ------------------------------------------------------------------

## The module holding what a Pipe end `id` gives or takes: the base behind a Hookup, or the Router itself.
static func _holder(g, id: int) -> Dictionary:
	if not g.modules.has(id):
		return {}
	var m: Dictionary = g.modules[id]
	if MU.defs[m["def"]]["kind"] == "router":
		return m
	return EX.base_of(g, m)


static func scan_line(g, m: Dictionary, def: Dictionary) -> void:
	m["state"] = ""
	if not connected(g, m):
		m["state"] = "Cut: a hinge let go or an end is gone."
		return
	match def["kind"]:
		"pipe": _pipe(g, m, def)
		"cable": _cable(g, m, def)
		"network": _network(g, m, def)


static func _pipe(g, m: Dictionary, def: Dictionary) -> void:
	var rate := MU.rate(g, int(def["params"]["rate"]))
	var forward: bool = m.get("dir", 1) > 0
	var src := _holder(g, m["ends"][0] if forward else m["ends"][1])
	var dst := _holder(g, m["ends"][1] if forward else m["ends"][0])
	if src.is_empty() or dst.is_empty():
		m["state"] = "An end has no base."
		return
	var sdef: Dictionary = MU.defs[src["def"]]
	var ddef: Dictionary = MU.defs[dst["def"]]
	# What came in last scan goes out first, so a cell spends a scan in the pipe.
	var moved := 0
	for mat: int in m["contents"].keys():
		var n := mini(rate - moved, int(m["contents"].get(mat, 0)))
		if n <= 0:
			continue
		var put := MU.add(dst, ddef, mat, n)
		MU.take(m, mat, put)
		moved += put
	var budget := mini(rate, MU.capacity(m, def) - MU.stored(m))
	if MU.defs[src["def"]]["kind"] == "router":
		budget = mini(budget, _router_share(g, src, MU.stored(src)))
	var pulled := 0
	for mat: int in src["contents"].keys():
		if budget - pulled <= 0:
			break
		var want := mini(budget - pulled, int(src["contents"].get(mat, 0)))
		var got := MU.take(src, mat, want)
		var put := MU.add(m, def, mat, got)
		if put < got:
			MU.add(src, sdef, mat, got - put)
		pulled += put
	m["carried"] = m.get("carried", 0) + moved
	if moved > 0 or pulled > 0:
		m["state"] = "Carrying."
	elif MU.stored(m) > 0:
		m["state"] = "Backed up: its end will not take what it carries."
	else:
		m["state"] = "Nothing to carry."


## Cells a pipe may draw from `router` this scan: its stock shared between the pipes that leave it.
static func _router_share(g, router: Dictionary, stock: int) -> int:
	var outs := 0
	for id: int in all(g):
		var pm: Dictionary = g.modules[id]
		if MU.defs[pm["def"]]["kind"] != "pipe" or not connected(g, pm):
			continue
		var from: int = pm["ends"][0] if pm.get("dir", 1) > 0 else pm["ends"][1]
		if from == router["id"]:
			outs += 1
	return maxi(1, int(ceil(float(stock) / float(maxi(1, outs)))))


static func _cable(g, m: Dictionary, def: Dictionary) -> void:
	var cap: float = def["params"]["charge_cap"]
	var charge: float = m.get("charge", 0.0)
	if m.get("live", false) and charge < cap:
		var take := minf(cap - charge, CHARGE_RATE)
		if g.stock[D.R_POWER] >= take:
			g.stock[D.R_POWER] -= take
			charge += take
	m["charge"] = charge
	m["energised"] = charge >= cap * ENERGISED
	if not m.get("live", false):
		m["state"] = "Dead: neither end has a Node or the Hub in reach."
	elif m["energised"]:
		m["state"] = "Live."
	else:
		m["state"] = "Charging."


static func _network(g, m: Dictionary, def: Dictionary) -> void:
	var forward: bool = m.get("dir", 1) > 0
	var dst_id: int = m["ends"][1] if forward else m["ends"][0]
	var dst: Dictionary = g.modules[dst_id]
	if not m.get("live", false):
		m["state"] = "Its far port has no Node or the Hub in reach."
		return
	var left := MU.rate(g, int(def["params"]["rate"]))
	var moved := 0
	for mat: int in m["contents"].keys():
		var n := mini(left - moved, int(m["contents"].get(mat, 0)))
		if M.is_good(mat):
			n = mini(n, g.good_room_cells(mat))
		if n <= 0:
			continue
		n = MU.take(m, mat, n)
		g.bank_cells(dst["at"], mat, n)
		moved += n
	m["carried"] = m.get("carried", 0) + moved
	if moved > 0:
		m["state"] = "Carrying goods."
	elif MU.stored(m) > 0:
		m["state"] = "Backed up: the bank will not take what it carries."
	else:
		m["state"] = "Nothing to carry."


## A click on a Pipe or Network line turns it round.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	if def["kind"] == "cable":
		return
	m["dir"] = -int(m.get("dir", 1))
	g.show_banner("%s: runs the other way." % def["name"], 1.5)


## What a destroyed or taken-down line hands back before its pixels spill (layers.gd `rescue`).
static func rescue(g, m: Dictionary, def: Dictionary) -> void:
	if not m.has("ends"):
		return
	match def["kind"]:
		"cable":
			g.stock[D.R_POWER] = minf(g.stock[D.R_POWER] + float(m.get("charge", 0.0)), g.power_cap())
			m["charge"] = 0.0
		"pipe":
			# Back to the base it came from, then on to the one it was bound for; the rest spills.
			var forward: bool = m.get("dir", 1) > 0
			for end: int in [m["ends"][0] if forward else m["ends"][1], m["ends"][1] if forward else m["ends"][0]]:
				var h := _holder(g, end)
				if h.is_empty():
					continue
				for mat: int in m["contents"].keys():
					var put := MU.add(h, MU.defs[h["def"]], mat, int(m["contents"].get(mat, 0)))
					MU.take(m, mat, put)
		"network":
			# Already uploaded to the network: delivered if the far port still stands, otherwise gone.
			var forward: bool = m.get("dir", 1) > 0
			var dst_id: int = m["ends"][1] if forward else m["ends"][0]
			if g.modules.has(dst_id) and m.get("live", false):
				for mat: int in m["contents"].keys():
					g.bank_cells(g.modules[dst_id]["at"], mat, int(m["contents"][mat]))
			m["contents"].clear()


# --- Reading -------------------------------------------------------------------------------

static func info(g, m: Dictionary, def: Dictionary) -> String:
	var s: String = m.get("state", "")
	match def["kind"]:
		"cable":
			var cap: float = def["params"]["charge_cap"]
			return "%s %.1f of %.1f power in transit." % [s, m.get("charge", 0.0), cap]
		_:
			var held := MU.stored(m)
			var what := "empty"
			if held > 0:
				var best := EX.most(m)
				what = "%d of %d cells in transit, mostly %s" % [held, MU.capacity(m, def), M.names[best]]
			var way := ""
			if connected(g, m):
				way = " %s to %s." % [MU.defs[g.modules[m["ends"][0 if m.get("dir", 1) > 0 else 1]]["def"]]["name"],
						MU.defs[g.modules[m["ends"][1 if m.get("dir", 1) > 0 else 0]]["def"]]["name"]]
			return "%s %s.%s Click to reverse." % [s, what.capitalize(), way]


## The line's stripe: the colour of what it carries (Cable: yellow once live, Network: teal), along its length.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var fr := MU.frame(g, m, def)
	var size: Vector2i = fr["lay"]["size"]
	var a: Vector2 = g.to_screen(MU.world(fr, Vector2(1.0, size.y * 0.5)))
	var b: Vector2 = g.to_screen(MU.world(fr, Vector2(size.x - 1.0, size.y * 0.5)))
	var col := Color(0.35, 0.35, 0.4, 0.9)
	var w := maxf(1.0, 2.0 * z)
	match def["kind"]:
		"cable":
			if m.get("energised", false):
				col = Color(1.0, 0.85, 0.3, 0.95)
			elif m.get("charge", 0.0) > 0.0:
				col = Color(0.7, 0.6, 0.25, 0.9)
		_:
			var held := MU.stored(m)
			if held > 0:
				var base := Color(M.color_of(EX.most(m)))
				col = Color(base, 0.95)
			elif def["kind"] == "network":
				col = Color(0.3, 0.7, 0.7, 0.8)
	ov.draw_line(a, b, col, w)
