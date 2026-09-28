extends SceneTree
## World-size benchmark for the phase 8b rescale. Worldgen is still 256 x 1024, so
## this generates seed 7 and tiles it up to the size asked for, which keeps caves,
## water and lava at today's density. It times what grows with the map.
##   godot --headless --path . --script tests/bench_size.gd -- --w=768 --h=5120

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

var w := 256
var h := 1024


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--w="):
			w = int(a.substr(4))
		elif a.begins_with("--h="):
			h = int(a.substr(4))
	print("== %d x %d (%.1f M cells, %.1fx today's area)" % [w, h, w * h / 1e6, w * h / float(D.W * D.H)])

	var base_sim = SimFactory.create()
	var t0 := Time.get_ticks_usec()
	var info: Dictionary = WorldGen.new().generate(base_sim, 7)
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var base: PackedByteArray = base_sim.get_cells()
	print("worldgen at 256 x 1024: %.0f ms (x%.1f area: ~%.0f ms if it scales linearly)" % [gen_ms, w * h / float(D.W * D.H), gen_ms * w * h / float(D.W * D.H)])

	var sim = SimFactory.create()
	sim.set_size(w, h)
	t0 = Time.get_ticks_usec()
	var big := PackedByteArray()
	big.resize(w * h)
	for y in h:
		var sy := y % D.H
		var x := 0
		while x < w:
			var n := mini(D.W, w - x)
			for k in n:
				big[y * w + x + k] = base[sy * D.W + k]
			x += n
	sim.set_cells(big)
	print("tiling (GDScript per-cell loop): %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))

	t0 = Time.get_ticks_usec()
	var settled: int = sim.stabilize()
	print("stabilize: %.0f ms (%d cells)" % [(Time.get_ticks_usec() - t0) / 1000.0, settled])

	# Quiet world: the tick plus the game's slow passes.
	_run(sim, 300, "quiet world")

	# One breach near the top: activity that doesn't grow with the map.
	var aq: Rect2i = info["aquifers"][0]
	_shaft(sim, aq.get_center().x, aq.end.y - 2, aq.end.y + 60)
	_run(sim, 600, "one aquifer breached")

	# Every tile's aquifers breached: activity that grows with the map.
	var tiles_x := ceili(w / float(D.W))
	var tiles_y := ceili(h / float(D.H))
	var shafts := 0
	for ty in tiles_y:
		for tx in tiles_x:
			for r: Rect2i in info["aquifers"]:
				var cx := tx * D.W + r.get_center().x
				var y0 := ty * D.H + r.end.y - 2
				if cx < w - 3 and y0 + 60 < h:
					_shaft(sim, cx, y0, y0 + 60)
					shafts += 1
	_run(sim, 600, "%d aquifers breached" % shafts)

	# Collapse sweep: the whole map, COLLAPSE_ROWS a tick.
	var calls := ceili(h / float(D.COLLAPSE_ROWS))
	t0 = Time.get_ticks_usec()
	for i in calls:
		sim.collapse(D.COLLAPSE_ROWS)
	var cms := (Time.get_ticks_usec() - t0) / 1000.0
	print("collapse: %.3f ms a call, a full sweep every %d ticks (%.2f s)" % [cms / calls, calls, calls / 60.0])

	# Light: explored everywhere (worst case) and just the top 1024 rows.
	var kw := w / 4
	var kh := h / 4
	var known := PackedByteArray()
	known.resize(kw * kh)
	known.fill(255)
	var lights := PackedInt32Array([w / 2, 37, 22])
	var sights := PackedInt32Array([w / 2, 37, 24])
	_light(sim, lights, sights, known, "light_update, all explored")
	sim.set_light_view(0, h / 2, w, h / 2 + 400)
	_light(sim, lights, sights, known, "light_update, all explored, 768 x 400 view")
	sim.set_light_view(0, 0, w, h)
	known.fill(0)
	for i in kw * (D.H >> 2):
		known[i] = 255
	_light(sim, lights, sights, known, "light_update, top 1024 rows explored")

	# The per-frame texture upload, CPU side (get_cells/get_aux_bytes + Image.set_data).
	var img := Image.create(w, h, false, Image.FORMAT_R8)
	var img2 := Image.create(w, h, false, Image.FORMAT_R8)
	t0 = Time.get_ticks_usec()
	for i in 20:
		img.set_data(w, h, false, Image.FORMAT_R8, sim.get_cells())
		img2.set_data(w, h, false, Image.FORMAT_R8, sim.get_aux_bytes())
	print("cell + aux upload prep: %.2f ms a frame (%.1f MB a frame to the GPU)" % [(Time.get_ticks_usec() - t0) / 20000.0, 2.0 * w * h / 1e6])

	# _refresh_memory's scan over every 4x4 block (a small patch visible).
	var vis := PackedByteArray()
	vis.resize(kw * kh)
	for ky in range(8, 24):
		for kx in range((kw >> 1) - 8, (kw >> 1) + 8):
			vis[ky * kw + kx] = 1
	t0 = Time.get_ticks_usec()
	for i in 5:
		for ky in kh:
			var row := ky * kw
			var kx := 0
			while kx < kw:
				if vis[row + kx] == 0:
					kx += 1
					continue
				kx += 1
	print("block scan (GDScript, %d blocks): %.2f ms" % [kw * kh, (Time.get_ticks_usec() - t0) / 5000.0])
	print("engine memory: ~%.0f MB (11 bytes a cell)" % (w * h * 11 / 1e6))
	quit()


func _shaft(sim, cx: int, y0: int, y1: int) -> void:
	for y in range(y0, y1):
		for x in range(cx - 2, cx + 3):
			if sim.get_cell(x, y) != D.BEDROCK:
				sim.set_cell(x, y, D.AIR)


func _run(sim, ticks: int, label: String) -> void:
	var step_total := 0
	var worst := 0
	var slow_total := 0
	var chunks := 0
	for t in ticks:
		var t0 := Time.get_ticks_usec()
		sim.step()
		var dt := Time.get_ticks_usec() - t0
		step_total += dt
		worst = maxi(worst, dt)
		chunks += sim.stat_chunks
		t0 = Time.get_ticks_usec()
		if t % 2 == 0:
			sim.erode(D.ERODE_SAMPLES, D.GROUND_Y + 6, 330)
		sim.weather(D.WEATHER_SAMPLES)
		sim.wash(D.WASH_SAMPLES)
		sim.collapse(D.COLLAPSE_ROWS)
		slow_total += Time.get_ticks_usec() - t0
	print("%s: step %.3f ms avg, %.2f worst, %d chunks awake; slow passes %.3f ms" % [label, step_total / 1000.0 / ticks, worst / 1000.0, roundi(chunks / float(ticks)), slow_total / 1000.0 / ticks])


func _light(sim, lights: PackedInt32Array, sights: PackedInt32Array, known: PackedByteArray, label: String) -> void:
	sim.light_update(lights, sights, D.SUN_LIGHT, known)
	var t0 := Time.get_ticks_usec()
	for i in 5:
		sim.light_update(lights, sights, D.SUN_LIGHT, known)
	print("%s: %.2f ms (4 a second)" % [label, (Time.get_ticks_usec() - t0) / 5000.0])
