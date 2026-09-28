extends Control
## SQUAD (Retro Bowl roster style): pages of 5x2 cards with arrows, "CARDS n / m", filters
## (position / tier / franchise) in the bottom nav, OFFENSE / DEFENSE stars. Starters have
## a yellow outline. Tap a card for its detail: big card, ratings, development (potential +
## XP bar), quick sell, train with a duplicate, lock.

const POS_FILTERS := ["ALL", "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]
const TIER_FILTERS := ["ALL", "BRONZE", "SILVER", "GOLD", "ELITE"]
const PER_PAGE := 10

var _ui: Dictionary
var _grid: GridContainer
var _count: Label
var _page := 0
var _pos := 0
var _tier := 0
var _franchise_only := false
var _buttons: Dictionary = {}
var _list: Array = []


func _ready() -> void:
	var team: TeamData = GameData.team(SaveManager.profile.franchise_team)
	_ui = MetaUI.screen(self, team.team_name.to_upper() if team != null else "SQUAD")
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 3)
	_count = MetaUI.label("", UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_count)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	root.add_child(row)
	var prev := IconButton.new("back", Vector2(24, 40))
	prev.pressed.connect(func() -> void: _turn(-1))
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(prev)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 6)
	center.add_child(_grid)
	var next := IconButton.new("play", Vector2(24, 40))
	next.pressed.connect(func() -> void: _turn(1))
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(next)
	var nav: HBoxContainer = _ui["nav"]
	_buttons["pos"] = MetaUI.nav_button("POS: ALL", _cycle.bind("pos"), 62)
	_buttons["tier"] = MetaUI.nav_button("TIER: ALL", _cycle.bind("tier"), 70)
	_buttons["team"] = MetaUI.nav_button("ALL TEAMS", _cycle.bind("team"), 70)
	for k in ["pos", "tier", "team"]:
		nav.add_child(_buttons[k])
	nav.add_child(MetaUI.nav_button("LINEUP", func() -> void: SceneRouter.goto(SceneRouter.LINEUP), 60))
	var ss := MetaUI.side_stars(Collection.lineup_entries(SaveManager.profile, GameData.db))
	nav.add_child(MetaUI.stat_box("OFFENSE", MetaUI.stars(ss["off"], UiSkin.STAR_BLUE), Vector2(62, 28)))
	nav.add_child(MetaUI.stat_box("DEFENSE", MetaUI.stars(ss["def"], UiSkin.STAR_RED), Vector2(62, 28)))
	_refresh()


func _cycle(which: String) -> void:
	match which:
		"pos":
			_pos = (_pos + 1) % POS_FILTERS.size()
		"tier":
			_tier = (_tier + 1) % TIER_FILTERS.size()
		"team":
			_franchise_only = not _franchise_only
	_page = 0
	_refresh()


func _turn(d: int) -> void:
	var pages := maxi(1, ceili(_list.size() / float(PER_PAGE)))
	_page = (_page + d + pages) % pages
	Sfx.play("swoosh")
	_refresh()


func _refresh() -> void:
	_buttons["pos"].text = "POS: %s" % POS_FILTERS[_pos]
	_buttons["tier"].text = "TIER: %s" % TIER_FILTERS[_tier]
	_buttons["team"].text = SaveManager.profile.franchise_team + " ONLY" if _franchise_only else "ALL TEAMS"
	MetaUI.clear(_grid)
	var prof := SaveManager.profile
	_list = []
	for e in prof.cards:
		var c: CardDef = GameData.card(e["def"])
		if c == null:
			continue
		var p: PlayerData = GameData.player(c.player_id)
		if _pos > 0 and p.pos != POS_FILTERS[_pos]:
			continue
		if _tier > 0 and Collection.card_tier(GameData.db, e) != _tier - 1:
			continue
		if _franchise_only and p.team != prof.franchise_team:
			continue
		_list.append([Collection.card_ovr(GameData.db, e), e, c])
	_list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var pages := maxi(1, ceili(_list.size() / float(PER_PAGE)))
	_page = clampi(_page, 0, pages - 1)
	_count.text = "CARDS %d / %d   -   PAGE %d / %d" % [_list.size(), prof.cards.size(), _page + 1, pages]
	var i := 0
	for item in _list.slice(_page * PER_PAGE, (_page + 1) * PER_PAGE):
		var v := CardView.new(item[2], item[1], 1)
		v.selected = prof.in_lineup(int(item[1]["uid"]))
		v.tapped.connect(_show_detail)
		_grid.add_child(v)
		v.modulate.a = 0.0
		var tw := v.create_tween()
		tw.tween_interval(0.025 * i)
		tw.tween_property(v, "modulate:a", 1.0, 0.12)
		i += 1
	(_ui["coins"] as CoinPill).set_coins(prof.coins)


func _show_detail(v: CardView) -> void:
	Sfx.play("flip")
	var prof := SaveManager.profile
	var uid := int(v.entry["uid"])
	var info := Collection.card_info(prof, GameData.db, v.entry)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var big := CardView.new(v.card, v.entry, 2)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(big)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(200, 0)
	row.add_child(col)
	var p: PlayerData = v.player
	col.add_child(MetaUI.label(p.name.to_upper(), UiSkin.YELLOW, 8))
	col.add_child(MetaUI.label("%s  #%d  %s  AGE %d" % [p.pos, p.jersey, p.team, int(info.get("age", 0))], UiSkin.MUTED))
	var a := CardRules.card_attrs(p.attrs, p.ovr, int(info.get("ovr", v.ovr())))
	for pair in _key_attrs(p.pos, a):
		var h := HBoxContainer.new()
		var l := MetaUI.label(pair[0], UiSkin.WHITE)
		l.custom_minimum_size = Vector2(66, 0)
		h.add_child(l)
		var bar := BarMeter.new(clampf((float(pair[1]) - 40.0) / 59.0, 0.0, 1.0), Vector2(100, 7))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		h.add_child(MetaUI.label(" %d" % int(pair[1]), UiSkin.WHITE))
		col.add_child(h)
	if info.get("prospect", false):
		var dh := HBoxContainer.new()
		dh.add_child(MetaUI.label("POT %d  " % int(info["pot"]), UiSkin.GREEN))
		var xb := BarMeter.new(float(info["xp"]) / maxf(float(info["xp_next"]), 1.0), Vector2(90, 7), UiSkin.GREEN)
		xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dh.add_child(xb)
		dh.add_child(MetaUI.label(" XP", UiSkin.MUTED))
		col.add_child(dh)
	else:
		col.add_child(MetaUI.label("FULLY DEVELOPED", UiSkin.MUTED))
	var starter: bool = info.get("in_lineup", false)
	col.add_child(MetaUI.label("STARTER" if starter else "BENCH", UiSkin.GREEN if starter else UiSkin.MUTED))
	var dupe := _find_dupe(uid)
	var btns: Array = [["CLOSE", Callable()]]
	btns.append(["UNLOCK" if v.entry["locked"] else "LOCK", _toggle_lock.bind(uid)])
	if dupe >= 0 and EconomyRules.can_train(prof, GameData.db, uid, dupe):
		btns.append(["TRAIN (DUPE)", _train.bind(uid, dupe)])
	if not starter and not v.entry["locked"]:
		btns.append(["SELL +%d" % EconomyRules.quicksell_value(GameData.db, v.entry), _sell.bind(uid), true])
	MetaUI.popup(self, "PLAYER CARD", row, btns)


func _toggle_lock(uid: int) -> void:
	var e := SaveManager.profile.find(uid)
	e["locked"] = not e["locked"]
	SaveManager.save()
	_refresh()


func _train(uid: int, dupe: int) -> void:
	if EconomyRules.train(SaveManager.profile, GameData.db, uid, dupe):
		Sfx.play("levelup")
		SaveManager.save()
		MetaUI.toast(self, "TRAINED! +1 OVR")
	_refresh()


func _sell(uid: int) -> void:
	if EconomyRules.quicksell(SaveManager.profile, GameData.db, uid) > 0:
		Sfx.play("claim")
		SaveManager.save()
		Fx.fly_coins(_ui["layer"], get_viewport_rect().size * 0.5, (_ui["coins"] as CoinPill).coin_global(), 8)
	_refresh()


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


static func _key_attrs(pos: String, a: Dictionary) -> Array:
	var keys: Array = ["spd", "acc", "str", "awr"]
	match pos:
		"QB":
			keys = ["thp", "tha", "awr", "spd"]
		"RB":
			keys = ["spd", "elu", "car", "cth"]
		"WR", "TE":
			keys = ["spd", "cth", "rte", "elu"]
		"OL":
			keys = ["blk", "str", "awr"]
		"DL", "LB":
			keys = ["tak", "prs", "str", "spd"]
		"CB", "S":
			keys = ["cov", "spd", "tak", "cth"]
		"K":
			keys = ["kpw", "kac"]
	var names := {"spd": "SPEED", "acc": "ACCEL", "str": "STRENGTH", "awr": "AWARE", "thp": "THROW PWR",
			"tha": "THROW ACC", "elu": "ELUSIVE", "car": "CARRY", "cth": "CATCH", "rte": "ROUTES", "blk": "BLOCK",
			"tak": "TACKLE", "prs": "PASS RUSH", "cov": "COVERAGE", "kpw": "KICK PWR", "kac": "KICK ACC"}
	var out: Array = []
	for k in keys:
		out.append([names[k], int(a.get(k, 60))])
	return out
