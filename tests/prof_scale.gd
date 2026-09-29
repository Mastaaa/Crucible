extends SceneTree
const D = preload("res://scripts/defs.gd")
## Where a tick's time goes at the new scale: the tick itself, and each of the
## periodic refreshes timed on its own.
##   godot --headless --path . --script tests/prof_scale.gd

var game: Node
var frames := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _t(label: String, f: Callable, n := 5) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call()
	print("  %-18s %7.2f ms" % [label, (Time.get_ticks_usec() - t0) / 1000.0 / n])


func _process(_d: float) -> bool:
	frames += 1
	if frames < 2:
		return false
	var t0 := Time.get_ticks_usec()
	game.new_game(7)
	print("new_game: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	game.paused = true
	t0 = Time.get_ticks_usec()
	game.run_ticks(600)
	print("600 ticks: %.2f ms a tick (sim %.2f)" % [(Time.get_ticks_usec() - t0) / 600000.0, game.perf_sim_ms])
	_t("_refresh_vision", game._refresh_vision)

	_t("_refresh_sense", game._refresh_sense)
	_t("_upload", func() -> void:
		game.sim.changed = true
		game.light_due = true
		game._upload())
	game.reveal_all = true
	_t("snap_place hub", func() -> void:
		game.snap_key = []
		game.snap_place(D.B_LAB, Vector2i(200, 150), false))
	_t("check_place", func() -> void: game.check_place(D.B_LAB, Rect2i(200, 150, 40, 30)))
	return true
