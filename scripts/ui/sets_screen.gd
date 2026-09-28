extends Control
## SETS: trade spare cards (unlocked, not starting) for packs or an Elite franchise star.

var _ui: Dictionary
var _list: VBoxContainer


func _ready() -> void:
	_ui = MetaUI.screen(self, "SETS")
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_ui["root"].add_child(_list)
	_ui["root"].add_child(MetaUI.label("ONLY UNLOCKED BENCH CARDS ARE USED.", UiTheme.DIM))
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var prof := SaveManager.profile
	for s in EconomyRules.SETS:
		var have := EconomyRules.set_candidates(prof, GameData.db, s).size()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := MetaUI.label("%s   (%d/%d)   DONE %dX" % [s["name"], mini(have, int(s["count"])), int(s["count"]),
				int(prof.sets_done.get(s["id"], 0))])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := MetaUI.button("COMPLETE", Vector2(90, 24), func() -> void: _complete(s))
		b.disabled = have < int(s["count"])
		row.add_child(b)
		_list.add_child(row)


func _complete(s: Dictionary) -> void:
	var prof := SaveManager.profile
	var reward := EconomyRules.complete_set(prof, GameData.db, s)
	if reward == "":
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var uids: Array[int] = []
	var title := ""
	if reward == "franchise_elite":
		var id := EconomyRules.franchise_elite(prof, GameData.db, rng)
		if id != "":
			uids.append(prof.add_card(id, int(Time.get_unix_time_from_system())))
		title = "FRANCHISE STAR"
	else:
		var pack := PackCatalog.get_pack(reward)
		uids = EconomyRules.grant_pack(prof, pack, GameData.db, rng, int(Time.get_unix_time_from_system()))
		title = pack.display_name
	SaveManager.save()
	SceneRouter.goto("res://scenes/meta/pack_open.tscn", {"uids": uids, "title": title,
			"back": "res://scenes/meta/sets.tscn"})
