extends SceneTree
## Sim benchmark: breach an aquifer with a shaft and time the flood.

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

func _initialize() -> void:
	var sim = SimFactory.create()
	var info := WorldGen.new().generate(sim, 123)
	# Shaft straight down through the first aquifer.
	var aq: Rect2i = info["aquifers"][0]
	var sx := aq.get_center().x - 2
	for y in range(D.GROUND_Y, 290):
		for x in range(sx, sx + 5):
			sim.set_cell(x, y, D.AIR)
	# A second scenario: open a lava pocket from above and drop water on it.
	var lp: Rect2i = info["lava_pockets"][1]
	var lx := lp.get_center().x
	for y in range(lp.position.y - 30, lp.position.y + 4):
		for x in range(lx - 2, lx + 3):
			if sim.get_cell(x, y) == D.STONE:
				sim.set_cell(x, y, D.AIR)
	var total := 0
	var worst := 0
	var ups := 0
	for t in 1800:
		if t % 3 == 0 and t < 1200:
			sim.set_cell(lx, lp.position.y - 28, D.WATER)
		if t % 2 == 0:
			sim.erode(D.ERODE_SAMPLES, D.GROUND_Y + 6, 330)
		var t0 := Time.get_ticks_usec()
		sim.step()
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		ups += sim.stat_updates
		if t % 300 == 0:
			print("tick %d: %.2f ms  chunks %d  updates %d  water %d  steam %d  obsidian %d" % [t, dt / 1000.0, sim.stat_chunks, sim.stat_updates, sim.count(D.WATER), sim.count(D.STEAM) + sim.count(D.STEAM+1) + sim.count(D.STEAM+2), sim.count(D.OBSIDIAN)])
	print("avg %.2f ms/tick, worst %.2f ms, avg updates %d, reactions %d, eroded %d" % [total / 1800.0 / 1000.0, worst / 1000.0, ups / 1800.0, sim.reactions, sim.eroded])
	quit()
