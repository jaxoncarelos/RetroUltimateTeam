extends Control
## ROAD TO GLORY - THE COMBINE & DRAFT DAY.
##   1. Combine: run 3 live reps (RtgDrill) in front of the scouts, or skip with a C grade.
##      The grade moves your draft stock.
##   2. Draft day: the board ticks through the picks before yours, "THE PICK IS IN...", then
##      the reveal: helmet, round / pick and "THE <TEAM> SELECT <YOU>". Tap skips ahead.
##      START YOUR CAREER signs the rookie deal and starts season 1.

var _ui: Dictionary
var _body: VBoxContainer
var prof: Profile
var _skip := false
var _revealed := false


func _ready() -> void:
	prof = SaveManager.profile
	var cfg := SceneRouter.take_config()
	if prof.rtg.is_empty() or str(prof.rtg.get("stage", "")) != "draft":
		SceneRouter.goto.call_deferred(SceneRouter.RTG_HUB)
		return
	var drill: Dictionary = cfg.get("drill", {})
	if not drill.is_empty() and str(drill.get("purpose", "")) == "combine" and not prof.rtg.has("combine"):
		prof.rtg["combine"] = float(drill["points"])
		SaveManager.save()
	_ui = MetaUI.screen(self, "THE COMBINE", "", {"coins": false})
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	(_ui["root"] as VBoxContainer).add_child(_body)
	if prof.rtg.has("combine"):
		_draft_day()
	else:
		_combine()


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap and not _revealed:
		_skip = true


# ---------------------------------------------------------------- combine

func _combine() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	_body.add_child(row)
	var cc := CenterContainer.new()
	row.add_child(cc)
	cc.add_child(RtgCard.new(prof.rtg["player"], "", 2))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var p: Dictionary = prof.rtg["player"]
	col.add_child(MetaUI.label("%s %s" % [p["first"], p["last"]], UiSkin.YELLOW, 16))
	col.add_child(MetaUI.label("%s  ·  %s  ·  %d OVR" % [p["pos"], RtgRules.archetype(str(p["pos"]), str(p["arch"]))["name"],
			RtgRules.ovr(str(p["pos"]), p["attrs"])], UiSkin.WHITE))
	var t := MetaUI.label("EVERY SCOUT IN THE LEAGUE IS WATCHING. THREE LIVE REPS AT YOUR POSITION: "
			+ "YOUR COMBINE GRADE MOVES YOUR DRAFT STOCK (A GREAT DAY CAN MAKE YOU A FIRST-ROUNDER). "
			+ "IT'S ALSO THE BEST WAY TO LEARN YOUR CONTROLS.", UiSkin.MUTED)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(250, 0)
	col.add_child(t)
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.button("SKIP (C GRADE)", Vector2(120, 28), func() -> void:
		prof.rtg["combine"] = 60.0
		SaveManager.save()
		SceneRouter.goto(SceneRouter.RTG_DRAFT)))
	nav.add_child(MetaUI.spacer())
	var go := MetaUI.continue_button("RUN THE COMBINE", func() -> void:
		SceneRouter.goto(SceneRouter.RTG_DRILL, {"player": prof.rtg["player"], "purpose": "combine",
				"back": SceneRouter.RTG_DRAFT}), true, 170)
	nav.add_child(go)
	Fx.pulse.call_deferred(go, 1.04, 1.0)


# ---------------------------------------------------------------- draft day

func _draft_day() -> void:
	(_ui["title"] as TitleBar).text = "DRAFT DAY"
	var d := RtgFlow.draft(prof.rtg, float(prof.rtg["combine"]))
	SaveManager.save()
	_run_draft(d)


func _run_draft(d: Dictionary) -> void:
	var panel := RetroPanel.new("ROUND %d" % int(d["round"]), UiSkin.PANEL, 6)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	var combine_l := MetaUI.label("COMBINE GRADE: %s" % RtgTracker.letter(float(d.get("combine", 60.0))), UiSkin.MUTED)
	col.add_child(combine_l)
	for b in d["board"]:
		if not _skip:
			await get_tree().create_timer(0.45).timeout
		var t: TeamData = GameData.team(str(b[1]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var helm := TextureRect.new()
		helm.texture = ArtGen.helmet(str(b[1]), t.uniform_colors() if t != null else {})
		helm.custom_minimum_size = Vector2(24, 18)
		helm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		helm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(helm)
		row.add_child(MetaUI.label("PICK %d" % int(b[0]), UiSkin.MUTED))
		row.add_child(MetaUI.label(t.team_name.to_upper() if t != null else str(b[1]), UiSkin.WHITE))
		row.add_child(MetaUI.label(str(b[2]), UiSkin.YELLOW))
		col.add_child(row)
		Sfx.play("tap")
	if not _skip:
		await get_tree().create_timer(0.5).timeout
	var drum := MetaUI.label("THE PICK IS IN...", UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(drum)
	Fx.pulse.call_deferred(drum, 1.08, 0.5)
	Sfx.play("swoosh")
	if not _skip:
		await get_tree().create_timer(1.4).timeout
	_reveal(d)


func _reveal(d: Dictionary) -> void:
	_revealed = true
	MetaUI.clear(_body)
	var team: TeamData = GameData.team(str(d["team"]))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_body.add_child(row)
	var card := RtgCard.new(prof.rtg["player"], str(d["team"]), 2)
	var cc := CenterContainer.new()
	cc.add_child(card)
	row.add_child(cc)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 5)
	row.add_child(col)
	var helm := TextureRect.new()
	helm.texture = ArtGen.helmet(str(d["team"]), team.uniform_colors())
	helm.custom_minimum_size = Vector2(64, 48)
	helm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	helm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(helm)
	col.add_child(MetaUI.label("ROUND %d  ·  PICK %d  (#%d OVERALL)" % [int(d["round"]), int(d["pick"]), int(d["overall"])], UiSkin.MUTED))
	col.add_child(MetaUI.label("THE %s SELECT" % team.team_name.to_upper(), UiSkin.WHITE))
	var p: Dictionary = prof.rtg["player"]
	var nm := MetaUI.label("%s %s %s" % [p["pos"], p["first"], p["last"]], UiSkin.YELLOW, 16)
	col.add_child(nm)
	col.add_child(MetaUI.label("ROOKIE DEAL: %d YEARS  ·  %s / YR" % [RtgRules.rookie_contract(d)["years"],
			RtgRules.rookie_contract(d)["salary"]], UiSkin.GREEN))
	nm.pivot_offset = Vector2(100, 8)
	nm.scale = Vector2(1.6, 1.6)
	nm.create_tween().tween_property(nm, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.flash(self, Color(team.primary.lightened(0.4), 0.5), 0.4)
	Fx.confetti(self, size.x, [team.primary, team.secondary, Color.WHITE], 70)
	Sfx.play("elite" if int(d["round"]) == 1 else "big")
	Sfx.play("cheer")
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.spacer())
	var go := MetaUI.continue_button("START YOUR CAREER", func() -> void:
		RtgFlow.sign_rookie(prof.rtg)
		SaveManager.save()
		SceneRouter.goto(SceneRouter.RTG_HUB), true, 180)
	nav.add_child(go)
	Fx.pulse.call_deferred(go, 1.04, 1.0)
