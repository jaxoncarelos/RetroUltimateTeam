extends Control
## OPTIONS (Retro Bowl settings layout): label + value button pairs in a grid - quarter
## length, defense pace, difficulty, season length, sound, screen shake, coach tips,
## favorite team, and a two-tap career reset.

var _grid: GridContainer
var _confirm_reset := false


func _ready() -> void:
	var ui := MetaUI.screen(self, "OPTIONS")
	var ver := MetaUI.label("V0.7", UiSkin.WHITE)
	ui["top_right"].add_child(ver)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui["root"].add_child(center)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	center.add_child(_grid)
	_refresh()


func _refresh() -> void:
	MetaUI.clear(_grid)
	var s := Settings
	_row("QUARTERS", "%.1f MIN" % s.quarter_minutes, func() -> void:
		var opts := [1.5, 2.5, 3.5, 5.0]
		s.quarter_minutes = opts[(opts.find(s.quarter_minutes) + 1) % opts.size()])
	_row("DIFFICULTY", "%s x%.2f" % [TeamRating.DIFFICULTY[s.difficulty][0], TeamRating.DIFFICULTY[s.difficulty][2]],
			func() -> void: s.difficulty = (s.difficulty + 1) % TeamRating.DIFFICULTY.size())
	_row("DEFENSE\nPACE", DefensePace.NAMES[s.defense_pace], func() -> void:
		s.defense_pace = (s.defense_pace + 1) % DefensePace.NAMES.size())
	_row("SEASON\nLENGTH", "%d GAMES" % s.season_games, func() -> void:
		s.season_games = 17 if s.season_games == 8 else 8)
	_row("SOUND", "OFF" if s.sfx_volume <= 0.0 else ("LOW" if s.sfx_volume < 0.6 else "HIGH"), func() -> void:
		s.sfx_volume = 0.4 if s.sfx_volume <= 0.0 else (0.8 if s.sfx_volume < 0.6 else 0.0))
	_row("SCREEN\nSHAKE", "ON" if s.shake else "OFF", func() -> void: s.shake = not s.shake)
	_row("COACH\nTIPS", "REPLAY" if s.tutorial_done else "ON", func() -> void: s.tutorial_done = false)
	var team: TeamData = GameData.team(SaveManager.profile.franchise_team)
	_row("RESET\nCAREER", "SURE? TAP" if _confirm_reset else "RESET", _reset, false)
	if team != null:
		var l := MetaUI.label("FAVORITE TEAM", UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_RIGHT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_grid.add_child(l)
		var b := MetaUI.button(team.team_name.to_upper(), Vector2(96, 26), func() -> void: pass)
		b.disabled = true
		_grid.add_child(b)


func _row(label: String, value: String, cb: Callable, saves := true) -> void:
	var l := MetaUI.label(label, UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_RIGHT)
	l.custom_minimum_size = Vector2(80, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_grid.add_child(l)
	_grid.add_child(MetaUI.button(value, Vector2(96, 26), func() -> void:
		cb.call()
		if saves:
			Settings.save_settings()
		_refresh()))


func _reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		return
	SaveManager.reset()
	SceneRouter.goto(SceneRouter.TEAM_PICK)
