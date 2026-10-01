extends Control
## Pack opening, FIFA style. The pack slides in and waits; a tap makes it rattle, tear
## open with a flash and a burst of light. A Mystery pack first spins like a slot machine
## through the packs it could be before landing on the real one. Then the TIER CLIMB: the
## stage lights up BRONZE... SILVER... GOLD... one step at a time up to the best card's
## tier, sometimes stalling a step short ("...") before bursting through (the fake-out).
## The best card gets a "walkout": spotlights sweep in the tier color, then its position,
## team (helmet + colors), OVR and, for X-Factor cards, the ability are revealed one by one
## before the card flips in with particles, glow and a screen shake scaled to its rarity.
## The rest wait face-down in the summary grid: tap each to flip it (or FLIP ALL), with
## NEW / duplicate + quick-sell value, QUICK SELL DUPES, OPEN ANOTHER and CONTINUE. SKIP
## jumps to the summary at any time. The cards were already saved when the pack was
## granted, so leaving early loses nothing.

## Chance the tier climb stalls one tier short before bursting through.
const FAKE_OUT_CHANCE := 0.4

enum Step { INTRO, TEARING, WALKOUT, REVEALED, SUMMARY }

var step := Step.INTRO
var _next := 0                     ## cards revealed so far (summary)
var _back := SceneRouter.HUB
var _pack: PackDef
var _mystery: PackDef              ## the Mystery pack this really was (null = a normal pack)
var _hero_seen := false            ## the best card was revealed by the walkout
var _flip_all_btn: Button
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
	_mystery = PackCatalog.get_pack(str(cfg["mystery"])) if cfg.has("mystery") else null
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
	if OS.get_cmdline_user_args().has("--summary"):   # debug: skip to the card summary
		_show_summary.call_deferred(true)
	else:
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
	# A Mystery pack keeps its secret in the title too.
	var head := TitleBar.new(_mystery.display_name if _mystery != null else _title)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = 26
	_content.add_child(head)
	_coins = CoinPill.new(_prof.coins)
	_coins.position = Vector2(6 + SafeArea.left(), 6 + SafeArea.top())
	add_child(_coins)
	var pc := _pack.color if _pack != null else CardView.tier_color(_best_tier())
	_pack_art = PackArt.new(pc, _title.replace(" PACK", ""), 3.0)
	if _mystery != null:
		_pack_art.color = _mystery.color
		_pack_art.label = "MYSTERY"
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
	if _mystery != null:
		await _mystery_spin()
		if _skip:
			return
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
	await _tier_climb(tier)
	if _skip:
		return
	_stage.color = tc
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
	if card.is_xfactor():
		await _xfactor_sting(card)
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
	if card.is_xfactor():
		nm.text += "  -  ⚡ " + str(AbilityRules.get_def(card.ability).get("name", ""))
		nm.add_theme_color_override("font_color", CardRules.PROGRAM_COLORS["xf"].lightened(0.35))
	step = Step.REVEALED
	_hero_seen = true
	_prompt.text = "TAP TO SEE ALL %d CARDS" % _entries.size() if _entries.size() > 1 else "TAP TO CONTINUE"


## Mystery pack: the foil cycles through the packs it could be, slowing down like a slot
## machine, and lands on the real one: "IT'S A GOLD PACK!".
func _mystery_spin() -> void:
	var ids: Array = Array(_mystery.mystery)
	var steps := 16
	var delay := 0.05
	Sfx.play("rumble")
	for k in steps:
		var p := PackCatalog.get_pack(str(ids[k % ids.size()]))
		if k == steps - 1:
			p = _pack
		if p != null:
			_pack_art.color = p.color
			_pack_art.label = p.display_name.replace(" PACK", "")
		Sfx.play("spin")
		_pack_art.shake = 0.3
		await _wait(delay)
		if _skip:
			return
		delay *= 1.17
	_pack_art.shake = 0.0
	var col := _pack.color if _pack != null else UiSkin.YELLOW
	Fx.flash(self, Color(col.lightened(0.5), 0.6), 0.35)
	Fx.burst(_content, _pack_art.position + _pack_art.size * 0.5, col.lightened(0.3), 30, 120.0, 0.7, 1.5)
	var t := _big_text("IT'S A %s!" % (_pack.display_name if _pack != null else "PACK"), 3, col)
	_slam(t, Vector2(0, -_pack_art.size.y * 0.5 - 4))
	Sfx.play("big" if _pack != null and _pack.price >= 9000 else "reveal")
	await _wait(1.0)
	_fade_out(t)


## The tier climb: BRONZE... SILVER... GOLD... up to the best card's tier, one rising step
## at a time. Sometimes it stalls a tier short ("...", the lights dip) and then bursts
## through to the real tier.
func _tier_climb(target: int) -> void:
	var fake := target >= 1 and randf() < FAKE_OUT_CHANCE
	var stop := target - 1 if fake else target
	for t in range(0, stop + 1):
		var tc := CardView.tier_color(t)
		_stage.color = tc
		_stage.rays = 0.25 + 0.15 * t
		var lbl := _big_text(CardRules.NAMES[t] + ("" if t == target else "..."), 4, tc)
		_pop(lbl, Vector2(0, -6))
		Sfx.play("climb%d" % t)
		Fx.burst(_content, _vp() * 0.5, tc.lightened(0.3), 6 + t * 6, 60.0 + t * 20.0, 0.5, 1.0)
		await _wait(0.5 if t < stop else 0.65)
		_fade_out(lbl)
		if _skip:
			return
	if not fake:
		return
	# The fake-out: the lights dip... then it breaks through.
	var dots := _big_text("...", 4, Color.WHITE)
	_pop(dots, Vector2(0, -6))
	Sfx.play("fizzle")
	var dim := create_tween().set_parallel()
	dim.tween_property(_stage, "rays", 0.08, 0.5)
	dim.tween_property(_dark, "color:a", 0.9, 0.5)
	await _wait(0.95)
	_fade_out(dots)
	if _skip:
		return
	var tc2 := CardView.tier_color(target)
	_stage.color = tc2
	_stage.rays = 0.6 + 0.1 * target
	Fx.flash(self, Color(tc2.lightened(0.5), 0.6), 0.35)
	Fx.shake(_content, 5.0, 0.3)
	var up := _big_text(CardRules.NAMES[target] + "!", 5, tc2)
	_slam(up, Vector2(0, -6))
	Sfx.play("climb%d" % target)
	Fx.burst(_content, _vp() * 0.5, tc2.lightened(0.3), 40, 150.0, 0.8, 2.0)
	create_tween().tween_property(_dark, "color:a", 0.82, 0.3)
	await _wait(0.8)
	_fade_out(up)


## X-Factor stinger: pink lightning, "X-FACTOR" slams in and the ability is named.
func _xfactor_sting(card: CardDef) -> void:
	var xc: Color = CardRules.PROGRAM_COLORS["xf"]
	var d := AbilityRules.get_def(card.ability)
	_stage.color = xc
	Sfx.play("xf")
	Fx.flash(self, Color(xc.lightened(0.4), 0.55), 0.3)
	var t := _big_text("X-FACTOR", 5, xc)
	_slam(t, Vector2(0, -22))
	var nm := MetaUI.label("⚡ %s ⚡" % str(d.get("name", "")), Color.WHITE, 16, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(0, _vp().y * 0.5 + 14)
	nm.size = Vector2(_vp().x, 18)
	_content.add_child(nm)
	_walk_nodes.append(nm)
	var tx := MetaUI.label(str(d.get("text", "")), UiSkin.YELLOW, 8, HORIZONTAL_ALIGNMENT_CENTER)
	tx.position = Vector2(0, _vp().y * 0.5 + 36)
	tx.size = Vector2(_vp().x, 10)
	_content.add_child(tx)
	_walk_nodes.append(tx)
	for i in 3:
		Fx.burst(_content, Vector2(randf_range(60, _vp().x - 60), randf_range(50, _vp().y - 60)), xc.lightened(0.2),
				14, 90.0, 0.5, 1.5)
	await _wait(1.5)
	for n in [t, nm, tx]:
		_fade_out(n)


## Lighter than _slam: a quick 2x -> 1x pop (tier climb steps).
func _pop(r: Control, offset: Vector2) -> void:
	r.position = ((_vp() - r.size) * 0.5).round() + offset
	r.pivot_offset = r.size * 0.5
	r.scale = Vector2(2, 2)
	var tw := create_tween()
	tw.tween_property(r, "scale", Vector2.ONE, 0.1)


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
			# The walkout already showed the best card; the rest wait for your tap.
			v.face_down = not instant and not (_hero_seen and e == _entries[0])
			v.tapped.connect(func(tv: CardView) -> void: _flip_one(tv))
			col.add_child(v)
			_cards.append(v)
			var dupe: bool = _dupe.get(int(e["uid"]), false)
			var tag := MetaUI.label("DUPE +%d" % EconomyRules.quicksell_value(GameData.db, e) if dupe else "NEW!",
					UiSkin.MUTED if dupe else UiSkin.GREEN, 8, HORIZONTAL_ALIGNMENT_CENTER)
			tag.modulate.a = 0.0 if v.face_down else 1.0
			col.add_child(tag)
			v.set_meta("tag", tag)
			# Don't need him? Sell him right here (70% of what he's worth; a banger pays big).
			var sell := MetaUI.button("SELL %s" % CoinPill.fmt(EconomyRules.quicksell_value(GameData.db, e)),
					Vector2(card_scale * CardView.W, 16), func() -> void: _sell_one(v))
			sell.theme_type_variation = "PillButton"
			sell.modulate.a = 0.0 if v.face_down else 1.0
			sell.disabled = v.face_down
			col.add_child(sell)
			v.set_meta("sell", sell)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	_summary.add_child(bar)
	var sell_total := _dupe_value()
	if sell_total > 0:
		_sell_btn = MetaUI.button("QUICK SELL DUPES +%s" % CoinPill.fmt(sell_total), Vector2(150, 26), _sell_dupes)
		bar.add_child(_sell_btn)
	var buy_pack := _buy_pack()
	if buy_pack != null and buy_pack.price > 0:
		var again := MetaUI.button("OPEN ANOTHER  %s" % CoinPill.fmt(buy_pack.price), Vector2(140, 26), _open_another)
		again.disabled = not EconomyRules.can_buy(_prof, buy_pack) or EconomyRules.has_pending_draft(_prof)
		bar.add_child(again)
	elif not _prof.pending_packs.is_empty():
		bar.add_child(MetaUI.button("NEXT FREE PACK (%d)" % _prof.pending_packs.size(), Vector2(140, 26), _open_next_free))
	var cont := MetaUI.yellow("CONTINUE ▶", Vector2(110, 26), func() -> void: SceneRouter.goto(_back))
	bar.add_child(cont)
	if instant:
		_next = _cards.size()
		return
	if _cards.all(func(v: CardView) -> bool: return not v.face_down):
		return
	_prompt.text = "TAP A CARD TO FLIP IT"
	_flip_all_btn = MetaUI.button("FLIP ALL", Vector2(80, 26), _deal)
	bar.add_child(_flip_all_btn)
	bar.move_child(_flip_all_btn, 0)


## Pack bought by OPEN ANOTHER: a Mystery pack is bought again as a Mystery pack.
func _buy_pack() -> PackDef:
	return _mystery if _mystery != null else _pack


## Tap-to-flip in the summary: Gold+ cards rattle first, then flip with a pop and a burst.
func _flip_one(v: CardView) -> void:
	if step != Step.SUMMARY or not v.face_down or v.has_meta("flipping"):
		return
	v.set_meta("flipping", true)
	var tier := v.tier()
	if tier >= CardRules.Tier.GOLD:
		v.glow = 0.5
		Fx.shake(v, 2.0 + tier, 0.3)
		Sfx.play("rumble")
		await _wait(0.35)
		if not is_instance_valid(v):
			return
	_reveal_card(v)
	if _cards.all(func(c: CardView) -> bool: return not c.face_down):
		_prompt.text = ""
		if is_instance_valid(_flip_all_btn):
			_flip_all_btn.visible = false


func _reveal_card(v: CardView) -> void:
	v.face_down = false
	_next += 1
	Fx.pop(v, 1.15, 0.22)
	var tier := v.tier()
	Sfx.play("flip" if tier < CardRules.Tier.GOLD else "big")
	if tier >= CardRules.Tier.GOLD:
		v.glow = 0.6
		Fx.burst(self, v.global_position + v.size * 0.5, CardView.tier_color(tier), 14, 70.0, 0.6, 1.0)
	if v.is_xfactor():
		Sfx.play("xf")
		Fx.burst(self, v.global_position + v.size * 0.5, CardRules.PROGRAM_COLORS["xf"], 16, 80.0, 0.6, 1.0)
	var tag: Label = v.get_meta("tag")
	tag.create_tween().tween_property(tag, "modulate:a", 1.0, 0.15)
	var sell: Button = v.get_meta("sell")
	if sell.text.begins_with("SELL"):
		sell.disabled = false
		sell.create_tween().tween_property(sell, "modulate:a", 1.0, 0.15)


## FLIP ALL: flips the remaining cards one by one, best last for a final pop.
func _deal() -> void:
	_prompt.text = ""
	if is_instance_valid(_flip_all_btn):
		_flip_all_btn.visible = false
	var order: Array = range(_cards.size())
	order.reverse()
	for i in order:
		await _wait(0.12)
		if not is_instance_valid(self) or step != Step.SUMMARY:
			return
		var v: CardView = _cards[i]
		if not v.face_down or v.has_meta("flipping"):
			continue
		_reveal_card(v)


func _dupe_value() -> int:
	var total := 0
	for e in _entries:
		var uid := int(e["uid"])
		if _dupe.get(uid, false) and not _prof.find(uid).is_empty() and not e.get("locked", false) \
				and not _prof.in_lineup(uid):
			total += EconomyRules.quicksell_value(GameData.db, e)
	return total


## SELL under one summary card.
func _sell_one(v: CardView) -> void:
	var uid := int(v.entry.get("uid", 0))
	var gained := EconomyRules.quicksell(_prof, GameData.db, uid)
	var sell: Button = v.get_meta("sell")
	if gained <= 0:
		MetaUI.toast(self, "LOCKED OR STARTING - CAN'T SELL", UiSkin.MUTED)
		return
	SaveManager.save()
	Sfx.play("claim")
	Fx.fly_coins(self, v.global_position + v.size * 0.5, _coins.coin_global(), 4 if gained < 5000 else 12)
	v.dim = true
	sell.text = "SOLD"
	sell.disabled = true
	_coins.set_coins(_prof.coins)
	MetaUI.toast(self, "+%s COINS" % CoinPill.fmt(gained))
	if is_instance_valid(_sell_btn) and _dupe_value() <= 0:
		_sell_btn.disabled = true


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
		if _dupe.get(int(v.entry.get("uid", 0)), false) and _prof.find(int(v.entry.get("uid", 0))).is_empty():
			Fx.fly_coins(self, v.global_position + v.size * 0.5, _coins.coin_global(), 4)
			v.dim = true
			var sb: Button = v.get_meta("sell")
			sb.text = "SOLD"
			sb.disabled = true
	_coins.set_coins(_prof.coins)
	MetaUI.toast(self, "+%s COINS" % CoinPill.fmt(gained))
	if is_instance_valid(_sell_btn):
		_sell_btn.text = "SOLD +%s" % CoinPill.fmt(gained)
		_sell_btn.disabled = true


func _open_another() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var r := EconomyRules.buy(_prof, _buy_pack(), GameData.db, rng, int(Time.get_unix_time_from_system()))
	if r.is_empty():
		return
	SaveManager.save()
	var real: PackDef = r["pack"]
	var cfg := {"uids": r["uids"], "title": real.display_name, "pack": real.id, "back": _back}
	if r["mystery"]:
		cfg["mystery"] = _buy_pack().id
	SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)


func _open_next_free() -> void:
	var cfg := GameFlow.open_pending_config(_prof, _back)
	if not cfg.is_empty():
		SceneRouter.goto(cfg["scene"], cfg)


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
