extends Control
## SEASON: an 8- or 17-game schedule vs real teams (other games simulated), standings,
## then 7-team-per-conference playoffs to the Super Bowl (Elite pack for the champion).

var _ui: Dictionary
var _body: VBoxContainer


func _ready() -> void:
	_ui = MetaUI.screen(self, "SEASON")
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui["root"].add_child(_body)
	_refresh()


func _refresh() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var prof := SaveManager.profile
	var s := prof.season
	if s.is_empty() or s.get("team", "") != prof.franchise_team:
		_body.add_child(MetaUI.label("PLAY A %d-GAME SEASON AGAINST REAL TEAMS, THEN THE PLAYOFFS." % Settings.season_games))
		_body.add_child(MetaUI.label("SUPER BOWL CHAMPIONS GET AN ELITE PACK.", UiTheme.DIM))
		_body.add_child(MetaUI.button("START SEASON", Vector2(160, 28), _new_season))
		return
	var table := SeasonRules.standings(s, GameData.teams.keys())
	var you: String = s["team"]
	var rec: Dictionary = table[you]
	var head := "YEAR %d  ·  %s  ·  %d-%d-%d" % [int(s["year"]), you, rec["w"], rec["l"], rec["t"]]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(MetaUI.label(head, UiTheme.ACCENT))
	match str(s["phase"]):
		"regular":
			var w := int(s["week"])
			var g := _find_game(s["weeks"][w], you)
			var home: bool = g[0] == you
			var opp: String = g[1] if home else g[0]
			info.add_child(MetaUI.label("WEEK %d OF %d:  %s %s  (OVR %d)" % [w + 1, int(s["games"]),
					"VS" if home else "AT", GameData.team(opp).team_name.to_upper(), int(s["ovr"].get(opp, 75))]))
			row.add_child(MetaUI.button("PLAY WEEK %d" % (w + 1), Vector2(110, 28), func() -> void: _play(g, "WEEK %d" % (w + 1))))
		"playoffs":
			var po: Dictionary = s["playoffs"]
			info.add_child(MetaUI.label("PLAYOFFS: %s ROUND" % SeasonRules.ROUND_NAMES[int(po["round"])]))
			var mine := SeasonRules.my_playoff_game(s)
			if not mine.is_empty():
				row.add_child(MetaUI.button("PLAY %s" % SeasonRules.ROUND_NAMES[int(po["round"])], Vector2(130, 28),
						func() -> void: _play(mine, SeasonRules.ROUND_NAMES[int(po["round"])])))
			else:
				info.add_child(MetaUI.label("YOU'RE OUT. WATCH THE REST:" if po["made_it"] else "YOU MISSED THE PLAYOFFS.",
						UiTheme.DIM))
				row.add_child(MetaUI.button("SIM ROUND", Vector2(110, 28), _sim_round))
		"done":
			var champ: String = s["playoffs"]["champion"]
			info.add_child(MetaUI.label("SUPER BOWL CHAMPIONS: %s %s" % [GameData.team(champ).city.to_upper(),
					GameData.team(champ).team_name.to_upper()], UiTheme.ACCENT if champ == you else UiTheme.TEXT))
			row.add_child(MetaUI.button("NEXT SEASON", Vector2(110, 28), _new_season))
	var sc := MetaUI.scroll(_body)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	sc.add_child(cols)
	for conf in ["AFC", "NFC"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		cols.add_child(col)
		col.add_child(MetaUI.label("%s STANDINGS" % conf, UiTheme.ACCENT))
		var abbrs: Array = []
		for a in GameData.teams:
			if GameData.team(a).conf == conf:
				abbrs.append(a)
		var ranked := SeasonRules.rank(abbrs, table)
		for i in ranked.size():
			var r: Dictionary = table[ranked[i]]
			var l := MetaUI.label("%2d %-4s %d-%d-%d  %+d" % [i + 1, ranked[i], r["w"], r["l"], r["t"], int(r["pf"]) - int(r["pa"])],
					UiTheme.ACCENT if ranked[i] == you else UiTheme.TEXT)
			col.add_child(l)
	if s["phase"] != "regular":
		var logc := VBoxContainer.new()
		cols.add_child(logc)
		logc.add_child(MetaUI.label("PLAYOFFS", UiTheme.ACCENT))
		for line in s["playoffs"].get("log", []):
			logc.add_child(MetaUI.label(line))


func _find_game(week: Array, you: String) -> Array:
	for g in week:
		if you in g:
			return g
	return [you, you]


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
	_refresh()


func _play(g: Array, label: String) -> void:
	var prof := SaveManager.profile
	var you := prof.franchise_team
	var opp: String = g[1] if g[0] == you else g[0]
	SceneRouter.goto(SceneRouter.MATCH, {"home": you, "away": opp, "from_hub": true, "difficulty": Settings.difficulty,
			"mode": "season", "extra": {"home": g[0], "away": g[1], "label": label}})


func _sim_round() -> void:
	var s := SaveManager.profile.season
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	SeasonRules.advance_round(s, SeasonRules.sim_playoff_round(s, rng))
	SaveManager.save()
	_refresh()
