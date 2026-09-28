extends Control
## LINEUP: the payoff screen for pulling cards. OFFENSE / DEFENSE tabs show your starters as
## mini cards laid out like a formation on a turf board (offense: WR1 OL1-OL4 TE WR2 on the
## line, QB + RB behind, K apart; defense: CB1 DL1-DL3 CB2 up front, S1 LB1 LB2 S2 behind).
## A green "▲+N" badge marks every slot where you own a better card (EconomyRules.
## lineup_upgrades); AUTO-BEST pulses while any exist. Tap a slot to pick from the cards
## that fit it (sorted by OVR, with the +/- change); team OVR and the offense / defense
## stars count up live.

const OFF_LINE := ["WR1", "OL1", "OL2", "OL3", "OL4", "TE", "WR2"]
const GAP := 7.0
const ROW_GAP := 12.0
const PICK_COLS := 7

var _ui: Dictionary
var _side := 0                     ## 0 = offense, 1 = defense
var _field: _Field
var _slots: Dictionary = {}        ## slot -> _Slot (current side only)
var _tabs: Array[Button] = []
var _ovr_l: Label
var _ovr_box: Control
var _off_stars: StarRating
var _def_stars: StarRating
var _auto: Button
var _auto_tw: Tween
var _chem_l: Label
var _up_l: Label
var _shown_ovr := -1
var _picker: Control


func _ready() -> void:
	_ui = MetaUI.screen(self, "LINEUP")
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 3)
	# Info line: hint | upgrades | chemistry.
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	root.add_child(info)
	info.add_child(MetaUI.label("TAP A PLAYER TO SWAP", UiSkin.MUTED))
	info.add_child(MetaUI.spacer())
	_up_l = MetaUI.label("", UiSkin.GREEN)
	info.add_child(_up_l)
	_chem_l = MetaUI.label("", UiSkin.WHITE)
	info.add_child(_chem_l)
	_field = _Field.new()
	_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field.resized.connect(_layout)
	root.add_child(_field)
	# Bottom nav: home | OFFENSE DEFENSE | TEAM OVR, stars | AUTO-BEST.
	var nav: HBoxContainer = _ui["nav"]
	for i in 2:
		var t := MetaUI.button(["OFFENSE", "DEFENSE"][i], Vector2(62, 28), _set_side.bind(i, true))
		_tabs.append(t)
		nav.add_child(t)
	nav.add_child(MetaUI.spacer())
	_ovr_l = MetaUI.label("", UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_CENTER)
	_ovr_box = MetaUI.stat_box("TEAM OVR", _ovr_l, Vector2(54, 29))
	nav.add_child(_ovr_box)
	_off_stars = MetaUI.stars(0.0, UiSkin.STAR_BLUE)
	nav.add_child(MetaUI.stat_box("OFFENSE", _off_stars, Vector2(58, 29)))
	_def_stars = MetaUI.stars(0.0, UiSkin.STAR_RED)
	nav.add_child(MetaUI.stat_box("DEFENSE", _def_stars, Vector2(58, 29)))
	_auto = MetaUI.button("AUTO-BEST", Vector2(76, 28), _auto_best)
	nav.add_child(_auto)
	_set_side(0, false)
	_update_totals(false)
	for arg in OS.get_cmdline_user_args():
		if arg == "--defense":   # debug: start on the defense tab (screenshots)
			_set_side(1, false)
		if arg.begins_with("--pick="):   # debug: open a slot's picker (screenshots)
			_open_picker.call_deferred(arg.get_slice("=", 1))


# ---------------------------------------------------------------- building

func _side_slots(side: int) -> Array:
	return TeamRating.OFFENSE_SLOTS + ["K"] if side == 0 else TeamRating.DEFENSE_SLOTS


func _set_side(side: int, animate := true) -> void:
	if animate and side == _side:
		return
	_side = side
	for i in _tabs.size():
		_tabs[i].theme_type_variation = "YellowButton" if i == side else ""
	for c in _slots.values():
		_field.remove_child(c)
		c.queue_free()
	_slots = {}
	var i := 0
	for slot: String in _side_slots(side):
		var s := _Slot.new(slot)
		s.pressed.connect(_open_picker)
		_field.add_child(s)
		_slots[slot] = s
		if animate:
			s.modulate.a = 0.0
			var tw := s.create_tween()
			tw.tween_interval(0.025 * i)
			tw.tween_property(s, "modulate:a", 1.0, 0.12)
		i += 1
	_field.side = side
	_layout()
	_fill_slots()


## Card positions inside the field, in a formation.
func _layout() -> void:
	if _field == null or _field.size.x <= 0.0:
		return
	var pitch := CardView.W + GAP
	var x0 := roundf((_field.size.x - (7 * CardView.W + 6 * GAP)) * 0.5)
	var top := roundf((_field.size.y - (2 * CardView.H + ROW_GAP)) * 0.5)
	var bot := top + CardView.H + ROW_GAP
	var pos := {}
	if _side == 0:
		for i in OFF_LINE.size():
			pos[OFF_LINE[i]] = Vector2(x0 + i * pitch, top)
		pos["QB"] = Vector2(x0 + 2.5 * pitch, bot)      # under center (between OL2 and OL3)
		pos["RB"] = Vector2(x0 + 3.5 * pitch + 4, bot)  # beside him, shotgun style
		pos["K"] = Vector2(x0 + 6 * pitch, bot)
		_field.divider_x = x0 + 5 * pitch + CardView.W + 8
	else:
		pos["CB1"] = Vector2(x0, top)
		pos["DL1"] = Vector2(x0 + 2 * pitch, top)
		pos["DL2"] = Vector2(x0 + 3 * pitch, top)
		pos["DL3"] = Vector2(x0 + 4 * pitch, top)
		pos["CB2"] = Vector2(x0 + 6 * pitch, top)
		pos["S1"] = Vector2(x0 + 0.5 * pitch, bot)
		pos["LB1"] = Vector2(x0 + 2.5 * pitch, bot)
		pos["LB2"] = Vector2(x0 + 3.5 * pitch, bot)
		pos["S2"] = Vector2(x0 + 5.5 * pitch, bot)
		_field.divider_x = -1.0
	_field.line_y = top + CardView.H + ROW_GAP * 0.5
	for slot in _slots:
		(_slots[slot] as _Slot).position = (pos.get(slot, Vector2.ZERO) as Vector2).round()
	_field.queue_redraw()


## Puts the current lineup's cards and the upgrade badges into the slots; `changed` slots
## pop with a burst.
func _fill_slots(changed: Array = []) -> void:
	var prof := SaveManager.profile
	var ups := EconomyRules.lineup_upgrades(prof, GameData.db)
	for slot: String in _slots:
		var s: _Slot = _slots[slot]
		var e := prof.find(int(prof.lineup.get(slot, -1)))
		var c: CardDef = GameData.card(e["def"]) if not e.is_empty() else null
		s.set_card(c, e if c != null else {})
		var up: Dictionary = ups.get(slot, {})
		s.set_upgrade(int(up.get("delta", 0)), c == null)
		if slot in changed:
			Fx.pop(s, 1.18, 0.35)
			Fx.burst(_field, s.position + s.size * 0.5, UiSkin.YELLOW, 18, 80.0, 0.6)
	# Tab badges (upgrades waiting on each side) and the AUTO-BEST pulse.
	var counts := [0, 0]
	for slot in ups:
		counts[0 if slot in TeamRating.OFFENSE_SLOTS or slot == "K" else 1] += 1
	for i in 2:
		MetaUI.badge(_tabs[i], counts[i])
	var n: int = counts[0] + counts[1]
	_up_l.text = ("▲ %d UPGRADE%s ON THE BENCH" % [n, "" if n == 1 else "S"]) if n > 0 else "BEST LINEUP ✓"
	_up_l.add_theme_color_override("font_color", UiSkin.GREEN if n > 0 else UiSkin.MUTED)
	if n > 0 and (_auto_tw == null or not _auto_tw.is_valid()):
		_auto.theme_type_variation = "YellowButton"
		_auto_tw = Fx.pulse(_auto, 1.07, 0.8)
	elif n == 0:
		_auto.theme_type_variation = ""
		if _auto_tw != null and _auto_tw.is_valid():
			_auto_tw.kill()
		_auto.scale = Vector2.ONE


## Team OVR (count-up), offense / defense stars (tweened) and chemistry.
func _update_totals(animate := true) -> void:
	var prof := SaveManager.profile
	var entries := Collection.lineup_entries(prof, GameData.db)
	var ovr := TeamRating.team_ovr(entries)
	var ss := MetaUI.side_stars(entries)
	var chem := Collection.chemistry(prof, GameData.db)
	_chem_l.text = "CHEMISTRY +%.1f" % chem
	_chem_l.add_theme_color_override("font_color", UiSkin.YELLOW if chem > 0.0 else UiSkin.MUTED)
	if not animate or _shown_ovr < 0:
		_ovr_l.text = str(ovr)
		_off_stars.value = ss["off"]
		_def_stars.value = ss["def"]
	else:
		if ovr != _shown_ovr:
			Fx.count_up(_ovr_l, _shown_ovr, ovr, 0.6)
			Fx.pop(_ovr_box, 1.12, 0.3)
			var diff := ovr - _shown_ovr
			MetaUI.toast(self, "TEAM OVR %d  %s%d" % [ovr, "▲+" if diff > 0 else "▼", absi(diff)],
					UiSkin.GREEN if diff > 0 else UiSkin.STAR_RED)
		var tw := create_tween().set_parallel()
		tw.tween_property(_off_stars, "value", float(ss["off"]), 0.5)
		tw.tween_property(_def_stars, "value", float(ss["def"]), 0.5)
	_shown_ovr = ovr


# ---------------------------------------------------------------- actions

func _auto_best() -> void:
	var prof := SaveManager.profile
	var before := prof.lineup.duplicate()
	Collection.auto_lineup(prof, GameData.db)
	SaveManager.save()
	var changed: Array = []
	for slot in TeamRating.ALL_SLOTS:
		if int(before.get(slot, -1)) != int(prof.lineup.get(slot, -1)):
			changed.append(slot)
	if changed.is_empty():
		MetaUI.toast(self, "ALREADY YOUR BEST LINEUP", UiSkin.WHITE)
		return
	Sfx.play("levelup")
	_fill_slots(changed)
	_update_totals()


func _open_picker(slot: String) -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	Sfx.play("flip")
	var prof := SaveManager.profile
	var pos := TeamRating.slot_pos(slot)
	var cur_uid := int(prof.lineup.get(slot, -1))
	var cur := prof.find(cur_uid)
	var cur_ovr := Collection.card_ovr(GameData.db, cur) if not cur.is_empty() else 0
	var where := {}   # uid -> slot it starts in
	for s in prof.lineup:
		where[int(prof.lineup[s])] = s
	var cands: Array = []
	for e in prof.cards:
		var c: CardDef = GameData.card(e["def"])
		if c != null and GameData.player(c.player_id).pos == pos:
			cands.append([Collection.card_ovr(GameData.db, e), e, c])
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else int(a[1]["uid"]) < int(b[1]["uid"]))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	var cur_txt := "EMPTY SLOT"
	if not cur.is_empty():
		cur_txt = "NOW: %d  %s" % [cur_ovr, GameData.player(GameData.card(cur["def"]).player_id).short_name()]
	head.add_child(MetaUI.label(cur_txt, UiSkin.WHITE))
	head.add_child(MetaUI.spacer())
	head.add_child(MetaUI.label("%d %s CARD%s" % [cands.size(), pos, "" if cands.size() == 1 else "S"], UiSkin.MUTED))
	var buttons: Array = [["CLOSE", Callable()]]
	if cands.size() <= 1:
		var none := MetaUI.label("NO OTHER %s CARDS YET.\nOPEN PACKS IN THE STORE TO FIND ONE!" % pos, UiSkin.MUTED, 8,
				HORIZONTAL_ALIGNMENT_CENTER)
		none.custom_minimum_size = Vector2(250, 26)
		body.add_child(none)
		buttons.append(["STORE", func() -> void: SceneRouter.goto(SceneRouter.STORE), true])
	var cols := clampi(cands.size(), 1, PICK_COLS)
	var rows := ceili(cands.size() / float(PICK_COLS))
	var cell_h := CardView.H + 11
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sc.custom_minimum_size = Vector2(cols * (CardView.W + 6) - 6 + (10 if rows > 2 else 0),
			mini(rows, 2) * (cell_h + 4) - 4)
	body.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)
	_picker = MetaUI.popup(self, "PICK %s" % slot, body, buttons)
	var i := 0
	for item in cands:
		var e: Dictionary = item[1]
		var uid := int(e["uid"])
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		var v := CardView.new(item[2], e, 1)
		v.selected = uid == cur_uid
		v.tapped.connect(func(_v: CardView) -> void: _choose(slot, uid))
		cell.add_child(v)
		var d := int(item[0]) - cur_ovr
		var txt := "NEW"
		var col := UiSkin.GREEN
		if uid == cur_uid:
			txt = "CURRENT"
			col = UiSkin.YELLOW
		elif not cur.is_empty():
			txt = "+%d" % d if d > 0 else ("%d" % d if d < 0 else "+0")
			col = UiSkin.GREEN if d > 0 else (UiSkin.STAR_RED if d < 0 else UiSkin.WHITE)
		if uid != cur_uid and where.has(uid):
			txt += " " + str(where[uid])
		cell.add_child(MetaUI.label(txt, col, 8, HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(cell)
		cell.modulate.a = 0.0
		var tw := cell.create_tween()
		tw.tween_interval(0.1 + 0.02 * mini(i, 14))
		tw.tween_property(cell, "modulate:a", 1.0, 0.1)
		i += 1


func _choose(slot: String, uid: int) -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null
	var prof := SaveManager.profile
	if int(prof.lineup.get(slot, -1)) == uid:
		return
	var before := prof.lineup.duplicate()
	var old_ovr := TeamRating.team_ovr(Collection.lineup_entries(prof, GameData.db))
	_assign(slot, uid)
	var changed: Array = []
	for s in TeamRating.ALL_SLOTS:
		if int(before.get(s, -1)) != int(prof.lineup.get(s, -1)):
			changed.append(s)
	var new_ovr := TeamRating.team_ovr(Collection.lineup_entries(prof, GameData.db))
	Sfx.play("claim" if new_ovr > old_ovr else "reveal")
	_fill_slots(changed)
	_update_totals()


## Puts a card into a slot; if it (or another version of the same player) starts elsewhere,
## the two slots swap.
func _assign(slot: String, uid: int) -> void:
	var prof := SaveManager.profile
	var new_player: String = GameData.card(prof.find(uid)["def"]).player_id
	var old := int(prof.lineup.get(slot, -1))
	for s in prof.lineup.keys():
		if s == slot:
			continue
		var other := prof.find(int(prof.lineup[s]))
		if other.is_empty():
			continue
		if int(prof.lineup[s]) == uid or GameData.card(other["def"]).player_id == new_player:
			if old >= 0 and TeamRating.slot_pos(s) == TeamRating.slot_pos(slot):
				prof.lineup[s] = old
			else:
				prof.lineup.erase(s)
	prof.lineup[slot] = uid
	SaveManager.save()


# ---------------------------------------------------------------- widgets

## Turf board behind the formation: mow stripes, hash marks, the line of scrimmage between
## the rows (blue offense / red defense) and a dashed divider before the kicker.
class _Field:
	extends Control
	var side := 0
	var line_y := 0.0
	var divider_x := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, UiSkin.BORDER)
		draw_rect(r.grow(-1), UiSkin.SHADOW)
		var turf := r.grow(-2)
		var stripe := 21.0
		var x := turf.position.x
		var k := 0
		while x < turf.end.x:
			var w := minf(stripe, turf.end.x - x)
			draw_rect(Rect2(x, turf.position.y, w, turf.size.y), Color("#2f7d3b") if k % 2 == 0 else Color("#2a7235"))
			x += stripe
			k += 1
		for hx in range(int(turf.position.x) + 10, int(turf.end.x), 21):
			draw_rect(Rect2(hx, turf.position.y + 2, 1, 3), Color(1, 1, 1, 0.3))
			draw_rect(Rect2(hx, turf.end.y - 5, 1, 3), Color(1, 1, 1, 0.3))
		if line_y > 0.0:
			var lc := UiSkin.STAR_BLUE if side == 0 else UiSkin.STAR_RED
			draw_rect(Rect2(turf.position.x, roundf(line_y) - 1, turf.size.x, 2), Color(lc, 0.6))
		if divider_x > 0.0:
			for y in range(int(line_y) + 4, int(turf.end.y) - 3, 4):
				draw_rect(Rect2(roundf(divider_x), y, 1, 2), Color(1, 1, 1, 0.4))


## One lineup slot: the starter's mini card (or an empty dashed frame), a bobbing green
## "▲+N" badge when a better card sits on the bench, and press feedback.
class _Slot:
	extends Control
	signal pressed(slot: String)
	var slot := ""
	var card_view: CardView
	var _badge: _UpBadge
	var _down := false

	func _init(p_slot: String) -> void:
		slot = p_slot
		custom_minimum_size = Vector2(CardView.W, CardView.H)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		_badge = _UpBadge.new()
		add_child(_badge)

	func set_card(card: CardDef, entry: Dictionary) -> void:
		if card_view != null:
			remove_child(card_view)
			card_view.queue_free()
			card_view = null
		if card != null:
			card_view = CardView.new(card, entry, 1)
			card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(card_view)
			move_child(card_view, 0)
		queue_redraw()

	func set_upgrade(delta: int, empty: bool) -> void:
		_badge.text = "" if delta <= 0 else ("▲NEW" if empty else "▲+%d" % delta)
		_badge.visible = delta > 0
		_badge.reset()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			pivot_offset = size * 0.5
			var tw := create_tween()
			if event.pressed:
				_down = true
				Sfx.play("tap")
				tw.tween_property(self, "scale", Vector2(0.93, 0.93), 0.05)
			else:
				tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				if _down and Rect2(Vector2.ZERO, size).has_point(event.position):
					pressed.emit(slot)
				_down = false
			accept_event()

	func _draw() -> void:
		if card_view != null:
			return
		# Empty slot: dashed frame, a plus and the slot name.
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.05, 0.2, 0.45))
		for x in range(0, int(r.size.x), 4):
			draw_rect(Rect2(x, 0, 2, 1), UiSkin.MUTED)
			draw_rect(Rect2(x, r.size.y - 1, 2, 1), UiSkin.MUTED)
		for y in range(0, int(r.size.y), 4):
			draw_rect(Rect2(0, y, 1, 2), UiSkin.MUTED)
			draw_rect(Rect2(r.size.x - 1, y, 1, 2), UiSkin.MUTED)
		var c := (r.size * 0.5 + Vector2(0, -8)).round()
		draw_rect(Rect2(c.x - 5, c.y - 1, 11, 3), UiSkin.MUTED)
		draw_rect(Rect2(c.x - 1, c.y - 5, 3, 11), UiSkin.MUTED)
		UiSkin.draw_text_c(self, r.size.x * 0.5, r.size.y - 18, slot, 8, UiSkin.WHITE)
		UiSkin.draw_text_c(self, r.size.x * 0.5, r.size.y - 8, "EMPTY", 8, UiSkin.MUTED)


## Green "▲+N" pill pinned to a slot's top-right corner, bobbing.
class _UpBadge:
	extends Control
	var text := ""
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		z_index = 2

	func reset() -> void:
		var w := PixelFont.text_width(text) + 5
		size = Vector2(w, 11)
		position = Vector2(CardView.W - w + 3, -9)
		queue_redraw()

	func _process(delta: float) -> void:
		if not visible:
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var bob := roundf(sin(_t * 5.0) * 1.0)
		var r := Rect2(0, bob, size.x, size.y)
		draw_rect(r.grow(1), UiSkin.SHADOW)
		draw_rect(r, UiSkin.GREEN)
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), UiSkin.GREEN.lightened(0.4))
		draw_string(PixelFont.get_font(), Vector2(3, bob + 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiSkin.NAVY_DEEP)
