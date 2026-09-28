extends Control
## First run: "CHOOSE YOUR TEAM". 32 helmet buttons; tapping one previews its franchise
## star and starting-squad OVR; START grants the starting squad and goes straight into
## the free Starter pack opening (walkout), then the hub.

var _grid: GridContainer
var _info: Label
var _confirm: Button
var _picked := ""
var _ui: Dictionary


func _ready() -> void:
	_ui = MetaUI.screen(self, "CHOOSE YOUR TEAM", "", {"coins": false})
	var root: VBoxContainer = _ui["root"]
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	center.add_child(_grid)
	var abbrs: Array = GameData.teams.keys()
	abbrs.sort()
	for abbr in abbrs:
		var t: TeamData = GameData.teams[abbr]
		var b := Button.new()
		b.custom_minimum_size = Vector2(50, 40)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var h := TextureRect.new()
		h.texture = ArtGen.helmet(abbr, t.uniform_colors(), false)
		h.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.size = Vector2(32, 24)
		h.position = Vector2(9, 3)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var l := MetaUI.label(abbr, UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
		l.position = Vector2(0, 27)
		l.size = Vector2(50, 9)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		b.pressed.connect(_select.bind(abbr))
		b.set_meta("abbr", abbr)
		_grid.add_child(b)
	var nav: HBoxContainer = _ui["nav"]
	_info = MetaUI.label("PICK A TEAM: YOU START WITH ITS REAL PLAYERS AS CARDS", UiSkin.WHITE)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nav.add_child(_info)
	_confirm = MetaUI.continue_button("START", _start, true, 100)
	_confirm.disabled = true
	nav.add_child(_confirm)


func _select(abbr: String) -> void:
	_picked = abbr
	for b in _grid.get_children():
		(b as Button).set_pressed_no_signal(b.get_meta("abbr") == abbr)
		if b.get_meta("abbr") == abbr:
			Fx.pop(b, 1.15, 0.2)
	var t: TeamData = GameData.teams[abbr]
	var pv: Dictionary = GameData.starter_preview(abbr)
	var star: PlayerData = pv.get("star")
	_info.text = "%s %s  -  SQUAD OVR %d\nSTAR: %s" % [t.city.to_upper(), t.team_name.to_upper(), int(pv.get("ovr", 0)),
			"%s %s (%d)" % [star.pos, star.short_name().to_upper(), star.ovr] if star != null else "-"]
	_confirm.disabled = false
	Fx.pop(_confirm, 1.1, 0.2)


func _start() -> void:
	if _picked == "":
		return
	var prof := Profile.new()
	Collection.grant_starters(prof, GameData.db, _picked, int(Time.get_unix_time_from_system()))
	SaveManager.profile = prof
	SaveManager.save()
	var cfg := GameFlow.open_pending_config(prof, SceneRouter.HUB)
	if cfg.is_empty():
		SceneRouter.goto(SceneRouter.HUB)
	else:
		cfg["title"] = "STARTER PACK"
		SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)
