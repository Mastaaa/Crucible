extends PanelContainer
## The goal layer's HUD panel (A3): the run goal with a depth readout and a tremor
## line, the chapter objective, and the Hub's current instruction with a skip button
## for the tutorial. Built by hud.gd; `refresh` runs with the HUD's own.

const D = preload("res://scripts/defs.gd")
const Goals = preload("res://scripts/goals.gd")

var hud
var depth_label: Label
var tremor_label: Label
var chapter_label: Label
var order_label: Label
var skip_button: Button


func setup(h) -> void:
	hud = h
	hud._anchor(self, 1.0, 0.0, 1.0, 0.0, -326, 42, -126, 42)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	add_child(vb)
	vb.add_child(hud._label("Light the Crucible", 15, hud.GOLD))
	depth_label = hud._label("", 12)
	vb.add_child(depth_label)
	tremor_label = hud._label("", 11, hud.DIM)
	vb.add_child(tremor_label)
	chapter_label = _wrapped("", 11, hud.DIM)
	vb.add_child(chapter_label)
	order_label = _wrapped("", 13, Color(1.0, 0.93, 0.8))
	vb.add_child(order_label)
	skip_button = hud._button("Skip tutorial")
	skip_button.pressed.connect(func() -> void: Goals.skip_tutorial(hud.game))
	vb.add_child(skip_button)


func _wrapped(text: String, fs: int, col: Color) -> Label:
	var l: Label = hud._label(text, fs, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(190, 0)
	return l


func refresh(g) -> void:
	visible = not g.run_lost and not (g.won and not g.carry_on) and not hud.research_panel.visible
	if not visible:
		return
	var gl: Dictionary = g.goals
	var band := "Surface"
	for k in D.LAYERS.size():
		if g.deepest >= D.LAYERS[k]["top"]:
			band = D.LAYERS[k]["name"]
	depth_label.text = "Depth %d of %d   %s" % [g.deepest, int(D.LAYERS[4]["top"]), band]
	var t := Goals.tremor(g)
	tremor_label.text = "" if t <= 0.0 else "Something below is moving. %s." % ["Faint", "Steady", "Heavy"][mini(int(t * 3.0), 2)]
	tremor_label.modulate.a = 0.55 + 0.45 * sin(g.game_time * (1.5 + 3.0 * t))
	var c: Dictionary = Goals.chapter(g)
	if c.is_empty():
		chapter_label.text = "Every chapter is done."
	else:
		chapter_label.text = "Chapter %d, %s: %s Hazard: %s" % [gl["chapter"] + 1, c["band"], c["objective"], c["hazard"]]
	if not gl["cur"].is_empty():
		var prog := Goals.progress(g)
		order_label.text = "Instruction %d: %s%s" % [gl["cur"]["n"], gl["cur"]["text"], "   " + prog if prog != "" else ""]
	elif gl["mode"] == "standing":
		order_label.text = "The Hub has no instruction. Next in %s." % hud._clock(maxf(0.0, gl["next_t"] - g.game_time))
	else:
		order_label.text = ""
	skip_button.visible = gl["mode"] == "tutorial"
