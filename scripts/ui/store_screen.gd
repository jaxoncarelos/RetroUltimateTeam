extends Control
## STORE: a shelf of foil packs (Bronze / Silver / Gold / Elite). Tap a pack for its odds;
## BUY spends the coins and adds the cards in one saved step, then the pack opening plays.
## Unaffordable packs say how many coins are missing and point to objectives.

var _ui: Dictionary


func _ready() -> void:
	_ui = MetaUI.screen(self, "STORE")
	var info := IconButton.new("info", Vector2(24, 22))
	info.pressed.connect(func() -> void: HowToEarn.show(self))
	_ui["top_right"].add_child(info)
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 2)
	var shelf := HBoxContainer.new()
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf.add_theme_constant_override("separation", 14)
	shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(shelf)
	var i := 0
	for pack in PackCatalog.store_packs():
		var tile := _pack_tile(pack)
		shelf.add_child(tile)
		tile.modulate.a = 0.0
		var tw := tile.create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_property(tile, "modulate:a", 1.0, 0.2)
		i += 1
	var hint := HBoxContainer.new()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_theme_constant_override("separation", 6)
	root.add_child(hint)
	var prof := SaveManager.profile
	if not prof.pending_packs.is_empty():
		var open_free := func() -> void:
			var cfg := GameFlow.open_pending_config(prof, SceneRouter.STORE)
			if not cfg.is_empty():
				SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)
		var free := MetaUI.yellow("OPEN FREE PACK x%d" % prof.pending_packs.size(), Vector2(150, 22), open_free)
		hint.add_child(free)
		Fx.pulse.call_deferred(free, 1.06, 0.8)
	else:
		hint.add_child(MetaUI.label("NEED COINS? WIN GAMES AND CLAIM OBJECTIVES", UiSkin.MUTED))
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.nav_button("SQUAD", func() -> void: SceneRouter.goto(SceneRouter.SQUAD)))
	nav.add_child(MetaUI.nav_button("SETS", func() -> void: SceneRouter.goto("res://scenes/meta/sets.tscn")))
	var ob := MetaUI.nav_button("OBJECTIVES", func() -> void: SceneRouter.goto(SceneRouter.OBJECTIVES), 76)
	nav.add_child(ob)
	MetaUI.badge.call_deferred(ob, ObjectiveRules.claimable_count(prof))


func _pack_tile(pack: PackDef) -> Control:
	var prof := SaveManager.profile
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var art := PackArt.for_pack(pack, 2.0)
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	art.gui_input.connect(func(ev: InputEvent) -> void: _pack_input(ev, pack))
	box.add_child(art)
	box.add_child(MetaUI.label(pack.display_name, pack.color.lightened(0.3), 8, HORIZONTAL_ALIGNMENT_CENTER))
	var g := "%d CARDS" % pack.card_count
	if pack.guarantee_tier >= 0:
		g += " - 1 %s+" % CardRules.NAMES[pack.guarantee_tier]
	box.add_child(MetaUI.label(g, UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER))
	var buy: Button
	if EconomyRules.can_buy(prof, pack):
		buy = MetaUI.yellow("%s ●" % CoinPill.fmt(pack.price), Vector2(96, 24), func() -> void: _buy(pack))
	else:
		buy = MetaUI.button("NEED %s" % CoinPill.fmt(pack.price - prof.coins), Vector2(96, 24),
				func() -> void: MetaUI.toast(self, "WIN GAMES + CLAIM OBJECTIVES FOR COINS", UiSkin.YELLOW))
	box.add_child(buy)
	return box


func _pack_input(ev: InputEvent, pack: PackDef) -> void:
	var tap: bool = (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed)
	if tap:
		Sfx.play("tap")
		_show_odds(pack)


func _show_odds(pack: PackDef) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(MetaUI.label(PackCatalog.summary(pack), UiSkin.MUTED))
	for l in PackCatalog.odds_lines(pack):
		var h := HBoxContainer.new()
		var t: int = CardRules.NAMES.find(l[0])
		var a := MetaUI.label(str(l[0]), CardView.tier_color(maxi(t, 0)).lightened(0.2))
		a.custom_minimum_size = Vector2(120, 0)
		h.add_child(a)
		var bar := BarMeter.new(float(l[1]) / 100.0, Vector2(100, 8), CardView.tier_color(maxi(t, 0)))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		h.add_child(MetaUI.label("  %d%%" % int(l[1]), UiSkin.WHITE))
		col.add_child(h)
	var btns: Array = [["CLOSE", Callable()]]
	if EconomyRules.can_buy(SaveManager.profile, pack):
		btns.append(["BUY %s" % CoinPill.fmt(pack.price), func() -> void: _buy(pack), true])
	MetaUI.popup(self, pack.display_name + " ODDS PER CARD", col, btns)


func _buy(pack: PackDef) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var uids := EconomyRules.buy_and_open(SaveManager.profile, pack, GameData.db, rng,
			int(Time.get_unix_time_from_system()))
	if uids.is_empty():
		return
	SaveManager.save()
	Sfx.play("coin")
	SceneRouter.goto(SceneRouter.PACK_OPEN, {"uids": uids, "title": pack.display_name, "pack": pack.id,
			"back": SceneRouter.STORE})
