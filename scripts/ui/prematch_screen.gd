extends Control
## PRE-MATCH (Retro Bowl matchup screen): both helmets, records, team names, offense /
## defense stars, a center panel with the OVR matchup and what a win pays (so the coin
## loop is always visible), the difficulty toggle, PLAY and SIM GAME.
## Config: a MatchConfig ({home, away, mode, extra, label, difficulty, from_hub}).

var cfg: Dictionary
var prof: Profile
var _ui: Dictionary
var _diff_btn: Button
var _reward_col: VBoxContainer
var _opp_view: _Side


func _ready() -> void:
	prof = SaveManager.profile
	cfg = SceneRouter.take_config()
	if cfg.is_empty():
		cfg = GameFlow.next_game_config(prof)
	cfg["difficulty"] = Settings.difficulty
	var title: String = cfg.get("label", "QUICK MATCH")
	_ui = MetaUI.screen(self, title)
	if cfg.get("mode", "quick") != "challenge":
		var sim := MetaUI.button("SIM GAME ▶", Vector2(78, 20), _sim)
		_ui["top_right"].add_child(sim)
	var you: TeamData = GameData.team(cfg.get("home", prof.franchise_team))
	var opp: TeamData = GameData.team(cfg.get("away", "PHI"))
	var root: VBoxContainer = _ui["root"]
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	root.add_child(row)
	_opp_view = _Side.new()
	_opp_view.team = opp
	_opp_view.facing_left = false
	_opp_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_opp_view)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(150, 0)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	row.add_child(mid)
	var you_view := _Side.new()
	you_view.team = you
	you_view.facing_left = true
	you_view.mine = true
	you_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(you_view)
	var mine_entries := Collection.lineup_entries(prof, GameData.db)
	var my_ovr := Collection.team_ovr(prof, GameData.db)
	you_view.ovr = my_ovr
	you_view.stars = MetaUI.side_stars(mine_entries)
	you_view.record = _record(you.abbr if you != null else "")
	_opp_view.record = _record(opp.abbr if opp != null else "")
	_set_opp(my_ovr)
	var vs := TextureRect.new()
	vs.texture = UiSkin.logo(["VS"], 3, Color.WHITE, Color("#b9c6e8"), UiSkin.STAR_RED, UiSkin.SHADOW)
	vs.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mid.add_child(vs)
	var mp := RetroPanel.new("REWARDS", UiSkin.PANEL, 5)
	mid.add_child(mp)
	_reward_col = VBoxContainer.new()
	_reward_col.add_theme_constant_override("separation", 1)
	mp.add_child(_reward_col)
	_fill_rewards()
	var nav: HBoxContainer = _ui["nav"]
	_diff_btn = MetaUI.nav_button("", _cycle_difficulty, 190)
	nav.add_child(_diff_btn)
	nav.add_child(MetaUI.spacer())
	var play := MetaUI.continue_button("PLAY", _play, true, 120)
	nav.add_child(play)
	Fx.pulse.call_deferred(play, 1.05, 1.0)
	_refresh_diff()
	you_view.slide_from = 1.0
	_opp_view.slide_from = -1.0


func _record(abbr: String) -> String:
	var s := prof.season
	if cfg.get("mode", "") == "season" and not s.is_empty():
		var table := SeasonRules.standings(s, GameData.teams.keys())
		var r: Dictionary = table.get(abbr, {})
		if not r.is_empty():
			return "%d-%d%s" % [r["w"], r["l"], "-%d" % r["t"] if int(r["t"]) > 0 else ""]
	if abbr == prof.franchise_team:
		return "%d-%d" % [prof.stats["wins"], prof.stats["losses"]]
	# No record to show: their division, so both sides line up.
	var t: TeamData = GameData.team(abbr)
	return ("%s %s" % [t.conf, t.div.to_upper()]).strip_edges() if t != null else ""


## The opponent plays at a difficulty-scaled OVR (GameData.opponent_lineup).
func _set_opp(my_ovr: int) -> void:
	var abbr: String = cfg.get("away", "PHI")
	var entries := GameData.db.team_entries(abbr)
	var real := TeamRating.team_ovr(entries)
	var eff := TeamRating.opponent_effective_ovr(my_ovr, Settings.difficulty, real, GameData.league_avg_ovr())
	_opp_view.ovr = eff
	_opp_view.stars = MetaUI.side_stars(TeamRating.rescale_entries(entries, real, eff))
	_opp_view.queue_redraw()


func _fill_rewards() -> void:
	MetaUI.clear(_reward_col)
	var mult: float = TeamRating.DIFFICULTY[Settings.difficulty][2]
	var streak := int(prof.stats.get("win_streak", 0))
	var lines := [["WIN", "+%d" % int(round(EconomyRules.WIN_COINS * mult)), UiSkin.YELLOW],
			["LOSS", "+%d" % int(round(EconomyRules.LOSS_COINS * mult)), UiSkin.WHITE],
			["EACH TD", "+%d" % EconomyRules.TD_BONUS, UiSkin.WHITE],
			["SACK / INT", "+%d" % EconomyRules.TAKEAWAY_BONUS, UiSkin.WHITE]]
	if streak >= 1:
		lines.append(["STREAK x%d" % (streak + 1), "+%d%%" % int(minf(EconomyRules.STREAK_STEP * streak,
				EconomyRules.STREAK_CAP) * 100), Color("#ffb14a")])
	var today := DailyRules.day_of()
	if int(prof.stats.get("last_win_day", 0)) != today:
		lines.append(["1ST WIN TODAY", "+%d" % EconomyRules.DAILY_WIN_BONUS, UiSkin.GREEN])
	for l in lines:
		var h := HBoxContainer.new()
		var a := MetaUI.label(l[0], UiSkin.MUTED)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(MetaUI.label(l[1], l[2], 8, HORIZONTAL_ALIGNMENT_RIGHT))
		var coin := TextureRect.new()
		coin.texture = UiSkin.coin_tex()
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(coin)
		_reward_col.add_child(h)


func _refresh_diff() -> void:
	var d: Array = TeamRating.DIFFICULTY[Settings.difficulty]
	_diff_btn.text = "DIFFICULTY: %s  (x%.2f)" % [d[0], d[2]]


func _cycle_difficulty() -> void:
	Settings.difficulty = (Settings.difficulty + 1) % TeamRating.DIFFICULTY.size()
	Settings.save_settings()
	cfg["difficulty"] = Settings.difficulty
	_refresh_diff()
	_set_opp(Collection.team_ovr(prof, GameData.db))
	_fill_rewards()
	Fx.pop(_reward_col, 1.08, 0.2)


func _play() -> void:
	cfg["from_hub"] = true
	SceneRouter.goto(SceneRouter.MATCH, cfg)


func _sim() -> void:
	SceneRouter.goto(SceneRouter.RESULTS, {"last_result": GameFlow.sim_result(prof, cfg)})


## One team: helmet (2x), record, city, big name, offense/defense stars, OVR.
class _Side:
	extends Control
	var team: TeamData
	var facing_left := false
	var mine := false
	var ovr := 0
	var record := ""
	var stars: Dictionary = {"off": 2.5, "def": 2.5}
	var slide_from := 0.0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if _t < 1.0:
			_t = minf(1.0, _t + delta * 3.0)
			queue_redraw()

	func _draw() -> void:
		if team == null:
			return
		var ease := 1.0 - pow(1.0 - _t, 3.0)
		var dx := slide_from * (1.0 - ease) * 200.0
		var cx := size.x * 0.5 + dx
		var tex := ArtGen.helmet(team.abbr, team.uniform_colors(), facing_left)
		draw_texture_rect(tex, Rect2(Vector2(roundf(cx - 64), 2), Vector2(128, 96)), false)
		var y := 108.0
		if record != "":
			UiSkin.draw_text_c(self, cx, y, record, 8, UiSkin.WHITE, Color(0, 0, 0, 0), UiSkin.SHADOW)
		y += 10
		UiSkin.draw_text_c(self, cx, y, team.city.to_upper(), 8, UiSkin.MUTED)
		y += 18
		UiSkin.draw_text_c(self, cx, y, team.team_name.to_upper(), 16, UiSkin.YELLOW if mine else UiSkin.WHITE,
				UiSkin.SHADOW, Color(0.02, 0.03, 0.15, 0.9))
		y += 6
		for k in 2:
			var lab := "OFFENSE" if k == 0 else "DEFENSE"
			var col := UiSkin.STAR_BLUE if k == 0 else UiSkin.STAR_RED
			var v: float = stars["off"] if k == 0 else stars["def"]
			var yy := y + k * 11
			UiSkin.draw_text(self, Vector2(cx - 50, yy + 8), lab, 8, UiSkin.WHITE)
			for i in 5:
				UiSkin.draw_star(self, Vector2(cx + 2 + i * 9, yy + 1), col, clampf(v - i, 0.0, 1.0))
		UiSkin.draw_text_c(self, cx, y + 33, "OVR %d" % ovr, 8, UiSkin.YELLOW if mine else UiSkin.WHITE)
