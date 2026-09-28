extends Control
## LINEUP: your 19 starters (offense, defense, kicker). Tap a slot to pick from the cards
## that fit it; AUTO-BEST fills every slot with your highest OVR cards.

var _ui: Dictionary
var _slots: GridContainer
var _picker: PanelContainer
var _ovr: Label


func _ready() -> void:
	_ui = MetaUI.screen(self, "LINEUP")
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_ui["root"].add_child(bar)
	_ovr = MetaUI.label("", UiTheme.ACCENT)
	_ovr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_ovr)
	bar.add_child(MetaUI.button("AUTO-BEST", Vector2(90, 24), func() -> void:
		Collection.auto_lineup(SaveManager.profile, GameData.db)
		SaveManager.save()
		_refresh()))
	var sc := MetaUI.scroll(_ui["root"])
	_slots = GridContainer.new()
	_slots.columns = 2
	_slots.add_theme_constant_override("h_separation", 6)
	_slots.add_theme_constant_override("v_separation", 3)
	sc.add_child(_slots)
	_picker = PanelContainer.new()
	_picker.visible = false
	add_child(_picker)
	_refresh()


func _refresh() -> void:
	var prof := SaveManager.profile
	var entries := Collection.lineup_entries(prof, GameData.db)
	_ovr.text = "TEAM OVR %d   ·   CHEMISTRY +%.1f" % [Collection.team_ovr(prof, GameData.db),
			Collection.chemistry(prof, GameData.db)]
	for c in _slots.get_children():
		_slots.remove_child(c)
		c.queue_free()
	for slot in TeamRating.ALL_SLOTS:
		var e: Dictionary = entries.get(slot, {})
		var text := "%-4s %s" % [slot, "- EMPTY -" if e.is_empty() else "%d  %s" % [e["ovr"], e["name"]]]
		var b := MetaUI.button(text, Vector2(224, 24), func() -> void: _open_picker(slot))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_slots.add_child(b)


func _open_picker(slot: String) -> void:
	for c in _picker.get_children():
		_picker.remove_child(c)
		c.queue_free()
	var prof := SaveManager.profile
	var pos := TeamRating.slot_pos(slot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_picker.add_child(col)
	col.add_child(MetaUI.label("PICK %s" % slot, UiTheme.ACCENT))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(260, 170)
	col.add_child(sc)
	var list := VBoxContainer.new()
	sc.add_child(list)
	var cands: Array = []
	for e in prof.cards:
		var c: CardDef = GameData.card(e["def"])
		if c != null and GameData.player(c.player_id).pos == pos:
			cands.append([c.ovr + int(e["boost"]), e, c])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for item in cands:
		var e: Dictionary = item[1]
		var c: CardDef = item[2]
		var p: PlayerData = GameData.player(c.player_id)
		var uid := int(e["uid"])
		var where := ""
		for s in prof.lineup:
			if int(prof.lineup[s]) == uid:
				where = "  (%s)" % s
		var b := MetaUI.button("%d  %s  %s%s" % [item[0], p.short_name(), CardRules.NAMES[c.tier], where],
				Vector2(250, 24), func() -> void: _assign(slot, uid))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	col.add_child(MetaUI.button("CANCEL", Vector2(250, 24), func() -> void: _picker.visible = false))
	_picker.visible = true
	_picker.reset_size()
	_picker.position = (get_viewport_rect().size - _picker.get_combined_minimum_size()) * 0.5


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
	_picker.visible = false
	_refresh()
