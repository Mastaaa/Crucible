extends SceneTree
## Dumps the generated map (fog off) to a PNG: one pixel per `step` cells (default
## 4, the whole map), or a crop at a pixel a cell.
## godot --headless --path . --script tests/mapdump.gd -- --seed=123 --out=/path.png [--step=4] [--rect=x,y,w,h]

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

const COLS := {
	0: Color("#101018"), 1: Color("#2e2735"), 2: Color("#77767c"), 3: Color("#3fd0b5"),
	4: Color("#3a2552"), 5: Color("#f2c14e"), 6: Color("#6e4a2e"), 7: Color("#90623e"),
	8: Color("#8a857c"), 9: Color("#2a6fdc"), 10: Color("#ff6a1a"),
}

func _initialize() -> void:
	var seed_value := 123
	var out := "/tmp/map.png"
	var step := 4
	var rect := Rect2i(0, 0, D.W, D.H)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--step="): step = maxi(int(a.substr(7)), 1)
		elif a.begins_with("--rect="):
			var p := a.substr(7).split(",")
			rect = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])).intersection(Rect2i(0, 0, D.W, D.H))
			step = 1
	var sim = SimFactory.create()
	var t0 := Time.get_ticks_msec()
	var info := WorldGen.new().generate(sim, seed_value)
	print("generate ms: ", Time.get_ticks_msec() - t0, " (arched ", info["arched"], ")")
	var counts := {}
	for m in [D.WATER, D.LAVA, D.GLIMMER, D.AIR, D.STONE, D.DIRT, D.PACKED_DIRT, D.GRAVEL, D.SAND, D.CLAY, D.COAL, D.SULFUR]:
		counts[D.mat_name(m)] = sim.count(m)
	print("counts: ", counts)
	print("info: plug_x=", info["plug_x"], " lake=", info["lake"], " crucible=", info["crucible"], " aquifers=", info["aquifers"], " lava_pockets=", info["lava_pockets"], " glimmer=", info["glimmer"], " springs=", info["springs"].size())
	var iw := ceili(rect.size.x / float(step))
	var ih := ceili(rect.size.y / float(step))
	var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	var cells: PackedByteArray = sim.get_cells()
	var pal: Image = D.M.palette_image()   # material colours from the data file
	for py in ih:
		var y := rect.position.y + py * step
		for px in iw:
			var x := rect.position.x + px * step
			var m: int = cells[y * D.W + x]
			var c: Color = COLS.get(m, pal.get_pixel(m, 0)) if m < 11 else pal.get_pixel(m, 0)
			c.a = 1.0
			if m == 0 and y < D.GROUND_Y: c = Color("#2a2f55")
			img.set_pixel(px, py, c)
	img.save_png(out)
	print("saved ", out)
	quit()
