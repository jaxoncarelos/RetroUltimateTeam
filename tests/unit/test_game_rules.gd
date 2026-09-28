extends GutTest
## Phase 3 rules: GameClock, GameState.apply_result, KickModel, CPU 4th down / 2-pt.

var t: GameplayTuning


func before_each() -> void:
	t = load("res://data/tuning/gameplay_tuning.tres")


# ---------------------------------------------------------------- clock

func test_clock_speed_maps_real_quarter_to_nfl_time() -> void:
	var c := GameClock.new(150.0)
	assert_almost_eq(c.speed, 6.0, 0.001)
	c.tick_live(10.0)
	assert_almost_eq(c.seconds_left, 900.0 - 60.0, 0.001)
	assert_eq(c.label(), "Q1 14:00")


func test_runoff_only_when_clock_running() -> void:
	var c := GameClock.new(150.0)
	c.stopped = true
	c.apply_runoff(30.0)
	assert_eq(c.seconds_left, 900.0)
	c.stopped = false
	c.apply_runoff(30.0)
	assert_eq(c.seconds_left, 870.0)


func test_two_minute_warning_once_in_q2_and_q4() -> void:
	var c := GameClock.new(150.0)
	c.quarter = 2
	c.seconds_left = 130.0
	c.stopped = false
	assert_true(c.apply_runoff(25.0))
	assert_eq(c.seconds_left, 105.0)
	assert_true(c.stopped, "the warning stops the clock")
	c.stopped = false
	c.seconds_left = 125.0
	assert_false(c.apply_runoff(25.0), "only once per half")
	var q1 := GameClock.new(150.0)
	q1.seconds_left = 130.0
	q1.stopped = false
	assert_false(q1.apply_runoff(25.0), "no warning in Q1")


func test_periods_and_overtime() -> void:
	var c := GameClock.new(150.0)
	assert_eq(c.next_period(), "q2")
	assert_eq(c.next_period(), "half")
	assert_eq(c.half_seconds_left(), 1800.0)
	assert_eq(c.next_period(), "q4")
	assert_eq(c.next_period(), "regulation_over")
	assert_true(c.is_overtime())
	assert_eq(c.seconds_left, GameClock.OT_PERIOD)
	assert_eq(c.label().left(2), "OT")


# ---------------------------------------------------------------- game state

func _gs() -> GameState:
	var g := GameState.new("KC", "PHI", 150.0)
	g.start_possession("KC", 35.0)
	return g


func _r(type: String, spot_x: float, yards: int, thrown := true) -> Dictionary:
	return {"type": type, "spot_x": spot_x, "spot_y": 26.0, "yards": yards, "turnover": type in ["int", "int_td", "fumble"],
			"pass_thrown": thrown}


func test_touchdown_scores_six_and_goes_to_pat() -> void:
	var g := _gs()
	var next := g.apply_result(_r("td", 111.0, 76), false, 900.0)
	assert_eq(next, GameState.Next.PAT)
	assert_eq(g.score["KC"], 6)
	assert_eq(g.stats["KC"]["pass_td"], 1)
	assert_true(g.clock.stopped)


func test_interception_flips_possession_and_field() -> void:
	var g := _gs()
	var next := g.apply_result(_r("int", 70.0, 0), false, 900.0)
	assert_eq(next, GameState.Next.PLAY)
	assert_eq(g.possession, "PHI")
	assert_eq(g.downs.los_x, 50.0, "their spot is 120 - 70 in their coordinates")
	assert_eq(g.stats["KC"]["int"], 1)


func test_pick_six_scores_for_the_defense() -> void:
	var g := _gs()
	var next := g.apply_result(_r("int_td", 8.0, 0), false, 900.0)
	assert_eq(next, GameState.Next.PAT)
	assert_eq(g.score["PHI"], 6)
	assert_eq(g.possession, "PHI")


func test_turnover_on_downs_gives_ball_at_spot() -> void:
	var g := _gs()
	for i in 4:
		g.apply_result(_r("tackle", g.downs.los_x + 1.0, 1, false), true, 900.0)
	assert_eq(g.possession, "PHI")
	assert_eq(g.downs.los_x, 120.0 - 39.0)


func test_safety_is_two_for_the_defense_and_a_free_kick() -> void:
	var g := _gs()
	g.start_possession("KC", 12.0)
	var next := g.apply_result(_r("sack", 9.0, -3), false, 900.0)
	assert_eq(next, GameState.Next.FREE_KICK)
	assert_eq(g.score["PHI"], 2)


func test_incompletion_stops_clock_and_tackle_runs_it() -> void:
	var g := _gs()
	g.apply_result(_r("incomplete", 35.0, 0), false, 900.0)
	assert_true(g.clock.stopped)
	g.apply_result(_r("tackle", 39.0, 4, false), true, 900.0)
	assert_false(g.clock.stopped)
	assert_eq(g.stats["KC"]["rush_att"], 1)
	assert_eq(g.stats["KC"]["pass_att"], 1)


func test_clock_expiry_ends_the_period() -> void:
	var g := _gs()
	g.clock.seconds_left = 0.0
	var next := g.apply_result(_r("tackle", 39.0, 4, false), true, 5.0)
	assert_eq(next, GameState.Next.END_PERIOD)


func test_runoff_tempo() -> void:
	var g := _gs()
	assert_eq(g.runoff(t), t.runoff_normal)
	g.clock.quarter = 4
	g.clock.seconds_left = 90.0
	g.score["PHI"] = 7
	assert_eq(g.runoff(t), t.runoff_hurry, "trailing late: hurry up")
	g.score["KC"] = 14
	g.clock.seconds_left = 200.0
	assert_eq(g.runoff(t), t.runoff_milk, "leading late: milk the clock")


func test_timeouts() -> void:
	var g := _gs()
	g.clock.stopped = false
	for i in 3:
		assert_true(g.use_timeout("KC"))
	assert_false(g.use_timeout("KC"))
	assert_true(g.clock.stopped)


func test_overtime_needs_both_possessions() -> void:
	var g := _gs()
	g.overtime = true
	g.clock.quarter = 5
	g.add_points("KC", 7)
	g.ot_possessions = 1
	assert_false(g.overtime_decided())
	g.ot_possessions = 2
	assert_true(g.overtime_decided())


# ---------------------------------------------------------------- kicks

func test_fg_distance_and_range() -> void:
	assert_eq(KickModel.fg_distance(90.0), 37.0)
	assert_gt(KickModel.fg_max_range(t, 95), KickModel.fg_max_range(t, 60))
	assert_eq(KickModel.fg_prob(t, 70.0, 60, 60), 0.0)
	assert_gt(KickModel.fg_prob(t, 25.0, 80, 80), KickModel.fg_prob(t, 50.0, 80, 80))


func test_kick_meter_zones() -> void:
	assert_gt(KickModel.meter_zone(t, 25.0, 90), KickModel.meter_zone(t, 55.0, 90))
	assert_gt(KickModel.meter_zone(t, 40.0, 95), KickModel.meter_zone(t, 40.0, 55))
	assert_gt(KickModel.meter_speed(t, 55.0), KickModel.meter_speed(t, 25.0))
	assert_eq(KickModel.meter_result(t, 0.0, 30.0, 80, 80), "good")
	var z := KickModel.meter_zone(t, 30.0, 80)
	assert_eq(KickModel.meter_result(t, z + t.meter_doink * 0.5, 30.0, 80, 80), "doink")
	assert_eq(KickModel.meter_result(t, 0.99, 30.0, 80, 80), "wide")
	assert_eq(KickModel.meter_result(t, 0.0, 80.0, 60, 80), "short")


func test_kickoff_and_punt_spots_are_on_the_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 200:
		var k := KickModel.kickoff(t, rng, 80)
		assert_between(k, FieldGeo.OWN_GOAL + 1.0, FieldGeo.OPP_GOAL - 1.0)
		var p := KickModel.punt(t, rng, 80, 40.0)
		assert_between(p, FieldGeo.OWN_GOAL, FieldGeo.LENGTH - FieldGeo.OWN_GOAL)


# ---------------------------------------------------------------- CPU decisions

func test_fourth_down_decisions() -> void:
	assert_eq(AIPlayCaller.fourth_down({"to_go": 8, "los_x": 40.0}, 87.0, 60.0), "punt")
	assert_eq(AIPlayCaller.fourth_down({"to_go": 8, "los_x": 85.0}, 42.0, 60.0), "fg")
	assert_eq(AIPlayCaller.fourth_down({"to_go": 1, "los_x": 60.0}, 67.0, 60.0), "go")
	assert_eq(AIPlayCaller.fourth_down({"to_go": 9, "los_x": 40.0, "score_diff": -7, "seconds_left": 100.0}, 87.0, 60.0), "go")
	assert_eq(AIPlayCaller.fourth_down({"to_go": 9, "los_x": 85.0, "score_diff": -2, "seconds_left": 100.0}, 42.0, 60.0), "fg")


func test_go_for_two_chart() -> void:
	assert_true(AIPlayCaller.go_for_two(-2, 4))
	assert_false(AIPlayCaller.go_for_two(-2, 2), "only late")
	assert_false(AIPlayCaller.go_for_two(-1, 4))
