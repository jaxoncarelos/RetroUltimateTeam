class_name CountBadge
extends Control
## Red notification dot with a count (or short text) and a white rim, pulsing.

var text := "1"
var _t := 0.0


func _init(p_text := "1") -> void:
	text = p_text
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := maxf(11.0, PixelFont.text_width(p_text) + 6.0)
	custom_minimum_size = Vector2(w, 11)
	size = custom_minimum_size
	z_index = 5


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var k := 1.0 + 0.12 * maxf(0.0, sin(_t * 6.0))
	draw_set_transform(size * 0.5 * (1.0 - k), 0.0, Vector2(k, k))
	draw_rect(Rect2(1, 0, size.x - 2, size.y), Color.WHITE)
	draw_rect(Rect2(0, 1, size.x, size.y - 2), Color.WHITE)
	draw_rect(Rect2(2, 1, size.x - 4, size.y - 2), UiSkin.RED)
	draw_rect(Rect2(1, 2, size.x - 2, size.y - 4), UiSkin.RED)
	UiSkin.draw_text_c(self, size.x * 0.5, 9, text, 8, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
