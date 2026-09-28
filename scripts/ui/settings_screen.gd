extends Control
## SETTINGS: game length, defense pace, difficulty, season length, sound, shake, tutorial,
## and resetting the career.

var _list: VBoxContainer
var _confirm_reset := false


func _ready() -> void:
	var ui := MetaUI.screen(self, "SETTINGS")
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	ui["root"].add_child(_list)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var s := Settings
	_row("QUARTER LENGTH: %.1f MIN" % s.quarter_minutes, func() -> void:
		var opts := [1.5, 2.5, 3.5, 5.0]
		s.quarter_minutes = opts[(opts.find(s.quarter_minutes) + 1) % opts.size()])
	_row("DEFENSE PACE: %s" % DefensePace.NAMES[s.defense_pace], func() -> void:
		s.defense_pace = (s.defense_pace + 1) % DefensePace.NAMES.size())
	_row("DIFFICULTY: %s" % TeamRating.DIFFICULTY[s.difficulty][0], func() -> void:
		s.difficulty = (s.difficulty + 1) % TeamRating.DIFFICULTY.size())
	_row("SEASON LENGTH: %d GAMES (NEXT SEASON)" % s.season_games, func() -> void:
		s.season_games = 17 if s.season_games == 8 else 8)
	_row("SOUND: %s" % ("OFF" if s.sfx_volume <= 0.0 else ("LOW" if s.sfx_volume < 0.6 else "HIGH")), func() -> void:
		s.sfx_volume = 0.4 if s.sfx_volume <= 0.0 else (0.8 if s.sfx_volume < 0.6 else 0.0)
		Sfx.play("tap"))
	_row("SCREEN SHAKE: %s" % ("ON" if s.shake else "OFF"), func() -> void: s.shake = not s.shake)
	_row("REPLAY COACH TIPS" if s.tutorial_done else "COACH TIPS: ON", func() -> void: s.tutorial_done = false)
	var reset := MetaUI.button("RESET CAREER (TAP TWICE)" if not _confirm_reset else "REALLY RESET? TAP AGAIN",
			Vector2(300, 22), _reset)
	_list.add_child(reset)


func _row(text: String, cb: Callable) -> void:
	_list.add_child(MetaUI.button(text, Vector2(300, 22), func() -> void:
		cb.call()
		Settings.save_settings()
		_refresh()))


func _reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_refresh()
		return
	SaveManager.reset()
	SceneRouter.goto(SceneRouter.TEAM_PICK)
