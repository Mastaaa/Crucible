extends RefCounted
## Makes the world simulation: the C++ one (native/, loaded from
## bin/crucible_sim.gdextension) when Godot has it, set up from
## data/materials.json; otherwise the old GDScript one in sim.gd, which is slower
## and ignores the data file.

const M = preload("res://scripts/materials.gd")
const SimGD = preload("res://scripts/sim.gd")

static var warned := false


## The C++ sim is used when it's loaded, unless the game was started with
## `-- --gdscript-sim` (for comparing the two).
static func native_available() -> bool:
	return ClassDB.class_exists("CrucibleSim") and not OS.get_cmdline_user_args().has("--gdscript-sim")


static func create(threads := -1) -> RefCounted:
	if native_available():
		var s: RefCounted = ClassDB.instantiate("CrucibleSim")
		M.ensure()
		s.configure(M.sim_materials, M.sim_reactions)
		if threads < 0:
			threads = clampi(OS.get_processor_count() - 1, 1, 4)
		s.set_threads(threads)
		if not warned:
			warned = true
			print("Crucible: C++ simulation, %d thread%s." % [threads, "" if threads == 1 else "s"])
		return s
	if not warned:
		warned = true
		push_warning("The C++ simulation isn't loaded (bin/crucible_sim.gdextension); using the slower GDScript one.")
	return SimGD.new()
