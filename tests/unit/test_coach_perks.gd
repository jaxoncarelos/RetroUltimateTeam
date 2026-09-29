extends GutTest
## Coach skill tree: points come from levels, perks cap out, respec refunds, perks change the
## match tuning and the economy, and ranks survive a save.

func _profile(level := 6) -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, GameData.db, "KC")
	p.coach["level"] = level
	return p


func test_points_come_from_levels() -> void:
	assert_eq(CoachPerks.points_earned(_profile(1)), 0)
	assert_eq(CoachPerks.available(_profile(6)), 5)


func test_buying_spends_points_and_caps_at_max() -> void:
	var p := _profile(50)
	for i in 10:
		CoachPerks.buy(p, "kicker")
	assert_eq(CoachPerks.rank(p, "kicker"), int(CoachPerks.find("kicker")["max"]))
	assert_eq(CoachPerks.available(p), 49 - int(CoachPerks.find("kicker")["max"]))
	assert_false(CoachPerks.can_buy(p, "kicker"))
	assert_false(CoachPerks.can_buy(_profile(1), "pocket"), "no points, no perk")


func test_respec_refunds_for_a_fee() -> void:
	var p := _profile(6)
	p.coins = 1000
	CoachPerks.buy(p, "pocket")
	CoachPerks.buy(p, "payday")
	assert_eq(CoachPerks.available(p), 3)
	assert_true(CoachPerks.respec(p))
	assert_eq(CoachPerks.available(p), 5)
	assert_eq(p.coins, 1000 - CoachPerks.RESPEC_COST)
	p.coins = 10
	CoachPerks.buy(p, "pocket")
	assert_false(CoachPerks.respec(p), "too poor to respec")


func test_perks_tune_the_match() -> void:
	var base: GameplayTuning = load("res://data/tuning/gameplay_tuning.tres")
	var p := _profile(20)
	assert_same(CoachPerks.apply_tuning(base, p), base, "no perks: the original resource")
	for id in ["pocket", "breaker", "focus", "hands", "feet", "kicker"]:
		CoachPerks.buy(p, id)
	var t := CoachPerks.apply_tuning(base, p)
	assert_gt(t.qb_free_time, base.qb_free_time)
	assert_gt(t.duel_window_time, base.duel_window_time)
	assert_gt(t.aim_assist_strength, base.aim_assist_strength)
	assert_gt(t.human_catch_bonus, base.human_catch_bonus)
	assert_gt(t.human_speed_mult, base.human_speed_mult)
	assert_lt(t.burst_cooldown, base.burst_cooldown)
	assert_gt(t.meter_zone_base, base.meter_zone_base)
	assert_eq(base.qb_free_time, load("res://data/tuning/gameplay_tuning.tres").qb_free_time, "the shared resource is untouched")


func test_payday_and_film_study_change_the_economy() -> void:
	var win := {"team": "KC", "opponent": "PHI", "pf": 30, "pa": 10, "tds": 3, "difficulty": 1, "mode": "quick",
			"box": {"pass_td": 2, "rush_td": 1}}
	var plain := _profile(20)
	var perked := _profile(20)
	for i in 5:
		CoachPerks.buy(perked, "payday")
	var a := EconomyRules.postgame(plain, GameData.db, win, 1790000000)
	var b := EconomyRules.postgame(perked, GameData.db, win, 1790000000)
	assert_gt(int(b["total"]), int(a["total"]))
	assert_true(b["items"].any(func(i: Dictionary) -> bool: return i["id"] == "payday"))
	var xp_plain := Collection.award_xp(_profile(20), GameData.db, true)
	assert_eq(CoachPerks.card_xp_mult(_profile(20)), 1.0)
	var film := _profile(20)
	for i in 5:
		CoachPerks.buy(film, "film")
	assert_almost_eq(CoachPerks.card_xp_mult(film), 1.5, 0.001)


func test_ranks_survive_a_save() -> void:
	var p := _profile(10)
	CoachPerks.buy(p, "feet")
	CoachPerks.buy(p, "feet")
	var q := Profile.from_dict(p.to_dict())
	assert_eq(CoachPerks.rank(q, "feet"), 2)
	assert_eq(CoachPerks.available(q), 7)
