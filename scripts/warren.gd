extends RefCounted
## The Warren's mites (phase 7). Static helpers the game calls with itself as
## `game`; each mite is a Dictionary, so a colony is a plain Array on the Warren.
##
## They dig a half-circle chamber over the Warren, then tunnel toward its marker
## (if one's set) by a simple rule, and hollow out a small circle there. One
## breadth-first search from the Warren's doorstep finds what they can reach and
## the way to it. Mites never dig what holds the Warren up; if the ground goes
## anyway, the Warren falls like any building.

const D = preload("res://scripts/defs.gd")

const S_HOME := 0       # on the doorstep, waiting for work or power
const S_OUT := 1        # walking its path to a cell
const S_DIG := 2        # digging it
const S_BACK := 3       # hauling it home
const S_PANIC := 4      # alight and running

const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const SEARCH_EVERY := 1.0   # seconds between searches when nothing has changed
const SEARCH_SOON := 0.2    # soonest a search reruns after a dig
const LOST_S := 8.0         # a mite that can't find its way home this long is gone
const REVEAL_R := 3.0       # fog a mite clears where it digs
const LOSS_TEXT := {"crushed": "A mite was crushed", "drowned": "A mite drowned",
		"choked": "A mite choked on fumes", "burned": "A mite burned up", "lava": "A mite fell in lava",
		"steam": "A mite was scalded", "lost": "A mite strayed and was lost"}


# --- Where they dig ------------------------------------------------------------------
# First a half-circle chamber over the Warren (its floor line is the flat side, so
# the ground it stands on stays). Then, with a marker set, a tunnel toward it: each
# free mite takes the cell it can reach that's nearest the marker, give or take a
# quirk of that cell (WARREN_WOBBLE), within WARREN_TUNNEL_SLACK of the straight
# line. Once one gets within reach of the marker, a small circle there.

static func scale(game) -> float:
	return D.WARREN_TEETH_SCALE if game.researched.has("hard_teeth") else 1.0


static func dome_radius(teeth_scale: float) -> float:
	return D.WARREN_DOME_R * teeth_scale


static func dome_centre(b) -> Vector2:
	return Vector2(b.x + b.w * 0.5, b.y + b.h)


## The chamber: cells above the Warren's floor line within the dome's radius of
## the middle of that line, less the Warren itself; clipped to the map.
static func dome_cells(b, teeth_scale: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := dome_centre(b)
	var r := dome_radius(teeth_scale)
	var ri := ceili(r)
	for yy in range(b.y + b.h - ri, b.y + b.h):
		for xx in range(floori(c.x) - ri, ceili(c.x) + ri + 1):
			if xx >= b.x and xx < b.x + b.w and yy >= b.y:
				continue
			if xx < 1 or xx >= D.W - 1 or yy < 1:
				continue
			if Vector2(xx + 0.5, yy + 0.5).distance_to(c) <= r:
				out.append(Vector2i(xx, yy))
	return out


## The circle dug out at the marker.
static func marker_cells(b, teeth_scale: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if b.marker.x < 0:
		return out
	var c := Vector2(b.marker) + Vector2(0.5, 0.5)
	var r := D.WARREN_MARKER_R * teeth_scale
	var ri := ceili(r)
	for yy in range(b.marker.y - ri, b.marker.y + ri + 1):
		for xx in range(b.marker.x - ri, b.marker.x + ri + 1):
			if xx >= 1 and xx < D.W - 1 and yy >= 1 and yy < D.H - 1 and Vector2(xx + 0.5, yy + 0.5).distance_to(c) <= r:
				out.append(Vector2i(xx, yy))
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


## A cell's own quirk, 0..1: fixed for that cell and that Warren, so the tunnel
## wanders the same way each time it's searched rather than flickering.
static func quirk(b, p: Vector2i) -> float:
	var h: int = hash(Vector3i(p.x, p.y, b.id))
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


## A cell a mite can stand in: passable, with something solid or built touching it.
static func walkable(sim, c: Vector2i, ember := false) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= D.W or c.y >= D.H:
		return false
	if not passable(sim.get_cell(c.x, c.y), ember):
		return false
	for o: Vector2i in N8:
		var n := c + o
		if n.x < 0 or n.y < 0 or n.x >= D.W or n.y >= D.H:
			return true             # the map's edge holds it
		var m: int = sim.get_cell(n.x, n.y)
		if m == D.BUILDING or D.is_solid(m):
			return true
	return false


## Liquid beside `c` (up, down, left or right): Sounding leaves a skin there.
static func by_liquid(sim, c: Vector2i) -> bool:
	for o: Vector2i in N4:
		var n := c + o
		if n.x >= 0 and n.y >= 0 and n.x < D.W and n.y < D.H and D.is_liquid(sim.get_cell(n.x, n.y)):
			return true
	return false


## What holds the Warren up, which mites leave alone: the solid cells under it,
## or, when nothing is under it, every solid cell touching it (corners count).
static func anchor_cells(sim, b) -> Dictionary:
	var keep := {}
	var fy: int = b.y + b.h
	for xx in range(b.x, b.x + b.w):
		if D.is_solid(sim.get_cell(xx, fy)):
			keep[Vector2i(xx, fy)] = true
	if not keep.is_empty():
		return keep
	for yy in range(b.y - 1, b.y + b.h + 1):
		for xx in range(b.x - 1, b.x + b.w + 1):
			var ring: bool = xx == b.x - 1 or xx == b.x + b.w or yy == b.y - 1 or yy == b.y + b.h
			if ring and D.is_solid(sim.get_cell(xx, yy)):
				keep[Vector2i(xx, yy)] = true
	return keep


# --- Search ----------------------------------------------------------------------

## Breadth-first from the Warren's doorstep (walkable cells touching its
## footprint) over walkable cells near the dome, the tunnel's corridor and the
## marker. Returns {"dist": {cell: steps}, "prev": {cell: cell toward home},
## "targets": [[dig cell, cell to stand in], ...] best first, "left": cells still
## to dig in the dome and at the marker, "stage": what they're on}.
## Stages: "dome", "tunnel", "marker", "done" (marker dug out), "idle" (dome done,
## no marker), "blocked" (nothing they can reach gets them nearer the marker).
static func search(game, b) -> Dictionary:
	var sim = game.sim
	var teeth: bool = game.researched.has("hard_teeth")
	var sc := scale(game)
	var ember: bool = game.researched.has("ember_brood")
	var sounding: bool = game.researched.has("sounding")
	var keep := anchor_cells(sim, b)
	var ok := func(q: Vector2i) -> bool:
		return can_dig(sim.get_cell(q.x, q.y), teeth) and not keep.has(q) and not (sounding and by_liquid(sim, q))
	var in_dome := {}
	var in_circle := {}
	var box := Rect2i(b.x, b.y, b.w, b.h)
	var left := 0
	for p in dome_cells(b, sc):
		box = box.expand(p)
		if ok.call(p):
			in_dome[p] = true
			left += 1
	var has_marker: bool = b.marker.x >= 0
	var mpos := Vector2(b.marker) + Vector2(0.5, 0.5)
	var reach_r := D.WARREN_MARKER_R * sc + 1.0
	if has_marker:
		for p in marker_cells(b, sc):
			box = box.expand(p)
			if ok.call(p):
				in_circle[p] = true
				left += 1
		var sl := ceili(D.WARREN_TUNNEL_SLACK)
		box = box.merge(Rect2i(b.marker - Vector2i(sl, sl), Vector2i(sl * 2 + 1, sl * 2 + 1)))
		box = box.merge(Rect2i(Vector2i(b.center()) - Vector2i(sl, sl), Vector2i(sl * 2 + 1, sl * 2 + 1)))
	box = box.grow(D.WARREN_REACH_MARGIN).intersection(Rect2i(1, 1, D.W - 2, D.H - 2))
	var dist := {}
	var prev := {}
	var queue: Array[Vector2i] = []
	for yy in range(b.y - 1, b.y + b.h + 1):
		for xx in range(b.x - 1, b.x + b.w + 1):
			var edge: bool = xx == b.x - 1 or xx == b.x + b.w or yy == b.y - 1 or yy == b.y + b.h
			var corner: bool = (xx == b.x - 1 or xx == b.x + b.w) and (yy == b.y - 1 or yy == b.y + b.h)
			var p := Vector2i(xx, yy)
			if edge and not corner and walkable(sim, p, ember):
				dist[p] = 0
				queue.append(p)
	var dome_t: Array = []
	var tunnel_t: Array = []     # [dig cell, cell to stand in, score, distance to the marker]
	var listed := {}
	var reached := false
	var best_d := INF            # nearest they've got to the marker
	var head := 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if has_marker:
			var pd := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(mpos)
			best_d = minf(best_d, pd)
			if pd <= reach_r:
				reached = true
		for o: Vector2i in N4:
			var q: Vector2i = p + o
			if not listed.has(q):
				if in_dome.has(q):
					listed[q] = true
					dome_t.append([q, p])
				elif in_circle.has(q):
					listed[q] = true
					var cd := (Vector2(q) + Vector2(0.5, 0.5)).distance_to(mpos)
					tunnel_t.append([q, p, cd, cd])
				elif has_marker and box.has_point(q) and ok.call(q):
					var qc := Vector2(q) + Vector2(0.5, 0.5)
					if off_line(b, qc) <= D.WARREN_TUNNEL_SLACK:
						listed[q] = true
						var qd := qc.distance_to(mpos)
						tunnel_t.append([q, p, qd + D.WARREN_WOBBLE * quirk(b, q), qd])
			if dist.has(q) or not box.has_point(q) or not walkable(sim, q, ember):
				continue
			dist[q] = dist[p] + 1
			prev[q] = p
			queue.append(q)
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
	return {"dist": dist, "prev": prev, "targets": targets, "left": left, "stage": stage}


## The way from the doorstep to `stand`, doorstep first.
static func path_to(found: Dictionary, stand: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var p := stand
	var prev: Dictionary = found.prev
	path.append(p)
	while prev.has(p):
		p = prev[p]
		path.append(p)
	path.reverse()
	return path


# --- Mites ------------------------------------------------------------------------

static func new_mite(at: Vector2i) -> Dictionary:
	return {"p": at, "state": S_HOME, "t": Vector2i(-1, -1), "path": [], "i": 0, "move": 0.0,
			"work": 0.0, "load": -1, "wet": 0.0, "choke": 0.0, "burn": 0.0, "lost": 0.0}


## How many mites this Warren keeps.
static func colony_size(game) -> int:
	return D.WARREN_MITES_EMBER if game.researched.has("ember_brood") else D.WARREN_MITES


## A doorstep cell for a new mite, or (-1, -1) if the Warren is walled in.
static func doorstep(b) -> Vector2i:
	var found: Dictionary = b.search
	for p: Vector2i in found.get("dist", {}):
		if found.dist[p] == 0:
			return p
	return Vector2i(-1, -1)


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
		var death := _hazards(game, mt)
		if death == "":
			_step(game, b, mt, claimed)
		else:
			b.mites.remove_at(i)
			b.mites_lost += 1
			b.last_loss = death
			var text: String = LOSS_TEXT.get(death, "A mite died")
			if b.mites.is_empty():
				text += "; the colony is gone (a new mite every %d s while linked, for Stone)" % int(D.WARREN_BREED_S)
			game.alert("info", text, b.center())
		i -= 1


## Whatever is killing it, or "".
static func _hazards(game, mt: Dictionary) -> String:
	var sim = game.sim
	var p: Vector2i = mt.p
	var m: int = sim.get_cell(p.x, p.y)
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
	elif (m == D.FIRE or _near(sim, p, D.FIRE)) and not game.researched.has("ember_brood"):
		mt.state = S_PANIC
		mt.burn = D.MITE_BURN_S
		mt.load = -1
	return ""


static func _near(sim, p: Vector2i, want: int) -> bool:
	for o: Vector2i in N8:
		var n := p + o
		if n.x >= 0 and n.y >= 0 and n.x < D.W and n.y < D.H and sim.get_cell(n.x, n.y) == want:
			return true
	return false


## Cells it may move this tick.
static func _moves(mt: Dictionary) -> int:
	mt.move = mt.move + D.MITE_MOVE_PER_S * D.DT
	var n := floori(mt.move)
	mt.move -= n
	return n


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
				var cost: float = D.power_per_cell(sim.get_cell(c.x, c.y)) * D.WARREN_POWER_FRAC
				if b.power < cost:
					b.starved = true
					return
				mt.t = c
				mt.path = path_to(found, tg[1])
				mt.i = 0
				mt.p = mt.path[0]
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
				if not walkable(sim, nx, ember):
					mt.state = S_BACK
					b.search_due = true
					break
				mt.i += 1
				mt.p = nx
		S_DIG:
			var c: Vector2i = mt.t
			var m: int = sim.get_cell(c.x, c.y)
			var teeth: bool = game.researched.has("hard_teeth")
			if not can_dig(m, teeth) or (game.researched.has("sounding") and by_liquid(sim, c)):
				mt.state = S_BACK
				b.search_due = true
				return
			mt.work = minf(mt.work + D.DT, 4.0)
			if mt.work < 1.0 / (D.bore_rate(m) * D.MITE_SPEED):
				return
			var cost: float = D.power_per_cell(m) * D.WARREN_POWER_FRAC
			if b.power < cost:
				b.starved = true
				return
			b.power -= cost
			game.used_acc += cost
			sim.set_cell(c.x, c.y, D.AIR)
			game.excavated(c)
			game.reveal(Vector2(c) + Vector2(0.5, 0.5), REVEAL_R)
			mt.load = m
			b.cells_dug += 1
			game.cells_drilled += 1
			b.search_due = true
			mt.state = S_BACK
		S_BACK:
			for _k in _moves(mt):
				var p: Vector2i = mt.p
				if found.dist.get(p, -1) == 0:
					_arrive(game, b, mt)
					return
				var best := p
				var best_d: int = found.dist.get(p, 1 << 30)
				for o: Vector2i in N4:
					var q: Vector2i = p + o
					var d: int = found.dist.get(q, 1 << 30)
					if d < best_d and walkable(sim, q, ember):
						best_d = d
						best = q
				if best == p:
					# Off the known map (the ground moved): wait for the next search.
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
					if q.x >= 0 and q.y >= 0 and q.x < D.W and q.y < D.H:
						var m: int = sim.get_cell(q.x, q.y)
						if walkable(sim, q, true):
							opts.append(q)
						elif not (D.is_thin(m) or D.is_liquid(m)):
							sim.ignite(q.x, q.y)
				if not opts.is_empty():
					mt.p = opts[game.rng.randi() % opts.size()]


## Home with its load: bank it here (the nearest Cache in reach, else the Hub).
static func _arrive(game, b, mt: Dictionary) -> void:
	if mt.load >= 0:
		for r: int in D.mat_yields(mt.load):
			game._bank(b.center(), r, 1.0 / D.CELLS_PER_UNIT)
		mt.load = -1
	mt.state = S_HOME
	mt.t = Vector2i(-1, -1)
