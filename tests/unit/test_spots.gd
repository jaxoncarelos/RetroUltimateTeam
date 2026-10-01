extends GutTest
## Dead-ball spots match what the player sees: the spot is where the ball visibly rests
## (no hidden fall-forward yards), "yards" (the GAIN OF N banner) is exactly the change in
## the line of scrimmage, and a runner downed short of the goal line is never a touchdown.

const DT := 1.0 / 60.0

var runner: PlayRunner
var off_book: PlaybookDef
var def_book: PlaybookDef
var ended: Array = []


func before_each() -> void:
	off_book = load("res://data/plays/offense_playbook.tres")
	def_book = load("res://data/plays/defense_playbook.tres")
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.human_team = -1
	add_child_autofree(runner)
	ended = []
	runner.play_ended.connect(func(r: Dictionary) -> void: ended.append(r))


func _play(id: String) -> PlayDef:
	for p in off_book.plays + def_book.plays:
		if p.id == id:
			return p
	return null


## Runs a play to the whistle; returns [result, ball x when play_ended fired].
func _run(off: PlayDef, def: PlayDef, los: float) -> Array:
	ended.clear()
	runner.setup_play(off, def, los, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	var passer := CpuPasser.new(runner, runner.rng) if not off.is_run() else null
	for i in int(20.0 / DT):
		if passer != null:
			passer.update(DT)
		runner._physics_process(DT)
		if not ended.is_empty():
			return [ended[0], runner.ball.field_pos.x]
	return []


func test_spot_is_the_visible_ball_and_banner_yards_are_the_los_change() -> void:
	var checked := 0
	var seed := 1
	for off_id in ["hb_dive", "hb_sweep", "toss", "counter", "slants", "mesh", "curls", "screen"]:
		for def_id in ["cover2", "cover3", "cover1", "lb_blitz"]:
			seed += 1
			runner.rng.seed = seed
			var out := _run(_play(off_id), _play(def_id), 35.0)
			if out.is_empty():
				continue
			var r: Dictionary = out[0]
			var ball_x: float = out[1]
			if r["type"] not in ["tackle", "out", "sack"]:
				continue
			checked += 1
			assert_almost_eq(float(r["spot_x"]), ball_x, 0.5,
					"%s vs %s: spot %.2f vs visible ball %.2f" % [off_id, def_id, r["spot_x"], ball_x])
			var downs := DownTracker.new()
			downs.start_drive(35.0)
			var before := downs.los_x
			downs.apply_spot(r["spot_x"])
			assert_eq(int(r["yards"]), int(downs.los_x - before), "%s: GAIN OF N = LOS change" % off_id)
			# The new LOS marker sits on the ball (whole-yard spot).
			assert_almost_eq(downs.los_x, ball_x, 0.5 + 0.01)
	assert_gt(checked, 15, "enough downed plays were checked")


func test_tackle_slide_is_visible_not_hidden_yards() -> void:
	runner.rng.seed = 3
	runner.setup_play(_play("hb_dive"), _play("cover2"), 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 90:
		runner._physics_process(DT)
		if runner.carrier != null and runner.carrier != runner.qb:
			break
	var c := runner.carrier
	c.velocity = Vector2(8.0, 0.0)
	var d := runner.defense[0]
	var at := c.field_pos.x
	runner.on_tackle(d, c)
	var slide := runner.fall_forward(c)
	assert_between(c.velocity.x, 0.1, 99.0, "he falls forward on the hit")
	for i in 90:
		c.step(DT, runner.tuning)
	assert_almost_eq(c.field_pos.x - at, slide, 0.25, "the body slides exactly the fall-forward yards")
	assert_lte(slide, runner.tuning.fall_slide_max)


func test_spot_is_contact_point_not_end_of_slide() -> void:
	runner.rng.seed = 3
	runner.setup_play(_play("hb_dive"), _play("cover2"), 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 90:
		runner._physics_process(DT)
		if runner.carrier != null and runner.carrier != runner.qb:
			break
	var c := runner.carrier
	c.field_pos = Vector2(50.0, c.field_pos.y)
	c.velocity = Vector2(9.0, 0.0)
	var contact_ball_x := 50.0 + c.facing * Ball.HOLD_AHEAD
	runner.on_tackle(runner.defense[0], c)
	for i in 240:
		runner._physics_process(DT)
		if not ended.is_empty():
			break
	for i in 60:
		runner._physics_process(DT)
	assert_false(ended.is_empty())
	var r: Dictionary = ended[0]
	assert_eq(r["type"], "tackle")
	assert_almost_eq(float(r["spot_x"]), contact_ball_x, 0.5 + runner.tuning.fall_forward_max)
	assert_lte(c.field_pos.x - 50.0, runner.tuning.fall_slide_max + 0.3, "the body only stumbles a little past the contact point")


func test_downed_at_the_one_is_not_a_touchdown() -> void:
	runner.rng.seed = 5
	var los := FieldGeo.OPP_GOAL - 3.0
	runner.setup_play(_play("hb_dive"), _play("goal_line") if _play("goal_line") != null else _play("cover2"),
			los, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 120:
		runner._physics_process(DT)
		if runner.carrier != null and runner.carrier != runner.qb:
			break
	var c := runner.carrier
	# Hit at full speed half a yard short of the plane: the slide stops short of the line.
	c.field_pos = Vector2(FieldGeo.OPP_GOAL - 0.9, c.field_pos.y)
	c.velocity = Vector2(9.0, 0.0)
	runner.on_tackle(runner.defense[0], c)
	for i in 200:
		runner._physics_process(DT)
		if not ended.is_empty():
			break
	assert_false(ended.is_empty())
	var r: Dictionary = ended[0]
	assert_eq(r["type"], "tackle")
	assert_lt(runner.ball.field_pos.x, FieldGeo.OPP_GOAL, "the ball rests short of the goal line")
	var downs := DownTracker.new()
	downs.start_drive(los)
	assert_ne(downs.apply_spot(r["spot_x"]), DownTracker.Outcome.TOUCHDOWN)
	assert_eq(int(r["yards"]), int(downs.los_x - los))


func test_spot_yard_matches_down_tracker() -> void:
	assert_eq(DownTracker.spot_yard(43.49), 43.0)
	assert_eq(DownTracker.spot_yard(43.5), 44.0)
	assert_eq(DownTracker.spot_yard(109.7), FieldGeo.OPP_GOAL - 1.0, "never rounded into the end zone")


func _carry_to(pos: Vector2, vel: Vector2) -> PlayerAgent:
	runner.rng.seed = 3
	runner.setup_play(_play("hb_dive"), _play("cover2"), 100.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 120:
		runner._physics_process(DT)
		if runner.carrier != null and runner.carrier != runner.qb:
			break
	var c := runner.carrier
	c.field_pos = pos
	c.velocity = vel
	runner._prev_carrier = null
	runner._check_carrier()   # records the previous in-bounds position
	return c


func test_leaving_the_field_before_the_goal_plane_is_no_touchdown() -> void:
	# One frame: in bounds short of the goal -> out of bounds and past the goal line.
	var c := _carry_to(Vector2(FieldGeo.OPP_GOAL - 0.3, 0.2), Vector2.ZERO)
	c.field_pos = Vector2(FieldGeo.OPP_GOAL + 0.4, -0.3)
	runner._check_carrier()
	assert_eq(runner._pending_result.get("type", ""), "out", "stepped out first: no points")


func test_crossing_the_goal_plane_in_bounds_scores_with_scorer_and_yards() -> void:
	var c := _carry_to(Vector2(FieldGeo.OPP_GOAL - 0.3, 0.4), Vector2.ZERO)
	c.display_name = "Tyreek Hill"
	c.field_pos = Vector2(FieldGeo.OPP_GOAL + 0.4, -0.05)   # goal plane crossed first, then out
	runner._check_carrier()
	var r: Dictionary = runner._pending_result
	assert_eq(r.get("type", ""), "td")
	assert_eq(r.get("scorer", ""), "Tyreek Hill")
	assert_eq(r.get("td_yards", -1), int(FieldGeo.OPP_GOAL - 100.0))
