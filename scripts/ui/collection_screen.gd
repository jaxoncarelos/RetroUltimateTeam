extends Control
## COLLECTION: every card you own. Filter by tier / position / team, sorted by OVR.
## Tap a card for details: quick-sell, train with a duplicate, lock.

const POS_FILTERS := ["ALL", "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]
const TIER_FILTERS := ["ALL", "BRONZE", "SILVER", "GOLD", "ELITE"]

var _ui: Dictionary
var _grid: GridContainer
var _detail: PanelContainer
var _pos := 0
var _tier := 0
var _franchise_only := false
var _buttons: Dictionary = {}


func _ready() -> void:
	_ui = MetaUI.screen(self, "COLLECTION")
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 4)
	_ui["root"].add_child(filters)
	_buttons["pos"] = MetaUI.button("POS: ALL", Vector2(80, 20), func() -> void:
		_pos = (_pos + 1) % POS_FILTERS.size()
		_refresh())
	_buttons["tier"] = MetaUI.button("TIER: ALL", Vector2(96, 20), func() -> void:
		_tier = (_tier + 1) % TIER_FILTERS.size()
		_refresh())
	_buttons["team"] = MetaUI.button("TEAM: ALL", Vector2(110, 20), func() -> void:
		_franchise_only = not _franchise_only
		_refresh())
	for k in ["pos", "tier", "team"]:
		filters.add_child(_buttons[k])
	_buttons["count"] = MetaUI.label("", UiTheme.DIM)
	filters.add_child(_buttons["count"])
	var sc := MetaUI.scroll(_ui["root"])
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 5)
	_grid.add_theme_constant_override("v_separation", 5)
	sc.add_child(_grid)
	_detail = PanelContainer.new()
	_detail.visible = false
	_detail.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_detail)
	_refresh()


func _refresh() -> void:
	_buttons["pos"].text = "POS: %s" % POS_FILTERS[_pos]
	_buttons["tier"].text = "TIER: %s" % TIER_FILTERS[_tier]
	_buttons["team"].text = "TEAM: %s" % (SaveManager.profile.franchise_team if _franchise_only else "ALL")
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var prof := SaveManager.profile
	var list: Array = []
	for e in prof.cards:
		var c: CardDef = GameData.card(e["def"])
		if c == null:
			continue
		var p: PlayerData = GameData.player(c.player_id)
		if _pos > 0 and p.pos != POS_FILTERS[_pos]:
			continue
		if _tier > 0 and c.tier != _tier - 1:
			continue
		if _franchise_only and p.team != prof.franchise_team:
			continue
		list.append([c.ovr + int(e["boost"]), e, c])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	_buttons["count"].text = "%d CARDS" % list.size()
	for item in list:
		var v := CardView.new(item[2], item[1], 1)
		v.tapped.connect(_show_detail)
		_grid.add_child(v)
	_ui["coins"].text = "%d COINS" % prof.coins


func _show_detail(v: CardView) -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var prof := SaveManager.profile
	var uid := int(v.entry["uid"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail.add_child(row)
	row.add_child(CardView.new(v.card, v.entry, 2))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var p: PlayerData = v.player
	var a := CardRules.card_attrs(p.attrs, p.ovr, v.card.ovr, int(v.entry["boost"]))
	col.add_child(MetaUI.label("%s  #%d  %s" % [p.name.to_upper(), p.jersey, p.team], UiTheme.ACCENT))
	col.add_child(MetaUI.label("SPD %d  ACC %d  STR %d  AWR %d" % [a["spd"], a["acc"], a["str"], a["awr"]]))
	col.add_child(MetaUI.label(_key_attrs(p.pos, a)))
	var in_lineup := prof.in_lineup(uid)
	col.add_child(MetaUI.label("STARTER" if in_lineup else "BENCH", UiTheme.DIM))
	var sell := MetaUI.button("QUICK SELL +%d" % EconomyRules.quicksell_value(GameData.db, v.entry), Vector2(150, 22),
			func() -> void:
				if EconomyRules.quicksell(prof, GameData.db, uid) > 0:
					Sfx.play("coin")
					SaveManager.save()
				_detail.visible = false
				_refresh())
	sell.disabled = in_lineup or v.entry["locked"]
	col.add_child(sell)
	var dupe := _find_dupe(uid)
	var train := MetaUI.button("TRAIN WITH DUPLICATE (+1)", Vector2(150, 22), func() -> void:
		if EconomyRules.train(prof, GameData.db, uid, dupe):
			Sfx.play("big")
			SaveManager.save()
		_detail.visible = false
		_refresh())
	train.disabled = dupe < 0 or int(v.entry["boost"]) >= EconomyRules.MAX_BOOST
	col.add_child(train)
	col.add_child(MetaUI.button("UNLOCK" if v.entry["locked"] else "LOCK", Vector2(150, 22), func() -> void:
		prof.find(uid)["locked"] = not prof.find(uid)["locked"]
		SaveManager.save()
		_detail.visible = false
		_refresh()))
	col.add_child(MetaUI.button("CLOSE", Vector2(150, 22), func() -> void: _detail.visible = false))
	_detail.visible = true
	_detail.reset_size()
	_detail.position = (get_viewport_rect().size - _detail.get_combined_minimum_size()) * 0.5


## Another copy of the same player that can be fed in (not locked, not starting).
func _find_dupe(uid: int) -> int:
	var prof := SaveManager.profile
	var target: CardDef = GameData.card(prof.find(uid)["def"])
	for e in prof.cards:
		if int(e["uid"]) == uid or e["locked"] or prof.in_lineup(int(e["uid"])):
			continue
		var c: CardDef = GameData.card(e["def"])
		if c != null and c.player_id == target.player_id:
			return int(e["uid"])
	return -1


static func _key_attrs(pos: String, a: Dictionary) -> String:
	match pos:
		"QB":
			return "THP %d  THA %d" % [a["thp"], a["tha"]]
		"RB", "WR", "TE":
			return "CTH %d  RTE %d  ELU %d  CAR %d" % [a["cth"], a["rte"], a["elu"], a["car"]]
		"OL":
			return "BLK %d" % a["blk"]
		"DL", "LB":
			return "TAK %d  PRS %d  COV %d" % [a["tak"], a["prs"], a["cov"]]
		"CB", "S":
			return "COV %d  TAK %d  CTH %d" % [a["cov"], a["tak"], a["cth"]]
		"K":
			return "KPW %d  KAC %d" % [a["kpw"], a["kac"]]
	return ""
