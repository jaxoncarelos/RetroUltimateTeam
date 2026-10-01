class_name MatchHUD
extends CanvasLayer
## In-game HUD, Retro Bowl style: a slim black top bar ("KC 0  PHI 0" | "1ST QTR 0:51" +
## pause | "1ST & 10"), a slim bottom bar with the controlled player ("P.MAHOMES [QB]") and
## the gesture hint, dark name-tag pills above your receivers before the snap, a compact
## CHANGE PLAY panel (opens the playbook grid), the quick play bar (top calls + BEST tag +
## MORE), PUNT / FG / TIMEOUT pills, outlined result banners, coach tips, choice panels
## (PAT, pause, final) and the kick meter. On defense: a big SWITCH button (bottom right)
## and a yellow name pill over the defender you control.

signal play_selected(play: PlayDef)
signal restart_pressed
## PUNT / FG / TIMEOUT buttons (by name).
signal special_pressed(action: String)
signal pause_pressed
## The SWITCH button (defense): take the defender nearest the ball.
signal switch_pressed
## A choice panel option was picked (index into the options passed to show_choice).
signal choice_made(index: int)
signal tip_closed

const WARN_COLOR := Color("#ff004d")
const BAR_SIZE := 4
const BAR_H := 14
const SWITCH_SIZE := Vector2(78, 46)
const XF_COLOR := Color("#ff2b6e")   ## X-Factor abilities (CardRules.PROGRAM_COLORS["xf"])

## Set by the match: name tags read the agents' positions from it (optional).
var runner: PlayRunner

var _all_plays: Array[PlayDef] = []
var _bar_plays: Array[PlayDef] = []
var _best: PlayDef
var _selected: PlayDef
var _keyed_id := ""
var _grid: PanelContainer
var _grid_rows: VBoxContainer
var _grid_buttons: Dictionary = {}

var _root: Control
var _top: _TopBar
var _bottom: _BottomBar
var _tags: _NameTags
var _replay_fx: _ReplayFx
var _change: Button
var _specials: VBoxContainer
var _pause: Button
var _choice: RetroPanel
var _choice_title: Label
var _choice_body: Label
var _choice_buttons: VBoxContainer
var _choice_dim: ColorRect
var kick_meter: KickMeter

var _banner: _Banner
var _warning: Label
var _xf_box: VBoxContainer          ## X-Factor ability chips (top left)
var _xf_toast: Label                ## "X-FACTOR ON" pop-up
var _xf_queue: Array = []
var _flash: ColorRect
var _tip: RetroPanel
var _tip_label: Label
var _play_bar: HBoxContainer
var _restart: Button
var _switch: Button
var _buttons: Dictionary = {}


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_tags = _NameTags.new()
	_tags.hud = self
	_tags.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_tags)

	_top = _TopBar.new()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.offset_bottom = BAR_H
	_top.pad_l = SafeArea.left()
	_top.pad_r = SafeArea.right()
	_root.add_child(_top)
	_bottom = _BottomBar.new()
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_top = -BAR_H
	_bottom.pad_l = SafeArea.left()
	_bottom.pad_r = SafeArea.right()
	_root.add_child(_bottom)

	_banner = _Banner.new()
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_banner)

	_replay_fx = _ReplayFx.new()
	_replay_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_replay_fx)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_warning = Label.new()
	_anchor(_warning, Vector2(0.5, 0.0), Rect2(-100, BAR_H + 3, 200, 12))
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warning.add_theme_color_override("font_color", Color.WHITE)
	var warn_box := StyleBoxFlat.new()
	warn_box.bg_color = Color(WARN_COLOR, 0.9)
	warn_box.set_corner_radius_all(2)
	warn_box.set_content_margin_all(2)
	_warning.add_theme_stylebox_override("normal", warn_box)
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.visible = false
	_root.add_child(_warning)

	_xf_box = VBoxContainer.new()
	_xf_box.add_theme_constant_override("separation", 1)
	_xf_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_xf_box, Vector2(0.0, 0.0), Rect2(4 + SafeArea.left(), BAR_H + 3, 150, 60))
	_root.add_child(_xf_box)
	_xf_toast = Label.new()
	_anchor(_xf_toast, Vector2(0.5, 0.0), Rect2(-130, 46, 260, 30))
	_xf_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xf_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xf_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var xf_bg := StyleBoxFlat.new()
	xf_bg.bg_color = Color(0.08, 0.02, 0.1, 0.92)
	xf_bg.border_color = XF_COLOR
	xf_bg.set_border_width_all(2)
	xf_bg.set_content_margin_all(4)
	_xf_toast.add_theme_stylebox_override("normal", xf_bg)
	_xf_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xf_toast.visible = false
	_root.add_child(_xf_toast)

	# Compact CHANGE PLAY panel (top right, under the bar) + special teams pills below.
	_change = Button.new()
	_change.theme_type_variation = "PillButton"
	_change.focus_mode = Control.FOCUS_NONE
	_anchor(_change, Vector2(1.0, 0.0), Rect2(-104 - SafeArea.right(), BAR_H + 3, 100, 26))
	_change.pressed.connect(func() -> void: _grid.visible = not _grid.visible)
	_change.visible = false
	_root.add_child(_change)
	_specials = VBoxContainer.new()
	_specials.add_theme_constant_override("separation", 3)
	_anchor(_specials, Vector2(1.0, 0.0), Rect2(-104 - SafeArea.right(), BAR_H + 33, 100, 80))
	_root.add_child(_specials)

	_play_bar = HBoxContainer.new()
	_play_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_bar.add_theme_constant_override("separation", 3)
	_root.add_child(_play_bar)

	_grid = PanelContainer.new()
	_grid.theme_type_variation = "PillPanel"
	_anchor(_grid, Vector2(0.5, 0.5), Rect2(-230, -104, 460, 150))
	_grid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_grid.grow_vertical = Control.GROW_DIRECTION_BOTH
	_grid.visible = false
	_root.add_child(_grid)
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
	close.theme_type_variation = "PillButton"
	close.custom_minimum_size = Vector2(48, 18)
	close.pressed.connect(func() -> void: _grid.visible = false)
	grid_head.add_child(close)
	_grid_rows = VBoxContainer.new()
	_grid_rows.add_theme_constant_override("separation", 2)
	grid_box.add_child(_grid_rows)

	# Pause: an icon in the middle of the top bar with a generous invisible hit box.
	_pause = Button.new()
	_pause.flat = true
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.set_meta("no_juice", true)
	_anchor(_pause, Vector2(0.5, 0.0), Rect2(34, 0, 26, 22))
	_pause.pressed.connect(func() -> void:
		Sfx.play("tap")
		pause_pressed.emit())
	_pause.visible = false
	_pause.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_pause.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_pause.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	_root.add_child(_pause)

	kick_meter = KickMeter.new()
	kick_meter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(kick_meter)

	_tip = RetroPanel.new("COACH SAYS", UiSkin.PANEL, 6)
	_anchor(_tip, Vector2(0.5, 0.0), Rect2(-150, 34, 300, 60))
	_tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip.visible = false
	_root.add_child(_tip)
	var tip_box := VBoxContainer.new()
	tip_box.add_theme_constant_override("separation", 5)
	_tip.add_child(tip_box)
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(286, 0)
	tip_box.add_child(_tip_label)
	var ok := MetaUI.yellow("GOT IT", Vector2(80, 22), func() -> void:
		_tip.visible = false
		tip_closed.emit())
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tip_box.add_child(ok)

	_choice_dim = ColorRect.new()
	_choice_dim.color = Color(0.0, 0.01, 0.06, 0.55)
	_choice_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_dim.visible = false
	_root.add_child(_choice_dim)
	_choice = RetroPanel.new("", UiSkin.PANEL, 7)
	_anchor(_choice, Vector2(0.5, 0.5), Rect2(-110, -70, 220, 140))
	_choice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choice.grow_vertical = Control.GROW_DIRECTION_BOTH
	_choice.visible = false
	_root.add_child(_choice)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 5)
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
	_choice_buttons.add_theme_constant_override("separation", 4)
	cbox.add_child(_choice_buttons)

	# SWITCH: big and thumb-sized in the bottom-right corner (moved up over the play bar
	# while calling a play so the two never overlap).
	_switch = Button.new()
	_switch.text = "SWITCH"
	_switch.theme_type_variation = "PillButton"
	_switch.focus_mode = Control.FOCUS_NONE
	_switch.add_theme_font_size_override("font_size", 16)
	_switch.add_theme_color_override("font_color", UiSkin.YELLOW)
	var sw_box := StyleBoxFlat.new()
	sw_box.bg_color = Color(0.03, 0.04, 0.08, 0.82)
	sw_box.border_color = UiSkin.YELLOW
	sw_box.set_border_width_all(2)
	sw_box.set_corner_radius_all(6)
	for st in ["normal", "hover", "focus"]:
		_switch.add_theme_stylebox_override(st, sw_box)
	var sw_press := sw_box.duplicate() as StyleBoxFlat
	sw_press.bg_color = Color(UiSkin.YELLOW, 0.35)
	_switch.add_theme_stylebox_override("pressed", sw_press)
	_anchor(_switch, Vector2(1.0, 1.0), Rect2(-SWITCH_SIZE.x - 6 - SafeArea.right(), -SWITCH_SIZE.y - BAR_H - 6, SWITCH_SIZE.x, SWITCH_SIZE.y))
	_switch.pressed.connect(func() -> void:
		Sfx.play("tap")
		switch_pressed.emit())
	_switch.visible = false
	_root.add_child(_switch)

	_restart = MetaUI.yellow("NEW DRIVE", Vector2(96, 24), func() -> void: restart_pressed.emit())
	_anchor(_restart, Vector2(0.5, 0.5), Rect2(-48, 10, 96, 24))
	_restart.visible = false
	_root.add_child(_restart)


static func _anchor(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y


# ---------------------------------------------------------------- play calling

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
		_buttons[p].set_pressed_no_signal(p == play)
	for p in _grid_buttons:
		_grid_buttons[p].set_pressed_no_signal(p == play)
	if play != null:
		_change.text = "CHANGE PLAY ▼\n%s" % play.display_name.to_upper().left(15)


## Warns that the CPU defense is keying on a play and marks that play's card ("" clears).
func set_keyed(_plays: Array[PlayDef], keyed_id: String) -> void:
	_keyed_id = keyed_id
	var keyed_name := ""
	for p in _all_plays:
		if p.id == keyed_id:
			keyed_name = p.display_name.to_upper()
	_refresh_card_texts()
	_warning.text = " DEFENSE IS KEYING ON %s " % keyed_name
	_warning.visible = keyed_name != ""


## Buttons like "PUNT", "FG 42", "TIMEOUT 2" (the text before the first space is the action).
func set_special_actions(actions: Array[String]) -> void:
	for c in _specials.get_children():
		_specials.remove_child(c)
		c.queue_free()
	for a in actions:
		var b := Button.new()
		b.text = a
		b.theme_type_variation = "PillButton"
		b.custom_minimum_size = Vector2(100, 22)
		b.focus_mode = Control.FOCUS_NONE
		if a.begins_with("FG") or a.begins_with("PUNT"):
			b.add_theme_color_override("font_color", UiSkin.YELLOW)
		var action := a.get_slice(" ", 0)
		b.pressed.connect(func() -> void: special_pressed.emit(action))
		_specials.add_child(b)


func show_pause_button(on: bool) -> void:
	_pause.visible = on
	_top.show_pause = on
	_top.queue_redraw()


## Modal panel with a title, body text and one button per option (choice_made(index)).
func show_choice(title: String, body: String, options: Array[String]) -> void:
	_choice_title.text = title
	_choice_body.text = body
	_choice_body.visible = body != ""
	for c in _choice_buttons.get_children():
		_choice_buttons.remove_child(c)
		c.queue_free()
	for i in options.size():
		var idx := i
		var cb := func() -> void:
			_choice.visible = false
			_choice_dim.visible = false
			choice_made.emit(idx)
		var b := MetaUI.yellow(options[i], Vector2(180, 24), cb) if i == 0 else MetaUI.button(options[i], Vector2(180, 24), cb)
		_choice_buttons.add_child(b)
	_choice.visible = true
	_choice_dim.visible = true
	_choice.reset_size.call_deferred()
	_choice.scale = Vector2(0.85, 0.85)
	(func() -> void:
		_choice.pivot_offset = _choice.size * 0.5
		_choice.create_tween().tween_property(_choice, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	).call_deferred()


func hide_choice() -> void:
	_choice.visible = false
	_choice_dim.visible = false


func is_choice_open() -> bool:
	return _choice.visible


func show_playbook_grid(on: bool) -> void:
	_grid.visible = on


func show_play_bar(on: bool) -> void:
	_play_bar.visible = on
	_change.visible = on
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
	b.theme_type_variation = "PillButton"
	b.set_meta("compact", compact)
	b.custom_minimum_size = size
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
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
		var b := _make_card(p, Vector2(80, 28))
		b.set_pressed_no_signal(p == _selected)
		_play_bar.add_child(b)
		_buttons[p] = b
		if p == _best:
			var tag := Label.new()
			tag.text = "BEST"
			tag.add_theme_color_override("font_color", UiSkin.NAVY_DEEP)
			tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiTheme.ACCENT
			sb.set_corner_radius_all(2)
			sb.content_margin_left = 2
			sb.content_margin_right = 1
			sb.content_margin_top = 1
			sb.content_margin_bottom = 0
			tag.add_theme_stylebox_override("normal", sb)
			tag.position = Vector2(2, -9)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tag)
	var more := Button.new()
	more.text = "MORE\n..."
	more.theme_type_variation = "PillButton"
	more.focus_mode = Control.FOCUS_NONE
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
			b.set_pressed_no_signal(p == _selected)
			row.add_child(b)
			_grid_buttons[p] = b
		_grid_rows.add_child(row)
	_grid.reset_size.call_deferred()


func show_restart(on: bool) -> void:
	_restart.visible = on


## The defense SWITCH button (pre-snap and live defensive snaps only).
func show_switch(on: bool) -> void:
	_switch.visible = on


func is_switch_visible() -> bool:
	return _switch.visible


# ---------------------------------------------------------------- bars / tags / banners

## Back-compat (drive sandbox): free text for the top bar's left and right.
func set_scorebug(down_text: String, drive_text: String) -> void:
	_top.left = drive_text
	_top.right = down_text
	_top.center = ""
	_top.queue_redraw()


## Full game: {"home", "away", "home_score", "away_score", "possession", "quarter": "1ST QTR",
## "clock": "0:51", "down": "1ST & 10"}.
func set_score_bar(d: Dictionary) -> void:
	_top.data = d
	_top.left = ""
	_top.queue_redraw()


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
	_bottom.tag = text
	_bottom.queue_redraw()


func set_hint(text: String) -> void:
	_bottom.hint = text
	_bottom.queue_redraw()


func show_replay(on: bool) -> void:
	_replay_fx.visible = on


## X-Factor chips: rows [{text, on}] (on = glowing, else progress in grey). [] hides them.
func set_abilities(rows: Array) -> void:
	for c in _xf_box.get_children():
		_xf_box.remove_child(c)
		c.queue_free()
	for r in rows:
		var l := Label.new()
		l.text = ("⚡ " if r["on"] else "") + str(r["text"])
		l.add_theme_color_override("font_color", Color.WHITE if r["on"] else UiTheme.DIM)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(XF_COLOR, 0.85) if r["on"] else Color(0.05, 0.05, 0.12, 0.7)
		bg.set_content_margin_all(1)
		bg.content_margin_left = 3
		bg.content_margin_right = 3
		l.add_theme_stylebox_override("normal", bg)
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_xf_box.add_child(l)


## Big pop-up when an X-Factor ability switches on (queued if one is already showing).
func show_ability(player: String, ability: String, text: String) -> void:
	_xf_queue.append("X-FACTOR!  %s: %s\n%s" % [player, ability, text])
	if not _xf_toast.visible:
		_next_ability()


func _next_ability() -> void:
	if _xf_queue.is_empty():
		_xf_toast.visible = false
		return
	_xf_toast.text = str(_xf_queue.pop_front())
	_xf_toast.visible = true
	_xf_toast.modulate.a = 1.0
	_xf_toast.pivot_offset = _xf_toast.size * 0.5
	_xf_toast.scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(_xf_toast, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.2)
	tw.tween_property(_xf_toast, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_next_ability)


func show_banner(text: String, sub := "", seconds := 1.6) -> void:
	_banner.show_text(text, sub, seconds)


func _process(_delta: float) -> void:
	if _warning.visible:
		_warning.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	var vp := get_viewport().get_visible_rect().size
	_play_bar.position.x = roundf((vp.x - _play_bar.size.x) * 0.5)
	_play_bar.position.y = vp.y - _play_bar.size.y - BAR_H - 3
	# SWITCH sits in the corner, lifted above the play bar while the bar is up.
	var lift := _play_bar.size.y + 6.0 if _play_bar.visible else 0.0
	_switch.offset_top = -SWITCH_SIZE.y - BAR_H - 6 - lift
	_switch.offset_bottom = -BAR_H - 6 - lift
	_tags.visible = runner != null
	if _tags.visible:
		_tags.queue_redraw()


## True when a viewport point lies over an interactive HUD control.
func is_point_over_ui(p: Vector2) -> bool:
	if _restart.visible and _restart.get_global_rect().has_point(p):
		return true
	if _switch.visible and _switch.get_global_rect().grow(4).has_point(p):
		return true
	if _grid.visible or _choice.visible or _tip.visible:
		return true   # the playbook grid, choice panels and coach tips are modal
	if _pause.visible and _pause.get_global_rect().has_point(p):
		return true
	if _change.visible and _change.get_global_rect().has_point(p):
		return true
	for b in _specials.get_children():
		if b is Control and b.visible and b.get_global_rect().has_point(p):
			return true
	if _play_bar.visible:
		for b in _play_bar.get_children():
			if b is Control and b.get_global_rect().has_point(p):
				return true
	return false


# ---------------------------------------------------------------- drawn pieces

## Slim black top bar: score left, quarter + clock + pause center, down & distance right.
class _TopBar:
	extends Control
	var data: Dictionary = {}
	var left := ""
	var center := ""
	var right := ""
	var show_pause := false
	var pad_l := 0.0   ## safe-area insets: text stays clear of rounded corners
	var pad_r := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.88))
		draw_rect(Rect2(0, size.y, size.x, 1), Color(0, 0, 0, 0.35))
		var y := 11.0
		if not data.is_empty():
			var x := 3.0 + pad_l
			for side in ["home", "away"]:
				var abbr: String = data.get(side, "")
				var sc := str(data.get(side + "_score", 0))
				var has_ball: bool = data.get("possession", "") == abbr
				# Score chip in the team's color so both sides read at a glance.
				var col: Color = data.get(side + "_color", Color("#30364a"))
				var chip_w := PixelFont.text_width(abbr) + PixelFont.text_width(sc) + 15.0 + (11.0 if has_ball else 0.0)
				draw_rect(Rect2(x - 1, 1, chip_w + 2, size.y - 2), Color(0, 0, 0, 0.9))
				draw_rect(Rect2(x, 2, chip_w, size.y - 4), col.darkened(0.15))
				draw_rect(Rect2(x, 2, chip_w, 1), col.lightened(0.3))
				var tx := x + 3.0
				if has_ball:
					UiSkin.draw_icon(self, "ball", Vector2(tx, 3), Color("#c8793a"), 1.0, false)
					tx += 11.0
				UiSkin.draw_text(self, Vector2(tx, y), abbr, 8, UiSkin.YELLOW if has_ball else Color.WHITE)
				tx += PixelFont.text_width(abbr) + 5
				UiSkin.draw_text(self, Vector2(tx, y), sc, 8, Color.WHITE)
				x += chip_w + 6.0
			var q: String = data.get("quarter", "")
			var clk: String = data.get("clock", "")
			var qw := PixelFont.text_width(q + " ")
			var cw := PixelFont.text_width(clk)
			var cx := size.x * 0.5 - (qw + cw) * 0.5
			UiSkin.draw_text(self, Vector2(cx, y), q, 8, Color.WHITE)
			UiSkin.draw_text(self, Vector2(cx + qw, y), clk, 8, UiSkin.YELLOW)
			var dn: String = data.get("down", "")
			UiSkin.draw_text(self, Vector2(size.x - 5 - pad_r - PixelFont.text_width(dn), y), dn, 8, Color.WHITE)
		else:
			UiSkin.draw_text(self, Vector2(4 + pad_l, y), left, 8, Color.WHITE)
			UiSkin.draw_text(self, Vector2(size.x - 5 - pad_r - PixelFont.text_width(right), y), right, 8, UiSkin.YELLOW)
		if show_pause:
			var px := size.x * 0.5 + 44
			draw_rect(Rect2(px, 3, 2, 8), Color.WHITE)
			draw_rect(Rect2(px + 4, 3, 2, 8), Color.WHITE)


## Slim black bottom bar: controlled player "P.MAHOMES [QB]" left, gesture hint right.
class _BottomBar:
	extends Control
	var tag := ""
	var hint := ""
	var pad_l := 0.0
	var pad_r := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if tag == "" and hint == "":
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8))
		var x := 4.0 + pad_l
		if tag != "":
			UiSkin.draw_icon(self, "face", Vector2(x, 3), UiSkin.YELLOW, 1.0, false)
			x += 11.0
			UiSkin.draw_text(self, Vector2(x, 11), tag, 8, Color.WHITE)
			x += PixelFont.text_width(tag) + 12
		if hint != "":
			var h := fit_hint(hint, size.x - 5 - pad_r - x)
			var w := PixelFont.text_width(h)
			UiSkin.draw_text(self, Vector2(maxf(x, size.x - 5 - pad_r - w), 11), h, 8, Color(1, 1, 1, 0.78))

	## Drops trailing "  ·  " parts of a hint until it fits `room` px (never runs off screen).
	static func fit_hint(text: String, room: float) -> String:
		var h := text
		while PixelFont.text_width(h) > room and h.contains("  ·  "):
			h = h.substr(0, h.rfind("  ·  "))
		return h


## Dark name-tag pills above your receivers before the snap (Retro Bowl "J.P" tags).
class _NameTags:
	extends Control
	var hud: MatchHUD

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r: PlayRunner = hud.runner
		if r == null or not is_instance_valid(r):
			return
		if r.human_team == PlayerAgent.Team.DEFENSE:
			_draw_defender(r)
			return
		if r.human_team != PlayerAgent.Team.OFFENSE or not hud._play_bar.visible:
			return
		for a in r.offense:
			if not is_instance_valid(a) or not a.is_eligible() or a == r.qb:
				continue
			var at := a.get_global_transform_with_canvas().origin
			var t := _short(a.display_name)
			var w := PixelFont.text_width(t) + 6
			var box := Rect2(roundf(at.x - w * 0.5), roundf(at.y - 30), w, 10)
			draw_rect(box, Color(0.03, 0.04, 0.06, 0.85))
			draw_rect(Rect2(box.position.x + 1, box.end.y, box.size.x - 2, 1), Color(0.03, 0.04, 0.06, 0.6))
			UiSkin.draw_text(self, box.position + Vector2(3, 8), t, 8, Color.WHITE)

	## Yellow pill "#54 F.WARNER" with a little pointer over the defender you control.
	func _draw_defender(r: PlayRunner) -> void:
		var a := r.controlled
		if a == null or not is_instance_valid(a) or r.phase not in [PlayRunner.Phase.PRE_SNAP, PlayRunner.Phase.LIVE]:
			return
		if a == r.carrier:
			return   # returning an interception: the carrier arrow marks him
		var at := a.get_global_transform_with_canvas().origin
		var t := "#%d %s" % [a.jersey, _short(a.display_name)] if a.jersey > 0 else _short(a.display_name)
		var w := PixelFont.text_width(t) + 6
		var box := Rect2(roundf(at.x - w * 0.5), roundf(at.y - 40 + a.z_height * -6.0), w, 10)
		draw_rect(box.grow(1), Color(0.03, 0.04, 0.06, 0.9))
		draw_rect(box, UiSkin.YELLOW)
		var tip := Vector2(roundf(at.x), box.end.y + 4)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-3, -4), tip + Vector2(3, -4)]), UiSkin.YELLOW)
		UiSkin.draw_text(self, box.position + Vector2(3, 8), t, 8, Color(0.03, 0.04, 0.06), Color(0, 0, 0, 0))

	static func _short(n: String) -> String:
		return n.to_upper().replace(". ", ".")


## Result banner: a dark band slides in with big outlined text (+ sub line), then fades.
class _Banner:
	extends Control
	var text := ""
	var sub := ""
	var _time := 0.0
	var _left := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_text(t: String, s: String, seconds: float) -> void:
		text = t
		sub = s
		_time = 0.0
		_left = seconds
		visible = true
		queue_redraw()

	func _process(delta: float) -> void:
		if _left <= 0.0:
			return
		_time += delta
		_left -= delta
		if _left <= 0.0:
			text = ""
		queue_redraw()

	func _draw() -> void:
		if text == "":
			return
		var appear := clampf(_time / 0.18, 0.0, 1.0)
		var fade := clampf(_left / 0.25, 0.0, 1.0)
		var a := appear * fade
		var y := 70.0
		var band_h := 30.0 if sub != "" else 22.0
		var w := size.x * (0.2 + 0.8 * appear)
		draw_rect(Rect2((size.x - w) * 0.5, y - 18, w, band_h), Color(0, 0, 0, 0.55 * a))
		draw_rect(Rect2((size.x - w) * 0.5, y - 18, w, 1), Color(UiSkin.YELLOW, 0.8 * a))
		draw_rect(Rect2((size.x - w) * 0.5, y - 19 + band_h, w, 1), Color(UiSkin.YELLOW, 0.8 * a))
		var slide := (1.0 - appear) * 40.0
		UiSkin.draw_text_c(self, size.x * 0.5 + slide, y - 2, text, 16, Color(UiSkin.YELLOW, a), Color(UiSkin.SHADOW, a),
				Color(0, 0, 0, 0.6 * a))
		if sub != "":
			UiSkin.draw_text_c(self, size.x * 0.5 - slide, y + 9, sub, 8, Color(1, 1, 1, a), Color(0, 0, 0, 0),
					Color(0, 0, 0, 0.6 * a))


## INSTANT REPLAY overlay: warm tint, letterbox bars, a blinking tag and a skip hint.
class _ReplayFx:
	extends Control
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.55, 0.10))
		draw_rect(Rect2(0, 0, size.x, 16), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(0, size.y - 16, size.x, 16), Color(0, 0, 0, 0.85))
		var on := int(_t * 2.0) % 2 == 0
		if on:
			draw_circle(Vector2(8 + SafeArea.left(), 8), 3.0, Color("#ff2e57"))
		UiSkin.draw_text(self, Vector2(16 + SafeArea.left(), 11), "INSTANT REPLAY", 8, Color.WHITE)
		var hint := "TAP TO SKIP"
		UiSkin.draw_text(self, Vector2(size.x - 8 - SafeArea.right() - PixelFont.text_width(hint), size.y - 5), hint, 8,
				Color(1, 1, 1, 0.75))
