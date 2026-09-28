class_name IconButton
extends Button
## Square navy button showing a pixel icon (home, gear, info, back…).

var icon_name := "home"
var icon_color := UiSkin.WHITE
var icon_scale := 1.0


func _init(p_icon := "home", p_size := Vector2(28, 28), p_scale := 1.0) -> void:
	icon_name = p_icon
	icon_scale = p_scale
	custom_minimum_size = p_size
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var tex := UiSkin.icon(icon_name)
	var sz := tex.get_size() * icon_scale
	var down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	var at := ((size - sz) * 0.5).round() + (Vector2(0, 1) if down else Vector2(1, -1))
	var col := UiSkin.NAVY_DEEP if down else icon_color
	UiSkin.draw_icon(self, icon_name, at, col, icon_scale, not down)
