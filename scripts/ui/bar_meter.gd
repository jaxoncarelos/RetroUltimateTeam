class_name BarMeter
extends Control
## Yellow bar meter on black with a light border; `frac` animates with fill_to().

var frac := 0.0:
	set(v):
		frac = v
		queue_redraw()
var color := UiSkin.YELLOW
var segments := 0


func _init(p_frac := 0.0, p_size := Vector2(100, 10), p_color := UiSkin.YELLOW) -> void:
	frac = p_frac
	color = p_color
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func fill_to(v: float, dur := 0.6) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "frac", v, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


func _draw() -> void:
	UiSkin.draw_bar(self, Rect2(Vector2.ZERO, size), frac, color, segments)
