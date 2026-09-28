extends SceneTree
## Dumps the generated map (all of it, fog off) to a PNG, 2 px per cell.
## godot --headless --path . --script tests/mapdump.gd -- --seed=123 --out=/path.png

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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif a.begins_with("--out="): out = a.substr(6)
	var sim = SimFactory.create()
	var t0 := Time.get_ticks_msec()
	var info := WorldGen.new().generate(sim, seed_value)
	print("generate ms: ", Time.get_ticks_msec() - t0)
	var counts := {}
	for m in [D.WATER, D.LAVA, D.GLIMMER, D.AIR, D.STONE, D.DIRT, D.PACKED_DIRT, D.GRAVEL, D.SAND, D.CLAY]:
		counts[D.mat_name(m)] = sim.count(m)
	print("counts: ", counts)
	print("info: plug_x=", info["plug_x"], " lake=", info["lake"], " aquifers=", info["aquifers"], " lava_pockets=", info["lava_pockets"], " glimmer=", info["glimmer"])
	var img := Image.create(D.W * 2, D.H * 2, false, Image.FORMAT_RGB8)
	var cells: PackedByteArray = sim.get_cells()
	var pal: Image = D.M.palette_image()   # material colours from the data file
	for y in D.H:
		for x in D.W:
			var m: int = cells[y * D.W + x]
			var c: Color = COLS.get(m, pal.get_pixel(m, 0)) if m < 11 else pal.get_pixel(m, 0)
			c.a = 1.0
			if m == 0 and y < D.GROUND_Y: c = Color("#2a2f55")
			img.fill_rect(Rect2i(x * 2, y * 2, 2, 2), c)
	img.save_png(out)
	print("saved ", out)
	quit()
