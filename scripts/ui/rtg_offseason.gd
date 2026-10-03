extends Control
## ROAD TO GLORY - OFFSEASON. Closes the season once (RtgFlow.close_season): the awards
## ceremony (each award stamps in with its coins / XP / legacy), your season line and record.
## Then the decisions: when your contract is up, offers from three teams and yours (pick one);
## RETIRE once you may (forced at RtgRules.RETIRE_AGE or a steep decline) — a legend, maybe a
## Hall of Famer; NEXT SEASON ages you a year (the legs go first after 30) and starts the new
## schedule.

var _ui: Dictionary
var prof: Profile
var _close: Dictionary
var _signed := {}
var _offer_buttons: Array[Button] = []
var _next: Button


func _ready() -> void:
	prof = SaveManager.profile
	if prof.rtg.is_empty() or str(prof.rtg.get("stage", "")) != "offseason":
		SceneRouter.goto.call_deferred(SceneRouter.RTG_HUB)
		return
	_close = RtgFlow.close_season(prof)
	_ui = MetaUI.screen(self, "OFFSEASON", SceneRouter.RTG_HUB)
	var root: VBoxContainer = _ui["root"]
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	row.add_child(_awards_panel())
	row.add_child(_decision_panel())
	var nav: HBoxContainer = _ui["nav"]
	var forced := RtgRules.must_retire(prof.rtg)
	if forced != "" or RtgRules.can_retire(prof.rtg):
		nav.add_child(MetaUI.button("RETIRE", Vector2(80, 28), _retire_confirm))
	nav.add_child(MetaUI.spacer())
	if forced == "":
		_next = MetaUI.continue_button("NEXT SEASON", _next_season, true, 140)
		_next.disabled = RtgRules.contract_up(prof.rtg) and _signed.is_empty()
		nav.add_child(_next)


func _awards_panel() -> Control:
	var rtg := prof.rtg
	var last: Dictionary = (rtg["career"] as Array).back() if not (rtg["career"] as Array).is_empty() else {}
	var p := RetroPanel.new("SEASON %d AWARDS" % int(rtg["year"]), UiSkin.PANEL, 5)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	p.add_child(col)
	col.add_child(MetaUI.label("%s  %d-%d  ·  AVG GRADE %s  ·  OVR %d" % [last.get("team", rtg["team"]), int(last.get("wins", 0)),
			int(last.get("losses", 0)), last.get("grade", "C"), RtgRules.player_ovr(rtg)], UiSkin.WHITE))
	col.add_child(MetaUI.label(RtgTracker.line_text(str(rtg["player"]["pos"]), last.get("stats", rtg["season_stats"])), UiSkin.MUTED))
	var awards: Array = _close.get("awards", [])
	if awards.is_empty():
		col.add_child(MetaUI.label("NO AWARDS THIS YEAR - BACK TO WORK.", UiSkin.MUTED))
	var delay := 0.4
	for id in awards:
		var a: Array = RtgRules.AWARDS[id]
		var l := MetaUI.label("★ %s" % a[0], UiSkin.YELLOW)
		l.modulate.a = 0.0
		col.add_child(l)
		var tw := l.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void:
			Sfx.play("elite" if id in ["mvp", "ring", "opoy", "dpoy"] else "big")
			Fx.pop(l, 1.4, 0.3))
		tw.tween_property(l, "modulate:a", 1.0, 0.15)
		delay += 0.7
	col.add_child(MetaUI.label("+%s COINS  ·  +%s XP  ·  +%d LEGACY (%d / %d HALL OF FAME)" % [CoinPill.fmt(int(_close.get("coins", 0))),
			CoinPill.fmt(int(_close.get("xp", 0))), int(_close.get("legacy", 0)), int(rtg.get("legacy", 0)), RtgRules.HOF_LEGACY], UiSkin.GREEN))
	if _close.get("card", false):
		col.add_child(MetaUI.label("YOUR PLAYER CARD JOINED YOUR ULTIMATE TEAM SQUAD (%d OVR)!" % RtgRules.player_ovr(rtg), UiSkin.YELLOW))
	elif not (rtg["career"] as Array).is_empty():
		col.add_child(MetaUI.label("YOUR ULTIMATE TEAM CARD IS NOW %d OVR." % RtgRules.player_ovr(rtg), UiSkin.MUTED))
	if "ring" in awards:
		Fx.confetti.call_deferred(self, size.x, [UiSkin.YELLOW, Color.WHITE], 80)
	return p


func _decision_panel() -> Control:
	var rtg := prof.rtg
	var p := RetroPanel.new("WHAT'S NEXT", UiSkin.PANEL, 5)
	p.custom_minimum_size = Vector2(220, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	p.add_child(col)
	var forced := RtgRules.must_retire(rtg)
	if forced != "":
		var why := "AT %d, YOUR BODY SAYS IT'S TIME." % int(rtg["player"]["age"]) if forced == "AGE" \
				else "THE LEAGUE HAS PASSED YOU BY. IT'S TIME."
		var l := MetaUI.label(why + " RETIRE AND SEE YOUR LEGACY.", UiSkin.YELLOW)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(205, 0)
		col.add_child(l)
		return p
	var c: Dictionary = rtg.get("contract", {})
	if RtgRules.contract_up(rtg):
		col.add_child(MetaUI.label("YOUR CONTRACT IS UP. OFFERS:", UiSkin.WHITE))
		for o in rtg.get("offers", []):
			var t: TeamData = GameData.team(str(o["team"]))
			var txt := "%s%s  %dY  %s/YR" % ["STAY: " if o.get("stay", false) else "", t.team_name.to_upper() if t != null else o["team"],
					int(o["years"]), o["salary"]]
			var b := MetaUI.button(txt, Vector2(205, 20), func() -> void: _sign(o))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			col.add_child(b)
			_offer_buttons.append(b)
	else:
		col.add_child(MetaUI.label("UNDER CONTRACT: %d MORE YEAR%s AT %s" % [int(c.get("years", 1)) - 1,
				"" if int(c.get("years", 1)) - 1 == 1 else "S", c.get("salary", "")], UiSkin.WHITE))
	var age := int(rtg["player"]["age"])
	col.add_child(MetaUI.label("AGE %d -> %d NEXT SEASON%s" % [age, age + 1, "  ·  EXPECT TO LOSE A STEP" if age + 1 >= 30 else ""],
			UiSkin.MUTED))
	if RtgRules.can_retire(rtg):
		col.add_child(MetaUI.label("YOU CAN RETIRE ANY OFFSEASON NOW.", UiSkin.MUTED))
	return p


func _sign(o: Dictionary) -> void:
	_signed = o
	RtgRules.sign(prof.rtg, o)
	prof.rtg["offers"] = []
	SaveManager.save()
	Sfx.play("big")
	for b in _offer_buttons:
		b.disabled = true
	var t: TeamData = GameData.team(str(o["team"]))
	MetaUI.toast(self, "SIGNED WITH THE %s!" % (t.team_name.to_upper() if t != null else str(o["team"])))
	if _next != null:
		_next.disabled = false


func _next_season() -> void:
	var changes := RtgFlow.next_season(prof)
	var bits: Array[String] = []
	for k in changes:
		bits.append("%s %s%d" % [RtgRules.ATTR_NAMES.get(k, k), "+" if int(changes[k]) > 0 else "", int(changes[k])])
	SceneRouter.goto(SceneRouter.RTG_HUB, {"toast": "YEAR %d!" % int(prof.rtg["year"]) + ("  " + ", ".join(bits) if not bits.is_empty() else "")})


func _retire_confirm() -> void:
	var body := MetaUI.label("HANG UP THE CLEATS? YOUR CAREER ENDS AND %s BECOMES A LEGEND." % str(prof.rtg["player"]["name"]),
			UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(260, 0)
	MetaUI.popup(self, "RETIRE", body, [["NOT YET", Callable()], ["RETIRE", _retire, true]])


func _retire() -> void:
	var reason := RtgRules.must_retire(prof.rtg)
	var legend := RtgFlow.retire(prof, reason if reason != "" else "CHOICE")
	var hof: bool = legend.get("hof", false)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(MetaUI.label("%s %s %s" % [legend["pos"], legend["first"], legend["last"]], UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MetaUI.label("%d SEASONS  ·  PEAK %d OVR  ·  LEGACY %d" % [int(legend["seasons"]), int(legend["peak"]), int(legend["legacy"])],
			UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MetaUI.label("CAREER: " + RtgTracker.line_text(str(legend["pos"]), legend["totals"]), UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MetaUI.label("FIRST-BALLOT HALL OF FAMER!" if hof else "A FINE CAREER. THE HALL WAS %d LEGACY AWAY." % maxi(0, RtgRules.HOF_LEGACY - int(legend["legacy"])),
			UiSkin.YELLOW if hof else UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
	if hof:
		Sfx.play("elite")
		Fx.confetti(self, size.x, [UiSkin.YELLOW, Color.WHITE, Color("#ffb000")], 90)
	else:
		Sfx.play("big")
	MetaUI.popup(self, "HALL OF FAME" if hof else "RETIRED", col, [["CONTINUE", func() -> void: SceneRouter.goto(SceneRouter.RTG_HUB), true]])
