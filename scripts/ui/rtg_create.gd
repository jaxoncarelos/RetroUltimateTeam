extends Control
## ROAD TO GLORY - CREATE YOUR PLAYER, three steps on one screen:
##   1 POSITION  (QB / RB / WR / CB: what you do and how it plays)
##   2 ARCHETYPE (three builds per position, with their key ratings and starting OVR)
##   3 IDENTITY  (name with RANDOM / EDIT, jersey number, skin / hair / beard / visor on a live card)
## START YOUR CAREER saves a new career (stage "draft") and goes to the combine & draft.

var _ui: Dictionary
var _body: VBoxContainer
var _step := 1
var _pos := "WR"
var _arch := ""
var _first := ""
var _last := ""
var _jersey := 11
var _look := {"skin": 3, "hair": "short", "hair_color": "black", "beard": "none", "visor": ""}
var _card: RtgCard
var _next: Button
var _rng := RandomNumberGenerator.new()

const VISORS := ["", "clear", "tinted"]


func _ready() -> void:
	_rng.randomize()
	var nm := RtgRules.random_name(_rng)
	_first = nm[0]
	_last = nm[1]
	_look["skin"] = _rng.randi_range(1, 6)
	_look["hair"] = ArtGen.HAIR_STYLES[_rng.randi() % ArtGen.HAIR_STYLES.size()]
	_ui = MetaUI.screen(self, "ROAD TO GLORY", "", {"coins": false})
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	(_ui["root"] as VBoxContainer).add_child(_body)
	var nav: HBoxContainer = _ui["nav"]
	var back := IconButton.new("back")
	back.pressed.connect(_back)
	nav.add_child(back)
	nav.add_child(MetaUI.spacer())
	_next = MetaUI.continue_button("NEXT", _advance, true, 150)
	nav.add_child(_next)
	_show()


func _back() -> void:
	if _step <= 1:
		SceneRouter.goto(SceneRouter.MODE)
		return
	_step -= 1
	Sfx.play("swoosh")
	_show()


func _advance() -> void:
	if _step == 1:
		_step = 2
		_arch = ""
	elif _step == 2:
		if _arch == "":
			return
		_step = 3
		var r: Array = RtgRules.JERSEYS[_pos]
		if _jersey < int(r[0]) or _jersey > int(r[1]):
			_jersey = RtgRules.random_jersey(_pos, _rng)
	else:
		_create()
		return
	Sfx.play("swoosh")
	_show()


func _show() -> void:
	MetaUI.clear(_body)
	(_ui["title"] as TitleBar).text = ["", "CHOOSE YOUR POSITION", "CHOOSE YOUR STYLE", "WHO ARE YOU?"][_step]
	match _step:
		1:
			_positions()
			_next.text = "NEXT ▶"
		2:
			_archetypes()
			_next.text = "NEXT ▶"
			_next.disabled = _arch == ""
		3:
			_identity()
			_next.text = "START YOUR CAREER ▶"
			_next.disabled = false


# ---------------------------------------------------------------- step 1

func _positions() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	_body.add_child(row)
	for pos in RtgRules.POSITIONS:
		var b := _tile(pos == _pos, Vector2(108, 150))
		b.pressed.connect(func() -> void:
			_pos = pos
			Sfx.play("tap")
			_advance())
		row.add_child(b)
		var col := _tile_col(b)
		var sel: bool = pos == _pos
		col.add_child(_sprite(pos))
		col.add_child(MetaUI.label(pos, UiSkin.NAVY_DEEP if sel else UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(MetaUI.label(RtgRules.POS_NAMES[pos], UiSkin.NAVY_DEEP if sel else UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
		var blurb := MetaUI.label(RtgRules.POS_BLURB[pos], UiSkin.NAVY_DEEP if sel else UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(96, 0)
		col.add_child(blurb)


## A small standing sprite of the position in college grays (or your look).
func _sprite(pos: String) -> Control:
	var c := CenterContainer.new()
	c.custom_minimum_size = Vector2(0, 40)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = PlayerSprites.frame_texture(0)
	tr.material = PlayerSprites.make_material(RtgCard.colors(""), hash(pos), _look)
	tr.custom_minimum_size = Vector2(PlayerSprites.FRAME) * 1.5
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tr)
	return c


func _tile(selected: bool, size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	if selected:
		b.theme_type_variation = "YellowButton"
	return b


func _tile_col(b: Button) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 5
	col.offset_right = -5
	col.offset_top = 6
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	return col


# ---------------------------------------------------------------- step 2

func _archetypes() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	for a in RtgRules.ARCHETYPES[_pos]:
		var id: String = a["id"]
		var attrs := RtgRules.start_attrs(_pos, id)
		var b := _tile(id == _arch, Vector2(150, 150))
		b.pressed.connect(func() -> void:
			_arch = id
			Sfx.play("tap")
			_show())
		row.add_child(b)
		var col := _tile_col(b)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(head)
		var nl := MetaUI.label(str(a["name"]), UiSkin.YELLOW if id != _arch else UiSkin.NAVY_DEEP)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nl)
		head.add_child(MetaUI.label("%d OVR" % RtgRules.ovr(_pos, attrs), UiSkin.WHITE if id != _arch else UiSkin.NAVY_DEEP))
		var d := MetaUI.label(str(a["desc"]), UiSkin.MUTED if id != _arch else UiSkin.NAVY_DEEP)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(136, 20)
		col.add_child(d)
		# Its key ratings: the position's weighted attributes, best first.
		var keys: Array = RtgRules.WEIGHTS[_pos].keys()
		keys.sort_custom(func(x: String, y: String) -> bool: return int(attrs[x]) > int(attrs[y]))
		for k in keys.slice(0, 5):
			col.add_child(_attr_bar(k, int(attrs[k]), id == _arch))


static func _attr_bar(key: String, v: int, inverted := false) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := MetaUI.label(RtgRules.ATTR_NAMES.get(key, key.to_upper()), UiSkin.NAVY_DEEP if inverted else UiSkin.WHITE)
	l.custom_minimum_size = Vector2(86, 0)
	h.add_child(l)
	var bar := BarMeter.new(clampf((v - 30) / 69.0, 0.0, 1.0), Vector2(30, 6))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(MetaUI.label(str(v), UiSkin.NAVY_DEEP if inverted else UiSkin.YELLOW))
	return h


# ---------------------------------------------------------------- step 3

func _identity() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var cc := CenterContainer.new()
	row.add_child(cc)
	_card = RtgCard.new(_player(), "", 2)
	cc.add_child(_card)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	col.add_child(name_row)
	var nl := MetaUI.label("%s %s" % [_first, _last], UiSkin.YELLOW, 16)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nl)
	name_row.add_child(MetaUI.button("RANDOM", Vector2(60, 22), func() -> void:
		var nm := RtgRules.random_name(_rng)
		_first = nm[0]
		_last = nm[1]
		Sfx.play("tap")
		_show()))
	name_row.add_child(MetaUI.button("EDIT", Vector2(46, 22), _edit_name))
	col.add_child(MetaUI.label("%s  ·  %s" % [RtgRules.POS_NAMES[_pos], RtgRules.archetype(_pos, _arch)["name"]], UiSkin.MUTED))
	var r: Array = RtgRules.JERSEYS[_pos]
	col.add_child(_cycler("NUMBER", "#%d" % _jersey, func(d: int) -> void:
		_jersey = int(r[0]) + posmod(_jersey - int(r[0]) + d, int(r[1]) - int(r[0]) + 1)))
	col.add_child(_cycler("SKIN", "TONE %d" % int(_look["skin"]), func(d: int) -> void:
		_look["skin"] = 1 + posmod(int(_look["skin"]) - 1 + d, 6)))
	col.add_child(_cycler("HAIR", str(_look["hair"]).to_upper(), func(d: int) -> void:
		_look["hair"] = _next_in(ArtGen.HAIR_STYLES, str(_look["hair"]), d)))
	col.add_child(_cycler("HAIR COLOR", str(_look["hair_color"]).replace("_", " ").to_upper(), func(d: int) -> void:
		_look["hair_color"] = _next_in(ArtGen.HAIR_COLOR_NAMES, str(_look["hair_color"]), d)))
	col.add_child(_cycler("BEARD", str(_look["beard"]).to_upper(), func(d: int) -> void:
		_look["beard"] = _next_in(ArtGen.BEARDS, str(_look["beard"]), d)))
	col.add_child(_cycler("VISOR", "NONE" if _look["visor"] == "" else str(_look["visor"]).to_upper(), func(d: int) -> void:
		_look["visor"] = _next_in(VISORS, str(_look["visor"]), d)))


static func _next_in(list: Array, cur: String, d: int) -> String:
	var i := maxi(list.find(cur), 0)
	return str(list[posmod(i + d, list.size())])


func _cycler(title: String, value: String, change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var t := MetaUI.label(title, UiSkin.WHITE)
	t.custom_minimum_size = Vector2(76, 0)
	h.add_child(t)
	h.add_child(MetaUI.button("◀", Vector2(24, 18), func() -> void:
		change.call(-1)
		Sfx.play("tap")
		_show()))
	var v := MetaUI.label(value, UiSkin.YELLOW, 8, HORIZONTAL_ALIGNMENT_CENTER)
	v.custom_minimum_size = Vector2(96, 0)
	h.add_child(v)
	h.add_child(MetaUI.button("▶", Vector2(24, 18), func() -> void:
		change.call(1)
		Sfx.play("tap")
		_show()))
	return h


## Name entry: two short fields (letters only, phone keyboard).
func _edit_name() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var f := LineEdit.new()
	f.text = _first
	f.max_length = 12
	f.custom_minimum_size = Vector2(170, 22)
	f.placeholder_text = "FIRST NAME"
	col.add_child(f)
	var l := LineEdit.new()
	l.text = _last
	l.max_length = 14
	l.custom_minimum_size = Vector2(170, 22)
	l.placeholder_text = "LAST NAME"
	col.add_child(l)
	MetaUI.popup(self, "YOUR NAME", col, [["CANCEL", Callable()], ["OK", func() -> void:
		var a := clean_name(f.text)
		var b := clean_name(l.text)
		if b != "":
			_first = a
			_last = b
		_show(), true]])
	f.grab_focus.call_deferred()


## Upper-case letters, spaces, apostrophes and dashes only.
static func clean_name(t: String) -> String:
	var out := ""
	for ch in t.to_upper().strip_edges():
		if (ch >= "A" and ch <= "Z") or ch in [" ", "'", "-", "."]:
			out += ch
	return out.strip_edges()


func _player() -> Dictionary:
	return RtgRules.new_player(_pos, _arch if _arch != "" else RtgRules.ARCHETYPES[_pos][0]["id"], _first, _last, _jersey, _look)


func _create() -> void:
	var prof := SaveManager.profile
	prof.rtg = RtgRules.new_career(_player(), str(Time.get_unix_time_from_system()))
	SaveManager.save()
	Sfx.play("big")
	SceneRouter.goto(SceneRouter.RTG_DRAFT)
