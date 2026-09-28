class_name TitleBar
extends Control
## Big outlined pixel title centered at the top, between star ornaments and emblems:
## [emblem] * * * TITLE * * * [emblem].

const STAR_COLS := [UiSkin.STAR_RED, UiSkin.WHITE, Color("#1b2a8a")]

var text := "":
	set(v):
		text = v
		queue_redraw()
var font_size := 16
var ornaments := true


func _init(p_text := "") -> void:
	text = p_text
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 26)


func _draw() -> void:
	var cx := size.x * 0.5
	var tw := PixelFont.text_width(text, font_size)
	var th := 7 * font_size / 8
	var base_y := roundf((size.y + th) * 0.5)
	UiSkin.draw_text_c(self, cx, base_y, text, font_size, UiSkin.WHITE, UiSkin.SHADOW, Color(0.02, 0.03, 0.15, 0.9))
	if not ornaments:
		return
	var s := 2.0 if font_size >= 16 else 1.0
	var star_w := 7.0 * s
	var gap := 2.0
	var top := roundf(base_y - th + (th - star_w) * 0.5)
	var left := roundf(cx - tw * 0.5 - 8.0)
	var right := roundf(cx + tw * 0.5 + 8.0)
	for i in 3:
		var lx := left - (i + 1) * star_w - i * gap
		UiSkin.draw_star(self, Vector2(lx, top), STAR_COLS[2 - i], 1.0, s)
		var rx := right + i * (star_w + gap)
		UiSkin.draw_star(self, Vector2(rx, top), STAR_COLS[2 - i], 1.0, s)
	var em := UiSkin.emblem()
	var ex_l := left - 3 * star_w - 2 * gap - 7.0 - 15.0
	var ex_r := right + 3 * star_w + 2 * gap + 7.0
	if ex_l > 76.0:
		draw_texture(em, Vector2(ex_l, base_y - th - 2))
		draw_texture(em, Vector2(ex_r, base_y - th - 2))
