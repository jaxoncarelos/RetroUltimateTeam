extends Node
## Installs the pixel font + the Retro-arcade Theme (UiSkin) for every Control in the game,
## and gives every Button a little juice: a squish on press, a bounce on release and a
## tap sound (set meta "no_juice" on a button to skip it, "silent" to skip the sound).

const INK := Color("#10141f")
const PANEL := Color("#1d2b53")
const PANEL_LIGHT := Color("#29366f")
const TEXT := Color("#f6f8ff")
const ACCENT := Color("#ffd21f")
const DIM := Color("#93a6e8")

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
	get_tree().node_added.connect(_on_node_added)


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

	t.set_stylebox("normal", "Button", UiSkin.button_box(UiSkin.NAVY, UiSkin.BORDER))
	t.set_stylebox("hover", "Button", UiSkin.button_box(UiSkin.NAVY_HI, UiSkin.BORDER))
	t.set_stylebox("pressed", "Button", UiSkin.button_box(UiSkin.YELLOW, UiSkin.BORDER, true))
	t.set_stylebox("hover_pressed", "Button", UiSkin.button_box(UiSkin.YELLOW, UiSkin.BORDER, true))
	t.set_stylebox("disabled", "Button", UiSkin.button_box(Color("#232a5c"), UiSkin.GREY))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", UiSkin.NAVY_DEEP)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_hover_pressed_color", "Button", UiSkin.NAVY_DEEP)
	t.set_color("font_disabled_color", "Button", UiSkin.GREY)

	# Yellow call-to-action button (CONTINUE, PLAY, CLAIM, BUY).
	t.set_type_variation("YellowButton", "Button")
	t.set_stylebox("normal", "YellowButton", UiSkin.button_box(UiSkin.YELLOW, UiSkin.BORDER))
	t.set_stylebox("hover", "YellowButton", UiSkin.button_box(UiSkin.YELLOW.lightened(0.2), UiSkin.BORDER))
	t.set_stylebox("pressed", "YellowButton", UiSkin.button_box(UiSkin.YELLOW.darkened(0.1), UiSkin.BORDER, true))
	t.set_stylebox("hover_pressed", "YellowButton", UiSkin.button_box(UiSkin.YELLOW.darkened(0.1), UiSkin.BORDER, true))
	t.set_color("font_color", "YellowButton", UiSkin.NAVY_DEEP)
	t.set_color("font_hover_color", "YellowButton", UiSkin.NAVY_DEEP)
	t.set_color("font_pressed_color", "YellowButton", UiSkin.NAVY_DEEP)
	t.set_color("font_hover_pressed_color", "YellowButton", UiSkin.NAVY_DEEP)

	# In-game pill (dark translucent, thin light border) for the HUD.
	t.set_type_variation("PillButton", "Button")
	var pill := _box(Color(0.02, 0.03, 0.08, 0.82), Color(1, 1, 1, 0.75), 1, 3)
	pill.set_corner_radius_all(2)
	var pill_hi := _box(Color(0.1, 0.12, 0.25, 0.9), Color(1, 1, 1, 0.95), 1, 3)
	pill_hi.set_corner_radius_all(2)
	var pill_on := _box(UiSkin.YELLOW, Color.WHITE, 1, 3)
	pill_on.set_corner_radius_all(2)
	t.set_stylebox("normal", "PillButton", pill)
	t.set_stylebox("hover", "PillButton", pill_hi)
	t.set_stylebox("pressed", "PillButton", pill_on)
	t.set_stylebox("hover_pressed", "PillButton", pill_on)
	t.set_stylebox("disabled", "PillButton", pill)
	t.set_stylebox("focus", "PillButton", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "PillButton", UiSkin.NAVY_DEEP)
	t.set_color("font_hover_pressed_color", "PillButton", UiSkin.NAVY_DEEP)

	# Match HUD: calm navy cards / buttons with a muted edge; yellow = selected / primary.
	var hud_fill := Color(UiSkin.PANEL, 0.94)
	for v in ["HudButton", "HudButtonHot", "HudCard"]:
		t.set_type_variation(v, "Button")
		var edge := UiSkin.YELLOW_DARK if v == "HudButtonHot" else UiSkin.HUD_EDGE
		t.set_stylebox("normal", v, UiSkin.button_box(hud_fill, edge))
		t.set_stylebox("hover", v, UiSkin.button_box(UiSkin.NAVY_HI, edge))
		t.set_stylebox("pressed", v, UiSkin.button_box(UiSkin.YELLOW, UiSkin.YELLOW_DARK, true))
		t.set_stylebox("hover_pressed", v, UiSkin.button_box(UiSkin.YELLOW, UiSkin.YELLOW_DARK, true))
		t.set_stylebox("disabled", v, UiSkin.button_box(hud_fill, UiSkin.GREY))
		t.set_color("font_pressed_color", v, UiSkin.NAVY_DEEP)
		t.set_color("font_hover_pressed_color", v, UiSkin.NAVY_DEEP)
	t.set_color("font_color", "HudButtonHot", UiSkin.YELLOW)
	t.set_color("font_hover_color", "HudButtonHot", UiSkin.YELLOW)

	t.set_stylebox("panel", "PanelContainer", UiSkin.panel_box())
	t.set_stylebox("panel", "Panel", UiSkin.panel_box())
	t.set_type_variation("PillPanel", "PanelContainer")
	var pp := _box(Color(0.02, 0.03, 0.08, 0.85), Color(1, 1, 1, 0.8), 1, 4)
	pp.set_corner_radius_all(2)
	t.set_stylebox("panel", "PillPanel", pp)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", UiSkin.SHADOW)
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", 1)

	# Thin light scrollbars.
	for sb_type in ["VScrollBar", "HScrollBar"]:
		var track := _box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 0)
		var grab := _box(Color(1, 1, 1, 0.7), Color(0, 0, 0, 0), 0, 0)
		t.set_stylebox("scroll", sb_type, track)
		t.set_stylebox("grabber", sb_type, grab)
		t.set_stylebox("grabber_highlight", sb_type, grab)
		t.set_stylebox("grabber_pressed", sb_type, grab)
	return t


# ---------------------------------------------------------------- button juice

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("no_juice"):
		var b := n as BaseButton
		if b.has_meta("_juiced"):
			return
		b.set_meta("_juiced", true)
		b.button_down.connect(_squish.bind(b))
		b.button_up.connect(_bounce.bind(b))
		b.pressed.connect(_click.bind(b))


func _squish(b: BaseButton) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(0.92, 0.9), 0.05)


func _bounce(b: BaseButton) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(1.06, 1.06), 0.07)
	tw.tween_property(b, "scale", Vector2.ONE, 0.09)


func _click(b: BaseButton) -> void:
	if is_instance_valid(b) and not b.has_meta("silent"):
		Sfx.play("tap")
