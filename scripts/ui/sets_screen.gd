extends Control
## SETS: trade spare cards (unlocked, not starting, never Legends) for packs, an Elite
## franchise star or a LEGEND DRAFT (a pick-one reward opens the draft screen).
## One framed tile per set, store-shelf style: a stack of the cards it eats ("x10"), an
## arrow, the reward pack, a progress bar (have / need), times completed and a COMPLETE
## button that turns yellow and pulses once you have enough.

var _ui: Dictionary
var _shelf: HBoxContainer


func _ready() -> void:
	_ui = MetaUI.screen(self, "SETS")
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 4)
	_shelf = HBoxContainer.new()
	_shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	_shelf.add_theme_constant_override("separation", 6)
	_shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_shelf)
	root.add_child(MetaUI.label("ONLY UNLOCKED BENCH CARDS ARE TRADED - LOCK A CARD TO KEEP IT SAFE", UiSkin.MUTED, 8,
			HORIZONTAL_ALIGNMENT_CENTER))
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.nav_button("SQUAD", func() -> void: SceneRouter.goto(SceneRouter.SQUAD)))
	nav.add_child(MetaUI.nav_button("STORE", func() -> void: SceneRouter.goto(SceneRouter.STORE)))
	_refresh(true)


func _refresh(animate := false) -> void:
	MetaUI.clear(_shelf)
	var i := 0
	for s in EconomyRules.SETS:
		var tile := _tile(s)
		_shelf.add_child(tile)
		if animate:
			tile.modulate.a = 0.0
			var tw := tile.create_tween()
			tw.tween_interval(0.07 * i)
			tw.tween_property(tile, "modulate:a", 1.0, 0.2)
		i += 1


func _tile(s: Dictionary) -> Control:
	var prof := SaveManager.profile
	var need := int(s["count"])
	var have := EconomyRules.set_candidates(prof, GameData.db, s).size()
	var tier := int(s["tier"])
	var franchise: bool = s["franchise_only"]
	var elite: bool = s["reward"] == "franchise_elite"
	var title := "FRANCHISE SET" if franchise else "%s SET" % CardRules.NAMES[tier]
	var p := RetroPanel.new(title, UiSkin.PANEL, 5)
	var narrow := EconomyRules.SETS.size() > 3
	p.custom_minimum_size = Vector2(124 if narrow else 146, 0)
	p.title_color = CardView.tier_color(tier).lightened(0.2)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(col)
	# Cards in -> reward out.
	var trade := HBoxContainer.new()
	trade.alignment = BoxContainer.ALIGNMENT_CENTER
	trade.add_theme_constant_override("separation", 4)
	col.add_child(trade)
	var stack := _Stack.new()
	stack.color = CardView.tier_color(tier)
	stack.count = need
	trade.add_child(stack)
	var arrow := MetaUI.label("▶", UiSkin.YELLOW)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trade.add_child(arrow)
	var art: PackArt
	if elite:
		art = PackArt.new(CardRules.COLORS[CardRules.Tier.ELITE], "STAR", 1.0)
	else:
		art = PackArt.for_pack(PackCatalog.get_pack(str(s["reward"])), 1.0)
	art.glow = 0.6 if have >= need else 0.0
	trade.add_child(art)
	var what := "%d %s%s CARDS" % [need, "FRANCHISE " if franchise else "", CardRules.NAMES[tier]]
	if narrow:
		what = "%d %s%s" % [need, "FRANCHISE " if franchise else "", CardRules.NAMES[tier]]
	col.add_child(MetaUI.label(what, UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
	var reward := "AN ELITE STAR OF YOUR TEAM" if elite else "FOR A %s" % PackCatalog.get_pack(str(s["reward"])).display_name
	if narrow:
		reward = "FOR A STAR" if elite else "FOR A " + PackCatalog.get_pack(str(s["reward"])).display_name.replace(" PACK", "")
	if not elite and PackCatalog.get_pack(str(s["reward"])).legend_guarantee > 0:
		reward = "FOR A LEGEND (1 OF 3)"
	col.add_child(MetaUI.label(reward, UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER))
	# Progress.
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 4)
	col.add_child(ph)
	var bar := BarMeter.new(float(mini(have, need)) / need, Vector2(0, 8), UiSkin.GREEN if have >= need else UiSkin.YELLOW)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(bar)
	ph.add_child(MetaUI.label("%d/%d" % [mini(have, need), need], UiSkin.GREEN if have >= need else UiSkin.WHITE))
	var b: Button
	if have >= need:
		b = MetaUI.yellow("COMPLETE", Vector2(0, 22), func() -> void: _complete(s))
		Fx.pulse.call_deferred(b, 1.05, 0.9)
	else:
		b = MetaUI.button("NEED %d MORE" % (need - have), Vector2(0, 22), func() -> void: pass)
		b.disabled = true
	col.add_child(b)
	var done := int(prof.sets_done.get(s["id"], 0))
	col.add_child(MetaUI.label("COMPLETED %dX" % done if done > 0 else "NOT COMPLETED YET",
			UiSkin.YELLOW if done > 0 else UiSkin.GREY, 8, HORIZONTAL_ALIGNMENT_CENTER))
	return p


func _complete(s: Dictionary) -> void:
	var prof := SaveManager.profile
	var reward := EconomyRules.complete_set(prof, GameData.db, s)
	if reward == "":
		return
	Sfx.play("claim")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var uids: Array[int] = []
	var title := ""
	if reward == "franchise_elite":
		var id := EconomyRules.franchise_elite(prof, GameData.db, rng)
		if id != "":
			uids.append(prof.add_card(id, int(Time.get_unix_time_from_system())))
		title = "FRANCHISE STAR"
	else:
		var pack := PackCatalog.get_pack(reward)
		uids = EconomyRules.grant_pack(prof, pack, GameData.db, rng, int(Time.get_unix_time_from_system()))
		title = pack.display_name
		if pack.pick:
			# Pick-one reward (Legend Draft): it was queued; open it first, on the draft screen.
			prof.pending_packs.push_front(prof.pending_packs.pop_back())
			var cfg := GameFlow.open_pending_config(prof, "res://scenes/meta/sets.tscn")
			if not cfg.is_empty():
				SceneRouter.goto(cfg["scene"], cfg)
				return
	SaveManager.save()
	SceneRouter.goto("res://scenes/meta/pack_open.tscn", {"uids": uids, "title": title,
			"back": "res://scenes/meta/sets.tscn"})


## A fanned stack of three face-down cards in a tier color with the count on top ("x10").
class _Stack:
	extends Control
	var color := Color.WHITE
	var count := 0

	func _init() -> void:
		custom_minimum_size = Vector2(46, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in 3:
			var r := Rect2(4 + i * 6, 12 - i * 5, 28, 40)
			draw_rect(r, UiSkin.SHADOW)
			draw_rect(r.grow(-1), color.lightened(0.2))
			draw_rect(r.grow(-3), UiSkin.NAVY)
			draw_rect(r.grow(-5), Color(color, 0.5), false, 1.0)
		var t := "x%d" % count
		UiSkin.draw_text_c(self, 24, 52, t, 16, UiSkin.WHITE, UiSkin.SHADOW)
