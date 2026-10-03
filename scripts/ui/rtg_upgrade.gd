extends Control
## ROAD TO GLORY - UPGRADE: spend XP on your position's ratings (the ones your OVR is made
## of, biggest weight first). Each +1 costs more the higher the rating (RtgRules.upgrade_cost).
## The card on the left updates live; OVR going up pops.

var _ui: Dictionary
var prof: Profile
var _list: VBoxContainer
var _card: RtgCard
var _xp: Label
var _ovr: Label


func _ready() -> void:
	prof = SaveManager.profile
	if prof.rtg.is_empty():
		SceneRouter.goto.call_deferred(SceneRouter.RTG_HUB)
		return
	_ui = MetaUI.screen(self, "UPGRADE", SceneRouter.RTG_HUB, {"coins": false})
	var root: VBoxContainer = _ui["root"]
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	_card = RtgCard.new(prof.rtg["player"], str(prof.rtg["team"]), 2)
	left.add_child(_card)
	_ovr = MetaUI.label("", UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_ovr)
	var panel := RetroPanel.new("RATINGS", UiSkin.PANEL, 4)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	_xp = MetaUI.label("", UiSkin.YELLOW)
	col.add_child(_xp)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	col.add_child(_list)
	var note := MetaUI.label("EARN XP BY PLAYING (SIMS PAY LESS), PRACTICE, GOALS AND AWARDS. STAR+ DEV TRAITS EARN MORE.", UiSkin.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	col.add_child(note)
	_refresh()


func _refresh() -> void:
	var rtg := prof.rtg
	var p: Dictionary = rtg["player"]
	var pos := str(p["pos"])
	_xp.text = "XP AVAILABLE: %s" % CoinPill.fmt(int(rtg["xp"]))
	_ovr.text = "%d OVR" % RtgRules.ovr(pos, p["attrs"])
	MetaUI.clear(_list)
	var keys: Array = RtgRules.WEIGHTS[pos].keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(RtgRules.WEIGHTS[pos][a]) > float(RtgRules.WEIGHTS[pos][b]))
	for k in keys:
		var v := int(p["attrs"][k])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 5)
		_list.add_child(h)
		var nl := MetaUI.label(RtgRules.ATTR_NAMES[k], UiSkin.WHITE)
		nl.custom_minimum_size = Vector2(104, 0)
		h.add_child(nl)
		var bar := BarMeter.new(clampf((v - 30) / 69.0, 0.0, 1.0), Vector2(90, 7))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		var vl := MetaUI.label(str(v), UiSkin.YELLOW)
		vl.custom_minimum_size = Vector2(18, 0)
		h.add_child(vl)
		var cost := RtgRules.upgrade_cost(v)
		var b := MetaUI.button("+1  %d XP" % cost if v < 99 else "MAX", Vector2(78, 18), func() -> void: _up(k))
		b.disabled = not RtgRules.can_upgrade(rtg, k)
		if not b.disabled:
			b.theme_type_variation = "YellowButton"
		h.add_child(b)
		h.add_child(MetaUI.label("%d%%" % int(round(float(RtgRules.WEIGHTS[pos][k]) * 100.0)), UiSkin.MUTED))


func _up(k: String) -> void:
	var before := RtgRules.player_ovr(prof.rtg)
	if not RtgRules.upgrade(prof.rtg, k):
		return
	GameData.register_rtg(prof)
	SaveManager.save()
	Sfx.play("tap")
	_card.refresh()
	_refresh()
	if RtgRules.player_ovr(prof.rtg) > before:
		Sfx.play("big")
		Fx.pop(_ovr, 1.5, 0.3)
		MetaUI.toast(self, "OVR UP! %d" % RtgRules.player_ovr(prof.rtg))
