extends Control
## STORE: buy packs with coins. Buying spends the coins and adds the cards in one saved
## step, then the pack-opening screen reveals them.

var _ui: Dictionary


func _ready() -> void:
	_ui = MetaUI.screen(self, "STORE")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui["root"].add_child(row)
	for pack in PackCatalog.store_packs():
		row.add_child(_pack_tile(pack))
	_ui["root"].add_child(MetaUI.label("ODDS PER CARD: BRONZE / SILVER / GOLD / ELITE", UiTheme.DIM))


func _pack_tile(pack: PackDef) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var art := ColorRect.new()
	art.color = pack.color
	art.custom_minimum_size = Vector2(104, 56)
	var name := MetaUI.label(pack.display_name, UiTheme.INK)
	name.position = Vector2(6, 6)
	art.add_child(name)
	var count := MetaUI.label("%d CARDS" % pack.card_count, UiTheme.INK)
	count.position = Vector2(6, 20)
	art.add_child(count)
	if pack.guarantee_tier >= 0:
		var g := MetaUI.label("1 %s+" % CardRules.NAMES[pack.guarantee_tier], UiTheme.INK)
		g.position = Vector2(6, 34)
		art.add_child(g)
	box.add_child(art)
	var odds: Array[String] = []
	for o in pack.odds:
		odds.append("%d" % int(round(o * 100)))
	box.add_child(MetaUI.label("%s%%" % "/".join(odds), UiTheme.TEXT))
	var buy := MetaUI.button("BUY %d" % pack.price, Vector2(104, 26), func() -> void: _buy(pack))
	buy.disabled = not EconomyRules.can_buy(SaveManager.profile, pack)
	box.add_child(buy)
	return box


func _buy(pack: PackDef) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var uids := EconomyRules.buy_and_open(SaveManager.profile, pack, GameData.db, rng,
			int(Time.get_unix_time_from_system()))
	if uids.is_empty():
		return
	SaveManager.save()
	SceneRouter.goto("res://scenes/meta/pack_open.tscn", {"uids": uids, "title": pack.display_name,
			"back": "res://scenes/meta/store.tscn"})
