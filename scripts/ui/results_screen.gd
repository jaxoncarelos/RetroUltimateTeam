extends Control
## RESULTS (after every match): the final score with both helmets, then an animated payout -
## each coin item ticks in, the total counts up and flies into the coin pill, the coach XP
## bar fills (LEVEL UP! pops with its reward), completed objectives get checkmarks, player
## development shows OVR gains, and new packs light up OPEN PACK. Big PLAY NEXT / OPEN PACK
## buttons keep the "one more game" loop to a single tap. Tap anywhere to fast-forward.
## Config: {"last_result": MatchController.match_result()} (applied here, once).

var prof: Profile
var res: Dictionary = {}
var _ui: Dictionary
var _fast := false
var _coins_col: VBoxContainer
var _total_l: Label
var _xp_bar: BarMeter
var _xp_lvl: Label
var _xp_gain: Label
var _obj_col: VBoxContainer
var _grow_col: VBoxContainer
var _pack_btn: Button
var _score_panel: Control


func _ready() -> void:
	prof = SaveManager.profile
	var cfg := SceneRouter.take_config()
	var r: Dictionary = cfg.get("last_result", {})
	var coins_start := prof.coins
	if not r.is_empty():
		res = GameFlow.apply_result(prof, r)
	var won: bool = res.get("won", false)
	var tie: bool = not r.is_empty() and int(r.get("pf", 0)) == int(r.get("pa", 0)) and not r.get("forfeit", false)
	var title := "VICTORY!" if won else ("TIE GAME" if tie else ("FORFEIT" if r.get("forfeit", false) else "DEFEAT"))
	if r.get("mode", "") == "challenge":
		title = "CHALLENGE WON!" if r.get("challenge_won", false) else "CHALLENGE FAILED"
	_ui = MetaUI.screen(self, title)
	(_ui["coins"] as CoinPill).set_coins(int(res.get("coins_before", coins_start)), false)
	_build(r)
	_run.call_deferred()


func _build(r: Dictionary) -> void:
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 6)
	_score_panel = _score(r)
	root.add_child(_score_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)
	# Coins.
	var cp := RetroPanel.new("COINS EARNED", UiSkin.PANEL, 5)
	cp.custom_minimum_size = Vector2(228, 0)
	row.add_child(cp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 1)
	cp.add_child(cv)
	_coins_col = VBoxContainer.new()
	_coins_col.add_theme_constant_override("separation", 1)
	_coins_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(_coins_col)
	var tot := HBoxContainer.new()
	cv.add_child(tot)
	var tl := MetaUI.label("TOTAL", UiSkin.WHITE)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tot.add_child(tl)
	_total_l = MetaUI.label("+0", UiSkin.YELLOW, 16, HORIZONTAL_ALIGNMENT_RIGHT)
	tot.add_child(_total_l)
	# Right column: coach XP, objectives, growth.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	var before: Dictionary = res.get("coach_before", ProgressionRules.level_progress(int(prof.coach.get("xp", 0))))
	var xp := RetroPanel.new("COACH XP", UiSkin.PANEL, 4)
	right.add_child(xp)
	var xh := HBoxContainer.new()
	xh.add_theme_constant_override("separation", 5)
	xp.add_child(xh)
	_xp_lvl = MetaUI.label("LVL %d" % int(before["level"]), UiSkin.WHITE)
	xh.add_child(_xp_lvl)
	_xp_bar = BarMeter.new(float(before["frac"]), Vector2(0, 9), UiSkin.STAR_BLUE)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xh.add_child(_xp_bar)
	_xp_gain = MetaUI.label("+0 XP", UiSkin.STAR_BLUE)
	xh.add_child(_xp_gain)
	var op := RetroPanel.new("OBJECTIVES COMPLETE", UiSkin.PANEL, 4)
	op.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(op)
	_obj_col = VBoxContainer.new()
	_obj_col.add_theme_constant_override("separation", 1)
	op.add_child(_obj_col)
	if not (res.get("level_ups", []) as Array).is_empty():
		var gp := RetroPanel.new("PLAYER GROWTH", UiSkin.PANEL, 4)
		right.add_child(gp)
		_grow_col = VBoxContainer.new()
		_grow_col.add_theme_constant_override("separation", 1)
		gp.add_child(_grow_col)
	# Nav: home, squad, [open pack], play next.
	var nav: HBoxContainer = _ui["nav"]
	nav.add_child(MetaUI.nav_button("SQUAD", func() -> void: SceneRouter.goto(SceneRouter.SQUAD)))
	nav.add_child(MetaUI.nav_button("OBJECTIVES", func() -> void: SceneRouter.goto(SceneRouter.OBJECTIVES), 76))
	_pack_btn = MetaUI.yellow("OPEN PACK", Vector2(96, 28), _open_pack)
	_pack_btn.visible = false
	nav.add_child(_pack_btn)
	var challenge: bool = r.get("mode", "") == "challenge"
	var next := MetaUI.continue_button("CHALLENGES" if challenge else "PLAY NEXT",
			(func() -> void: SceneRouter.goto(SceneRouter.CHALLENGES)) if challenge else _play_next, true, 116)
	nav.add_child(next)
	Fx.pulse.call_deferred(next, 1.05, 1.1)


func _score(r: Dictionary) -> Control:
	var p := RetroPanel.new("", UiSkin.PANEL, 3)
	p.custom_minimum_size = Vector2(0, 58)
	var sv := _ScoreView.new()
	sv.you = GameData.team(str(r.get("team", prof.franchise_team)))
	sv.opp = GameData.team(str(r.get("opponent", "PHI")))
	sv.pf = int(r.get("pf", 0))
	sv.pa = int(r.get("pa", 0))
	var b: Dictionary = r.get("box", {})
	if not b.is_empty():
		sv.line = "PASS %d/%d %d YDS   RUSH %d-%d   TD %d   SACKS %d   INT %d" % [int(b.get("pass_comp", 0)),
				int(b.get("pass_att", 0)), int(b.get("pass_yds", 0)), int(b.get("rush_att", 0)), int(b.get("rush_yds", 0)),
				int(b.get("tds", int(r.get("tds", 0)))), int(r.get("def_sacks", 0)), int(r.get("def_ints", 0))]
	if r.get("simulated", false):
		sv.line = "SIMULATED GAME"
	sv.msg = str(res.get("mode_msg", ""))
	p.add_child(sv)
	return p


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap:
		_fast = true


func _wait(sec: float) -> void:
	if _fast:
		await get_tree().process_frame
		return
	await get_tree().create_timer(sec).timeout


# ---------------------------------------------------------------- the payout animation

func _run() -> void:
	if res.is_empty():
		return
	Fx.pop(_score_panel, 1.06, 0.3)
	Sfx.play("td" if res.get("won", false) else "whistle")
	if res.get("won", false):
		Fx.confetti(self, get_viewport_rect().size.x, [UiSkin.YELLOW, Color.WHITE, UiSkin.STAR_BLUE, UiSkin.STAR_RED], 50)
	await _wait(0.5)
	# 1) Coin items tick in.
	var running := 0
	for item in res.get("items", []):
		if item.get("id", "") == "objective":
			continue
		var h := _line(str(item["label"]), "+%d" % int(item["coins"]), UiSkin.WHITE, UiSkin.YELLOW)
		_coins_col.add_child(h)
		Fx.pop(h, 1.1, 0.2)
		Sfx.play("coin_tick")
		running += int(item["coins"])
		_total_l.text = "+%s" % CoinPill.fmt(running)
		await _wait(0.26)
	# 2) Objectives completed this game (auto-claimed: their coins join the total).
	var objs: Array = []
	for item in res.get("items", []):
		if item.get("id", "") == "objective":
			objs.append(item)
	if objs.is_empty():
		_obj_col.add_child(MetaUI.label("NONE THIS GAME", UiSkin.MUTED))
		_obj_col.add_child(MetaUI.label("TAP OBJECTIVES TO SEE GOALS", UiSkin.MUTED))
	var shown := 0
	var rest_coins := 0
	for item in objs:
		shown += 1
		if shown > 5 and objs.size() > 6:
			rest_coins += int(item["coins"])
			running += int(item["coins"])
			continue
		var label := str(item["label"])
		var colon := label.find(": ")
		if colon >= 0:
			label = label.substr(colon + 2)
		var line := _obj_line(label, int(item["coins"]), str(item.get("pack", "")))
		_obj_col.add_child(line)
		Fx.pop(line, 1.15, 0.25)
		Sfx.play("claim")
		running += int(item["coins"])
		_total_l.text = "+%s" % CoinPill.fmt(running)
		await _wait(0.25)
	if rest_coins > 0:
		var more := _obj_line("+%d MORE" % (objs.size() - 5), rest_coins, "")
		_obj_col.add_child(more)
		Fx.pop(more, 1.15, 0.25)
		Sfx.play("claim")
		_total_l.text = "+%s" % CoinPill.fmt(running)
	# 3) Total -> coins fly into the pill.
	var gained := int(res.get("coins_after", prof.coins)) - int(res.get("coins_before", prof.coins))
	var extra := gained - running
	if extra > 0:
		var h2 := _line("LEVEL-UP + MODE BONUS", "+%d" % extra, UiSkin.WHITE, UiSkin.YELLOW)
		_coins_col.add_child(h2)
	Fx.count_up(_total_l, running, gained, 0.4, "+")
	Fx.pop(_total_l, 1.3, 0.3)
	await _wait(0.45)
	var pill: CoinPill = _ui["coins"]
	if gained > 0:
		Fx.fly_coins(_ui["layer"], _total_l.global_position + _total_l.size * 0.5, pill.coin_global(), clampi(gained / 60, 6, 18))
		await _wait(0.35)
		pill.set_coins(prof.coins)
		Sfx.play("coin")
	# 4) Coach XP.
	var coach: Dictionary = res.get("coach", {})
	var gain := int(coach.get("xp", 0))
	Fx.count_up(_xp_gain, 0, gain, 0.6, "+", " XP", false)
	for up in coach.get("level_ups", []):
		await _xp_bar.fill_to(1.0, 0.0 if _fast else 0.45).finished
		_level_up(up)
		_xp_bar.frac = 0.0
		_xp_lvl.text = "LVL %d" % int(up["level"])
		await _wait(0.9)
	var after: Dictionary = coach.get("progress", ProgressionRules.level_progress(int(prof.coach.get("xp", 0))))
	_xp_lvl.text = "LVL %d" % int(after["level"])
	await _xp_bar.fill_to(float(after["frac"]), 0.0 if _fast else 0.5).finished
	# 5) Player growth.
	if _grow_col != null:
		for u in (res.get("level_ups", []) as Array).slice(0, 3):
			var g := _line(str(u["name"]).to_upper(), "%d ▶ %d" % [int(u["from"]), int(u["to"])], UiSkin.WHITE, UiSkin.GREEN)
			_grow_col.add_child(g)
			Fx.pop(g, 1.1, 0.2)
			Sfx.play("reveal")
			await _wait(0.25)
	# 6) Packs waiting.
	if not prof.pending_packs.is_empty():
		_pack_btn.text = "OPEN PACK x%d" % prof.pending_packs.size() if prof.pending_packs.size() > 1 else "OPEN PACK"
		_pack_btn.visible = true
		Fx.pop(_pack_btn, 1.3, 0.35)
		Fx.pulse.call_deferred(_pack_btn, 1.08, 0.7)
		MetaUI.toast(self, "NEW PACK AVAILABLE!")
		Sfx.play("big")


func _level_up(up: Dictionary) -> void:
	Sfx.play("levelup")
	var text := "LEVEL %d!" % int(up["level"])
	var tex := UiSkin.logo([text], 3, Color.WHITE, UiSkin.YELLOW, UiSkin.STAR_BLUE, UiSkin.SHADOW)
	var t := TextureRect.new()
	t.texture = tex
	t.size = tex.get_size()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_index = 30
	var vp := get_viewport_rect().size
	t.position = ((vp - t.size) * 0.5).round() + Vector2(0, -20)
	add_child(t)
	var sub := MetaUI.label("+%d COINS%s" % [int(up.get("coins", 0)),
			("  +  %s PACK" % str(up["pack"]).to_upper()) if str(up.get("pack", "")) != "" else ""], UiSkin.YELLOW, 8,
			HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, t.position.y + t.size.y + 2)
	sub.size = Vector2(vp.x, 10)
	sub.z_index = 30
	add_child(sub)
	Fx.pop(t, 1.4, 0.35)
	Fx.burst(self, vp * 0.5, UiSkin.YELLOW, 50, 140.0, 1.0)
	Fx.confetti(self, vp.x, [UiSkin.YELLOW, UiSkin.STAR_BLUE, Color.WHITE], 50)
	var tw := create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(t, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(sub, "modulate:a", 0.0, 0.3)
	tw.tween_callback(t.queue_free)
	tw.tween_callback(sub.queue_free)


func _line(a: String, b: String, ca: Color, cb: Color) -> Control:
	var h := HBoxContainer.new()
	var l := MetaUI.label(a, ca)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	h.add_child(MetaUI.label(b, cb, 8, HORIZONTAL_ALIGNMENT_RIGHT))
	return h


func _obj_line(title: String, coins: int, pack: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var ck := TextureRect.new()
	ck.texture = UiSkin.icon("check")
	ck.modulate = UiSkin.GREEN
	ck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ck)
	var l := MetaUI.label(title.to_upper(), UiSkin.WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	h.add_child(MetaUI.label("+%d%s" % [coins, " +PACK" if pack != "" else ""], UiSkin.YELLOW, 8, HORIZONTAL_ALIGNMENT_RIGHT))
	return h


func _play_next() -> void:
	SceneRouter.goto(SceneRouter.PREMATCH, GameFlow.next_game_config(prof))


func _open_pack() -> void:
	var cfg := GameFlow.open_pending_config(prof, SceneRouter.HUB)
	if not cfg.is_empty():
		SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)


## Score strip: your helmet + score, FINAL, their score + helmet, box line, mode message.
class _ScoreView:
	extends Control
	var you: TeamData
	var opp: TeamData
	var pf := 0
	var pa := 0
	var line := ""
	var msg := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cx := size.x * 0.5
		if you != null:
			draw_texture(ArtGen.helmet(you.abbr, you.uniform_colors(), false), Vector2(4, -2))
			UiSkin.draw_text(self, Vector2(72, 12), you.team_name.to_upper(), 8, UiSkin.WHITE, Color(0, 0, 0, 0), UiSkin.SHADOW)
		if opp != null:
			draw_texture(ArtGen.helmet(opp.abbr, opp.uniform_colors(), true), Vector2(size.x - 68, -2))
			var on := opp.team_name.to_upper()
			UiSkin.draw_text(self, Vector2(size.x - 72 - PixelFont.text_width(on), 12), on, 8, UiSkin.WHITE,
					Color(0, 0, 0, 0), UiSkin.SHADOW)
		var win := pf > pa
		UiSkin.draw_text_c(self, cx - 44, 36, str(pf), 24, UiSkin.YELLOW if win else UiSkin.WHITE, UiSkin.SHADOW)
		UiSkin.draw_text_c(self, cx + 44, 36, str(pa), 24, UiSkin.YELLOW if pa > pf else UiSkin.WHITE, UiSkin.SHADOW)
		UiSkin.draw_text_c(self, cx, 24, "FINAL", 8, UiSkin.MUTED)
		UiSkin.draw_text_c(self, cx, 34, "-", 16, UiSkin.WHITE)
		if line != "":
			UiSkin.draw_text_c(self, cx, size.y - 1, line, 8, UiSkin.MUTED)
		if msg != "":
			UiSkin.draw_text_c(self, cx, 10, msg, 8, UiSkin.YELLOW, Color(0, 0, 0, 0), UiSkin.SHADOW)
