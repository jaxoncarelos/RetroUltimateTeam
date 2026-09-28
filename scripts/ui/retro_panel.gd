class_name RetroPanel
extends PanelContainer
## Navy framed panel with a thin light border and an inset section label drawn over the
## top border ("- SALARY CAP -").

var title := "":
	set(v):
		title = v
		_apply()
		queue_redraw()
var title_color := UiSkin.WHITE
var fill := UiSkin.PANEL
var pad := 5


func _init(p_title := "", p_fill := UiSkin.PANEL, p_pad := 5) -> void:
	fill = p_fill
	pad = p_pad
	title = p_title


func _apply() -> void:
	var sb := UiSkin.panel_box(fill, UiSkin.BORDER, pad)
	if title != "":
		sb.content_margin_top = pad + 5
	add_theme_stylebox_override("panel", sb)


func _draw() -> void:
	if title == "":
		return
	var t := "- %s -" % title
	var w := PixelFont.text_width(t)
	var x := roundf((size.x - w) * 0.5)
	draw_rect(Rect2(x - 3, 0, w + 6, 1), fill)
	UiSkin.draw_text(self, Vector2(x, 4), t, 8, title_color, UiSkin.SHADOW)
