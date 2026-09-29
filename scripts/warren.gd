extends RefCounted
## The Warren's mites (phase 7, reworked for the phase 8b scale). Static helpers the
## game calls with itself as `game`; each mite is a Dictionary, so a colony is a
## plain Array on the Warren.
##
## They dig a half-circle chamber over the Warren, then tunnel toward its marker
## (if one's set) by a simple rule, and hollow out a small circle there. Mites are
## small and work in bites, BITE x BITE cells (the fog's 4x4 blocks): a mite
## nibbles a bite out a cell at a time, moves on to a bite beside it, and after a
## short burst of bites (MITE_BURST) carries the lot home. One breadth-first search
## over bites from the Warren's doorstep finds what they can reach and the way to
## it. Mites never dig what holds the Warren up; if the ground goes anyway, the
## Warren falls like any building.
##
## Phase 8d: a mite walks and clings on its own, but the moment physics takes it
## (it loses its grip, a blast catches it) it's a small body in the engine
## (MITE_SIZE square, material Mite) that falls, tumbles, piles up and can be
## thrown; once it lies still it walks again from where it landed. Rock moving into
## a mite with MITE_CRUSH or more crushes it; less squeezes it into the next bite.

const D = preload("res://scripts/defs.gd")

const S_HOME := 0       # on the doorstep, waiting for work or power
const S_OUT := 1        # walking its path to a bite
const S_DIG := 2        # nibbling it out
const S_BACK := 3       # hauling its load home
const S_PANIC := 4      # alight and running

const BSHIFT := 2
const BITE := 1 << BSHIFT   # cells across a bite
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const SEARCH_EVERY := 1.0   # seconds between searches when nothing has changed
const SEARCH_SOON := 0.5    # soonest a search reruns after a bite
const LOST_S := 8.0         # a mite that can't find its way home this long is gone
const REVEAL_R := 3.0 * D.S # fog a mite clears where it digs
const BURST_HOP := 2        # the next bite of a burst is at most this many bites off
const LOSS_TEXT := {"crushed": "A mite was crushed", "fell": "A mite fell too far", "drowned": "A mite drowned",
		"choked": "A mite choked on fumes", "burned": "A mite burned up", "lava": "A mite fell in lava",
		"steam": "A mite was scalded", "lost": "A mite strayed and was lost"}


# --- Bites -------------------------------------------------------------------------

## The bite a cell is in.
static func bite_of(c: Vector2i) -> Vector2i:
	return Vector2i(c.x >> BSHIFT, c.y >> BSHIFT)


## The cells of a bite.
static func bite_rect(q: Vector2i) -> Rect2i:
	return Rect2i(q * BITE, Vector2i(BITE, BITE))


## A bite's middle, in cells.
static func bite_centre(q: Vector2i) -> Vector2:
	return Vector2(q * BITE) + Vector2(BITE, BITE) * 0.5


## Where to draw a mite (its top-left cell).
static func mite_cell(mt: Dictionary) -> Vector2:
	if mt.body != 0:
		return mt.fp
	return Vector2(mt.p * BITE) + Vector2(0.5, 0.5)


static var _masks := {}


## A byte per material for the engine's counts: "pass" (open to a mite),
## "pass_ember" (with fire too), "hold" (solid, or a building), "liquid", "fire",
## "soft" (what mites dig) and "teeth" (with Hard Teeth).
static func mask(what: String) -> PackedByteArray:
	if not _masks.has(what):
		var out := PackedByteArray()
		out.resize(256)
		for m in 256:
			var hit := false
			match what:
				"pass": hit = passable(m, false)
				"pass_ember": hit = passable(m, true)
				"hold": hit = m == D.BUILDING or (D.is_solid(m) and m != D.MITE)
				"liquid": hit = D.is_liquid(m)
				"fire": hit = m == D.FIRE
				"soft": hit = can_dig(m, false)
				"teeth": hit = can_dig(m, true)
			out[m] = 1 if hit else 0
		_masks[what] = out
	return _masks[what]


# --- Where they dig ------------------------------------------------------------------
# First a half-circle chamber over the Warren (its floor line is the flat side, so
# the ground it stands on stays). Then, with a marker set, a tunnel toward it: each
# free mite takes the bite it can reach that's nearest the marker, give or take a
# quirk of that bite (WARREN_WOBBLE), within WARREN_TUNNEL_SLACK of the straight
# line. Once one gets within reach of the marker, a small circle there.

static func scale(game) -> float:
	return D.WARREN_TEETH_SCALE if game.researched.has("hard_teeth") else 1.0


static func dome_radius(teeth_scale: float) -> float:
	return D.WARREN_DOME_R * teeth_scale


static func dome_centre(b) -> Vector2:
	return Vector2(b.x + b.w * 0.5, b.y + b.h)


## The Warren's own bites (any bite holding a cell of it).
static func home_rect(b) -> Rect2i:
	var q0 := bite_of(Vector2i(b.x, b.y))
	var q1 := bite_of(Vector2i(b.x + b.w - 1, b.y + b.h - 1))
	return Rect2i(q0, q1 - q0 + Vector2i.ONE)


## The chamber: bites whose middle lies above the Warren's floor line within the
## dome's radius of the middle of that line, less the Warren's own bites.
static func dome_bites(b, teeth_scale: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := dome_centre(b)
	var r := dome_radius(teeth_scale)
	var home := home_rect(b)
	var q0 := bite_of(Vector2i(floori(c.x - r), floori(c.y - r)))
	var q1 := bite_of(Vector2i(ceili(c.x + r), b.y + b.h - 1))
	for qy in range(maxi(q0.y, 0), q1.y + 1):
		for qx in range(maxi(q0.x, 0), mini(q1.x, (D.W >> BSHIFT) - 1) + 1):
			var q := Vector2i(qx, qy)
			if home.has_point(q):
				continue
			var m := bite_centre(q)
			if m.y < b.y + b.h and m.distance_to(c) <= r:
				out.append(q)
	return out


## The circle dug out at the marker.
static func marker_bites(b, teeth_scale: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if b.marker.x < 0:
		return out
	var c := Vector2(b.marker) + Vector2(0.5, 0.5)
	var r := D.WARREN_MARKER_R * teeth_scale
	var q0 := bite_of(Vector2i(floori(c.x - r), floori(c.y - r)))
	var q1 := bite_of(Vector2i(ceili(c.x + r), ceili(c.y + r)))
	for qy in range(maxi(q0.y, 0), mini(q1.y, (D.H >> BSHIFT) - 1) + 1):
		for qx in range(maxi(q0.x, 0), mini(q1.x, (D.W >> BSHIFT) - 1) + 1):
			var q := Vector2i(qx, qy)
			if bite_centre(q).distance_to(c) <= r:
				out.append(q)
	return out


static func marker_range(teeth_scale: float) -> float:
	return D.WARREN_MARKER_RANGE * teeth_scale


static func set_marker(b, at: Vector2i) -> void:
	b.marker = at
	b.search = {}
	b.search_due = true
	b.stage = ""


## How far `p` sits from the straight line between the Warren and its marker.
static func off_line(b, p: Vector2) -> float:
	var a: Vector2 = b.center()
	var m := Vector2(b.marker) + Vector2(0.5, 0.5)
	var ab := m - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## A bite's own quirk, 0..1: fixed for that bite and that Warren, so the tunnel
## wanders the same way each time it's searched rather than flickering.
static func quirk(b, q: Vector2i) -> float:
	var h: int = hash(Vector3i(q.x, q.y, b.id))
	return float(h & 0xffff) / 65535.0


## Whether a mite may dig `m`: soft ground, plus stone and glimmer with Hard Teeth.
## Sulfur, never.
static func can_dig(m: int, teeth: bool) -> bool:
	return (D.MITE_SOFT.has(m) or (teeth and D.MITE_HARD.has(m))) and D.bore_rate(m) > 0.0


## Open to a mite: air, harmless gas or water. Fumes, steam and lava are walls to
## it (it goes round what it can see), and so are flames unless it's Ember Brood.
static func passable(m: int, ember := false) -> bool:
	if m == D.FIRE:
		return ember
	if m == D.FUMES or m == D.LAVA or (m >= D.STEAM and m <= D.STEAM_LAST):
		return false
	return D.is_thin(m) or D.is_liquid(m)


## What holds the Warren up, which mites leave alone: the bites of the row right
## under it when anything solid is there, else the bites round it.
static func anchor_bites(sim, b) -> Dictionary:
	var keep := {}
	var home := home_rect(b)
	var under: int = sim.count_in_rect(b.x, b.y + b.h, b.w, 1, mask("hold"))
	if under > 0:
		var qy: int = (b.y + b.h) >> BSHIFT
		for qx in range(home.position.x, home.end.x):
			keep[Vector2i(qx, qy)] = true
			keep[Vector2i(qx, qy + 1)] = true
		return keep
	for qy in range(home.position.y - 1, home.end.y + 1):
		for qx in range(home.position.x - 1, home.end.x + 1):
			if not home.has_point(Vector2i(qx, qy)):
				keep[Vector2i(qx, qy)] = true
	return keep


# --- Search ----------------------------------------------------------------------

## Breadth-first over bites from the Warren's doorstep (walkable bites beside it)
## through walkable bites near the dome, the tunnel's corridor and the marker. A
## bite is walkable when every cell of it is open to a mite and something solid or
## built is in a bite beside it. Returns {"box": the bites searched, "dist": steps
## home per bite of the box (-1 unreached), "prev": the bite one step nearer home,
## "targets": [[dig bite, bite to stand in], ...] best first, "left": bites still to
## dig in the dome and at the marker, "stage": what they're on}.
## Stages: "dome", "tunnel", "marker", "done" (marker dug out), "idle" (dome done,
## no marker), "blocked" (nothing they can reach gets them nearer the marker).
static func search(game, b) -> Dictionary:
	var sim = game.sim
	var teeth: bool = game.researched.has("hard_teeth")
	var sc := scale(game)
	var ember: bool = game.researched.has("ember_brood")
	var sounding: bool = game.researched.has("sounding")
	var home := home_rect(b)
	var dome := dome_bites(b, sc)
	var circle := marker_bites(b, sc)
	var has_marker: bool = b.marker.x >= 0
	var mpos := Vector2(b.marker) + Vector2(0.5, 0.5)
	var reach_r := D.WARREN_MARKER_R * sc + BITE
	# The bites looked at, with a margin for walking round and a bite beyond that
	# for the neighbour counts.
	var box := home
	for q in dome:
		box = box.expand(q)
	if has_marker:
		for q in circle:
			box = box.expand(q)
		var sl := ceili(D.WARREN_TUNNEL_SLACK) >> BSHIFT
		box = box.merge(Rect2i(bite_of(b.marker) - Vector2i(sl, sl), Vector2i(sl * 2 + 1, sl * 2 + 1)))
		box = box.merge(Rect2i(bite_of(Vector2i(b.center())) - Vector2i(sl, sl), Vector2i(sl * 2 + 1, sl * 2 + 1)))
	box = box.grow((D.WARREN_REACH_MARGIN >> BSHIFT) + 1).intersection(Rect2i(0, 0, D.W >> BSHIFT, D.H >> BSHIFT))
	var bw := box.size.x
	var n := bw * box.size.y
	var ox := box.position.x
	var oy := box.position.y
	var pass_n: PackedByteArray = sim.block_counts(ox, oy, bw, box.size.y, mask("pass_ember" if ember else "pass"))
	var hold_n: PackedByteArray = sim.block_counts(ox, oy, bw, box.size.y, mask("hold"))
	var dig_n: PackedByteArray = sim.block_counts(ox, oy, bw, box.size.y, mask("teeth" if teeth else "soft"))
	var wet_n := PackedByteArray()
	if sounding:
		wet_n = sim.block_counts(ox, oy, bw, box.size.y, mask("liquid"))
	var inner := box.grow(-1)
	var walkable := PackedByteArray()
	walkable.resize(n)
	for j in range(1, box.size.y - 1):
		for i in range(1, bw - 1):
			var k := j * bw + i
			if pass_n[k] < 16:
				continue
			for o: Vector2i in N8:
				if hold_n[k + o.y * bw + o.x] > 0:
					walkable[k] = 1
					break
	var keep := anchor_bites(sim, b)
	var skin := ceili(D.WARREN_SKIN / float(BITE))
	var ok := func(q: Vector2i) -> bool:
		if not inner.has_point(q) or keep.has(q):
			return false
		var k := (q.y - oy) * bw + (q.x - ox)
		if dig_n[k] == 0:
			return false
		if sounding:
			for dy in range(-skin, skin + 1):
				for dx in range(-skin, skin + 1):
					var qq := q + Vector2i(dx, dy)
					if box.has_point(qq) and wet_n[(qq.y - oy) * bw + (qq.x - ox)] > 0:
						return false
		return true
	var in_dome := {}
	var in_circle := {}
	var left := 0
	for q in dome:
		if ok.call(q):
			in_dome[q] = true
			left += 1
	for q in circle:
		if ok.call(q):
			in_circle[q] = true
			left += 1
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var queue := PackedInt32Array()
	# The doorstep: walkable bites beside the Warren's own (not at its corners).
	for qy in range(home.position.y - 1, home.end.y + 1):
		for qx in range(home.position.x - 1, home.end.x + 1):
			var q := Vector2i(qx, qy)
			var edge := not home.has_point(q)
			var corner := (qx == home.position.x - 1 or qx == home.end.x) and (qy == home.position.y - 1 or qy == home.end.y)
			if edge and not corner and inner.has_point(q):
				var k := (qy - oy) * bw + (qx - ox)
				if walkable[k] and dist[k] < 0:
					dist[k] = 0
					queue.append(k)
	var dome_t: Array = []
	var tunnel_t: Array = []     # [dig bite, bite to stand in, score, distance to the marker]
	var listed := {}
	var reached := false
	var best_d := INF            # nearest they've got to the marker
	var head := 0
	while head < queue.size():
		var k := queue[head]
		head += 1
		var p := Vector2i(ox + k % bw, oy + floori(k / float(bw)))
		if has_marker:
			var pd := bite_centre(p).distance_to(mpos)
			best_d = minf(best_d, pd)
			if pd <= reach_r:
				reached = true
		for o: Vector2i in N4:
			var q: Vector2i = p + o
			if not inner.has_point(q):
				continue
			if not listed.has(q):
				if in_dome.has(q):
					listed[q] = true
					dome_t.append([q, p])
				elif in_circle.has(q):
					listed[q] = true
					var cd := bite_centre(q).distance_to(mpos)
					tunnel_t.append([q, p, cd, cd])
				elif has_marker and ok.call(q):
					var qc := bite_centre(q)
					if off_line(b, qc) <= D.WARREN_TUNNEL_SLACK:
						listed[q] = true
						var qd := qc.distance_to(mpos)
						tunnel_t.append([q, p, qd + D.WARREN_WOBBLE * quirk(b, q), qd])
			var kq := k + o.y * bw + o.x
			if dist[kq] >= 0 or not walkable[kq]:
				continue
			dist[kq] = dist[k] + 1
			prev[kq] = k
			queue.append(kq)
	var targets: Array = []
	var stage := "idle"
	if not dome_t.is_empty():
		targets = dome_t
		stage = "dome"
	elif has_marker and reached:
		# There: the circle, and whatever still stands between them and it.
		targets = tunnel_t.filter(func(e: Array) -> bool: return e[3] <= reach_r)
		targets.sort_custom(func(u: Array, v: Array) -> bool: return u[3] < v[3])
		stage = "marker" if not targets.is_empty() else "done"
	elif has_marker:
		# On the way: nothing much further from the marker than they've already got,
		# so a wall they can't cut stops them instead of setting them hollowing out
		# everything round it.
		targets = tunnel_t.filter(func(e: Array) -> bool: return e[3] <= best_d + D.WARREN_DETOUR)
		targets.sort_custom(func(u: Array, v: Array) -> bool: return u[2] < v[2])
		stage = "tunnel" if not targets.is_empty() else "blocked"
	return {"box": box, "dist": dist, "prev": prev, "targets": targets, "left": left, "stage": stage}


## Steps home from bite `q` in a search (-1: it didn't reach there).
static func home_dist(found: Dictionary, q: Vector2i) -> int:
	var box: Rect2i = found.box
	if not box.has_point(q):
		return -1
	return found.dist[(q.y - box.position.y) * box.size.x + (q.x - box.position.x)]


## The way from the doorstep to `stand`, doorstep first.
static func path_to(found: Dictionary, stand: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var box: Rect2i = found.box
	var bw := box.size.x
	var k := (stand.y - box.position.y) * bw + (stand.x - box.position.x)
	while k >= 0:
		path.append(Vector2i(box.position.x + k % bw, box.position.y + floori(k / float(bw))))
		k = found.prev[k]
	path.reverse()
	return path


## A doorstep bite for a new mite, or (-1, -1) if the Warren is walled in.
static func doorstep(b) -> Vector2i:
	var found: Dictionary = b.search
	if found.is_empty():
		return Vector2i(-1, -1)
	var box: Rect2i = found.box
	var dist: PackedInt32Array = found.dist
	for k in dist.size():
		if dist[k] == 0:
			return Vector2i(box.position.x + k % box.size.x, box.position.y + floori(k / float(box.size.x)))
	return Vector2i(-1, -1)


# --- Mites ------------------------------------------------------------------------

static func new_mite(at: Vector2i) -> Dictionary:
	return {"p": at, "state": S_HOME, "t": Vector2i(-1, -1), "path": [], "i": 0, "move": 0.0,
			"work": 0.0, "load": {}, "burst": 0, "wet": 0.0, "choke": 0.0, "burn": 0.0, "lost": 0.0,
			"body": 0, "fp": Vector2.ZERO, "fate": ""}


## How many mites this Warren keeps.
static func colony_size(game) -> int:
	return D.WARREN_MITES_EMBER if game.researched.has("ember_brood") else D.WARREN_MITES


## One tick of a built Warren and its colony.
static func tick(game, b) -> void:
	b.starved = false
	if b.falling:
		return
	b.search_t += D.DT
	if b.search.is_empty() or b.search_t >= SEARCH_EVERY or (b.search_due and b.search_t >= SEARCH_SOON):
		b.search = search(game, b)
		b.zone_left = b.search.left
		b.stage = b.search.stage
		b.search_t = 0.0
		b.search_due = false
	# Breeding: the first colony comes with the build; replacements cost Stone.
	if not b.bred:
		var door := doorstep(b)
		if door.x >= 0:
			for _j in colony_size(game):
				b.mites.append(new_mite(door))
			b.bred = true
	elif b.mites.size() < colony_size(game):
		b.breed_t += D.DT
		if b.breed_t >= D.WARREN_BREED_S and b.connected and game.stock[D.R_STONE] >= D.WARREN_BREED_COST:
			var door := doorstep(b)
			if door.x >= 0:
				game.stock[D.R_STONE] -= D.WARREN_BREED_COST
				b.mites.append(new_mite(door))
				b.breed_t = 0.0
	var claimed := {}
	for mt: Dictionary in b.mites:
		if mt.state == S_OUT or mt.state == S_DIG:
			claimed[mt.t] = true
	var i: int = b.mites.size() - 1
	while i >= 0:
		var mt: Dictionary = b.mites[i]
		var death := _fly(game, b, mt) if mt.body != 0 else _hazards(game, mt)
		if death == "" and mt.body == 0:
			_step(game, b, mt, claimed)
			if not _gripping(game.sim, mt.p):
				loosen(game, mt, Vector2.ZERO)
		if death != "":
			if mt.body != 0:
				game.sim.remove_body(mt.body)
				game.mite_bodies.erase(mt.body)
			b.mites.remove_at(i)
			b.mites_lost += 1
			b.last_loss = death
			var text: String = LOSS_TEXT.get(death, "A mite died")
			if b.mites.is_empty():
				text += "; the colony is gone (a new mite every %d s while linked, for Stone)" % int(D.WARREN_BREED_S)
			game.alert("info", text, b.center())
		i -= 1


## Whatever is killing it, or "". What's at the middle of its bite is what it's in.
## Rock moving in (a body) crushes it, or with too little weight squeezes it into an
## open bite beside it.
static func _hazards(game, mt: Dictionary) -> String:
	var sim = game.sim
	var c := Vector2i(bite_centre(mt.p))
	var other: int = sim.get_owner(c.x, c.y)
	if other != 0:
		if game.body_momentum(other) >= D.MITE_CRUSH:
			return "crushed"
		for o: Vector2i in N8:
			if _open(sim, mt.p + o, game.researched.has("ember_brood")):
				mt.p = mt.p + o
				if mt.state != S_HOME:
					mt.state = S_BACK
				return ""
		return "crushed"
	var m: int = sim.get_cell(c.x, c.y)
	if m == D.LAVA:
		return "lava"
	if m >= D.STEAM and m <= D.STEAM_LAST:
		return "steam"
	if not (D.is_thin(m) or D.is_liquid(m)):
		return "crushed"
	mt.wet = mt.wet + D.DT if D.is_liquid(m) else 0.0
	if mt.wet >= D.MITE_DROWN_S:
		return "drowned"
	mt.choke = mt.choke + D.DT if m == D.FUMES else 0.0
	if mt.choke >= D.MITE_CHOKE_S:
		return "choked"
	if mt.lost >= LOST_S:
		return "lost"
	if mt.state == S_PANIC:
		mt.burn -= D.DT
		if mt.burn <= 0.0:
			return "burned"
	elif not game.researched.has("ember_brood"):
		var r := bite_rect(mt.p).grow(1)
		if sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask("fire")) > 0:
			mt.state = S_PANIC
			mt.burn = D.MITE_BURN_S
			mt.load = {}
	return ""


## Every cell of the bite open to a mite.
static func _open(sim, q: Vector2i, ember: bool) -> bool:
	var r := bite_rect(q)
	return sim.count_in_rect(r.position.x, r.position.y, BITE, BITE, mask("pass_ember" if ember else "pass")) == BITE * BITE


## Bites it may move this tick.
static func _moves(mt: Dictionary) -> int:
	mt.move = mt.move + D.MITE_MOVE_PER_S * D.DT / BITE
	var n := floori(mt.move)
	mt.move -= n
	return n


## The next bite of a burst: the nearest one still to dig that nobody has claimed,
## within BURST_HOP bites of `q` (the bite just eaten) or `p` (where it stands).
static func _next_bite(found: Dictionary, q: Vector2i, p: Vector2i, claimed: Dictionary) -> Array:
	var best: Array = []
	var best_d := BURST_HOP + 1
	for tg: Array in found.targets:
		var c: Vector2i = tg[0]
		if claimed.has(c) or c == q:
			continue
		var dq := (c - q).abs()
		var dp := (c - p).abs()
		var d := mini(maxi(dq.x, dq.y), maxi(dp.x, dp.y))
		if d < best_d:
			best_d = d
			best = tg
	return best


static func _step(game, b, mt: Dictionary, claimed: Dictionary) -> void:
	var sim = game.sim
	var found: Dictionary = b.search
	var ember: bool = game.researched.has("ember_brood")
	match mt.state:
		S_HOME:
			if not b.enabled or found.is_empty():
				return
			for tg: Array in found.targets:
				var c: Vector2i = tg[0]
				if claimed.has(c):
					continue
				mt.t = c
				mt.path = path_to(found, tg[1])
				mt.i = 0
				mt.p = mt.path[0]
				mt.burst = 0
				mt.state = S_OUT
				claimed[c] = true
				return
		S_OUT:
			for _k in _moves(mt):
				if mt.i >= mt.path.size() - 1:
					mt.state = S_DIG
					mt.work = 0.0
					break
				var nx: Vector2i = mt.path[mt.i + 1]
				if not _open(sim, nx, ember):
					mt.state = S_BACK
					b.search_due = true
					break
				mt.i += 1
				mt.p = nx
		S_DIG:
			_nibble(game, b, mt, claimed)
		S_BACK:
			for _k in _moves(mt):
				var p: Vector2i = mt.p
				if home_dist(found, p) == 0:
					_arrive(game, b, mt)
					return
				var best := p
				var best_d: int = home_dist(found, p)
				if best_d < 0:
					best_d = 1 << 30
				for o: Vector2i in N4:
					var q: Vector2i = p + o
					var d := home_dist(found, q)
					if d >= 0 and d < best_d and _open(sim, q, ember):
						best_d = d
						best = q
				if best == p:
					# Off the known map (the ground moved, or it's in a bite it just
					# dug): wait for the next search.
					mt.lost += D.DT
					b.search_due = true
					return
				mt.lost = 0.0
				mt.p = best
		S_PANIC:
			for _k in _moves(mt):
				var opts: Array[Vector2i] = []
				for o: Vector2i in N8:
					var q: Vector2i = mt.p + o
					if q.x < 0 or q.y < 0 or q.x >= D.W >> BSHIFT or q.y >= D.H >> BSHIFT:
						continue
					if _open(sim, q, true):
						opts.append(q)
					else:
						var c := Vector2i(bite_centre(q))
						sim.ignite(c.x, c.y)
				if not opts.is_empty():
					mt.p = opts[game.rng.randi() % opts.size()]


## Nibble the target bite, a cell at a time; when it's done, go on to a bite beside
## it (up to MITE_BURST bites a trip) or head home with the load.
static func _nibble(game, b, mt: Dictionary, claimed: Dictionary) -> void:
	var sim = game.sim
	var q: Vector2i = mt.t
	var teeth: bool = game.researched.has("hard_teeth")
	mt.work = minf(mt.work + D.DT, 4.0)
	var r := bite_rect(q)
	var any := false
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			var m: int = sim.get_cell(xx, yy)
			if not can_dig(m, teeth):
				continue
			any = true
			var cost := 1.0 / (D.bore_rate(m) * D.MITE_SPEED)
			if mt.work < cost:
				return
			var pc: float = D.power_per_cell(m) * D.WARREN_POWER_FRAC
			if b.power < pc:
				b.starved = true
				return
			mt.work -= cost
			b.power -= pc
			game.used_acc += pc
			sim.set_cell(xx, yy, D.AIR)
			game.excavated(Vector2i(xx, yy))
			mt.load[m] = mt.load.get(m, 0) + 1
			b.cells_dug += 1
			game.cells_drilled += 1
	if any:
		# Everything it can take here went this tick; look again next tick.
		return
	# The bite is done.
	game.reveal(bite_centre(q), REVEAL_R)
	b.search_due = true
	mt.burst += 1
	if mt.burst < D.MITE_BURST and not b.search.is_empty():
		var tg := _next_bite(b.search, q, mt.p, claimed)
		if not tg.is_empty():
			var c: Vector2i = tg[0]
			var stand: Vector2i = tg[1]
			if (stand - mt.p).abs().x <= BURST_HOP and (stand - mt.p).abs().y <= BURST_HOP:
				mt.p = stand     # hop to where that bite is dug from
			elif _open(sim, q, game.researched.has("ember_brood")):
				mt.p = q         # or into the bite it just ate
			claimed.erase(q)
			claimed[c] = true
			mt.t = c
			mt.work = 0.0
			return
	mt.state = S_BACK


## Home with its load: bank it here (the nearest Cache in reach, else the Hub).
static func _arrive(game, b, mt: Dictionary) -> void:
	for m: int in mt.load:
		for r: int in D.mat_yields(m):
			game._bank(b.center(), r, mt.load[m] / D.CELLS_PER_UNIT)
	mt.load = {}
	mt.state = S_HOME
	mt.t = Vector2i(-1, -1)


# --- As a body ----------------------------------------------------------------------

## Something solid or built within MITE_GRIP bites of this one to cling to.
static func _gripping(sim, q: Vector2i) -> bool:
	var r := bite_rect(q).grow(BITE * D.MITE_GRIP)
	return sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask("hold")) > 0


## Physics takes the mite: it becomes a body at the foot of its bite moving at `v`
## (cells a second). Nothing happens if there's no room for it there.
static func loosen(game, mt: Dictionary, v: Vector2) -> void:
	if mt.body != 0:
		return
	var sim = game.sim
	var at := Vector2i(mt.p * BITE) + Vector2i(0, BITE - D.MITE_SIZE)
	if sim.count_in_rect(at.x, at.y, D.MITE_SIZE, D.MITE_SIZE, mask("pass_ember")) < D.MITE_SIZE * D.MITE_SIZE:
		return
	for yy in range(at.y, at.y + D.MITE_SIZE):
		for xx in range(at.x, at.x + D.MITE_SIZE):
			sim.set_cell(xx, yy, D.MITE)
	var id: int = sim.make_body(at.x, at.y, D.MITE_SIZE, D.MITE_SIZE, v.x, v.y, 0.0)
	if id < 0:
		for yy in range(at.y, at.y + D.MITE_SIZE):
			for xx in range(at.x, at.x + D.MITE_SIZE):
				sim.set_cell(xx, yy, D.AIR)
		return
	sim.set_creature(id, true)
	if mt.state == S_OUT or mt.state == S_DIG:
		mt.state = S_BACK       # its bite is someone else's now
	mt.body = id
	mt.fp = Vector2(at)
	mt.fate = ""
	game.mite_bodies[id] = mt


## A mite that's a body: gone if the body is (shattered by its own fall, or crushed:
## the reason is in mt.fate); walking again once it's lain still a third of a second.
static func _fly(game, b, mt: Dictionary) -> String:
	var sim = game.sim
	var st: PackedFloat32Array = sim.body_state(mt.body)
	if st.is_empty():
		game.mite_bodies.erase(mt.body)
		mt.body = 0
		return mt.fate if mt.fate != "" else "fell"
	var half := D.MITE_SIZE * 0.5
	mt.fp = Vector2(st[0] - half, st[1] - half)
	if mt.state == S_PANIC:
		mt.burn -= D.DT
		if mt.burn <= 0.0:
			return "burned"
	if st[8] < 20.0:
		return ""
	sim.remove_body(mt.body)
	game.mite_bodies.erase(mt.body)
	mt.body = 0
	mt.p = bite_of(Vector2i(floori(st[0]), floori(st[1])))
	if mt.state != S_PANIC and (mt.state != S_HOME or not mt.load.is_empty()):
		mt.state = S_BACK       # wherever it was going, it has to find its way again
	mt.path = []
	mt.lost = 0.0
	b.search_due = true
	return ""
