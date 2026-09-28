extends Control
## MODE SELECT: big stacked buttons with icons (Season, Quick Match, Challenges,
## Ultimate Team), Retro Bowl style.


func _ready() -> void:
	var ui := MetaUI.screen(self, "MODE SELECT")
	var root: VBoxContainer = ui["root"]
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 7)
	var season_label := "SEASON MODE"
	var s := SaveManager.profile.season
	if not s.is_empty() and s.get("phase", "") != "done":
		season_label = "SEASON  -  WEEK %d" % (int(s.get("week", 0)) + 1) if s.get("phase", "") == "regular" else "SEASON  -  PLAYOFFS"
	_mode(root, "calendar", season_label, "PLAYOFFS, ELITE PACK FOR CHAMPS",
			func() -> void: SceneRouter.goto(SceneRouter.SEASON))
	_mode(root, "ball", "QUICK MATCH", "1 GAME  -  WIN FOR %d COINS" % EconomyRules.WIN_COINS,
			func() -> void: SceneRouter.goto(SceneRouter.PREMATCH, GameFlow.next_quick_config(SaveManager.profile)))
	var done: Dictionary = SaveManager.profile.challenges.get("done", {})
	var left := ChallengeRules.LIST.size() - done.size()
	_mode(root, "flame", "CHALLENGES", "CLUTCH SCENARIOS  -  %d TO BEAT" % maxi(left, 0),
			func() -> void: SceneRouter.goto(SceneRouter.CHALLENGES))
	_mode(root, "cards", "ULTIMATE TEAM", "OPEN PACKS, BUILD YOUR SQUAD",
			func() -> void: SceneRouter.goto(SceneRouter.STORE))


func _mode(parent: Control, icon: String, title: String, sub: String, cb: Callable) -> void:
	var row := CenterContainer.new()
	parent.add_child(row)
	var b := MetaUI.button("", Vector2(280, 36), cb)
	row.add_child(b)
	var ic := TextureRect.new()
	ic.texture = UiSkin.icon(icon)
	ic.size = UiSkin.icon(icon).get_size() * 2.0
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.position = Vector2(10, roundf((34 - ic.size.y) * 0.5))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = UiSkin.YELLOW
	b.add_child(ic)
	var t := MetaUI.label(title, UiSkin.WHITE)
	t.position = Vector2(44, 7)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	var st := MetaUI.label(sub, UiSkin.MUTED)
	st.position = Vector2(44, 18)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(st)
