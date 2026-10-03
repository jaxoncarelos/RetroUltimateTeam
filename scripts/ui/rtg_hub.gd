extends Control
## ROAD TO GLORY HUB. No career: the intro (CREATE YOUR PLAYER) and your Legends shelf.
## A career: your card, name / team / age line, coach trust, XP (UPGRADE), the next game,
## this season's line and goals; nav: home, CAREER, SCHEDULE, PRACTICE (once a week, XP),
## UPGRADE and PLAY (play or sim the game) - or OFFSEASON when the season is over.

var _ui: Dictionary
var prof: Profile


func _ready() -> void:
	prof = SaveManager.profile
	var cfg := SceneRouter.take_config()
	_ui = MetaUI.screen(self, "ROAD TO GLORY", SceneRouter.MODE)
	if not prof.rtg.is_empty() and str(prof.rtg.get("stage", "")) == "draft":
		SceneRouter.goto.call_deferred(SceneRouter.RTG_DRAFT)
		return
	var drill: Dictionary = cfg.get("drill", {})
	if not drill.is_empty() and str(drill.get("purpose", "")) == "practice" and not prof.rtg.is_empty():
		_apply_practice(drill)
	if prof.rtg.is_empty():
		_intro()
	else:
		_career()
	if cfg.has("toast"):
		MetaUI.toast.call_deferred(self, str(cfg["toast"]))


# ---------------------------------------------------------------- no career yet

func _intro() -> void:
	var root: VBoxContainer = _ui["root"]
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := MetaUI.label("BE ONE PLAYER. GET DRAFTED. BECOME A LEGEND.", UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(t)
	var d := MetaUI.label("CREATE A QB, RB, WR OR CB, RUN THE COMBINE, HEAR YOUR NAME CALLED ON DRAFT DAY, "
			+ "THEN PLAY YOUR SIDE OF THE BALL WITH ALL-NEW TWO-THUMB CONTROLS. EARN XP, WIN THE COACH'S TRUST, "
			+ "CHASE AWARDS AND RINGS, AND RETIRE INTO THE HALL OF FAME.", UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(420, 0)
	root.add_child(d)
	if not prof.rtg_legends.is_empty():
		root.add_child(_legends_panel())
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.spacer())
	var go := MetaUI.continue_button("CREATE YOUR PLAYER", func() -> void: SceneRouter.goto(SceneRouter.RTG_CREATE), true, 190)
	nav.add_child(go)
	Fx.pulse.call_deferred(go, 1.04, 1.0)


func _legends_panel() -> Control:
	var p := RetroPanel.new("LEGENDS", UiSkin.PANEL, 4)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	p.add_child(col)
	for l in prof.rtg_legends.slice(maxi(0, prof.rtg_legends.size() - 4)):
		var aw: Dictionary = l.get("awards", {})
		var bits: Array[String] = []
		if int(l.get("rings", 0)) > 0:
			bits.append("%d RING%s" % [int(l["rings"]), "S" if int(l["rings"]) > 1 else ""])
		for id in ["mvp", "opoy", "dpoy", "all_pro", "pro_bowl"]:
			if int(aw.get(id, 0)) > 0:
				bits.append("%dX %s" % [int(aw[id]), RtgRules.AWARDS[id][0]])
		var line := "%s %s %s  ·  %d SEASONS  ·  PEAK %d%s" % [l["pos"], l["first"], l["last"], int(l["seasons"]),
				int(l["peak"]), "  ·  HALL OF FAME" if l.get("hof", false) else ""]
		col.add_child(MetaUI.label(line, UiSkin.YELLOW if l.get("hof", false) else UiSkin.WHITE))
		if not bits.is_empty():
			col.add_child(MetaUI.label("   " + "  ".join(bits.slice(0, 3)), UiSkin.MUTED))
	return p


# ---------------------------------------------------------------- the career

func _career() -> void:
	var rtg := prof.rtg
	var p: Dictionary = rtg["player"]
	var team: TeamData = GameData.team(str(rtg["team"]))
	var root: VBoxContainer = _ui["root"]
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var cc := CenterContainer.new()
	row.add_child(cc)
	cc.add_child(RtgCard.new(p, str(rtg["team"]), 2))
	# Middle: who you are, trust, XP, this season's line.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	row.add_child(mid)
	mid.add_child(MetaUI.label("%s %s" % [p["first"], p["last"]], UiSkin.YELLOW, 16))
	mid.add_child(MetaUI.label("#%d %s  ·  %s  ·  AGE %d" % [int(p["jersey"]), p["pos"],
			RtgRules.archetype(str(p["pos"]), str(p["arch"]))["name"], int(p["age"])], UiSkin.WHITE))
	var dev := int(p.get("dev", 0))
	mid.add_child(MetaUI.label("%s  ·  YEAR %d  ·  DEV: %s" % [team.team_name.to_upper() if team != null else "",
			int(rtg["year"]), RtgRules.DEV[dev]], RtgRules.DEV_COLORS[dev] if dev > 0 else UiSkin.MUTED))
	mid.add_child(_meter("COACH TRUST", int(rtg["trust"]) / 100.0, "%d" % int(rtg["trust"]), UiSkin.GREEN))
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	mid.add_child(xp_row)
	xp_row.add_child(MetaUI.label("XP %s" % CoinPill.fmt(int(rtg["xp"])), UiSkin.YELLOW))
	var cheapest := _cheapest_upgrade()
	var up := MetaUI.button("UPGRADE", Vector2(74, 20), func() -> void: SceneRouter.goto(SceneRouter.RTG_UPGRADE))
	xp_row.add_child(up)
	if cheapest > 0 and int(rtg["xp"]) >= cheapest:
		up.theme_type_variation = "YellowButton"
		Fx.pulse.call_deferred(up, 1.05, 0.9)
	var line_panel := RetroPanel.new("THIS SEASON", UiSkin.PANEL, 3)
	line_panel.add_child(MetaUI.label(RtgTracker.line_text(str(p["pos"]), rtg["season_stats"]) + "  ·  AVG GRADE %s" %
			RtgTracker.letter(RtgRules.grade_avg(rtg)), UiSkin.WHITE))
	mid.add_child(line_panel)
	# Right: next game + goals.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(180, 0)
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	right.add_child(_next_game_panel())
	right.add_child(_goals_panel())
	# Nav.
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.nav_button("CAREER", _career_popup, 64))
	nav.add_child(MetaUI.nav_button("SCHEDULE", _schedule_popup, 70))
	var prac := MetaUI.nav_button("PRACTICE", _practice, 70)
	prac.disabled = _practiced() or str(rtg["stage"]) != "season"
	nav.add_child(prac)
	if str(rtg["stage"]) == "offseason":
		var off := MetaUI.continue_button("OFFSEASON", func() -> void: SceneRouter.goto(SceneRouter.RTG_OFFSEASON), true, 120)
		nav.add_child(off)
		Fx.pulse.call_deferred(off, 1.05, 1.0)
	else:
		var play := MetaUI.continue_button("PLAY", _play, true, 100)
		nav.add_child(play)
		Fx.pulse.call_deferred(play, 1.05, 1.1)


func _meter(title: String, frac: float, value: String, color: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	var l := MetaUI.label(title, UiSkin.MUTED)
	l.custom_minimum_size = Vector2(78, 0)
	h.add_child(l)
	var bar := BarMeter.new(clampf(frac, 0.0, 1.0), Vector2(90, 8), color)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.segments = 5
	h.add_child(bar)
	h.add_child(MetaUI.label(value, UiSkin.WHITE))
	return h


func _cheapest_upgrade() -> int:
	var p: Dictionary = prof.rtg["player"]
	var best := 0
	for k in RtgRules.WEIGHTS[str(p["pos"])]:
		var v := int(p["attrs"][k])
		if v >= 99:
			continue
		var c := RtgRules.upgrade_cost(v)
		if best == 0 or c < best:
			best = c
	return best


func _next_game_panel() -> Control:
	var rtg := prof.rtg
	var s: Dictionary = rtg["season"]
	var table := SeasonRules.standings(s, GameData.teams.keys())
	var you := str(rtg["team"])
	var rec: Dictionary = table.get(you, {"w": 0, "l": 0, "t": 0})
	var p := RetroPanel.new("RECORD %d-%d%s" % [int(rec["w"]), int(rec["l"]), ("-%d" % int(rec["t"])) if int(rec["t"]) > 0 else ""], UiSkin.PANEL, 3)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var g := RtgRules.next_game(rtg)
	if g.is_empty():
		var champ := str(s.get("playoffs", {}).get("champion", ""))
		h.add_child(MetaUI.label("SEASON OVER" + ("  ·  CHAMPIONS!" if champ == you else ""), UiSkin.YELLOW if champ == you else UiSkin.WHITE))
		return p
	var opp: String = g["away"] if g["home"] == you else g["home"]
	var t: TeamData = GameData.team(opp)
	var helm := TextureRect.new()
	helm.texture = ArtGen.helmet(opp, t.uniform_colors(), true)
	helm.custom_minimum_size = Vector2(36, 27)
	helm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	helm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(helm)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	col.add_child(MetaUI.label(str(g["label"]), UiSkin.YELLOW))
	col.add_child(MetaUI.label("%s %s" % ["VS" if g["home"] == you else "AT", t.team_name.to_upper()], UiSkin.WHITE))
	var orec: Dictionary = table.get(opp, {"w": 0, "l": 0})
	col.add_child(MetaUI.label("(%d-%d)  ·  %s" % [int(orec["w"]), int(orec["l"]), TeamRating.DIFFICULTY[Settings.difficulty][0]], UiSkin.MUTED))
	return p


func _goals_panel() -> Control:
	var p := RetroPanel.new("SEASON GOALS", UiSkin.PANEL, 3)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	p.add_child(col)
	for g in prof.rtg.get("goals", []):
		var have := RtgRules.goal_progress(prof.rtg, g)
		var done: bool = g.get("done", false)
		var l := MetaUI.label(("✓ " if done else "") + str(g["text"]), UiSkin.GREEN if done else UiSkin.WHITE)
		col.add_child(l)
		var bar := BarMeter.new(clampf(float(have) / maxf(float(g["target"]), 1.0), 0.0, 1.0), Vector2(150, 5),
				UiSkin.GREEN if done else UiSkin.YELLOW)
		col.add_child(bar)
	return p


# ---------------------------------------------------------------- actions

func _play() -> void:
	var cfg := RtgFlow.game_config(prof.rtg)
	if cfg.is_empty():
		return
	var t: TeamData = GameData.team(str(cfg["away"]))
	var body := MetaUI.label("%s  ·  %s %s\nDIFFICULTY: %s  ·  PLAY IT FOR FULL XP, OR SIM FOR LESS" % [cfg["label"],
			"VS" if cfg["extra"]["home"] == prof.rtg["team"] else "AT", t.team_name.to_upper(),
			TeamRating.DIFFICULTY[Settings.difficulty][0]], UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	MetaUI.popup(self, "GAME DAY", body, [["SIM GAME", _sim_game], ["PLAY ▶", func() -> void:
		SceneRouter.goto(SceneRouter.MATCH, cfg), true]])


func _sim_game() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var r := RtgRules.sim_game(prof.rtg, rng)
	if r.is_empty():
		return
	SceneRouter.goto(SceneRouter.RTG_POSTGAME, {"last_result": r})


func _practice_key() -> String:
	var s: Dictionary = prof.rtg.get("season", {})
	return "%d:%s:%d" % [int(prof.rtg["year"]), str(s.get("phase", "")), int(s.get("week", 0))
			+ (int(s.get("playoffs", {}).get("round", 0)) * 100 if s.get("phase", "") == "playoffs" else 0)]


func _practiced() -> bool:
	return str(prof.rtg.get("practice_key", "")) == _practice_key()


func _practice() -> void:
	if _practiced():
		return
	SceneRouter.goto(SceneRouter.RTG_DRILL, {"player": prof.rtg["player"], "purpose": "practice",
			"back": SceneRouter.RTG_HUB})


## Practice XP: 40 + 1.6 × grade points (an A rep day ≈ 180 XP), once per week.
func _apply_practice(drill: Dictionary) -> void:
	if _practiced():
		return
	var xp := int(round(40.0 + 1.6 * float(drill["points"])))
	prof.rtg["xp"] = int(prof.rtg["xp"]) + xp
	prof.rtg["xp_total"] = int(prof.rtg.get("xp_total", 0)) + xp
	prof.rtg["practice_key"] = _practice_key()
	SaveManager.save()
	MetaUI.toast.call_deferred(self, "PRACTICE %s  ·  +%d XP" % [str(drill["letter"]), xp])


func _career_popup() -> void:
	var rtg := prof.rtg
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var pos := str(rtg["player"]["pos"])
	var d: Dictionary = rtg.get("draft", {})
	col.add_child(MetaUI.label("DRAFTED: ROUND %d, PICK %d BY %s  ·  LEGACY %d / %d HOF" % [int(d.get("round", 0)),
			int(d.get("pick", 0)), str(d.get("team", "")), int(rtg.get("legacy", 0)), RtgRules.HOF_LEGACY], UiSkin.MUTED))
	if (rtg["career"] as Array).is_empty():
		col.add_child(MetaUI.label("YOUR FIRST SEASON IS UNDER WAY.", UiSkin.WHITE))
	for c in rtg["career"]:
		var aw: Array = c.get("awards", [])
		var names: Array[String] = []
		for id in aw:
			names.append(str(RtgRules.AWARDS[id][0]))
		col.add_child(MetaUI.label("Y%d %s %d-%d  %s  OVR %d  ·  %s" % [int(c["year"]), c["team"], int(c["wins"]), int(c["losses"]),
				c["grade"], int(c["ovr"]), RtgTracker.line_text(pos, c["stats"])], UiSkin.WHITE))
		if not names.is_empty():
			col.add_child(MetaUI.label("    " + ", ".join(names), UiSkin.YELLOW))
	if int(rtg.get("rings", 0)) > 0:
		col.add_child(MetaUI.label("SUPER BOWL RINGS: %d" % int(rtg["rings"]), UiSkin.YELLOW))
	MetaUI.popup(self, "CAREER", col, [["CLOSE", Callable(), true]])


func _schedule_popup() -> void:
	var rtg := prof.rtg
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	var games: Array = rtg.get("games", [])
	if games.is_empty():
		col.add_child(MetaUI.label("NO GAMES PLAYED YET THIS SEASON.", UiSkin.WHITE))
	for g in games.slice(maxi(0, games.size() - 10)):
		var won := int(g["pf"]) > int(g["pa"])
		col.add_child(MetaUI.label("%s %s %s  %s %d-%d  ·  %s  %s" % [g["label"], "VS" if g["home"] else "AT", g["opp"],
				"W" if won else ("L" if int(g["pf"]) < int(g["pa"]) else "T"), int(g["pf"]), int(g["pa"]), g["grade"], g["line"]],
				UiSkin.GREEN if won else UiSkin.WHITE))
	var nxt := RtgRules.next_game(rtg)
	if not nxt.is_empty():
		var you := str(rtg["team"])
		col.add_child(MetaUI.label("NEXT: %s %s %s" % [nxt["label"], "VS" if nxt["home"] == you else "AT",
				nxt["away"] if nxt["home"] == you else nxt["home"]], UiSkin.YELLOW))
	MetaUI.popup(self, "SEASON %d" % int(rtg["year"]), col, [["CLOSE", Callable(), true]])
