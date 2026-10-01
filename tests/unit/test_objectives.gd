extends GutTest
## ObjectiveRules (dailies/weeklies/milestones), ProgressionRules (coach level), DailyRules
## (login streak) and the GameState stats they read.

const DAY := 86400
const T0 := 1790000000 + 12 * 3600

var db: RosterDB


func before_all() -> void:
	db = GameData.db


func _prof() -> Profile:
	var p := Profile.new()
	p.franchise_team = "KC"
	return p


# ---------------------------------------------------------------- objectives

func test_active_lists_three_dailies_three_weeklies_and_milestones() -> void:
	var p := _prof()
	var list := ObjectiveRules.active(p, T0)
	var kinds := {"daily": 0, "weekly": 0, "milestone": 0}
	for o in list:
		kinds[o["kind"]] += 1
		for k in ["id", "kind", "title", "desc", "reward", "progress", "target", "done", "claimed", "pack", "starter",
				"reward_text"]:
			assert_true(o.has(k), "%s has %s" % [o["id"], k])
		assert_gt(int(o["reward"]), 0, o["id"])
	assert_eq(kinds["daily"], ObjectiveRules.DAILY_COUNT)
	assert_eq(kinds["weekly"], ObjectiveRules.WEEKLY_COUNT)
	assert_gte(kinds["milestone"], 30)
	assert_eq(list[0]["kind"], "daily", "dailies first")
	var first_ms: Dictionary = ObjectiveRules.of_kind(p, "milestone", T0)[0]
	assert_true(first_ms["starter"], "the easy first-session objectives lead the milestones")
	var ids := {}
	for o in list:
		assert_false(ids.has(o["id"]), "unique id %s" % o["id"])
		ids[o["id"]] = true


func test_dailies_rotate_by_date_and_are_deterministic() -> void:
	var p := _prof()
	var a := ObjectiveRules.of_kind(p, "daily", T0).map(func(o: Dictionary) -> String: return o["id"])
	var b := ObjectiveRules.of_kind(p, "daily", T0 + 3600).map(func(o: Dictionary) -> String: return o["id"])
	assert_eq(a, b, "same day, same dailies")
	var sets := {}
	for d in 7:
		var ids := ObjectiveRules.of_kind(p, "daily", T0 + d * DAY).map(func(o: Dictionary) -> String: return o["id"])
		sets[str(ids)] = true
	assert_gt(sets.size(), 2, "dailies change from day to day")
	var w1 := ObjectiveRules.weeklies_for_week(100)
	var w2 := ObjectiveRules.weeklies_for_week(101)
	assert_eq(w1.size(), ObjectiveRules.WEEKLY_COUNT)
	assert_ne(str(w1) + str(w2), str(w1) + str(w1), "weeks differ (sanity)")


func test_record_match_progresses_and_claims_pay_once() -> void:
	var p := _prof()
	var box := {"won": true, "pf": 28, "pa": 7, "pass_comp": 14, "pass_td": 2, "rush_td": 2, "rush_yds": 120,
			"longest_pass": 45, "longest_run": 31, "def_sacks": 2, "def_ints": 0, "fg_made": 0}
	var done := ObjectiveRules.record_match(p, box, T0)
	for id in ["m_first_pass", "m_first_td", "m_first_win", "m_pass40", "m_run20", "m_rush100", "m_tds3",
			"m_sacks2", "m_sack", "m_blowout"]:
		assert_has(done, id)
	assert_does_not_have(done, "m_pass60")
	assert_does_not_have(done, "m_int")
	assert_eq(ObjectiveRules.claimable_count(p, T0), done.size())
	var coins := p.coins
	var got := ObjectiveRules.claim(p, "m_pass40", T0)
	assert_eq(got, ObjectiveRules.find(p, "m_pass40", T0)["reward"])
	assert_eq(p.coins, coins + got, "one claim's coach XP is below a level-up")
	assert_eq(ObjectiveRules.claim(p, "m_pass40", T0), 0, "claims only once")
	assert_eq(ObjectiveRules.claim(p, "m_pass60", T0), 0, "unfinished can't be claimed")
	assert_eq(ObjectiveRules.claim(p, "nope", T0), 0)
	# Milestones are lifetime: a second match doesn't re-complete them.
	var again := ObjectiveRules.record_match(p, box, T0 + 60)
	assert_does_not_have(again, "m_pass40")
	assert_true(ObjectiveRules.find(p, "m_pass40", T0)["claimed"])


func test_game_mode_uses_best_single_game_and_total_mode_sums() -> void:
	var p := _prof()
	ObjectiveRules.record_match(p, {"pf": 7, "pa": 10, "rush_yds": 60}, T0)
	ObjectiveRules.record_match(p, {"pf": 7, "pa": 10, "rush_yds": 60}, T0 + 60)
	var m := ObjectiveRules.find(p, "m_rush100", T0)
	assert_eq(m["progress"], 60, "best single game, not the sum")
	assert_false(m["done"])
	assert_eq(int(p.objectives["totals"]["rush_yds"]), 120)
	assert_eq(int(p.objectives["totals"]["games"]), 2)
	assert_eq(ObjectiveRules.find(p, "m_games10", T0)["progress"], 2)


func test_periodic_objectives_reset_when_the_day_changes() -> void:
	var p := _prof()
	var daily: Dictionary = ObjectiveRules.of_kind(p, "daily", T0)[0]
	var stat: String = daily["stat"]
	var box := {"pf": 50, "pa": 0, "won": true}
	box[stat] = 999
	if stat.begins_with("packs"):
		ObjectiveRules.record_event(p, stat, 999, T0)
	else:
		ObjectiveRules.record_match(p, box, T0)
	assert_true(ObjectiveRules.find(p, daily["id"], T0)["done"])
	# Next week (so the same id can't be re-picked with progress intact by chance).
	var later := T0 + 8 * DAY
	for o in ObjectiveRules.of_kind(p, "daily", later):
		assert_eq(o["progress"], 0, "fresh dailies start at zero: %s" % o["id"])
	for o in ObjectiveRules.of_kind(p, "weekly", later):
		assert_eq(o["progress"], 0, "fresh weeklies start at zero: %s" % o["id"])


func test_events_and_pack_rewards() -> void:
	var p := _prof()
	ObjectiveRules.record_event(p, "packs_gold", 1, T0)
	assert_true(ObjectiveRules.find(p, "m_gold_pack", T0)["done"])
	# A milestone with a pack reward queues the pack.
	for i in 25:
		ObjectiveRules.record_match(p, {"pf": 21, "pa": 3}, T0 + i)
	var d := ObjectiveRules.claim_details(p, "m_wins25", T0)
	assert_gt(int(d["coins"]), 0)
	assert_eq(d["pack"], "gold")
	assert_has(p.pending_packs, "gold")
	# Best-value stats.
	ObjectiveRules.record_best(p, "team_ovr", 81, T0)
	assert_true(ObjectiveRules.find(p, "m_team80", T0)["done"])
	assert_false(ObjectiveRules.find(p, "m_team85", T0)["done"])
	var all := ObjectiveRules.claim_all(p, T0)
	assert_gt(all["ids"].size(), 3)
	assert_eq(ObjectiveRules.claimable_count(p, T0), 0)


func test_forfeit_counts_only_as_a_game() -> void:
	var p := _prof()
	var done := ObjectiveRules.record_match(p, {"forfeit": true, "pf": 0, "pa": 0, "pass_comp": 5}, T0)
	assert_does_not_have(done, "m_first_pass")
	assert_eq(int(p.objectives["totals"]["games"]), 1)


func test_objective_state_survives_save() -> void:
	var p := _prof()
	ObjectiveRules.record_match(p, {"pf": 21, "pa": 3, "pass_comp": 3}, T0)
	ObjectiveRules.claim(p, "m_first_win", T0)
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(ObjectiveRules.find(back, "m_first_win", T0)["claimed"])
	assert_true(ObjectiveRules.find(back, "m_first_pass", T0)["done"])
	assert_eq(ObjectiveRules.claim(back, "m_first_win", T0), 0)


# ---------------------------------------------------------------- coach level

func test_coach_levels_and_rewards() -> void:
	assert_eq(ProgressionRules.level_from_xp(0), 1)
	assert_eq(ProgressionRules.level_from_xp(ProgressionRules.xp_to_next(1) - 1), 1)
	assert_eq(ProgressionRules.level_from_xp(ProgressionRules.xp_to_next(1)), 2)
	assert_eq(ProgressionRules.level_from_xp(99999999), ProgressionRules.MAX_LEVEL)
	for lv in range(2, ProgressionRules.MAX_LEVEL + 1):
		assert_eq(ProgressionRules.level_from_xp(ProgressionRules.xp_for_level(lv)), lv)
		assert_gt(int(ProgressionRules.rewards_for_level(lv)["coins"]), 0, "every level pays")
	assert_eq(ProgressionRules.rewards_for_level(10)["pack"], "gold")
	assert_eq(ProgressionRules.rewards_for_level(25)["pack"], "silver", "elite packs are earned, not handed out")
	assert_eq(ProgressionRules.rewards_for_level(50)["pack"], "elite")
	var pr := ProgressionRules.level_progress(ProgressionRules.xp_for_level(3) + 10)
	assert_eq(pr["level"], 3)
	assert_eq(pr["into"], 10)
	assert_almost_eq(float(pr["frac"]), 10.0 / ProgressionRules.xp_to_next(3), 0.0001)


func test_add_xp_pays_every_level_crossed() -> void:
	var p := _prof()
	var coins := p.coins
	var ups := ProgressionRules.add_xp(p, ProgressionRules.xp_for_level(10))
	assert_eq(ups.size(), 9)
	assert_eq(int(p.coach["level"]), 10)
	var expect := 0
	for lv in range(2, 11):
		expect += int(ProgressionRules.rewards_for_level(lv)["coins"])
	assert_eq(p.coins, coins + expect)
	assert_has(p.pending_packs, "gold", "level 10 gold pack queued")
	assert_eq(ProgressionRules.add_xp(p, 0), [] as Array[Dictionary])


func test_match_xp_breakdown() -> void:
	var win := ProgressionRules.xp_for_match({"tds": 3, "def_sacks": 2, "def_ints": 1, "pf": 21, "pa": 7}, true)
	assert_eq(win["total"], ProgressionRules.XP_PLAYED + ProgressionRules.XP_WIN + 3 * ProgressionRules.XP_PER_TD
			+ 3 * ProgressionRules.XP_PER_TAKEAWAY)
	var ids: Array = win["items"].map(func(i: Dictionary) -> String: return i["id"])
	assert_eq(ids, ["played", "win", "tds", "defense"])
	var loss := ProgressionRules.xp_for_match({"pf": 3, "pa": 7}, false)
	assert_eq(loss["total"], ProgressionRules.XP_PLAYED)


# ---------------------------------------------------------------- daily login

func test_login_streak_escalates_and_resets() -> void:
	var p := _prof()
	var coins := p.coins
	var r1 := DailyRules.check_in(p, T0)
	assert_eq(r1["day"], 1)
	assert_false(r1["already_claimed"])
	assert_eq(p.coins, coins + int(DailyRules.REWARDS[0]["coins"]))
	var again := DailyRules.check_in(p, T0 + 3600)
	assert_true(again["already_claimed"])
	assert_eq(p.coins, coins + int(DailyRules.REWARDS[0]["coins"]), "no double pay")
	for d in range(2, 8):
		var r := DailyRules.check_in(p, T0 + (d - 1) * DAY)
		assert_eq(r["day"], d)
	assert_has(p.pending_packs, "gold", "day 7 = gold pack")
	var cal := DailyRules.calendar(p, T0 + 6 * DAY)
	assert_eq(cal.size(), 7)
	assert_true(cal[6]["today"])
	assert_true(cal[0]["claimed"])
	assert_eq(DailyRules.check_in(p, T0 + 7 * DAY)["day"], 1, "the cycle repeats after day 7")
	assert_eq(DailyRules.check_in(p, T0 + 8 * DAY)["day"], 2)
	# Missing a day resets the streak.
	assert_eq(DailyRules.check_in(p, T0 + 10 * DAY)["day"], 1)
	assert_eq(int(p.login["streak"]), 1)


# ---------------------------------------------------------------- game stats

func _r(type: String, spot_x: float, yards: int, thrown := true) -> Dictionary:
	return {"type": type, "spot_x": spot_x, "spot_y": 26.0, "yards": yards, "turnover": type in ["int", "int_td", "fumble"],
			"pass_thrown": thrown}


func test_game_state_tracks_longest_plays_fg_and_box_score() -> void:
	var g := GameState.new("KC", "PHI", 150.0)
	g.start_possession("KC", 35.0)
	g.apply_result(_r("tackle", 77.0, 42), false, 900.0)
	g.apply_result(_r("tackle", 80.0, 3, false), true, 900.0)
	g.apply_result(_r("tackle", 102.0, 22, false), true, 900.0)
	g.apply_result(_r("tackle", 108.0, 6), false, 900.0)
	assert_eq(g.stats["KC"]["long_pass"], 42)
	assert_eq(g.stats["KC"]["long_run"], 22)
	g.record_field_goal("KC", true, 51.4)
	g.record_field_goal("KC", false, 58.0)
	assert_eq(g.stats["KC"]["fg_made"], 1)
	assert_eq(g.stats["KC"]["fg_att"], 2)
	assert_eq(g.stats["KC"]["fg_long"], 51)
	g.add_points("KC", 3)
	g.start_possession("PHI", 35.0)
	g.apply_result(_r("int_td", 8.0, 0), false, 900.0)
	var box := g.box_score("KC")
	assert_eq(box["def_pick6"], 1)
	assert_eq(box["def_ints"], 1)
	assert_eq(box["pf"], 9)
	assert_eq(box["longest_pass"], 42)
	var done := ObjectiveRules.record_match(_prof(), box, T0)
	assert_has(done, "m_fg50")
	assert_has(done, "m_pick6")
	assert_has(done, "m_pass40")
