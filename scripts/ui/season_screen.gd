extends Control
## SEASON (Retro Bowl "Schedule"): the week's matchups in a framed two-column list with
## mini helmets and scores (your game in yellow), arrows to page weeks, a STANDINGS view,
## playoffs, and CONTINUE into the pre-match screen for your next game.

var _ui: Dictionary
var _panel: RetroPanel
var _body: Control
var _week := 0
var _standings := false
var _nav_extra: Array[Control] = []


func _ready() -> void:
	_ui = MetaUI.screen(self, "SCHEDULE")
	var root: VBoxContainer = _ui["root"]
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	root.add_child(row)
	var prev := IconButton.new("back", Vector2(24, 40))
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prev.pressed.connect(func() -> void: _page(-1))
	row.add_child(prev)
	_panel = RetroPanel.new("WEEK 1", UiSkin.PANEL, 5)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_panel)
	var next := IconButton.new("play", Vector2(24, 40))
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(func() -> void: _page(1))
	row.add_child(next)
	var s := SaveManager.profile.season
	_week = clampi(int(s.get("week", 0)), 0, maxi(0, (s.get("weeks", []) as Array).size() - 1))
	_refresh()


func _page(d: int) -> void:
	var s := SaveManager.profile.season
	var n := (s.get("weeks", []) as Array).size()
	if n == 0 or _standings:
		return
	_week = (_week + d + n) % n
	Sfx.play("swoosh")
	_refresh()


func _active() -> bool:
	var prof := SaveManager.profile
	return not prof.season.is_empty() and prof.season.get("team", "") == prof.franchise_team


func _refresh() -> void:
	var prof := SaveManager.profile
	var s := prof.season
	if _body != null:
		_panel.remove_child(_body)
		_body.queue_free()
	for c in _nav_extra:
		c.queue_free()
	_nav_extra.clear()
	var nav: HBoxContainer = _ui["nav"]
	if not _active():
		_panel.title = "NEW SEASON"
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 6)
		col.add_child(MetaUI.label("PLAY A %d-GAME SEASON AGAINST REAL TEAMS," % Settings.season_games, UiSkin.WHITE, 8,
				HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(MetaUI.label("THEN THE PLAYOFFS. MAKING THEM PAYS %d COINS," % ModeResults.PLAYOFF_BERTH_COINS,
				UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(MetaUI.label("EVERY PLAYOFF WIN %d. CHAMPIONS GET AN ELITE PACK!" % ModeResults.PLAYOFF_WIN_COINS,
				UiSkin.YELLOW, 8, HORIZONTAL_ALIGNMENT_CENTER))
		_body = col
		_panel.add_child(col)
		_add_nav(MetaUI.spacer())
		_add_nav(MetaUI.continue_button("START SEASON", _new_season, true, 150))
		return
	var you: String = s["team"]
	var table := SeasonRules.standings(s, GameData.teams.keys())
	_add_nav(MetaUI.nav_button("SCHEDULE" if _standings else "STANDINGS", func() -> void:
		_standings = not _standings
		_refresh(), 90))
	_add_nav(MetaUI.spacer())
	match str(s["phase"]):
		"regular", "playoffs":
			var cfg := GameFlow.season_game_config(prof)
			if not cfg.is_empty():
				var play := MetaUI.continue_button("PLAY " + str(cfg.get("label", "")), func() -> void:
					SceneRouter.goto(SceneRouter.PREMATCH, cfg), true, 150)
				_add_nav(play)
				Fx.pulse.call_deferred(play, 1.05, 1.1)
			elif s["phase"] == "playoffs":
				_add_nav(MetaUI.continue_button("SIM ROUND", _sim_round, true, 130))
		"done":
			_add_nav(MetaUI.continue_button("NEXT SEASON", _new_season, true, 130))
	if _standings:
		_panel.title = "STANDINGS  -  YEAR %d" % int(s["year"])
		_body = _standings_view(table, you)
	elif s["phase"] == "regular":
		_panel.title = "WEEK %d" % (_week + 1)
		_body = _week_view(s, _week, you)
	else:
		var po: Dictionary = s["playoffs"]
		_panel.title = "PLAYOFFS" if s["phase"] == "playoffs" else "SEASON OVER"
		var col2 := VBoxContainer.new()
		col2.add_theme_constant_override("separation", 1)
		if s["phase"] == "done":
			var champ: String = po["champion"]
			col2.add_child(MetaUI.label("SUPER BOWL CHAMPIONS: %s" % GameData.team(champ).team_name.to_upper(),
					UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_CENTER))
		else:
			col2.add_child(MetaUI.label("%s ROUND" % SeasonRules.ROUND_NAMES[int(po["round"])], UiSkin.YELLOW, 8,
					HORIZONTAL_ALIGNMENT_CENTER))
			if SeasonRules.my_playoff_game(s).is_empty():
				col2.add_child(MetaUI.label("YOU'RE OUT - SIM THE REST" if po.get("made_it", false) else
						"YOU MISSED THE PLAYOFFS", UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER))
		for line in (po.get("log", []) as Array).slice(-12):
			col2.add_child(MetaUI.label(str(line), UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
		_body = col2
	_panel.add_child(_body)


func _add_nav(c: Control) -> void:
	(_ui["nav"] as HBoxContainer).add_child(c)
	_nav_extra.append(c)


func _week_view(s: Dictionary, w: int, you: String) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	for g in s["weeks"][w]:
		var mine: bool = you in g
		var h := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiSkin.ROW if mine else (Color(1, 1, 1, 0.03) if grid.get_child_count() % 4 < 2 else Color(0, 0, 0, 0))
		sb.content_margin_left = 3
		sb.content_margin_right = 3
		h.add_theme_stylebox_override("panel", sb)
		h.custom_minimum_size = Vector2(196, 13)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 3)
		h.add_child(hb)
		var col := UiSkin.YELLOW if mine else UiSkin.WHITE
		var away: TeamData = GameData.team(g[1])
		var home: TeamData = GameData.team(g[0])
		hb.add_child(HelmetView.new(away, 0.5, false))
		var t := MetaUI.label("%-3s AT %-3s" % [g[1], g[0]], col)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(t)
		hb.add_child(HelmetView.new(home, 0.5, true))
		var res := ""
		for rr in s["results"]:
			if rr[0] == g[0] and rr[1] == g[1]:
				res = "%d-%d" % [int(rr[3]), int(rr[2])]
		var rl := MetaUI.label(res, col, 8, HORIZONTAL_ALIGNMENT_RIGHT)
		rl.custom_minimum_size = Vector2(38, 0)
		hb.add_child(rl)
		grid.add_child(h)
	return grid


func _standings_view(table: Dictionary, you: String) -> Control:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	for conf in ["AFC", "NFC"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		cols.add_child(col)
		col.add_child(MetaUI.label(conf, UiSkin.YELLOW))
		var abbrs: Array = []
		for a in GameData.teams:
			if GameData.team(a).conf == conf:
				abbrs.append(a)
		var ranked := SeasonRules.rank(abbrs, table)
		for i in ranked.size():
			var r: Dictionary = table[ranked[i]]
			col.add_child(MetaUI.label("%2d %-4s %2d-%-2d  %+d" % [i + 1, ranked[i], r["w"], r["l"], int(r["pf"]) - int(r["pa"])],
					UiSkin.YELLOW if ranked[i] == you else (UiSkin.WHITE if i < 7 else UiSkin.MUTED)))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(cols)
	return sc


func _new_season() -> void:
	var prof := SaveManager.profile
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var strengths := {}
	for a in GameData.teams:
		strengths[a] = GameData.db.team_ovr(a)
	strengths[prof.franchise_team] = Collection.team_ovr(prof, GameData.db)
	var year := int(prof.season.get("year", 0)) + 1
	prof.season = SeasonRules.new_season(GameData.teams, prof.franchise_team, Settings.season_games, strengths, rng, year)
	SaveManager.save()
	_week = 0
	Sfx.play("claim")
	_refresh()


func _sim_round() -> void:
	var s := SaveManager.profile.season
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	SeasonRules.advance_round(s, SeasonRules.sim_playoff_round(s, rng))
	SaveManager.save()
	_refresh()
