extends Control
## Draft-style packs (DRAFT PACK, QB / RECEIVER / DEFENSE / TRENCHES DRAFT): face-down
## prospects you only get hints about (each card glows in its tier color and shows its
## position, or its team when they all play the same position; X-Factor cards crackle pink). Tap one, KEEP IT, and
## it flips with the usual celebration; then the other two flip over to show what you
## passed on. The options were saved when the pack was bought (Profile.pending_pick), so
## leaving here and coming back offers the same three.

var _back := SceneRouter.STORE
var _prof: Profile
var _ids: Array = []
var _views: Array[CardView] = []
var _hints: Array[Label] = []
var _chosen := -1
var _done := false
var _keep: Button
var _info: Label
var _bar: HBoxContainer
var _t := 0.0
var _pack: PackDef


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var cfg := SceneRouter.take_config()
	_back = cfg.get("back", _back)
	_prof = SaveManager.profile
	if not EconomyRules.has_pending_draft(_prof):
		SceneRouter.goto.call_deferred(_back)
		return
	_ids = _prof.pending_pick.get("options", [])
	_pack = PackCatalog.get_pack(str(_prof.pending_pick.get("pack", "")))
	_build()


func _build() -> void:
	var bg := RetroBg.new()
	bg.header_line = 0
	bg.footer_line = 0
	bg.tint = Color(0.5, 0.7, 0.55)
	add_child(bg)
	var head := TitleBar.new("%s  -  KEEP ONE" % (_pack.display_name if _pack != null else "DRAFT"))
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = 26
	add_child(head)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 30
	col.offset_bottom = -6 - SafeArea.bottom()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	# One position (QB draft…): the team is the second hint instead of the position.
	var positions := {}
	for id in _ids:
		var oc: CardDef = GameData.card(str(id))
		if oc != null:
			positions[GameData.player(oc.player_id).pos] = true
	var by_team := positions.size() == 1 and _ids.size() > 1
	_info = MetaUI.label("THE GLOW TELLS THE TIER. THE CHIP TELLS THE %s. CHOOSE WISELY." % ("TEAM" if by_team else "POSITION"),
			UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22 if _ids.size() <= 3 else 8)
	col.add_child(row)
	for i in _ids.size():
		var c: CardDef = GameData.card(str(_ids[i]))
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 3)
		row.add_child(slot)
		var v := CardView.new(c, {}, 2)
		v.face_down = true
		v.glow = 0.7
		v.tapped.connect(func(_v: CardView) -> void: _select(i))
		slot.add_child(v)
		_views.append(v)
		var p: PlayerData = GameData.player(c.player_id) if c != null else null
		var chip := "?"
		if p != null:
			chip = p.team if by_team else p.pos
		var hint := MetaUI.label("%s%s" % [chip, "  ⚡" if c != null and c.is_xfactor() else ""],
				Color.WHITE, 16, HORIZONTAL_ALIGNMENT_CENTER)
		slot.add_child(hint)
		_hints.append(hint)
	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 8)
	col.add_child(_bar)
	_keep = MetaUI.yellow("TAP A CARD", Vector2(150, 26), _confirm)
	_keep.disabled = true
	_bar.add_child(_keep)


func _process(delta: float) -> void:
	_t += delta
	# Face-down cards breathe in their tier color: the only hint at what is inside.
	for i in _views.size():
		var v := _views[i]
		if v.face_down:
			var c: CardDef = v.card
			var tier := c.tier if c != null else 0
			v.glow = 0.45 + 0.25 * sin(_t * (2.0 + tier) + i) + (0.2 if i == _chosen else 0.0)
			if c != null and c.is_xfactor() and randf() < delta * 3.0:
				Fx.burst(self, v.global_position + Vector2(randf() * v.size.x, randf() * v.size.y),
						CardRules.PROGRAM_COLORS["xf"], 3, 30.0, 0.3, 1.0)


## The face-down hint glow uses the card's tier color (CardView draws glow in tier color).
func _select(i: int) -> void:
	if _done:
		return
	_chosen = i
	Sfx.play("tap")
	for k in _views.size():
		_views[k].selected = k == i
		var tw := _views[k].create_tween()
		tw.tween_property(_views[k], "position:y", -8.0 if k == i else 0.0, 0.12)
	_keep.disabled = false
	_keep.text = "KEEP THIS ONE"


func _confirm() -> void:
	if _done or _chosen < 0:
		return
	var uid := EconomyRules.pick_draft(_prof, GameData.db, _chosen, int(Time.get_unix_time_from_system()))
	if uid < 0:
		return
	_done = true
	SaveManager.save()
	_keep.visible = false
	_info.text = "WELCOME TO THE TEAM!"
	var v := _views[_chosen]
	v.entry = _prof.find(uid)
	await _flip(v, true)
	await get_tree().create_timer(0.7).timeout
	for k in _views.size():
		if k == _chosen:
			continue
		await _flip(_views[k], false)
		_views[k].dim = true
		_hints[k].text = "PASSED"
		_hints[k].add_theme_color_override("font_color", UiSkin.MUTED)
		await get_tree().create_timer(0.25).timeout
	_hints[_chosen].text = "KEPT!"
	_hints[_chosen].add_theme_color_override("font_color", UiSkin.GREEN)
	_bar.add_child(MetaUI.yellow("CONTINUE ▶", Vector2(110, 26), func() -> void: SceneRouter.goto(_back)))


func _flip(v: CardView, big: bool) -> void:
	v.pivot_offset = v.size * 0.5
	Sfx.play("flip")
	var tw := create_tween()
	tw.tween_property(v, "scale:x", 0.05, 0.12)
	tw.tween_callback(func() -> void:
		v.face_down = false
		v.glow = 0.0)
	tw.tween_property(v, "scale:x", 1.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	if big:
		var tier := v.tier()
		var tc := CardView.tier_color(tier)
		v.glow = 1.0
		Fx.flash(self, Color(tc.lightened(0.5), 0.4), 0.35)
		Fx.burst(self, v.global_position + v.size * 0.5, tc.lightened(0.2), 30 + tier * 15, 120.0, 0.9, 2.0)
		Sfx.play("elite" if tier >= CardRules.Tier.ELITE else ("big" if tier >= CardRules.Tier.GOLD else "reveal"))
		if tier >= CardRules.Tier.GOLD:
			Fx.confetti(self, size.x, [tc, Color.WHITE], 40)
