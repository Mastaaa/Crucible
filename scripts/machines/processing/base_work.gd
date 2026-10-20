extends RefCounted
## What a processing part does to a base (A9 processing recut). A machine plugged into a base's socket acts on
## the base's contents through the wall; an interior strip joined to two bases moves and changes what passes
## from one to the other. This file holds the shared pieces: finding the bases, moving cells between them,
## and the filter a plugged machine puts on what may leave its base (`lets` and `holds`).
##
## A machine publishes two optional lists of `pass` style rules (see MU.passes) on its record each scan:
##   m["lets"]   only what these match may leave the base (a Heater on Boil: steam and what it leaves behind)
##   m["holds"]  what these match stays in the base (a Press keeps its pressable powder, a Caster its castable liquid)
## `may_leave` reads them over a base's machines; the base's own `pass` rule and any strip drawing from it
## ask it, so the Tank keeps its feed in while a machine works on it. machines.gd clears both before a scan,
## so a part that is off or short of a base holds nothing back.

const MU = preload("res://scripts/machines/mu.gd")
const LY = preload("res://scripts/machines/layers.gd")
const F = preload("res://scripts/machines/faces.gd")


## The base a machine is plugged into (its first joined base), or {}.
static func plug_base(g, m: Dictionary) -> Dictionary:
	var ids := LY.bases_of(g, m)
	return g.modules[ids[0]] if not ids.is_empty() else {}


## The base joined at the face named `name`, or {} (none there, not a base, or no hollow).
static func base_at(g, m: Dictionary, def: Dictionary, name: String) -> Dictionary:
	var p := MU.partner(g, m, def, name)
	return p if not p.is_empty() and LY.layer_of(MU.defs[p["def"]]) == "base" and p.get("sim") != null else {}


## A strip's two ends, [in, out]: the bases joined at the faces named `in` and `out` (or `a` and `b`), {} for a missing one.
static func ends(g, m: Dictionary, def: Dictionary) -> Array:
	var names := ["in", "out"] if MU.face_index(def, "in") >= 0 else ["a", "b"]
	var out: Array = []
	for n: String in names:
		var p := MU.partner(g, m, def, n)
		out.append(p if not p.is_empty() and LY.layer_of(MU.defs[p["def"]]) == "base" else {})
	return out


## Whether base `base` lets material `mat` out: no plugged machine holds it, and, when any machine says what it
## lets out, one of them lets this.
static func may_leave(g, base: Dictionary, mat: int) -> bool:
	var only: Array = []
	for l: Dictionary in LY.links(g, base):
		var o: Dictionary = g.modules[l["other"]]
		if LY.layer_of(MU.defs[o["def"]]) != "machine":
			continue
		for r: Dictionary in o.get("holds", []):
			if MU.accepts(r, mat):
				return false
		only.append_array(o.get("lets", []))
	if only.is_empty():
		return true
	for r: Dictionary in only:
		if MU.passes(r, mat):
			return true
	return false


## Moves up to `budget` cells that `rule` passes (and the source lets out) from base `src` to base `dst`, paying
## `power` a cell from the Hub's stock; returns how many arrived. What the destination has no room for goes back.
static func carry(g, src: Dictionary, dst: Dictionary, rule: Dictionary, budget: int, power: float) -> int:
	var moved := 0
	var held: Dictionary = src["contents"].duplicate()
	for mat: int in held:
		if budget <= 0:
			break
		if not MU.passes(rule, mat, held) or not may_leave(g, src, mat):
			continue
		var want := mini(budget, src["contents"].get(mat, 0))
		var room := MU.capacity(dst, MU.defs[dst["def"]]) - MU.stored(dst)
		want = mini(want, room)
		if want <= 0:
			continue
		if power > 0.0:
			while want > 0 and not MU.take_power(g, power * float(want)):
				want = want >> 1
			if want <= 0:
				return moved
		var got := MU.take(src, mat, want)
		var put := MU.add(dst, MU.defs[dst["def"]], mat, got)
		if put < got:
			MU.add(src, MU.defs[src["def"]], mat, got - put)
		budget -= put
		moved += put
	return moved


## Why a strip cannot work, "" when both its bases are there and have a hollow of their own to work on.
static func missing(ends_: Array) -> String:
	for b: Dictionary in ends_:
		if b.is_empty():
			return "Needs a base joined on each side."
		if b.get("sim") == null:
			return "Its base has no hollow to work on."
	return ""
