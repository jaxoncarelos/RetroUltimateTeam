class_name MetaUI
extends RefCounted
## Shared builders for the meta screens (480x270 canvas, Retro Bowl-style menus): the
## screen scaffold (background, star title, coin pill, info slot, content column, bottom
## nav with a Home button), buttons, framed panels, stat boxes, popups, badges and toasts.

const HEADER_H := 28
const FOOTER_H := 38


## Builds the scaffold on `owner`. Returns {"root": VBoxContainer (content column),
## "nav": HBoxContainer (bottom row), "coins": CoinPill, "title": TitleBar,
## "top_right": HBoxContainer, "top_left": HBoxContainer, "bg": RetroBg, "layer": Control}.
## back_to = "" hides the Home button. opts: "coins" (bool), "nav" (bool), "home_icon" (String).
static func screen(owner: Control, title: String, back_to := "res://scenes/meta/hub.tscn", opts: Dictionary = {}) -> Dictionary:
	owner.set_anchors_preset(Control.PRESET_FULL_RECT)
	var has_nav: bool = opts.get("nav", true)
	var bg := RetroBg.new()
	bg.footer_line = FOOTER_H if has_nav else 0.0
	owner.add_child(bg)
	var tb := TitleBar.new(title)
	tb.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tb.offset_top = 1
	tb.offset_bottom = HEADER_H - 1
	owner.add_child(tb)
	var tl := HBoxContainer.new()
	tl.position = Vector2(6, 6)
	tl.add_theme_constant_override("separation", 4)
	owner.add_child(tl)
	var coins := CoinPill.new(SaveManager.profile.coins)
	if opts.get("coins", true):
		tl.add_child(coins)
	var tr := HBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.offset_left = -200
	tr.offset_right = -6
	tr.offset_top = 3
	tr.offset_bottom = 25
	tr.alignment = BoxContainer.ALIGNMENT_END
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.add_theme_constant_override("separation", 4)
	owner.add_child(tr)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = HEADER_H + 5
	root.offset_bottom = -(FOOTER_H + 4) if has_nav else -6
	root.add_theme_constant_override("separation", 5)
	owner.add_child(root)
	var nav := HBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_left = 8
	nav.offset_right = -8
	nav.offset_top = -FOOTER_H + 5
	nav.offset_bottom = -4
	nav.add_theme_constant_override("separation", 6)
	nav.visible = has_nav
	owner.add_child(nav)
	if back_to != "" and has_nav:
		var home := IconButton.new(opts.get("home_icon", "home"))
		home.pressed.connect(func() -> void: SceneRouter.goto(back_to))
		nav.add_child(home)
	# Overlay layer for popups / flying coins (always on top).
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 10
	owner.add_child(layer)
	return {"root": root, "nav": nav, "coins": coins, "title": tb, "top_right": tr, "top_left": tl, "bg": bg,
			"layer": layer}


static func button(text: String, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## Yellow call-to-action button.
static func yellow(text: String, size: Vector2, cb: Callable) -> Button:
	var b := button(text, size, cb)
	b.theme_type_variation = "YellowButton"
	return b


## Bottom-nav button (two-line text allowed, fills the row evenly).
static func nav_button(text: String, cb: Callable, min_w := 70.0) -> Button:
	var b := button(text, Vector2(min_w, 28), cb)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## "CONTINUE >" style button at the right of the nav.
static func continue_button(text: String, cb: Callable, is_yellow := true, w := 110.0) -> Button:
	var b := yellow(text + " ▶", Vector2(w, 28), cb) if is_yellow else button(text + " ▶", Vector2(w, 28), cb)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	return b


static func label(text: String, color := UiTheme.TEXT, font_size := 8, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", color)
	if font_size != 8:
		l.add_theme_font_size_override("font_size", font_size)
	return l


static func panel(title := "", fill := UiSkin.PANEL, pad := 5) -> RetroPanel:
	return RetroPanel.new(title, fill, pad)


## Small titled box with centered content (like OFFENSE / DEFENSE star boxes).
static func stat_box(title: String, content: Control, min_size := Vector2(84, 30)) -> RetroPanel:
	var p := RetroPanel.new(title, UiSkin.PANEL, 3)
	p.custom_minimum_size = min_size
	var c := CenterContainer.new()
	c.add_child(content)
	p.add_child(c)
	return p


static func stars(value: float, color := UiSkin.STAR_BLUE, s := 1.0) -> StarRating:
	return StarRating.new(value, color, s)


## Scrollable area that fills the rest of the column.
static func scroll(parent: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	return sc


static func spacer(horizontal := true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Red pulsing count badge pinned to the top-right corner of `target` (0 removes it).
static func badge(target: Control, count: int, text := "") -> Control:
	var old := target.get_node_or_null("Badge")
	if old != null:
		target.remove_child(old)
		old.queue_free()
	if count <= 0 and text == "":
		return null
	var b := CountBadge.new(text if text != "" else (str(count) if count < 10 else "9+"))
	b.name = "Badge"
	target.add_child(b)
	b.position = Vector2(maxf(target.custom_minimum_size.x, target.size.x) - b.size.x + 3, -5)
	return b


## Modal popup: dims the screen and shows a titled panel with `body` and a row of
## buttons ([text, callable, yellow?]...). Any button closes it first. Returns the dimmer.
static func popup(owner: Control, title: String, body: Control, buttons: Array = []) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 40
	owner.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var p := RetroPanel.new(title, UiSkin.PANEL, 6)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	col.add_child(body)
	if not buttons.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		for spec in buttons:
			var cb: Callable = spec[1]
			var w := maxf(70.0, PixelFont.text_width(spec[0]) + 18.0)
			var close := func() -> void:
				dim.queue_free()
				if cb.is_valid():
					cb.call()
			var b := yellow(spec[0], Vector2(w, 24), close) if spec.size() > 2 and spec[2] else button(spec[0], Vector2(w, 24), close)
			row.add_child(b)
	p.modulate.a = 0.0
	p.scale = Vector2(0.85, 0.85)
	var appear := func() -> void:
		p.pivot_offset = p.size * 0.5
		var tw := p.create_tween().set_parallel()
		tw.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 1.0, 0.12)
	appear.call_deferred()
	return dim


## Message that drops in under the header and fades away.
static func toast(owner: Control, text: String, color := UiSkin.YELLOW, seconds := 1.8) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.12, 0.92)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	l.add_theme_stylebox_override("normal", sb)
	l.z_index = 45
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(l)
	l.reset_size()
	var w := owner.get_viewport_rect().size.x
	l.position = Vector2(roundf((w - l.size.x) * 0.5), 10)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", 34.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


## Removes every child of `c` immediately.
static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


## Offense / defense star values for a lineup-entries dictionary (slot -> {ovr}).
static func side_stars(entries: Dictionary) -> Dictionary:
	var o := 0.0
	var on := 0
	var d := 0.0
	var dn := 0
	for slot in entries:
		var ovr := float(entries[slot].get("ovr", 60))
		if slot in TeamRating.OFFENSE_SLOTS:
			o += ovr
			on += 1
		elif slot in TeamRating.DEFENSE_SLOTS:
			d += ovr
			dn += 1
	var off_ovr := o / maxi(on, 1) if on > 0 else 60.0
	var def_ovr := d / maxi(dn, 1) if dn > 0 else 60.0
	return {"off": UiSkin.ovr_stars(off_ovr), "def": UiSkin.ovr_stars(def_ovr), "off_ovr": off_ovr, "def_ovr": def_ovr}
