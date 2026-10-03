extends Control
## ROAD TO GLORY POSTGAME: applies the game to the career once (RtgFlow.apply_game), then shows
## the score, a stamped letter grade, your stat line and best moments, XP and coins counting
## up, the coach-trust change, finished goals and the season news. CONTINUE goes back to the
## RTG hub (or on to the offseason when the season just ended).

var _ui: Dictionary
var prof: Profile
var _res: Dictionary = {}
var _r: Dictionary = {}


func _ready() -> void:
	prof = SaveManager.profile
	var cfg := SceneRouter.take_config()
	_r = cfg.get("last_result", {})
	_ui = MetaUI.screen(self, "POSTGAME", "", {"coins": true})
	if prof.rtg.is_empty() or _r.is_empty():
		SceneRouter.goto.call_deferred(SceneRouter.RTG_HUB)
		return
	_res = RtgFlow.apply_game(prof, _r)
	(_ui["coins"] as CoinPill).set_coins(prof.coins - int(_res["coins"]), false)
	_build()
	(_ui["coins"] as CoinPill).set_coins.call_deferred(prof.coins, true)


func _build() -> void:
	var root: VBoxContainer = _ui["root"]
	var you := str(prof.rtg["team"])
	var opp := str(_r.get("opponent", ""))
	var won := bool(_res["won"])
	var head := MetaUI.label("%s  %s %d - %d %s" % ["WIN" if won else ("LOSS" if int(_r["pf"]) < int(_r["pa"]) else "TIE"),
			you, int(_r["pf"]), int(_r["pa"]), opp] + ("  (SIMULATED)" if _r.get("simulated", false) and not _r.get("sim_started", false) else ""),
			UiSkin.GREEN if won else UiSkin.WHITE, 16, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(head)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	var stamp := _GradeStamp.new()
	stamp.letter = str(_res["grade"])
	stamp.custom_minimum_size = Vector2(110, 110)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stamp)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	col.add_child(MetaUI.label("GAME GRADE  ·  " + str(_res["line"]), UiSkin.YELLOW))
	var hl: Array = _r.get("rtg", {}).get("highlights", [])
	hl.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pts"]) > float(b["pts"]))
	for h in hl.slice(0, 3):
		col.add_child(MetaUI.label(("★ " if float(h["pts"]) >= 50.0 else "! ") + str(h["text"]),
				UiSkin.GREEN if float(h["pts"]) >= 50.0 else UiSkin.RED))
	var xp_l := MetaUI.label("", UiSkin.WHITE)
	col.add_child(xp_l)
	Fx.count_up(xp_l, 0, int(_res["xp"]), 0.9, "+", " XP")
	var coins_l := MetaUI.label("", UiSkin.YELLOW)
	col.add_child(coins_l)
	Fx.count_up(coins_l, 0, int(_res["coins"]), 0.9, "+", " COINS", false)
	var tb := int(_res["trust_before"])
	var ta := int(_res["trust_after"])
	var trust_row := HBoxContainer.new()
	trust_row.add_theme_constant_override("separation", 5)
	col.add_child(trust_row)
	trust_row.add_child(MetaUI.label("COACH TRUST", UiSkin.MUTED))
	var bar := BarMeter.new(tb / 100.0, Vector2(110, 8), UiSkin.GREEN if ta >= tb else UiSkin.RED)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trust_row.add_child(bar)
	bar.fill_to.call_deferred(ta / 100.0, 0.8)
	trust_row.add_child(MetaUI.label("%d (%s%d)" % [ta, "+" if ta >= tb else "", ta - tb], UiSkin.GREEN if ta >= tb else UiSkin.RED))
	for g in _res["goals_done"]:
		col.add_child(MetaUI.label("GOAL COMPLETE: %s  +%d XP  +%d COINS" % [g["text"], int(g["xp"]), int(g["coins"])], UiSkin.GREEN))
	if str(_res["season_msg"]) != "":
		col.add_child(MetaUI.label(str(_res["season_msg"]), UiSkin.YELLOW))
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.spacer())
	var over := bool(_res["season_over"])
	var go := MetaUI.continue_button("OFFSEASON" if over else "CONTINUE", func() -> void:
		SceneRouter.goto(SceneRouter.RTG_OFFSEASON if over else SceneRouter.RTG_HUB), true, 130)
	nav.add_child(go)
	Sfx.play("big" if RtgTracker.tier(str(_res["grade"])) == 2 else ("reveal" if RtgTracker.tier(str(_res["grade"])) == 1 else "bad"))
	if won:
		Fx.confetti.call_deferred(self, size.x, [UiSkin.YELLOW, Color.WHITE, UiSkin.GREEN], 40)


## A big round grade stamp that thumps down.
class _GradeStamp:
	extends Control
	var letter := "C"
	var _k := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := create_tween()
		tw.tween_property(self, "_k", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var tier := RtgTracker.tier(letter)
		var col: Color = [UiSkin.RED, Color.WHITE, UiSkin.GREEN][tier]
		if letter.begins_with("A"):
			col = UiSkin.YELLOW
		var s := lerpf(2.2, 1.0, _k)
		draw_set_transform(c, -0.12, Vector2.ONE * s)
		draw_circle(Vector2.ZERO, 46.0, Color(0, 0, 0, 0.35 * _k))
		draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, Color(col, _k), 4.0)
		draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 48, Color(col, 0.6 * _k), 2.0)
		UiSkin.draw_text_c(self, 0.0, 12.0, letter, 32, Color(col, _k), Color(0, 0, 0, 0))
		draw_set_transform(Vector2.ZERO)
