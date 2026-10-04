extends Control
## STORE, laid out like Madden Mobile's: tabs FEATURED (StoreRules: the program pack of the
## week, a daily deal, a bundle of the week, each with a countdown and a purchase limit),
## PACKS (Bronze / Silver / Gold / Pro / Elite), PROGRAMS (Throwback, Hall of Fame, X-Factor,
## Team, Mystery), BUNDLES (several packs for less) and DRAFTS (keep 1 of N). Legends are baked
## into the normal packs (a small chance per card, shown in the odds) and the program packs.
## Tap a pack for its odds; BUY spends the coins and adds the cards in one saved step, then the
## pack opening plays (a draft goes to the pick screen; a bundle's packs open one after another).

static var _tab := 0

const DRAFT := "res://scenes/meta/draft.tscn"
const TILE_W := 86.0
const ART_SCALE := 1.45

var _ui: Dictionary
var _shelf: HBoxContainer
var _tabs: Array[Button] = []
var _timers: Array = []   ## [[Label, ends at (msec), prefix]]


func _ready() -> void:
	_ui = MetaUI.screen(self, "STORE")
	var info := IconButton.new("info", Vector2(24, 22))
	info.pressed.connect(func() -> void: HowToEarn.show(self))
	_ui["top_right"].add_child(info)
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 2)
	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 4)
	root.add_child(tab_row)
	var titles: Array[String] = ["FEATURED"]
	for s in PackCatalog.SHELVES:
		titles.append(str(s[0]))
	for t in titles.size():
		var b := Button.new()
		b.text = titles[t]
		b.theme_type_variation = "PillButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, 18)
		b.pressed.connect(_show_shelf.bind(t))
		tab_row.add_child(b)
		_tabs.append(b)
	_shelf = HBoxContainer.new()
	_shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	_shelf.add_theme_constant_override("separation", 4)
	_shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_shelf)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tab="):   # debug screenshots
			_tab = int(a.get_slice("=", 1))
	_show_shelf(clampi(_tab, 0, titles.size() - 1))
	var hint := HBoxContainer.new()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_theme_constant_override("separation", 6)
	root.add_child(hint)
	var prof := SaveManager.profile
	if EconomyRules.has_pending_draft(prof):
		var finish := MetaUI.yellow("FINISH YOUR DRAFT PICK", Vector2(170, 22), func() -> void:
			SceneRouter.goto(DRAFT, {"back": SceneRouter.STORE}))
		hint.add_child(finish)
		Fx.pulse.call_deferred(finish, 1.06, 0.8)
	elif not prof.pending_packs.is_empty():
		var free := MetaUI.yellow("OPEN YOUR PACKS x%d" % prof.pending_packs.size(), Vector2(150, 22), _open_pending)
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
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_tick)
	add_child(tick)


func _open_pending() -> void:
	var cfg := GameFlow.open_pending_config(SaveManager.profile, SceneRouter.STORE)
	if not cfg.is_empty():
		SceneRouter.goto(cfg["scene"], cfg)


func _show_shelf(index: int) -> void:
	_tab = index
	for t in _tabs.size():
		_tabs[t].set_pressed_no_signal(t == index)
	MetaUI.clear(_shelf)
	_timers.clear()
	var tiles: Array[Control] = []
	if index == 0:
		for offer in StoreRules.featured(int(Time.get_unix_time_from_system())):
			tiles.append(_pack_tile(PackCatalog.get_pack(str(offer["pack"])), offer))
	else:
		for pack in PackCatalog.shelf(index - 1):
			tiles.append(_pack_tile(pack))
	_shelf.add_theme_constant_override("separation", 22 if tiles.size() <= 3 else 3)
	var i := 0
	for tile in tiles:
		_shelf.add_child(tile)
		tile.modulate.a = 0.0
		var tw := tile.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(tile, "modulate:a", 1.0, 0.2)
		i += 1


## One pack on the shelf. `offer` = a FEATURED offer (deal price, limit, countdown) or {}.
func _pack_tile(pack: PackDef, offer: Dictionary = {}) -> Control:
	var prof := SaveManager.profile
	var w := TILE_W * (1.5 if not offer.is_empty() else 1.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(w, 0)
	if not offer.is_empty():
		box.add_child(MetaUI.label(str(offer["kind"]), UiSkin.YELLOW, 8, HORIZONTAL_ALIGNMENT_CENTER))
	var tag := str(offer.get("tag", pack.tag))
	box.add_child(_ribbon(tag, pack))
	var art := _art(pack, ART_SCALE * (0.78 if not offer.is_empty() else 1.0))
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	art.gui_input.connect(func(ev: InputEvent) -> void: _pack_input(ev, pack, offer))
	box.add_child(art)
	var shown := pack.display_name if pack.display_name.length() <= 14 else pack.display_name.trim_suffix(" PACK")
	var name_l := MetaUI.label(shown, pack.color.lightened(0.3), 8, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.custom_minimum_size = Vector2(w, 0)
	name_l.clip_text = true
	box.add_child(name_l)
	var line := _short_line(pack)
	if not offer.is_empty():
		line = line.replace("\n", " · ").trim_suffix(" ·  ")
	box.add_child(MetaUI.label(line, UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER))
	var price := pack.price
	if not offer.is_empty():
		price = int(offer["price"])
		var l := MetaUI.label("", UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
		box.add_child(l)
		_timers.append([l, Time.get_ticks_msec() + int(offer["ends_in"]) * 1000, _offer_note(offer)])
		_set_timer(_timers[-1])
	var left := StoreRules.left(prof, offer) if not offer.is_empty() else -1
	var buy: Button
	if EconomyRules.has_pending_draft(prof):
		buy = MetaUI.button("PICK FIRST", Vector2(w, 22), func() -> void:
			SceneRouter.goto(DRAFT, {"back": SceneRouter.STORE}))
	elif left == 0:
		buy = MetaUI.button("SOLD OUT", Vector2(w, 22), Callable())
		buy.disabled = true
	elif prof.coins >= price:
		buy = MetaUI.yellow("%s ●" % CoinPill.fmt(price), Vector2(w, 22), func() -> void: _buy(pack, offer))
	else:
		buy = MetaUI.button("NEED %s" % CoinPill.fmt(price - prof.coins), Vector2(w, 22),
				func() -> void: MetaUI.toast(self, "WIN GAMES + CLAIM OBJECTIVES FOR COINS", UiSkin.YELLOW))
	box.add_child(buy)
	return box


## "WAS 8,000 · 1 LEFT" style note under a featured offer (before its countdown).
func _offer_note(offer: Dictionary) -> String:
	var parts: Array[String] = []
	if int(offer["list_price"]) > int(offer["price"]):
		parts.append("WAS " + CoinPill.fmt(int(offer["list_price"])))
	var left := StoreRules.left(SaveManager.profile, offer)
	if left > 0:
		parts.append("%d LEFT" % left)
	return (" · ".join(parts) + "\n" if not parts.is_empty() else "") + "ENDS IN "


func _tick() -> void:
	for t in _timers:
		if is_instance_valid(t[0]):
			_set_timer(t)


func _set_timer(t: Array) -> void:
	var secs := maxi(0, (int(t[1]) - Time.get_ticks_msec()) / 1000)
	(t[0] as Label).text = str(t[2]) + StoreRules.time_left_text(secs)


## The colored ribbon over a pack ("NEW", "-30%", "LIMITED", "SAVE 12%"); blank keeps the row.
func _ribbon(tag: String, pack: PackDef) -> Control:
	var text := tag
	if text == "" and not pack.bundle.is_empty():
		var list := PackCatalog.bundle_list_price(pack)
		if list > pack.price:
			text = "SAVE %d%%" % int(round(100.0 * (1.0 - float(pack.price) / list)))
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(TILE_W, 11)
	if text == "":
		return holder
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiSkin.RED if text.begins_with("-") or text == "LIMITED" else (UiSkin.GREEN.darkened(0.25)
			if text.begins_with("SAVE") or text == "BEST VALUE" else UiSkin.YELLOW_DARK)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(MetaUI.label(text, UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
	holder.add_child(p)
	Fx.pulse.call_deferred(p, 1.06, 1.1)
	return holder


## Pack art; a bundle fans out the packs inside it.
func _art(pack: PackDef, art_scale: float) -> Control:
	if pack.bundle.is_empty():
		return PackArt.for_pack(pack, art_scale)
	var ids: Array[String] = []
	for id in pack.bundle:
		if id not in ids:
			ids.append(id)
	while ids.size() < 3:
		ids.push_front(ids[0])
	ids = ids.slice(ids.size() - 3)
	var sz := Vector2(PackArt.W, PackArt.H) * art_scale * 0.82
	var root := Control.new()
	root.custom_minimum_size = Vector2(TILE_W, sz.y + 6)
	for i in 3:
		var a := PackArt.for_pack(PackCatalog.get_pack(ids[i]), art_scale * 0.82)
		a.position = Vector2(TILE_W * 0.5 - sz.x * 0.5 + (i - 1) * 11.0, 6.0 - absf(i - 1) * 4.0)
		a.rotation = (i - 1) * 0.12
		a.pivot_offset = sz * 0.5
		root.add_child(a)
	var n := MetaUI.label("x%d" % pack.bundle.size(), UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_RIGHT)
	n.position = Vector2(TILE_W - 30, -2)
	n.size = Vector2(28, 16)
	root.add_child(n)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	return root


## Two short lines: what's in it ("5 CARDS" / "KEEP 1 OF 3" / "5 PACKS") and its hook
## ("1 GOLD+", "1 LEGEND", "1 X-FACTOR", "LEGENDS 5%", "SAVE 12%"; " " keeps the rows even).
func _short_line(pack: PackDef) -> String:
	var a := "%d CARDS" % pack.card_count
	var b := " "
	if not pack.bundle.is_empty():
		a = "%d PACKS" % pack.bundle.size()
	elif pack.pick:
		a = "KEEP 1 OF %d" % pack.card_count
		if pack.legend_guarantee > 0:
			b = "ALL LEGENDS"
		elif not pack.positions.is_empty():
			b = "/".join(PackedStringArray(Array(pack.positions)))
	elif not pack.mystery.is_empty():
		a = "??? CARDS"
		b = "ANY PACK"
	elif pack.legend_guarantee > 0:
		b = "%d LEGEND" % pack.legend_guarantee
	elif pack.legend_chance >= 0.01:
		b = "LEGENDS %d%%" % int(round(pack.legend_chance * 100.0))
	elif pack.xf_guarantee > 0 and pack.guarantee_tier < 2:
		b = "1 X-FACTOR"
	elif pack.guarantee_tier >= 0:
		b = "1 %s+" % CardRules.NAMES[pack.guarantee_tier]
	return a + "\n" + b


func _pack_input(ev: InputEvent, pack: PackDef, offer: Dictionary) -> void:
	var tap: bool = (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed)
	if tap:
		Sfx.play("tap")
		_show_odds(pack, offer)


func _show_odds(pack: PackDef, offer: Dictionary = {}) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	if pack.blurb != "":
		col.add_child(MetaUI.label(pack.blurb, UiSkin.YELLOW))
	col.add_child(MetaUI.label(PackCatalog.summary(pack), UiSkin.MUTED))
	if not pack.eras.is_empty():
		col.add_child(MetaUI.label("LEGENDS FROM: " + ", ".join(PackedStringArray(Array(pack.eras))), UiSkin.MUTED))
	var lines := PackCatalog.odds_lines(pack)
	if not pack.mystery.is_empty():
		# Mystery: odds of which pack it turns out to be.
		lines = []
		for i in pack.mystery.size():
			var mp := PackCatalog.get_pack(pack.mystery[i])
			lines.append([mp.display_name if mp != null else pack.mystery[i], int(round(pack.mystery_weights[i] * 100.0))])
	if not pack.bundle.is_empty():
		var list := PackCatalog.bundle_list_price(pack)
		col.add_child(MetaUI.label("ONE AT A TIME: %s   BUNDLE: %s" % [CoinPill.fmt(list),
				CoinPill.fmt(int(offer.get("price", pack.price)))], UiSkin.WHITE))
		col.add_child(MetaUI.label("THE PACKS GO TO YOUR QUEUE AND OPEN ONE AFTER ANOTHER", UiSkin.MUTED))
	for l in lines:
		var h := HBoxContainer.new()
		var t: int = CardRules.NAMES.find(l[0])
		var lc: Color = CardRules.PROGRAM_COLORS["legend"] if l[0] == "LEGEND" else CardView.tier_color(maxi(t, 0))
		var a := MetaUI.label(str(l[0]), lc.lightened(0.2))
		a.custom_minimum_size = Vector2(120, 0)
		h.add_child(a)
		var bar := BarMeter.new(float(l[1]) / 100.0, Vector2(100, 8), lc)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		var pct := float(l[1])
		h.add_child(MetaUI.label("  %s%%" % (str(snappedf(pct, 0.1)) if pct < 1.0 else str(int(round(pct)))), UiSkin.WHITE))
		col.add_child(h)
	var btns: Array = [["CLOSE", Callable()]]
	var price := int(offer.get("price", pack.price))
	var ok := StoreRules.can_buy(SaveManager.profile, offer) if not offer.is_empty() \
			else EconomyRules.can_buy(SaveManager.profile, pack)
	if ok and not EconomyRules.has_pending_draft(SaveManager.profile):
		btns.append(["BUY %s" % CoinPill.fmt(price), func() -> void: _buy(pack, offer), true])
	var title := pack.display_name + (" - WHICH PACK?" if not pack.mystery.is_empty() else
			(" - CONTENTS" if not pack.bundle.is_empty() else " ODDS PER CARD"))
	MetaUI.popup(self, title, col, btns)


func _buy(pack: PackDef, offer: Dictionary = {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var now := int(Time.get_unix_time_from_system())
	var r := StoreRules.buy(SaveManager.profile, offer, GameData.db, rng, now) if not offer.is_empty() \
			else EconomyRules.buy(SaveManager.profile, pack, GameData.db, rng, now)
	if r.is_empty():
		return
	SaveManager.save()
	Sfx.play("coin")
	if r.get("bundle", false):
		_open_pending()
		return
	if r["draft"]:
		SceneRouter.goto(DRAFT, {"back": SceneRouter.STORE})
		return
	var real: PackDef = r["pack"]
	var cfg := {"uids": r["uids"], "title": real.display_name, "pack": real.id, "back": SceneRouter.STORE}
	if r["mystery"]:
		cfg["mystery"] = pack.id
	SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)
