extends Node2D
## Everything drawn on top of the terrain, in screen space so lines and text stay
## crisp at any zoom: links, buildings, packets and the placement ghost (modules draw
## themselves through machines.gd).

const D = preload("res://scripts/defs.gd")
const Building = preload("res://scripts/building.gd")
const MC = preload("res://scripts/machines/machines.gd")
const InteriorLayer = preload("res://scripts/interior_layer.gd")

const LINK_COL := Color(0.55, 0.78, 1.0, 0.32)
const TREE_COL := Color(0.62, 0.84, 1.0, 0.55)
const OK_COL := Color(0.45, 0.95, 0.55)
const BAD_COL := Color(1.0, 0.35, 0.3)
const SEL_COL := Color(1.0, 0.86, 0.35)
const SPRING_COL := Color(0.45, 0.75, 1.0)
const WORN_COL := Color(1.0, 0.5, 0.18, 0.9)

var game: Node2D
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	var inside := InteriorLayer.new()
	inside.game = game
	add_child(inside)


func _draw() -> void:
	var g = game
	if g == null or g.sim == null:
		return
	var z: float = g.zoom
	var vs := get_viewport_rect().size
	var screen := Rect2(Vector2.ZERO, vs)
	var t := Time.get_ticks_msec() * 0.001

	if g.show_network:
		_draw_ranges(g, z, screen)
	_draw_springs(g, z, t, screen)
	_draw_links(g, z)
	for b: Building in g.buildings:
		_draw_building(g, b, z, t, screen)
	_draw_packets(g, z)
	_draw_plans(g, z)
	MC.draw(self, g, z)
	if g.selected != null and not g.selected.dead:
		var s: Building = g.selected
		_draw_rect_outline(_brect(g, s, z).grow(2.0), SEL_COL, 2.0)
		if s.type == D.B_BRACE:
			_draw_holds(g, [s.anchor_a, s.anchor_b], z, Color(D.B_COLORS[D.B_BRACE], 0.5))
	elif g.tool_type < 0 and not g.brush_mode:
		var hb: Building = g.building_at(g.hover)
		if hb != null:
			_draw_rect_outline(_brect(g, hb, z).grow(1.0), Color(1, 1, 1, 0.35), 1.0)
	if g.tool_type >= 0:
		_draw_ghost(g, z)
	if g.demolish_target != null:
		var p: float = clampf(g.demolish_hold / 0.6, 0.0, 1.0)
		draw_arc(g.mouse_screen, 16.0, -PI * 0.5, -PI * 0.5 + TAU * p, 32, BAD_COL, 3.0)
		_draw_rect_outline(_brect(g, g.demolish_target, z).grow(2.0), BAD_COL, 2.0)
	if g.brush_mode and g.hover.x >= 0:
		draw_arc(g.to_screen(Vector2(g.hover) + Vector2(0.5, 0.5)), (g.brush_r + 0.5) * z, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 1.0)
		if g.brush_material() == g.BRUSH_BLAST:
			draw_arc(g.to_screen(Vector2(g.hover) + Vector2(0.5, 0.5)), D.BLAST_RADIUS * z, 0.0, TAU, 48, Color(1.0, 0.6, 0.3, 0.8), 1.0)
		_label(g.mouse_screen + Vector2(18, -8), "Brush: " + g.brush_name(), Color.WHITE, 13)


func _brect(g, b: Building, z: float) -> Rect2:
	return Rect2(g.to_screen(Vector2(b.x, b.y)), Vector2(b.w, b.h) * z)


# --- Network -----------------------------------------------------------------------

func _draw_links(g, z: float) -> void:
	for b: Building in g.buildings:
		if b.link == null or b.type == D.B_CRUCIBLE and not b.connected:
			continue
		var a: Vector2 = g.to_screen(b.center())
		var c: Vector2 = g.to_screen(b.link.center())
		var col := TREE_COL if b.active_relay else LINK_COL
		var w := 1.5 if b.active_relay and z >= 3.0 else 1.0
		# A worn link turns orange as it weakens.
		var hp: float = g.link_health(b, b.link)
		if hp < 1.0:
			col = WORN_COL.lerp(col, hp)
			w = maxf(w, 1.5)
		draw_line(a, c, col, w)
	# Broken links: dashed red, crossed out in the middle, until a Stone mends them.
	for key: int in g.broken_links:
		var ends: Array = g.link_ends.get(key, [])
		if ends.size() < 2:
			continue
		var a: Vector2 = g.to_screen(ends[0].center())
		var c: Vector2 = g.to_screen(ends[1].center())
		draw_dashed_line(a, c, Color(BAD_COL, 0.8), 1.0, maxf(3.0, z))
		var m := (a + c) * 0.5
		var s := maxf(3.0, z * 0.9 * D.S)
		draw_line(m + Vector2(-s, -s), m + Vector2(s, s), BAD_COL, 1.5)
		draw_line(m + Vector2(-s, s), m + Vector2(s, -s), BAD_COL, 1.5)


func _draw_ranges(g, z: float, screen: Rect2) -> void:
	for rl: Building in g.relays:
		var c: Vector2 = g.to_screen(rl.center())
		if not screen.grow(D.RELAY_RANGE * z).has_point(c):
			continue
		var col := Color(0.5, 0.8, 1.0, 0.18) if rl.connected else Color(1, 0.4, 0.3, 0.25)
		draw_arc(c, D.relay_range(rl.type) * z, 0.0, TAU, 64, col, 1.0)
		draw_arc(c, D.LINK_RANGE * z, 0.0, TAU, 48, Color(col, col.a * 0.6), 1.0)


## Springs you've found: a slow blue pulse where the water comes from.
func _draw_springs(g, z: float, t: float, screen: Rect2) -> void:
	for c: Vector2i in g.info.get("springs", []):
		if not g.is_known(c.x, c.y):
			continue
		var p: Vector2 = g.to_screen(Vector2(c) + Vector2(0.5, 0.5))
		if not screen.grow(20.0 + 4.0 * D.S * z).has_point(p):
			continue
		var ph := fmod(t * 0.8 + c.x * 0.37, 1.0)
		draw_arc(p, maxf(2.0, z * 0.8 * D.S) + ph * z * 3.0 * D.S, 0.0, TAU, 24, Color(SPRING_COL, 0.7 * (1.0 - ph)), 1.0)
		draw_circle(p, maxf(1.5, z * 0.5 * D.S), Color(SPRING_COL, 0.9))


func _draw_packets(g, z: float) -> void:
	var s := maxf(3.0, z * 0.7 * D.S)
	for p in g.packets:
		var c: Vector2 = g.to_screen(p.pos)
		var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
		draw_rect(r, D.RES_COLORS[p.res])


# --- Buildings -----------------------------------------------------------------------

func _draw_building(g, b: Building, z: float, t: float, screen: Rect2) -> void:
	var r := _brect(g, b, z)
	if not r.grow(60.0).intersects(screen):
		return
	if b.type == D.B_CRUCIBLE:
		_draw_crucible(g, b, r, z, t)
		return
	var col: Color = D.B_COLORS[b.type]
	var lw := 2.0 if z >= 3.0 else 1.0
	if not b.built:
		draw_rect(r, Color(col, 0.10))
		var p := b.progress()
		if p > 0.0:
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * p, r.size.x, r.size.y * p), Color(col, 0.30))
		_dashed_outline(r, Color(col, 0.95), 1.0)
	elif b.type == D.B_BRACE:
		_draw_brace(r, col, z, b.horizontal)
	elif b.type == D.B_BULKHEAD:
		draw_rect(r, Color(0.23, 0.25, 0.30))
		draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, z * 0.6))), Color(0.40, 0.43, 0.50))
		_draw_rect_outline(r, Color(0.12, 0.13, 0.16), 1.0)
	else:
		draw_rect(r, Color(0.07, 0.08, 0.11, 0.94))
		_draw_rect_outline(r, col, lw)

	var letter: String = D.B_LETTERS[b.type]
	if letter != "":
		var fs := int(clampf(minf(r.size.x, r.size.y) * 0.72, 9.0, 22.0))
		if b.type == D.B_HUB:
			fs = int(clampf(r.size.y * 0.42, 10.0, 22.0))
		var tc := col if b.built else Color(col, 0.8)
		draw_string(font, Vector2(r.position.x, r.get_center().y + fs * 0.36), letter,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, tc)

	# Feedback
	if b.flash > 0.0:
		draw_rect(r, Color(1.0, 1.0, 1.0, clampf(b.flash, 0.0, 0.5) * 0.6))
	if b.type != D.B_HUB and not b.connected and D.needs_link(b.type):
		var blink := 0.5 + 0.5 * sin(t * 7.0)
		_draw_rect_outline(r.grow(1.0), Color(BAD_COL, 0.35 + 0.5 * blink), 1.0)
		_draw_broken_link(r.position + Vector2(r.size.x, 0.0), 6.0, Color(BAD_COL, 0.5 + 0.5 * blink))
	elif b.drowned:
		var blink := 0.5 + 0.5 * sin(t * 5.0)
		_draw_rect_outline(r.grow(1.0), Color(0.4, 0.7, 1.0, 0.4 + 0.5 * blink), 1.0)
		_label_center(r.position + Vector2(r.size.x * 0.5, -6.0), "~", Color(0.5, 0.8, 1.0), 14)
	if b.hp < b.max_hp:
		var f := clampf(b.hp / b.max_hp, 0.0, 1.0)
		var bar := Rect2(r.position + Vector2(0, -5), Vector2(r.size.x, 3))
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, 3)), Color(1.0 - f, 0.2 + 0.7 * f, 0.25))


func _draw_crucible(g, b: Building, r: Rect2, z: float, t: float) -> void:
	var seen: bool = g.is_known(int(b.center().x), int(b.center().y))
	var a := 1.0 if seen else 0.45
	var gold := Color(0.95, 0.72, 0.30, a)
	var u := r.size / Vector2(20.0, 12.0)
	var o := r.position
	var bowl := PackedVector2Array([
		o + Vector2(0, 1) * u, o + Vector2(20, 1) * u, o + Vector2(18, 5) * u,
		o + Vector2(15, 10) * u, o + Vector2(13, 12) * u, o + Vector2(7, 12) * u,
		o + Vector2(5, 10) * u, o + Vector2(2, 5) * u])
	var charge: float = g.crucible_charge()
	var body := Color(0.20, 0.14, 0.08, a)
	if g.cstate == 2:
		body = Color(1.0, 0.85, 0.45, 1.0)
	draw_colored_polygon(bowl, body)
	if g.cstate == 1 and charge > 0.0:
		var level := 12.0 - 10.0 * charge
		var inner := PackedVector2Array([
			o + Vector2(3.5, level) * u, o + Vector2(16.5, level) * u,
			o + Vector2(14.5, 10.5) * u, o + Vector2(5.5, 10.5) * u])
		var pulse := 0.75 + 0.25 * sin(t * 4.0)
		draw_colored_polygon(inner, Color(1.0, 0.5 + 0.3 * charge, 0.12, 0.85 * pulse))
	var closed := bowl.duplicate()
	closed.append(bowl[0])
	draw_polyline(closed, gold, 2.0 if z >= 3.0 else 1.0)
	draw_line(o + Vector2(-1, 1) * u, o + Vector2(21, 1) * u, gold, 2.0)
	if g.cstate == 2:
		for k in 12:
			var ang := TAU * k / 12.0 + t * 0.3
			var c := r.get_center()
			draw_line(c + Vector2.from_angle(ang) * r.size.x * 0.6, c + Vector2.from_angle(ang) * r.size.x * (0.8 + 0.1 * sin(t * 3.0 + k)), Color(1.0, 0.85, 0.4, 0.8), 2.0)
	elif g.cstate == 1:
		var ring := r.size.x * (0.62 + 0.04 * sin(t * 3.0))
		draw_arc(r.get_center(), ring, 0.0, TAU, 64, Color(1.0, 0.6, 0.2, 0.35 + 0.4 * charge), 2.0)
	if not b.connected and g.cstate != 2 and seen:
		_label_center(Vector2(r.get_center().x, r.position.y - 8.0), "Link a Node within %d cells" % int(D.LINK_RANGE), Color(1, 0.85, 0.5, 0.8), 12)


# --- Sensors and ghost ------------------------------------------------------------------


func _draw_ghost(g, z: float) -> void:
	var type: int = g.tool_type
	if type == D.B_BRACE:
		_draw_brace_ghost(g, z)
		return
	if type != D.B_BULKHEAD and g.drag_from.x >= 0 and g.dragged_line(g.drag_from, g.hover):
		var pts: Array = g.line_points(type, g.drag_from, g.hover, g.tool_horizontal)
		var col: Color = D.B_COLORS[type]
		for c: Vector2i in pts:
			var fr: Rect2i = g.footprint(type, c, g.tool_horizontal)
			var pr := Rect2(g.to_screen(Vector2(fr.position)), Vector2(fr.size) * z)
			draw_rect(pr, Color(col, 0.18))
			_dashed_outline(pr, Color(col, 0.8), 1.0)
		_label(g.mouse_screen + Vector2(18, 10), "%d %s%s: %s each" % [pts.size(), D.B_NAMES[type], "" if pts.size() == 1 else "s",
				_cost_text(type)], Color(0.85, 0.9, 1.0), 12)
		return
	if type == D.B_BULKHEAD and g.drag_from.x >= 0:
		var rects: Array = g.bulkhead_line(g.drag_from, g.hover)
		var ok: Array = g.bulkhead_valid(rects)
		for k in rects.size():
			var rr: Rect2i = rects[k]
			var br := Rect2(g.to_screen(Vector2(rr.position)), Vector2(rr.size) * z)
			var bc := OK_COL if ok[k] else BAD_COL
			draw_rect(br, Color(bc, 0.25))
			_draw_rect_outline(br, bc, 1.0)
		return
	var r: Rect2i = g.snap_place(type, g.hover, g.tool_horizontal)
	var why: String = g.check_place(type, r, type != D.B_BULKHEAD)
	# Snapped away from the cursor: a faint mark where the cursor is.
	if r != g.footprint(type, g.hover, g.tool_horizontal):
		_draw_cell_box(g, g.hover, z, Color(OK_COL, 0.35))
	if type == D.B_BULKHEAD and why == "" and not g.touches_solid(r):
		why = "Must touch rock"
	var c := OK_COL if why == "" else BAD_COL
	var sr := Rect2(g.to_screen(Vector2(r.position)), Vector2(r.size) * z)
	var center := Vector2(r.position) + Vector2(r.size) * 0.5
	# Ranges of nearby relays, so it's clear where the network reaches.
	var relay := D.is_relay_type(type)
	for rl: Building in g.relays:
		var reach: float = maxf(D.relay_range(type), D.relay_range(rl.type)) if relay else D.LINK_RANGE
		if rl.connected and rl.center().distance_to(center) < reach + 30.0:
			draw_arc(g.to_screen(rl.center()), reach * z, 0.0, TAU, 64, Color(0.5, 0.8, 1.0, 0.25), 1.0)
	var link: Building = g.find_link(type, r)
	if link != null:
		draw_dashed_line(g.to_screen(center), g.to_screen(link.center()), Color(0.6, 0.85, 1.0, 0.8), 1.0, 3.0)
	draw_rect(sr, Color(c, 0.22))
	_draw_rect_outline(sr, c, 1.0)
	var letter: String = D.B_LETTERS[type]
	if letter != "":
		var fs := int(clampf(minf(sr.size.x, sr.size.y) * 0.72, 9.0, 22.0))
		draw_string(font, Vector2(sr.position.x, sr.get_center().y + fs * 0.36), letter,
				HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, fs, Color(c, 0.9))
	var cost_txt := _cost_text(type)
	if why != "":
		_label(g.mouse_screen + Vector2(18, 10), why, BAD_COL, 13)
	else:
		_label(g.mouse_screen + Vector2(18, 10), cost_txt, Color(0.85, 0.9, 1.0), 12)


## Buildings a dragged line has yet to lay: dashed outlines where they'll go.
func _draw_plans(g, z: float) -> void:
	for p: Dictionary in g.plans:
		var fr: Rect2i = g.footprint(p["type"], p["at"], p["horiz"])
		var pr := Rect2(g.to_screen(Vector2(fr.position)), Vector2(fr.size) * z)
		var col: Color = D.B_COLORS[p["type"]]
		draw_rect(pr, Color(col, 0.08))
		_dashed_outline(pr, Color(col, 0.55), 1.0)


## A Brace: a pale beam with cross-braces every couple of cells.
func _draw_brace(r: Rect2, col: Color, z: float, flat: bool) -> void:
	draw_rect(r, Color(col.darkened(0.55), 0.95))
	var len_px := r.size.x if flat else r.size.y
	var th := r.size.y if flat else r.size.x
	var step := maxf(z * 2.0, 4.0)
	var k := 0.0
	while k < len_px - 0.5:
		var k2 := minf(k + step, len_px)
		if flat:
			draw_line(Vector2(r.position.x + k, r.end.y), Vector2(r.position.x + k2, r.position.y), Color(col, 0.9), 1.0)
		else:
			draw_line(Vector2(r.position.x, r.position.y + k), Vector2(r.end.x, r.position.y + k2), Color(col, 0.9), 1.0)
		k = k2
	_draw_rect_outline(r, Color(col, 0.95), 1.0)
	if th >= 3.0:
		draw_line(r.position, r.position + (Vector2(r.size.x, 0.0) if flat else Vector2(0.0, r.size.y)), Color(col.lightened(0.3), 0.8), 1.0)


## The ground a Brace holds: a ring round each anchor.
func _draw_holds(g, ends: Array, z: float, col: Color) -> void:
	for c: Vector2i in ends:
		if c.x >= 0:
			draw_arc(g.to_screen(Vector2(c) + Vector2(0.5, 0.5)), (D.BRACE_HOLD + 0.5) * z, 0.0, TAU, 40, col, 1.0)
			_draw_cell_box(g, c, z, col)


## Placing a Brace: the gap it would span through the cursor, its anchors and holds.
func _draw_brace_ghost(g, z: float) -> void:
	var r: Rect2i = g.brace_rect(g.hover, g.tool_horizontal)
	var why: String = g.check_brace(r)
	var c := OK_COL if why == "" else BAD_COL
	if r.size.x > 0 and r.size.y > 0:
		var shown := r
		if maxi(r.size.x, r.size.y) > D.BRACE_MAX:
			shown = Rect2i(g.hover, Vector2i.ONE)
		var sr := Rect2(g.to_screen(Vector2(shown.position)), Vector2(shown.size) * z)
		draw_rect(sr, Color(c, 0.25))
		_draw_rect_outline(sr, c, 1.0)
		if shown == r:
			_draw_holds(g, g.brace_anchors(r), z, Color(c, 0.5))
	else:
		_draw_cell_box(g, g.hover, z, Color(c, 0.6))
	var txt := why if why != "" else "%s, %d cells" % [_cost_text(D.B_BRACE), maxi(r.size.x, r.size.y)]
	_label(g.mouse_screen + Vector2(18, 10), txt, BAD_COL if why != "" else Color(0.85, 0.9, 1.0), 13 if why != "" else 12)


func _cost_text(type: int) -> String:
	var parts: Array = []
	var cost: Array = D.B_COSTS[type]
	for r in D.NRES:
		if cost[r] > 0:
			parts.append("%d %s" % [cost[r], D.RES_NAMES[r]])
	return ", ".join(parts)


# --- Little drawing helpers ------------------------------------------------------------

func _draw_rect_outline(r: Rect2, col: Color, w: float) -> void:
	draw_rect(r, col, false, w)


func _dashed_outline(r: Rect2, col: Color, w: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	draw_dashed_line(a, b, col, w, 4.0)
	draw_dashed_line(b, c, col, w, 4.0)
	draw_dashed_line(c, d, col, w, 4.0)
	draw_dashed_line(d, a, col, w, 4.0)


func _draw_cell_box(g, c: Vector2i, z: float, col: Color) -> void:
	_draw_rect_outline(Rect2(g.to_screen(Vector2(c)), Vector2(z, z)).grow(1.0), col, 1.0)


func _draw_broken_link(p: Vector2, s: float, col: Color) -> void:
	draw_circle(p, s, Color(0.1, 0.02, 0.02, 0.85))
	draw_arc(p, s, 0.0, TAU, 16, col, 1.5)
	draw_line(p + Vector2(-s * 0.6, s * 0.6), p + Vector2(s * 0.6, -s * 0.6), col, 1.5)


func _label(p: Vector2, text: String, col: Color, size: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_rect(Rect2(p + Vector2(-4, -size), Vector2(w + 8, size + 6)), Color(0.03, 0.03, 0.05, 0.85))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _label_center(p: Vector2, text: String, col: Color, size: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, p - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
