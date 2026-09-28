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
	_buttons["dupes"] = MetaUI.button("SELL DUPES", Vector2(74, 19), _confirm_sell_dupes)
	_buttons["dupes"].size_flags_vertical = Control.SIZE_SHRINK_END   # room for the count badge
	_ui["top_right"].add_child(_buttons["dupes"])
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
	for arg in OS.get_cmdline_user_args():   # debug: open a popup for screenshots
		if arg == "--sell-dupes":
			_confirm_sell_dupes.call_deferred()
		elif arg == "--detail" and _grid.get_child_count() > 0:
			_show_detail.call_deferred(_grid.get_child(0))


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
	_refresh_dupes.call_deferred()


func _refresh_dupes() -> void:
	var n: int = EconomyRules.duplicate_plan(SaveManager.profile, GameData.db)["sell_uids"].size()
	MetaUI.badge(_buttons["dupes"], n)


func _confirm_sell_dupes() -> void:
	var prof := SaveManager.profile
	var plan := EconomyRules.duplicate_plan(prof, GameData.db)
	var uids: Array = plan["sell_uids"]
	if uids.is_empty():
		MetaUI.toast(self, "NO SPARE COPIES TO SELL", UiSkin.WHITE)
		return
	Sfx.play("flip")
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.add_child(MetaUI.label("SELL %d SPARE CARD%s OF %d PLAYER%s?" % [uids.size(), "" if uids.size() == 1 else "S",
			int(plan["players"]), "" if int(plan["players"]) == 1 else "S"], UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
	# A peek at what goes (up to 6 cards, best first).
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	var shown: Array = []
	for uid in uids:
		shown.append(prof.find(int(uid)))
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Collection.card_ovr(GameData.db, a) > Collection.card_ovr(GameData.db, b))
	for e in shown.slice(0, 6):
		var v := CardView.new(GameData.card(e["def"]), e, 1)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(v)
	if shown.size() > 6:
		var more := MetaUI.label("+%d
MORE" % (shown.size() - 6), UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER)
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(more)
	body.add_child(row)
	var total := HBoxContainer.new()
	total.alignment = BoxContainer.ALIGNMENT_CENTER
	total.add_theme_constant_override("separation", 4)
	total.add_child(MetaUI.label("+" + CoinPill.fmt(int(plan["coins"])), UiSkin.YELLOW, 16))
	var coin := TextureRect.new()
	coin.texture = UiSkin.coin_tex()
	coin.custom_minimum_size = Vector2(14, 14)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total.add_child(coin)
	body.add_child(total)
	body.add_child(MetaUI.label("YOUR BEST COPY OF EACH PLAYER STAYS.
STARTERS AND LOCKED CARDS ARE NEVER SOLD.", UiSkin.MUTED,
			8, HORIZONTAL_ALIGNMENT_CENTER))
	MetaUI.popup(self, "SELL DUPLICATES", body, [["CANCEL", Callable()],
			["SELL +%s" % CoinPill.fmt(int(plan["coins"])), _sell_dupes, true]])


func _sell_dupes() -> void:
	var prof := SaveManager.profile
	var n: int = EconomyRules.duplicate_plan(prof, GameData.db)["sell_uids"].size()
	var coins := EconomyRules.sell_duplicates(prof, GameData.db)
	if coins <= 0:
		return
	SaveManager.save()
	Sfx.play("claim")
	var pill: CoinPill = _ui["coins"]
	Fx.fly_coins(_ui["layer"], get_viewport_rect().size * 0.5, pill.coin_global(), clampi(n * 2, 8, 20))
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if is_instance_valid(pill):
			pill.set_coins(prof.coins))
	MetaUI.toast(self, "SOLD %d CARD%s  +%s COINS" % [n, "" if n == 1 else "S", CoinPill.fmt(coins)])
	_page = 0
	_refresh()
	pill.set_coins(prof.coins - coins, false)


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
	var copies := 0
	for e in prof.cards:
		var oc: CardDef = GameData.card(e["def"])
		if oc != null and oc.player_id == v.card.player_id:
			copies += 1
	var st := MetaUI.label("STARTER" if starter else "BENCH", UiSkin.GREEN if starter else UiSkin.MUTED)
	if copies > 1:
		st.text += "  -  YOU OWN %d COPIES" % copies
	col.add_child(st)
	# Quick-sell line: value, or why it can't be sold.
	var sell_txt := "QUICK SELL: %s COINS" % CoinPill.fmt(EconomyRules.quicksell_value(GameData.db, v.entry))
	var sell_col := UiSkin.YELLOW
	if starter:
		sell_txt = "STARTERS CAN'T BE SOLD"
		sell_col = UiSkin.MUTED
	elif v.entry["locked"]:
		sell_txt = "LOCKED - UNLOCK TO SELL"
		sell_col = UiSkin.MUTED
	col.add_child(MetaUI.label(sell_txt, sell_col))
	var dupe := _find_dupe(uid)
	var btns: Array = [["CLOSE", Callable()]]
	btns.append(["UNLOCK" if v.entry["locked"] else "LOCK", _toggle_lock.bind(uid)])
	if dupe >= 0 and EconomyRules.can_train(prof, GameData.db, uid, dupe):
		btns.append(["TRAIN (DUPE)", _train.bind(uid, dupe)])
	if not starter and not v.entry["locked"]:
		btns.append(["SELL +%s ●" % CoinPill.fmt(EconomyRules.quicksell_value(GameData.db, v.entry)), _sell.bind(uid), true])
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
