class_name MatchHUD
extends CanvasLayer
## In-game HUD in the shared UiSkin pixel style (one palette, one 9-slice look):
##  - top centre: a compact scoreboard pill (away score | quarter + clock | home score, team
##    colour chips, ball icon) with down & distance + ball spot hanging under it;
##  - top left: a real 26 px pause button; top right: a small PUNT / FG / TIMEOUT stack;
##  - bottom: ONE play-call carousel (4 cards + MORE) in a container row that also reserves
##    the defense SWITCH slot, so nothing ever overlaps or needs per-frame offsets;
##  - MORE opens a category-tabbed playbook grid (the selected play is highlighted there);
##  - a slim bottom strip (controlled player + gesture hint), name tags, result banners,
##    coach tips, choice panels (PAT, pause, final) and the kick meter.
## Everything sits inside `_safe`, a Control inset by SafeArea (notch / rounded corners).

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
## Road to Glory pre-snap card button (by id: "snap", "ready", "audible", "hot").
signal rtg_action(id: String)

const WARN_COLOR := UiSkin.RED
const BAR_SIZE := 4
const BAR_H := 14          ## bottom strip height
const CARD_H := 32.0
const CARD_W := 70.0
const MORE_W := 44.0
const SWITCH_W := 74.0
const GRID_COLS := 4
const XF_COLOR := Color("#ff2b6e")   ## X-Factor abilities (CardRules.PROGRAM_COLORS["xf"])

## Set by the match: name tags read the agents' positions from it (optional).
var runner: PlayRunner

var _all_plays: Array[PlayDef] = []
var _bar_plays: Array[PlayDef] = []
var _best: PlayDef
var _selected: PlayDef
var _keyed_id := ""
var _grid: PanelContainer
var _grid_dim: ColorRect
var _grid_tabs: HBoxContainer
var _grid_cards: GridContainer
var _grid_cat := ""
var _grid_buttons: Dictionary = {}

var _root: Control
var _safe: Control
var _top: _Scoreboard
var _bottom: _BottomBar
var _tags: _NameTags
var _replay_fx: _ReplayFx
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
var _bottom_row: HBoxContainer
var _pad_left: Control
var _pad_right: Control
var _play_bar: HBoxContainer
var _restart: Button
var _switch: Button
var _reserve_switch := false
var _buttons: Dictionary = {}
## Road to Glory pieces: the pre-snap call card, the per-play grade pop, your stat line.
var _rtg_card: RetroPanel
var _rtg_title: Label
var _rtg_job: Label
var _rtg_row: HBoxContainer
var _grade: Label
var _rtg_line: Label


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

	_bottom = _BottomBar.new()
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_top = -BAR_H
	_bottom.pad_l = SafeArea.left()
	_bottom.pad_r = SafeArea.right()
	_root.add_child(_bottom)

	# Everything interactive lives inside the safe area (left / top / right insets; the
	# bottom strip bleeds to the screen edge so the row above it stays clear of it).
	_safe = Control.new()
	_safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe.offset_left = SafeArea.left()
	_safe.offset_right = -SafeArea.right()
	_safe.offset_top = maxf(SafeArea.top(), 2.0)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_safe)

	_top = _Scoreboard.new()
	_top.hud = self
	_anchor(_top, Vector2(0.5, 0.0), Rect2(-_Scoreboard.W * 0.5, 0, _Scoreboard.W, _Scoreboard.H))
	_safe.add_child(_top)

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

	# Pause: a real 26 px button at the top-left.
	_pause = Button.new()
	_pause.theme_type_variation = "HudButton"
	_pause.icon = UiSkin.icon("pause")
	_pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.add_theme_color_override("icon_normal_color", UiSkin.WHITE)
	_pause.add_theme_color_override("icon_hover_color", UiSkin.WHITE)
	_pause.add_theme_color_override("icon_pressed_color", UiSkin.NAVY_DEEP)
	_pause.focus_mode = Control.FOCUS_NONE
	_anchor(_pause, Vector2(0, 0), Rect2(0, 0, 28, 28))
	_pause.pressed.connect(func() -> void: pause_pressed.emit())
	_pause.visible = false
	_safe.add_child(_pause)

	# PUNT / FG / TIMEOUT: a compact stack at the top right.
	_specials = VBoxContainer.new()
	_specials.add_theme_constant_override("separation", 4)
	_specials.alignment = BoxContainer.ALIGNMENT_BEGIN
	_anchor(_specials, Vector2(1, 0), Rect2(-70, 0, 70, 80))
	_specials.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_specials.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_specials)

	# "DEFENSE IS KEYING ON X" under the scoreboard.
	_warning = Label.new()
	_anchor(_warning, Vector2(0.5, 0.0), Rect2(-100, _Scoreboard.H + 3, 200, 13))
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warning.add_theme_color_override("font_color", Color.WHITE)
	_warning.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	var warn_box := UiSkin.panel_box(UiSkin.RED.darkened(0.35), UiSkin.RED, 2)
	_warning.add_theme_stylebox_override("normal", warn_box)
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.visible = false
	_safe.add_child(_warning)

	_xf_box = VBoxContainer.new()
	_xf_box.add_theme_constant_override("separation", 1)
	_xf_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_xf_box, Vector2(0.0, 0.0), Rect2(4, BAR_H + 3 + 30, 150, 60))
	_safe.add_child(_xf_box)
	_xf_toast = Label.new()
	_anchor(_xf_toast, Vector2(0.5, 0.0), Rect2(-130, 56, 260, 30))
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
	_safe.add_child(_xf_toast)

	# Bottom row: [pad][play carousel][SWITCH slot]. The pads are equal so the carousel
	# stays centred; both are zero-width until the defense SWITCH slot is reserved.
	_bottom_row = HBoxContainer.new()
	_bottom_row.add_theme_constant_override("separation", 4)
	_bottom_row.anchor_left = 0.0
	_bottom_row.anchor_right = 1.0
	_bottom_row.anchor_top = 1.0
	_bottom_row.anchor_bottom = 1.0
	_bottom_row.offset_left = 0.0
	_bottom_row.offset_right = 0.0
	_bottom_row.offset_bottom = -(BAR_H + 4)
	_bottom_row.offset_top = -(BAR_H + 4 + CARD_H)
	_bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_bottom_row)
	_pad_left = Control.new()
	_pad_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_row.add_child(_pad_left)
	_play_bar = HBoxContainer.new()
	_play_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_bar.add_theme_constant_override("separation", 4)
	_play_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_row.add_child(_play_bar)
	_pad_right = Control.new()
	_pad_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_row.add_child(_pad_right)

	# SWITCH (defense): lives in the reserved right slot of the bottom row.
	_switch = Button.new()
	_switch.text = "SWITCH"
	_switch.theme_type_variation = "YellowButton"
	_switch.focus_mode = Control.FOCUS_NONE
	_switch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_switch.pressed.connect(func() -> void: switch_pressed.emit())
	_switch.visible = false
	_pad_right.add_child(_switch)

	_build_grid()

	kick_meter = KickMeter.new()
	kick_meter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(kick_meter)

	_tip = RetroPanel.new("COACH SAYS", UiSkin.PANEL, 6)
	_anchor(_tip, Vector2(0.5, 0.0), Rect2(-150, 44, 300, 60))
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
	var ok := MetaUI.yellow("GOT IT", Vector2(80, 24), func() -> void:
		_tip.visible = false
		tip_closed.emit())
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tip_box.add_child(ok)

	_choice_dim = ColorRect.new()
	_choice_dim.color = Color(UiSkin.SHADOW, 0.6)
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
	_choice_title.add_theme_color_override("font_color", UiSkin.YELLOW)
	_choice_title.add_theme_font_size_override("font_size", 16)
	cbox.add_child(_choice_title)
	_choice_body = Label.new()
	_choice_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(_choice_body)
	_choice_buttons = VBoxContainer.new()
	_choice_buttons.add_theme_constant_override("separation", 4)
	cbox.add_child(_choice_buttons)

	_build_rtg()

	_restart = MetaUI.yellow("NEW DRIVE", Vector2(96, 24), func() -> void: restart_pressed.emit())
	_anchor(_restart, Vector2(0.5, 0.5), Rect2(-48, 10, 96, 24))
	_restart.visible = false
	_root.add_child(_restart)
	_update_reserve()


static func _anchor(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y


## Road to Glory: the pre-snap call card (bottom centre), the grade pop and the stat line.
func _build_rtg() -> void:
	_rtg_card = RetroPanel.new("", UiSkin.PANEL, 4)
	_anchor(_rtg_card, Vector2(0.5, 1.0), Rect2(-150, -(BAR_H + 4 + 58), 300, 58))
	_rtg_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rtg_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_rtg_card.visible = false
	_safe.add_child(_rtg_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_rtg_card.add_child(col)
	_rtg_title = Label.new()
	_rtg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rtg_title.add_theme_color_override("font_color", UiSkin.YELLOW)
	col.add_child(_rtg_title)
	_rtg_job = Label.new()
	_rtg_job.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rtg_job.custom_minimum_size = Vector2(288, 0)
	_rtg_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_rtg_job)
	_rtg_row = HBoxContainer.new()
	_rtg_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rtg_row.add_theme_constant_override("separation", 5)
	col.add_child(_rtg_row)
	_grade = Label.new()
	_anchor(_grade, Vector2(1.0, 0.0), Rect2(-120, 30, 116, 30))
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grade.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_grade.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_grade.add_theme_stylebox_override("normal", UiSkin.panel_box(Color(0.03, 0.04, 0.12, 0.88), UiSkin.YELLOW, 2))
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade.visible = false
	_safe.add_child(_grade)
	_rtg_line = Label.new()
	_anchor(_rtg_line, Vector2(0.0, 0.0), Rect2(32, 4, 170, 13))
	_rtg_line.add_theme_stylebox_override("normal", UiSkin.panel_box(Color(0.03, 0.04, 0.12, 0.8), Color(1, 1, 1, 0.25), 1))
	_rtg_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rtg_line.visible = false
	_safe.add_child(_rtg_line)


## The pre-snap card: call name, your job, buttons [{id, text, yellow}]. Empty title hides it.
func show_rtg_call(title: String, job: String, actions: Array) -> void:
	_rtg_card.visible = title != ""
	if title == "":
		return
	_rtg_title.text = title
	_rtg_job.text = job
	for c in _rtg_row.get_children():
		_rtg_row.remove_child(c)
		c.queue_free()
	for a in actions:
		var id := str(a["id"])
		var cb := func() -> void: rtg_action.emit(id)
		var b := MetaUI.yellow(str(a["text"]), Vector2(84, 22), cb) if a.get("yellow", false) \
				else MetaUI.button(str(a["text"]), Vector2(84, 22), cb)
		b.disabled = a.get("disabled", false)
		_rtg_row.add_child(b)
	_rtg_card.reset_size.call_deferred()


func hide_rtg_call() -> void:
	_rtg_card.visible = false


func rtg_call_open() -> bool:
	return _rtg_card.visible


## Per-play grade pop: "B+  12 YD CATCH" (tier 2 green, 1 white, 0 red), fades out.
func show_grade(letter: String, note: String) -> void:
	var tier := RtgTracker.tier(letter)
	_grade.text = "%s  %s " % [note, letter]
	_grade.add_theme_color_override("font_color", [UiSkin.RED, Color.WHITE, UiSkin.GREEN][tier])
	_grade.visible = true
	_grade.modulate.a = 1.0
	_grade.pivot_offset = Vector2(_grade.size.x, _grade.size.y * 0.5)
	_grade.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(_grade, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.0)
	tw.tween_property(_grade, "modulate:a", 0.0, 0.35)


## Your running stat line (top left, next to pause). "" hides it.
func set_rtg_line(text: String) -> void:
	_rtg_line.visible = text != ""
	_rtg_line.text = " " + text


## Road to Glory controls layer (RtgPad) inside the safe area, under banners and panels.
func add_rtg_pad(pad: Control) -> void:
	_safe.add_child(pad)
	_safe.move_child(pad, 0)


## The category-tabbed playbook grid (opened by the MORE card).
func _build_grid() -> void:
	_grid_dim = ColorRect.new()
	_grid_dim.color = Color(UiSkin.SHADOW, 0.55)
	_grid_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_dim.visible = false
	_root.add_child(_grid_dim)
	_grid = PanelContainer.new()
	_grid.add_theme_stylebox_override("panel", UiSkin.panel_box(Color(UiSkin.NAVY_DEEP, 0.97), UiSkin.HUD_EDGE, 6))
	_anchor(_grid, Vector2(0.5, 0.5), Rect2(-100, -60, 200, 120))
	_grid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_grid.grow_vertical = Control.GROW_DIRECTION_BOTH
	_grid.visible = false
	_root.add_child(_grid)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_grid.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	var title := Label.new()
	title.text = "PLAYBOOK"
	title.add_theme_color_override("font_color", UiSkin.YELLOW)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_grid_tabs = HBoxContainer.new()
	_grid_tabs.add_theme_constant_override("separation", 3)
	_grid_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_grid_tabs)
	var close := Button.new()
	close.text = "BACK"
	close.theme_type_variation = "HudButton"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(54, 24)
	close.pressed.connect(func() -> void: show_playbook_grid(false))
	head.add_child(close)
	_grid_cards = GridContainer.new()
	_grid_cards.columns = GRID_COLS
	_grid_cards.add_theme_constant_override("h_separation", 4)
	_grid_cards.add_theme_constant_override("v_separation", 4)
	box.add_child(_grid_cards)


# ---------------------------------------------------------------- play calling

## Offers plays: the bar shows the top BAR_SIZE of `ranked` (first = "BEST", preselected
## by the caller) plus a MORE card that opens the full playbook grid of `all`.
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
	if play != null and play.category != _grid_cat and not _grid.visible:
		_grid_cat = play.category
		_rebuild_grid()
	for p in _grid_buttons:
		_grid_buttons[p].set_pressed_no_signal(p == play)


## Warns that the CPU defense is keying on a play and marks that play's card ("" clears).
func set_keyed(_plays: Array[PlayDef], keyed_id: String) -> void:
	_keyed_id = keyed_id
	var keyed_name := ""
	for p in _all_plays:
		if p.id == keyed_id:
			keyed_name = p.display_name.to_upper()
	for p in _buttons:
		_buttons[p].keyed = p.id == keyed_id
		_buttons[p].queue_redraw()
	for p in _grid_buttons:
		_grid_buttons[p].keyed = p.id == keyed_id
		_grid_buttons[p].queue_redraw()
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
		var hot: bool = a.begins_with("FG") or a.begins_with("PUNT")
		b.theme_type_variation = "HudButtonHot" if hot else "HudButton"
		b.custom_minimum_size = Vector2(70, 24)
		b.focus_mode = Control.FOCUS_NONE
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
	_grid_dim.visible = on
	if on:
		if _grid_cat == "" and _selected != null:
			_grid_cat = _selected.category
		_rebuild_grid()


## Keeps the playbook panel centred however big its content is.
func _center_grid() -> void:
	_grid.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_grid.position = ((vp - _grid.size) * 0.5).round()


func show_play_bar(on: bool) -> void:
	_play_bar.visible = on
	if not on:
		show_playbook_grid(false)


func _make_card(p: PlayDef, size: Vector2) -> _PlayCard:
	var b := _PlayCard.new()
	b.setup(p.display_name.to_upper(), _card_sub(p), size)
	b.keyed = p.id == _keyed_id
	b.toggle_mode = true
	b.pressed.connect(func() -> void:
		show_playbook_grid(false)
		play_selected.emit(p))
	return b


## Second card line: the category, or the formation when the name already says it.
func _card_sub(p: PlayDef) -> String:
	var sub := p.category
	if sub in p.display_name.to_upper() and p.formation != null:
		sub = p.formation.display_name.to_upper()
	return sub


func _rebuild_bar() -> void:
	for c in _play_bar.get_children():
		_play_bar.remove_child(c)
		c.queue_free()
	_buttons.clear()
	for p in _bar_plays:
		var b := _make_card(p, Vector2(CARD_W, CARD_H))
		b.best = p == _best
		b.set_pressed_no_signal(p == _selected)
		_play_bar.add_child(b)
		_buttons[p] = b
	var more := _PlayCard.new()
	more.setup("MORE", "ALL", Vector2(MORE_W, CARD_H))
	more.pressed.connect(func() -> void: show_playbook_grid(not _grid.visible))
	_play_bar.add_child(more)


func _rebuild_grid() -> void:
	for c in _grid_cards.get_children():
		_grid_cards.remove_child(c)
		c.queue_free()
	for c in _grid_tabs.get_children():
		_grid_tabs.remove_child(c)
		c.queue_free()
	_grid_buttons.clear()
	var cats: Array[String] = []
	for p in _all_plays:
		if p.category not in cats:
			cats.append(p.category)
	if _grid_cat not in cats and not cats.is_empty():
		_grid_cat = cats[0]
	for cat in cats:
		var t := Button.new()
		t.text = cat
		t.theme_type_variation = "HudButton"
		t.toggle_mode = true
		t.focus_mode = Control.FOCUS_NONE
		t.custom_minimum_size = Vector2(52, 24)
		t.set_pressed_no_signal(cat == _grid_cat)
		t.pressed.connect(func() -> void:
			_grid_cat = cat
			_rebuild_grid())
		_grid_tabs.add_child(t)
	for p in _all_plays:
		if p.category != _grid_cat:
			continue
		var b := _make_card(p, Vector2(92, CARD_H))
		b.set_pressed_no_signal(p == _selected)
		_grid_cards.add_child(b)
		_grid_buttons[p] = b
	_center_grid.call_deferred()


func show_restart(on: bool) -> void:
	_restart.visible = on


## The defense SWITCH button (pre-snap and live defensive snaps only). Its slot in the
## bottom row stays reserved from the first time it is shown, so nothing shifts.
func show_switch(on: bool) -> void:
	if on:
		_reserve_switch = true
		_update_reserve()
	_switch.visible = on


func is_switch_visible() -> bool:
	return _switch.visible


func _update_reserve() -> void:
	var w := SWITCH_W if _reserve_switch else 0.0
	_pad_left.custom_minimum_size = Vector2(w, CARD_H)
	_pad_right.custom_minimum_size = Vector2(w, CARD_H)


# ---------------------------------------------------------------- bars / tags / banners

## Back-compat (drive sandbox): free text for the scoreboard (`down_text` on the pill,
## `drive_text` on the strip below it).
func set_scorebug(down_text: String, drive_text: String) -> void:
	_top.data = {}
	_top.left = drive_text
	_top.right = down_text
	_top.queue_redraw()


## Full game: {"home", "away", "home_score", "away_score", "possession", "quarter": "1ST QTR",
## "clock": "0:51", "down": "1ST & 10", "home_color", "away_color", "spot": optional text}.
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
		_warning.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 120.0)
	_tags.visible = runner != null
	if _tags.visible:
		_tags.queue_redraw()
	if runner != null and is_instance_valid(runner) and _top.live_spot != _spot_text():
		_top.queue_redraw()


## Ball spot under the scoreboard: "KC 25" (yard line, tagged with the side of the field).
func _spot_text() -> String:
	if runner == null or not is_instance_valid(runner) or _top.data.is_empty():
		return ""
	var yl := int(roundf(runner.los_x - FieldGeo.OWN_GOAL))
	if yl == 50:
		return "50"
	var poss: String = _top.data.get("possession", "")
	var other: String = _top.data.get("away", "") if poss == _top.data.get("home", "") else _top.data.get("home", "")
	return ("%s %d" % [poss, yl]) if yl < 50 else ("%s %d" % [other, 100 - yl])


## True when a viewport point lies over an interactive HUD control.
func is_point_over_ui(p: Vector2) -> bool:
	if _grid.visible or _choice.visible or _tip.visible:
		return true   # the playbook grid, choice panels and coach tips are modal
	if _restart.visible and _restart.get_global_rect().has_point(p):
		return true
	if _switch.visible and _switch.get_global_rect().grow(4).has_point(p):
		return true
	if _pause.visible and _pause.get_global_rect().grow(2).has_point(p):
		return true
	for b in _specials.get_children():
		if b is Control and b.visible and b.get_global_rect().has_point(p):
			return true
	if _play_bar.visible:
		for b in _play_bar.get_children():
			if b is Control and b.get_global_rect().has_point(p):
				return true
	if _rtg_card.visible and _rtg_card.get_global_rect().grow(2).has_point(p):
		return true
	return false


# ---------------------------------------------------------------- drawn pieces

## One play-call card: big play name, small category / formation line, a green BEST badge
## (top left) and a red "!" when the CPU defense is keying on the play. Selected = yellow.
class _PlayCard:
	extends Button
	var title := ""
	var sub := ""
	var best := false
	var keyed := false

	func setup(p_title: String, p_sub: String, size_: Vector2) -> void:
		title = p_title
		sub = p_sub
		custom_minimum_size = size_
		theme_type_variation = "HudCard"
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var on := is_pressed()
		var r := Rect2(1, 2, size.x - 2, size.y - 2) if on else Rect2(2, 0, size.x - 2, size.y - 2)
		var cx := r.position.x + r.size.x * 0.5
		var ink := UiSkin.NAVY_DEEP if on else UiSkin.WHITE
		var soft := UiSkin.NAVY if on else UiSkin.MUTED
		if keyed and not on:
			ink = UiSkin.RED.lightened(0.25)
		UiSkin.draw_text_fit(self, cx, r.position.y + 20.0, title, int(r.size.x) - 6, ink)
		var s := sub
		var maxw := int(r.size.x) - 6
		while s.length() > 1 and PixelFont.condensed_width(s) > maxw:
			s = s.left(s.length() - 1)
		PixelFont.draw_condensed(self, Vector2(roundf(cx - PixelFont.condensed_width(s) * 0.5), r.position.y + 22.0), s, soft)
		if best:
			var w := PixelFont.condensed_width("BEST") + 4
			draw_rect(Rect2(r.position.x + 3, r.position.y + 3, w, 7), UiSkin.GREEN)
			PixelFont.draw_condensed(self, Vector2(r.position.x + 5, r.position.y + 3), "BEST", UiSkin.NAVY_DEEP)
		if keyed:
			var kx := r.end.x - 11
			draw_rect(Rect2(kx, r.position.y + 3, 8, 7), UiSkin.RED)
			PixelFont.draw_condensed(self, Vector2(kx + 3, r.position.y + 3), "!", Color.WHITE)


## Compact scoreboard pill: AWAY chip/abbr/score | quarter + clock | score/abbr/chip HOME,
## with a small strip under it for down & distance and the ball spot.
class _Scoreboard:
	extends Control
	const W := 216.0
	const H := 22.0
	const STRIP_H := 11.0
	var hud: MatchHUD
	var data: Dictionary = {}
	var left := ""    ## sandbox free text (strip)
	var right := ""   ## sandbox free text (pill)
	var live_spot := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(W, H + STRIP_H)

	func _draw() -> void:
		UiSkin.draw_frame(self, Rect2(0, 0, W, H), Color(UiSkin.NAVY_DEEP, 0.94), UiSkin.HUD_EDGE)
		var strip := ""
		if data.is_empty():
			UiSkin.draw_text_c(self, W * 0.5, 15, right, 8, UiSkin.YELLOW)
			strip = left
		else:
			_side("away", true)
			_side("home", false)
			draw_rect(Rect2(W * 0.5 - 29, 3, 1, H - 6), Color(UiSkin.HUD_EDGE, 0.6))
			draw_rect(Rect2(W * 0.5 + 28, 3, 1, H - 6), Color(UiSkin.HUD_EDGE, 0.6))
			UiSkin.draw_text_c(self, W * 0.5, 11, data.get("quarter", ""), 8, UiSkin.MUTED)
			UiSkin.draw_text_c(self, W * 0.5, 20, data.get("clock", ""), 8, UiSkin.YELLOW)
			live_spot = hud._spot_text() if hud != null else ""
			strip = str(data.get("down", ""))
			var spot: String = data.get("spot", live_spot)
			if spot != "":
				strip += "  ·  " + spot
		if strip != "":
			var w := PixelFont.text_width(strip) + 14.0
			var x := roundf((W - w) * 0.5)
			UiSkin.draw_frame(self, Rect2(x, H - 1, w, STRIP_H + 1), Color(UiSkin.NAVY_DEEP, 0.9), UiSkin.HUD_EDGE)
			UiSkin.draw_text_c(self, W * 0.5, H + 8, strip, 8, UiSkin.WHITE if data.is_empty() else UiSkin.WHITE)

	func _side(key: String, is_left: bool) -> void:
		var abbr: String = data.get(key, "")
		var score := str(data.get(key + "_score", 0))
		var has_ball: bool = data.get("possession", "") == abbr
		var col: Color = data.get(key + "_color", Color("#30364a"))
		var ink := UiSkin.YELLOW if has_ball else UiSkin.WHITE
		var sw := PixelFont.text_width(score, 16)
		var aw := PixelFont.text_width(abbr)
		var chip := Rect2(6 if is_left else W - 14, 7, 8, 8)
		draw_rect(chip.grow(1), UiSkin.SHADOW)
		draw_rect(chip, col)
		draw_rect(Rect2(chip.position, Vector2(8, 1)), col.lightened(0.35))
		var ax := 17.0 if is_left else W - 17.0 - aw
		UiSkin.draw_text(self, Vector2(ax, 15), abbr, 8, ink)
		var sx := 80.0 - sw if is_left else W - 80.0
		UiSkin.draw_text(self, Vector2(sx, 17), score, 16, UiSkin.WHITE, UiSkin.SHADOW)
		if has_ball:
			var bx := 38.0 if is_left else W - 49.0
			UiSkin.draw_icon(self, "ball", Vector2(bx, 8), Color("#c8793a"), 1.0, false)


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
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiSkin.SHADOW, 0.82))
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
		if r.locked != null and is_instance_valid(r.locked):
			_draw_defender(r, true)   # Road to Glory: a YOU pill over your player, either side
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
	func _draw_defender(r: PlayRunner, rtg := false) -> void:
		var a := r.locked if rtg else r.controlled
		if a == null or not is_instance_valid(a) or r.phase not in [PlayRunner.Phase.PRE_SNAP, PlayRunner.Phase.LIVE]:
			return
		if a == r.carrier and not rtg:
			return   # returning an interception: the carrier arrow marks him
		var at := a.get_global_transform_with_canvas().origin
		var t := "#%d %s" % [a.jersey, _short(a.display_name)] if a.jersey > 0 else _short(a.display_name)
		if rtg:
			t = "YOU  " + t
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
