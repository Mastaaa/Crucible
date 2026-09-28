extends Node2D
## Crucible: the game controller.
##
## Owns the simulation, buildings, supply network, packets, the Crucible, the
## camera and input. overlay.gd draws buildings, links and packets on top of the
## terrain; hud.gd builds the interface. Balance numbers live in defs.gd.

const D = preload("res://scripts/defs.gd")
const WR = preload("res://scripts/warren.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const Mats = preload("res://scripts/materials.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
const Building = preload("res://scripts/building.gd")
const Overlay = preload("res://scripts/overlay.gd")
const Hud = preload("res://scripts/hud.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")

const KW := 64                 # explored/sense maps: one byte per 4 x 4 block
const KH := 256
const SIDE_UI := 240.0         # screen width kept free for side panels, per side
const DIRS4 := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const BRUSH_BLAST := -1           # not a material: the brush sets off a blast where you click
const BRUSH_MATS := [D.WATER, D.LAVA, D.LOOSE_DIRT, D.RUBBLE, D.DIRT, D.PACKED_DIRT, D.GRAVEL, D.SAND,
		D.CLAY, D.STONE, D.COAL, D.SULFUR, D.FIRE, D.STEAM, BRUSH_BLAST, D.AIR]
const SPEEDS := [1, 2, 4]
const FIX_BUILDING := -2            # Packet.fix for a Stone that repairs the building it goes to
const BUCKET_SHIFT := 4        # relay grid buckets are 16 x 16 cells (one relay range)
const GRID_W := 16             # D.W >> BUCKET_SHIFT


class Packet:
	var res := 0
	var target = null
	var hops: Array = []               # relays along the way, Hub first
	var pts := PackedVector2Array()    # hop centres, then the target
	var seg := 0
	var pos := Vector2.ZERO
	var source = null                  # the Hub, a Cache or a generator
	var fix := -1                      # -1: ordinary; FIX_BUILDING: repairs its target; else a link key


# --- World state ---------------------------------------------------------------
var sim                          # CrucibleSim (C++) or the GDScript fallback; see sim_factory.gd
var sim_label := ""               # which one, for the F3 overlay
var info := {}
var seed_value := 0
var buildings: Array = []
var hub: Building
var crucible: Building
var drill: Building               # the fixed Drill beside the Hub
var rng := RandomNumberGenerator.new()   # seeded with the map: Thumper throws and the like
var stock := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
var packets: Array = []
var relays: Array = []
var relay_index := {}             # relay -> its index in `relays`
var relay_grid := {}              # 16x16-cell bucket -> indices of the relays in it
var caches: Array = []            # built, linked Caches (for banking), as of the last rebuild
var dispatch_wait := 0            # ticks until the next dispatch pass after one that sent nothing
var net_dirty := true
var next_id := 1
var next_order := 1
var send_log: Array = []
var spout_rr := 0
# Sources (Hub, Caches, generators): one shortest-path tree over the relays each.
var src_list: Array = []
var src_dist: Array = []          # PackedFloat64Array per source, indexed like `relays`
var src_prev: Array = []          # PackedInt32Array per source
var src_entry := PackedInt32Array()
var spring_acc := 0.0
var power_made := 0.0             # smoothed power/s from the Hub and generators, for the HUD
var power_used := 0.0             # smoothed power/s burned by machines
var used_acc := 0.0
# Links: each building's line to the relay it draws through (see _link_key).
var link_hp := {}                 # link key -> HP left, for links that have taken damage
var broken_links := {}            # link key -> true: out of the network until mended
var link_fixes := {}              # link key -> true while a Stone is on its way to mend it
var link_ends := {}               # link key -> [building, relay], for damaged and broken links
var damaged := {}                 # building -> true once hurt, until repaired or gone (repair requests)
# Hazard scans reuse their inputs until a building comes or goes or the network is rebuilt.
var scan_dirty := true
var scan_list: Array = []         # buildings checked for hazards
var scan_rects := PackedInt32Array()
var scan_gates := PackedInt32Array()  # indexes in scan_list of Floodgates (open ones leak liquid)
var link_list: Array = []         # buildings whose link is checked
var fallers: Array = []           # buildings falling right now
var fliers: Array = []            # Thumpers in the air, or being dragged
var scan_stale := false           # a mover changed its link: rebuild the scan lists soon
var by_id := {}                   # building id -> building, rebuilt with the scan cache
var still_lights := PackedInt32Array()  # lights and sights that don't move or switch, with the cache
var still_sights := PackedInt32Array()
var lit_list: Array = []          # Lamps and Drills: their light switches or moves
var link_segs := PackedInt32Array()

var game_time := 0.0
var ticks := 0
var paused := false
var speed_idx := 0
var accum := 0.0
var won := false
var buildings_lost := 0
var cells_drilled := 0

# --- Research ------------------------------------------------------------------
var researched := {}              # tech id -> true (for upgrades: at least one level done)
var levels := {}                  # upgrade tech id -> levels done
var tech_power := {}              # tech id -> power put into it so far
var tech_mats := {}               # tech id -> PackedFloat64Array of materials delivered to Labs
var current_tech := ""            # "" when nothing is picked
var tiers_open: Array = [false, true, false, false, false]   # by tier number
var unlocked := {}                # building type -> true, for the build list
var research_rate := 0.0          # smoothed power/s going into research, for the HUD
var research_acc := 0.0
var _tech_by_id := {}             # tech id -> its entry in D.TECHS

# --- Crucible ------------------------------------------------------------------
var cstate := 0                # 0 dormant, 1 charging, 2 lit
var c_delivered := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
var c_inflight := PackedInt32Array([0, 0, 0, 0, 0])
var c_tokens := 0.0
var c_last_packet := -1.0
var c_draining := false
var tremor_timer := D.TREMOR_EVERY_S
var tremor_left := 0
var cave_cells := 0               # cells caved in recently (for the cave-in alert)
var cave_t := 0.0                 # seconds since that count started
var strut_list: Array = []        # Struts, with the scan cache (their anchors are checked)
var crucible_linked_once := false

# --- Alerts --------------------------------------------------------------------
var alerts: Array = []
var seen_kinds := {}
var seen_mats := {}               # material id -> true once its first-sighting note has shown
var pause_on_breach := true
var banner_text := ""
var banner_time := 0.0

# --- Knowledge maps ------------------------------------------------------------
var known := PackedByteArray()
var known_changed := true
var vis := PackedByteArray()      # blocks that show live: lit and explored
var seen := PackedByteArray()     # blocks lit and within sight of your buildings right now
var vis_changed := true
var mem_due := true               # the remembered picture needs refreshing from the live grid
var light_due := true             # the light map changed since it was last uploaded
var sense := PackedByteArray()
var sense_changed := true
var reveal_all := false

# --- Rendering -----------------------------------------------------------------
var terrain: Sprite2D
var terrain_mat: ShaderMaterial
var grid_img: Image
var grid_tex: ImageTexture
var aux_img: Image                # each cell's extra byte: burning, or a gas's life
var aux_tex: ImageTexture
var pal_tex: ImageTexture         # material colours and styles, from data/materials.json
var known_img: Image
var known_tex: ImageTexture
var vis_img: Image
var vis_tex: ImageTexture
var light_img: Image              # brightness per cell, from the C++ sim's light map
var light_tex: ImageTexture
var has_light := false            # the sim lights per cell (the GDScript one only lights blocks)
var mem_img: Image                # the map as last seen, shown where nothing looks now
var mem_tex: ImageTexture
var heat_img: Image
var heat_tex: ImageTexture
var sense_img: Image
var sense_tex: ImageTexture
var overlay: Node2D
var hud: Node

# --- Camera --------------------------------------------------------------------
var zoom := 3
var zoom_max := 4
var cam_y := 0.0
var cam_target := 0.0
var view_offset := Vector2.ZERO
var map_x := 0.0
var cam_x := D.W * 0.5          # world x at the middle of the screen
var cam_x_target := D.W * 0.5
var zoom_min := 2
var shake := 0.0
var ui_scale := 1.0

# --- Tools and input -------------------------------------------------------------
var tool_type := -1
var tool_dir := 0
var tool_horizontal := false
var drag_from := Vector2i(-1, -1)
var selected: Building = null
var hover := Vector2i(-1, -1)
var snap_key: Array = []          # snap_place's last question and answer, reused for a few frames
var snap_rect := Rect2i()
var snap_offsets: Array = []      # offsets within PLACE_SNAP, nearest first
var mouse_screen := Vector2.ZERO
var sensor_mode := false
var demolish_target: Building = null
var demolish_hold := 0.0
var grab: Building = null          # a Thumper under a left press: dragged once the mouse moves
var grab_from := Vector2i.ZERO
var panning := false
var pan_last := Vector2.ZERO
var show_network := false
var brush_mode := false
var brush_idx := 0
var painting := 0
var show_perf := false
var perf_sim_ms := 0.0
var perf_tick_ms := 0.0
var perf_frame_ms := 0.0
var headless := false


# ================================================================================
# Setup
# ================================================================================

func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	RenderingServer.set_default_clear_color(Color(0.035, 0.035, 0.05))
	var s := randi() % 100000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			s = int(a.substr(7))
	_build_nodes()
	new_game(s)
	get_viewport().size_changed.connect(_layout)
	_layout()
	zoom = default_zoom()
	_layout()
	_center_on(hub.center().y + 30.0, true, hub.center().x)


func _build_nodes() -> void:
	terrain = Sprite2D.new()
	terrain.centered = false
	terrain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = TERRAIN_SHADER
	terrain.material = terrain_mat
	add_child(terrain)

	grid_img = Image.create(D.W, D.H, false, Image.FORMAT_R8)
	grid_tex = ImageTexture.create_from_image(grid_img)
	terrain.texture = grid_tex
	known_img = Image.create(KW, KH, false, Image.FORMAT_R8)
	known_tex = ImageTexture.create_from_image(known_img)
	heat_img = Image.create(KW, KH, false, Image.FORMAT_R8)
	heat_tex = ImageTexture.create_from_image(heat_img)
	sense_img = Image.create(KW, KH, false, Image.FORMAT_R8)
	sense_tex = ImageTexture.create_from_image(sense_img)
	vis_img = Image.create(KW, KH, false, Image.FORMAT_R8)
	vis_tex = ImageTexture.create_from_image(vis_img)
	light_img = Image.create(D.W, D.H, false, Image.FORMAT_R8)
	light_tex = ImageTexture.create_from_image(light_img)
	mem_img = Image.create(D.W, D.H, false, Image.FORMAT_R8)
	mem_tex = ImageTexture.create_from_image(mem_img)
	aux_img = Image.create(D.W, D.H, false, Image.FORMAT_R8)
	aux_tex = ImageTexture.create_from_image(aux_img)
	pal_tex = ImageTexture.create_from_image(Mats.palette_image())
	terrain_mat.set_shader_parameter("grid_tex", grid_tex)
	terrain_mat.set_shader_parameter("aux_tex", aux_tex)
	terrain_mat.set_shader_parameter("pal_tex", pal_tex)
	terrain_mat.set_shader_parameter("known_tex", known_tex)
	terrain_mat.set_shader_parameter("heat_tex", heat_tex)
	terrain_mat.set_shader_parameter("sense_tex", sense_tex)
	terrain_mat.set_shader_parameter("vis_tex", vis_tex)
	terrain_mat.set_shader_parameter("light_tex", light_tex)
	terrain_mat.set_shader_parameter("mem_tex", mem_tex)
	terrain_mat.set_shader_parameter("ground_y", float(D.GROUND_Y))

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	overlay = Overlay.new()
	overlay.game = self
	layer.add_child(overlay)

	hud = Hud.new()
	hud.game = self
	add_child(hud)


func new_game(s: int) -> void:
	seed_value = s
	rng.seed = s * 7919 + 13
	sim = SimFactory.create()
	sim.set_seed(s)
	if SimFactory.native_available():
		sim_label = "C++ sim, %d thread%s" % [sim.get_threads(), "" if sim.get_threads() == 1 else "s"]
	else:
		sim_label = "GDScript sim (the C++ one didn't load)"
	info = WorldGen.new().generate(sim, s)
	buildings.clear()
	packets.clear()
	relays.clear()
	alerts.clear()
	seen_kinds.clear()
	seen_mats.clear()
	link_hp.clear()
	broken_links.clear()
	link_fixes.clear()
	link_ends.clear()
	damaged.clear()
	fallers.clear()
	fliers.clear()
	scan_stale = false
	scan_dirty = true
	send_log.clear()
	next_id = 1
	next_order = 1
	stock = PackedFloat64Array([D.START_STONE, 0.0, 0.0, 0.0, D.START_POWER])
	spring_acc = 0.0
	power_made = D.HUB_POWER_PER_S
	researched.clear()
	levels.clear()
	tech_power.clear()
	tech_mats.clear()
	current_tech = ""
	tiers_open = [false, true, false, false, false]
	research_rate = 0.0
	research_acc = 0.0
	_refresh_unlocks()
	power_used = 0.0
	used_acc = 0.0
	game_time = 0.0
	ticks = 0
	accum = 0.0
	won = false
	paused = false
	buildings_lost = 0
	cells_drilled = 0
	cstate = 0
	c_delivered = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	c_inflight = PackedInt32Array([0, 0, 0, 0, 0])
	c_tokens = 0.0
	c_last_packet = -1.0
	c_draining = false
	tremor_timer = D.TREMOR_EVERY_S
	tremor_left = 0
	cave_cells = 0
	cave_t = 0.0
	strut_list.clear()
	crucible_linked_once = false
	selected = null
	demolish_target = null
	grab = null
	tool_type = -1
	sensor_mode = false
	banner_text = ""

	hub = _make_building(D.B_HUB, info["hub"])
	hub.built = true
	crucible = _make_building(D.B_CRUCIBLE, info["crucible"])
	crucible.built = true
	# The Drill: fixed on the Hub's right, boring straight down from the start.
	var hr: Rect2i = info["hub"]
	drill = _make_building(D.B_DRILL, Rect2i(hr.end.x, hr.end.y - 3, 3, 3))
	drill.fixed = true
	drill.built = true
	drill.power = D.POWER_RESERVE
	drill.reach_limit = max_reach()
	for yy in range(drill.y, drill.y + drill.h):
		for xx in range(drill.x, drill.x + drill.w):
			sim.set_cell(xx, yy, D.BUILDING)

	known = PackedByteArray()
	known.resize(KW * KH)
	for i in ((D.GROUND_Y + 12) >> 2) * KW:
		known[i] = 255
	reveal(hub.center(), D.REVEAL_START)
	known_changed = true
	sense = PackedByteArray()
	sense.resize(KW * KH)
	sense_changed = true
	vis = PackedByteArray()
	vis.resize(KW * KH)
	vis_changed = true
	seen = PackedByteArray()
	seen.resize(KW * KH)
	if mem_img != null:
		mem_img.set_data(D.W, D.H, false, Image.FORMAT_R8, sim.get_cells())
		mem_tex.update(mem_img)
	mem_due = true
	sim.refresh_heat(true)
	sim.changed = true
	net_dirty = true
	_rebuild_network()
	alert("info", "The Drill beside the Hub is boring down. The Crucible waits at the bottom.", hub.center())
	alert("info", "Build a Lab (5) and pick something to research (T).", hub.center())
	if hud:
		hud.on_new_game()


# ================================================================================
# Frame loop
# ================================================================================

func _process(delta: float) -> void:
	var f0 := Time.get_ticks_usec()
	_held_keys(delta)
	if not paused and not won:
		var spd: int = SPEEDS[speed_idx]
		accum += delta * spd
		var n := 0
		while accum >= D.DT and n < 2 * spd:
			_tick()
			accum -= D.DT
			n += 1
		accum = minf(accum, D.DT * 2.0)
	_update_demolish(delta)
	if grab != null:
		if grab.dead:
			grab = null
		elif grab.held:
			grab.hold_at = Vector2(hover) + Vector2(0.5, 0.5)
	if painting != 0 and hover.x >= 0:
		_paint(hover, painting == 2)
	_update_camera(delta)
	_upload()
	terrain_mat.set_shader_parameter("time_s", Time.get_ticks_msec() * 0.001)
	overlay.queue_redraw()
	hud.refresh()
	if banner_time > 0.0:
		banner_time -= delta
	perf_frame_ms = lerpf(perf_frame_ms, (Time.get_ticks_usec() - f0) * 0.001, 0.1)


func _tick() -> void:
	var t0 := Time.get_ticks_usec()
	ticks += 1
	game_time += D.DT
	sim.step()
	var t1 := Time.get_ticks_usec()
	if ticks % 2 == 0:
		sim.erode(D.ERODE_SAMPLES, D.GROUND_Y + 6, 330)
	sim.weather(D.WEATHER_SAMPLES)
	sim.wash(D.WASH_SAMPLES)
	_cave_ins(sim.collapse(D.COLLAPSE_ROWS))
	if net_dirty:
		_rebuild_network()
	_springs()
	if not fallers.is_empty():
		_update_falling()
	if not fliers.is_empty():
		_update_fliers()
	_update_buildings()
	_research_check()
	if stock[D.R_STONE] < D.HUB_TRICKLE_BELOW:
		stock[D.R_STONE] += D.DT / D.HUB_TRICKLE_S
	# The floor: the Hub always makes a little power, so no network is past saving.
	if stock[D.R_POWER] < D.HUB_POWER_CAP:
		stock[D.R_POWER] = minf(stock[D.R_POWER] + D.HUB_POWER_PER_S * D.DT, D.HUB_POWER_CAP)
	if ticks % 30 == 0:
		_power_stats()
	_dispatch()
	_move_packets()
	# Buildings and links take turns, three ticks apart, so neither lands on the other.
	if scan_stale and ticks % 30 == 0:
		scan_stale = false
		scan_dirty = true
	if ticks % 6 == 0:
		_damage_scan()
		_check_struts()
	elif ticks % 6 == 3:
		_link_scan(6.0 * D.DT)
	if ticks % 20 == 0:
		sim.refresh_heat(false)
	if ticks % 30 == 0:
		_refresh_sense()
	if ticks % 15 == 0:
		_refresh_vision()
	if cstate == 1:
		_update_crucible()
	perf_sim_ms = lerpf(perf_sim_ms, (t1 - t0) * 0.001, 0.05)
	perf_tick_ms = lerpf(perf_tick_ms, (Time.get_ticks_usec() - t0) * 0.001, 0.05)


## Advance the game by `n` ticks without rendering (used by tests).
func run_ticks(n: int) -> void:
	for _i in n:
		_tick()


func _upload() -> void:
	if sim.changed:
		grid_img.set_data(D.W, D.H, false, Image.FORMAT_R8, sim.get_cells())
		grid_tex.update(grid_img)
		aux_img.set_data(D.W, D.H, false, Image.FORMAT_R8, sim.get_aux_bytes())
		aux_tex.update(aux_img)
		sim.changed = false
	if known_changed:
		known_img.set_data(KW, KH, false, Image.FORMAT_R8, known)
		known_tex.update(known_img)
		known_changed = false
	if sim.heat_changed:
		heat_img.set_data(KW, KH, false, Image.FORMAT_R8, sim.get_heat())
		heat_tex.update(heat_img)
		sim.heat_changed = false
	if sense_changed:
		sense_img.set_data(KW, KH, false, Image.FORMAT_R8, sense)
		sense_tex.update(sense_img)
		sense_changed = false
	if vis_changed:
		vis_img.set_data(KW, KH, false, Image.FORMAT_R8, vis)
		vis_tex.update(vis_img)
		vis_changed = false
	if light_due:
		var lp: PackedByteArray = sim.get_light()
		has_light = lp.size() == D.W * D.H
		if has_light:
			light_img.set_data(D.W, D.H, false, Image.FORMAT_R8, lp)
			light_tex.update(light_img)
		terrain_mat.set_shader_parameter("use_light", 1.0 if has_light else 0.0)
		light_due = false
	if mem_due:
		_refresh_memory()
		mem_due = false
	terrain_mat.set_shader_parameter("reveal_all", 1.0 if reveal_all else 0.0)


# ================================================================================
# Buildings
# ================================================================================

func _make_building(type: int, r: Rect2i) -> Building:
	var b := Building.new()
	b.id = next_id
	next_id += 1
	b.type = type
	b.x = r.position.x
	b.y = r.position.y
	b.w = r.size.x
	b.h = r.size.y
	b.max_hp = D.B_HP[type]
	b.hp = b.max_hp
	b.cost = PackedInt32Array(D.B_COSTS[type])
	b.order = next_order
	next_order += 1
	buildings.append(b)
	scan_dirty = true
	return b


## Footprint of a building of `type` centred on cell `c`.
func footprint(type: int, c: Vector2i, horiz: bool) -> Rect2i:
	var s: Vector2i = D.B_SIZES[type]
	if type == D.B_FLOODGATE and horiz:
		s = Vector2i(s.y, s.x)
	return Rect2i(c.x - (s.x >> 1), c.y - (s.y >> 1), s.x, s.y)


## Where a building of `type` goes with the cursor on `c`. Its footprint there if
## that's a legal spot. If it's only floating, or poking into rock, the nearest
## legal spot within PLACE_SNAP cells instead, a spot resting on something counting
## as a cell and a bit nearer. Otherwise the plain footprint, so the ghost can say
## what's wrong. Bulkheads are laid by hand and never snap.
func snap_place(type: int, c: Vector2i, horiz: bool) -> Rect2i:
	var key := [type, c, horiz, ticks >> 3, Engine.get_process_frames() >> 3]
	if key == snap_key:
		return snap_rect
	snap_key = key
	var r := footprint(type, c, horiz)
	snap_rect = r
	if type == D.B_BULKHEAD:
		return r
	var why := check_place(type, r)
	if why != "Must touch rock" and why != "Needs open air or water":
		return r
	if why == "Must touch rock" and not _solid_within(r.grow(D.PLACE_SNAP + 1)):
		return r
	if snap_offsets.is_empty():
		var n := D.PLACE_SNAP
		for dy in range(-n, n + 1):
			for dx in range(-n, n + 1):
				if (dx != 0 or dy != 0) and dx * dx + dy * dy <= n * n:
					snap_offsets.append(Vector2i(dx, dy))
		snap_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
	var best_score := INF
	for o: Vector2i in snap_offsets:
		var d2 := float(o.length_squared())
		if d2 >= best_score:
			break
		var rr := Rect2i(r.position + o, r.size)
		if check_place(type, rr) != "":
			continue
		var score := d2 if _rests(rr) else d2 + 1.5
		if score < best_score:
			best_score = score
			snap_rect = rr
	return snap_rect


## Anything solid (or a building) inside `r`.
func _solid_within(r: Rect2i) -> bool:
	for yy in range(maxi(r.position.y, 0), mini(r.end.y, D.H)):
		for xx in range(maxi(r.position.x, 0), mini(r.end.x, D.W)):
			if D.is_solid(sim.get_cell(xx, yy)):
				return true
	return false


## Something solid (or a building) right under `r`.
func _rests(r: Rect2i) -> bool:
	for xx in range(r.position.x, r.end.x):
		if D.is_solid(sim.get_cell(xx, r.end.y)):
			return true
	return false


## Returns "" when the footprint is a legal spot, otherwise a short reason.
func check_place(type: int, r: Rect2i, need_touch := true) -> String:
	if r.position.x < 2 or r.position.y < 2 or r.end.x > D.W - 2 or r.end.y > D.H - 2:
		return "Out of bounds"
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if not Mats.buildable_in(sim.get_cell(xx, yy)):
				return "Needs open air or water"
			if not is_known(xx, yy):
				return "Unexplored"
	if need_touch and not touches_solid(r):
		return "Must touch rock"
	if find_link(type, r) == null:
		return "Out of network range"
	return ""


func touches_solid(r: Rect2i) -> bool:
	for xx in range(r.position.x, r.end.x):
		if D.is_solid(sim.get_cell(xx, r.position.y - 1)) or D.is_solid(sim.get_cell(xx, r.end.y)):
			return true
	for yy in range(r.position.y, r.end.y):
		if D.is_solid(sim.get_cell(r.position.x - 1, yy)) or D.is_solid(sim.get_cell(r.end.x, yy)):
			return true
	return false


## The relay a building of `type` at `r` would draw packets through, or null.
## `exclude` is the building asking, if it exists: it can't link to itself, or
## over a link of its that's broken.
func find_link(type: int, r: Rect2i, exclude: Building = null) -> Building:
	var best: Building = null
	var best_cost := INF
	var c := Vector2(r.position) + Vector2(r.size) * 0.5
	var relay := D.is_relay_type(type)
	var reach := int(ceil(D.MAST_RANGE if relay else D.LINK_RANGE)) + 1
	for i in _relays_near(r.grow(reach)):
		var rl: Building = relays[i]
		if not rl.connected or rl == exclude:
			continue
		if exclude != null and not broken_links.is_empty() and broken_links.has(_link_key(exclude, rl)):
			continue
		if relay and rl.drowned:
			continue
		var d := 0.0
		if relay:
			d = c.distance_to(rl.center())
			if d > maxf(D.relay_range(type), D.relay_range(rl.type)):
				continue
		else:
			d = dist_to_rect(rl.center(), r)
			if d > D.LINK_RANGE:
				continue
		if rl.net_dist + d < best_cost:
			best_cost = rl.net_dist + d
			best = rl
	return best


## Indices of relays whose centre could lie inside `area` (bucket precision).
func _relays_near(area: Rect2i) -> Array:
	var out: Array = []
	var bx0 := clampi(area.position.x >> BUCKET_SHIFT, 0, GRID_W - 1)
	var bx1 := clampi((area.end.x - 1) >> BUCKET_SHIFT, 0, GRID_W - 1)
	var by0 := maxi(area.position.y >> BUCKET_SHIFT, 0)
	var by1 := maxi((area.end.y - 1) >> BUCKET_SHIFT, 0)
	for by in range(by0, by1 + 1):
		for bx in range(bx0, bx1 + 1):
			var cell: Array = relay_grid.get(by * GRID_W + bx, [])
			out.append_array(cell)
	return out


static func dist_to_rect(p: Vector2, r: Rect2i) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)


func place(type: int, r: Rect2i, dir := 0, horiz := false) -> Building:
	var b := _make_building(type, r)
	b.dir = dir
	b.horizontal = horiz
	# Buildings can go into water; a Hopper banks the water it displaces.
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if type == D.B_HOPPER and sim.get_cell(xx, yy) == D.WATER:
				_bank(Vector2(xx, yy), D.R_WATER, 1.0 / D.CELLS_PER_UNIT)
			sim.set_cell(xx, yy, D.BUILDING)
	if type == D.B_DRILL:
		b.reach_limit = D.DRILL_REACH
	elif type == D.B_BORER:
		b.trail = [Vector2i(b.x, b.y)]
		b.mode = 2              # charges up where it's placed before it sets off
	elif type == D.B_SPOUT:
		b.sensor_on = true
		b.sx = b.x + 1
		b.sy = mini(b.y + b.h + 3, D.H - 3)
	elif type == D.B_FLOODGATE:
		b.sensor_on = true
		b.sx = b.x + (b.w >> 1)
		b.sy = maxi(b.y - 2, 2)
	if b.fully_delivered():
		_complete(b)
	net_dirty = true
	return b


func _complete(b: Building) -> void:
	b.built = true
	b.flash = 0.6
	scan_dirty = true
	if D.is_relay_type(b.type) or b.is_source():
		net_dirty = true
	if b.type == D.B_DRILL:
		_refresh_sense()


# --- Struts ---------------------------------------------------------------------------

## The gap a Strut would span through cell `c`: the open cells (air, gas or water)
## in its row (flat) or column (upright), out to what stops them both ways. Stops
## looking a cell past STRUT_MAX so open sky isn't searched end to end. Empty
## when `c` itself isn't open.
func strut_rect(c: Vector2i, horiz: bool) -> Rect2i:
	if c.x < 2 or c.y < 2 or c.x >= D.W - 2 or c.y >= D.H - 2 or not Mats.buildable_in(sim.get_cell(c.x, c.y)):
		return Rect2i(c, Vector2i.ZERO)
	var step := Vector2i(1, 0) if horiz else Vector2i(0, 1)
	var a := c
	var b := c
	for _k in D.STRUT_MAX:
		var n := a - step
		if n.x < 2 or n.y < 2 or not Mats.buildable_in(sim.get_cell(n.x, n.y)):
			break
		a = n
	for _k in D.STRUT_MAX:
		var n := b + step
		if n.x >= D.W - 2 or n.y >= D.H - 2 or not Mats.buildable_in(sim.get_cell(n.x, n.y)):
			break
		b = n
	return Rect2i(a, b - a + Vector2i.ONE)


## The two cells a Strut at `r` rests on, one past each end.
static func strut_anchors(r: Rect2i) -> Array:
	if r.size.x >= r.size.y:
		return [Vector2i(r.position.x - 1, r.position.y), Vector2i(r.end.x, r.position.y)]
	return [Vector2i(r.position.x, r.position.y - 1), Vector2i(r.position.x, r.end.y)]


## Rock a Strut can rest on: anything static that isn't a building.
func strut_anchor_ok(c: Vector2i) -> bool:
	var m: int = sim.get_cell(c.x, c.y)
	return Mats.kind_of(m) == Mats.K_STATIC and m != D.BUILDING


## "" when a Strut can go at `r` (from strut_rect), otherwise a short reason.
func check_strut(r: Rect2i) -> String:
	if r.size.x <= 0 or r.size.y <= 0:
		return "Needs a gap: open air or water"
	if maxi(r.size.x, r.size.y) > D.STRUT_MAX:
		return "Too wide: a Strut spans %d cells at most" % D.STRUT_MAX
	for c: Vector2i in strut_anchors(r):
		if not strut_anchor_ok(c):
			return "Both ends must meet rock"
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if not is_known(xx, yy):
				return "Unexplored"
	var cost: Array = D.B_COSTS[D.B_STRUT]
	for res in D.NRES:
		if stock[res] < cost[res]:
			return "Needs %d %s at the Hub" % [cost[res], D.RES_NAMES[res]]
	return ""


## Build a Strut at once, paid from the Hub's stock: no blueprint, no link.
func place_strut(r: Rect2i) -> Building:
	var b := _make_building(D.B_STRUT, r)
	b.horizontal = r.size.x >= r.size.y
	for res in D.NRES:
		stock[res] -= b.cost[res]
		b.delivered[res] = b.cost[res]
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			sim.set_cell(xx, yy, D.BUILDING)
	var ends := strut_anchors(r)
	b.anchor_a = ends[0]
	b.anchor_b = ends[1]
	_strut_hold(b, 1)
	_complete(b)
	return b


func _strut_hold(b: Building, delta: int) -> void:
	if b.anchor_a.x >= 0:
		sim.hold_circle(b.anchor_a.x, b.anchor_a.y, D.STRUT_HOLD, delta)
	if b.anchor_b.x >= 0:
		sim.hold_circle(b.anchor_b.x, b.anchor_b.y, D.STRUT_HOLD, delta)


## A Strut snaps when either end loses its rock (dug, blasted, caved in).
func _check_struts() -> void:
	for b: Building in strut_list:
		if b.dead or b.falling:
			continue
		if not strut_anchor_ok(b.anchor_a) or not strut_anchor_ok(b.anchor_b):
			_destroy(b, "losing an anchor")


## Cave-ins: tally what the collapse sweep brings down and call out a real one.
func _cave_ins(n: int) -> void:
	cave_t += D.DT
	if n > 0:
		cave_cells += n
		if cave_cells >= D.CAVE_ALERT_CELLS:
			# Only where you've explored: ground out in the dark comes down unannounced.
			var at: Vector2i = sim.get_last_cave()
			if is_known(at.x, at.y):
				alert("cavein", "Cave-in at depth %d" % at.y, Vector2(at) + Vector2(0.5, 0.5))
			cave_cells = -1000      # once per episode: reset below after a quiet spell
			cave_t = 0.0
	if cave_t >= 2.0:
		cave_cells = 0
		cave_t = 0.0


func demolish(b: Building) -> void:
	if b == null or b.dead or b.type == D.B_HUB or b.type == D.B_CRUCIBLE or b.fixed:
		return
	for r in D.NRES:
		if b.built:
			stock[r] += b.cost[r] * 0.5 + b.store[r]
		else:
			stock[r] += b.delivered[r]
	if b.built:
		stock[D.R_POWER] += b.power
	_remove(b, D.AIR)


func _destroy(b: Building, cause: String) -> void:
	if b.dead:
		return
	buildings_lost += 1
	alert("destroyed", "%s destroyed by %s at depth %d" % [b.title(), cause, int(b.center().y)], b.center())
	_remove(b, D.RUBBLE)


func _remove(b: Building, fill: int) -> void:
	b.dead = true
	if b.type == D.B_STRUT:
		_strut_hold(b, -1)
	for yy in range(b.y, b.y + b.h):
		for xx in range(b.x, b.x + b.w):
			if sim.get_cell(xx, yy) == D.BUILDING:
				sim.set_cell(xx, yy, fill)
	buildings.erase(b)
	damaged.erase(b)
	fliers.erase(b)
	if grab == b:
		grab = null
	scan_dirty = true
	_forget_links(b)
	if selected == b:
		selected = null
	if demolish_target == b:
		demolish_target = null
	net_dirty = true
	if b.type == D.B_DRILL:
		_refresh_sense()


func building_at(c: Vector2i) -> Building:
	for b: Building in buildings:
		if b.has_cell(c.x, c.y):
			return b
	return null


func set_drill_dir(b: Building, dir: int) -> void:
	if b.dir == dir:
		return
	b.dir = dir
	b.reach = 0
	b.scan_from = 0
	_refresh_sense()


func set_reach_limit(b: Building, limit: int) -> void:
	b.reach_limit = limit
	b.reach = mini(b.reach, limit)
	b.scan_from = 0


# ================================================================================
# Machines
# ================================================================================

func _update_buildings() -> void:
	for b: Building in buildings:
		if b.flash > 0.0:
			b.flash -= D.DT
		if b.alert_cd > 0.0:
			b.alert_cd -= D.DT
		var t := b.type
		if D.is_conduit(t) or t == D.B_BULKHEAD or not b.built or b.falling:
			continue
		if b.breach_cd > 0.0:
			b.breach_cd -= D.DT
		# Machines run on their reserves, cut off or not; an empty one stops.
		if t == D.B_DRILL:
			b.starved = false
			if b.enabled:
				_drill(b)
		elif t == D.B_HOPPER:
			b.starved = false
			if b.enabled:
				_hopper(b)
		elif t == D.B_SPOUT:
			_spout(b)
		elif t == D.B_FLOODGATE:
			if ticks % 6 == 0:
				_gate(b)
		elif t == D.B_WATERWHEEL:
			_wheel(b)
		elif t == D.B_LAMP:
			_lamp(b)
		elif t == D.B_LAB:
			_lab(b)
		elif t == D.B_THUMPER:
			_thumper(b)
		elif t == D.B_BORER:
			_borer(b)
		elif t == D.B_WARREN:
			WR.tick(self, b)


func _drill(b: Building) -> void:
	b.work = minf(b.work + D.DT, 2.0)   # must exceed the dearest cell (obsidian, 1.3 s)
	b.rescan -= 1
	if b.rescan <= 0:
		b.scan_from = 0
		b.rescan = 30
	var guard := 0
	while guard < 16:
		guard += 1
		var c := _drill_find(b)
		if c.x == -2:
			break                  # still looking down a long channel; carry on next tick
		if c.x < 0:
			if b.reach >= b.reach_limit or not _drill_can_extend(b):
				break
			b.reach += 1
			if b.reach % 2 == 0:
				reveal(b.drill_head(), D.REVEAL_DIG)
			continue
		var m: int = sim.get_cell(c.x, c.y)
		var cost := 1.0 / (D.bore_rate(m) * b.lanes() * drill_speed())
		if b.work < cost:
			break
		var pc := drill_power(m, b.channel_row(c))
		if b.power < pc:
			b.starved = true
			break
		b.work -= cost
		b.power -= pc
		used_acc += pc
		sim.set_cell(c.x, c.y, D.AIR)
		excavated(c)
		for r: int in D.mat_yields(m):
			_bank(Vector2(c), r, 1.0 / D.CELLS_PER_UNIT)
		b.cells_bored += 1
		cells_drilled += 1
		_breach_check(b, c)


## The first cell left to dig in the channel, from `scan_from` down. A long
## channel is looked over DRILL_SCAN_ROWS rows a tick: (-2, -2) means "not found
## yet, keep looking next tick"; (-1, -1) that the channel is clear to `reach`.
func _drill_find(b: Building) -> Vector2i:
	var end := mini(b.reach, b.scan_from + D.DRILL_SCAN_ROWS)
	for r in range(b.scan_from, end):
		for k in b.lanes():
			var c := b.channel_cell(r, k)
			if can_cut(sim.get_cell(c.x, c.y)):
				b.scan_from = r
				return c
	b.scan_from = end
	if end < b.reach:
		return Vector2i(-2, -2)
	return Vector2i(-1, -1)


## What the Drill and Borers can cut: anything diggable, obsidian only with the Saw.
func can_cut(m: int) -> bool:
	if m == D.OBSIDIAN and not researched.has("obsidian_saw"):
		return false
	return D.is_drillable(m)


## The channel grows one row at a time. It stops at bedrock or buildings across
## the whole row, and at a row of solid lava: a drill won't push its channel into
## a lava body (so boring into a lava lake stops at the surface). Water it bores
## straight through.
func _drill_can_extend(b: Building) -> bool:
	var blocked := 0
	var lava := 0
	var n := b.lanes()
	for k in n:
		var c := b.channel_cell(b.reach, k)
		if c.x < 2 or c.x > D.W - 3 or c.y < 2 or c.y > D.H - 3:
			return false
		var m: int = sim.get_cell(c.x, c.y)
		if m == D.BEDROCK or m == D.BUILDING or (m == D.OBSIDIAN and not can_cut(m)):
			blocked += 1
		elif m == D.LAVA:
			lava += 1
	return blocked < n and lava < n


## A breach is liquid that was sealed until this cell went: no other open
## neighbour. Liquid already lapping at the channel doesn't count again, and
## each drill reports each liquid once.
func _breach_check(b: Building, c: Vector2i) -> void:
	if b.breach_cd > 0.0:
		return
	for o: Vector2i in DIRS4:
		var p := c + o
		var m: int = sim.get_cell(p.x, p.y)
		if m != D.WATER and m != D.LAVA:
			continue
		var sealed := true
		for o2: Vector2i in DIRS4:
			var q := p + o2
			if q == c:
				continue
			var n: int = sim.get_cell(q.x, q.y)
			if D.is_thin(n):
				sealed = false
				break
		if not sealed:
			continue
		# One report per drill per liquid: a farm drill mining a lava crust knows.
		var bit := 1 if m == D.WATER else 2
		if b.breached & bit:
			continue
		b.breached |= bit
		b.breach_cd = 30.0
		if m == D.WATER:
			alert("water_breach", "Water breach at depth %d" % c.y, Vector2(c))
		else:
			alert("lava_breach", "Lava breach at depth %d" % c.y, Vector2(c))
		return


## Hoppers swallow loose material that lands in their mouth (the row above them),
## worth something or not (so ash doesn't clog them), and drink water from their
## sides too, so one dropped into a flood drains it.
func _hopper(b: Building) -> void:
	b.intake = minf(b.intake + D.HOPPER_RATE * D.DT, 3.0)
	if b.intake < 1.0 or b.y - 1 < 2:
		return
	var bw := b.w
	var bh := b.h
	var n := bw + 2 * bh
	var start := ticks % n
	var take_water := b.filter != 2
	var take_solids := b.filter != 1
	for k in n:
		if b.intake < 1.0:
			break
		# Rim cells in turn: the mouth (the row above), then the left and right sides.
		var idx := (start + k) % n
		var cx := 0
		var cy := 0
		var mouth := idx < bw
		if mouth:
			cx = b.x + idx
			cy = b.y - 1
		elif idx < bw + bh:
			cx = b.x - 1
			cy = b.y + idx - bw
		else:
			cx = b.x + bw
			cy = b.y + idx - bw - bh
		var m: int = sim.get_cell(cx, cy)
		# Liquids worth something (water, not lava), and any powder in the mouth.
		var mk := Mats.kind_of(m)
		var drink := take_water and mk == Mats.K_LIQUID and D.mat_res(m) >= 0
		var eat := mouth and take_solids and mk == Mats.K_POWDER
		if not (drink or eat):
			continue
		if b.power < D.HOPPER_POWER_PER_CELL:
			b.starved = true
			return
		b.power -= D.HOPPER_POWER_PER_CELL
		used_acc += D.HOPPER_POWER_PER_CELL
		sim.set_cell(cx, cy, D.AIR)
		for r: int in D.mat_yields(m):
			_bank(Vector2(cx, cy), r, 1.0 / D.CELLS_PER_UNIT)
		b.intake -= 1.0
		b.cells_taken += 1


func _spout(b: Building) -> void:
	b.sensor_wet = b.sensor_on and D.is_liquid(sim.get_cell(b.sx, b.sy))
	var pending := b.queue + b.inflight[D.R_WATER] * int(D.CELLS_PER_UNIT)
	var wants := b.enabled and b.connected and not b.sensor_wet and pending < D.SPOUT_QUEUE_MAX
	if wants:
		b.tokens = minf(b.tokens + D.SPOUT_RATES[b.rate_idx] * D.DT, 1.0)
	b.starved = wants and b.tokens >= 1.0 and not spout_can_pay(b)
	if b.queue > 0:
		# Under the middle first, then along the underside, then out of the sides.
		var outs: Array = [Vector2i(b.x + (b.w >> 1), b.y + b.h)]
		for k in b.w:
			outs.append(Vector2i(b.x + k, b.y + b.h))
		outs.append(Vector2i(b.x - 1, b.y + b.h - 1))
		outs.append(Vector2i(b.x + b.w, b.y + b.h - 1))
		for o: Vector2i in outs:
			var px := o.x
			var py := o.y
			var m: int = sim.get_cell(px, py)
			if D.is_thin(m):
				sim.set_cell(px, py, D.WATER)
				b.queue -= 1
				break


## Opening or closing costs a little power; a Floodgate with none stays as it is.
func _gate(b: Building) -> void:
	b.sensor_wet = D.is_liquid(sim.get_cell(b.sx, b.sy))
	var want := b.gate_mode == 1 or (b.gate_mode == 2 and b.sensor_wet)
	b.starved = false
	if want == b.gate_open:
		return
	if b.power < D.GATE_POWER:
		b.starved = true
		return
	b.power -= D.GATE_POWER
	used_acc += D.GATE_POWER
	set_gate(b, want)


## A Spout pays for each packet of water as it pours; it only asks for one it can pay for.
func spout_can_pay(b: Building) -> bool:
	return b.power - b.inflight[D.R_WATER] * D.SPOUT_POWER_PER_PACKET >= D.SPOUT_POWER_PER_PACKET


## Water landing on a Waterwheel's top runs through it and out underneath, and
## every cell makes a little power. The wheel keeps some for machines nearby; the
## network carries the rest to the Hub. Water pooled under it stalls it.
func _wheel(b: Building) -> void:
	var made := 0.0
	if b.enabled:
		b.gen_tokens = minf(b.gen_tokens + D.WHEEL_CELLS_PER_S * D.DT, 3.0)
		var cx := b.x + (b.w >> 1)
		var outs: Array = [Vector2i(cx, b.y + b.h), Vector2i(b.x, b.y + b.h), Vector2i(b.x + b.w - 1, b.y + b.h)]
		var start := ticks % b.w
		for k in b.w:
			if b.gen_tokens < 1.0:
				break
			var ix := b.x + (start + k) % b.w
			if sim.get_cell(ix, b.y - 1) != D.WATER:
				continue
			var exit := Vector2i(-1, -1)
			for o: Vector2i in outs:
				var m: int = sim.get_cell(o.x, o.y)
				if D.is_thin(m):
					exit = o
					break
			if exit.x < 0:
				break
			sim.set_cell(ix, b.y - 1, D.AIR)
			sim.set_cell(exit.x, exit.y, D.WATER)
			b.gen_tokens -= 1.0
			made += D.WHEEL_POWER_PER_CELL
	b.store[D.R_POWER] = minf(b.store[D.R_POWER] + made, D.GEN_BUFFER)
	b.flow = lerpf(b.flow, made / D.DT, 0.03)
	if b.flow < 0.005:
		b.flow = 0.0
	b.spin = fmod(b.spin + b.flow * D.DT * 2.0, TAU)


func _lamp(b: Building) -> void:
	b.starved = false
	if not b.enabled:
		return
	var burn := D.LAMP_POWER_PER_S * D.DT
	if b.power >= burn:
		b.power -= burn
		used_acc += burn
	else:
		b.power = 0.0
		b.starved = true


# ================================================================================
# Movers: Thumpers and Borers
# ================================================================================
# A mover steps a cell at a time into open space (air, gas or liquid), and
# whatever was in the cells it moves into ends up in the cells it leaves, so
# water it pushes through goes round it. Its link, hazard-scan entry, light and
# sight follow it without rebuilding the whole network.

static func _open(m: int) -> bool:
	return D.is_thin(m) or D.is_liquid(m)


## Whether `b` can move one cell by (dx, dy) (one of them 0).
func _can_shift(b: Building, dx: int, dy: int) -> bool:
	if dx != 0:
		var cx := b.x + b.w if dx > 0 else b.x - 1
		if cx < 2 or cx > D.W - 3:
			return false
		for yy in range(b.y, b.y + b.h):
			if not _open(sim.get_cell(cx, yy)):
				return false
		return true
	var cy := b.y + b.h if dy > 0 else b.y - 1
	if cy < 2 or cy > D.H - 3:
		return false
	for xx in range(b.x, b.x + b.w):
		if not _open(sim.get_cell(xx, cy)):
			return false
	return true


func _shift(b: Building, dx: int, dy: int) -> void:
	if dx != 0:
		var lead := b.x + b.w if dx > 0 else b.x - 1
		var tail := b.x if dx > 0 else b.x + b.w - 1
		for yy in range(b.y, b.y + b.h):
			var m: int = sim.get_cell(lead, yy)
			sim.set_cell(lead, yy, D.BUILDING)
			sim.set_cell(tail, yy, m)
		b.x += dx
	else:
		var lead := b.y + b.h if dy > 0 else b.y - 1
		var tail := b.y if dy > 0 else b.y + b.h - 1
		for xx in range(b.x, b.x + b.w):
			var m: int = sim.get_cell(xx, lead)
			sim.set_cell(xx, lead, D.BUILDING)
			sim.set_cell(xx, tail, m)
		b.y += dy
	b.moved += 1
	if not scan_dirty and b.scan_idx >= 0 and b.scan_idx < scan_list.size() and scan_list[b.scan_idx] == b:
		scan_rects[b.scan_idx * 5] = b.x
		scan_rects[b.scan_idx * 5 + 1] = b.y
	if not scan_dirty and b.seg_idx >= 0 and b.seg_idx < link_list.size() and link_list[b.seg_idx] == b:
		var c := b.center()
		link_segs[b.seg_idx * 4] = int(c.x)
		link_segs[b.seg_idx * 4 + 1] = int(c.y)


## Find `b` a relay from where it is now (a mover's link follows it about).
func _relink(b: Building) -> void:
	var old = b.link
	b.link = null if b.falling or not b.built else find_link(b.type, b.rect(), b)
	b.connected = b.link != null
	b.was_connected = b.connected
	if b.link != old:
		scan_stale = true
		if b.link != null and not scan_dirty and b.seg_idx >= 0 and b.seg_idx < link_list.size() and link_list[b.seg_idx] == b:
			var c: Vector2 = b.link.center()
			link_segs[b.seg_idx * 4 + 2] = int(c.x)
			link_segs[b.seg_idx * 4 + 3] = int(c.y)


## A homing Borer climbs back the way it came: it doesn't need ground under it.
func _clinging(b: Building) -> bool:
	return b.type == D.B_BORER and (b.mode == 1 or b.mode == 3)


## Liquid round the bottom of `b` (it sinks slowly through it).
func _wet(b: Building) -> bool:
	return D.is_liquid(sim.get_cell(b.x + (b.w >> 1), b.y + b.h)) or D.is_liquid(sim.get_cell(b.x - 1, b.y + b.h - 1)) \
			or D.is_liquid(sim.get_cell(b.x + b.w, b.y + b.h - 1))


## Throw `b` (a Thumper) with velocity (vx, vy) in cells a second. It's off the
## network until it lands.
func launch(b: Building, vx: float, vy: float) -> void:
	if not b.flying:
		b.flying = true
		b.falling = true
		fliers.append(b)
		b.fx = b.x
		b.fy = b.y
		_relink(b)
	b.vx = vx
	b.vy = vy


## Pick up a built Thumper and drag it: it follows `hold_at` until let go.
func grab_thumper(b: Building, at: Vector2) -> void:
	if b == null or b.dead or not b.built or b.type != D.B_THUMPER:
		return
	b.held = true
	b.hold_at = at
	launch(b, b.vx, b.vy)


## Let go of a dragged Thumper: it keeps the speed it had, so a flick throws it.
func release_thumper(b: Building) -> void:
	if b == null:
		return
	b.held = false


## Thrown and dragged Thumpers: gravity (slow through liquid), a cell at a time,
## stopping against anything solid; they land once something is under them.
func _update_fliers() -> void:
	for k in range(fliers.size() - 1, -1, -1):
		var b: Building = fliers[k]
		if b.dead:
			fliers.remove_at(k)
			continue
		if b.held:
			var want := b.hold_at - Vector2(b.w, b.h) * 0.5
			var v := (want - Vector2(b.fx, b.fy)) * 10.0
			if v.length() > D.DRAG_SPEED:
				v = v.normalized() * D.DRAG_SPEED
			b.vx = v.x
			b.vy = v.y
		else:
			b.vy = minf(b.vy + D.FALL_ACCEL * D.DT, D.FALL_MAX)
			if _wet(b):
				b.vx *= 0.9
				b.vy = clampf(b.vy, -D.FLY_WATER_MAX, D.FLY_WATER_MAX)
		b.fx += b.vx * D.DT
		b.fy += b.vy * D.DT
		var tx := roundi(b.fx)
		var ty := roundi(b.fy)
		var guard := 0
		while (b.x != tx or b.y != ty) and guard < 8:
			guard += 1
			var ddx := tx - b.x
			var ddy := ty - b.y
			if ddx != 0 and absi(ddx) >= absi(ddy):
				var sx := signi(ddx)
				if _can_shift(b, sx, 0):
					_shift(b, sx, 0)
				else:
					b.vx = 0.0 if b.held else -b.vx * 0.3
					b.fx = b.x
					tx = b.x
			else:
				var sy := signi(ddy)
				if _can_shift(b, 0, sy):
					_shift(b, 0, sy)
				else:
					b.vy = 0.0
					b.fy = b.y
					ty = b.y
		if not b.held and b.vy >= 0.0 and not _can_shift(b, 0, 1):
			fliers.remove_at(k)
			_land_flier(b)


func _land_flier(b: Building) -> void:
	b.flying = false
	b.falling = false
	b.vx = 0.0
	b.vy = 0.0
	b.fx = b.x
	b.fy = b.y
	_relink(b)
	scan_stale = true


## A Thumper goes off every few seconds while it has power: a blast just under
## it craters the ground (what breaks flies as debris) and throws it up.
func _thumper(b: Building) -> void:
	b.starved = false
	if not b.enabled:
		return
	b.work = minf(b.work + D.DT, 60.0)
	if b.work < thump_interval():
		return
	var cost := thump_cost()
	if b.power < cost:
		b.starved = true
		return
	b.work = 0.0
	b.power -= cost
	used_acc += cost
	var pw := thump_power()
	b.blasts += 1
	# The charge sits a little under it, and its body is out of the way for the
	# blast, so what goes up flies clear of the crater instead of hitting it.
	for yy in range(b.y, b.y + b.h):
		for xx in range(b.x, b.x + b.w):
			sim.set_cell(xx, yy, D.AIR)
	blast(Vector2i(b.x + (b.w >> 1), b.y + b.h + D.THUMP_DEPTH), thump_radius(), pw, b)
	for yy in range(b.y, b.y + b.h):
		for xx in range(b.x, b.x + b.w):
			sim.set_cell(xx, yy, D.BUILDING)
	if not b.dead:
		launch(b, rng.randf_range(-D.THUMP_DRIFT, D.THUMP_DRIFT), -(D.THUMP_LAUNCH + 2.0 * pw))


## The cells a Borer's front faces heading `dir` (0 down, 1 left, 2 right, 3 up).
static func _face(b: Building, dir: int) -> Array:
	var out: Array = []
	match dir:
		1:
			for k in b.h:
				out.append(Vector2i(b.x - 1, b.y + k))
		2:
			for k in b.h:
				out.append(Vector2i(b.x + b.w, b.y + k))
		3:
			for k in b.w:
				out.append(Vector2i(b.x + k, b.y - 1))
		_:
			for k in b.w:
				out.append(Vector2i(b.x + k, b.y + b.h))
	return out


const BORER_STEPS := [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]


func set_borer_dir(b: Building, dir: int) -> void:
	b.dir = dir
	b.stuck = ""


## A Borer grinds the rock in front of it and moves into the space. It runs on
## its reserve out past the network; with Homing it heads back at half power.
func _borer(b: Building) -> void:
	b.starved = false
	if not b.enabled:
		return
	var cap := reserve_cap(b)
	b.work = minf(b.work + D.DT, 2.0)
	if b.mode == 0 and researched.has("homing") and b.power <= cap * 0.5 and not b.connected and b.trail.size() > 1:
		b.mode = 1
		b.trail_idx = b.trail.size() - 1
		b.stuck = ""
		alert("info", "Borer heading home to recharge, from depth %d" % b.y, b.center())
	elif b.mode == 1 and b.connected and b.power >= cap - 1.0:
		b.mode = 3              # back in reach and topped up on the way: back to work
	if b.mode == 2:
		if b.power >= cap - 1.0:
			b.mode = 3
		return
	if b.mode == 1 or b.mode == 3:
		_borer_retrace(b)
	else:
		_borer_bore(b)


## Dig one cell of `m` at `c` if there's time and power banked: true if it did.
func _borer_dig(b: Building, c: Vector2i, m: int) -> bool:
	var cost := 1.0 / (D.bore_rate(m) * b.w * D.BORER_SPEED)
	if b.work < cost:
		return false
	var pc := D.power_per_cell(m)
	if b.power < pc:
		b.starved = true
		return false
	b.work -= cost
	b.power -= pc
	used_acc += pc
	sim.set_cell(c.x, c.y, D.AIR)
	excavated(c)
	for r: int in D.mat_yields(m):
		_bank(Vector2(c), r, 1.0 / D.CELLS_PER_UNIT)
	b.cells_bored += 1
	cells_drilled += 1
	_breach_check(b, c)
	return true


## One step along (dx, dy), if there's time and power for it.
func _borer_step(b: Building, dx: int, dy: int) -> bool:
	var mc := 1.0 / D.BORER_MOVE_PER_S
	if b.work < mc:
		return false
	if b.power < D.BORER_MOVE_POWER:
		b.starved = true
		return false
	b.work -= mc
	b.power -= D.BORER_MOVE_POWER
	used_acc += D.BORER_MOVE_POWER
	_shift(b, dx, dy)
	_relink(b)
	if b.moved % 2 == 0:
		reveal(b.center(), D.REVEAL_DIG)
	return true


func _borer_bore(b: Building) -> void:
	var guard := 0
	while guard < 8:
		guard += 1
		var face := _face(b, b.dir)
		var open_n := 0
		var lava_n := 0
		var hard := ""
		var did := false
		var cut := false
		for c: Vector2i in face:
			var m: int = sim.get_cell(c.x, c.y)
			if can_cut(m):
				cut = true
				did = _borer_dig(b, c, m)
				break
			elif _open(m):
				open_n += 1
				if m == D.LAVA:
					lava_n += 1
			elif m == D.OBSIDIAN:
				hard = "Obsidian ahead: it needs the Obsidian Saw."
			elif m == D.BUILDING:
				hard = "A building is in the way."
			else:
				hard = "%s ahead: it can't cut that." % D.mat_name(m)
		if cut:
			if not did:
				return
			b.stuck = ""
			continue
		if open_n < face.size():
			b.stuck = hard
			return
		if lava_n == face.size():
			b.stuck = "Lava ahead: it won't bore into a lava body."
			return
		var st: Vector2i = BORER_STEPS[b.dir]
		if not _can_shift(b, st.x, st.y):
			b.stuck = "The edge of the map."
			return
		if not _borer_step(b, st.x, st.y):
			return
		b.stuck = ""
		b.trail.append(Vector2i(b.x, b.y))


## Homing: back along the trail toward where it was placed (mode 1), or out
## along it to where it left off (mode 3). Fill that has come down in the way
## gets dug; a building in the way stops it.
func _borer_retrace(b: Building) -> void:
	var guard := 0
	while guard < 4:
		guard += 1
		var at := Vector2i(b.x, b.y)
		var next := at
		if b.mode == 1:
			if b.trail_idx <= 0:
				b.mode = 2
				b.trail_idx = 0
				return
			next = b.trail[b.trail_idx - 1]
		else:
			if b.trail_idx >= b.trail.size() - 1:
				b.mode = 0
				b.trail_idx = b.trail.size() - 1
				return
			next = b.trail[b.trail_idx + 1]
		var d := next - at
		if d == Vector2i.ZERO:
			b.trail_idx += -1 if b.mode == 1 else 1
			continue
		if absi(d.x) + absi(d.y) != 1:
			# The trail doesn't join up (it was moved): bore on from here.
			b.mode = 0
			b.trail = [at]
			b.trail_idx = 0
			return
		var dir := BORER_STEPS.find(d)
		for c: Vector2i in _face(b, dir):
			var m: int = sim.get_cell(c.x, c.y)
			if _open(m):
				continue
			if can_cut(m):
				if not _borer_dig(b, c, m):
					return
				continue
			b.stuck = "Something is in its tunnel; it can't get past."
			return
		if not _can_shift(b, d.x, d.y):
			return
		if not _borer_step(b, d.x, d.y):
			return
		b.stuck = ""
		b.trail_idx += -1 if b.mode == 1 else 1


## Springs add water where there's room: into their own cell, or on top of the
## pool sitting over them, so a drained aquifer fills back up.
func _springs() -> void:
	spring_acc += D.SPRING_CELLS_PER_S * D.DT
	if spring_acc < 1.0:
		return
	spring_acc -= 1.0
	for c: Vector2i in info.get("springs", []):
		var y := c.y
		var guard := 0
		while guard < 64 and sim.get_cell(c.x, y) == D.WATER:
			y -= 1
			guard += 1
		var m: int = sim.get_cell(c.x, y)
		if D.is_thin(m):
			sim.set_cell(c.x, y, D.WATER)


func _power_stats() -> void:
	var made := D.HUB_POWER_PER_S
	for b: Building in buildings:
		if b.type == D.B_WATERWHEEL and b.built:
			made += b.flow
	power_made = made
	power_used = lerpf(power_used, used_acc / (30.0 * D.DT), 0.5)
	used_acc = 0.0
	research_rate = lerpf(research_rate, research_acc / (30.0 * D.DT), 0.5)
	research_acc = 0.0


func set_gate(b: Building, open: bool) -> void:
	b.gate_open = open
	for yy in range(b.y, b.y + b.h):
		for xx in range(b.x, b.x + b.w):
			var m: int = sim.get_cell(xx, yy)
			if open:
				if m == D.BUILDING:
					sim.set_cell(xx, yy, D.AIR)
			else:
				sim.set_cell(xx, yy, D.BUILDING)


## Lava, fire, corrosion, steam and drowning checks, ten times a second; then
## the same for links.
func _damage_scan() -> void:
	if scan_dirty:
		_rebuild_scan()
	if scan_list.is_empty():
		return
	var dt := 6.0 * D.DT
	var list := scan_list
	for k: int in scan_gates:
		var g: Building = list[k]
		scan_rects[k * 5 + 4] = 1 if g.gate_open else 0
	var hz: PackedInt32Array = sim.hazards_batch(scan_rects, D.CORRODE_REACH)
	var unheld: Array = []
	for k in list.size():
		var o := k * 8
		var lava := hz[o]
		var fire := hz[o + 1]
		var steam := hz[o + 2]
		var corrode := hz[o + 5]
		var b: Building = list[k]
		# Nothing solid touching it: held up only if a building beside it is.
		if hz[o + 6] == 0 and not b.falling and not b.dead and not _clinging(b):
			unheld.append(b)
		# Most buildings, most of the time: nothing near them, nothing to count down.
		if lava == 0 and fire == 0 and steam == 0 and corrode == 0 \
				and (not D.is_conduit(b.type) or (hz[o + 3] == 0 and not b.drowned and b.wet_scans == 0)):
			continue
		if b.dead:
			continue
		var liquid := hz[o + 3]
		var open := hz[o + 4]
		if lava > 0:
			if D.is_conduit(b.type):
				_destroy(b, "lava")
				continue
			_hurt(b, D.LAVA_DPS * dt, "lava")
			if b.dead:
				continue
		var ring := 2 * (b.w + b.h)
		# Flames burn any building, in proportion to how much of its outline they
		# wrap (full damage from half of it).
		if fire > 0:
			_hurt(b, D.FIRE_DPS * clampf(fire / (ring * 0.5), 0.0, 1.0) * dt, "fire")
			if b.dead:
				continue
		# Sulfur (a deposit, grit or fumes) within a few cells eats it slowly.
		if corrode > 0:
			_hurt(b, D.CORRODE_DPS * clampf(corrode / D.CORRODE_FULL, 0.0, 1.0) * dt, "corrosion")
			if b.dead:
				continue
		# Steam scalds Conduits, the network's weak point, in proportion to how much
		# of the outline it wraps (full damage from half of it). Machines shrug it off:
		# an obsidian farm has to live in its own steam.
		if steam > 0 and D.is_conduit(b.type):
			var share := clampf(steam / (ring * 0.5), 0.0, 1.0)
			_hurt(b, D.STEAM_DPS * share * dt, "steam")
			if b.dead:
				continue
		if D.is_conduit(b.type) and b.built:
			# Hysteresis, so a waterline lapping at a Conduit doesn't flicker it:
			# drowned after 0.5 s fully underwater; back in service only after 2 s
			# with a quarter of its outline in the open.
			var under := liquid > 0 and open == 0
			var clear := open * 4 >= 2 * (b.w + b.h)
			var flip := under if not b.drowned else clear
			if flip:
				b.wet_scans += 1
				if b.wet_scans >= (5 if under else 20):
					b.wet_scans = 0
					b.drowned = under
					net_dirty = true
					if under:
						alert("drowned", "%s drowned at depth %d: it can't pass the network on" % [b.title(), int(b.center().y)], b.center())
					else:
						alert("info", "%s back in service at depth %d" % [b.title(), int(b.center().y)], b.center())
			else:
				b.wet_scans = 0
	if not unheld.is_empty():
		_settle(unheld)


## The hazard scans' inputs, rebuilt when buildings come or go or links change.
func _rebuild_scan() -> void:
	scan_dirty = false
	strut_list = []
	var shields := PackedInt32Array()
	var damp := researched.has("tremor_dampers")
	for b: Building in buildings:
		if b.type == D.B_STRUT and not b.dead:
			strut_list.append(b)
			if damp:
				shields.append(int(b.center().x))
				shields.append(int(b.center().y))
				shields.append(int(D.STRUT_DAMP_R + maxf(b.w, b.h) * 0.5))
	sim.set_shields(shields)
	scan_list = []
	scan_rects = PackedInt32Array()
	scan_gates = PackedInt32Array()
	link_list = []
	link_segs = PackedInt32Array()
	# Which buildings touch (corners count), through an 8x8 bucket hash.
	var grid := {}
	by_id.clear()
	for b: Building in buildings:
		b.touching = PackedInt32Array()
		if b.dead:
			continue
		by_id[b.id] = b
		for gy in range((b.y - 1) >> 3, ((b.y + b.h) >> 3) + 1):
			for gx in range((b.x - 1) >> 3, ((b.x + b.w) >> 3) + 1):
				var key := gy * 64 + gx
				if not grid.has(key):
					grid[key] = []
				var cell: Array = grid[key]
				for o: Building in cell:
					if not b.touching.has(o.id) and b.rect().grow(1).intersects(o.rect()):
						b.touching.append(o.id)
						o.touching.append(b.id)
				cell.append(b)
	# Light and sight that only change when a building comes, goes, finishes or moves.
	still_lights = PackedInt32Array()
	still_sights = PackedInt32Array()
	lit_list = []
	_circle(still_lights, hub.center(), D.LIGHT_HUB)
	_circle(still_sights, hub.center(), D.SIGHT_HUB)
	_circle(still_lights, crucible.center(), D.LIGHT_CRUCIBLE)
	for b: Building in buildings:
		if D.is_mover(b.type) and b.built and not b.dead:
			lit_list.append(b)       # its light and sight go where it goes
			continue
		if b.dead or not b.built or b.falling or b.type == D.B_HUB or b.type == D.B_CRUCIBLE:
			continue
		if D.is_conduit(b.type):
			_circle(still_sights, b.center(), D.SIGHT_CONDUIT)
			continue
		_circle(still_lights, b.center(), D.LIGHT_PILOT)
		_circle(still_sights, b.center(), D.SIGHT_MACHINE)
		if b.type == D.B_LAMP or b.type == D.B_DRILL:
			lit_list.append(b)
	for b: Building in buildings:
		b.scan_idx = -1
		b.seg_idx = -1
		if b.dead:
			continue
		if b.type != D.B_HUB and b.type != D.B_CRUCIBLE and not b.fixed:
			if b.type == D.B_FLOODGATE:
				scan_gates.append(scan_list.size())
			b.scan_idx = scan_list.size()
			scan_list.append(b)
			scan_rects.append(b.x)
			scan_rects.append(b.y)
			scan_rects.append(b.w)
			scan_rects.append(b.h)
			scan_rects.append(0)
		var rl = b.link
		if rl != null and not rl.dead:
			var a := b.center()
			var c: Vector2 = rl.center()
			b.seg_idx = link_list.size()
			link_list.append(b)
			link_segs.append(int(a.x))
			link_segs.append(int(a.y))
			link_segs.append(int(c.x))
			link_segs.append(int(c.y))


## Buildings with no ground touching them: those joined (through buildings that
## touch) to one that has ground stay put; the rest come loose.
func _settle(unheld: Array) -> void:
	var loose := {}
	for b: Building in unheld:
		loose[b] = true
	var queue: Array = []
	for b: Building in unheld:
		for id: int in b.touching:
			var o: Building = by_id.get(id)
			if o != null and not o.dead and not o.falling and not loose.has(o):
				queue.append(b)
				break
	while not queue.is_empty():
		var b: Building = queue.pop_back()
		if not loose.has(b):
			continue
		loose.erase(b)
		for id: int in b.touching:
			var o: Building = by_id.get(id)
			if o != null and loose.has(o):
				queue.append(o)
	for b: Building in loose:
		_come_loose(b)


func _come_loose(b: Building) -> void:
	if b.type == D.B_STRUT:
		_destroy(b, "losing its anchors")
		return
	if b.type == D.B_THUMPER:
		launch(b, 0.0, 0.0)
		return
	b.falling = true
	b.fall_v = 0.0
	b.fall_acc = 0.0
	b.fell = 0
	fallers.append(b)
	net_dirty = true
	scan_dirty = true
	alert("loose", "%s came loose at depth %d" % [b.title(), b.y], b.center())


## Falling buildings drop a cell at a time, swapping places with the air, gas or
## liquid under them, until something solid (or another building) is underneath.
func _update_falling() -> void:
	for k in range(fallers.size() - 1, -1, -1):
		var b: Building = fallers[k]
		if b.dead:
			fallers.remove_at(k)
			continue
		b.fall_v = minf(b.fall_v + D.FALL_ACCEL * D.DT, D.FALL_MAX)
		b.fall_acc += b.fall_v * D.DT
		var landed := false
		while b.fall_acc >= 1.0:
			b.fall_acc -= 1.0
			if not _can_drop(b):
				landed = true
				break
			_drop(b)
		if landed:
			fallers.remove_at(k)
			_land(b)


func _can_drop(b: Building) -> bool:
	var yb := b.y + b.h
	if yb >= D.H - 2:
		return false
	for xx in range(b.x, b.x + b.w):
		if D.is_solid(sim.get_cell(xx, yb)):
			return false
	return true


func _drop(b: Building) -> void:
	var yb := b.y + b.h
	for xx in range(b.x, b.x + b.w):
		var below: int = sim.get_cell(xx, yb)
		for yy in range(yb, b.y, -1):
			sim.set_cell(xx, yy, sim.get_cell(xx, yy - 1))
		sim.set_cell(xx, b.y, below)
	b.y += 1
	b.fell += 1
	# A Drill sinking into its own channel has that much less channel below it.
	if b.type == D.B_DRILL and b.dir == 0:
		b.reach = maxi(b.reach - 1, 0)
		b.scan_from = 0
	elif b.type == D.B_BORER and b.mode == 0:
		b.trail.append(Vector2i(b.x, b.y))   # so Homing can climb back the way it fell
	scan_dirty = true


func _land(b: Building) -> void:
	b.falling = false
	b.fall_v = 0.0
	b.fall_acc = 0.0
	if b.type == D.B_DRILL and b.dir != 0:
		b.reach = 0            # its channel is somewhere above now
		b.scan_from = 0
	net_dirty = true
	scan_dirty = true
	b.flash = 0.5
	alert("loose", "%s landed %d cells down, at depth %d" % [b.title(), b.fell, b.y], b.center())
	if b.type == D.B_DRILL:
		_refresh_sense()


const HURT_ALERTS := {
	"lava": ["lava", "Lava reaching a %s at depth %d"],
	"steam": ["steam", "Steam scalding a %s at depth %d"],
	"fire": ["fire", "Fire burning a %s at depth %d"],
	"corrosion": ["corrosion", "Sulfur corroding a %s at depth %d"],
	"blast": ["blast", "Blast hit a %s at depth %d"],
}


func _hurt(b: Building, amount: float, cause: String) -> void:
	b.hp -= amount
	damaged[b] = true
	b.flash = 0.25
	# A Thumper singes itself on its own flash every blast: only say so once it's in trouble.
	var routine: bool = b.type == D.B_THUMPER and (cause == "fire" or cause == "blast") and b.hp > b.max_hp * 0.5
	if b.alert_cd <= 0.0 and not routine:
		b.alert_cd = 10.0
		var a: Array = HURT_ALERTS.get(cause, HURT_ALERTS["lava"])
		alert(a[0], a[1] % [b.title(), int(b.center().y)], b.center())
	if b.hp <= 0.0:
		_destroy(b, cause)


# ================================================================================
# Links
# ================================================================================
# A link is a building's line to the relay it draws packets through (a relay's
# is the line to the next relay toward a source). Fire, sulfur and lava on the
# line wear it down; a broken link is out of the network (the building finds
# another relay in range if there is one) until a Stone arrives to mend it. Worn
# links ask for their Stone at half strength.

## A link's key, the same from either end.
static func _link_key(a: Building, b: Building) -> int:
	return mini(a.id, b.id) * 1000000 + maxi(a.id, b.id)


## 0..1: what's left of the link between `a` and `b` (0 when broken).
func link_health(a: Building, b: Building) -> float:
	var key := _link_key(a, b)
	if broken_links.has(key):
		return 0.0
	return float(link_hp.get(key, D.LINK_HP)) / D.LINK_HP


func hurt_link(a: Building, rl: Building, amount: float, cause: String) -> void:
	if a == null or rl == null or a.dead or rl.dead:
		return
	var key := _link_key(a, rl)
	if broken_links.has(key):
		return
	link_ends[key] = [a, rl]
	var hp: float = float(link_hp.get(key, D.LINK_HP)) - amount
	if hp > 0.0:
		link_hp[key] = hp
		return
	link_hp.erase(key)
	broken_links[key] = true
	net_dirty = true
	var mid := (a.center() + rl.center()) * 0.5
	alert("link_broken", "Link broken by %s at depth %d; a Stone will mend it" % [cause, int(mid.y)], mid)


func _mend_link(key: int) -> void:
	link_fixes.erase(key)
	link_hp.erase(key)
	if broken_links.has(key):
		broken_links.erase(key)
		net_dirty = true
	link_ends.erase(key)


## Where a Stone goes to mend link `key`: whichever end the network can reach,
## the relay end first.
func _fix_target(key: int) -> Building:
	var ends: Array = link_ends.get(key, [])
	if ends.size() < 2:
		return null
	for e: Building in [ends[1], ends[0]]:
		if not e.dead and e.built and e.connected and _target_relay(e) >= 0:
			return e
	return null


## Forget every link `b` is an end of (it's gone).
func _forget_links(b: Building) -> void:
	for key: int in link_ends.keys():
		var ends: Array = link_ends[key]
		if ends[0] == b or ends[1] == b:
			link_ends.erase(key)
			link_hp.erase(key)
			broken_links.erase(key)
			link_fixes.erase(key)


## Hazards along the links in use, checked with the buildings.
func _link_scan(dt: float) -> void:
	if scan_dirty:
		_rebuild_scan()
	var list := link_list
	if list.is_empty():
		return
	var hz: PackedInt32Array = sim.segments_batch(link_segs)
	for k in list.size():
		var fire := hz[k * 3]
		var cor := hz[k * 3 + 1]
		var hot := hz[k * 3 + 2]
		if fire == 0 and cor == 0 and hot == 0:
			continue
		var b: Building = list[k]
		if b.dead or b.link == null or b.link.dead:
			continue
		var dmg := D.LINK_FIRE_DPS * minf(fire / 4.0, 1.0) + D.LINK_CORRODE_DPS * minf(cor / 8.0, 1.0)
		if hot > 0:
			dmg += D.LINK_LAVA_DPS
		var cause := "fire" if fire > 0 else ("lava" if hot > 0 else "corrosion")
		hurt_link(b, b.link, dmg * dt, cause)


# ================================================================================
# Blasts
# ================================================================================

## A blast at `at`: the sim breaks what the blast can beat and throws it as
## debris; buildings and links nearby take damage by distance.
## `source` (a Thumper) is spared, and so is its own link.
func blast(at: Vector2i, radius: float, power: int, source: Building = null) -> int:
	var broke: int = sim.explode(at.x, at.y, radius, power)
	var p := Vector2(at) + Vector2(0.5, 0.5)
	for b: Building in buildings.duplicate():
		if b.dead or b.type == D.B_HUB or b.type == D.B_CRUCIBLE or b.fixed or b == source:
			continue
		var d := dist_to_rect(p, b.rect())
		if d <= radius:
			_hurt(b, D.BLAST_DAMAGE * power * (1.0 - d / (radius + 1.0)), "blast")
	for b: Building in buildings:
		if b.dead or b.link == null or b.link.dead or b == source:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, b.center(), b.link.center())
		var d := p.distance_to(q)
		if d <= radius:
			hurt_link(b, b.link, D.LINK_BLAST * power * (1.0 - d / (radius + 1.0)), "a blast")
	shake = maxf(shake, 0.5 if source == null else 0.12)
	reveal(p, radius + 4.0)
	return broke


# ================================================================================
# Network and packets
# ================================================================================

func _rebuild_network() -> void:
	net_dirty = false
	scan_dirty = true
	relays.clear()
	relay_index.clear()
	relay_grid.clear()
	for b: Building in buildings:
		b.connected = false
		b.link = null
		b.parent = null
		b.net_dist = INF
		b.active_relay = false
		if b.type == D.B_HUB or (D.is_conduit(b.type) and b.built and b.enabled and not b.falling):
			b.active_relay = true
			var i := relays.size()
			relay_index[b] = i
			relays.append(b)
			var c := b.center()
			var key := (int(c.y) >> BUCKET_SHIFT) * GRID_W + clampi(int(c.x) >> BUCKET_SHIFT, 0, GRID_W - 1)
			if not relay_grid.has(key):
				relay_grid[key] = []
			relay_grid[key].append(i)
	var n := relays.size()
	# Relay-to-relay links, looked up through the bucket grid.
	var adj: Array = []
	for i in n:
		adj.append([])
	for i in n:
		var ci: Vector2 = relays[i].center()
		var ri := D.relay_range(relays[i].type)
		var reach := int(ceil(D.MAST_RANGE)) + 1
		var area := Rect2i(int(ci.x) - reach, int(ci.y) - reach, 2 * reach + 1, 2 * reach + 1)
		for j: int in _relays_near(area):
			if j <= i:
				continue
			var d := ci.distance_to(relays[j].center())
			if d <= maxf(ri, D.relay_range(relays[j].type)) and (broken_links.is_empty() or not broken_links.has(_link_key(relays[i], relays[j]))):
				adj[i].append(Vector2(j, d))
				adj[j].append(Vector2(i, d))
	# Sources: the Hub, then every built Cache and generator, each entering the
	# network at the nearest relay in reach. A Cache on a cut-off stretch keeps
	# that stretch running.
	src_list.clear()
	src_dist.clear()
	src_prev.clear()
	src_entry = PackedInt32Array()
	var link_reach := int(ceil(D.LINK_RANGE)) + 1
	for b: Building in buildings:
		if not b.built or not b.is_source() or b.falling:
			continue
		var entry := -1
		var d0 := 0.0
		if b == hub:
			entry = relay_index[hub]
		else:
			# The nearest relay in reach, preferring one that isn't drowned.
			var best := INF
			for i: int in _relays_near(b.rect().grow(link_reach)):
				var dd := dist_to_rect(relays[i].center(), b.rect())
				if dd > D.LINK_RANGE or broken_links.has(_link_key(b, relays[i])):
					continue
				var score := dd + (1000.0 if relays[i].drowned else 0.0)
				if score < best:
					best = score
					entry = i
					d0 = dd
		if entry < 0:
			continue
		var dist := PackedFloat64Array()
		dist.resize(n)
		dist.fill(INF)
		var prev := PackedInt32Array()
		prev.resize(n)
		prev.fill(-1)
		var done := PackedByteArray()
		done.resize(n)
		dist[entry] = d0
		var heap: Array = []
		_heap_push(heap, d0, entry)
		while heap.size() > 0:
			var u := int(_heap_pop(heap).y)
			if done[u] != 0:
				continue
			done[u] = 1
			if relays[u].drowned:
				continue            # a drowned Conduit can't pass the network on
			var du := dist[u]
			for e: Vector2 in adj[u]:
				var v := int(e.x)
				var nd := du + e.y
				if done[v] == 0 and nd < dist[v]:
					dist[v] = nd
					prev[v] = u
					_heap_push(heap, nd, v)
		src_list.append(b)
		src_dist.append(dist)
		src_prev.append(prev)
		src_entry.append(entry)
	# A relay is connected when some source reaches it; its parent points back
	# along the shortest way to the nearest source (drawn as the network tree).
	for i in n:
		var rl: Building = relays[i]
		for k in src_list.size():
			var d: float = src_dist[k][i]
			if d < rl.net_dist:
				rl.net_dist = d
				rl.connected = true
				var pi: int = src_prev[k][i]
				rl.parent = relays[pi] if pi >= 0 else null
	# Everything else links to the best connected relay in range.
	var lost := 0
	var lost_at := Vector2.ZERO
	for b: Building in buildings:
		if b.type == D.B_HUB:
			continue
		if b.active_relay:
			b.link = b.parent
		elif b.falling or not D.needs_link(b.type):
			b.link = null
			b.connected = false
		else:
			b.link = find_link(b.type, b.rect(), b)
			b.connected = b.link != null
		if b.built and b.was_connected and not b.connected and not b.falling:
			lost += 1
			lost_at = b.center()
			b.flash = 1.0
		b.was_connected = b.connected
	caches.clear()
	for b: Building in buildings:
		if b.type == D.B_CACHE and b.built and b.connected:
			caches.append(b)
	if lost > 0:
		alert("link", "%d building%s lost %s link" % [lost, "" if lost == 1 else "s", "its" if lost == 1 else "their"], lost_at)
	if crucible.connected and not crucible_linked_once:
		crucible_linked_once = true
		alert("crucible", "The Crucible is connected. Stock up, then Activate.", crucible.center())
	_validate_packets()


## A small binary min-heap of Vector2(key, index), for the path search.
static func _heap_push(h: Array, key: float, i: int) -> void:
	h.append(Vector2(key, i))
	var k := h.size() - 1
	while k > 0:
		var p := (k - 1) >> 1
		if h[p].x <= h[k].x:
			break
		var tmp: Vector2 = h[p]
		h[p] = h[k]
		h[k] = tmp
		k = p


static func _heap_pop(h: Array) -> Vector2:
	var top: Vector2 = h[0]
	var last: Vector2 = h.pop_back()
	var n := h.size()
	if n > 0:
		h[0] = last
		var k := 0
		while true:
			var l := 2 * k + 1
			if l >= n:
				break
			var m := l
			if l + 1 < n and h[l + 1].x < h[l].x:
				m = l + 1
			if h[k].x <= h[m].x:
				break
			var tmp: Vector2 = h[k]
			h[k] = h[m]
			h[m] = tmp
			k = m
	return top


func _validate_packets() -> void:
	for k in range(packets.size() - 1, -1, -1):
		var p: Packet = packets[k]
		var ok: bool = not p.target.dead and p.target.connected
		if ok:
			for hi in range(maxi(p.seg - 1, 0), p.hops.size()):
				var rl: Building = p.hops[hi]
				if rl.dead or not rl.active_relay or not rl.connected \
						or (rl.drowned and hi < p.hops.size() - 1):
					ok = false
					break
		if not ok:
			_refund(p)
			packets.remove_at(k)


## What a source holds (the Hub's is the main stockpile).
func store_of(src: Building) -> PackedFloat64Array:
	return stock if src == hub else src.store


func _refund(p: Packet) -> void:
	_fix_done(p)
	var src: Building = p.source
	if src != null and not src.dead and src != hub:
		src.store[p.res] += 1.0
	else:
		stock[p.res] += 1.0
	if p.target == crucible:
		c_inflight[p.res] -= 1
	else:
		p.target.inflight[p.res] -= 1


## Everything held anywhere: the Hub plus every Cache and generator.
func total(r: int) -> float:
	var t: float = stock[r]
	for b: Building in buildings:
		if b.built and (b.type == D.B_CACHE or b.type == D.B_WATERWHEEL):
			t += b.store[r]
	return t


## The relay a packet for `target` ends its trip at (the Hub is its own), or -1.
func _target_relay(target: Building) -> int:
	if target == hub:
		return relay_index.get(hub, -1)
	var link: Building = target.link
	if link == null or not relay_index.has(link):
		return -1
	return relay_index[link]


## The path a packet from source k takes to `target`, or null when there's none.
func _route(k: int, target: Building) -> Packet:
	var e := _target_relay(target)
	if e < 0:
		return null
	var dist: PackedFloat64Array = src_dist[k]
	if dist[e] == INF:
		return null
	var prev: PackedInt32Array = src_prev[k]
	var entry: int = src_entry[k]
	var chain: Array = []
	var i := e
	var guard := 0
	while i >= 0 and guard < 1000:
		guard += 1
		chain.push_front(relays[i])
		if i == entry:
			break
		i = prev[i]
	if chain.is_empty() or chain[0] != relays[entry]:
		return null
	var src: Building = src_list[k]
	var p := Packet.new()
	p.source = src
	p.hops = chain
	if src != hub:
		p.pts.append(src.center())
	for node: Building in chain:
		p.pts.append(node.center())
	p.pts.append(target.center())
	p.pos = p.pts[0]
	return p


## The nearest source (by network distance) that holds `r` and has a packet to
## send. `mode` 0: any source; 1: not a Cache (Cache top-ups); 2: only a
## generator with more than it keeps for itself (surplus going to the Hub).
func _best_source(target: Building, r: int, mode: int) -> int:
	var e := _target_relay(target)
	if e < 0:
		return -1
	var best := -1
	var best_d := INF
	for k in src_list.size():
		var s: Building = src_list[k]
		if s == target or s.dead or s.send_tokens < 1.0:
			continue
		if mode >= 1 and s.type == D.B_CACHE:
			continue
		if mode == 2 and (s.type != D.B_WATERWHEEL or s.store[r] < D.GEN_BUFFER * 0.5 + 1.0):
			continue
		if store_of(s)[r] < 1.0:
			continue
		var d: float = src_dist[k][e]
		if d < best_d:
			best_d = d
			best = k
	return best


func _dispatch() -> void:
	var ready_n := 0
	for s: Building in src_list:
		var rate := D.HUB_PACKETS_PER_S
		if s.type == D.B_CACHE:
			rate = D.CACHE_PACKETS_PER_S
		elif s.type == D.B_WATERWHEEL:
			rate = D.GEN_PACKETS_PER_S
		s.send_tokens = minf(s.send_tokens + rate * D.DT, 1.0)
		if s.send_tokens >= 1.0:
			ready_n += 1
	if cstate == 1:
		c_tokens = minf(c_tokens + D.CRUCIBLE_PACKETS_PER_S * D.DT, 1.0)
	while send_log.size() > 0 and game_time - send_log[0] > 1.0:
		send_log.pop_front()
	if dispatch_wait > 0:
		dispatch_wait -= 1
		return
	if ready_n == 0:
		return
	# What the sources with a packet to send could send at all.
	var avail := PackedByteArray()
	avail.resize(D.NRES)
	var any := false
	for s: Building in src_list:
		if s.send_tokens < 1.0:
			continue
		var st := store_of(s)
		for r in D.NRES:
			if st[r] >= 1.0:
				avail[r] = 1
				any = true
	var sent := 0
	if any:
		for rq: Array in _requests(avail):
			var target: Building = rq[0]
			var r: int = rq[1]
			var want: int = rq[2]
			var mode: int = rq[3]
			var fix: int = rq[4]
			while want > 0:
				var k := _best_source(target, r, mode)
				if k < 0:
					break
				var p := _route(k, target)
				if p == null:
					break
				var src: Building = src_list[k]
				p.res = r
				p.target = target
				p.fix = fix
				if fix == FIX_BUILDING:
					target.repairing = true
				elif fix >= 0:
					link_fixes[fix] = true
				store_of(src)[r] -= 1.0
				src.send_tokens -= 1.0
				if src.send_tokens < 1.0:
					ready_n -= 1
				if src == hub:
					send_log.append(game_time)
				if target == crucible:
					c_inflight[r] += 1
					c_tokens -= 1.0
				else:
					target.inflight[r] += 1
					if target.built and target.type == D.B_SPOUT and r == D.R_WATER:
						target.tokens -= 1.0
				packets.append(p)
				sent += 1
				want -= 1
				if ready_n <= 0:
					break
			if ready_n <= 0:
				break
	# Nothing could go: look again in a tenth of a second rather than every tick.
	if sent == 0:
		dispatch_wait = 5


## What the network is asked for, most urgent first, as [target, resource,
## count, source mode (see _best_source), fix (see Packet.fix)]: the charging
## Crucible, then power for the machines that hold back hazards, then repairs
## (links, then buildings), then blueprints in the order they were placed, then
## power and water for everything else, then Cache top-ups, then generators'
## surplus back to the Hub.
func _requests(avail: PackedByteArray) -> Array:
	var out: Array = []
	if cstate == 1 and crucible.connected and c_tokens >= 1.0:
		var best := -1
		var best_frac := 99.0
		for r in [D.R_GLIMMER, D.R_OBSIDIAN, D.R_WATER]:
			var need: float = D.RECIPE[r] - c_delivered[r] - c_inflight[r]
			if need <= 0.0 or avail[r] == 0:
				continue
			var frac: float = (c_delivered[r] + c_inflight[r]) / float(D.RECIPE[r])
			if frac < best_frac:
				best_frac = frac
				best = r
		if best >= 0:
			out.append([crucible, best, 1, 0, -1])
	# Power goes one packet at a time to whichever machine is emptiest, so a
	# working machine isn't kept waiting while idle ones top up their reserves.
	var urgent: Array = []
	var later: Array = []
	for b: Building in buildings:
		if avail[D.R_POWER] == 0:
			break
		if not b.connected or not b.built or not D.uses_power(b.type):
			continue
		var have := b.power + b.inflight[D.R_POWER]
		if have > reserve_cap(b) - 1.0:
			continue
		# Hoppers and Floodgates hold back hazards: when they're under half,
		# they go ahead of blueprints.
		if (b.type == D.B_HOPPER or b.type == D.B_FLOODGATE) and have < D.POWER_RESERVE * 0.5:
			urgent.append([b, D.R_POWER, 1, 0, -1])
		else:
			later.append([b, D.R_POWER, 1, 0, -1])
	var emptiest := func(a: Array, c: Array) -> bool:
		var ba: Building = a[0]
		var bc: Building = c[0]
		return ba.power + ba.inflight[D.R_POWER] < bc.power + bc.inflight[D.R_POWER]
	urgent.sort_custom(emptiest)
	later.sort_custom(emptiest)
	out.append_array(urgent)
	# Repairs, a Stone each: broken links, worn ones, then damaged buildings.
	if avail[D.R_STONE] != 0:
		for key: int in broken_links:
			if not link_fixes.has(key):
				var t := _fix_target(key)
				if t != null:
					out.append([t, D.R_STONE, 1, 0, key])
		for key: int in link_hp:
			if link_fixes.has(key) or link_hp[key] > D.LINK_HP * D.LINK_REPAIR_BELOW:
				continue
			var t := _fix_target(key)
			if t != null:
				out.append([t, D.R_STONE, 1, 0, key])
		# Only buildings that have been hurt, in the order they were first hurt.
		for b: Building in damaged.keys():
			if b.dead or b.hp >= b.max_hp * D.REPAIR_BELOW:
				if not b.repairing:
					damaged.erase(b)
				continue
			if b.built and b.connected and not b.repairing \
					and b.type != D.B_HUB and b.type != D.B_CRUCIBLE:
				out.append([b, D.R_STONE, 1, 0, FIX_BUILDING])
	for b: Building in buildings:
		if b.built or not b.connected:
			continue
		for r in D.NRES:
			if avail[r] == 0:
				continue
			var need := b.still_needed(r)
			if need > 0:
				out.append([b, r, need, 0, -1])
	# The current tech's materials go to a Lab, like construction.
	if current_tech != "":
		var lab := _research_lab()
		if lab != null:
			var want := tech_mats_needed(tech_step(current_tech))
			var got := tech_mats_got(current_tech)
			for r in D.NRES:
				if want[r] <= 0 or avail[r] == 0:
					continue
				var flying := 0
				for lb: Building in buildings:
					if lb.type == D.B_LAB:
						flying += lb.inflight[r]
				var need := int(want[r] - got[r]) - flying
				if need > 0:
					out.append([lab, r, need, 0, -1])
	out.append_array(later)
	var n := buildings.size() if avail[D.R_WATER] != 0 else 0
	for k in n:
		var b: Building = buildings[(spout_rr + k) % n]
		if b.type != D.B_SPOUT or not b.built or not b.connected or not b.enabled:
			continue
		if b.tokens >= 1.0 and spout_can_pay(b):
			spout_rr = (spout_rr + k + 1) % n
			out.append([b, D.R_WATER, 1, 0, -1])
			break
	for b: Building in buildings:
		if b.type != D.B_CACHE or not b.built or not b.connected:
			continue
		for r in D.NRES:
			if avail[r] == 0:
				continue
			var need := int(D.CACHE_TOPUP[r] - b.store[r]) - b.inflight[r]
			if need > 0:
				out.append([b, r, need, 1, -1])
	var surplus := 0
	for s: Building in src_list:
		if avail[D.R_POWER] == 0:
			break
		if s.type == D.B_WATERWHEEL:
			surplus += maxi(int(s.store[D.R_POWER] - D.GEN_BUFFER * 0.5), 0)
	surplus = mini(surplus, int(D.HUB_POWER_CAP - stock[D.R_POWER]) - hub.inflight[D.R_POWER])
	if surplus > 0:
		out.append([hub, D.R_POWER, surplus, 2, -1])
	return out


func _move_packets() -> void:
	var step := D.PACKET_SPEED * D.DT
	for k in range(packets.size() - 1, -1, -1):
		var p: Packet = packets[k]
		var left := step
		while left > 0.0 and p.seg < p.pts.size() - 1:
			var to: Vector2 = p.pts[p.seg + 1]
			var dv := to - p.pos
			var dl := dv.length()
			if dl <= left:
				p.pos = to
				p.seg += 1
				left -= dl
			else:
				p.pos += dv / dl * left
				left = 0.0
		if p.seg >= p.pts.size() - 1:
			packets.remove_at(k)
			_deliver(p)


func _deliver(p: Packet) -> void:
	var b: Building = p.target
	if b == crucible:
		c_inflight[p.res] -= 1
		if cstate == 1:
			c_delivered[p.res] += 1.0
			c_last_packet = game_time
		else:
			stock[p.res] += 1.0
		return
	if b.dead:
		_fix_done(p)
		stock[p.res] += 1.0
		return
	b.inflight[p.res] -= 1
	if p.fix == FIX_BUILDING:
		b.repairing = false
		b.hp = minf(b.max_hp, b.hp + b.max_hp * D.REPAIR_HP)
		b.flash = 0.4
		return
	if p.fix >= 0:
		_mend_link(p.fix)
		return
	if not b.built:
		b.delivered[p.res] += 1.0
		if b.fully_delivered():
			_complete(b)
	elif p.res == D.R_POWER and D.uses_power(b.type):
		b.power += 1.0
	elif b.type == D.B_SPOUT and p.res == D.R_WATER:
		b.queue += int(D.CELLS_PER_UNIT)
		var pay := minf(b.power, D.SPOUT_POWER_PER_PACKET)
		b.power -= pay
		used_acc += pay
	elif b.type == D.B_CACHE:
		b.store[p.res] += 1.0
	elif b.type == D.B_LAB:
		_research_delivery(p.res)
	else:
		stock[p.res] += 1.0


## A repair packet that won't arrive: let its building or link ask again.
func _fix_done(p: Packet) -> void:
	if p.fix == FIX_BUILDING:
		if p.target != null:
			p.target.repairing = false
	elif p.fix >= 0:
		link_fixes.erase(p.fix)


func warren_colony() -> int:
	return WR.colony_size(self)


## How far a Warren's marker can sit from it.
func warren_marker_range() -> float:
	return WR.marker_range(WR.scale(self))


func set_warren_marker(b: Building, at: Vector2i) -> void:
	WR.set_marker(b, at)


func clear_warren_marker(b: Building) -> void:
	WR.set_marker(b, Vector2i(-1, -1))


## What sensor mode is placing for the selected building: a sensor, or a Warren's marker.
func pick_range() -> float:
	if selected != null and selected.type == D.B_WARREN:
		return warren_marker_range()
	return D.SENSOR_RANGE


## A building has just dug `c` out: the ground round it settles for a while
## before weathering, erosion or loose fill can take it.
func excavated(c: Vector2i) -> void:
	sim.settle_around(c.x, c.y, D.SETTLE_RADIUS, int(D.SETTLE_S * D.TICKS_PER_S))


## Where something dug or swallowed at `at` goes: the nearest Cache in reach
## with room, else the Hub.
func _bank(at: Vector2, r: int, amount: float) -> void:
	if r == D.R_GLIMMER and not tiers_open[2]:
		discover(2, at)
	var best: Building = null
	var best_d := D.CACHE_BANK_RANGE
	for c: Building in caches:
		if c.dead or c.store[r] >= D.CACHE_CAP:
			continue
		var d := at.distance_to(c.center())
		if d <= best_d:
			best_d = d
			best = c
	if best != null:
		best.store[r] += amount
	else:
		stock[r] += amount


## Packets per second the Hub sent over the last second.
func hub_output() -> int:
	return send_log.size()


# ================================================================================
# Research
# ================================================================================

func tech(id: String) -> Dictionary:
	if _tech_by_id.is_empty():
		for t: Dictionary in D.TECHS:
			_tech_by_id[t["id"]] = t
	return _tech_by_id[id]


## What researching a tech next costs: the tech itself, or for an upgrade the
## level after the ones done ({} once every level is done). Has "tier", "power"
## and maybe "mats".
func tech_step(id: String) -> Dictionary:
	var t := tech(id)
	if not t.has("levels"):
		return t
	var lv: Array = t["levels"]
	var n := level(id)
	return lv[n] if n < lv.size() else {}


## Materials a tech wants delivered to the Labs, [stone, glimmer, obsidian, water, power].
## `t` is a tech, or a step from tech_step.
static func tech_mats_needed(t: Dictionary) -> Array:
	return t.get("mats", [0, 0, 0, 0, 0])


## Levels an upgrade has (1 for a plain tech).
func tech_levels(id: String) -> int:
	var t := tech(id)
	return (t["levels"] as Array).size() if t.has("levels") else 1


func tech_done(id: String) -> bool:
	return level(id) >= tech_levels(id)


func tech_mats_got(id: String) -> PackedFloat64Array:
	if not tech_mats.has(id):
		var a := PackedFloat64Array()
		a.resize(D.NRES)
		tech_mats[id] = a
	return tech_mats[id]


## What a tech is waiting on: "done", a reason it can't be picked, or "" when it can.
func tech_block(id: String) -> String:
	var t := tech(id)
	if tech_done(id):
		return "done"
	if t.has("phase"):
		return "Arrives in a later build (phase %d)" % t["phase"]
	var tier: int = tech_step(id)["tier"]
	if not tiers_open[tier]:
		if level(id) > 0:
			return "Level %d opens with %s" % [level(id) + 1, D.TIER_DISCOVERY[tier]]
		return "Opens with %s" % D.TIER_DISCOVERY[tier]
	var needs: Array = t["needs"]
	if needs.is_empty():
		return ""
	var missing: Array = []
	for n: String in needs:
		if not researched.has(n):
			missing.append(tech(n)["name"])
	if t.get("any", false):
		if missing.size() == needs.size():
			return "Needs %s" % " or ".join(missing)
	elif missing.size() > 0:
		return "Needs %s" % ", ".join(missing)
	return ""


## Share of a tech's power already put in, 0..1.
func tech_power_frac(id: String) -> float:
	var st := tech_step(id)
	if st.is_empty():
		return 1.0
	return clampf(tech_power.get(id, 0.0) / float(st["power"]), 0.0, 1.0)


func tech_mats_done(id: String) -> bool:
	var need := tech_mats_needed(tech_step(id))
	var got := tech_mats_got(id)
	for r in D.NRES:
		if got[r] < need[r]:
			return false
	return true


func pick_research(id: String) -> void:
	if tech_block(id) != "":
		return
	current_tech = id


func is_unlocked(type: int) -> bool:
	return unlocked.has(type)


func _refresh_unlocks() -> void:
	unlocked.clear()
	for t: int in D.STARTING_KIT:
		unlocked[t] = true
	for t: Dictionary in D.TECHS:
		if t.has("building") and researched.has(t["id"]):
			unlocked[t["building"]] = true


## Levels of an upgrade done (0 for none; a plain tech counts 1 once researched).
func level(id: String) -> int:
	if levels.has(id):
		return levels[id]
	return 1 if researched.has(id) else 0


func drill_speed() -> float:
	return D.DRILL_SPEED * pow(D.DRILL_BIT_SPEED, level("drill_bit"))


## Power a Drill spends on one cell of `m` at channel row `row`: dearer with
## every Drill Bit level, and further down the shaft.
func drill_power(m: int, row: int) -> float:
	return D.power_per_cell(m) * pow(D.DRILL_BIT_POWER, level("drill_bit")) * (1.0 + row / D.DRILL_DEEP_ROWS)


## How deep the fixed Drill reaches, in rows below it.
func max_reach() -> int:
	return D.DRILL_REACHES[mini(level("drill_shaft"), D.DRILL_REACHES.size() - 1)]


func thump_power() -> int:
	return D.THUMP_POWERS[level("thump_charge")]


func thump_radius() -> float:
	return D.THUMP_RADII[level("thump_radius")]


func thump_cost() -> float:
	return D.THUMP_COSTS[level("thump_efficiency")]


func thump_interval() -> float:
	return D.THUMP_INTERVALS[level("thump_rhythm")]


## The most power a building holds in reserve.
func reserve_cap(b: Building) -> float:
	if b.type == D.B_BORER:
		return D.BORER_RESERVES[level("borer_cells")]
	return D.POWER_RESERVE


## A Lab turns power from its reserve into progress on the current tech, up to
## LAB_POWER_PER_S; it stops drawing once the tech has all the power it needs.
func _lab(b: Building) -> void:
	b.starved = false
	if current_tech == "" or not b.enabled:
		return
	var st := tech_step(current_tech)
	if st.is_empty():
		return
	var need: float = float(st["power"]) - tech_power.get(current_tech, 0.0)
	if need <= 0.0:
		return
	var burn := minf(D.LAB_POWER_PER_S * D.DT, need)
	if b.power < burn:
		b.starved = true
		burn = b.power
	if burn <= 0.0:
		return
	b.power -= burn
	used_acc += burn
	research_acc += burn
	tech_power[current_tech] = tech_power.get(current_tech, 0.0) + burn


func _research_check() -> void:
	if current_tech == "":
		return
	if tech_power_frac(current_tech) >= 1.0 and tech_mats_done(current_tech):
		_finish_research(current_tech)


## Materials arriving at a Lab go into the current tech, or back to the Hub if
## it no longer needs them (the pick changed while they were on their way).
func _research_delivery(r: int) -> void:
	if current_tech != "":
		var got := tech_mats_got(current_tech)
		if got[r] < tech_mats_needed(tech_step(current_tech))[r]:
			got[r] += 1.0
			tech_mats[current_tech] = got
			return
	stock[r] += 1.0


## The Lab that receives research materials: the first built, linked one.
func _research_lab() -> Building:
	for b: Building in buildings:
		if b.type == D.B_LAB and b.built and b.connected:
			return b
	return null


func _finish_research(id: String) -> void:
	var t := tech(id)
	var old_reach := max_reach()
	researched[id] = true
	var tname: String = t["name"]
	if t.has("levels"):
		levels[id] = level(id) + 1 if levels.has(id) else 1
		tname = "%s %d" % [t["name"], levels[id]]
		tech_power.erase(id)
		tech_mats.erase(id)
	if current_tech == id:
		current_tech = ""
	_refresh_unlocks()
	scan_dirty = true
	var at := hub.center()
	var lab := _research_lab()
	if lab != null:
		at = lab.center()
	alert("research", "Research done: %s" % tname, at)
	show_banner("Research done: %s. %s" % [tname, t["text"]], 4.0)
	if id == "drill_shaft" and drill != null and drill.reach_limit >= old_reach:
		# The Drill carries on down to its new reach unless it was held short.
		drill.reach_limit = max_reach()
		drill.scan_from = 0


func discover(tier: int, at: Vector2) -> void:
	if tiers_open[tier]:
		return
	tiers_open[tier] = true
	alert("research", "Discovery: %s. Tier %d research is open." % [D.TIER_FOUND[tier], tier], at)
	show_banner("Discovery: %s. Tier %d research is open (T)." % [D.TIER_FOUND[tier], tier], 5.0)


# ================================================================================
# The Crucible
# ================================================================================

func activate_crucible() -> void:
	if cstate != 0 or not crucible.connected:
		return
	cstate = 1
	c_delivered = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	c_tokens = 1.0
	c_last_packet = -1.0
	tremor_timer = D.TREMOR_EVERY_S
	alert("crucible", "The Crucible is charging. Keep it fed.", crucible.center())


func crucible_charge() -> float:
	var got := 0.0
	var need := 0.0
	for r in D.NRES:
		need += D.RECIPE[r]
		got += minf(c_delivered[r], D.RECIPE[r])
	return got / need


func _update_crucible() -> void:
	c_draining = c_last_packet >= 0.0 and game_time - c_last_packet > D.CRUCIBLE_STALL_S
	if c_draining:
		for r in D.NRES:
			c_delivered[r] = maxf(0.0, c_delivered[r] - D.RECIPE[r] * D.CRUCIBLE_DRAIN_PER_S * D.DT)
	tremor_timer -= D.DT
	if tremor_timer <= 0.0:
		tremor_timer += D.TREMOR_EVERY_S
		tremor_left = D.TREMOR_CELLS
		shake = 0.8
		alert("tremor", "Tremor: loose stone is coming down", crucible.center())
	# A tremor crumbles its stone over a quarter of a second, not all in one tick.
	if tremor_left > 0:
		sim.tremor(mini(tremor_left, 14), D.GROUND_Y + 4, D.H - 4)
		tremor_left -= 14
	for r in D.NRES:
		if c_delivered[r] < D.RECIPE[r]:
			return
	cstate = 2
	won = true
	alert("crucible", "The Crucible is lit.", crucible.center())
	if hud:
		hud.show_win()


# ================================================================================
# Knowledge maps
# ================================================================================

func is_known(x: int, y: int) -> bool:
	if reveal_all:
		return true
	if x < 0 or y < 0 or x >= D.W or y >= D.H:
		return false
	return known[(y >> 2) * KW + (x >> 2)] != 0


func reveal(p: Vector2, r: float) -> void:
	var kx0 := maxi(int((p.x - r) / 4.0), 0)
	var kx1 := mini(int((p.x + r) / 4.0), KW - 1)
	var ky0 := maxi(int((p.y - r) / 4.0), 0)
	var ky1 := mini(int((p.y + r) / 4.0), KH - 1)
	var r2 := (r + 2.0) * (r + 2.0)
	for ky in range(ky0, ky1 + 1):
		for kx in range(kx0, kx1 + 1):
			var dx := kx * 4 + 2.0 - p.x
			var dy := ky * 4 + 2.0 - p.y
			if dx * dx + dy * dy <= r2 and known[ky * KW + kx] == 0:
				known[ky * KW + kx] = 255
				known_changed = true


## Light and fog. The sim spreads light from the Hub, Lamps, pilot lights,
## glowing materials and the sky; a block is explored once it's lit within sight
## of one of your buildings, and shows live whenever it's lit after that.
## Unlit, it shows as you last saw it.
func _refresh_vision() -> void:
	if scan_dirty:
		_rebuild_scan()
	var lights := still_lights.duplicate()
	var sights := still_sights.duplicate()
	for b: Building in lit_list:
		if b.dead or b.falling:
			continue
		if b.type == D.B_LAMP:
			if b.enabled and b.power > 0.0:
				_circle(lights, b.center(), D.LIGHT_LAMP)
				_circle(sights, b.center(), D.LIGHT_LAMP)
		elif D.is_mover(b.type):
			_circle(lights, b.center(), D.LIGHT_PILOT)
			_circle(sights, b.center(), D.SIGHT_MACHINE)
		else:
			_circle(lights, b.drill_head(), D.LIGHT_PILOT)
			_circle(sights, b.drill_head(), D.LIGHT_PILOT + 2.0)
	var maps: PackedByteArray = sim.light_update(lights, sights, D.SUN_LIGHT, known)
	var n := KW * KH
	var fresh := maps.slice(0, n)
	var expl := maps.slice(n, 2 * n)
	seen = maps.slice(2 * n, 3 * n)
	if fresh != vis:
		vis = fresh
		vis_changed = true
	if expl != known:
		known = expl
		known_changed = true
	light_due = true
	mem_due = true
	var found: PackedInt32Array = sim.materials_in(seen)
	_sightings(found)
	if not tiers_open[3] and found[D.LAVA] >= 0:
		var at := found[D.LAVA]
		discover(3, Vector2(at % D.W, floori(at / float(D.W))))
	if not tiers_open[4]:
		var cr := crucible.rect()
		for yy in range(cr.position.y, cr.end.y, 4):
			for xx in range(cr.position.x, cr.end.x, 4):
				if seen[(yy >> 2) * KW + (xx >> 2)] != 0:
					discover(4, crucible.center())
					return


static func _circle(into: PackedInt32Array, p: Vector2, r: float) -> void:
	into.append(int(p.x))
	into.append(int(p.y))
	into.append(int(r))


## The first time something with a note in the data file (Coal, Sulfur, fire,
## fumes) comes into view, say what it is.
func _sightings(found: PackedInt32Array) -> void:
	for m in found.size():
		var at := found[m]
		if at < 0 or seen_mats.has(m):
			continue
		var note := Mats.sighted_text(m)
		if note == "":
			continue
		seen_mats[m] = true
		var pos := Vector2(at % D.W, floori(at / float(D.W)))
		alert("discovery", note, pos)
		show_banner(note, 6.0)


func is_seen(x: int, y: int) -> bool:
	if reveal_all:
		return true
	if x < 0 or y < 0 or x >= D.W or y >= D.H:
		return false
	return vis[(y >> 2) * KW + (x >> 2)] != 0


## Copy what is visible now into the remembered picture, a run of blocks at a time.
func _refresh_memory() -> void:
	if grid_img == null:
		return
	for ky in KH:
		var row := ky * KW
		var kx := 0
		while kx < KW:
			if vis[row + kx] == 0:
				kx += 1
				continue
			var start := kx
			while kx < KW and vis[row + kx] != 0:
				kx += 1
			mem_img.blit_rect(grid_img, Rect2i(start * 4, ky * 4, (kx - start) * 4, 4), Vector2i(start * 4, ky * 4))
	mem_tex.update(mem_img)


func _refresh_sense() -> void:
	var fresh := PackedByteArray()
	fresh.resize(KW * KH)
	for b: Building in buildings:
		if (b.type != D.B_DRILL and b.type != D.B_BORER) or not b.built:
			continue
		for p: Vector2 in [b.center(), b.drill_head()]:
			var sr := D.SENSE_RADIUS
			var kx0 := maxi(int((p.x - sr) / 4.0), 0)
			var kx1 := mini(int((p.x + sr) / 4.0), KW - 1)
			var ky0 := maxi(int((p.y - sr) / 4.0), 0)
			var ky1 := mini(int((p.y + sr) / 4.0), KH - 1)
			for ky in range(ky0, ky1 + 1):
				for kx in range(kx0, kx1 + 1):
					var dx := kx * 4 + 2.0 - p.x
					var dy := ky * 4 + 2.0 - p.y
					if dx * dx + dy * dy <= (sr + 2.0) * (sr + 2.0):
						fresh[ky * KW + kx] = 255
	if fresh != sense:
		sense = fresh
		sense_changed = true


# ================================================================================
# Alerts
# ================================================================================

func alert(kind: String, text: String, at: Vector2) -> void:
	for a: Dictionary in alerts:
		# Same message lately, or the same kind of trouble close by (five farm
		# drills breaching one lake read as one event).
		var same: bool = a["text"] == text and game_time - a["t"] < 6.0
		var near: bool = a["kind"] == kind and kind != "crucible" and kind != "info" \
				and absf(a["y"] - at.y) <= 12.0 and game_time - a["t"] < 20.0
		if same or near:
			a["n"] += 1
			a["t"] = game_time
			if hud:
				hud.alerts_dirty = true
			return
	alerts.append({"kind": kind, "text": text, "x": at.x, "y": at.y, "t": game_time, "n": 1})
	if alerts.size() > 60:
		alerts.pop_front()
	if pause_on_breach and (kind == "water_breach" or kind == "lava_breach") and not seen_kinds.has(kind):
		paused = true
		show_banner("First %s. Paused: press Space to carry on." % ("water breach" if kind == "water_breach" else "lava breach"), 6.0)
		_center_on(at.y, false, at.x)
	seen_kinds[kind] = true
	if hud:
		hud.alerts_dirty = true


func show_banner(text: String, secs := 3.0) -> void:
	banner_text = text
	banner_time = secs


# ================================================================================
# Camera
# ================================================================================

func _layout() -> void:
	var vs := get_viewport_rect().size
	ui_scale = clampf(round(vs.y / 800.0 * 4.0) / 4.0, 1.0, 2.5)
	# The closest zoom that still fits the whole width is the far limit; the
	# camera normally sits about 1.5x closer and pans sideways.
	zoom_min = clampi(int((vs.x - 2.0 * SIDE_UI * ui_scale) / D.W), 2, 4)
	zoom_max = zoom_min * 2 + 2
	zoom = clampi(zoom, zoom_min, zoom_max)
	_clamp_cam_x()
	cam_x = cam_x_target
	_apply_cam_x()
	if hud:
		hud.apply_layout(vs, ui_scale)
	_clamp_cam()


func default_zoom() -> int:
	return clampi(int(round(zoom_min * D.CAMERA_CLOSER)), zoom_min, zoom_max)


## Half the unobstructed view width, in cells.
func _half_view_cols() -> float:
	var vs := get_viewport_rect().size
	return maxf(vs.x * 0.5 - SIDE_UI * ui_scale, 40.0) / zoom


func _clamp_cam_x() -> void:
	var half := _half_view_cols()
	if D.W <= 2.0 * half:
		cam_x_target = D.W * 0.5
	else:
		cam_x_target = clampf(cam_x_target, half - 2.0, D.W - half + 2.0)


func _apply_cam_x() -> void:
	map_x = floor(get_viewport_rect().size.x * 0.5 - cam_x * zoom)


func view_rows() -> float:
	return get_viewport_rect().size.y / zoom


func _clamp_cam() -> void:
	var top := -40.0 * ui_scale / zoom
	cam_target = clampf(cam_target, top, D.H - view_rows() + 4.0)


func _center_on(y: float, snap: bool, x := -1.0) -> void:
	cam_target = y - view_rows() * 0.5
	_clamp_cam()
	if x >= 0.0:
		cam_x_target = x
		_clamp_cam_x()
	if snap:
		cam_y = cam_target
		cam_x = cam_x_target


func set_zoom(z: int, anchor_screen_y := -1.0) -> void:
	z = clampi(z, zoom_min, zoom_max)
	if z == zoom:
		return
	var ay := anchor_screen_y if anchor_screen_y >= 0.0 else get_viewport_rect().size.y * 0.5
	var world_y := cam_y + ay / zoom
	zoom = z
	_clamp_cam_x()
	cam_x = cam_x_target
	_apply_cam_x()
	cam_y = world_y - ay / zoom
	cam_target = cam_y
	_clamp_cam()
	cam_y = cam_target


func _update_camera(delta: float) -> void:
	cam_y = lerpf(cam_y, cam_target, 1.0 - exp(-delta * 14.0))
	if absf(cam_y - cam_target) < 0.02:
		cam_y = cam_target
	cam_x = lerpf(cam_x, cam_x_target, 1.0 - exp(-delta * 14.0))
	if absf(cam_x - cam_x_target) < 0.02:
		cam_x = cam_x_target
	_apply_cam_x()
	var off := Vector2.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 5.0
	view_offset = Vector2(map_x, round(-cam_y * zoom)) + off.round()
	terrain.position = view_offset
	terrain.scale = Vector2(zoom, zoom)
	hover = screen_to_cell(mouse_screen)


func screen_to_cell(s: Vector2) -> Vector2i:
	var p := (s - view_offset) / float(zoom)
	return Vector2i(floori(p.x), floori(p.y))


func to_screen(p: Vector2) -> Vector2:
	return view_offset + p * zoom


func deepest_building() -> Building:
	var best: Building = hub
	for b: Building in buildings:
		if b.type != D.B_CRUCIBLE and b.y + b.h > best.y + best.h:
			best = b
	return best


func jump_to(y: float, x := -1.0) -> void:
	_center_on(y, false, x)


# ================================================================================
# Input
# ================================================================================

func select_tool(type: int) -> void:
	if not is_unlocked(type):
		show_banner("%s isn't researched yet (T opens Research)." % D.B_NAMES[type], 2.5)
		return
	tool_type = type
	sensor_mode = false
	brush_mode = false
	selected = null
	if type == D.B_DRILL:
		show_banner("Drill: R turns it (down, left, right). Esc cancels.", 3.0)
	elif type == D.B_BORER:
		tool_dir = mini(tool_dir, 3)
		show_banner("Borer: R turns it (down, left, right, up) before placing; turn it any time after. Esc cancels.", 3.5)
	elif type == D.B_THUMPER:
		show_banner("Thumper: once it's built, drag it to move it; let go mid-swing to throw it. Esc cancels.", 3.5)
	elif type == D.B_FLOODGATE:
		show_banner("Floodgate: R turns it on its side. Esc cancels.", 3.0)
	elif type == D.B_BULKHEAD:
		show_banner("Bulkhead: drag to lay a wall. Esc cancels.", 3.0)
	elif type == D.B_STRUT:
		show_banner("Strut: click in a gap to span it rock to rock; R turns it upright or flat. Esc cancels.", 3.5)


func cancel_tool() -> void:
	tool_type = -1
	drag_from = Vector2i(-1, -1)
	sensor_mode = false


func begin_sensor_move() -> void:
	if selected != null and (selected.type == D.B_SPOUT or selected.type == D.B_FLOODGATE):
		sensor_mode = true
		tool_type = -1
		show_banner("Click a cell within %d of the building to move its sensor. Esc cancels." % int(D.SENSOR_RANGE), 4.0)
	elif selected != null and selected.type == D.B_WARREN:
		sensor_mode = true
		tool_type = -1
		show_banner("Click where the mites should tunnel to, within %d cells. Esc cancels." % int(warren_marker_range()), 4.0)


func toggle_pause() -> void:
	paused = not paused


func cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()


func speed() -> int:
	return SPEEDS[speed_idx]


func brush_material() -> int:
	return BRUSH_MATS[brush_idx]


func brush_name() -> String:
	var m := brush_material()
	return "Blast (click)" if m == BRUSH_BLAST else D.mat_name(m)


func restart(same_seed: bool) -> void:
	new_game(seed_value if same_seed else randi() % 100000)
	_center_on(hub.center().y + 30.0, true, hub.center().x)


## Blocks of a Bulkhead line dragged from `a` to `b`: straight along the longer axis.
func bulkhead_line(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var d := b - a
	var horizontal := absi(d.x) >= absi(d.y)
	var n := ((absi(d.x) if horizontal else absi(d.y)) >> 2) + 1
	var s := signi(d.x) if horizontal else signi(d.y)
	if s == 0:
		s = 1
	for k in mini(n, 40):
		var c := a + (Vector2i(4 * k * s, 0) if horizontal else Vector2i(0, 4 * k * s))
		out.append(footprint(D.B_BULKHEAD, c, false))
	return out


## Which blocks of a line can be placed, and whether the line as a whole touches rock.
func bulkhead_valid(rects: Array) -> Array:
	var ok: Array = []
	var any_touch := false
	for r: Rect2i in rects:
		var why := check_place(D.B_BULKHEAD, r, false)
		ok.append(why == "")
		if why == "" and touches_solid(r):
			any_touch = true
	if not any_touch:
		for k in ok.size():
			ok[k] = false
	return ok


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_screen = event.position
		hover = screen_to_cell(mouse_screen)
		if grab != null and not grab.held and not grab.dead and (hover - grab_from).length_squared() >= 4:
			grab_thumper(grab, Vector2(hover) + Vector2(0.5, 0.5))
		if panning:
			cam_target -= (event.position.y - pan_last.y) / zoom
			cam_y = cam_target
			cam_x_target -= (event.position.x - pan_last.x) / zoom
			_clamp_cam_x()
			cam_x = cam_x_target
			pan_last = event.position
			_clamp_cam()
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _mouse_button(e: InputEventMouseButton) -> void:
	mouse_screen = e.position
	hover = screen_to_cell(mouse_screen)
	if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not e.pressed:
			return
		var up := e.button_index == MOUSE_BUTTON_WHEEL_UP
		if e.ctrl_pressed:
			set_zoom(zoom + (1 if up else -1), e.position.y)
		elif e.shift_pressed:
			cam_x_target += (-1.0 if up else 1.0) * 90.0 / zoom
			_clamp_cam_x()
		else:
			cam_target += (-1.0 if up else 1.0) * 90.0 / zoom
			_clamp_cam()
		get_viewport().set_input_as_handled()
		return
	if e.button_index == MOUSE_BUTTON_MIDDLE:
		panning = e.pressed
		pan_last = e.position
		return
	if e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_left_press()
		else:
			_left_release()
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		if e.pressed:
			if brush_mode:
				painting = 2
			elif tool_type >= 0 or sensor_mode:
				cancel_tool()
			else:
				demolish_target = building_at(hover)
				demolish_hold = 0.0
				if demolish_target != null and (demolish_target.type == D.B_HUB or demolish_target.type == D.B_CRUCIBLE or demolish_target.fixed):
					demolish_target = null
		else:
			painting = 0
			demolish_target = null
			demolish_hold = 0.0


func _left_press() -> void:
	if brush_mode:
		if brush_material() == BRUSH_BLAST:
			if hover.x >= 2 and hover.x < D.W - 2 and hover.y >= 2 and hover.y < D.H - 2:
				blast(hover, D.BLAST_RADIUS, D.BLAST_POWER)
			return
		painting = 1
		return
	if sensor_mode and selected != null:
		var pr := pick_range()
		if selected.center().distance_to(Vector2(hover) + Vector2(0.5, 0.5)) <= pr \
				and hover.x >= 2 and hover.x < D.W - 2 and hover.y >= 2 and hover.y < D.H - 2:
			if selected.type == D.B_WARREN:
				set_warren_marker(selected, hover)
			else:
				selected.sx = hover.x
				selected.sy = hover.y
			sensor_mode = false
		else:
			show_banner("Too far: it must be within %d cells." % int(pr), 2.0)
		return
	if tool_type == D.B_BULKHEAD:
		drag_from = hover
		return
	if tool_type == D.B_STRUT:
		var sr := strut_rect(hover, tool_horizontal)
		var swhy := check_strut(sr)
		if swhy == "":
			place_strut(sr)
		else:
			show_banner(swhy, 1.5)
		return
	if tool_type >= 0:
		var r := snap_place(tool_type, hover, tool_horizontal)
		var why := check_place(tool_type, r)
		if why == "":
			place(tool_type, r, tool_dir, tool_horizontal)
		else:
			show_banner(why, 1.5)
		return
	selected = building_at(hover)
	# A built Thumper under the press gets dragged once the mouse moves off it a little.
	if selected != null and selected.type == D.B_THUMPER and selected.built:
		grab = selected
		grab_from = hover


func _left_release() -> void:
	painting = 0 if painting == 1 else painting
	if grab != null:
		release_thumper(grab)
		grab = null
	if tool_type == D.B_BULKHEAD and drag_from.x >= 0:
		var rects := bulkhead_line(drag_from, hover)
		var ok := bulkhead_valid(rects)
		var placed := 0
		for k in rects.size():
			if ok[k]:
				place(D.B_BULKHEAD, rects[k])
				placed += 1
		if placed == 0:
			show_banner("No wall here: blocks need open air, rock contact and network range.", 2.0)
		drag_from = Vector2i(-1, -1)


func _key(e: InputEventKey) -> void:
	var k := e.keycode
	var idx := D.PALETTE_KEYS.find(OS.get_keycode_string(k))
	if idx >= 0:
		if is_unlocked(D.PALETTE[idx]):
			select_tool(D.PALETTE[idx])
	elif k == KEY_T:
		hud.toggle_research()
	elif k == KEY_ESCAPE:
		if hud.help_visible():
			hud.toggle_help()
		elif hud.research_visible():
			hud.toggle_research()
		elif tool_type >= 0 or sensor_mode:
			cancel_tool()
		elif brush_mode:
			brush_mode = false
		else:
			selected = null
	elif k == KEY_R:
		if tool_type == D.B_DRILL:
			tool_dir = (tool_dir + 1) % 3
		elif tool_type == D.B_BORER:
			tool_dir = (tool_dir + 1) % 4
		elif tool_type == D.B_FLOODGATE or tool_type == D.B_STRUT:
			tool_horizontal = not tool_horizontal
	elif k == KEY_SPACE:
		toggle_pause()
	elif k == KEY_TAB:
		cycle_speed()
	elif k == KEY_N:
		show_network = not show_network
	elif k == KEY_HOME:
		_center_on(hub.center().y, false, hub.center().x)
	elif k == KEY_END:
		_center_on(deepest_building().center().y, false, deepest_building().center().x)
	elif k == KEY_F1 or k == KEY_H:
		hud.toggle_help()
	elif k == KEY_F3:
		show_perf = not show_perf
	elif k == KEY_F5:
		restart(not e.shift_pressed)
	elif k == KEY_F9:
		brush_mode = not brush_mode
		tool_type = -1
		if brush_mode:
			show_banner("Sandbox brush: left paints, right erases, [ ] change material (Blast: click). F9 to exit.", 4.0)
	elif k == KEY_F10:
		reveal_all = not reveal_all
	elif k == KEY_BRACKETLEFT:
		brush_idx = (brush_idx + BRUSH_MATS.size() - 1) % BRUSH_MATS.size()
	elif k == KEY_BRACKETRIGHT:
		brush_idx = (brush_idx + 1) % BRUSH_MATS.size()
	elif k == KEY_EQUAL or k == KEY_KP_ADD:
		set_zoom(zoom + 1)
	elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		set_zoom(zoom - 1)
	elif k == KEY_DELETE and selected != null:
		demolish(selected)
	elif k == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _held_keys(delta: float) -> void:
	if headless:
		return
	var dir := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir += 1.0
	if Input.is_key_pressed(KEY_PAGEUP):
		dir -= 3.0
	if Input.is_key_pressed(KEY_PAGEDOWN):
		dir += 3.0
	if dir != 0.0:
		cam_target += dir * 700.0 * delta / zoom
		_clamp_cam()
	var side := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		side -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		side += 1.0
	if side != 0.0:
		cam_x_target += side * 700.0 * delta / zoom
		_clamp_cam_x()


func _update_demolish(delta: float) -> void:
	if demolish_target == null:
		return
	if demolish_target.dead or not demolish_target.has_cell(hover.x, hover.y):
		demolish_target = null
		demolish_hold = 0.0
		return
	demolish_hold += delta
	if demolish_hold >= 0.6:
		demolish(demolish_target)
		demolish_target = null
		demolish_hold = 0.0


## The sandbox brush. Fire lights what can burn and fills open space with
## flames; everything else replaces what's there (not buildings or bedrock).
func _paint(c: Vector2i, erase: bool) -> void:
	var m: int = D.AIR if erase else BRUSH_MATS[brush_idx]
	if m == BRUSH_BLAST:
		return
	for oy in range(-3, 4):
		for ox in range(-3, 4):
			if ox * ox + oy * oy > 9:
				continue
			var x := c.x + ox
			var y := c.y + oy
			if x < 2 or x > D.W - 3 or y < 4 or y > D.H - 3:
				continue
			var cur: int = sim.get_cell(x, y)
			if cur == D.BUILDING or cur == D.BEDROCK:
				continue
			if m == D.FIRE:
				if Mats.is_burnable(cur):
					sim.ignite(x, y)
				elif D.is_thin(cur):
					sim.set_cell(x, y, D.FIRE)
				continue
			sim.set_cell(x, y, m)
	reveal(Vector2(c), 8.0)
