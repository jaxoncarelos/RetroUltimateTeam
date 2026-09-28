class_name MatchHUD
extends CanvasLayer
## Scorebug, result banners, gesture hints and the play-call strip.

signal play_selected(play: PlayDef)
signal restart_pressed
## PUNT / FG / TIMEOUT buttons (by name).
signal special_pressed(action: String)
signal pause_pressed
## A choice panel option was picked (index into the options passed to show_choice).
signal choice_made(index: int)
signal tip_closed

const WARN_COLOR := Color("#ff004d")
const BAR_SIZE := 4

var _all_plays: Array[PlayDef] = []
var _bar_plays: Array[PlayDef] = []
var _best: PlayDef
var _selected: PlayDef
var _keyed_id := ""
var _grid: PanelContainer
var _grid_rows: VBoxContainer
var _grid_buttons: Dictionary = {}

var _specials: HBoxContainer
var _pause: Button
var _choice: PanelContainer
var _choice_title: Label
var _choice_body: Label
var _choice_buttons: VBoxContainer
var kick_meter: KickMeter

var _down_label: Label
var _drive_label: Label
var _banner: Label
var _banner_sub: Label
var _hint: Label
var _warning: Label
var _tag: Label
var _flash: ColorRect
var _tip: PanelContainer
var _tip_label: Label
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
	_anchor(_hint, Vector2(0.5, 1.0), Rect2(-240, -56, 480, 10))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	_tip = PanelContainer.new()
	_anchor(_tip, Vector2(0.5, 0.0), Rect2(-150, 40, 300, 60))
	_tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip.visible = false
	root.add_child(_tip)
	var tip_box := VBoxContainer.new()
	tip_box.add_theme_constant_override("separation", 4)
	_tip.add_child(tip_box)
	var coach := Label.new()
	coach.text = "COACH SAYS:"
	coach.add_theme_color_override("font_color", UiTheme.ACCENT)
	tip_box.add_child(coach)
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(290, 0)
	tip_box.add_child(_tip_label)
	var ok := Button.new()
	ok.text = "GOT IT"
	ok.custom_minimum_size = Vector2(80, 20)
	ok.pressed.connect(func() -> void:
		_tip.visible = false
		tip_closed.emit())
	tip_box.add_child(ok)

	_tag = Label.new()
	_anchor(_tag, Vector2(0.0, 1.0), Rect2(6, -68, 220, 10))
	_tag.add_theme_color_override("font_color", Color("#ffec27"))
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	root.add_child(_tag)

	_warning = Label.new()
	_anchor(_warning, Vector2(0.5, 0.0), Rect2(-80, 30, 160, 12))
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warning.add_theme_color_override("font_color", WARN_COLOR)
	var warn_box := StyleBoxFlat.new()
	warn_box.bg_color = Color(UiTheme.INK, 0.9)
	warn_box.border_color = WARN_COLOR
	warn_box.set_border_width_all(1)
	warn_box.set_content_margin_all(2)
	_warning.add_theme_stylebox_override("normal", warn_box)
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.visible = false
	root.add_child(_warning)

	_play_bar = HBoxContainer.new()
	_play_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_bar.add_theme_constant_override("separation", 3)
	root.add_child(_play_bar)

	_grid = PanelContainer.new()
	_anchor(_grid, Vector2(0.5, 0.5), Rect2(-230, -100, 460, 150))
	_grid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_grid.grow_vertical = Control.GROW_DIRECTION_BOTH
	_grid.visible = false
	root.add_child(_grid)
	var grid_box := VBoxContainer.new()
	grid_box.add_theme_constant_override("separation", 3)
	_grid.add_child(grid_box)
	var grid_head := HBoxContainer.new()
	grid_box.add_child(grid_head)
	var grid_title := Label.new()
	grid_title.text = "PLAYBOOK"
	grid_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	grid_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_head.add_child(grid_title)
	var close := Button.new()
	close.text = "BACK"
	close.custom_minimum_size = Vector2(44, 16)
	close.pressed.connect(func() -> void: _grid.visible = false)
	grid_head.add_child(close)
	_grid_rows = VBoxContainer.new()
	_grid_rows.add_theme_constant_override("separation", 2)
	grid_box.add_child(_grid_rows)

	# Special teams / timeout buttons (top right, under the pause button).
	_specials = HBoxContainer.new()
	_specials.add_theme_constant_override("separation", 3)
	_anchor(_specials, Vector2(1.0, 0.0), Rect2(-200, 26, 196, 26))
	_specials.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_specials)

	_pause = Button.new()
	_pause.text = "II"
	_pause.custom_minimum_size = Vector2(26, 20)
	_anchor(_pause, Vector2(1.0, 0.0), Rect2(-30, 4, 26, 20))
	_pause.pressed.connect(func() -> void: pause_pressed.emit())
	_pause.visible = false
	root.add_child(_pause)

	kick_meter = KickMeter.new()
	kick_meter.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(kick_meter)

	_choice = PanelContainer.new()
	_anchor(_choice, Vector2(0.5, 0.5), Rect2(-110, -70, 220, 140))
	_choice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choice.grow_vertical = Control.GROW_DIRECTION_BOTH
	_choice.visible = false
	root.add_child(_choice)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 4)
	_choice.add_child(cbox)
	_choice_title = Label.new()
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_choice_title.add_theme_font_size_override("font_size", 16)
	cbox.add_child(_choice_title)
	_choice_body = Label.new()
	_choice_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(_choice_body)
	_choice_buttons = VBoxContainer.new()
	_choice_buttons.add_theme_constant_override("separation", 3)
	cbox.add_child(_choice_buttons)

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


## Offers plays: the bar shows the top BAR_SIZE of `ranked` (first = "BEST", preselected
## by the caller) plus a MORE button that opens the full playbook grid of `all`.
func set_play_options(ranked: Array[PlayDef], all: Array[PlayDef]) -> void:
	_all_plays = all
	_best = ranked[0] if not ranked.is_empty() else null
	_bar_plays = ranked.slice(0, BAR_SIZE)
	_rebuild_bar()
	_rebuild_grid()


## Back-compat: every play on the bar, no ranking.
func set_playbook(plays: Array[PlayDef]) -> void:
	set_play_options(plays, plays)


func set_selected(play: PlayDef) -> void:
	_selected = play
	if play != null and play not in _bar_plays:
		# A pick from the grid replaces the last card so the call is always visible.
		if _bar_plays.size() >= BAR_SIZE:
			_bar_plays[BAR_SIZE - 1] = play
		else:
			_bar_plays.append(play)
		_rebuild_bar()
	for p in _buttons:
		_buttons[p].button_pressed = p == play
	for p in _grid_buttons:
		_grid_buttons[p].button_pressed = p == play


## Warns that the CPU defense is keying on a play and marks that play's card ("" clears).
func set_keyed(_plays: Array[PlayDef], keyed_id: String) -> void:
	_keyed_id = keyed_id
	var keyed_name := ""
	for p in _all_plays:
		if p.id == keyed_id:
			keyed_name = p.display_name.to_upper()
	_refresh_card_texts()
	_warning.text = "DEFENSE IS KEYING ON %s" % keyed_name
	_warning.visible = keyed_name != ""


## Buttons like "PUNT", "FG 42", "TIMEOUT 2" (the text before the first space is the action).
func set_special_actions(actions: Array[String]) -> void:
	for c in _specials.get_children():
		_specials.remove_child(c)
		c.queue_free()
	for a in actions:
		var b := Button.new()
		b.text = a
		b.custom_minimum_size = Vector2(44, 22)
		var action := a.get_slice(" ", 0)
		b.pressed.connect(func() -> void: special_pressed.emit(action))
		_specials.add_child(b)


func show_pause_button(on: bool) -> void:
	_pause.visible = on


## Modal panel with a title, body text and one button per option (choice_made(index)).
func show_choice(title: String, body: String, options: Array[String]) -> void:
	_choice_title.text = title
	_choice_body.text = body
	_choice_body.visible = body != ""
	for c in _choice_buttons.get_children():
		_choice_buttons.remove_child(c)
		c.queue_free()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.custom_minimum_size = Vector2(160, 24)
		var idx := i
		b.pressed.connect(func() -> void:
			_choice.visible = false
			choice_made.emit(idx))
		_choice_buttons.add_child(b)
	_choice.visible = true
	_choice.reset_size.call_deferred()


func hide_choice() -> void:
	_choice.visible = false


func is_choice_open() -> bool:
	return _choice.visible


func show_playbook_grid(on: bool) -> void:
	_grid.visible = on


func show_play_bar(on: bool) -> void:
	_play_bar.visible = on
	if not on:
		_grid.visible = false


## Compact cards (grid) show only the name; bar cards add the category.
func _style_card(b: Button, p: PlayDef) -> void:
	var name := ("! " if p.id == _keyed_id else "") + p.display_name.to_upper()
	# Second line: the category, or the formation when the name already says it.
	var sub := p.category
	if sub in name and p.formation != null:
		sub = p.formation.display_name.to_upper()
	b.text = name if b.get_meta("compact", false) else "%s\n%s" % [name, sub]
	b.add_theme_color_override("font_color", WARN_COLOR if p.id == _keyed_id else UiTheme.TEXT)


func _refresh_card_texts() -> void:
	for p in _buttons:
		_style_card(_buttons[p], p)
	for p in _grid_buttons:
		_style_card(_grid_buttons[p], p)


func _make_card(p: PlayDef, size: Vector2, compact := false) -> Button:
	var b := Button.new()
	b.set_meta("compact", compact)
	b.custom_minimum_size = size
	b.toggle_mode = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	_style_card(b, p)
	b.pressed.connect(func() -> void:
		_grid.visible = false
		play_selected.emit(p))
	return b


func _rebuild_bar() -> void:
	for c in _play_bar.get_children():
		_play_bar.remove_child(c)
		c.queue_free()
	_buttons.clear()
	for p in _bar_plays:
		var b := _make_card(p, Vector2(78, 28))
		b.button_pressed = p == _selected
		_play_bar.add_child(b)
		_buttons[p] = b
		if p == _best:
			var tag := Label.new()
			tag.text = "BEST"
			tag.add_theme_color_override("font_color", UiTheme.INK)
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiTheme.ACCENT
			sb.set_content_margin_all(1)
			tag.add_theme_stylebox_override("normal", sb)
			tag.position = Vector2(2, -10)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tag)
	var more := Button.new()
	more.text = "MORE\n..."
	more.custom_minimum_size = Vector2(40, 28)
	more.pressed.connect(func() -> void: _grid.visible = not _grid.visible)
	_play_bar.add_child(more)
	# Re-center after the container sizes itself.
	_play_bar.reset_size.call_deferred()


func _rebuild_grid() -> void:
	for c in _grid_rows.get_children():
		_grid_rows.remove_child(c)
		c.queue_free()
	_grid_buttons.clear()
	var cats: Array[String] = []
	for p in _all_plays:
		if p.category not in cats:
			cats.append(p.category)
	for cat in cats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var lbl := Label.new()
		lbl.text = cat
		lbl.custom_minimum_size = Vector2(34, 0)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", UiTheme.ACCENT)
		row.add_child(lbl)
		for p in _all_plays:
			if p.category != cat:
				continue
			var b := _make_card(p, Vector2(56, 28), true)
			b.button_pressed = p == _selected
			row.add_child(b)
			_grid_buttons[p] = b
		_grid_rows.add_child(row)
	_grid.reset_size.call_deferred()


func show_restart(on: bool) -> void:
	_restart.visible = on


func set_scorebug(down_text: String, drive_text: String) -> void:
	_down_label.text = down_text
	_drive_label.text = drive_text


## Full-screen color flash (touchdowns, turnovers).
func flash(color: Color, strength := 0.7) -> void:
	_flash.color = Color(color, strength)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.45)


## Coach tip panel (tutorial). Emits tip_closed when dismissed.
func show_tip(text: String) -> void:
	_tip_label.text = text
	_tip.visible = true
	_tip.reset_size.call_deferred()


func tip_open() -> bool:
	return _tip.visible


## Name/number of the player the human controls ("" hides it).
func set_player_tag(text: String) -> void:
	_tag.text = text
	_tag.visible = text != ""


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
	if _warning.visible:
		_warning.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	_play_bar.position.x = (get_viewport().get_visible_rect().size.x - _play_bar.size.x) * 0.5
	_play_bar.position.y = get_viewport().get_visible_rect().size.y - _play_bar.size.y - 4


## True when a viewport point lies over an interactive HUD control.
func is_point_over_ui(p: Vector2) -> bool:
	if _restart.visible and _restart.get_global_rect().has_point(p):
		return true
	if _grid.visible or _choice.visible or _tip.visible:
		return true   # the playbook grid, choice panels and coach tips are modal
	if _pause.visible and _pause.get_global_rect().has_point(p):
		return true
	for b in _specials.get_children():
		if b is Control and b.visible and b.get_global_rect().has_point(p):
			return true
	if _play_bar.visible:
		for b in _play_bar.get_children():
			if b is Control and b.get_global_rect().has_point(p):
				return true
	return false
