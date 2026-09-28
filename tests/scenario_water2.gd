extends SceneTree
const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
const COLS := {0: Color("#101018"), 1: Color("#2e2735"), 2: Color("#77767c"), 3: Color("#3fd0b5"),
	4: Color("#5a3585"), 5: Color("#f2c14e"), 6: Color("#6e4a2e"), 7: Color("#b07a4a"),
	8: Color("#a8a397"), 9: Color("#2a6fdc"), 10: Color("#ff6a1a")}

func crop(sim, r: Rect2i, s: int) -> Image:
	var img := Image.create(r.size.x * s, r.size.y * s, false, Image.FORMAT_RGB8)
	for y in r.size.y:
		for x in r.size.x:
			var m: int = sim.get_cell(r.position.x + x, r.position.y + y)
			img.fill_rect(Rect2i(x * s, y * s, s, s), COLS.get(m, Color.WHITE) if m < 11 else Color(0.95, 0.95, 1.0))
	return img

func _initialize() -> void:
	var sim = SimFactory.create()
	var info := WorldGen.new().generate(sim, 123)
	var aq: Rect2i = info["aquifers"][0]
	var sx := aq.position.x - 12
	var hop_y := aq.end.y + 20
	for y in range(D.GROUND_Y, hop_y + 3):
		for x in range(sx, sx + 5):
			sim.set_cell(x, y, D.AIR)
	for y in range(hop_y, hop_y + 3):
		for x in range(sx, sx + 5):
			sim.set_cell(x, y, D.BUILDING)
	var by := aq.end.y - 5
	var x := sx + 5
	while x < aq.position.x + 20:
		for y in range(by, by + 5):
			if sim.get_cell(x, y) != D.WATER:
				sim.set_cell(x, y, D.AIR)
		x += 1
	var region := Rect2i(sx - 4, aq.position.y - 6, 80, 64)
	var sheet := Image.create(region.size.x * 3 * 4 + 30, region.size.y * 3, false, Image.FORMAT_RGB8)
	var k := 0
	var intake := 0.0
	for t in 60 * 20:
		sim.step()
		intake = minf(intake + 0.5, 5.0)
		for j in 5:
			if intake < 1.0: break
			if sim.get_cell(sx + j, hop_y - 1) == D.WATER:
				sim.set_cell(sx + j, hop_y - 1, D.AIR)
				intake -= 1.0
		if t in [30, 180, 420, 1190]:
			var img := crop(sim, region, 3)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(k * (region.size.x * 3 + 10), 0))
			k += 1
	sheet.save_png("/home/claude/shots/breach.png")
	print("water left: ", sim.count(D.WATER))
	quit()
