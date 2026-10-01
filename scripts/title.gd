extends CanvasLayer
## The title screen (phase 10): Continue the saved run, or Start Run on a new
## world (a seed if one's typed, else the one behind the menu). Esc goes back to
## the run in hand.

const Save = preload("res://scripts/save.gd")
const GOLD := Color(0.96, 0.76, 0.36)
const DIM := Color(0.66, 0.70, 0.78)

var game: Node
var root: Control
var continue_button: Button
var seed_edit: LineEdit
var note: Label


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.theme = game.hud._make_theme()
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = -190
	panel.offset_bottom = 190
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var name_label := _label("CRUCIBLE", 36, GOLD)
	vb.add_child(name_label)
	vb.add_child(_label("Feed and light the Crucible at the bottom of the world.", 13, DIM))
	vb.add_child(HSeparator.new())
	continue_button = _button("Continue")
	continue_button.pressed.connect(_on_continue)
	vb.add_child(continue_button)
	var start := _button("Start Run")
	start.pressed.connect(func() -> void: game.start_run(seed_edit.text))
	vb.add_child(start)
	var bench := _button("Lab Bench")
	bench.tooltip_text = "An open room to paint any material into, heat it and cool it, and watch what it does. Never saved."
	bench.pressed.connect(func() -> void: game.start_bench())
	vb.add_child(bench)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "Seed (blank for a random one)"
	seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_edit.text_submitted.connect(func(t: String) -> void: game.start_run(t))
	vb.add_child(seed_edit)
	var quit := _button("Quit")
	quit.pressed.connect(func() -> void: game.quit_game())
	vb.add_child(quit)
	note = _label("", 12, DIM)
	vb.add_child(note)
	vb.add_child(_label("F1 in the run lists the controls. Esc comes back here.", 12, DIM))


func apply_layout(vs: Vector2, ui_scale: float) -> void:
	scale = Vector2(ui_scale, ui_scale)
	if root:
		root.size = vs / ui_scale


## Show the menu, with Continue set for what there is to go back to.
func open() -> void:
	visible = true
	note.text = ""
	if game.live_run and not game.run_lost and not game.bench:
		continue_button.text = "Continue (seed %d, %s)" % [game.seed_value, _clock(game.game_time)]
		continue_button.disabled = false
	else:
		var head: Dictionary = Save.peek()
		continue_button.disabled = head.is_empty()
		if head.is_empty():
			continue_button.text = "Continue (no saved run)"
		else:
			continue_button.text = "Continue (seed %d, %s)" % [head["seed"], _clock(head["time"])]


func _on_continue() -> void:
	if not game.continue_game():
		note.text = "That save couldn't be read."
		continue_button.disabled = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE \
			and game.live_run and not game.run_lost:
		get_viewport().set_input_as_handled()
		if game.bench:
			game.start_bench()
		else:
			game.continue_game()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(260, 34)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [int(s / 3600.0), int(s / 60.0) % 60, s % 60]
