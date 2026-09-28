extends Control
## HUB: your franchise, team OVR and coins, and the ways into the game.
## Processes the last match result handed back by the match scene.

var prof: Profile
var _body: VBoxContainer
var _header: Label
var _message: Label


func _ready() -> void:
	prof = SaveManager.profile
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var cfg := SceneRouter.take_config()
	var bg := ColorRect.new()
	bg.color = UiTheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 6)
	add_child(root)
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
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	root.add_child(_body)
	if cfg.has("last_result"):
		_process_result(cfg["last_result"])
	_refresh()
	_build_buttons()


func _refresh() -> void:
	var team: TeamData = GameData.team(prof.franchise_team)
	var ovr := Collection.team_ovr(prof, GameData.db)
	var chem := Collection.chemistry(prof, GameData.db)
	_header.text = "%s %s\nTEAM OVR %d  (+%.1f CHEMISTRY)   ·   %d COINS\nRECORD %d-%d-%d" % [
		team.city.to_upper() if team else "", team.team_name.to_upper() if team else "", ovr, chem, prof.coins,
		prof.stats["wins"], prof.stats["losses"], prof.stats["ties"]]


func _build_buttons() -> void:
	var play := Button.new()
	play.text = "PLAY QUICK MATCH"
	play.custom_minimum_size = Vector2(200, 32)
	play.pressed.connect(_quick_match)
	_body.add_child(play)


func _quick_match() -> void:
	var others: Array = GameData.teams.keys()
	others.erase(prof.franchise_team)
	var opp: String = others[randi() % others.size()]
	SceneRouter.goto(SceneRouter.MATCH, {"home": prof.franchise_team, "away": opp, "from_hub": true,
			"difficulty": Settings.difficulty, "mode": "quick"})


func _process_result(r: Dictionary) -> void:
	var won: bool = int(r["pf"]) > int(r["pa"]) and not r.get("forfeit", false)
	var tie: bool = int(r["pf"]) == int(r["pa"]) and not r.get("forfeit", false)
	prof.stats["games"] += 1
	if won:
		prof.stats["wins"] += 1
	elif tie:
		prof.stats["ties"] += 1
	else:
		prof.stats["losses"] += 1
	SaveManager.save()
	_message.text = "%s %d - %d %s" % [r["team"], r["pf"], r["pa"], r["opponent"]]
