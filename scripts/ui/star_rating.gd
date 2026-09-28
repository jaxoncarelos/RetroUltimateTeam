class_name StarRating
extends Control
## Row of up to 5 pixel stars with halves (offense blue, defense red, cards yellow).

var value := 3.0:
	set(v):
		value = v
		queue_redraw()
var color := UiSkin.STAR_BLUE
var star_scale := 1.0
var count := 5


func _init(p_value := 3.0, p_color := UiSkin.STAR_BLUE, p_scale := 1.0) -> void:
	value = p_value
	color = p_color
	star_scale = p_scale
	custom_minimum_size = Vector2(count * 9 - 1, 9) * p_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var pitch := 9.0 * star_scale
	var total := count * pitch - 2.0 * star_scale
	var x0 := roundf((size.x - total) * 0.5)
	var y0 := roundf((size.y - 7.0 * star_scale) * 0.5)
	for i in count:
		UiSkin.draw_star(self, Vector2(x0 + i * pitch, y0), color, clampf(value - i, 0.0, 1.0), star_scale)
