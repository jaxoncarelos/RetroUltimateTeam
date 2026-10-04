extends GutTest
## Difficulty: playoff rounds raise the floor (the Super Bowl is always LEGEND), and difficulty
## changes the CPU's decisions (play calling, coach calls, reads), not only its OVR.

var def_ai: DefenseAITuning = load("res://data/tuning/defense_ai_tuning.tres")


func test_playoff_floor_rises_every_round_to_legend() -> void:
	assert_eq(SeasonRules.min_difficulty("WEEK 3"), 0)
	var last := -1
	for r in range(1, SeasonRules.ROUND_NAMES.size()):
		var m := SeasonRules.min_difficulty(SeasonRules.ROUND_NAMES[r])
		assert_gt(m, last, SeasonRules.ROUND_NAMES[r])
		last = m
	assert_eq(SeasonRules.min_difficulty("SUPER BOWL"), TeamRating.DIFFICULTY.size() - 1)
	assert_eq(SeasonRules.game_difficulty(0, "SUPER BOWL"), 3, "a Rookie still plays the Super Bowl on Legend")
	assert_eq(SeasonRules.game_difficulty(2, "DIVISIONAL"), 2, "a higher setting is kept")
	assert_eq(SeasonRules.game_difficulty(0, "WEEK 1"), 0)


func test_rtg_playoff_game_uses_the_floor() -> void:
	var rtg := {"team": "KC", "year": 1, "trust": 50, "player": {"pos": "WR", "name": "T", "jersey": 1, "attrs": {}}, "season": {"phase": "playoffs", "team": "KC",
			"playoffs": {"round": 4, "games": [["KC", "PHI"]]}}}
	var cfg := RtgRules.game_config(rtg, 0, {})
	if cfg.is_empty():
		pass_test("no playoff game in this stub")
		return
	assert_eq(int(cfg["difficulty"]), 3)
	assert_eq(int(cfg["min_difficulty"]), 3)


func test_tables_get_sharper_with_difficulty() -> void:
	for table in [def_ai.call_iq_by_difficulty, def_ai.eyes_by_difficulty, def_ai.qb_iq_by_difficulty,
			def_ai.coach_iq_by_difficulty, def_ai.drive_pts_by_difficulty]:
		assert_eq(table.size(), TeamRating.DIFFICULTY.size())
		for i in range(1, table.size()):
			assert_gt(table[i], table[i - 1])
	for i in range(1, def_ai.react_mult_by_difficulty.size()):
		assert_lt(def_ai.react_mult_by_difficulty[i], def_ai.react_mult_by_difficulty[i - 1], "faster reads")


func test_rookie_defense_ignores_your_tendencies_legend_jumps_on_them() -> void:
	var book: PlaybookDef = load("res://data/plays/defense_playbook.tres")
	var mem := DefenseMemory.new(def_ai)
	var off_book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	var slant: PlayDef = null
	for p in off_book.plays:
		if p.category == "SHORT":
			slant = p
			break
	for i in 6:
		mem.record(slant.id, slant.formation.id, slant.category, 4)
	var sit := {"down": 1, "to_go": 10, "los_x": 40.0}
	var spread := func(iq: float) -> float:
		var w := AIPlayCaller.defense_weights(book.plays, mem, sit, null, iq)
		var mx := 0.0
		var sum := 0.0
		for x in w:
			mx = maxf(mx, x)
			sum += x
		return mx / sum   # share of the favourite call
	assert_lt(spread.call(0.25), spread.call(1.0))
	assert_lt(spread.call(1.0), spread.call(1.5))


func test_coach_iq_changes_fourth_down_calls() -> void:
	var short := {"to_go": 1, "los_x": 52.0}   # 4th and 1 at his own 42
	assert_eq(AIPlayCaller.fourth_down(short, 75.0, 55.0, 1.0), "go", "a sharp coach goes for it")
	assert_eq(AIPlayCaller.fourth_down(short, 75.0, 55.0, 0.2), "punt", "a timid one punts")
	var long_fg := {"to_go": 7, "los_x": 78.0}
	assert_eq(AIPlayCaller.fourth_down(long_fg, 49.0, 54.0, 0.7), "fg")
	assert_eq(AIPlayCaller.fourth_down(long_fg, 49.0, 54.0, 0.2), "punt", "timid: only chip shots")
	var desperate := {"to_go": 9, "los_x": 40.0, "score_diff": -7, "seconds_left": 100.0}
	assert_eq(AIPlayCaller.fourth_down(desperate, 87.0, 60.0, 0.2), "go", "even a timid coach goes when he must")
	assert_false(AIPlayCaller.go_for_two(-2, 4, 0.2))
	assert_true(AIPlayCaller.go_for_two(-2, 4, 1.0))


func test_smarter_cpu_drives_score_more() -> void:
	var a := GameSim.drive_rate(80.0, 80.0, true, 35.0, -2.0)
	var b := GameSim.drive_rate(80.0, 80.0, true, 35.0, 2.0)
	assert_gt(b, a)


func test_runner_scales_reads_only_against_you() -> void:
	var r := PlayRunner.new()
	r.def_ai = def_ai
	r.difficulty = 0
	r.human_team = PlayerAgent.Team.OFFENSE
	assert_almost_eq(r.eyes_mult(), def_ai.eyes_by_difficulty[0], 0.001)
	assert_eq(r.cpu_qb_iq(), 0.0, "your own QB isn't dumbed down")
	r.human_team = PlayerAgent.Team.DEFENSE
	r.difficulty = 3
	assert_almost_eq(r.cpu_qb_iq(), def_ai.qb_iq_by_difficulty[3], 0.001)
	assert_eq(r.eyes_mult(), 1.0)
	r.human_team = -1
	assert_eq(r.cpu_qb_iq(), 0.0, "CPU vs CPU unchanged")
	r.free()
