class_name RetroBg
extends Control
## Screen background: royal-blue vertical gradient, a faint tiled emblem pattern and thin
## light lines under the header and above the bottom nav (Retro Bowl-style menus).

var header_line := 28.0       ## y of the line under the title (<= 0: none)
var footer_line := 38.0       ## distance of the footer line from the bottom (<= 0: none)
var tint := Color(1, 1, 1, 1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var h := size.y
	var y := 0.0
	while y < h:
		var u := absf((y / maxf(h, 1.0)) - 0.5) * 2.0
		draw_rect(Rect2(0, y, size.x, 2), UiSkin.BLUE.lerp(UiSkin.BLUE_DARK, u * u) * tint)
		y += 2.0
	draw_texture_rect(UiSkin.bg_tile(), r, true)
	if header_line > 0.0:
		draw_rect(Rect2(0, 0, size.x, header_line), Color(0.02, 0.05, 0.25, 0.18))
		draw_rect(Rect2(0, header_line, size.x, 1), Color(UiSkin.BLUE_LINE, 0.9))
		draw_rect(Rect2(0, header_line + 1, size.x, 1), Color(0.02, 0.05, 0.3, 0.35))
	if footer_line > 0.0:
		var fy := h - footer_line
		draw_rect(Rect2(0, fy, size.x, footer_line), Color(0.02, 0.05, 0.25, 0.18))
		draw_rect(Rect2(0, fy, size.x, 1), Color(UiSkin.BLUE_LINE, 0.9))
