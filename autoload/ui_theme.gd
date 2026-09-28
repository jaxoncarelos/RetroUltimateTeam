extends Node
## Installs the pixel font + a flat retro Theme for every Control in the game.

const INK := Color("#10141f")
const PANEL := Color("#1d2b53")
const PANEL_LIGHT := Color("#29366f")
const TEXT := Color("#fff1e8")
const ACCENT := Color("#ffec27")
const DIM := Color("#83769c")

var theme: Theme


func _ready() -> void:
	ThemeDB.fallback_font = PixelFont.get_font()
	ThemeDB.fallback_font_size = PixelFont.BASE_SIZE
	theme = _build_theme()
	# The engine default theme carries its own font, which beats ThemeDB.fallback_font,
	# so merge our look into it directly (covers every Control, including popups).
	var default_theme := ThemeDB.get_default_theme()
	default_theme.merge_with(theme)
	default_theme.default_font = theme.default_font
	default_theme.default_font_size = theme.default_font_size
	get_tree().root.theme = theme


func _box(bg: Color, border: Color, border_w := 1, pad := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	sb.set_content_margin_all(pad)
	return sb


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = PixelFont.get_font()
	t.default_font_size = PixelFont.BASE_SIZE

	t.set_stylebox("normal", "Button", _box(PANEL, TEXT))
	t.set_stylebox("hover", "Button", _box(PANEL_LIGHT, TEXT))
	t.set_stylebox("pressed", "Button", _box(ACCENT, TEXT))
	t.set_stylebox("disabled", "Button", _box(INK, DIM))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", DIM)

	t.set_stylebox("panel", "PanelContainer", _box(Color(INK, 0.85), TEXT, 1, 3))
	t.set_stylebox("panel", "Panel", _box(Color(INK, 0.85), TEXT, 1, 3))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", INK)
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", 1)
	return t
