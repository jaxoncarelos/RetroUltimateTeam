extends GutTest

var t: GameplayTuning


func before_each() -> void:
	t = load("res://data/tuning/gameplay_tuning.tres")


func test_speed_increases_with_rating() -> void:
	assert_gt(RatingModel.max_speed(t, 95), RatingModel.max_speed(t, 70))


func test_reaction_faster_with_awareness() -> void:
	assert_lt(RatingModel.reaction_delay(t, 99), RatingModel.reaction_delay(t, 60))
	assert_almost_eq(RatingModel.reaction_delay(t, 99), t.reaction_fast, 0.001)
	assert_almost_eq(RatingModel.reaction_delay(t, 40), t.reaction_slow, 0.001)


func test_throw_power_extends_range() -> void:
	assert_gt(RatingModel.max_throw_distance(t, 99), RatingModel.max_throw_distance(t, 60))


func test_deep_throws_are_lobbed() -> void:
	var short := RatingModel.throw_arc(t, 85, 8.0)
	var deep := RatingModel.throw_arc(t, 85, 40.0)
	assert_gt(deep.y, short.y * 3.0, "deep apex should be much higher")
	assert_gt(deep.x, short.x)


func test_accuracy_and_pressure_affect_aim_error() -> void:
	var clean_good := RatingModel.aim_error(t, 95, 90, 20.0, 0.0)
	var clean_bad := RatingModel.aim_error(t, 60, 90, 20.0, 0.0)
	var pressured := RatingModel.aim_error(t, 95, 90, 20.0, 1.0)
	assert_lt(clean_good, clean_bad)
	assert_gt(pressured, clean_good)


func test_contest_lowers_catch_probability() -> void:
	var open := RatingModel.catch_prob(t, 90, 0.0, 80)
	var covered := RatingModel.catch_prob(t, 90, 1.0, 80)
	assert_gt(open, 0.9)
	assert_lt(covered, open)


func test_tackle_probability_bounds_and_juke() -> void:
	var even := RatingModel.tackle_prob(t, 80, 80, 80, false)
	var juked := RatingModel.tackle_prob(t, 80, 80, 80, true)
	assert_between(even, t.tackle_min, t.tackle_max)
	assert_lt(juked, even)
	assert_gt(RatingModel.tackle_prob(t, 95, 60, 60, false), RatingModel.tackle_prob(t, 60, 95, 90, false))


func test_better_blocker_holds_longer() -> void:
	assert_gt(RatingModel.shed_time(t, 95, 70, 0.0), RatingModel.shed_time(t, 70, 95, 0.0))
	assert_gte(RatingModel.shed_time(t, 40, 99, -1.0), t.shed_min)


func test_fill_attrs_uses_profile_and_explicit_values() -> void:
	var qb := RatingModel.fill_attrs("QB", 90, {"spd": 88})
	assert_eq(qb["spd"], 88, "explicit value wins")
	assert_eq(qb["thp"], 90, "profile offset 0")
	assert_eq(qb.size(), RatingModel.ATTRS.size())
	for a in qb:
		assert_between(qb[a], 25, 99)
