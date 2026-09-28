extends Control
## Pack opening: cards start face down in ascending rarity; tap each (or FLIP ALL) to
## reveal. Gold and Elite pulls flash. The cards were already saved when the pack was
## bought, so leaving early loses nothing.

var _cards: Array[CardView] = []
var _next := 0
var _back := "res://scenes/meta/hub.tscn"
var _info: Label


func _ready() -> void:
	var cfg := SceneRouter.take_config()
	_back = cfg.get("back", _back)
	var ui := MetaUI.screen(self, cfg.get("title", "PACK"), "")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui["root"].add_child(row)
	var prof := SaveManager.profile
	var owned_before := {}
	for e in prof.cards:
		if int(e["uid"]) not in cfg.get("uids", []):
			owned_before[e["def"]] = true
	for uid in cfg.get("uids", []):
		var e := prof.find(int(uid))
		var c: CardDef = GameData.card(e.get("def", ""))
		if c == null:
			continue
		var v := CardView.new(c, e, 2 if cfg.get("uids", []).size() <= 4 else 1)
		v.face_down = true
		v.set_meta("dupe", owned_before.has(e["def"]))
		v.tapped.connect(func(_v: CardView) -> void: _flip_next())
		row.add_child(v)
		_cards.append(v)
	_info = MetaUI.label("TAP TO REVEAL", UiTheme.DIM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui["root"].add_child(_info)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 8)
	ui["root"].add_child(bottom)
	bottom.add_child(MetaUI.button("FLIP ALL", Vector2(90, 26), _flip_all))
	bottom.add_child(MetaUI.button("DONE", Vector2(90, 26), func() -> void: SceneRouter.goto(_back)))


func _flip_next() -> void:
	if _next >= _cards.size():
		return
	var v := _cards[_next]
	_next += 1
	v.face_down = false
	if v.card.tier >= CardRules.Tier.GOLD:
		v.flash = 1.0
		Sfx.play("big")
	else:
		Sfx.play("flip")
	var p: PlayerData = v.player
	_info.text = "%s %s  ·  %s %d%s" % [p.pos, p.name.to_upper(), CardRules.NAMES[v.card.tier], v.card.ovr,
			"  (DUPLICATE: TRAIN OR SELL IT)" if v.get_meta("dupe") else "  NEW!"]


func _flip_all() -> void:
	while _next < _cards.size():
		_flip_next()
