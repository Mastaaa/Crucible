extends RefCounted
## Layers and assemblies (A9 foundation, "LY"). Alex's module kit has layers: a base (Case, Tank,
## Cell) takes machine and exterior parts at side sockets and interior strips at side ports; lines,
## standalone tools and anchored parts sit outside it. A definition names its layer in `layer`;
## what the layer asks of it is `needs` (a list, with a default per layer, `[]` to ask nothing).
##
## Parts keep working alone. This file only recognises and coordinates:
##  - `scan` (every machine scan) finds each assembly of joined parts (face links and joints), gives
##    it an overseer record in `g.overseers`, and sets `m["needs"]` on every module: "" when its
##    layer's rules are met, else what is missing (machines.gd then holds the module and shows it).
##  - `line` is the overseer's one-line readout, gathered from the parts' own status text.
##  - `weld` bolts a part that needs a base to the base(s) it joins, so the assembly is one piece.
##  - `rescue` hands a line part's in-transit contents to a neighbour before it is lost.
##  - `validate` is the definition format's contract, checked over every definition by tests.
## Parts may publish `m["offers"]` (Array of words) and `m["waits"]` (a reason, when held up by a
## neighbour); the overseer shows `waits` first. `peers` and `bases_of` are how a part finds them.
## Nothing here preloads machines.gd (it preloads this file); `kinds` is set by it.

const MU = preload("res://scripts/machines/mu.gd")
const F = preload("res://scripts/machines/faces.gd")
const JT = preload("res://scripts/machines/joints.gd")
const MT = preload("res://scripts/machines/tools/mount.gd")

const ORDER := ["base", "machine", "interior", "exterior", "line", "standalone", "anchored"]
const NAMES := {"base": "Bases", "machine": "Machines", "interior": "Interiors", "exterior": "Exterior parts",
		"line": "Lines", "standalone": "Standalone tools", "anchored": "Anchored parts", "": "Other"}
const NAME_RULES := "res://data/overseer.json"
## What a layer asks of a part whose definition has no `needs` of its own.
##   socket: one of its socket faces joined to a base.   base_each_face: every pixel face joined to a base.
##   line: its `mount` side against a drawn line it takes (`mounts`), a standalone tool's (machines/tools/mount.gd).
const DEFAULT_NEEDS := {"machine": ["socket"], "exterior": ["socket"], "interior": ["base_each_face"]}
const MOVERS := ["winch", "slide", "turntable"]
const LEAD_RANK := {"exterior": 1, "machine": 2, "interior": 3, "base": 4}
const MAX_LINE := 120           # characters in a readout

## The behaviour scripts by `kind` (machines.gd sets it: it can't be preloaded here).
static var kinds := {}
static var _rules: Array = []
static var _rules_loaded := false


static func layer_of(def: Dictionary) -> String:
	return def.get("layer", "")


static func needs_of(def: Dictionary) -> Array:
	if def.has("needs"):
		return def["needs"]
	return DEFAULT_NEEDS.get(layer_of(def), [])


# --- Joins -----------------------------------------------------------------------------

static func _def(g, id: int) -> Dictionary:
	return MU.defs[g.modules[id]["def"]]


## The modules joined to `m`'s faces: [{face, other, other_face}].
static func links(g, m: Dictionary) -> Array:
	var out: Array = []
	for i in m["faces"].size():
		var o: int = m["faces"][i]["link_m"]
		if o != 0 and g.modules.has(o):
			out.append({"face": i, "other": o, "other_face": m["faces"][i]["link_f"]})
	return out


## Ids of the bases joined to `m` at any face.
static func bases_of(g, m: Dictionary) -> Array:
	var out: Array = []
	for l: Dictionary in links(g, m):
		if layer_of(_def(g, l["other"])) == "base" and not out.has(l["other"]):
			out.append(l["other"])
	return out


## Ids of the other modules in `m`'s assembly (none if it stands alone).
static func peers(g, m: Dictionary) -> Array:
	var o: Dictionary = g.overseers.get(m.get("overseer", 0), {})
	var out: Array = []
	for id: int in o.get("members", []):
		if id != m["id"]:
			out.append(id)
	return out


## "" when `m` has what its layer asks for, else what is missing, in the player's words.
static func unmet(g, m: Dictionary, def: Dictionary) -> String:
	for need: String in needs_of(def):
		if need == "socket":
			var ok := false
			for l: Dictionary in links(g, m):
				var f: Dictionary = def["faces"][l["face"]] if l["face"] < def["faces"].size() else {}
				if f.get("type", -1) == F.SOCKET and layer_of(_def(g, l["other"])) == "base":
					ok = true
			if not ok:
				return "Needs a base: join its socket to the side of a Tank, Case or Cell."
		elif need == "base_each_face":
			for i in def["faces"].size():
				var f: Dictionary = def["faces"][i]
				if f["type"] != F.PIXEL:
					continue
				var o: int = m["faces"][i]["link_m"] if i < m["faces"].size() else 0
				if o == 0 or not g.modules.has(o) or layer_of(_def(g, o)) != "base":
					return "Needs a base joined on each side: nothing at its %s face." % f.get("name", "open")
		elif need == "line":
			m["on"] = MT.line_under(g, m, def)
			if m["on"] == 0:
				return MT.missing(def)
		elif need == "host":
			m["on"] = MT.host_under(g, m, def)
			if m["on"] == 0:
				return MT.missing(def)
	return ""


# --- Assemblies and the overseer ------------------------------------------------------------

static func _root(parent: Dictionary, id: int) -> int:
	while parent[id] != id:
		parent[id] = parent[parent[id]]
		id = parent[id]
	return id


## Every machine scan: sets each module's `needs` and `overseer`, rebuilds `g.overseers` (an assembly of
## two or more modules joined by faces or joints; its id is its lowest module id) and welds parts to bases.
static func scan(g) -> void:
	g.overseers.clear()
	var parent := {}
	for id: int in g.modules:
		parent[id] = id
	for id: int in g.modules:
		for f: Dictionary in g.modules[id]["faces"]:
			var o: int = f["link_m"]
			if o != 0 and parent.has(o):
				parent[_root(parent, id)] = _root(parent, o)
	for jid: int in g.joints:
		var j: Dictionary = g.joints[jid]
		if j["b"] != 0 and parent.has(j["a"]) and parent.has(j["b"]):
			parent[_root(parent, j["a"])] = _root(parent, j["b"])
	var groups := {}
	for id: int in g.modules:
		var r := _root(parent, id)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(id)
	for r: int in groups:
		var ids: Array = groups[r]
		ids.sort()
		var oid: int = ids[0] if ids.size() > 1 else 0
		if oid != 0:
			g.overseers[oid] = {"id": oid, "members": ids, "lead": _lead(g, ids), "name": _name(g, ids)}
		for id: int in ids:
			g.modules[id]["overseer"] = oid
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		var def: Dictionary = MU.defs[m["def"]]
		m["needs"] = unmet(g, m, def)
		weld(g, m, def)


static func _rank(g, id: int) -> int:
	var def := _def(g, id)
	if MOVERS.has(def.get("kind", "")):
		return 0
	return LEAD_RANK.get(layer_of(def), 5)


## The member that speaks for the assembly: movers first, then exterior, machine, interior and base parts.
static func _lead(g, ids: Array) -> int:
	var best: int = ids[0]
	for id: int in ids:
		if _rank(g, id) < _rank(g, best):
			best = id
	return best


static func _rule_set() -> Array:
	if not _rules_loaded:
		_rules_loaded = true
		var f := FileAccess.open(NAME_RULES, FileAccess.READ)
		var json: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if json is Dictionary:
			_rules = json.get("names", [])
	return _rules


## What the assembly is called: the first rule in data/overseer.json it satisfies (`has`: every entry
## present, `any`: at least one; entries are "kind:<kind>" or "layer:<layer>"), else its lead's name.
static func _name(g, ids: Array) -> String:
	var present := {}
	for id: int in ids:
		var def := _def(g, id)
		present["kind:" + str(def.get("kind", ""))] = true
		present["layer:" + layer_of(def)] = true
	for rule: Dictionary in _rule_set():
		var ok := true
		for h: String in rule.get("has", []):
			ok = ok and present.has(h)
		var any: Array = rule.get("any", [])
		if ok and not any.is_empty():
			ok = false
			for a: String in any:
				ok = ok or present.has(a)
		if ok:
			return rule["name"]
	return "%s group" % _def(g, _lead(g, ids))["name"]


## The overseer's one line for the assembly module `m` belongs to ("" when it stands alone): its name and
## size, then what the parts say: any part held up (`needs`, `waits`) first, then the lead's own status.
static func line(g, m: Dictionary) -> String:
	var o: Dictionary = g.overseers.get(m.get("overseer", 0), {})
	if o.is_empty():
		return ""
	var items: Array = []
	for id: int in o["members"]:
		var p: Dictionary = g.modules[id]
		var why: String = p.get("waits", "")
		if why == "":
			why = p.get("needs", "")
		if why != "":
			items.append([_def(g, id)["name"], why])
	var lead: Dictionary = g.modules[o["lead"]]
	if items.size() < 2:
		var s := status_of(g, lead)
		if s != "":
			items.append([_def(g, o["lead"])["name"], s])
	var out := "%s, %d parts" % [o["name"], o["members"].size()]
	var sep := ": "
	for it: Array in items:
		var piece := "%s: %s" % [it[0], str(it[1]).trim_suffix(".")]
		if out.length() + sep.length() + piece.length() > MAX_LINE:
			break
		out += sep + piece
		sep = ". "
	return out


## A part's own status text: its `state`, else the first line of what its behaviour says in `info`.
static func status_of(g, m: Dictionary) -> String:
	var s: String = str(m.get("state", ""))
	if s != "":
		return s
	var def: Dictionary = MU.defs[m["def"]]
	var kind: Variant = kinds.get(def.get("kind", ""))
	if kind != null:
		return str(kind.info(g, m, def)).split("\n")[0]
	return ""


# --- Welding and line parts ----------------------------------------------------------------

## A machine, interior or exterior part that needs a base is bolted to the base(s) it is joined to, so
## the assembly is one rigid piece wherever it stands (the bolts are `hold_rig`'s, owned by the part).
static func weld(g, m: Dictionary, def: Dictionary) -> void:
	if def.has("mount"):
		MT.hold(g, m, def)        # a standalone tool is bolted to its line
		return
	if needs_of(def).is_empty():
		return
	var bases := bases_of(g, m)
	if bases.is_empty():
		if m.get("welded", false):
			JT.drop_auto(g, m["id"])
			m["welded"] = false
		return
	JT.hold_rig(g, m["id"], bases, true)
	m["welded"] = true


## Called when a module has just been placed: its first pairing is done, so weld it at once.
static func placed(g, m: Dictionary) -> void:
	m["needs"] = unmet(g, m, MU.defs[m["def"]])
	weld(g, m, MU.defs[m["def"]])


## A definition with an `inventory` (a line part: Pipe, Cable, Network) hands what it carries to the
## nearest joined module that will take it before it is spilled, as Alex asked: a broken Pipe puts its
## contents back where they came from.
static func rescue(g, m: Dictionary, def: Dictionary) -> void:
	if not def.has("inventory"):
		return
	var kind: Variant = kinds.get(def.get("kind", ""))
	if kind != null and kind.has_method("rescue"):
		kind.rescue(g, m, def)       # a drawn line (lines.gd) knows where its load belongs
	if m["contents"].is_empty():
		return
	var near: Array = []
	for l: Dictionary in links(g, m):
		near.append(l["other"])
	near.sort_custom(func(a: int, b: int) -> bool:
		return g.modules[a]["at"].distance_to(m["at"]) < g.modules[b]["at"].distance_to(m["at"]))
	for mat: int in m["contents"].keys():
		for o: int in near:
			var want: int = m["contents"].get(mat, 0)
			if want <= 0:
				break
			var put := MU.add(g.modules[o], _def(g, o), mat, want)
			if put > 0:
				MU.take(m, mat, put)


# --- The definition format ---------------------------------------------------------------------

## What is wrong with definition `def` against the layer rules (an empty list is a good one). Tests run
## it over every definition, so a track that fills in a stub keeps the format.
static func validate(def: Dictionary) -> Array:
	var bad: Array = []
	var id: String = def.get("id", "?")
	var layer := layer_of(def)
	if layer != "" and not ORDER.has(layer):
		bad.append("%s: unknown layer '%s'" % [id, layer])
		return bad
	var faces: Array = def.get("faces", [])
	var sockets := 0
	var pixels: Array = []
	for f: Dictionary in faces:
		if f["type"] == F.SOCKET:
			sockets += 1
			if f["w"] != F.SOCKET_W:
				bad.append("%s: socket face '%s' is %d wide, sockets are %d" % [id, f.get("name", ""), f["w"], F.SOCKET_W])
		elif f["type"] == F.PIXEL:
			pixels.append(f)
	var needs := needs_of(def)
	if layer == "base" and sockets < 1:
		bad.append("%s: a base needs at least one socket face" % id)
	if needs.has("socket") and sockets < 1:
		bad.append("%s: needs a base at a socket but has no socket face" % id)
	if needs.has("base_each_face"):
		if pixels.size() < 2 or pixels.size() > 3 or (pixels[0]["dir"] + pixels[1]["dir"]) != Vector2i.ZERO:
			bad.append("%s: an interior strip has two pixel faces on opposite sides (and may have a third)" % id)
	if needs.has("host") and not MU.FRONT_DIRS.has(def.get("mount", "")):
		bad.append("%s: a part that needs a host names its `mount` side" % id)
	if needs.has("line") and (not MU.FRONT_DIRS.has(def.get("mount", "")) or def.get("mounts", []).is_empty()):
		bad.append("%s: a part that needs a line names its `mount` side and the `mounts` it takes" % id)
	if (needs.has("line") or needs.has("host")) and MU.FRONT_DIRS.has(def.get("mount", "")) \
			and MU.FRONT_DIRS[def["mount"]] + MU.FRONT_DIRS.get(def.get("front", "down"), Vector2i.ZERO) != Vector2i.ZERO:
		bad.append("%s: its `front` is opposite its `mount`" % id)
	if layer == "anchored" and not def.get("anchored", false):
		bad.append("%s: an anchored part is `anchored`" % id)
	if def.has("inventory"):
		if int(def["inventory"].get("cap", 0)) <= 0:
			bad.append("%s: inventory needs a positive cap" % id)
	elif layer == "line" and def.get("stub", false):
		bad.append("%s: a line part has an inventory (what is in transit)" % id)
	for a: Dictionary in def.get("attach", []):
		if MU.face_index(def, a.get("face", "")) < 0:
			bad.append("%s: attach names a face that is not there ('%s')" % [id, a.get("face", "")])
	if def.get("stub", false):
		if layer == "":
			bad.append("%s: a stub names its layer" % id)
		if def.get("kind", "") != "stub":
			bad.append("%s: a stub's kind is 'stub'" % id)
		if not ["processing", "exterior", "tools"].has(def.get("track", "")):
			bad.append("%s: a stub names the track that fills it in" % id)
	return bad
