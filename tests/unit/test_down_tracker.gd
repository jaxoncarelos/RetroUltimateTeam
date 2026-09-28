extends GutTest

var dt: DownTracker


func before_each() -> void:
	dt = DownTracker.new()
	dt.start_drive(35.0)


func test_start_drive() -> void:
	assert_eq(dt.down, 1)
	assert_eq(dt.to_go(), 10)
	assert_eq(dt.down_text(), "1ST & 10")


func test_short_gain_advances_down() -> void:
	assert_eq(dt.apply_spot(39.0), DownTracker.Outcome.NEXT_DOWN)
	assert_eq(dt.down, 2)
	assert_eq(dt.to_go(), 6)


func test_first_down_resets_chains() -> void:
	assert_eq(dt.apply_spot(46.0), DownTracker.Outcome.FIRST_DOWN)
	assert_eq(dt.down, 1)
	assert_eq(dt.first_down_x, 56.0)


func test_exact_line_to_gain_is_first_down() -> void:
	assert_eq(dt.apply_spot(45.0), DownTracker.Outcome.FIRST_DOWN)


func test_spots_round_to_whole_yards() -> void:
	dt.apply_spot(38.4)
	assert_eq(dt.los_x, 38.0)
	assert_eq(dt.to_go(), 7)


func test_turnover_on_downs() -> void:
	dt.apply_spot(36.0)
	dt.apply_spot(37.0)
	dt.apply_spot(38.0)
	assert_eq(dt.down, 4)
	assert_eq(dt.apply_spot(39.0), DownTracker.Outcome.TURNOVER_ON_DOWNS)


func test_touchdown_needs_the_play_to_score() -> void:
	assert_eq(dt.apply_spot(110.0, true), DownTracker.Outcome.TOUCHDOWN)


func test_tackled_short_of_goal_line_is_not_a_touchdown() -> void:
	dt.start_drive(105.0)
	# Downed half a yard short (and even a spot that rounds/falls into the end zone) stays at the 1.
	assert_ne(dt.apply_spot(109.6), DownTracker.Outcome.TOUCHDOWN)
	assert_eq(dt.los_x, 109.0)
	assert_ne(dt.apply_spot(110.4), DownTracker.Outcome.TOUCHDOWN)
	assert_eq(dt.los_x, 109.0)


func test_touchdown_flag() -> void:
	assert_eq(dt.apply_spot(60.0, true), DownTracker.Outcome.TOUCHDOWN)


func test_safety_in_own_end_zone() -> void:
	dt.start_drive(12.0)
	assert_eq(dt.apply_spot(9.0), DownTracker.Outcome.SAFETY)


func test_goal_to_go() -> void:
	dt.start_drive(104.0)
	assert_true(dt.is_goal_to_go())
	assert_eq(dt.down_text(), "1ST & GOAL")


func test_incomplete_keeps_spot_and_counts_down() -> void:
	dt.apply_spot(dt.los_x)
	assert_eq(dt.down, 2)
	assert_eq(dt.los_x, 35.0)
	assert_eq(dt.plays, 1)
