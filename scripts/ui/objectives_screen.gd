extends Control
## OBJECTIVES (Retro Bowl Hall of Fame style): a framed list with crown icons (gold when
## done, grey otherwise), progress bars, coin rewards and CLAIM buttons; tabs for DAILY /
## WEEKLY / MILESTONES in the bottom nav; CLAIM ALL; the info button explains every coin
## source. This screen is where players learn how to make money.

const KINDS := ["daily", "weekly", "milestone"]
const TAB_NAMES := ["DAILY", "WEEKLY", "HALL OF FAME"]

var prof: Profile
var _ui: Dictionary
var _kind := 0
var _panel: RetroPanel
var _list: VBoxContainer
var _tabs: Array[Button] = []
var _claim_all: Button


func _ready() -> void:
	prof = SaveManager.profile
	_ui = MetaUI.screen(self, "OBJECTIVES")
	var info := IconButton.new("info", Vector2(24, 22))
	info.pressed.connect(func() -> void: HowToEarn.show(self))
	_ui["top_right"].add_child(info)
	var root: VBoxContainer = _ui["root"]
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	_panel = RetroPanel.new("DAILY", UiSkin.PANEL, 5)
	_panel.custom_minimum_size = Vector2(400, 188)
	center.add_child(_panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(sc)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var nav: HBoxContainer = _ui["nav"]
	for i in KINDS.size():
		var b := MetaUI.nav_button(TAB_NAMES[i], _select.bind(i), 100)
		b.toggle_mode = true
		nav.add_child(b)
		_tabs.append(b)
	_claim_all = MetaUI.yellow("CLAIM ALL", Vector2(84, 28), _do_claim_all)
	nav.add_child(_claim_all)
	# Open on the first tab with something to claim.
	for i in KINDS.size():
		if _claimable(KINDS[i]) > 0:
			_kind = i
			break
	_refresh()


func _claimable(kind: String) -> int:
	var n := 0
	for o in ObjectiveRules.of_kind(prof, kind):
		if o["done"] and not o["claimed"]:
			n += 1
	return n


func _select(i: int) -> void:
	_kind = i
	_refresh()


func _refresh() -> void:
	for i in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == _kind)
		MetaUI.badge(_tabs[i], _claimable(KINDS[i]))
	MetaUI.clear(_list)
	var objs := ObjectiveRules.of_kind(prof, KINDS[_kind])
	var done := 0
	for o in objs:
		if o["claimed"]:
			done += 1
	var pct := int(round(100.0 * done / maxf(objs.size(), 1.0)))
	_panel.title = "%s  %d%%" % [TAB_NAMES[_kind], pct] if _kind == 2 else "%s  %d / %d" % [TAB_NAMES[_kind], done, objs.size()]
	if _kind == 0:
		_list.add_child(MetaUI.label("NEW DAILIES EVERY DAY - PLAY GAMES TO COMPLETE THEM", UiSkin.MUTED))
	elif _kind == 1:
		_list.add_child(MetaUI.label("WEEKLIES RESET EVERY MONDAY - BIG PAYOUTS", UiSkin.MUTED))
	for o in objs:
		_list.add_child(_row(o))
	_claim_all.visible = ObjectiveRules.claimable_count(prof) > 1
	(_ui["coins"] as CoinPill).set_coins(prof.coins)


func _row(o: Dictionary) -> Control:
	var done: bool = o["done"]
	var claimed: bool = o["claimed"]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.custom_minimum_size = Vector2(0, 22)
	var crown := TextureRect.new()
	crown.texture = UiSkin.icon("crown")
	crown.modulate = UiSkin.YELLOW if done else UiSkin.GREY
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(crown)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var tcol := UiSkin.WHITE if not claimed else UiSkin.GREY
	col.add_child(MetaUI.label(str(o["desc"]).to_upper(), tcol))
	if not done:
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 4)
		var bar := BarMeter.new(float(o["progress"]) / maxf(float(o["target"]), 1.0), Vector2(120, 6))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pr.add_child(bar)
		pr.add_child(MetaUI.label("%s / %s" % [CoinPill.fmt(int(o["progress"])), CoinPill.fmt(int(o["target"]))], UiSkin.MUTED))
		col.add_child(pr)
	var reward := MetaUI.label(str(o.get("reward_text", "+%d" % int(o["reward"]))), UiSkin.YELLOW if not claimed else UiSkin.GREY,
			8, HORIZONTAL_ALIGNMENT_RIGHT)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(reward)
	var coin := TextureRect.new()
	coin.texture = UiSkin.coin_tex()
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.modulate.a = 1.0 if not claimed else 0.4
	h.add_child(coin)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(58, 20)
	h.add_child(slot)
	if done and not claimed:
		var b := MetaUI.yellow("CLAIM", Vector2(56, 20), _claim.bind(str(o["id"])))
		slot.add_child(b)
		b.set_meta("silent", true)
		Fx.pulse.call_deferred(b, 1.08, 0.8)
	elif claimed:
		var ck := TextureRect.new()
		ck.texture = UiSkin.icon("check")
		ck.modulate = UiSkin.GREEN
		ck.position = Vector2(24, 7)
		slot.add_child(ck)
	return h


func _claim(id: String) -> void:
	var btn_pos := get_viewport_rect().size * 0.5
	for row in _list.get_children():
		for c in row.get_children():
			if c.get_child_count() > 0 and c.get_child(0) is Button:
				btn_pos = (c.get_child(0) as Button).global_position
	var r := ObjectiveRules.claim_details(prof, id)
	if int(r["coins"]) <= 0 and str(r["pack"]) == "":
		return
	SaveManager.save()
	_payout(int(r["coins"]), [r["pack"]] if str(r["pack"]) != "" else [], r["level_ups"], btn_pos)


func _do_claim_all() -> void:
	var r := ObjectiveRules.claim_all(prof)
	if int(r["coins"]) <= 0 and (r["packs"] as Array).is_empty():
		return
	SaveManager.save()
	_payout(int(r["coins"]), r["packs"], r["level_ups"], _claim_all.global_position)


func _payout(coins: int, packs: Array, ups: Array, from: Vector2) -> void:
	Sfx.play("claim")
	var pill: CoinPill = _ui["coins"]
	Fx.fly_coins(_ui["layer"], from + Vector2(20, 8), pill.coin_global(), clampi(coins / 50, 6, 20))
	Fx.burst(self, from + Vector2(20, 8), UiSkin.YELLOW, 24, 90.0, 0.6)
	MetaUI.toast(self, "+%s COINS%s" % [CoinPill.fmt(coins), "  +  PACK!" if not packs.is_empty() else ""])
	for up in ups:
		MetaUI.toast(self, "COACH LEVEL %d!  +%d COINS" % [int(up["level"]), int(up["coins"])], UiSkin.STAR_BLUE, 2.4)
		Sfx.play("levelup")
	_refresh()
	pill.shown = pill.shown - coins
	pill.set_coins(prof.coins)
	if not prof.pending_packs.is_empty() and not packs.is_empty():
		var open := func() -> void:
			var cfg := GameFlow.open_pending_config(prof, SceneRouter.OBJECTIVES)
			if not cfg.is_empty():
				SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)
		MetaUI.popup(self, "PACK EARNED!", MetaUI.label("A NEW PACK IS WAITING", UiSkin.YELLOW, 16), [["LATER", Callable()],
				["OPEN IT", open, true]])
