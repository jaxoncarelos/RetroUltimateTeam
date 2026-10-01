extends GutTest
## PlayByPlay.synthesize / from_log and the drive_log GameSim now returns.

func _sim_log(seed_value: int) -> Dictionary:
	var gs := GameState.new("KC", "PHI")
	gs.start_possession("PHI", 25.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var summary := GameSim.finish(gs, {"KC": 80, "PHI": 78}, rng)
	return {"gs": gs, "log": summary["drive_log"]}


func _scrimmage_yards(plays: Array[Dictionary]) -> int:
	var t := 0
	for p in plays:
		t += int(p["yards"])
	return t


func test_drive_yards_sum_exactly_and_outcome_ends_drive() -> void:
	var seen := {}
	for s in 40:
		var log: Array = _sim_log(s + 1)["log"]
		assert_gt(log.size(), 5)
		for i in log.size():
			var d: Dictionary = log[i]
			var plays := PlayByPlay.synthesize(d, 100 + i)
			assert_false(plays.is_empty())
			assert_eq(_scrimmage_yards(plays), int(d["yards"]), "yards sum for %s" % [d])
			var last: Dictionary = plays[plays.size() - 1]
			var want := {"td": "td", "fg": "fg", "miss": "miss", "punt": "punt", "turnover": "turnover", "downs": "downs"}
			assert_eq(last["result"], want[d["outcome"]])
			seen[d["outcome"]] = true
			for k in plays.size() - 1:
				assert_false(plays[k]["result"] in ["td", "fg", "miss", "punt", "turnover", "downs"], "no early ending")
			if d["outcome"] == "td":
				assert_almost_eq(float(last["to_x"]), 100.0, 1.0)
	for o in ["td", "fg", "punt", "turnover", "downs"]:
		assert_true(seen.has(o), "saw %s" % o)


func test_points_in_log_match_score() -> void:
	var r := _sim_log(7)
	var gs: GameState = r["gs"]
	var pts := {"KC": 0, "PHI": 0}
	for d in r["log"]:
		pts[d["team"]] += int(d["points"])
	# Drives only cover the simulated part (game started 0-0 here), so totals are equal.
	assert_eq(pts["KC"], int(gs.score["KC"]))
	assert_eq(pts["PHI"], int(gs.score["PHI"]))


func test_deterministic_synthesis_and_game_sim() -> void:
	var a := _sim_log(42)
	var b := _sim_log(42)
	assert_eq(a["log"], b["log"])
	assert_eq((a["gs"] as GameState).score, (b["gs"] as GameState).score)
	assert_eq(PlayByPlay.from_drives(a["log"], 9), PlayByPlay.from_drives(b["log"], 9))
	assert_ne(PlayByPlay.from_drives(a["log"], 9), PlayByPlay.from_drives(a["log"], 10))


func test_text_and_headers() -> void:
	var plays := PlayByPlay.from_drives([
		{"team": "KC", "outcome": "td", "plays": 6, "yards": 75, "points": 7, "start_x": 25.0},
		{"team": "PHI", "outcome": "punt", "plays": 4, "yards": 8, "points": 0, "start_x": 25.0}], 3)
	assert_eq(plays[0]["header"], "KC drive 1 - TD, 6 plays 75 yd")
	assert_string_contains(plays[0]["text"], "1st & 10 at own 25")
	var punt: Dictionary = plays[plays.size() - 1]
	assert_string_contains(punt["text"], "Punt")
	assert_string_contains(punt["text"], "4th &")
	var heads := 0
	for p in plays:
		if p["header"] != "":
			heads += 1
	assert_eq(heads, 2)


func test_from_log_passthrough() -> void:
	var out := PlayByPlay.from_log([
		{"quarter": 1, "clock": 880.0, "down": 1, "dist": 10, "spot": 25.0, "text": "Run", "yards": 4, "team": "KC"},
		{"quarter": 1, "clock": 850.0, "down": 2, "dist": 6, "spot": 29.0, "text": "Pass", "yards": 12, "team": "KC"},
		{"quarter": 1, "clock": 800.0, "down": 1, "dist": 10, "spot": 25.0, "text": "Run", "yards": 0, "team": "PHI"}])
	assert_eq(out.size(), 3)
	assert_eq(out[0]["to_x"], 29.0)
	assert_eq(out[0]["drive"], 0)
	assert_eq(out[2]["drive"], 1)
	assert_ne(out[2]["header"], "")
	assert_eq(out[1]["header"], "")
	assert_eq(PlayByPlay.summary(out[1]), "Play had 12 yd gain")
