extends Control
## HUB: your franchise (badge, team OVR, chemistry, coins, record) and every way into the
## game. Processes the last match result handed back by the match scene: record, coins
## (postgame rewards), season/challenge progress.

var prof: Profile
var _header: Label
var _message: Label
var _diff: Button


func _ready() -> void:
	prof = SaveManager.profile
	var cfg := SceneRouter.take_config()
	var ui := MetaUI.screen(self, "POCKET GRIDIRON", "")
	var root: VBoxContainer = ui["root"]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var team: TeamData = GameData.team(prof.franchise_team)
	if team != null:
		top.add_child(TeamBadge.new(team, 2))
	_header = Label.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_message = Label.new()
	_message.add_theme_color_override("font_color", UiTheme.ACCENT)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_message)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)
	var size := Vector2(110, 34)
	grid.add_child(MetaUI.button("QUICK MATCH", size, _quick_match))
	grid.add_child(MetaUI.button("SEASON", size, func() -> void: SceneRouter.goto("res://scenes/meta/season.tscn")))
	grid.add_child(MetaUI.button("CHALLENGES", size, func() -> void: SceneRouter.goto("res://scenes/meta/challenges.tscn")))
	grid.add_child(MetaUI.button("STORE", size, func() -> void: SceneRouter.goto("res://scenes/meta/store.tscn")))
	grid.add_child(MetaUI.button("LINEUP", size, func() -> void: SceneRouter.goto("res://scenes/meta/lineup.tscn")))
	grid.add_child(MetaUI.button("COLLECTION", size, func() -> void: SceneRouter.goto("res://scenes/meta/collection.tscn")))
	grid.add_child(MetaUI.button("SETS", size, func() -> void: SceneRouter.goto("res://scenes/meta/sets.tscn")))
	grid.add_child(MetaUI.button("SETTINGS", size, func() -> void: SceneRouter.goto("res://scenes/meta/settings.tscn")))
	for b in grid.get_children():
		# Screens that are not built yet stay disabled.
		var target := "res://scenes/meta/%s.tscn" % (b as Button).text.to_lower().replace(" ", "_")
		if (b as Button).text in ["SEASON", "CHALLENGES", "SETTINGS"] and not ResourceLoader.exists(target):
			(b as Button).disabled = true
	_diff = MetaUI.button("", Vector2(226, 24), _cycle_difficulty)
	root.add_child(_diff)
	if cfg.has("last_result"):
		_process_result(cfg["last_result"])
	_refresh(ui)


func _refresh(ui: Dictionary = {}) -> void:
	var team: TeamData = GameData.team(prof.franchise_team)
	var ovr := Collection.team_ovr(prof, GameData.db)
	var chem := Collection.chemistry(prof, GameData.db)
	_header.text = "%s %s\nTEAM OVR %d  (+%.1f CHEMISTRY)\nRECORD %d-%d-%d  ·  PACKS OPENED %d" % [
		team.city.to_upper() if team else "", team.team_name.to_upper() if team else "", ovr, chem,
		prof.stats["wins"], prof.stats["losses"], prof.stats["ties"], prof.stats["packs_opened"]]
	var d: Array = TeamRating.DIFFICULTY[Settings.difficulty]
	_diff.text = "DIFFICULTY: %s  (COINS X%.2f)" % [d[0], d[2]]
	if ui.has("coins"):
		ui["coins"].text = "%d COINS" % prof.coins


func _cycle_difficulty() -> void:
	Settings.difficulty = (Settings.difficulty + 1) % TeamRating.DIFFICULTY.size()
	Settings.save_settings()
	_refresh()


## Opponent for a quick match: any other team.
func _quick_match() -> void:
	var others: Array = GameData.teams.keys()
	others.erase(prof.franchise_team)
	var opp: String = others[randi() % others.size()]
	SceneRouter.goto(SceneRouter.MATCH, {"home": prof.franchise_team, "away": opp, "from_hub": true,
			"difficulty": Settings.difficulty, "mode": "quick"})


func _process_result(r: Dictionary) -> void:
	var forfeit: bool = r.get("forfeit", false)
	var won: bool = int(r["pf"]) > int(r["pa"]) and not forfeit
	var tie: bool = int(r["pf"]) == int(r["pa"]) and not forfeit
	prof.stats["games"] += 1
	if won:
		prof.stats["wins"] += 1
	elif tie:
		prof.stats["ties"] += 1
	else:
		prof.stats["losses"] += 1
	var today := int(Time.get_unix_time_from_system() / 86400)
	var first_win := won and int(prof.stats["last_win_day"]) != today
	if won:
		prof.stats["last_win_day"] = today
	var rw := EconomyRules.match_rewards(r, first_win)
	prof.coins += int(rw["total"])
	prof.stats["coins_earned"] += int(rw["total"])
	var lines: Array[String] = []
	for l in rw["lines"]:
		lines.append("%s +%d" % [l[0], l[1]])
	var head := "%s %d - %d %s" % [r["team"], r["pf"], r["pa"], r["opponent"]]
	if forfeit:
		head = "FORFEIT vs %s" % r["opponent"]
	_message.text = "%s   ·   REWARDS +%d COINS\n%s" % [head, rw["total"], "   ".join(lines)]
	var extra := ModeResults.apply(r, prof, GameData.db)
	if extra != "":
		_message.text += "\n" + extra
	if rw["total"] > 0:
		Sfx.play("coin")
	SaveManager.save()
