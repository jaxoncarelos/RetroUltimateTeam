extends GutTest
## Challenges (goal evaluation, daily generator, start states in the match) and ModeResults.

var _saved: Profile


func before_all() -> void:
	_saved = SaveManager.profile
	SaveManager.disabled = true


func after_all() -> void:
	SaveManager.profile = _saved


func _profile() -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, GameData.db, "KC")
	SaveManager.profile = p
	return p


func test_goal_evaluation() -> void:
	assert_eq(ChallengeRules.evaluate("td", {"you_tds": 1}), 1)
	assert_eq(ChallengeRules.evaluate("td", {"possession_lost": true}), -1)
	assert_eq(ChallengeRules.evaluate("td", {}), 0)
	assert_eq(ChallengeRules.evaluate("stop", {"opp_pts": 3}), -1)
	assert_eq(ChallengeRules.evaluate("stop", {"their_drive_over": true}), 1)
	assert_eq(ChallengeRules.evaluate("win", {"game_over": true, "you_lead": true}), 1)
	assert_eq(ChallengeRules.evaluate("win", {"game_over": true}), -1)
	assert_eq(ChallengeRules.evaluate("tds:2", {"you_tds": 1}), 0)
	assert_eq(ChallengeRules.evaluate("tds:2", {"you_tds": 2}), 1)
	assert_eq(ChallengeRules.evaluate("tds:2", {"you_tds": 1, "period_over": true}), -1)
	assert_eq(ChallengeRules.evaluate("ints:2", {"ints": 2}), 1)
	assert_eq(ChallengeRules.evaluate("score", {"you_pts": 3}), 1)


func test_there_are_ten_plus_challenges_with_valid_data() -> void:
	assert_gte(ChallengeRules.LIST.size(), 10)
	var ids := {}
	var teams := TeamData.load_all()
	for c in ChallengeRules.LIST:
		assert_false(ids.has(c["id"]))
		ids[c["id"]] = true
		assert_true(teams.has(c["opponent"]), c["id"])
		var st: Dictionary = c["start"]
		assert_between(int(st["yard"]), 1, 99, c["id"])
		assert_between(int(st["quarter"]), 1, 4, c["id"])
		if c["pack"] != "":
			assert_not_null(PackCatalog.get_pack(c["pack"]), c["id"])


func test_daily_is_deterministic_per_date() -> void:
	var teams := TeamData.load_all().keys()
	assert_eq(ChallengeRules.daily(20260928, teams), ChallengeRules.daily(20260928, teams))
	assert_ne(ChallengeRules.daily(20260928, teams)["id"], ChallengeRules.daily(20260929, teams)["id"])
	assert_eq(ChallengeRules.daily_seed(0), 19700101)


func test_every_challenge_starts_in_its_state() -> void:
	_profile()
	for c in ChallengeRules.LIST:
		var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
		m.config = {"home": "KC", "away": c["opponent"], "from_hub": true, "mode": "challenge", "challenge": c}
		add_child_autofree(m)
		var st: Dictionary = c["start"]
		assert_eq(m.gs.clock.quarter, int(st["quarter"]), c["id"])
		assert_eq(int(m.gs.clock.seconds_left), int(st["clock"]), c["id"])
		assert_eq(int(m.gs.score["KC"]), int(st["you"]), c["id"])
		assert_eq(m.gs.possession, "KC" if st["ball"] == "you" else c["opponent"], c["id"])
		assert_eq(m.gs.downs.los_x, FieldGeo.OWN_GOAL + float(st["yard"]), c["id"])
		assert_eq(m.gs.downs.down, int(st["down"]), c["id"])


func test_challenge_decides_and_reports() -> void:
	_profile()
	var c: Dictionary = ChallengeRules.find("red_zone_regular")
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	m.config = {"home": "KC", "away": "PIT", "from_hub": true, "mode": "challenge", "challenge": c,
			"extra": {"challenge": c["id"]}}
	add_child_autofree(m)
	m.gs.stats["KC"]["rush_td"] += 1
	m.gs.add_points("KC", 6)
	assert_true(m._check_challenge())
	var r := m.match_result()
	assert_true(r["challenge_won"])
	var prof := SaveManager.profile
	var coins := prof.coins
	var msg := ModeResults.apply(r, prof, GameData.db)
	assert_string_contains(msg, "COMPLETE")
	assert_eq(prof.coins, coins + int(c["coins"]))
	assert_string_contains(ModeResults.apply(r, prof, GameData.db), "ALREADY", "reward only once")


func test_season_results_advance_the_season() -> void:
	var prof := _profile()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var strengths := {}
	for a in GameData.teams:
		strengths[a] = GameData.db.team_ovr(a)
	prof.season = SeasonRules.new_season(GameData.teams, "KC", 2, strengths, rng)
	for w in 2:
		var g: Array = []
		for pair in prof.season["weeks"][w]:
			if "KC" in pair:
				g = pair
		var opp: String = g[1] if g[0] == "KC" else g[0]
		ModeResults.apply({"mode": "season", "team": "KC", "opponent": opp, "pf": 30, "pa": 3,
				"extra": {"home": g[0], "away": g[1]}}, prof, GameData.db)
	assert_eq(prof.season["phase"], "playoffs")
	var table := SeasonRules.standings(prof.season, GameData.teams.keys())
	assert_eq(table["KC"]["w"], 2)
	var total_games := 0
	for a in table:
		total_games += int(table[a]["w"]) + int(table[a]["l"]) + int(table[a]["t"])
	assert_eq(total_games, 2 * 32, "every team played every week")
