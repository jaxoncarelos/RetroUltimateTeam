extends GutTest
## Road to Glory career rules: creation, OVR, upgrades, the draft, a full season with
## playoffs, awards, the offseason (aging, contracts), retirement and the save round trip.

var rng := RandomNumberGenerator.new()


func before_each() -> void:
	rng.seed = 2024


func _career(pos := "WR") -> Dictionary:
	var arch: String = RtgRules.ARCHETYPES[pos][0]["id"]
	return RtgRules.new_career(RtgRules.new_player(pos, arch, "Jalen", "Carter", 11, {"skin": 3}))


func _drafted(pos := "WR") -> Dictionary:
	var rtg := _career(pos)
	var d := RtgRules.draft(rtg, 70.0, GameData.teams, RtgFlow.team_ovrs(), RtgFlow.starter_ovrs(RtgRules.SLOT[pos]), rng)
	RtgRules.sign_rookie(rtg, d, GameData.teams, RtgFlow.team_ovrs(), 8, rng)
	return rtg


func test_every_archetype_starts_as_a_raw_rookie() -> void:
	for pos in RtgRules.POSITIONS:
		assert_eq(RtgRules.ARCHETYPES[pos].size(), 3)
		for a in RtgRules.ARCHETYPES[pos]:
			var o := RtgRules.ovr(pos, RtgRules.start_attrs(pos, a["id"]))
			assert_between(o, 58, 68, "%s %s starts at %d" % [pos, a["id"], o])
	var p := RtgRules.new_player("RB", "power", "a", "b", 22, {})
	assert_eq(p["name"], "A. B")
	assert_eq(p["age"], RtgRules.START_AGE)


func test_archetypes_shape_the_ratings() -> void:
	var deep := RtgRules.start_attrs("WR", "deep_threat")
	var poss := RtgRules.start_attrs("WR", "possession")
	assert_gt(int(deep["spd"]), int(poss["spd"]))
	assert_gt(int(poss["cth"]), int(deep["cth"]))


func test_upgrades_cost_more_at_the_top_and_raise_ovr() -> void:
	assert_lt(RtgRules.upgrade_cost(65), RtgRules.upgrade_cost(80))
	assert_lt(RtgRules.upgrade_cost(80), RtgRules.upgrade_cost(95))
	var rtg := _career("WR")
	assert_false(RtgRules.upgrade(rtg, "cth"), "no XP yet")
	rtg["xp"] = 50000
	var before := RtgRules.player_ovr(rtg)
	for i in 30:
		RtgRules.upgrade(rtg, "cth")
		RtgRules.upgrade(rtg, "rte")
	assert_gt(RtgRules.player_ovr(rtg), before + 10)
	assert_lt(int(rtg["xp"]), 50000)
	assert_false(RtgRules.upgrade(rtg, "tak"), "only your position's ratings")


func test_draft_and_rookie_season() -> void:
	var rtg := _drafted("RB")
	assert_eq(rtg["stage"], "season")
	assert_true(GameData.teams.has(rtg["team"]))
	assert_between(int(rtg["draft"]["round"]), 1, 7)
	assert_gt(int(rtg["contract"]["years"]), 2)
	assert_eq((rtg["goals"] as Array).size(), 3)
	var g := RtgRules.next_game(rtg)
	assert_false(g.is_empty())
	assert_true(rtg["team"] in [g["home"], g["away"]])
	var cfg := RtgRules.game_config(rtg, 1, {})
	assert_eq(cfg["mode"], "rtg")
	assert_eq(cfg["home"], rtg["team"])
	assert_eq(cfg["rtg"]["slot"], "RB")
	assert_true(cfg["rtg"]["show_tips"], "first game: controls tip")


func test_a_great_combine_drafts_you_higher() -> void:
	var hi := 0
	var lo := 0
	for i in 40:
		rng.seed = 100 + i
		hi += int(RtgRules.draft(_career(), 95.0, GameData.teams, RtgFlow.team_ovrs(), RtgFlow.starter_ovrs("WR1"), rng)["overall"])
		rng.seed = 100 + i
		lo += int(RtgRules.draft(_career(), 35.0, GameData.teams, RtgFlow.team_ovrs(), RtgFlow.starter_ovrs("WR1"), rng)["overall"])
	assert_lt(hi, lo)


func test_a_game_moves_xp_trust_week_and_stats() -> void:
	var rtg := _drafted("WR")
	var r := RtgRules.sim_game(rtg, rng)
	r["simulated"] = false
	r["rtg"]["points"] = 90.0
	r["rtg"]["stats"]["rec"] = 7
	r["rtg"]["stats"]["rec_yds"] = 120
	r["rtg"]["stats"]["rec_td"] = 2
	var t0 := int(rtg["trust"])
	var res := RtgRules.apply_game(rtg, r, GameData.teams, rng)
	assert_eq(res["grade"], "A")
	assert_gt(int(res["xp"]), 400)
	assert_gt(int(rtg["trust"]), t0)
	assert_eq(int(rtg["season"]["week"]), 1)
	assert_eq(int(rtg["season_stats"]["rec_yds"]), 120)
	assert_eq((rtg["games"] as Array).size(), 1)


func test_sims_pay_less_than_playing() -> void:
	var st := RtgTracker.empty_stats()
	assert_lt(RtgRules.game_xp(64.0, st, true, 0, true), RtgRules.game_xp(64.0, st, true, 0, false) * 0.6)
	assert_gt(RtgRules.game_xp(90.0, st, true, 3), RtgRules.game_xp(90.0, st, true, 0), "dev traits earn more")


func test_full_season_to_offseason_and_next_year() -> void:
	var rtg := _drafted("CB")
	var guard := 40
	while str(rtg["stage"]) == "season" and guard > 0:
		guard -= 1
		var r := RtgRules.sim_game(rtg, rng)
		assert_false(r.is_empty())
		RtgRules.apply_game(rtg, r, GameData.teams, rng)
	assert_eq(rtg["stage"], "offseason")
	assert_eq(rtg["season"]["phase"], "done")
	assert_true(RtgRules.next_game(rtg).is_empty())
	var close := RtgRules.close_season(rtg)
	assert_true(close.has("awards"))
	assert_eq((rtg["career"] as Array).size(), 1)
	var age := int(rtg["player"]["age"])
	RtgRules.next_season(rtg, GameData.teams, RtgFlow.team_ovrs(), 8, rng)
	assert_eq(int(rtg["year"]), 2)
	assert_eq(int(rtg["player"]["age"]), age + 1)
	assert_eq(rtg["stage"], "season")
	assert_eq(int(rtg["season"]["week"]), 0)


func test_awards_follow_production() -> void:
	var rtg := _drafted("WR")
	for i in 8:
		rtg["games"].append({"pf": 30, "pa": 10, "pts": 88.0})
	var st: Dictionary = rtg["season_stats"]
	st["rec"] = 60
	st["rec_yds"] = 900
	st["rec_td"] = 9
	var a := RtgRules.season_awards(rtg)
	assert_has(a, "roy")
	assert_has(a, "pro_bowl")
	var quiet := _drafted("WR")
	for i in 8:
		quiet["games"].append({"pf": 10, "pa": 30, "pts": 55.0})
	assert_eq(RtgRules.season_awards(quiet).size(), 0)


func test_aging_takes_speed_after_thirty() -> void:
	var rtg := _career("RB")
	rtg["player"]["age"] = 31
	var spd := int(rtg["player"]["attrs"]["spd"])
	var drops := 0
	for i in 5:
		var ch := RtgRules.age_player(rtg, rng)
		drops += -int(ch.get("spd", 0))
	assert_gt(drops, 2)
	assert_lt(int(rtg["player"]["attrs"]["spd"]), spd)


func test_contracts_and_retirement() -> void:
	var rtg := _drafted("QB")
	rtg["contract"]["years"] = 1
	assert_true(RtgRules.contract_up(rtg))
	var offers := RtgRules.contract_offers(rtg, GameData.teams, RtgFlow.team_ovrs(), rng)
	assert_eq(offers.size(), 4)
	assert_true(offers[3].get("stay", false))
	RtgRules.sign(rtg, offers[0])
	assert_eq(rtg["team"], offers[0]["team"])
	assert_false(RtgRules.can_retire(rtg), "a rookie can't retire yet")
	rtg["player"]["age"] = RtgRules.RETIRE_AGE
	assert_eq(RtgRules.must_retire(rtg), "AGE")
	rtg["legacy"] = RtgRules.HOF_LEGACY + 5
	var legend := RtgRules.retire(rtg, "AGE")
	assert_true(legend["hof"])
	assert_eq(rtg["stage"], "retired")


func test_save_round_trip() -> void:
	var prof := Profile.new()
	prof.rtg = _drafted("WR")
	prof.rtg_legends = [{"name": "X", "pos": "CB", "hof": true}]
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(prof.to_dict())))
	assert_eq(back.rtg["team"], prof.rtg["team"])
	assert_eq(int(back.rtg["player"]["attrs"]["cth"]), int(prof.rtg["player"]["attrs"]["cth"]))
	assert_eq(RtgRules.next_game(back.rtg)["label"], RtgRules.next_game(prof.rtg)["label"])
	assert_eq(back.rtg_legends.size(), 1)


func test_coordinator_feeds_you() -> void:
	var book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	var sit := {"down": 1, "to_go": 10, "los_x": 35.0, "score_diff": 0, "seconds_left": 999.0}
	var mine_hi := 0
	var mine_lo := 0
	for i in 300:
		if RtgPlay.features(RtgPlay.oc_call(book.plays, sit, rng, "RB", 1.0), "RB"):
			mine_hi += 1
		if RtgPlay.features(RtgPlay.oc_call(book.plays, sit, rng, "RB", 0.0), "RB"):
			mine_lo += 1
	assert_gt(mine_hi, mine_lo, "more trust, more touches")
	assert_eq(RtgPlay.audibles(book.plays, sit, "WR1", null).size(), 3)


func test_route_names_and_hot_routes() -> void:
	assert_eq(RtgPlay.route_name(RtgPlay.hot_route_path("GO", 10.0, 26.0), 1.0), "GO")
	assert_eq(RtgPlay.route_name(RtgPlay.hot_route_path("SLANT", 10.0, 26.0), 1.0), "SLANT")
	assert_eq(RtgPlay.route_name(RtgPlay.hot_route_path("OUT", 10.0, 26.0), 1.0), "OUT")
	assert_eq(RtgPlay.route_name(RtgPlay.hot_route_path("POST", 10.0, 26.0), 1.0), "POST")
	assert_eq(RtgPlay.route_name(RtgPlay.hot_route_path("CURL", 10.0, 26.0), 1.0, "sit"), "CURL")
	var slant := RtgPlay.hot_route_path("SLANT", 40.0, 26.0)
	assert_lt(slant[1].y, 0.0, "a receiver on the bottom side slants up, toward the ball")
	var base := {"type": "route", "path": PackedVector2Array([Vector2(5, 0)]), "delay": 0.3}
	var hot := RtgPlay.hot_assignment(base, "GO", 10.0, 26.0)
	assert_false(hot.has("delay"))
	assert_eq((base["path"] as PackedVector2Array).size(), 1, "the play's own assignment is untouched")


func test_tracker_grades() -> void:
	var t := RtgTracker.new("WR", "WR1")
	var g := t.record({"type": "tackle", "yards": 25, "pass_thrown": true, "carrier_slot": "WR1", "target_slot": "WR1",
			"broken_tackles": 1, "catch_x": 50.0, "spot_x": 60.0}, {"side": "offense"})
	assert_true(g["letter"].begins_with("A"))
	assert_eq(int(t.stats["yac"]), 10)
	g = t.record({"type": "incomplete", "yards": 0, "pass_thrown": true, "carrier_slot": "", "target_slot": "WR1",
			"drop": true}, {"side": "offense"})
	assert_eq(g["letter"], "F")
	assert_true(t.record({"type": "tackle", "yards": 4, "pass_thrown": false, "carrier_slot": "RB"}, {"side": "offense",
			"run_play": true}).is_empty(), "a run you didn't carry isn't graded")
	var cb := RtgTracker.new("CB", "CB1")
	g = cb.record({"type": "int", "yards": 0, "pass_thrown": true, "carrier_slot": "CB1", "target_slot": "WR1"}, {"side": "defense"})
	assert_eq(g["letter"], "A+")
	assert_eq(int(cb.stats["ints"]), 1)
	g = cb.record({"type": "td", "yards": 40, "pass_thrown": true, "carrier_slot": "WR1", "target_slot": "WR1",
			"cover_slot": "CB1"}, {"side": "defense"})
	assert_eq(g["letter"], "F")
