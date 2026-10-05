extends Node2D
## Draws the inside of every module that has an interior (scripts/machines/interior.gd): the
## interior's open box as a texture of material ids, run through the palette by a small shader
## and squeezed into the module's cavity. It sits behind the overlay's own drawing, in
## screen space like it.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")

const SHADER := """
shader_type canvas_item;
uniform sampler2D palette : filter_nearest;
void fragment() {
	int id = int(floor(texture(TEXTURE, UV).r * 255.0 + 0.5));
	if (id == 0) {
		discard;
	}
	vec4 c = texelFetch(palette, ivec2(id, 0), 0);
	COLOR = vec4(c.rgb, 0.92);
}
"""

var game: Node2D
var _pal: ImageTexture
var _tex := {}                  # sim instance id -> {"img": Image, "tex": ImageTexture}
var _sweep := 0


func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_pal = ImageTexture.create_from_image(M.palette_image())
	mat.set_shader_parameter("palette", _pal)
	material = mat
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show_behind_parent = true


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var g = game
	if g == null or g.sim == null or g.modules.is_empty():
		return
	var vs := get_viewport_rect().size
	var seen := {}
	for id: int in g.modules:
		var m: Dictionary = g.modules[id]
		var sim: Variant = m.get("sim")
		if sim == null:
			continue
		var def: Dictionary = MU.defs[m["def"]]
		var fr := MU.frame(g, m, def)
		var size: Vector2i = fr["lay"]["size"]
		var t := float(def["wall"])
		var pts := PackedVector2Array()
		for c: Vector2 in [Vector2(t, t), Vector2(size.x - t, t), Vector2(size.x - t, size.y - t), Vector2(t, size.y - t)]:
			pts.append(g.to_screen(MU.world(fr, c)))
		var lo := Vector2(minf(minf(pts[0].x, pts[1].x), minf(pts[2].x, pts[3].x)), minf(minf(pts[0].y, pts[1].y), minf(pts[2].y, pts[3].y)))
		var hi := Vector2(maxf(maxf(pts[0].x, pts[1].x), maxf(pts[2].x, pts[3].x)), maxf(maxf(pts[0].y, pts[1].y), maxf(pts[2].y, pts[3].y)))
		if hi.x < 0.0 or hi.y < 0.0 or lo.x > vs.x or lo.y > vs.y:
			continue
		var key: int = sim.get_instance_id()
		seen[key] = true
		var tex := _texture(key, sim, m["box"])
		draw_colored_polygon(pts, Color.WHITE, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), tex)
	_sweep += 1
	if _sweep % 120 == 0:
		for key: int in _tex.keys():
			if not seen.has(key):
				_tex.erase(key)


## The interior's open box as a texture of ids, refreshed when the sim has changed.
func _texture(key: int, sim: RefCounted, box: Rect2i) -> ImageTexture:
	var e: Variant = _tex.get(key)
	if e != null and e["box"] == box and not sim.get_changed():
		return e["tex"]
	var cells: PackedByteArray = sim.get_cells()
	var w: int = sim.get_width()
	var bytes := PackedByteArray()
	for y in range(box.position.y, box.end.y):
		bytes.append_array(cells.slice(y * w + box.position.x, y * w + box.end.x))
	var img := Image.create_from_data(box.size.x, box.size.y, false, Image.FORMAT_R8, bytes)
	sim.set_changed(false)
	if e == null or e["box"] != box:
		e = {"box": box, "tex": ImageTexture.create_from_image(img)}
		_tex[key] = e
	else:
		e["tex"].update(img)
	return e["tex"]
