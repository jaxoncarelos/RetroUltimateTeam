class_name MatchHUD
extends CanvasLayer
## Scorebug, result banners, gesture hints and the play-call strip.

signal play_selected(play: PlayDef)
signal restart_pressed

var _down_label: Label
var _drive_label: Label
var _banner: Label
var _banner_sub: Label
var _hint: Label
var _play_bar: HBoxContainer
var _restart: Button
var _buttons: Dictionary = {}
var _banner_timer := 0.0


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bug := PanelContainer.new()
	bug.position = Vector2(4, 4)
	bug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bug)
	var bug_box := VBoxContainer.new()
	bug_box.add_theme_constant_override("separation", 1)
	bug.add_child(bug_box)
	_down_label = Label.new()
	_down_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	bug_box.add_child(_down_label)
	_drive_label = Label.new()
	bug_box.add_child(_drive_label)

	_banner = Label.new()
	_anchor(_banner, Vector2(0.5, 0.0), Rect2(-200, 64, 400, 20))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 16)
	_banner.add_theme_color_override("font_color", UiTheme.ACCENT)
	_banner.add_theme_constant_override("shadow_offset_x", 2)
	_banner.add_theme_constant_override("shadow_offset_y", 2)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)
	_banner_sub = Label.new()
	_anchor(_banner_sub, Vector2(0.5, 0.0), Rect2(-200, 88, 400, 10))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner_sub)

	_hint = Label.new()
	_anchor(_hint, Vector2(0.5, 1.0), Rect2(-240, -46, 480, 10))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)

	_play_bar = HBoxContainer.new()
	_play_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_bar.add_theme_constant_override("separation", 3)
	root.add_child(_play_bar)

	_restart = Button.new()
	_restart.text = "NEW DRIVE"
	_anchor(_restart, Vector2(0.5, 0.5), Rect2(-48, 10, 96, 24))
	_restart.visible = false
	_restart.pressed.connect(func() -> void: restart_pressed.emit())
	root.add_child(_restart)


static func _anchor(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y


func set_playbook(plays: Array[PlayDef]) -> void:
	for c in _play_bar.get_children():
		c.queue_free()
	_buttons.clear()
	for p in plays:
		var b := Button.new()
		b.text = "%s\n%s" % [p.display_name.to_upper(), p.category]
		b.custom_minimum_size = Vector2(62, 24)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: play_selected.emit(p))
		_play_bar.add_child(b)
		_buttons[p] = b
	# Re-center after the container sizes itself.
	_play_bar.reset_size.call_deferred()


func set_selected(play: PlayDef) -> void:
	for p in _buttons:
		_buttons[p].button_pressed = p == play


func show_play_bar(on: bool) -> void:
	_play_bar.visible = on


func show_restart(on: bool) -> void:
	_restart.visible = on


func set_scorebug(down_text: String, drive_text: String) -> void:
	_down_label.text = down_text
	_drive_label.text = drive_text


func set_hint(text: String) -> void:
	_hint.text = text


func show_banner(text: String, sub := "", seconds := 1.6) -> void:
	_banner.text = text
	_banner_sub.text = sub
	_banner.visible = true
	_banner_sub.visible = sub != ""
	_banner_timer = seconds


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner.visible = false
			_banner_sub.visible = false
	_play_bar.position.x = (get_viewport().get_visible_rect().size.x - _play_bar.size.x) * 0.5
	_play_bar.position.y = get_viewport().get_visible_rect().size.y - _play_bar.size.y - 4


## True when a viewport point lies over an interactive HUD control.
func is_point_over_ui(p: Vector2) -> bool:
	if _restart.visible and _restart.get_global_rect().has_point(p):
		return true
	if _play_bar.visible:
		for b in _play_bar.get_children():
			if b is Control and b.get_global_rect().has_point(p):
				return true
	return false
