extends Control
## CHALLENGES: scenario vignettes (start state + goal) and a Daily Challenge from the date.
## Rewards are paid the first time each is completed.


func _ready() -> void:
	var ui := MetaUI.screen(self, "CHALLENGES")
	var sc := MetaUI.scroll(ui["root"])
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	var seed_value := ChallengeRules.daily_seed(Time.get_unix_time_from_system())
	var all: Array = [ChallengeRules.daily(seed_value, GameData.teams.keys())]
	all.append_array(ChallengeRules.LIST)
	var done: Dictionary = SaveManager.profile.challenges.get("done", {})
	for c in all:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var reward := "%d COINS" % int(c["coins"])
		if c.get("pack", "") != "":
			reward += " + %s" % PackCatalog.get_pack(c["pack"]).display_name
		col.add_child(MetaUI.label("%s%s   (%s)" % ["[DONE] " if done.has(c["id"]) else "", c["title"], reward],
				UiTheme.ACCENT if not done.has(c["id"]) else UiTheme.DIM))
		col.add_child(MetaUI.label(c["desc"]))
		row.add_child(col)
		var opp: String = c.get("opponent", "PHI")
		if opp == SaveManager.profile.franchise_team:
			opp = "PHI" if opp != "PHI" else "KC"
		row.add_child(MetaUI.button("PLAY", Vector2(60, 26), func() -> void: _play(c, opp, seed_value)))
		list.add_child(row)


func _play(c: Dictionary, opp: String, seed_value: int) -> void:
	SceneRouter.goto(SceneRouter.MATCH, {"home": SaveManager.profile.franchise_team, "away": opp, "from_hub": true,
			"difficulty": Settings.difficulty, "mode": "challenge", "challenge": c,
			"extra": {"challenge": c["id"], "daily_seed": seed_value}})
