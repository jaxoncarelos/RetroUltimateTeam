class_name FieldView
extends Node2D
## Draws turf, yard lines, numbers, hashes, end zones, and the LOS / first-down markers.

const GRASS_A := Color("#2f8a3a")
const GRASS_B := Color("#2a7d34")
const BORDER := Color("#1f5c28")
const LINE := Color("#f4f4f4")
const LOS_COLOR := Color("#29adff")
const FIRST_DOWN_COLOR := Color("#ffec27")

var left_endzone := Color("#1d2b53")
var right_endzone := Color("#7e2553")
var left_label := "HOME"
var right_label := "AWAY"

var los_x := -1.0:
	set(v):
		los_x = v
		queue_redraw()
var first_down_x := -1.0:
	set(v):
		first_down_x = v
		queue_redraw()


func _px(x_yd: float, y_yd: float) -> Vector2:
	return FieldProjection.to_screen(Vector2(x_yd, y_yd))


func _yard_rect(x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	var a := _px(x0, y0)
	var b := _px(x1, y1)
	draw_rect(Rect2(a, b - a), c)


func _draw() -> void:
	var font := PixelFont.get_font()
	draw_rect(FieldProjection.world_rect(), BORDER)
	# 5-yard grass stripes
	var x := 0.0
	var i := 0
	while x < FieldGeo.LENGTH:
		_yard_rect(x, 0, x + 5.0, FieldGeo.WIDTH, GRASS_A if i % 2 == 0 else GRASS_B)
		x += 5.0
		i += 1
	# End zones
	_yard_rect(0, 0, FieldGeo.OWN_GOAL, FieldGeo.WIDTH, left_endzone)
	_yard_rect(FieldGeo.OPP_GOAL, 0, FieldGeo.LENGTH, FieldGeo.WIDTH, right_endzone)
	_draw_endzone_text(font, 5.0, left_label)
	_draw_endzone_text(font, 115.0, right_label)
	# Yard lines every 5, hashes every yard
	for yd in range(int(FieldGeo.OWN_GOAL), int(FieldGeo.OPP_GOAL) + 1):
		var sx := int(_px(yd, 0).x)
		if yd % 5 == 0:
			draw_rect(Rect2(sx, 0, 1, FieldGeo.WIDTH * FieldProjection.PX_Y), LINE)
		else:
			for hy in [0.6, FieldGeo.HASH_TOP, FieldGeo.HASH_BOTTOM, FieldGeo.WIDTH - 0.6]:
				draw_rect(Rect2(sx, int(_px(0, hy).y) - 1, 1, 2), Color(LINE, 0.8))
	# Numbers
	for yd in range(20, 110, 10):
		var n := FieldGeo.yard_line_number(yd)
		for ny in [9.0, FieldGeo.WIDTH - 7.0]:
			var p := _px(yd, ny)
			draw_string(font, Vector2(p.x - 6, p.y), str(n), HORIZONTAL_ALIGNMENT_CENTER, 12, 8, Color(LINE, 0.9))
	# Sidelines
	draw_rect(Rect2(_px(0, 0) - Vector2(0, 2), Vector2(FieldGeo.LENGTH * FieldProjection.PX_X, 2)), LINE)
	draw_rect(Rect2(_px(0, FieldGeo.WIDTH), Vector2(FieldGeo.LENGTH * FieldProjection.PX_X, 2)), LINE)
	# Markers
	if los_x >= 0.0:
		draw_rect(Rect2(int(_px(los_x, 0).x) - 1, 0, 2, FieldGeo.WIDTH * FieldProjection.PX_Y), LOS_COLOR)
	if first_down_x >= 0.0 and first_down_x < FieldGeo.OPP_GOAL:
		draw_rect(Rect2(int(_px(first_down_x, 0).x) - 1, 0, 2, FieldGeo.WIDTH * FieldProjection.PX_Y), FIRST_DOWN_COLOR)


func _draw_endzone_text(font: Font, center_x: float, text: String) -> void:
	var step := FieldGeo.WIDTH / float(text.length() + 1)
	for i in text.length():
		var p := _px(center_x, step * (i + 1))
		draw_string(font, Vector2(p.x - 8, p.y + 4), text[i], HORIZONTAL_ALIGNMENT_CENTER, 16, 16, Color(LINE, 0.85))
