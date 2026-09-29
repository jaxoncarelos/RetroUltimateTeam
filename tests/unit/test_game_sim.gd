extends GutTest
## GameSim: drive-by-drive finish of a game. Stats add up to the score, momentum carries over,
## averages look like football, and upsets still happen.

func _fresh(home := "KC", away := "PHI") -> GameState:
	var gs := GameState.new(home, away)
	gs.start_possession(away, 25.0)
	return gs


func _sim(gs: GameState, ovr_h := 80, ovr_a := 80, seed_value := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	GameSim.finish(gs, {gs.home: ovr_h, gs.away: ovr_a}, rng)


func test_stats_add_up_to_the_score() -> void:
	for s in 60:
		var gs := _fresh()
		_sim(gs, 80, 80, s + 1)
		for t in [gs.home, gs.away]:
			var st: Dictionary = gs.stats[t]
			var pts := int(gs.score[t])
			var floor_pts := 6 * (int(st["pass_td"]) + int(st["rush_td"])) + 3 * int(st["fg_made"])
			var ceil_pts := floor_pts + int(st["pass_td"]) + int(st["rush_td"])
			assert_true(pts >= floor_pts and pts <= ceil_pts, "%s scored %d from %d TD %d FG" % [t, pts, int(st["pass_td"]) + int(st["rush_td"]), int(st["fg_made"])])
			assert_eq(int(st["yards"]), int(st["pass_yds"]) + int(st["rush_yds"]) - 6 * int(st["sacks"]))
			assert_true(int(st["pass_comp"]) <= int(st["pass_att"]))
			assert_true(int(st["plays"]) >= int(st["pass_att"]) + int(st["rush_att"]) + int(st["sacks"]))


func test_never_ends_tied() -> void:
	for s in 200:
		var gs := _fresh()
		_sim(gs, 75, 75, s + 1)
		assert_ne(gs.score[gs.home], gs.score[gs.away])


func test_full_game_averages_look_like_football() -> void:
	var pts := 0.0
	var yds := 0.0
	var comp := 0.0
	var att := 0.0
	var n := 400
	for s in n:
		var gs := _fresh()
		_sim(gs, 80, 80, s + 1)
		for t in [gs.home, gs.away]:
			pts += int(gs.score[t])
			yds += int(gs.stats[t]["yards"])
			comp += int(gs.stats[t]["pass_comp"])
			att += int(gs.stats[t]["pass_att"])
	pts /= n * 2.0
	yds /= n * 2.0
	assert_between(pts, 18.0, 28.0, "points per team")
	assert_between(yds, 270.0, 420.0, "yards per team")
	assert_between(comp / att, 0.55, 0.72, "completion %")


func test_better_team_wins_more_but_upsets_happen() -> void:
	var wins := 0
	var n := 400
	for s in n:
		var gs := _fresh()
		_sim(gs, 90, 72, s + 1)
		if int(gs.score["KC"]) > int(gs.score["PHI"]):
			wins += 1
	var pct := float(wins) / n
	assert_between(pct, 0.6, 0.93, "favorite win rate %.2f (not a lock, not a coin flip)" % pct)


func _half(home_pts: int, away_pts: int, home_yds: int, away_yds: int) -> GameState:
	var gs := _fresh()
	gs.clock.quarter = 3
	gs.clock.seconds_left = GameClock.QUARTER
	gs.score["KC"] = home_pts
	gs.score["PHI"] = away_pts
	gs.stats["KC"]["plays"] = 34
	gs.stats["PHI"]["plays"] = 30
	gs.stats["KC"]["yards"] = home_yds
	gs.stats["PHI"]["yards"] = away_yds
	return gs


func test_momentum_a_dominant_first_half_carries_over() -> void:
	var wins := 0
	var n := 400
	for s in n:
		var gs := _half(28, 3, 290, 60)   # even ratings, but KC has run away with it
		_sim(gs, 78, 78, s + 1)
		if int(gs.score["KC"]) > int(gs.score["PHI"]):
			wins += 1
	assert_gt(float(wins) / n, 0.97, "a 28-3 lead with 290-60 yards almost never gets lost")


func test_momentum_hot_offense_keeps_scoring_and_a_cold_one_stays_cold() -> void:
	var hot_add := 0.0
	var cold_add := 0.0
	var n := 300
	for s in n:
		var gs := _half(21, 3, 330, 70)
		_sim(gs, 78, 78, s + 1)
		hot_add += int(gs.score["KC"]) - 21
		cold_add += int(gs.score["PHI"]) - 3
	assert_gt(hot_add / n, cold_add / n + 3.0, "the team that has been moving the ball scores more in the second half")


func test_a_close_even_game_stays_close_on_average() -> void:
	var margin := 0.0
	var n := 300
	for s in n:
		var gs := _half(14, 13, 180, 175)
		_sim(gs, 78, 78, s + 1)
		margin += absf(float(gs.score["KC"]) - float(gs.score["PHI"]))
	assert_between(margin / n, 4.0, 14.0, "average final margin of a tied-at-half game")
