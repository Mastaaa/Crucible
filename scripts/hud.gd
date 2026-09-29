extends CanvasLayer
## The interface, built in code: resource bar, build palette, building panel,
## alert log, depth ruler, Crucible panel, help and win screens.

const D = preload("res://scripts/defs.gd")
const Building = preload("res://scripts/building.gd")

const GOLD := Color(0.96, 0.76, 0.36)
const CARD_W := 232.0             # research card width
const DIM := Color(0.66, 0.70, 0.78)
const KIND_COLORS := {
	"water_breach": Color(0.45, 0.72, 1.0), "lava_breach": Color(1.0, 0.5, 0.25),
	"steam": Color(0.9, 0.92, 1.0), "lava": Color(1.0, 0.45, 0.3),
	"destroyed": Color(1.0, 0.4, 0.35), "link": Color(1.0, 0.55, 0.45),
	"drowned": Color(0.45, 0.7, 1.0), "tremor": Color(1.0, 0.7, 0.35),
	"crucible": GOLD, "info": DIM, "research": Color(0.9, 0.62, 0.86),
	"fire": Color(1.0, 0.62, 0.3), "corrosion": Color(0.85, 0.85, 0.35), "blast": Color(1.0, 0.7, 0.4),
	"link_broken": Color(1.0, 0.5, 0.4), "discovery": Color(0.95, 0.9, 0.55),
	"loose": Color(0.95, 0.75, 0.5), "cavein": Color(0.9, 0.68, 0.45), "crush": Color(1.0, 0.58, 0.4),
}


class Ruler extends Control:
	## Depth ruler on the right edge, doubling as a minimap: layers, your network,
	## recent alerts, the current view and the deepest building.
	const D = preload("res://scripts/defs.gd")
	const BX := 6.0
	const BW := 30.0
	var game: Node

	func _draw() -> void:
		if game == null or game.sim == null:
			return
		var font := ThemeDB.fallback_font
		var top := 10.0
		var bottom := size.y - 10.0
		var s := (bottom - top) / D.H
		var sx := BW / D.W
		for layer: Dictionary in D.LAYERS:
			var y0: float = top + layer["top"] * s
			var y1: float = top + layer["bottom"] * s
			draw_rect(Rect2(BX, y0, BW, y1 - y0), Color(layer["color"], 0.45))
			draw_string(font, Vector2(BX + BW + 5.0, y0 + 12.0), layer["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))
		# the Crucible, once it has been seen
		var cr: Rect2i = game.crucible.rect()
		if game.is_known(cr.get_center().x, cr.get_center().y):
			draw_rect(Rect2(BX + cr.position.x * sx, top + cr.position.y * s, maxf(cr.size.x * sx, 2.0), maxf(cr.size.y * s, 2.0)), Color(1.0, 0.85, 0.4))
		# your network
		for b in game.buildings:
			if b.type == D.B_CRUCIBLE:
				continue
			var col := Color(0.55, 0.8, 1.0) if D.is_conduit(b.type) else Color(1.0, 0.72, 0.4)
			if b.type == D.B_HUB:
				col = Color(1.0, 0.85, 0.4)
			if not b.built:
				col.a = 0.45
			draw_rect(Rect2(BX + b.x * sx - 0.5, top + b.y * s - 0.5, maxf(b.w * sx, 1.5), maxf(b.h * s, 1.5)), col)
		# alerts from the last 30 seconds
		var now: float = game.game_time
		for a: Dictionary in game.alerts:
			var age: float = now - a["t"]
			if age > 30.0 or a["kind"] == "info" or a["kind"] == "crucible":
				continue
			var p := Vector2(BX + a["x"] * sx, top + a["y"] * s)
			var pulse := 0.6 + 0.4 * sin(now * 6.0)
			draw_circle(p, 3.0, Color(1.0, 0.35, 0.3, pulse * (1.0 - age / 30.0)))
		# the view window
		var half: float = game._half_view_cols()
		var vx0: float = BX + clampf(game.cam_x - half, 0.0, D.W) * sx
		var vx1: float = BX + clampf(game.cam_x + half, 0.0, D.W) * sx
		var vy0: float = top + clampf(game.cam_y, 0.0, D.H) * s
		var vy1: float = top + clampf(game.cam_y + game.view_rows(), 0.0, D.H) * s
		draw_rect(Rect2(vx0, vy0, maxf(vx1 - vx0, 2.0), maxf(vy1 - vy0, 2.0)), Color(1, 1, 1, 0.9), false, 1.0)
		# deepest building
		var db = game.deepest_building()
		var dy: float = top + (db.y + db.h) * s
		var tri := PackedVector2Array([Vector2(BX - 6.0, dy - 4.0), Vector2(BX, dy), Vector2(BX - 6.0, dy + 4.0)])
		draw_colored_polygon(tri, Color(0.5, 1.0, 0.7))
		draw_string(font, Vector2(BX + BW + 5.0, dy + 4.0), "%d" % (db.y + db.h), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.75))

	func _gui_input(event: InputEvent) -> void:
		var pressed := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pressed = true
		if pressed and game != null:
			var top := 10.0
			var s := (size.y - 20.0) / D.H
			var wx := clampf((event.position.x - BX) / BW * D.W, 0.0, D.W)
			game.jump_to(clampf((event.position.y - top) / s, 0.0, D.H), wx)
			accept_event()


var game: Node
var root: Control
var alerts_dirty := true
var info_for: Building = null
var info_refreshers: Array = []

var res_labels: Array = []
var hub_label: Label
var speed_label: Label
var time_label: Label
var seed_label: Label
var cursor_label: Label
var build_buttons: Array = []
var left_col: VBoxContainer
var info_panel: PanelContainer
var info_box: VBoxContainer
var alert_panel: PanelContainer
var alert_box: VBoxContainer
var ruler: Ruler
var crucible_panel: PanelContainer
var c_lines: Array = []
var c_activate: Button
var c_bar: ProgressBar
var c_status: Label
var banner_panel: PanelContainer
var banner: Label
var help_panel: PanelContainer
var win_panel: PanelContainer
var win_label: Label
var perf_label: Label
var breach_check: CheckBox
var research_button: Button
var research_panel: PanelContainer
var research_head: Label
var research_cards := {}          # tech id -> {"button", "state", "bar", "mats"}
var tier_notes: Array = []        # Label per tier (index 1..4)
var card_plain: StyleBoxFlat
var card_current: StyleBoxFlat


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_bar()
	_build_left()
	_build_alerts()
	_build_ruler()
	_build_crucible_panel()
	_build_banner()
	_build_help()
	_build_research()
	_build_win()
	perf_label = Label.new()
	perf_label.visible = false
	perf_label.add_theme_font_size_override("font_size", 12)
	perf_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_anchor(perf_label, 1.0, 0.0, 1.0, 0.0, -360, 44, -100, 110)
	root.add_child(perf_label)


func apply_layout(vs: Vector2, ui_scale: float) -> void:
	scale = Vector2(ui_scale, ui_scale)
	root.position = Vector2.ZERO
	root.size = vs / ui_scale


func on_new_game() -> void:
	info_for = null
	alerts_dirty = true
	if win_panel:
		win_panel.visible = false


# --- Construction ---------------------------------------------------------------

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.055, 0.075, 0.9)
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(5)
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	th.set_stylebox("panel", "PanelContainer", panel)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.12, 0.135, 0.17)
	n.set_corner_radius_all(4)
	n.content_margin_left = 8
	n.content_margin_right = 8
	n.content_margin_top = 4
	n.content_margin_bottom = 4
	var hv := n.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.17, 0.19, 0.24)
	var pr := n.duplicate() as StyleBoxFlat
	pr.bg_color = Color(0.30, 0.24, 0.12)
	pr.border_color = GOLD
	pr.set_border_width_all(1)
	var ds := n.duplicate() as StyleBoxFlat
	ds.bg_color = Color(0.09, 0.09, 0.11)
	th.set_stylebox("normal", "Button", n)
	th.set_stylebox("hover", "Button", hv)
	th.set_stylebox("pressed", "Button", pr)
	th.set_stylebox("hover_pressed", "Button", pr)
	th.set_stylebox("disabled", "Button", ds)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	# Build palette buttons: the same look, less padding, so nine fit above the panel.
	th.set_type_variation("PaletteButton", "Button")
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := th.get_stylebox(st, "Button").duplicate() as StyleBoxFlat
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		th.set_stylebox(st, "PaletteButton", sb)
	th.set_color("font_color", "Button", Color(0.88, 0.9, 0.95))
	th.set_color("font_pressed_color", "Button", Color(1.0, 0.92, 0.7))
	th.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.92, 0.7))
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.52))
	th.set_color("font_color", "Label", Color(0.88, 0.9, 0.95))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.13)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.55, 0.15)
	fill.set_corner_radius_all(3)
	th.set_stylebox("background", "ProgressBar", bg)
	th.set_stylebox("fill", "ProgressBar", fill)
	return th


func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	return b


func _label(text: String, size := 14, col := Color(0.88, 0.9, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	_anchor(bar, 0.0, 0.0, 1.0, 0.0, 0, 0, 0, 34)
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	bar.add_child(hb)
	for r in D.NRES:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = D.RES_COLORS[r]
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(sw)
		var l := _label("", 14)
		l.custom_minimum_size.x = 152 if r == D.R_POWER else 84
		box.add_child(l)
		res_labels.append(l)
		hb.add_child(box)
		if r == D.R_POWER:
			box.tooltip_text = "Power held at the Hub and in Caches and Waterwheels, then made and used per second. The Hub makes 2/s on its own."
		else:
			box.tooltip_text = "%s held at the Hub and in Caches." % D.RES_NAMES[r]
	hub_label = _label("", 14, DIM)
	hb.add_child(hub_label)
	speed_label = _label("", 14)
	hb.add_child(speed_label)
	time_label = _label("", 14, DIM)
	hb.add_child(time_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	cursor_label = _label("", 13, DIM)
	hb.add_child(cursor_label)
	research_button = _button("T  Research")
	research_button.custom_minimum_size.x = 176
	research_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	research_button.clip_text = true
	research_button.pressed.connect(toggle_research)
	hb.add_child(research_button)
	var help := _button("F1  Help")
	help.pressed.connect(toggle_help)
	hb.add_child(help)


func _build_left() -> void:
	left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	_anchor(left_col, 0.0, 0.0, 0.0, 0.0, 8, 42, 236, 42)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left_col)
	var bp := PanelContainer.new()
	left_col.add_child(bp)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	bp.add_child(vb)
	vb.add_child(_label("Build", 13, GOLD))
	for k in D.PALETTE.size():
		var type: int = D.PALETTE[k]
		var cost: Array = D.B_COSTS[type]
		var parts: Array = []
		for r in D.NRES:
			if cost[r] > 0:
				parts.append("%d %s" % [cost[r], D.RES_NAMES[r]])
		var b := _button("%s  %s   %s" % [D.PALETTE_KEYS[k], D.B_NAMES[type], ", ".join(parts)])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.theme_type_variation = "PaletteButton"
		b.tooltip_text = D.B_BLURBS[type]
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void:
			if game.tool_type == type:
				game.cancel_tool()
			else:
				game.select_tool(type))
		vb.add_child(b)
		build_buttons.append(b)
	info_panel = PanelContainer.new()
	info_panel.visible = false
	left_col.add_child(info_panel)
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 5)
	info_panel.add_child(info_box)


func _build_alerts() -> void:
	alert_panel = PanelContainer.new()
	_anchor(alert_panel, 0.0, 1.0, 0.0, 1.0, 8, -126, 380, -8)
	root.add_child(alert_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	alert_panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_child(_label("Alerts   (click to look)", 13, GOLD))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	seed_label = _label("", 12, Color(0.5, 0.53, 0.6))
	head.add_child(seed_label)
	vb.add_child(head)
	alert_box = VBoxContainer.new()
	alert_box.add_theme_constant_override("separation", 0)
	vb.add_child(alert_box)


func _build_ruler() -> void:
	var panel := PanelContainer.new()
	_anchor(panel, 1.0, 0.0, 1.0, 1.0, -118, 42, -8, -8)
	root.add_child(panel)
	ruler = Ruler.new()
	ruler.game = game
	ruler.custom_minimum_size = Vector2(90, 100)
	ruler.mouse_filter = Control.MOUSE_FILTER_STOP
	ruler.tooltip_text = "Minimap: click to jump there"
	panel.add_child(ruler)


func _build_crucible_panel() -> void:
	crucible_panel = PanelContainer.new()
	crucible_panel.visible = false
	_anchor(crucible_panel, 1.0, 1.0, 1.0, 1.0, -336, -226, -100, -8)
	root.add_child(crucible_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	crucible_panel.add_child(vb)
	vb.add_child(_label("The Crucible", 15, GOLD))
	for r in [D.R_OBSIDIAN, D.R_GLIMMER, D.R_WATER]:
		var l := _label("", 13)
		l.add_theme_color_override("font_color", D.RES_COLORS[r])
		vb.add_child(l)
		c_lines.append([r, l])
	c_bar = ProgressBar.new()
	c_bar.min_value = 0.0
	c_bar.max_value = 100.0
	c_bar.custom_minimum_size = Vector2(200, 16)
	c_bar.show_percentage = true
	c_bar.add_theme_font_size_override("font_size", 11)
	vb.add_child(c_bar)
	c_status = _label("", 12, DIM)
	c_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_status.custom_minimum_size = Vector2(210, 0)
	vb.add_child(c_status)
	c_activate = _button("Activate")
	c_activate.pressed.connect(func() -> void: game.activate_crucible())
	vb.add_child(c_activate)


func _build_banner() -> void:
	banner_panel = PanelContainer.new()
	banner_panel.visible = false
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(banner_panel, 0.5, 0.0, 0.5, 0.0, -300, 44, 300, 78)
	root.add_child(banner_panel)
	banner = _label("", 14, Color(1.0, 0.93, 0.8))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_panel.add_child(banner)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.visible = false
	_anchor(help_panel, 0.5, 0.5, 0.5, 0.5, -330, -330, 330, 330)
	root.add_child(help_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	help_panel.add_child(vb)
	vb.add_child(_label("Crucible", 20, GOLD))
	# Everything between the title and the buttons scrolls, so the panel fits a 720-tall window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(640, 540)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	var goal := _label("Build self-running machinery down through the world and light the Crucible at the bottom. You never dig yourself: buildings do. Blueprints fill up as packets of material arrive from the Hub along your Conduits.", 13, DIM)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.custom_minimum_size = Vector2(620, 0)
	body.add_child(goal)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	body.add_child(grid)
	var rows := [
		["Mouse wheel, W / S", "Scroll up and down (middle-drag pans)"],
		["A / D, Shift + wheel", "Pan sideways"],
		["Ctrl + wheel, + / -", "Zoom in and out"],
		["1 - 9, 0, B, M, G, X", "Pick a building from the Build list"],
		["R", "Turn a Borer, Floodgate or Strut before placing it"],
		["Left click", "Place; drag to lay Bulkheads; click a building for its settings"],
		["Drag a Thumper", "Move it anywhere open; let go mid-swing to throw it (not too hard into rock)"],
		["Right click", "Cancel placement; hold on a building to demolish it (50% back)"],
		["Space / Tab", "Pause / cycle 1x, 2x and 4x speed"],
		["T", "Research: pick what the Labs work on"],
		["N", "Network overlay: ranges and links"],
		["Home / End", "Jump to the Hub / your deepest building"],
		["F5 / Shift+F5", "Restart this seed / new seed"],
		["F9, [ ]", "Sandbox brush: materials, Coal, Sulfur, Fire, Blast (right-drag erases)"],
		["F3 / F10 / F11", "Performance / reveal the map / fullscreen"],
	]
	for row in rows:
		grid.add_child(_label(row[0], 13, GOLD))
		grid.add_child(_label(row[1], 13))
	var tips := _label(("Conduits link within %d cells (Relay Masts %d); everything else must sit within %d of one. " % [int(D.RELAY_RANGE), int(D.MAST_RANGE), int(D.LINK_RANGE)]) + "A Conduit under water stops relaying, and lava destroys it.\n\nUnderground is dark. Sunlight falls straight down open shafts, lava, fire and glimmer glow, and every machine carries a small light; a Lamp lights %d cells, and rock casts shadows. What's lit near your buildings gets explored; explored ground shows live while it's lit and as you last saw it when it isn't.\n\nEverything you build needs rock, or a building that's held up, touching it (corners count). Dig that away and it falls until it lands on something, off the network on the way down; a long fall hurts it (water breaks the fall). When placing, the outline snaps to the nearest spot within %d cells that touches rock.\n\n" % [int(D.LIGHT_LAMP), D.PLACE_SNAP] + "Machines run on power: each keeps a small reserve and the network refills it by packet, from the nearest Hub, Cache or Waterwheel that has some. A machine with an empty reserve stops where it stands. The Hub makes 2 power/s on its own; a Waterwheel makes more from water falling through it, a Steam Turbine from steam rising through it, and springs keep aquifers topped up. Caches hold power and materials out at the front and keep a cut-off stretch running for a while.\n\n" + "Labs turn power into research (T); new tiers open as you find Glimmer, lava and the Crucible. Upgrades come in levels, each dearer than the last.\n\nThe Drill beside the Hub bores a 30-wide shaft straight down on its own; Drill Bit and Drill Shaft research make it faster and deeper, down to the bedrock over the chamber. A Thumper blasts the ground under it every few seconds and throws itself up; what it breaks flies as rubble for Hoppers to catch, and its blasts hurt anything of yours nearby. A Borer tunnels the way it's pointed until its power runs out or it meets bedrock, a building or a lava body; out past the network it runs on its reserve, so lay Conduits behind it (Homing brings it back to recharge). Obsidian stops the Drill and Borers until the Obsidian Saw.\n\n" + ("From about %d down the rock is hot. It stops the Drill and Borers until the Coolant Jacket, and then each pays 1 Water per %d cells of it, sent to it by packet; the water goes up behind it as steam, which scalds Conduits and can turn a Steam Turbine. Mites dig it with Ember Brood. Water boils on hot rock, and enough of it slowly quenches the rock to stone.\n\n" % [D.HOT_TOP, roundi(1.0 / D.COOLANT_WATER_PER_CELL)]) + ("A Warren's mites hollow out a chamber over it, then tunnel toward the marker you set in its panel, finding their own way, and dig out a small circle there, carrying each cell home to bank. They dig whatever is in their way, even the wall between them and an aquifer, until Sounding, but never what holds the Warren up. They cling to any surface; when their hold goes they drop, and a blast throws them (a long fall kills one). Water drowns them, fumes choke them, lava and steam kill them, falling rock crushes them, and one that catches fire runs about lighting things until it burns out. A lost mite is replaced every %d s for a Stone. Freshly dug ground settles for %d s before it can crumble or slide, so there's time to prop a new hole up.\n\n" % [int(D.WARREN_BREED_S), int(D.SETTLE_S)]) + "Coal banks Stone and Power when dug, and burns: lava or flames light it, and fire needs air, so a buried or flooded seam goes out. Sulfur banks Stone and Glimmer, but it eats buildings and links a few cells off and burns into fumes that sink and pool. Fire, sulfur and lava wear links down; a broken one drops out of the network until a Stone arrives to mend it, and worn links and damaged buildings ask for their Stone on their own. Ceilings shed the odd cell, dirt far more often than stone.\n\n" + ("Every kind of ground has a span: the widest gap it can roof over (gravel 40, dirt 70, coal and sulfur 90, clay 110, stone 150, packed dirt 240; glimmer, obsidian and bedrock any). Open up a room wider than that and its ceiling breaks off from the middle in slabs that tumble down and shatter into rubble, until what's left is an arch or its own rubble props it (over a crawlspace it crumbles instead). Falling rock hurts what it hits by its weight and speed, cuts links it falls through and crushes mites, and the rubble can bury whatever is under it. Rock, rubble and buildings under a ceiling all hold it up; water doesn't. A Strut (X) spans a gap up to %d cells, rock to rock, flat or upright: it props whatever rests on it, and nothing within %d cells of either end caves in or crumbles. It costs %d Stone from the Hub, goes up at once and needs no link or upkeep, but it snaps if either end loses its rock. With Tremor Dampers, the Crucible's tremors spare stone within %d cells of a Strut.\n\nGround differs. Gravel comes down fast, coal twice as fast as dirt, packed dirt hardly ever. Stone hangs only from stone: a lump held up by dirt alone drops once it's undermined. Sand pours the moment it's opened up. Water slowly wears stone into dirt and dirt into sand, and carries sand off; gravel and clay shrug it off, and clay lines the aquifers.\n\n" % [D.STRUT_MAX, D.STRUT_HOLD, D.B_COSTS[D.B_STRUT][0], int(D.STRUT_DAMP_R)]) + "The Crucible wants %d Obsidian (water on lava, then cut or blast the crust), %d Glimmer and %d Water, delivered while it charges, and draws %d power/s the whole time. Keep it fed and powered or the charge drains." % [D.RECIPE[D.R_OBSIDIAN], D.RECIPE[D.R_GLIMMER], D.RECIPE[D.R_WATER], int(D.CRUCIBLE_POWER_PER_S)], 13, DIM)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size = Vector2(620, 0)
	body.add_child(tips)
	breach_check = CheckBox.new()
	breach_check.text = "Pause the first time a Drill or Borer breaks into water, and again for lava"
	breach_check.focus_mode = Control.FOCUS_NONE
	breach_check.add_theme_font_size_override("font_size", 13)
	breach_check.button_pressed = true
	breach_check.toggled.connect(func(on: bool) -> void: game.pause_on_breach = on)
	vb.add_child(breach_check)
	var close := _button("Close  (Esc)")
	close.pressed.connect(toggle_help)
	vb.add_child(close)


func _build_research() -> void:
	card_plain = _card_style(Color(1, 1, 1, 0.06))
	card_current = _card_style(GOLD)
	research_panel = PanelContainer.new()
	research_panel.visible = false
	_anchor(research_panel, 0.5, 0.0, 0.5, 1.0, -508, 42, 508, -8)
	root.add_child(research_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	research_panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	head.add_child(_label("Research", 20, GOLD))
	research_head = _label("", 13, DIM)
	research_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	research_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	research_head.clip_text = true
	head.add_child(research_head)
	var close := _button("Close  (T)")
	close.pressed.connect(toggle_research)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	scroll.add_child(cols)
	# Four columns: Tier 1, Tier 2, Tiers 3 and 4 stacked (4 has one tech), then the
	# upgrades, whose levels open tier by tier.
	tier_notes = [null, null, null, null, null]
	for group: Array in [[1], [2], [3, 4], [0]]:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = CARD_W + 4
		col.add_theme_constant_override("separation", 5)
		cols.add_child(col)
		for tier: int in group:
			if tier == 4:
				var gap := Control.new()
				gap.custom_minimum_size.y = 6
				col.add_child(gap)
			col.add_child(_label("Tier %d" % tier if tier > 0 else "Upgrades", 15, GOLD))
			var note := _label("", 11, DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(CARD_W, 0)
			col.add_child(note)
			tier_notes[tier] = note
			for t: Dictionary in D.TECHS:
				if t.has("levels") == (tier == 0) and (tier == 0 or t["tier"] == tier):
					col.add_child(_tech_card(t))


func _card_style(border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.085, 0.095, 0.125)
	st.border_color = border
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


func _tech_card(t: Dictionary) -> Control:
	var id: String = t["id"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", card_plain)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var btn := _button(t["name"])
	btn.toggle_mode = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.theme_type_variation = "PaletteButton"
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(func() -> void:
		if game.current_tech == id:
			game.current_tech = ""
		else:
			game.pick_research(id)
		_refresh_research())
	v.add_child(btn)
	var desc := _label(t["text"], 11, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_W - 14, 0)
	v.add_child(desc)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(CARD_W - 14, 5)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	v.add_child(bar)
	var state := _label("", 11, DIM)
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.custom_minimum_size = Vector2(CARD_W - 14, 0)
	v.add_child(state)
	research_cards[id] = {"card": card, "button": btn, "bar": bar, "state": state}
	return card


## "Drill Bit 2/5   260 power, 8 Glimmer": a card's button, with what's next.
func _tech_title(id: String) -> String:
	var g = game
	var t: Dictionary = g.tech(id)
	var txt: String = t["name"]
	if t.has("levels"):
		txt += "  %d/%d" % [g.level(id), g.tech_levels(id)]
	var st: Dictionary = g.tech_step(id)
	if not st.is_empty():
		txt += "   " + _tech_cost_text(st)
	return txt


func _tech_cost_text(t: Dictionary) -> String:
	var parts: Array = ["%d power" % t["power"]]
	var mats: Array = t.get("mats", [0, 0, 0, 0, 0])
	for r in D.NRES:
		if mats[r] > 0:
			parts.append("%d %s" % [mats[r], D.RES_NAMES[r]])
	return ", ".join(parts)


## "3 Glimmer, 2 Obsidian": what the current pick still wants delivered to a Lab.
func _mats_left(id: String) -> String:
	var g = game
	var want: Array = g.tech_mats_needed(g.tech_step(id))
	var got: PackedFloat64Array = g.tech_mats_got(id)
	var parts: Array = []
	for r in D.NRES:
		var left := int(want[r] - got[r])
		if left > 0:
			parts.append("%d %s" % [left, D.RES_NAMES[r]])
	return ", ".join(parts)


func _labs_built() -> int:
	var n := 0
	for b: Building in game.buildings:
		if b.type == D.B_LAB and b.built:
			n += 1
	return n


## The top bar's research button.
func _research_line() -> String:
	var g = game
	if g.current_tech == "":
		for t: Dictionary in D.TECHS:
			if g.tech_block(t["id"]) == "":
				return "T  Research: pick one"
		return "T  Research"
	var t: Dictionary = g.tech(g.current_tech)
	var frac: float = g.tech_power_frac(g.current_tech)
	var nm: String = t["name"]
	if t.has("levels"):
		nm += " %d" % (g.level(g.current_tech) + 1)
	var txt := "T  %s %d%%" % [nm, int(frac * 100.0)]
	if _labs_built() == 0:
		txt += "  (no Lab)"
	elif frac >= 1.0 and not g.tech_mats_done(g.current_tech):
		txt += "  (needs %s)" % _mats_left(g.current_tech)
	return txt


func _refresh_research() -> void:
	var g = game
	var labs := _labs_built()
	if labs == 0:
		research_head.text = "No Lab yet: build one (5) to turn power into research."
	elif g.current_tech == "":
		research_head.text = "Pick a tech. Each Lab puts up to %d power/s into it." % int(D.LAB_POWER_PER_S)
	else:
		research_head.text = "%s: %.1f power/s from %d Lab%s" % [g.tech(g.current_tech)["name"], g.research_rate, labs, "" if labs == 1 else "s"]
	for tier in range(0, 5):
		var note: Label = tier_notes[tier]
		if tier == 0:
			note.text = "Each level costs more than the last; later levels wait for their tier."
		elif tier == 1:
			note.text = "Open from the start."
		elif g.tiers_open[tier]:
			note.text = "Open: found %s." % D.TIER_FOUND[tier]
		else:
			note.text = "Opens with %s." % D.TIER_DISCOVERY[tier]
	for id: String in research_cards:
		var c: Dictionary = research_cards[id]
		var btn: Button = c["button"]
		var bar: ProgressBar = c["bar"]
		var state: Label = c["state"]
		var card: PanelContainer = c["card"]
		var block: String = g.tech_block(id)
		var frac: float = g.tech_power_frac(id)
		var current: bool = g.current_tech == id
		btn.text = _tech_title(id)
		btn.set_pressed_no_signal(current)
		btn.disabled = block != ""
		bar.visible = frac > 0.0 and block != "done"
		bar.value = frac
		var col := DIM
		if block == "done":
			state.text = "All levels done." if g.tech(id).has("levels") else "Researched."
			col = Color(0.55, 0.9, 0.6)
			btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.9, 0.6))
		elif block != "":
			state.text = block + "."
			col = Color(0.5, 0.52, 0.58) if g.tech(id).has("phase") else Color(0.8, 0.6, 0.55)
			btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.47, 0.52))
		elif current:
			state.text = "Researching%s: %d%%" % [" level %d" % (g.level(id) + 1) if g.tech(id).has("levels") else "", int(frac * 100.0)]
			var left := _mats_left(id)
			if left != "":
				state.text += ". Still to deliver: %s" % left
			col = GOLD
		elif frac > 0.0:
			state.text = "Paused at %d%%. Click to carry on." % int(frac * 100.0)
			col = Color(0.88, 0.9, 0.95)
		else:
			state.text = "Click to research."
			col = Color(0.88, 0.9, 0.95)
		state.add_theme_color_override("font_color", col)
		card.add_theme_stylebox_override("panel", card_current if current else card_plain)


func _build_win() -> void:
	win_panel = PanelContainer.new()
	win_panel.visible = false
	_anchor(win_panel, 0.5, 0.5, 0.5, 0.5, -230, -110, 230, 110)
	root.add_child(win_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	win_panel.add_child(vb)
	var title := _label("The Crucible is lit.", 24, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	win_label = _label("", 14)
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(win_label)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var same := _button("Replay this seed")
	same.pressed.connect(func() -> void: game.restart(true))
	hb.add_child(same)
	var fresh := _button("New seed")
	fresh.pressed.connect(func() -> void: game.restart(false))
	hb.add_child(fresh)


# --- Per-frame refresh ---------------------------------------------------------------

func refresh() -> void:
	var g = game
	for r in D.NRES:
		res_labels[r].text = "%s %d" % [D.RES_NAMES[r], int(floor(g.total(r) + 0.0001))]
	res_labels[D.R_POWER].text += "   +%.1f  -%.1f/s" % [g.power_made, g.power_used]
	var short: bool = g.power_used > g.power_made + 0.05 and g.total(D.R_POWER) < 20.0
	res_labels[D.R_POWER].add_theme_color_override("font_color", Color(1.0, 0.55, 0.4) if short else Color(0.88, 0.9, 0.95))
	hub_label.text = "Hub %d / 6 pkt/s" % g.hub_output()
	if g.won:
		speed_label.text = "Lit"
	elif g.paused:
		speed_label.text = "Paused"
	else:
		speed_label.text = "Speed %dx" % g.speed()
	speed_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4) if g.paused else Color(0.88, 0.9, 0.95))
	time_label.text = _clock(g.game_time)
	seed_label.text = "Seed %d" % g.seed_value
	var hv: Vector2i = g.hover
	if hv.x >= 0 and hv.x < D.W and hv.y >= 0 and hv.y < D.H:
		if g.is_known(hv.x, hv.y) or g.sim.get_cell(hv.x, hv.y) == D.BEDROCK:
			var b: Building = g.building_at(hv)
			var what := ""
			if b != null:
				what = b.title()
			else:
				var m: int = g.sim.get_cell(hv.x, hv.y)
				what = D.mat_name(m)
				if D.M.is_burnable(m) and g.sim.get_aux(hv.x, hv.y) > 0:
					what += " (burning)"
			cursor_label.text = "Depth %d  %s" % [hv.y, what]
		else:
			cursor_label.text = "Depth %d  unexplored" % hv.y
	else:
		cursor_label.text = ""
	for k in build_buttons.size():
		var bt: Button = build_buttons[k]
		bt.set_pressed_no_signal(g.tool_type == D.PALETTE[k])
		var open: bool = g.is_unlocked(D.PALETTE[k])
		if bt.visible != open:
			bt.visible = open
	research_button.text = _research_line()
	if research_panel.visible:
		_refresh_research()

	if g.selected != info_for:
		_rebuild_info()
	if info_for != null:
		for f: Callable in info_refreshers:
			f.call()
	if alerts_dirty:
		_rebuild_alerts()
	ruler.queue_redraw()
	_refresh_crucible()

	var btext: String = ""
	if g.banner_time > 0.0:
		btext = g.banner_text
	elif g.paused and not g.won:
		btext = "Paused. Space to carry on."
	banner_panel.visible = btext != ""
	banner.text = btext
	perf_label.visible = g.show_perf
	if g.show_perf:
		perf_label.text = "FPS %d   frame %.1f ms\nsim %.2f ms/tick   tick %.2f ms\nchunks %d   updates %d   packets %d\n%s" % [
			Engine.get_frames_per_second(), g.perf_frame_ms, g.perf_sim_ms, g.perf_tick_ms,
			g.sim.stat_chunks, g.sim.stat_updates, g.packets.size(), g.sim_label]


func _clock(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [int(s / 60.0), s % 60]


func show_win() -> void:
	var g = game
	win_label.text = "Time %s    Buildings lost %d\nCells drilled %d    Seed %d" % [_clock(g.game_time), g.buildings_lost, g.cells_drilled, g.seed_value]
	win_panel.visible = true


func toggle_research() -> void:
	research_panel.visible = not research_panel.visible
	if research_panel.visible:
		help_panel.visible = false
		_refresh_research()


func research_visible() -> bool:
	return research_panel.visible


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func help_visible() -> bool:
	return help_panel.visible


func _rebuild_alerts() -> void:
	alerts_dirty = false
	for c in alert_box.get_children():
		c.queue_free()
	var g = game
	var n: int = g.alerts.size()
	for k in range(maxi(0, n - 4), n):
		var a: Dictionary = g.alerts[k]
		var txt := "[%s] %s" % [_clock(a["t"]), a["text"]]
		if a["n"] > 1:
			txt += "  x%d" % a["n"]
		var b := _button(txt)
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(350, 0)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", KIND_COLORS.get(a["kind"], DIM))
		var ay: float = a["y"]
		var ax: float = a["x"]
		b.pressed.connect(func() -> void: game.jump_to(ay, ax))
		alert_box.add_child(b)


func _refresh_crucible() -> void:
	var g = game
	var shown: bool = g.crucible.connected or g.cstate != 0
	crucible_panel.visible = shown
	if not shown:
		return
	for pair: Array in c_lines:
		var r: int = pair[0]
		var l: Label = pair[1]
		var need: int = D.RECIPE[r]
		if g.cstate == 1:
			l.text = "%s  %d / %d fed   (%d in stock)" % [D.RES_NAMES[r], int(g.c_delivered[r]), need, int(g.total(r))]
		elif g.cstate == 2:
			l.text = "%s  %d / %d fed" % [D.RES_NAMES[r], need, need]
		else:
			l.text = "%s  %d / %d in stock" % [D.RES_NAMES[r], int(g.total(r)), need]
	c_bar.visible = g.cstate >= 1
	c_bar.value = g.crucible_charge() * 100.0
	c_activate.visible = g.cstate == 0
	c_activate.disabled = not g.crucible.connected
	if g.cstate == 0:
		var short := false
		for r in [D.R_OBSIDIAN, D.R_GLIMMER, D.R_WATER]:
			if g.total(r) < D.RECIPE[r]:
				short = true
		c_status.text = ("Stock is short. Charging drains if packets stop for 5 s." if short else "Ready. Tremors start once it charges.") \
				+ " It draws %d power/s while charging." % int(D.CRUCIBLE_POWER_PER_S)
	elif g.cstate == 1:
		var txt := "Power %d / %d (drawing %d/s). Tremor in %d s." % [int(g.c_power), int(D.CRUCIBLE_POWER_RESERVE),
				int(D.CRUCIBLE_POWER_PER_S), int(ceil(g.tremor_timer))]
		if g.c_starved:
			txt = "Draining! Out of power for 5 s. " + txt
		elif g.c_draining:
			txt = "Draining! Nothing has arrived for 5 s. " + txt
		if not g.crucible.connected:
			txt = "Link lost! " + txt
		c_status.text = txt
	else:
		c_status.text = "Lit."


# --- Building panel -------------------------------------------------------------------

func _rebuild_info() -> void:
	info_for = game.selected
	info_refreshers.clear()
	for c in info_box.get_children():
		c.queue_free()
	if info_for == null:
		info_panel.visible = false
		return
	info_panel.visible = true
	var b: Building = info_for
	var title := _label("%s" % b.title(), 16, D.B_COLORS[b.type])
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.tooltip_text = D.B_BLURBS[b.type]
	info_box.add_child(title)
	var status := _label("", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(200, 0)
	info_box.add_child(status)
	info_refreshers.append(func() -> void: status.text = _status_text(b))

	match b.type:
		D.B_CONDUIT, D.B_MAST:
			_on_off(b)
		D.B_DRILL:
			if not b.fixed:
				_options("Bore", ["Down", "Left", "Right"], func() -> int: return b.dir,
						func(k: int) -> void: game.set_drill_dir(b, k))
			var step := 10 if b.fixed else 2
			_stepper("Reach", func() -> int: return b.reach_limit,
					func(v: int) -> void: game.set_reach_limit(b, clampi(v, 2, game.max_reach() if b.fixed else D.DRILL_REACH)), step)
			_on_off(b)
		D.B_THUMPER:
			var tip := _label("Drag it to move it; let go mid-swing to throw it.", 12, DIM)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tip.custom_minimum_size = Vector2(200, 0)
			info_box.add_child(tip)
			_on_off(b)
		D.B_BORER:
			_options("Head", ["Down", "Left", "Right", "Up"], func() -> int: return b.dir,
					func(k: int) -> void: game.set_borer_dir(b, k))
			_on_off(b)
		D.B_WARREN:
			var set_b := _button("Set marker")
			set_b.add_theme_font_size_override("font_size", 12)
			set_b.pressed.connect(func() -> void:
				game.selected = b
				game.begin_sensor_move())
			info_box.add_child(set_b)
			var clr := _button("Clear marker")
			clr.add_theme_font_size_override("font_size", 12)
			clr.pressed.connect(func() -> void: game.clear_warren_marker(b))
			info_box.add_child(clr)
			_on_off(b)
		D.B_HOPPER:
			_options("Takes", ["All", "Water", "Solids"], func() -> int: return b.filter,
					func(k: int) -> void: b.filter = k)
			_on_off(b)
		D.B_SPOUT:
			_options("Rate/s", ["0.5", "1", "2"], func() -> int: return b.rate_idx,
					func(k: int) -> void: b.rate_idx = k)
			_options("Sensor", ["Stops it", "Ignored"], func() -> int: return 0 if b.sensor_on else 1,
					func(k: int) -> void: b.sensor_on = k == 0)
			_sensor_button(b)
			_on_off(b)
		D.B_FLOODGATE:
			_options("Gate", ["Closed", "Open", "Auto"], func() -> int: return b.gate_mode,
					func(k: int) -> void: b.gate_mode = k)
			var note := _label("Auto opens while liquid touches its sensor.", 12, DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(200, 0)
			info_box.add_child(note)
			_sensor_button(b)
		D.B_WATERWHEEL, D.B_TURBINE, D.B_LAMP:
			_on_off(b)
		D.B_LAB:
			var rb := _button("Research  (T)")
			rb.add_theme_font_size_override("font_size", 12)
			rb.pressed.connect(toggle_research)
			info_box.add_child(rb)
			_on_off(b)
	if b.type != D.B_HUB and b.type != D.B_CRUCIBLE and not b.fixed:
		var dem := _button("Demolish (50% back)" if b.built else "Cancel blueprint")
		dem.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
		dem.pressed.connect(func() -> void: game.demolish(b))
		info_box.add_child(dem)


## The Coolant Jacket's tank on a Drill or Borer.
func _coolant_line(lines: Array, b: Building) -> void:
	if game.researched.has("coolant_jacket"):
		lines.append("Coolant %.1f / %d Water (1 per %d cells of hot rock)" % [b.coolant, int(D.COOLANT_CAP), roundi(1.0 / D.COOLANT_WATER_PER_CELL)])


func _status_text(b: Building) -> String:
	var g = game
	var lines: Array = []
	if not b.built:
		var need: Array = []
		for r in D.NRES:
			var miss := b.cost[r] - int(b.delivered[r])
			if miss > 0:
				need.append("%d %s" % [miss, D.RES_NAMES[r]])
		lines.append("Blueprint %d%%  (needs %s)" % [int(b.progress() * 100.0), ", ".join(need)])
	if b.flying:
		lines.append("In the air." if not b.held else "Being dragged.")
	elif b.type != D.B_HUB and not b.connected and D.needs_link(b.type):
		lines.append("No link: move a Conduit within range." if not D.is_mover(b.type) else "Out of network range: running on its reserve.")
	if b.drowned:
		lines.append("Drowned: not relaying.")
	if b.type != D.B_HUB and b.type != D.B_CRUCIBLE:
		if b.fixed:
			lines.append("Fixed beside the Hub   depth %d" % b.y)
		else:
			lines.append("HP %d / %d   depth %d" % [int(ceil(b.hp)), int(b.max_hp), b.y])
	if b.built and D.uses_power(b.type):
		var cap: float = g.reserve_cap(b)
		if b.starved:
			lines.append("Out of power: stopped. Power %.1f / %d" % [b.power, int(cap)])
		else:
			lines.append("Power %.1f / %d" % [b.power, int(cap)])
	match b.type:
		D.B_HUB:
			lines.append("Sending %d of 6 packets a second." % g.hub_output())
			lines.append("Power %d / %d here, making %.1f/s" % [int(g.stock[D.R_POWER]), int(D.HUB_POWER_CAP), D.HUB_POWER_PER_S])
		D.B_WATERWHEEL:
			if b.built:
				lines.append("Making %.2f power/s   holding %.1f / %d" % [b.flow, b.store[D.R_POWER], int(D.GEN_BUFFER)])
				if b.flow <= 0.0:
					lines.append("Idle: it needs water landing on its top and room underneath for it to fall into.")
		D.B_TURBINE:
			if b.built:
				lines.append("Making %.2f power/s   holding %.1f / %d" % [b.flow, b.store[D.R_POWER], int(D.GEN_BUFFER)])
				if b.flow <= 0.0:
					lines.append("Idle: it needs steam rising under it and open air over it for the steam to leave by.")
		D.B_CACHE:
			if b.built:
				var held: Array = []
				for r in D.NRES:
					if b.store[r] >= 1.0:
						held.append("%d %s" % [int(b.store[r]), D.RES_NAMES[r]])
				lines.append("Holds " + (", ".join(held) if held.size() > 0 else "nothing yet"))
				lines.append("Digging within %d cells banks here (up to %d of each)." % [int(D.CACHE_BANK_RANGE), int(D.CACHE_CAP)])
		D.B_LAB:
			if b.built:
				if g.current_tech == "":
					lines.append("Idle: pick a tech in the Research tab (T).")
				else:
					var t: Dictionary = g.tech(g.current_tech)
					lines.append("On %s: %d%%" % [t["name"], int(g.tech_power_frac(g.current_tech) * 100.0)])
					if g.tech_power_frac(g.current_tech) >= 1.0 and not g.tech_mats_done(g.current_tech):
						lines.append("Waiting for %s." % _mats_left(g.current_tech))
		D.B_LAMP:
			if b.built:
				lines.append("Lit: light reaches %d cells through open air, a few into rock." % int(D.LIGHT_LAMP) if b.power > 0.0 and b.enabled else "Dark.")
		D.B_DRILL:
			if b.built:
				lines.append("Channel %d / %d   bored %d cells" % [b.reach, b.reach_limit, b.cells_bored])
				if b.fixed:
					lines.append("Head at depth %d. Drill Bit %d, Drill Shaft %d (reach %d)." % [int(b.drill_head().y), g.level("drill_bit"), g.level("drill_shaft"), g.max_reach()])
				if b.stuck != "":
					lines.append("Stopped: " + b.stuck)
				_coolant_line(lines, b)
		D.B_THUMPER:
			if b.built:
				lines.append("Blast power %d, radius %.1f, %.2f power a blast" % [g.thump_power(), g.thump_radius(), g.thump_cost()])
				if b.enabled and not b.flying:
					lines.append("Next blast in %.1f s   blasts %d" % [maxf(g.thump_interval() - b.work, 0.0), b.blasts])
		D.B_BORER:
			if b.built:
				var what: String = ["Boring", "Heading home to recharge", "Charging up where it started", "Heading back out"][b.mode]
				lines.append("%s   bored %d cells" % [what, b.cells_bored])
				if b.stuck != "":
					lines.append("Stopped: " + b.stuck)
				elif b.mode == 0 and not g.researched.has("homing"):
					lines.append("When its power runs out it stops where it is (Homing brings it back).")
				_coolant_line(lines, b)
		D.B_WARREN:
			if b.built:
				var what: String = {"dome": "Hollowing out the chamber over it.", "tunnel": "Tunnelling toward the marker.",
						"marker": "Digging out round the marker.", "done": "Marker dug out. Set another to send them on.",
						"idle": "Chamber dug. Set a marker to send them further.",
						"blocked": "Can't get any nearer the marker from here."}.get(b.stage, "Settling in.")
				lines.append(what)
				lines.append("Mites %d / %d   dug %d cells" % [b.mites.size(), g.warren_colony(), b.cells_dug])
				if b.marker.x >= 0:
					lines.append("Marker %d cells off, at depth %d" % [roundi(b.center().distance_to(Vector2(b.marker))), b.marker.y])
				if b.mites.size() < g.warren_colony():
					lines.append("Next mite in %d s (%d Stone, while linked)" % [ceili(maxf(D.WARREN_BREED_S - b.breed_t, 0.0)), int(D.WARREN_BREED_COST)])
				if b.mites_lost > 0:
					lines.append("Mites lost: %d (last %s)" % [b.mites_lost, b.last_loss])
				if b.starved:
					lines.append("Out of power: the mites wait at home.")
		D.B_HOPPER:
			if b.built:
				lines.append("Swallowed %d cells" % b.cells_taken)
		D.B_SPOUT:
			if b.built:
				lines.append("Pouring %d cells   sensor %s" % [b.queue, "wet" if b.sensor_wet else "dry"])
		D.B_FLOODGATE:
			if b.built:
				lines.append("%s   sensor %s" % ["Open" if b.gate_open else "Closed", "wet" if b.sensor_wet else "dry"])
	return "\n".join(lines)


func _options(label: String, names: Array, getter: Callable, setter: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	var l := _label(label, 12, DIM)
	l.custom_minimum_size = Vector2(48, 0)
	hb.add_child(l)
	var btns: Array = []
	for k in names.size():
		var bt := _button(names[k])
		bt.toggle_mode = true
		bt.add_theme_font_size_override("font_size", 12)
		bt.pressed.connect(func() -> void: setter.call(k))
		hb.add_child(bt)
		btns.append(bt)
	info_box.add_child(hb)
	info_refreshers.append(func() -> void:
		var cur: int = getter.call()
		for k in btns.size():
			btns[k].set_pressed_no_signal(k == cur))


## "Label  [-] value [+]": small integer settings (Drill reach).
func _stepper(label: String, getter: Callable, setter: Callable, step: int) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	var l := _label(label, 12, DIM)
	l.custom_minimum_size = Vector2(48, 0)
	hb.add_child(l)
	var minus := _button("-")
	minus.add_theme_font_size_override("font_size", 12)
	minus.pressed.connect(func() -> void: setter.call(getter.call() - step))
	hb.add_child(minus)
	var val := _label("", 13)
	val.custom_minimum_size = Vector2(56, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(val)
	var plus := _button("+")
	plus.add_theme_font_size_override("font_size", 12)
	plus.pressed.connect(func() -> void: setter.call(getter.call() + step))
	hb.add_child(plus)
	info_box.add_child(hb)
	info_refreshers.append(func() -> void: val.text = "%d cells" % getter.call())


func _on_off(b: Building) -> void:
	_options("Switch", ["On", "Off"], func() -> int: return 0 if b.enabled else 1,
			func(k: int) -> void:
				b.enabled = k == 0
				game.net_dirty = true)


func _sensor_button(b: Building) -> void:
	var bt := _button("Move sensor")
	bt.add_theme_font_size_override("font_size", 12)
	bt.pressed.connect(func() -> void:
		game.selected = b
		game.begin_sensor_move())
	info_box.add_child(bt)
