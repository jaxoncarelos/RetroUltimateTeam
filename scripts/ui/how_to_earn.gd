class_name HowToEarn
extends RefCounted
## "HOW TO EARN COINS" popup (info button on the hub, store and objectives): every coin
## source with its numbers, straight from the rules constants.


static func show(owner: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var mult: float = TeamRating.DIFFICULTY[Settings.difficulty][2]
	var lines := [
		["PLAY A GAME", "+%d  (WIN +%d)" % [EconomyRules.LOSS_COINS, EconomyRules.WIN_COINS]],
		["EACH TOUCHDOWN / SACK / INT", "+%d / +%d" % [EconomyRules.TD_BONUS, EconomyRules.TAKEAWAY_BONUS]],
		["WIN STREAK", "+%d%% PER WIN" % int(EconomyRules.STREAK_STEP * 100)],
		["FIRST WIN OF THE DAY", "+%d" % EconomyRules.DAILY_WIN_BONUS],
		["OBJECTIVES (DAILY/WEEKLY/HOF)", "+100 TO +3,000"],
		["CHALLENGES (FIRST CLEAR)", "+250 TO +800"],
		["COACH LEVEL-UPS", "COINS + PACKS"],
		["DAILY LOGIN (7-DAY STREAK)", "UP TO A GOLD PACK"],
		["QUICK SELL SPARE CARDS", "+25 AND UP"],
		["DIFFICULTY %s" % TeamRating.DIFFICULTY[Settings.difficulty][0], "COINS X%.2f" % mult],
	]
	for l in lines:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var coin := TextureRect.new()
		coin.texture = UiSkin.coin_tex()
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(coin)
		var a := MetaUI.label(l[0], UiSkin.WHITE)
		a.custom_minimum_size = Vector2(186, 0)
		h.add_child(a)
		h.add_child(MetaUI.label(l[1], UiSkin.YELLOW))
		col.add_child(h)
	MetaUI.popup(owner, "HOW TO EARN COINS", col, [["CLOSE", Callable()],
			["OBJECTIVES", func() -> void: SceneRouter.goto(SceneRouter.OBJECTIVES), true]])
