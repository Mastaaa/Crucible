extends SceneTree
## Snapshot a region of the sim over time (CPU colours), for eyeballing flow.

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
const COLS := {
	0: Color("#101018"), 1: Color("#2e2735"), 2: Color("#77767c"), 3: Color("#3fd0b5"),
	4: Color("#5a3585"), 5: Color("#f2c14e"), 6: Color("#6e4a2e"), 7: Color("#b07a4a"),
	8: Color("#a8a397"), 9: Color("#2a6fdc"), 10: Color("#ff6a1a"),
}

func crop(sim, r: Rect2i, s: int) -> Image:
	var img := Image.create(r.size.x * s, r.size.y * s, false, Image.FORMAT_RGB8)
	for y in r.size.y:
		for x in r.size.x:
			var m: int = sim.get_cell(r.position.x + x, r.position.y + y)
			var c: Color = COLS.get(m, Color.WHITE) if m < 11 else Color(0.95, 0.95, 1.0)
			img.fill_rect(Rect2i(x * s, y * s, s, s), c)
	return img

func _initialize() -> void:
	var sim = SimFactory.create()
	var info := WorldGen.new().generate(sim, 123)
	var aq: Rect2i = info["aquifers"][0]
	var sx := aq.get_center().x - 2
	for y in range(D.GROUND_Y, 290):
		for x in range(sx, sx + 5):
			sim.set_cell(x, y, D.AIR)
	var lp: Rect2i = info["lava_pockets"][1]
	var lx := lp.get_center().x
	for y in range(lp.position.y - 30, lp.position.y + 4):
		for x in range(lx - 2, lx + 3):
			if sim.get_cell(x, y) == D.STONE:
				sim.set_cell(x, y, D.AIR)
	var shots := [20, 90, 240, 900]
	var row := Image.create(4 * 100 * 2 + 30, 200 * 2, false, Image.FORMAT_RGB8)
	row.fill(Color("#000000"))
	var lrow := Image.create(4 * 60 * 3 + 30, 60 * 3, false, Image.FORMAT_RGB8)
	var k := 0
	for t in 901:
		if t % 3 == 0 and t < 700:
			sim.set_cell(lx, lp.position.y - 28, D.WATER)
		sim.step()
		if t in shots:
			var a := crop(sim, Rect2i(sx - 48, aq.position.y - 20, 100, 200), 2)
			row.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i(k * 210, 0))
			var b := crop(sim, Rect2i(lx - 30, lp.position.y - 32, 60, 60), 3)
			lrow.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(k * 190, 0))
			k += 1
	row.save_png("/home/claude/shots/flood.png")
	lrow.save_png("/home/claude/shots/lava.png")
	print("done; reactions ", sim.reactions)
	quit()
