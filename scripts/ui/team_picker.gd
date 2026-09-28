extends Control
## First run: "PICK YOUR NFL TEAM". 32 badges; tapping one shows its stars and team OVR;
## confirming grants the starter cards (top 5 Silver, the rest Bronze) and opens the hub.

var _grid: GridContainer
var _info: Label
var _confirm: Button
var _picked := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 6
	box.offset_bottom = -6
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.text = "PICK YOUR NFL TEAM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)
	_grid = GridContainer.new()
	_grid.columns = 11
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	box.add_child(_grid)
	var abbrs: Array = GameData.teams.keys()
	abbrs.sort()
	for abbr in abbrs:
		var t: TeamData = GameData.teams[abbr]
		var b := Button.new()
		b.custom_minimum_size = Vector2(38, 44)
		b.toggle_mode = true
		b.tooltip_text = "%s %s" % [t.city, t.team_name]
		var badge := TeamBadge.new(t, 2)
		badge.position = Vector2(3, 3)
		b.add_child(badge)
		b.pressed.connect(func() -> void: _select(abbr))
		b.set_meta("abbr", abbr)
		_grid.add_child(b)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	box.add_child(bottom)
	_info = Label.new()
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.text = "YOU START WITH YOUR TEAM'S REAL PLAYERS AS CARDS.\nTHE TOP 5 ARE SILVER, THE REST BRONZE."
	bottom.add_child(_info)
	_confirm = Button.new()
	_confirm.text = "START\nCAREER"
	_confirm.custom_minimum_size = Vector2(72, 40)
	_confirm.disabled = true
	_confirm.pressed.connect(_start)
	bottom.add_child(_confirm)


func _select(abbr: String) -> void:
	_picked = abbr
	for b in _grid.get_children():
		b.button_pressed = b.get_meta("abbr") == abbr
	var t: TeamData = GameData.teams[abbr]
	var roster: Array = GameData.team_players(abbr).duplicate()
	roster.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.ovr > b.ovr)
	var stars: Array[String] = []
	for p: PlayerData in roster:
		if not p.generated and stars.size() < 3:
			stars.append("%s %s" % [p.pos, p.short_name()])
	_info.text = "%s %s  ·  TEAM OVR %d\nSTARS: %s" % [t.city.to_upper(), t.team_name.to_upper(),
			GameData.db.team_ovr(abbr), ", ".join(stars) if not stars.is_empty() else "-"]
	_confirm.disabled = false


func _start() -> void:
	if _picked == "":
		return
	var prof := Profile.new()
	Collection.grant_starters(prof, GameData.db, _picked, int(Time.get_unix_time_from_system()))
	SaveManager.profile = prof
	SaveManager.save()
	SceneRouter.goto(SceneRouter.HUB)
