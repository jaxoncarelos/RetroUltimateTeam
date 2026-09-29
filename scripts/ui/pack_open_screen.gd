extends Control
## Pack opening, FIFA style. The pack slides in and waits; a tap makes it rattle, tear
## open with a flash and a burst of light. The best card gets a "walkout": the screen
## darkens, spotlights sweep in the tier color, then its position, team (helmet + colors)
## and OVR are revealed one by one before the card flips in with particles, glow and a
## screen shake scaled to its rarity (90+ = fireworks). Then every card is dealt into a
## summary grid (NEW / duplicate + quick-sell value) with QUICK SELL DUPES, OPEN ANOTHER
## and CONTINUE. SKIP jumps to the summary at any time. The cards were already saved when
## the pack was granted, so leaving early loses nothing.

enum Step { INTRO, TEARING, WALKOUT, REVEALED, SUMMARY }

var step := Step.INTRO
var _next := 0                     ## cards revealed so far (summary)
var _back := SceneRouter.HUB
var _pack: PackDef
var _title := "PACK"
var _entries: Array = []           ## owned-card entries, best first
var _dupe: Dictionary = {}         ## uid -> true when you already owned that card
var _skip := false
var _prof: Profile

var _content: Control
var _stage: _Stage
var _dark: ColorRect
var _pack_art: PackArt
var _prompt: Label
var _skip_btn: Button
var _coins: CoinPill
var _sell_btn: Button
var _walk_nodes: Array[Node] = []
var _hero: CardView
var _summary: Control
var _grid: HBoxContainer
var _cards: Array[CardView] = []
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var cfg := SceneRouter.take_config()
	_prof = SaveManager.profile
	_back = cfg.get("back", _back)
	_title = cfg.get("title", "PACK")
	_pack = PackCatalog.get_pack(str(cfg.get("pack", ""))) if cfg.has("pack") else null
	var uids: Array = cfg.get("uids", [])
	var owned_before := {}
	for e in _prof.cards:
		if int(e["uid"]) not in uids:
			owned_before[e["def"]] = true
	for uid in uids:
		var e := _prof.find(int(uid))
		if e.is_empty() or GameData.card(e.get("def", "")) == null:
			continue
		_entries.append(e)
		_dupe[int(uid)] = owned_before.has(e["def"])
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Collection.card_ovr(GameData.db, a) > Collection.card_ovr(GameData.db, b))
	_build()
	_intro.call_deferred()


func _build() -> void:
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	var bg := RetroBg.new()
	bg.header_line = 0
	bg.footer_line = 0
	bg.tint = Color(0.55, 0.55, 0.7)
	_content.add_child(bg)
	_stage = _Stage.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.color = _pack.color if _pack != null else UiSkin.YELLOW
	_content.add_child(_stage)
	_dark = ColorRect.new()
	_dark.color = Color(0.0, 0.01, 0.05, 0.0)
	_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_dark)
	var head := TitleBar.new(_title)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = 26
	_content.add_child(head)
	_coins = CoinPill.new(_prof.coins)
	_coins.position = Vector2(6 + SafeArea.left(), 6 + SafeArea.top())
	add_child(_coins)
	var pc := _pack.color if _pack != null else CardView.tier_color(_best_tier())
	_pack_art = PackArt.new(pc, _title.replace(" PACK", ""), 3.0)
	_pack_art.size = Vector2(PackArt.W, PackArt.H) * 3.0
	_content.add_child(_pack_art)
	_prompt = MetaUI.label("TAP TO OPEN", UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -100
	_prompt.offset_right = 100
	_prompt.offset_top = -18 - SafeArea.bottom()
	_prompt.offset_bottom = -8 - SafeArea.bottom()
	add_child(_prompt)
	_skip_btn = MetaUI.button("SKIP ▶", Vector2(56, 20), _flip_all)
	_skip_btn.theme_type_variation = "PillButton"
	_skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_btn.offset_left = -62 - SafeArea.right()
	_skip_btn.offset_right = -6 - SafeArea.right()
	_skip_btn.offset_top = 5 + SafeArea.top()
	_skip_btn.offset_bottom = 25 + SafeArea.top()
	add_child(_skip_btn)


func _best_tier() -> int:
	return Collection.card_tier(GameData.db, _entries[0]) if not _entries.is_empty() else 0


func _best_ovr() -> int:
	return Collection.card_ovr(GameData.db, _entries[0]) if not _entries.is_empty() else 0


func _vp() -> Vector2:
	return get_viewport_rect().size


func _process(delta: float) -> void:
	_t += delta
	if step in [Step.INTRO, Step.REVEALED]:
		_prompt.modulate.a = 1.0 if fmod(_t, 1.0) < 0.65 else 0.2
	if step == Step.INTRO and _pack_art != null:
		_pack_art.position.y = _pack_rest().y + sin(_t * 2.2) * 3.0


func _pack_rest() -> Vector2:
	return ((_vp() - _pack_art.size) * 0.5).round() + Vector2(0, 8)


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if not tap:
		return
	accept_event()
	match step:
		Step.INTRO:
			_open()
		Step.REVEALED:
			_show_summary()


# ---------------------------------------------------------------- intro / tear

func _intro() -> void:
	if _entries.is_empty():
		_show_summary()
		return
	_pack_art.position = Vector2(_pack_rest().x, _vp().y + 10)
	_stage.rays = 0.35
	var tw := create_tween()
	tw.tween_property(_pack_art, "position:y", _pack_rest().y, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("whoosh")
	if OS.get_cmdline_user_args().has("--auto-open"):
		# Debug / screenshots: open by itself, then show the summary.
		await _wait(0.9)
		if step == Step.INTRO:
			_open()
		while step != Step.REVEALED and step != Step.SUMMARY:
			await _wait(0.2)
		await _wait(1.6)
		_show_summary()


func _open() -> void:
	step = Step.TEARING
	_prompt.text = ""
	var tier := _best_tier()
	Sfx.play("rumble")
	var tw := create_tween().set_parallel()
	tw.tween_property(_pack_art, "shake", 1.0, 0.7)
	tw.tween_property(_pack_art, "glow", 1.0, 0.7)
	tw.tween_property(_stage, "rays", 0.8, 0.7)
	for i in 4:
		get_tree().create_timer(0.15 * i).timeout.connect(func() -> void:
			if step == Step.TEARING and is_instance_valid(_pack_art):
				var side := Vector2(randf_range(0, _pack_art.size.x), randf_range(0, _pack_art.size.y))
				Fx.burst(_content, _pack_art.position + side, _pack_art.color.lightened(0.4), 6, 50.0, 0.4, 1.0))
	await get_tree().create_timer(0.72).timeout
	if _skip:
		return
	Sfx.play("tear")
	var t2 := create_tween()
	t2.tween_property(_pack_art, "tear", 1.0, 0.18)
	await t2.finished
	if _skip:
		return
	Fx.flash(self, Color(1, 1, 0.9, 0.85), 0.45)
	var center := _pack_art.position + _pack_art.size * 0.5
	Fx.burst(_content, center, CardView.tier_color(tier).lightened(0.3), 40 + tier * 20, 160.0, 0.9, 2.0, 60.0)
	Fx.burst(_content, center, Color.WHITE, 20, 90.0, 0.5, 1.0)
	var t3 := create_tween().set_parallel()
	t3.tween_property(_pack_art, "position:y", -_pack_art.size.y - 20, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t3.tween_property(_pack_art, "modulate:a", 0.0, 0.35)
	await t3.finished
	if _skip:
		return
	_walkout()


# ---------------------------------------------------------------- walkout

func _walkout() -> void:
	step = Step.WALKOUT
	var e: Dictionary = _entries[0]
	var card: CardDef = GameData.card(e["def"])
	var p: PlayerData = GameData.player(card.player_id)
	var team: TeamData = GameData.team(p.team)
	var tier := _best_tier()
	var ovr := _best_ovr()
	var tc := CardView.tier_color(tier)
	var big := tier >= CardRules.Tier.GOLD
	_stage.color = tc
	var tw := create_tween().set_parallel()
	tw.tween_property(_dark, "color:a", 0.82 if big else 0.55, 0.35)
	tw.tween_property(_stage, "spot", 1.0, 0.6)
	tw.tween_property(_stage, "rays", 0.5 if big else 0.3, 0.6)
	if big:
		Sfx.play("walkout")
		# 1) Position.
		await _wait(0.55)
		if _skip:
			return
		var pos := _big_text(p.pos, 5, tc)
		_slam(pos, Vector2(0, -18))
		await _wait(0.9)
		if _skip:
			return
		_fade_out(pos)
		# 2) Team: colored bands sweep in + the helmet slides to the center.
		var bands := _TeamBands.new()
		bands.primary = team.primary if team != null else tc
		bands.secondary = team.secondary if team != null else Color.WHITE
		bands.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content.add_child(bands)
		_walk_nodes.append(bands)
		var bt := create_tween()
		bt.tween_property(bands, "progress", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		Sfx.play("whoosh")
		if team != null:
			var helm := HelmetView.new(team, 2.0, true)
			helm.size = Vector2(128, 96)
			helm.position = Vector2(_vp().x + 10, (_vp().y - 96) * 0.5 - 8)
			_content.add_child(helm)
			_walk_nodes.append(helm)
			var ht := create_tween()
			ht.tween_property(helm, "position:x", (_vp().x - 128) * 0.5, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var tn := MetaUI.label(("%s %s" % [team.city, team.team_name]).to_upper(), Color.WHITE, 16, HORIZONTAL_ALIGNMENT_CENTER)
			tn.set_anchors_preset(Control.PRESET_CENTER)
			tn.offset_left = -200
			tn.offset_right = 200
			tn.offset_top = 44
			tn.offset_bottom = 62
			tn.modulate.a = 0.0
			_content.add_child(tn)
			_walk_nodes.append(tn)
			create_tween().tween_property(tn, "modulate:a", 1.0, 0.3).set_delay(0.25)
		await _wait(1.0)
		if _skip:
			return
		for n in _walk_nodes.duplicate():
			if is_instance_valid(n):
				_fade_out(n)
		_walk_nodes.clear()
		# Let the team band clear so the OVR slams onto a clean stage.
		await _wait(0.3)
		if _skip:
			return
		# 3) OVR.
		var o := _big_text(str(ovr), 7, tc)
		_slam(o, Vector2(0, -10))
		Fx.burst(_content, _vp() * 0.5, tc.lightened(0.3), 30, 130.0, 0.8)
		await _wait(0.9)
		if _skip:
			return
		_fade_out(o)
	else:
		await _wait(0.35)
		if _skip:
			return
	# 4) The card flips in.
	_hero = CardView.new(card, e, 2)
	_hero.face_down = true
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.size = Vector2(CardView.W, CardView.H) * 2
	_hero.position = ((_vp() - _hero.size) * 0.5).round() + Vector2(0, 4)
	_hero.pivot_offset = _hero.size * 0.5
	_hero.scale = Vector2(0.05, 1.0)
	_content.add_child(_hero)
	Sfx.play("flip")
	var ft := create_tween()
	ft.tween_property(_hero, "scale:x", 1.0, 0.16)
	ft.tween_property(_hero, "scale:x", 0.05, 0.1)
	ft.tween_callback(func() -> void: _hero.face_down = false)
	ft.tween_property(_hero, "scale", Vector2(1.12, 1.12), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ft.tween_property(_hero, "scale", Vector2.ONE, 0.12)
	await ft.finished
	if _skip:
		return
	_celebrate(_hero, tier, ovr)
	_hero.glow = 1.0
	_hero.is_new = not _dupe.get(int(e["uid"]), false)
	var nm := MetaUI.label(p.name.to_upper(), Color.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(0, _hero.position.y + _hero.size.y + 4)
	nm.size = Vector2(_vp().x, 10)
	_content.add_child(nm)
	_walk_nodes.append(nm)
	step = Step.REVEALED
	_prompt.text = "TAP TO SEE ALL %d CARDS" % _entries.size() if _entries.size() > 1 else "TAP TO CONTINUE"


## Particles, glow, shake and stingers scaled to rarity.
func _celebrate(target: Control, tier: int, ovr: int) -> void:
	var tc := CardView.tier_color(tier)
	var c := target.position + target.size * 0.5
	# D's light burst sprite spinning behind the card, and a glow ring pulse.
	if ResourceLoader.exists("res://art/fx/light_burst.png"):
		var lb := Sprite2D.new()
		lb.texture = load("res://art/fx/light_burst.png")
		lb.position = c
		lb.modulate = Color(tc.lightened(0.4), 0.0)
		lb.scale = Vector2.ONE * (2.0 + tier * 0.5)
		_content.add_child(lb)
		_content.move_child(lb, target.get_index())
		_walk_nodes.append(lb)
		var lt := lb.create_tween().set_parallel()
		lt.tween_property(lb, "modulate:a", 0.55 + tier * 0.1, 0.3)
		lt.tween_property(lb, "rotation", TAU, 12.0)
	if ResourceLoader.exists("res://art/fx/glow_ring.png"):
		var ring := Sprite2D.new()
		ring.texture = load("res://art/fx/glow_ring.png")
		ring.position = c
		ring.modulate = tc.lightened(0.5)
		ring.scale = Vector2(0.5, 0.5)
		_content.add_child(ring)
		var rt := ring.create_tween().set_parallel()
		rt.tween_property(ring, "scale", Vector2.ONE * (5.0 + tier), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt.tween_property(ring, "modulate:a", 0.0, 0.6)
		rt.chain().tween_callback(ring.queue_free)
	Fx.flash(self, Color(tc.lightened(0.5), 0.35 + tier * 0.1), 0.4)
	Fx.burst(_content, c, tc.lightened(0.2), 24 + tier * 22, 110.0 + tier * 30.0, 1.0, 2.0, 80.0)
	Fx.burst(_content, c, Color.WHITE, 10 + tier * 6, 80.0, 0.6, 1.0)
	_stage.rays = 0.6 + tier * 0.12
	var shake: float = [0.0, 2.0, 4.0, 7.0][clampi(tier, 0, 3)]
	if shake > 0.0:
		Fx.shake(_content, shake, 0.25 + tier * 0.1)
	match tier:
		CardRules.Tier.ELITE:
			Sfx.play("elite")
		CardRules.Tier.GOLD:
			Sfx.play("big")
		_:
			Sfx.play("reveal")
	if ovr >= 90:
		Fx.fireworks(_content, Rect2(40, 30, _vp().x - 80, _vp().y * 0.5), [tc, UiSkin.YELLOW, Color.WHITE, UiSkin.STAR_BLUE],
				8, 2.0)
		Fx.confetti(_content, _vp().x, [tc, UiSkin.YELLOW, Color.WHITE, UiSkin.STAR_RED], 90)
	elif tier >= CardRules.Tier.GOLD:
		Fx.confetti(_content, _vp().x, [tc, Color.WHITE], 40)
	Sfx.play("sparkle")


func _big_text(text: String, px: int, col: Color) -> TextureRect:
	var tex := UiSkin.logo([text], px, Color.WHITE, col.lightened(0.2), col.darkened(0.2), UiSkin.SHADOW)
	var r := TextureRect.new()
	r.texture = tex
	r.size = tex.get_size()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(r)
	_walk_nodes.append(r)
	return r


func _slam(r: Control, offset: Vector2) -> void:
	r.position = ((_vp() - r.size) * 0.5).round() + offset
	r.pivot_offset = r.size * 0.5
	# Integer steps keep the pixel digits crisp while they slam down (3x -> 2x -> 1x).
	r.scale = Vector2(3, 3)
	r.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(r, "scale", Vector2(2, 2), 0.08)
	tw.tween_property(r, "scale", Vector2.ONE, 0.08)
	tw.tween_callback(func() -> void:
		Sfx.play("slam")
		Fx.shake(_content, 3.0, 0.2))
	tw.tween_property(r, "scale", Vector2(1.1, 1.1), 0.05)
	tw.tween_property(r, "scale", Vector2.ONE, 0.07)


func _fade_out(n: Variant) -> void:
	if not is_instance_valid(n) or not n is CanvasItem:
		return
	_walk_nodes.erase(n)
	var tw: Tween = (n as CanvasItem).create_tween()
	tw.tween_property(n, "modulate:a", 0.0, 0.2)
	tw.tween_callback(n.queue_free)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout


# ---------------------------------------------------------------- summary

## SKIP / tests: reveal everything and go straight to the summary.
func _flip_all() -> void:
	_skip = true
	_show_summary(true)


func _show_summary(instant := false) -> void:
	if step == Step.SUMMARY:
		if instant:
			for v in _cards:
				v.face_down = false
			_next = _cards.size()
		return
	step = Step.SUMMARY
	_skip_btn.visible = false
	_prompt.text = ""
	for n in _walk_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_walk_nodes.clear()
	if is_instance_valid(_hero):
		_hero.queue_free()
	if is_instance_valid(_pack_art):
		_pack_art.visible = false
	create_tween().tween_property(_dark, "color:a", 0.35, 0.3)
	_stage.spot = 0.0
	_stage.rays = 0.2
	_summary = VBoxContainer.new()
	_summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summary.offset_top = 32
	_summary.offset_bottom = -6 - SafeArea.bottom()
	_summary.add_theme_constant_override("separation", 6)
	_summary.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_summary)
	var n := _entries.size()
	var news := 0
	for e in _entries:
		if not _dupe.get(int(e["uid"]), false):
			news += 1
	_summary.add_child(MetaUI.label("%d CARDS ADDED TO YOUR SQUAD  -  %d NEW" % [n, news], UiSkin.WHITE, 8,
			HORIZONTAL_ALIGNMENT_CENTER))
	var per_row := mini(n, 6)
	var rows := [_entries.slice(0, per_row), _entries.slice(per_row)]
	var card_scale := 1
	for row_entries in rows:
		if (row_entries as Array).is_empty():
			continue
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		_summary.add_child(row)
		if _grid == null:
			_grid = row
		for e in row_entries:
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 2)
			row.add_child(col)
			var v := CardView.new(GameData.card(e["def"]), e, card_scale)
			v.face_down = not instant
			v.tapped.connect(func(_v: CardView) -> void: pass)
			col.add_child(v)
			_cards.append(v)
			var dupe: bool = _dupe.get(int(e["uid"]), false)
			var tag := MetaUI.label("DUPE +%d" % EconomyRules.quicksell_value(GameData.db, e) if dupe else "NEW!",
					UiSkin.MUTED if dupe else UiSkin.GREEN, 8, HORIZONTAL_ALIGNMENT_CENTER)
			tag.modulate.a = 1.0 if instant else 0.0
			col.add_child(tag)
			v.set_meta("tag", tag)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	_summary.add_child(bar)
	var sell_total := _dupe_value()
	if sell_total > 0:
		_sell_btn = MetaUI.button("QUICK SELL DUPES +%s" % CoinPill.fmt(sell_total), Vector2(150, 26), _sell_dupes)
		bar.add_child(_sell_btn)
	if _pack != null and _pack.price > 0:
		var again := MetaUI.button("OPEN ANOTHER  %s" % CoinPill.fmt(_pack.price), Vector2(140, 26), _open_another)
		again.disabled = not EconomyRules.can_buy(_prof, _pack)
		bar.add_child(again)
	elif not _prof.pending_packs.is_empty():
		bar.add_child(MetaUI.button("NEXT FREE PACK (%d)" % _prof.pending_packs.size(), Vector2(140, 26), _open_next_free))
	var cont := MetaUI.yellow("CONTINUE ▶", Vector2(110, 26), func() -> void: SceneRouter.goto(_back))
	bar.add_child(cont)
	if instant:
		_next = _cards.size()
		return
	_deal()


## Flips the summary cards one by one, best last for a final pop.
func _deal() -> void:
	var order: Array = range(_cards.size())
	order.reverse()
	for i in order:
		await _wait(0.12)
		if not is_instance_valid(self) or step != Step.SUMMARY:
			return
		var v: CardView = _cards[i]
		if not v.face_down:
			continue
		v.face_down = false
		_next += 1
		Fx.pop(v, 1.15, 0.22)
		var tier := v.tier()
		Sfx.play("flip" if tier < CardRules.Tier.GOLD else "big")
		if tier >= CardRules.Tier.GOLD:
			v.glow = 0.6
			Fx.burst(self, v.global_position + v.size * 0.5, CardView.tier_color(tier), 14, 70.0, 0.6, 1.0)
		var tag: Label = v.get_meta("tag")
		tag.create_tween().tween_property(tag, "modulate:a", 1.0, 0.15)


func _dupe_value() -> int:
	var total := 0
	for e in _entries:
		if _dupe.get(int(e["uid"]), false) and not e.get("locked", false) and not _prof.in_lineup(int(e["uid"])):
			total += EconomyRules.quicksell_value(GameData.db, e)
	return total


func _sell_dupes() -> void:
	var gained := 0
	for e in _entries.duplicate():
		var uid := int(e["uid"])
		if _dupe.get(uid, false) and not e.get("locked", false) and not _prof.in_lineup(uid):
			gained += EconomyRules.quicksell(_prof, GameData.db, uid)
	if gained <= 0:
		return
	SaveManager.save()
	Sfx.play("claim")
	for v in _cards:
		if _dupe.get(int(v.entry.get("uid", 0)), false):
			Fx.fly_coins(self, v.global_position + v.size * 0.5, _coins.coin_global(), 4)
			v.dim = true
	_coins.set_coins(_prof.coins)
	MetaUI.toast(self, "+%s COINS" % CoinPill.fmt(gained))
	if is_instance_valid(_sell_btn):
		_sell_btn.text = "SOLD +%s" % CoinPill.fmt(gained)
		_sell_btn.disabled = true


func _open_another() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var uids := EconomyRules.buy_and_open(_prof, _pack, GameData.db, rng, int(Time.get_unix_time_from_system()))
	if uids.is_empty():
		return
	SaveManager.save()
	SceneRouter.goto(SceneRouter.PACK_OPEN, {"uids": uids, "title": _pack.display_name, "pack": _pack.id,
			"back": _back})


func _open_next_free() -> void:
	var cfg := GameFlow.open_pending_config(_prof, _back)
	if not cfg.is_empty():
		SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)


# ---------------------------------------------------------------- effects layer

## Rotating light rays + two spotlights converging on the center, in `color`.
class _Stage:
	extends Control
	var color := Color.WHITE
	var rays := 0.0
	var spot := 0.0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, 6)
		if rays > 0.0:
			var n := 14
			var r := size.length()
			for i in n:
				var a := _t * 0.35 + TAU * i / n
				var w := 0.09
				var pts := PackedVector2Array([c, c + Vector2.from_angle(a - w) * r, c + Vector2.from_angle(a + w) * r])
				draw_colored_polygon(pts, Color(color.lightened(0.3), 0.10 * rays))
			for k in 5:
				draw_circle(c, 70.0 - k * 12.0, Color(color.lightened(0.4), 0.05 * rays))
		if spot > 0.0:
			var sway := sin(_t * 1.3) * 30.0
			for side in [-1.0, 1.0]:
				var top := Vector2(size.x * 0.5 + side * (size.x * 0.55), -10)
				var hit := c + Vector2(sway * side * 0.5, 30)
				var left := hit + Vector2(-70, 0)
				var right := hit + Vector2(70, 0)
				draw_colored_polygon(PackedVector2Array([top, left, right]), Color(color.lightened(0.5), 0.12 * spot))
			for k in 4:
				draw_circle(c + Vector2(0, 40), (90.0 - k * 18.0) * spot, Color(color.lightened(0.5), 0.06 * spot))


## Team-color stripes sweeping across the middle of the screen (walkout team reveal).
class _TeamBands:
	extends Control
	var primary := Color.RED
	var secondary := Color.WHITE
	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x * progress
		var cy := size.y * 0.5 - 8
		draw_rect(Rect2(0, cy - 40, w, 80), Color(primary, 0.85))
		draw_rect(Rect2(size.x - w, cy - 46, w, 5), Color(secondary, 0.9))
		draw_rect(Rect2(size.x - w, cy + 41, w, 5), Color(secondary, 0.9))
