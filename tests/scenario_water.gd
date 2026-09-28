extends SceneTree
## Breach an aquifer into a shaft with a hopper at the bottom; measure the flood
## for several hopper intake rates.

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

func run(rate: float, breach_row_from_bottom: int) -> void:
	var sim = SimFactory.create()
	var info := WorldGen.new().generate(sim, 123)
	var aq: Rect2i = info["aquifers"][0]          # (113..170, 121..150)
	var sx := aq.position.x - 12                   # shaft 12 cells left of the aquifer box
	var hop_y := aq.end.y + 20                     # hopper top row
	for y in range(D.GROUND_Y, hop_y + 3):
		for x in range(sx, sx + 5):
			sim.set_cell(x, y, D.AIR)
	for y in range(hop_y, hop_y + 3):
		for x in range(sx, sx + 5):
			sim.set_cell(x, y, D.BUILDING)
	# breach tunnel from the shaft into the aquifer's side
	var by := aq.end.y - breach_row_from_bottom - 5
	var x := sx + 5
	while x < aq.position.x + 20:
		for y in range(by, by + 5):
			if sim.get_cell(x, y) != D.WATER:
				sim.set_cell(x, y, D.AIR)
		x += 1
	var intake := 0.0
	var taken := 0
	var peak := 0
	var line := ""
	for t in 60 * 90:
		sim.step()
		intake = minf(intake + rate / 60.0, 5.0)
		for k in 5:
			if intake < 1.0: break
			if sim.get_cell(sx + k, hop_y - 1) == D.WATER:
				sim.set_cell(sx + k, hop_y - 1, D.AIR)
				intake -= 1.0
				taken += 1
		if t % 300 == 0:
			var pool := 0
			for y in range(hop_y - 1, D.GROUND_Y, -1):
				var wet := 0
				for k in 5:
					if sim.get_cell(sx + k, y) == D.WATER: wet += 1
				if wet >= 4: pool += 1
				else: break
			peak = maxi(peak, pool)
			line += " %ds:pool%d/taken%d" % [t / 60.0, pool, taken]
	print("rate %3d/s breach %d rows up: peak pool %d rows, taken %d cells in 90 s |%s" % [int(rate), breach_row_from_bottom, peak, taken, line])

func _initialize() -> void:
	for rate in [90.0, 120.0]:
		run(rate, 0)
	run(90.0, 12)
	quit()
