extends Control
## CHALLENGES: a Hall-of-Fame style framed list of scenario vignettes (the Daily first) with
## crown icons (gold once beaten), rewards and PLAY buttons. First clears pay.


func _ready() -> void:
	var ui := MetaUI.screen(self, "CHALLENGES")
	var done: Dictionary = SaveManager.profile.challenges.get("done", {})
	var seed_value := ChallengeRules.daily_seed(Time.get_unix_time_from_system())
	var all: Array = [ChallengeRules.daily(seed_value, GameData.teams.keys())]
	all.append_array(ChallengeRules.LIST)
	var beaten := 0
	for c in all:
		if done.has(c["id"]):
			beaten += 1
	var panel := RetroPanel.new("BEATEN %d / %d" % [beaten, all.size()], UiSkin.PANEL, 5)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui["root"].add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for c in all:
		var is_done := done.has(c["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var crown := TextureRect.new()
		crown.texture = UiSkin.icon("crown")
		crown.modulate = UiSkin.YELLOW if is_done else UiSkin.GREY
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(crown)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var reward := "+%d" % int(c["coins"])
		if c.get("pack", "") != "":
			reward += " + %s" % PackCatalog.get_pack(c["pack"]).display_name
		var head := HBoxContainer.new()
		var t := MetaUI.label(str(c["title"]), UiSkin.YELLOW if str(c["id"]).begins_with("daily") else UiSkin.WHITE)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		head.add_child(MetaUI.label("DONE" if is_done else reward, UiSkin.GREEN if is_done else UiSkin.YELLOW))
		col.add_child(head)
		col.add_child(MetaUI.label(str(c["desc"]), UiSkin.MUTED))
		row.add_child(col)
		var opp: String = c.get("opponent", "PHI")
		if opp == SaveManager.profile.franchise_team:
			opp = "PHI" if opp != "PHI" else "KC"
		var b := MetaUI.yellow("PLAY", Vector2(54, 24), _play.bind(c, opp, seed_value)) if not is_done \
				else MetaUI.button("REPLAY", Vector2(54, 24), _play.bind(c, opp, seed_value))
		row.add_child(b)
		list.add_child(row)


func _play(c: Dictionary, opp: String, seed_value: int) -> void:
	SceneRouter.goto(SceneRouter.MATCH, {"home": SaveManager.profile.franchise_team, "away": opp, "from_hub": true,
			"difficulty": Settings.difficulty, "mode": "challenge", "challenge": c,
			"extra": {"challenge": c["id"], "daily_seed": seed_value}})
