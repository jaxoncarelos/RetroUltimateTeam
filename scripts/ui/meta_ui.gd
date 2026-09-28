class_name MetaUI
extends RefCounted
## Shared builders for the meta screens (480x270 canvas, big touch targets).


## Full-screen dark background + a column with a header row (BACK button, title, coins).
## Returns {"root": VBoxContainer, "coins": Label, "title": Label}.
static func screen(owner: Control, title: String, back_to := "res://scenes/meta/hub.tscn") -> Dictionary:
	owner.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	owner.add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_right = -8
	root.offset_top = 6
	root.offset_bottom = -6
	root.add_theme_constant_override("separation", 5)
	owner.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	if back_to != "":
		head.add_child(button("< BACK", Vector2(56, 22), func() -> void: SceneRouter.goto(back_to)))
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var coins := Label.new()
	coins.text = "%d COINS" % SaveManager.profile.coins
	coins.add_theme_color_override("font_color", Color("#ffcf40"))
	head.add_child(coins)
	return {"root": root, "coins": coins, "title": t}


static func button(text: String, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.pressed.connect(cb)
	return b


static func label(text: String, color := UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l


## Scrollable area that fills the rest of the column.
static func scroll(parent: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	return sc
