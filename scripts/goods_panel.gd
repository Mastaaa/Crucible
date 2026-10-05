extends PanelContainer
## The goods terminal (A5): a list of every good the Hub holds, one row each, in id order.
## Built by hud.gd, bottom right, growing upward; `refresh` runs with the HUD's own and
## hides the panel while there is nothing banked.

const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")

var hud
var rows: VBoxContainer
var title: Label


func setup(h) -> void:
	hud = h
	hud._anchor(self, 1.0, 1.0, 1.0, 1.0, -326, -8, -126, -8)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)
	title = hud._label("Goods", 13, hud.GOLD)
	vb.add_child(title)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 1)
	vb.add_child(rows)


func refresh(g) -> void:
	visible = not g.goods.is_empty() and not g.bench and not g.run_lost and not (g.won and not g.carry_on) \
			and not hud.research_panel.visible
	if not visible:
		return
	var off := -8.0 - (226.0 if hud.crucible_panel.visible else 0.0)
	offset_top = off
	offset_bottom = off
	var ids: Array = g.goods.keys()
	ids.sort()
	while rows.get_child_count() < ids.size():
		rows.add_child(hud._label("", 12))
	for k in rows.get_child_count():
		var row: Label = rows.get_child(k)
		row.visible = k < ids.size()
		if k < ids.size():
			var mat: int = ids[k]
			row.text = "%s   %s" % [M.names[mat], _units(g.goods[mat])]
			row.add_theme_color_override("font_color", M.color_of(mat).lerp(Color.WHITE, 0.6))


## Units to one decimal under ten, whole above.
static func _units(u: float) -> String:
	return "%.1f" % u if u < 10.0 else "%d" % int(u)
