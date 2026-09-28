extends Control
## HUB (Retro Bowl "main screen"): upcoming-games strip with helmets, division standings,
## coach level + objectives panels, team OVR / offense / defense stars, and the bottom nav
## (settings, modes, store, squad, objectives, PLAY). Shows the daily check-in on launch,
## a pulsing OPEN PACK button when reward packs wait, and still accepts a "last_result"
## config (legacy path; the results screen normally applies matches).

var prof: Profile
var _ui: Dictionary
var _obj_btn: Button


func _ready() -> void:
	prof = SaveManager.profile
	var cfg := SceneRouter.take_config()
	_ui = MetaUI.screen(self, "POCKET GRIDIRON", "")
	if cfg.has("last_result"):
		var res := GameFlow.apply_result(prof, cfg["last_result"])
		MetaUI.toast.call_deferred(self, "+%s COINS" % CoinPill.fmt(int(res["coins_after"]) - int(res["coins_before"])))
		(_ui["coins"] as CoinPill).set_coins(prof.coins, false)
	_build()
	if not cfg.has("last_result"):
		_maybe_daily_popup.call_deferred()


func _build() -> void:
	var root: VBoxContainer = _ui["root"]
	root.add_theme_constant_override("separation", 6)
	var info := IconButton.new("info", Vector2(24, 22))
	info.pressed.connect(func() -> void: HowToEarn.show(self))
	_ui["top_right"].add_child(info)
	# Upcoming games strip.
	var strip := RetroPanel.new("", UiSkin.PANEL, 2)
	strip.custom_minimum_size = Vector2(0, 80)
	var sv := _Strip.new()
	sv.games = _strip_games()
	if not prof.pending_packs.is_empty():
		# Reward packs waiting: the strip's last slot becomes a shaking FREE PACK.
		sv.games = sv.games.slice(0, 2)
		sv.pack_count = prof.pending_packs.size()
		sv.pack_art = PackArt.for_pack(PackCatalog.get_pack(str(prof.pending_packs[0])), 1.0)
		sv.on_pack = _open_pending
	strip.add_child(sv)
	root.add_child(strip)
	# Lower row: standings | coach, objectives, team boxes.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)
	row.add_child(_standings_panel())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	right.add_child(_coach_panel())
	right.add_child(_objectives_panel())
	var boxes := HBoxContainer.new()
	boxes.add_theme_constant_override("separation", 5)
	right.add_child(boxes)
	var entries := Collection.lineup_entries(prof, GameData.db)
	var ss := MetaUI.side_stars(entries)
	var ovr_l := MetaUI.label(str(Collection.team_ovr(prof, GameData.db)), UiSkin.YELLOW, 16)
	boxes.add_child(_box("TEAM OVR", ovr_l))
	boxes.add_child(_box("OFFENSE", MetaUI.stars(ss["off"], UiSkin.STAR_BLUE)))
	boxes.add_child(_box("DEFENSE", MetaUI.stars(ss["def"], UiSkin.STAR_RED)))
	# Bottom nav.
	var nav: HBoxContainer = _ui["nav"]
	var gear := IconButton.new("gear")
	gear.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.SETTINGS))
	nav.add_child(gear)
	var modes := IconButton.new("trophy")
	modes.icon_color = UiSkin.YELLOW
	modes.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.MODE))
	nav.add_child(modes)
	nav.add_child(MetaUI.nav_button("STORE", func() -> void: SceneRouter.goto(SceneRouter.STORE)))
	nav.add_child(MetaUI.nav_button("SQUAD", func() -> void: SceneRouter.goto(SceneRouter.SQUAD)))
	_obj_btn = MetaUI.nav_button("OBJECTIVES", func() -> void: SceneRouter.goto(SceneRouter.OBJECTIVES), 76)
	nav.add_child(_obj_btn)
	var play := MetaUI.continue_button("PLAY", _play, true, 104)
	nav.add_child(play)
	Fx.pulse.call_deferred(play, 1.05, 1.1)
	_refresh_badges.call_deferred()


func _refresh_badges() -> void:
	MetaUI.badge(_obj_btn, ObjectiveRules.claimable_count(prof))


func _box(title: String, content: Control) -> RetroPanel:
	var b := MetaUI.stat_box(title, content, Vector2(0, 34))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _play() -> void:
	SceneRouter.goto(SceneRouter.PREMATCH, GameFlow.next_game_config(prof))


func _open_pending() -> void:
	var cfg := GameFlow.open_pending_config(prof, SceneRouter.HUB)
	if not cfg.is_empty():
		SceneRouter.goto(SceneRouter.PACK_OPEN, cfg)


# ---------------------------------------------------------------- panels

func _standings_panel() -> RetroPanel:
	var team: TeamData = GameData.team(prof.franchise_team)
	var conf := team.conf if team != null else "AFC"
	var div := team.div if team != null else ""
	var p := RetroPanel.new("%s %s" % [conf, div.to_upper()] if div != "" else "YOUR DIVISION", UiSkin.PANEL, 4)
	p.custom_minimum_size = Vector2(212, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	var head := _row("TEAM", "W", "L", "T", UiSkin.MUTED, false)
	col.add_child(head)
	var abbrs: Array = []
	for a in GameData.teams:
		var t: TeamData = GameData.teams[a]
		if t.conf == conf and t.div == div:
			abbrs.append(a)
	var s := prof.season
	var table: Dictionary = SeasonRules.standings(s, GameData.teams.keys()) if not s.is_empty() else {}
	if table.is_empty():
		for a in abbrs:
			table[a] = {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}
		table[prof.franchise_team] = {"w": int(prof.stats["wins"]), "l": int(prof.stats["losses"]),
				"t": int(prof.stats["ties"]), "pf": 0, "pa": 0}
	var ranked: Array = SeasonRules.rank(abbrs, table)
	for a in ranked:
		var r: Dictionary = table.get(a, {"w": 0, "l": 0, "t": 0})
		var mine: bool = a == prof.franchise_team
		col.add_child(_row(GameData.team(a).team_name.to_upper(), str(r["w"]), str(r["l"]), str(r["t"]),
				UiSkin.YELLOW if mine else UiSkin.WHITE, mine))
	var streak := int(prof.stats.get("win_streak", 0))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	col.add_child(MetaUI.spacer(false))
	col.add_child(foot)
	foot.add_child(MetaUI.label("CAREER %d-%d-%d" % [prof.stats["wins"], prof.stats["losses"], prof.stats["ties"]],
			UiSkin.MUTED))
	foot.add_child(MetaUI.spacer())
	if streak >= 2:
		var fl := TextureRect.new()
		fl.texture = UiSkin.icon("flame")
		fl.modulate = Color("#ff9d2e")
		foot.add_child(fl)
		foot.add_child(MetaUI.label("%d WIN STREAK" % streak, Color("#ffb14a")))
	return p


func _row(n: String, w: String, l: String, t: String, col: Color, hi: bool) -> Control:
	var r := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiSkin.ROW if hi else Color(0, 0, 0, 0)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	r.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	r.add_child(h)
	var nl := MetaUI.label(n, col)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	for v in [w, l, t]:
		var vl := MetaUI.label(v, col, 8, HORIZONTAL_ALIGNMENT_RIGHT)
		vl.custom_minimum_size = Vector2(18, 0)
		h.add_child(vl)
	return r


func _coach_panel() -> Control:
	var prog := ProgressionRules.level_progress(int(prof.coach.get("xp", 0)))
	var p := RetroPanel.new("COACH LEVEL %d" % int(prog["level"]), UiSkin.PANEL, 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var bar := BarMeter.new(float(prog["frac"]), Vector2(0, 9))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.segments = 5
	h.add_child(bar)
	var next := ProgressionRules.rewards_for_level(int(prog["level"]) + 1)
	var txt := "MAX" if prog["max"] else "%d/%d XP" % [prog["into"], prog["needed"]]
	h.add_child(MetaUI.label(txt, UiSkin.MUTED))
	if not prog["max"] and str(next.get("pack", "")) != "":
		p.tooltip_text = "NEXT LEVEL: %s PACK" % str(next["pack"]).to_upper()
	return p


## Objectives panel: "N READY TO CLAIM!" (pulsing) or the next goal and its reward - the
## everyday answer to "how do I get coins?".
func _objectives_panel() -> Control:
	var n := ObjectiveRules.claimable_count(prof)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 26)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.OBJECTIVES))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var crown := TextureRect.new()
	crown.texture = UiSkin.icon("crown")
	crown.modulate = UiSkin.YELLOW
	crown.position = Vector2(7, 9)
	crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(crown)
	if n > 0:
		btn.text = "    %d OBJECTIVE%s READY - CLAIM!" % [n, "S" if n > 1 else ""]
		btn.theme_type_variation = "YellowButton"
		crown.modulate = UiSkin.NAVY_DEEP
		Fx.pulse.call_deferred(btn, 1.03, 0.9)
	else:
		var next := _next_objective()
		btn.text = "    %s  +%s" % [_short(str(next.get("desc", "PLAY GAMES TO EARN COINS")).to_upper(), 26),
				CoinPill.fmt(int(next.get("reward", 0)))] if not next.is_empty() else "    OBJECTIVES: EARN COINS"
	return btn


## `t` cut to `n` characters at a word boundary, with ".." when shortened.
static func _short(t: String, n: int) -> String:
	if t.length() <= n:
		return t
	var cut := t.left(n - 2)
	var sp := cut.rfind(" ")
	if sp > n / 2:
		cut = cut.left(sp)
	return cut.strip_edges() + ".."


func _next_objective() -> Dictionary:
	var best := {}
	var best_frac := -1.0
	for o in ObjectiveRules.active(prof):
		if o["claimed"] or o["done"] or o["kind"] == "milestone" and not o.get("starter", false):
			continue
		var f := float(o["progress"]) / maxf(float(o["target"]), 1.0)
		if f > best_frac:
			best_frac = f
			best = o
	return best


# ---------------------------------------------------------------- strip

## [{label, sub, team: TeamData, result: String, current: bool}] x3
func _strip_games() -> Array:
	var out: Array = []
	var s := prof.season
	var you := prof.franchise_team
	if not s.is_empty() and s.get("team", "") == you and s.get("phase", "") == "regular":
		var w := int(s["week"])
		var first := clampi(w - 1, 0, maxi(0, (s["weeks"] as Array).size() - 3))
		for i in range(first, mini(first + 3, (s["weeks"] as Array).size())):
			var g: Array = []
			for pair in s["weeks"][i]:
				if you in pair:
					g = pair
			if g.is_empty():
				continue
			var home: bool = g[0] == you
			var opp: String = g[1] if home else g[0]
			var res := ""
			for r in s["results"]:
				if r[0] == g[0] and r[1] == g[1]:
					var mine := int(r[2]) if home else int(r[3])
					var theirs := int(r[3]) if home else int(r[2])
					res = "%s %d-%d" % ["W" if mine > theirs else ("L" if mine < theirs else "T"), mine, theirs]
			out.append({"label": "WEEK %d" % (i + 1), "sub": "%s %s" % ["VS" if home else "AT",
					GameData.team(opp).team_name.to_upper()], "team": GameData.team(opp), "result": res, "current": i == w})
		return out
	if not s.is_empty() and s.get("phase", "") == "playoffs":
		var cfg := GameFlow.season_game_config(prof)
		if not cfg.is_empty():
			out.append({"label": "PLAYOFFS", "sub": str(cfg.get("label", "")), "team": GameData.team(prof.franchise_team),
					"result": "", "current": false})
			out.append({"label": "NEXT UP", "sub": "VS " + GameData.team(cfg["away"]).team_name.to_upper(),
					"team": GameData.team(cfg["away"]), "result": "", "current": true})
			return out
	var opps := GameFlow.next_quick_opponents(prof, 3)
	for i in opps.size():
		out.append({"label": "NEXT UP" if i == 0 else "THEN", "sub": "VS " + GameData.team(opps[i]).team_name.to_upper(),
				"team": GameData.team(opps[i]), "result": "", "current": i == 0})
	return out


## Draws the strip: labels, helmets on a progress line (green up to the next game).
class _Strip:
	extends Control
	var games: Array = []
	var pack_art: PackArt
	var pack_count := 0
	var on_pack := Callable()
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS if pack_art != null else Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		if pack_art != null:
			add_child(pack_art)
			resized.connect(func() -> void: pack_art.position = Vector2(size.x * 5.0 / 6.0 - 22.0, 12.0))

	func _process(delta: float) -> void:
		_t += delta
		if pack_art != null:
			# A little rattle every second to beg for a tap.
			pack_art.shake = 0.6 if fmod(_t, 1.4) < 0.25 else 0.0
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if tap and pack_art != null and event.position.x > size.x * 2.0 / 3.0 and on_pack.is_valid():
			Sfx.play("tap")
			on_pack.call()

	func _draw() -> void:
		var n := games.size()
		if pack_art != null:
			var px := size.x * 5.0 / 6.0
			var blink := fmod(_t, 0.8) < 0.55
			UiSkin.draw_text_c(self, px, 9, "FREE PACK" + (" x%d" % pack_count if pack_count > 1 else "") + "!", 8,
					UiSkin.YELLOW, Color(0, 0, 0, 0), UiSkin.SHADOW)
			if blink:
				UiSkin.draw_text_c(self, px, size.y - 1, "TAP TO OPEN", 8, UiSkin.WHITE, Color(0, 0, 0, 0), UiSkin.SHADOW)
			for k in 3:
				draw_circle(Vector2(px, 46), 24.0 - k * 5.0 + sin(_t * 4.0) * 1.5, Color(UiSkin.YELLOW, 0.06 + k * 0.05))
		if n == 0:
			return
		var cur := 0
		for i in n:
			if games[i]["current"]:
				cur = i
		var xs: Array[float] = []
		for i in n:
			xs.append(size.x * (float(i) + 0.5) / 3.0)
		var line_y := 56.0
		draw_rect(Rect2(4, line_y, (size.x - 8) if pack_art == null else xs[n - 1] - 4.0, 2), Color(1, 1, 1, 0.85))
		draw_rect(Rect2(4, line_y, xs[cur] - 4, 2), UiSkin.GREEN)
		for i in n:
			var g: Dictionary = games[i]
			var cx: float = xs[i]
			var col := UiSkin.YELLOW if g["current"] else UiSkin.WHITE
			UiSkin.draw_text_c(self, cx, 9, g["label"], 8, col, Color(0, 0, 0, 0), UiSkin.SHADOW)
			UiSkin.draw_text_c(self, cx, 18, g["sub"], 8, col, Color(0, 0, 0, 0), UiSkin.SHADOW)
			var team: TeamData = g["team"]
			if team == null:
				continue
			if g["current"]:
				for k in 4:
					draw_circle(Vector2(cx, 46), 26.0 - k * 4.0 + sin(_t * 3.0) * 1.5, Color(UiSkin.GREEN, 0.08 + k * 0.05))
			var tex := ArtGen.helmet(team.abbr, team.uniform_colors(), true)
			draw_texture(tex, Vector2(roundf(cx - 32), 22))
			if g["result"] != "":
				var res: String = g["result"]
				UiSkin.draw_text_c(self, cx, size.y - 1, res, 8,
						UiSkin.GREEN if res.begins_with("W") else (UiSkin.STAR_RED if res.begins_with("L") else UiSkin.WHITE),
						Color(0, 0, 0, 0), UiSkin.SHADOW)


# ---------------------------------------------------------------- daily check-in

func _maybe_daily_popup() -> void:
	if not prof.has_team() or OS.get_cmdline_user_args().has("--no-popups"):
		return
	var cal := DailyRules.calendar(prof)
	var pending := false
	for d in cal:
		if d["today"] and not d["claimed"]:
			pending = true
	if pending:
		DailyPopup.show(self, prof, _ui)
