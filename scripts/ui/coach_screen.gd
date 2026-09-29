extends Control
## COACH: the skill tree. Every coach level gives a point; spend them on perks (QB time, swipe
## window, aim assist, hands, quick feet, kick zone, coins, card XP). Tap BUY on a tile; RESPEC
## refunds everything for a few coins.

var _ui: Dictionary
var _grid: GridContainer
var _points_l: Label
var _respec: Button


func _ready() -> void:
	_ui = MetaUI.screen(self, "COACH")
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 3)
	_points_l = MetaUI.label("", UiSkin.YELLOW, 8, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_points_l)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 3)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_grid)
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.spacer())
	_respec = MetaUI.button("", Vector2(150, 28), _do_respec)
	nav.add_child(_respec)
	_refresh()


func _refresh() -> void:
	var prof := SaveManager.profile
	MetaUI.clear(_grid)
	var avail := CoachPerks.available(prof)
	_points_l.text = "LEVEL %d  -  %d POINT%s TO SPEND" % [int(prof.coach.get("level", 1)), avail, "" if avail == 1 else "S"]
	_points_l.add_theme_color_override("font_color", UiSkin.YELLOW if avail > 0 else UiSkin.MUTED)
	for perk in CoachPerks.PERKS:
		_grid.add_child(_tile(perk, prof))
	_respec.text = "RESPEC  -%d" % CoachPerks.RESPEC_COST if CoachPerks.has_any(prof) else "NOTHING TO RESET"
	_respec.disabled = not CoachPerks.has_any(prof) or prof.coins < CoachPerks.RESPEC_COST
	(_ui["coins"] as CoinPill).set_coins(prof.coins, false)


func _tile(perk: Dictionary, prof: Profile) -> Control:
	var rank := CoachPerks.rank(prof, perk["id"])
	var mx := int(perk["max"])
	var p := RetroPanel.new("", UiSkin.PANEL, 4)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(MetaUI.label(perk["name"], UiSkin.YELLOW if rank > 0 else UiSkin.WHITE))
	var d := MetaUI.label(perk["desc"], UiSkin.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(150, 0)
	col.add_child(d)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 2)
	for i in mx:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(9, 5)
		r.color = UiSkin.YELLOW if i < rank else UiSkin.STAR_EMPTY
		pips.add_child(r)
	col.add_child(pips)
	var can := CoachPerks.can_buy(prof, perk["id"])
	var label := "MAX" if rank >= mx else "BUY"
	var b: Button = MetaUI.yellow(label, Vector2(40, 22), func() -> void: _buy(perk["id"])) if can \
			else MetaUI.button(label, Vector2(40, 22), func() -> void: pass)
	b.disabled = not can
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return p


func _buy(id: String) -> void:
	var prof := SaveManager.profile
	if CoachPerks.buy(prof, id):
		SaveManager.save()
		Sfx.play("claim")
		_refresh()


func _do_respec() -> void:
	var prof := SaveManager.profile
	if CoachPerks.respec(prof):
		SaveManager.save()
		Sfx.play("coin")
		_refresh()
