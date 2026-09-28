extends GutTest
## Phase 2: human defense (manual control + SWITCH, dive/jump/switch taps, human tackling),
## INT returns, fumbles, pace.

const DT := 1.0 / 60.0

var runner: PlayRunner
var touch: TouchInput
var dc: HumanDefenseControl
var off_book: PlaybookDef
var def_book: PlaybookDef
var ended: Array = []


func before_each() -> void:
	off_book = load("res://data/plays/offense_playbook.tres")
	def_book = load("res://data/plays/defense_playbook.tres")
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 11
	runner.human_team = PlayerAgent.Team.DEFENSE
	add_child_autofree(runner)
	touch = TouchInput.new()
	add_child_autofree(touch)
	dc = HumanDefenseControl.new()
	add_child_autofree(dc)
	dc.bind(runner, touch, runner.tuning)
	runner.human_input = dc
	ended = []
	runner.play_ended.connect(func(r: Dictionary) -> void: ended.append(r))


func _play(id: String) -> PlayDef:
	for p in off_book.plays:
		if p.id == id:
			return p
	for p in def_book.plays:
		if p.id == id:
			return p
	return null


func _setup(off_id: String, def_id: String) -> void:
	runner.setup_play(_play(off_id), _play(def_id), 35.0, FieldGeo.CENTER_Y, {}, {})


func _view(field_p: Vector2) -> Vector2:
	return dc.get_viewport().get_canvas_transform() * FieldProjection.to_screen(field_p)


func _step(n: int) -> void:
	for i in n:
		runner._physics_process(DT)
		dc.update(DT)


func test_human_gets_a_defender_at_the_snap() -> void:
	_setup("slants", "cover2")
	assert_not_null(runner.controlled)
	assert_eq(runner.controlled.team, PlayerAgent.Team.DEFENSE)
	assert_eq(runner.controlled.pos_code, "LB")


func test_switch_button_takes_the_defender_nearest_the_landing_spot() -> void:
	_setup("deep_shot", "cover3")
	runner.snap()
	_step(60)
	var before := runner.controlled
	var target := Vector2(runner.los_x + 25.0, 8.0)
	runner.throw_ball(target)
	_step(5)
	assert_eq(runner.controlled, before, "a throw never switches you automatically")
	dc.switch_to_ball()
	var ctrl := runner.controlled
	var best_t := INF
	for d in runner.defense:
		best_t = minf(best_t, d.field_pos.distance_to(runner.ball.to) / d.max_speed)
	assert_almost_eq(ctrl.field_pos.distance_to(runner.ball.to) / ctrl.max_speed, best_t, 0.4)


func test_switcher_prefers_pursuers_in_front_of_the_carrier() -> void:
	_setup("hb_dive", "cover2")
	runner.snap()
	_step(70)
	assert_eq(runner.carrier.slot, "RB")
	dc.switch_to_ball()
	var c := runner.carrier
	assert_gt(runner.controlled.field_pos.x, c.field_pos.x - 1.5, "never a defender trailing the play")


func test_tap_on_defender_switches_and_holds() -> void:
	_setup("slants", "cover2")
	runner.snap()
	_step(5)
	for slot in ["CB2", "S1"]:
		var d: PlayerAgent = runner.def_slots[slot]
		touch.tapped.emit(_view(d.field_pos))
		assert_eq(runner.controlled, d)
		_step(90)
		if runner.phase == PlayRunner.Phase.LIVE and runner.carrier != d:
			assert_eq(runner.controlled, d, "manual pick of %s holds until you switch" % slot)


func test_drag_moves_the_controlled_defender() -> void:
	_setup("slants", "cover2")
	runner.snap()
	var me := runner.controlled
	var start := Vector2(200, 150)
	touch.drag_started.emit(start, start + Vector2(0, -30))
	_step(30)
	assert_true(me.human)
	assert_lt(me.velocity.y, -1.0, "dragging up moves him toward the top sideline")
	touch.released.emit(start, start + Vector2(0, -30), true)
	assert_false(me.human, "letting go hands him back to his brain")


func test_tap_near_carrier_in_range_dives() -> void:
	_setup("hb_dive", "cover2")
	runner.snap()
	_step(70)
	var c := runner.carrier
	var me := runner.controlled
	me.field_pos = c.field_pos + Vector2(1.5, 0.0)
	touch.tapped.emit(_view(c.field_pos))
	assert_gt(me.dive_timer, 0.0)


func test_perfectly_timed_jump_can_intercept() -> void:
	var t := runner.tuning
	assert_gt(RatingModel.jump_int_prob(t, 0.0, 90, 70), 0.3)
	assert_eq(RatingModel.jump_int_prob(t, t.jump_good, 90, 70), 0.0)
	assert_eq(RatingModel.jump_deflect_prob(t, 0.0), 1.0)
	assert_eq(RatingModel.jump_deflect_prob(t, (t.jump_perfect + t.jump_good) * 0.5), t.jump_deflect_good)
	assert_eq(RatingModel.jump_deflect_prob(t, t.jump_good + 0.1), 0.0)


func test_jump_at_the_catch_point_resolves_the_pass() -> void:
	_setup("curls", "cover2")
	dc.switcher.manual(runner.def_slots["S1"])   # a deep defender, away from the rush
	runner.snap()
	_step(60)
	var me := runner.controlled
	var target := me.field_pos + Vector2(2.0, 0.0)
	runner.throw_ball(target)
	me.field_pos = runner.ball.to
	# Leap so the ball arrives at the top of the jump. (No human input here, so his brain
	# would wander off during a lofted ball's hang time: hold him on the spot.)
	while runner.ball.time_left() > runner.tuning.jump_time * 0.5:
		me.field_pos = runner.ball.to
		_step(1)
	runner.defender_jump(me)
	_step(120)   # the ball arrives, then the dead-ball pause
	assert_false(ended.is_empty() and runner.carrier != me, "the play resolved")
	if not ended.is_empty():
		assert_has(["incomplete", "int", "int_td"], ended[0]["type"])


func test_interception_is_returned_until_tackled() -> void:
	_setup("slants", "cover2")
	runner.human_team = -1
	runner.snap()
	_step(30)
	var d: PlayerAgent = runner.def_slots["S1"]
	runner._set_carrier(d)
	assert_eq(runner.phase, PlayRunner.Phase.LIVE, "an INT no longer ends the play at the catch")
	for i in 1200:
		runner._physics_process(DT)
		if not ended.is_empty():
			break
	assert_false(ended.is_empty())
	assert_has(["int", "int_td"], ended[0]["type"])
	assert_true(ended[0]["turnover"])


func test_pick_six_when_returner_reaches_the_end_zone() -> void:
	_setup("slants", "cover2")
	runner.human_team = -1
	runner.snap()
	var d: PlayerAgent = runner.def_slots["S1"]
	runner._set_carrier(d)
	d.field_pos = Vector2(FieldGeo.OWN_GOAL - 0.5, 20.0)
	runner._physics_process(DT)
	for i in 120:
		runner._physics_process(DT)
	assert_eq(ended[0]["type"], "int_td")


func test_fumble_probability_bounds() -> void:
	var t := runner.tuning
	var sure_hands := RatingModel.fumble_prob(t, 99, 60, 60)
	var butter := RatingModel.fumble_prob(t, 50, 95, 95)
	assert_lt(sure_hands, butter)
	assert_between(sure_hands, 0.002, 0.06)
	assert_between(butter, 0.002, 0.06)


func test_defense_pace_rules() -> void:
	var every := DefensePace.Pace.EVERY_SNAP
	var key := DefensePace.Pace.KEY_DOWNS
	var hi := DefensePace.Pace.HIGHLIGHTS
	var first_down_midfield := {"down": 1, "to_go": 10, "los_x": 50.0}
	assert_true(DefensePace.human_plays(every, first_down_midfield))
	assert_false(DefensePace.human_plays(key, first_down_midfield))
	assert_true(DefensePace.human_plays(key, {"down": 3, "to_go": 6, "los_x": 50.0}))
	assert_true(DefensePace.human_plays(key, {"down": 1, "to_go": 10, "los_x": 95.0}), "red zone")
	assert_true(DefensePace.human_plays(key, {"down": 1, "los_x": 40.0, "half_seconds_left": 90.0}))
	assert_false(DefensePace.human_plays(hi, {"down": 3, "to_go": 6, "los_x": 50.0}))
	assert_true(DefensePace.human_plays(hi, {"down": 4, "to_go": 2, "los_x": 50.0}))
	assert_eq(DefensePace.from_name("key"), key)
	assert_eq(DefensePace.from_name("nonsense"), every)


func test_no_automatic_switching_during_a_play() -> void:
	for pair in [["hb_dive", "cover2"], ["slants", "cover3"], ["screen", "cover1"], ["deep_shot", "cover2"]]:
		_setup(pair[0], pair[1])
		var mine := runner.controlled
		runner.snap()
		for i in 600:
			_step(1)
			if runner.phase != PlayRunner.Phase.LIVE:
				break
			if runner.carrier != null and runner.carrier.team == PlayerAgent.Team.DEFENSE:
				break   # an interception hands you the returner (the one allowed change)
			assert_eq(runner.controlled, mine, "%s: control stays on your man" % pair[0])
			if runner.controlled != mine:
				break


func test_presnap_tap_picks_a_defender_and_is_remembered() -> void:
	_setup("slants", "cover2")
	var readied := []
	dc.ready_tapped.connect(func() -> void: readied.append(true))
	var s1: PlayerAgent = runner.def_slots["S1"]
	touch.tapped.emit(_view(s1.field_pos))
	assert_eq(runner.controlled, s1, "tap on a defender pre-snap picks him")
	assert_true(readied.is_empty(), "…and does not snap")
	assert_eq(runner.phase, PlayRunner.Phase.PRE_SNAP)
	touch.tapped.emit(_view(Vector2(runner.los_x - 12.0, 3.0)))
	assert_eq(readied.size(), 1, "a tap away from the defenders = ready")
	# Next play (same call): the pick carries over.
	_setup("hb_dive", "cover2")
	dc.on_play_setup()
	assert_eq(runner.controlled.slot, "S1")


func test_switch_button_cycles_presnap() -> void:
	_setup("slants", "cover2")
	var first := runner.controlled
	dc.switch_to_ball()
	assert_ne(runner.controlled, first)
	assert_has(["LB", "S"], runner.controlled.pos_code)


## Your man wraps up from outside CPU tackle range and far more surely than a CPU defender.
func test_human_tackles_are_generous() -> void:
	var t := runner.tuning
	assert_gt(t.human_tackle_range, t.tackle_range)
	var made := 0
	var trials := 30
	for i in trials:
		runner.rng.seed = 100 + i
		_setup("hb_dive", "cover2")
		runner.snap()
		_step(70)
		var c := runner.carrier
		if c == null or c.team != PlayerAgent.Team.OFFENSE or runner.phase != PlayRunner.Phase.LIVE:
			trials -= 1
			continue
		var me := runner.controlled
		me.engaged_with = null
		me.tackle_cd = 0.0
		me.stun = 0.0
		me.field_pos = c.field_pos + Vector2(t.tackle_range + 0.25, 0.0)
		# Keep everyone else away so only your man can make this tackle.
		for d in runner.defense:
			if d != me:
				d.field_pos = Vector2(d.field_pos.x + 30.0, d.field_pos.y)
		runner.contact.resolve(0.0)
		if c.is_down:
			made += 1
	assert_gt(trials, 20)
	assert_gt(float(made) / trials, 0.8, "human wrap-ups succeed %d/%d" % [made, trials])


func test_human_tackle_chance_beats_cpu() -> void:
	var t := runner.tuning
	var cpu := RatingModel.tackle_prob(t, 65, 85, 70, false)
	assert_lt(cpu + t.human_tackle_bonus, 1.0)
	assert_gt(minf(cpu + t.human_tackle_bonus, t.human_tackle_max), cpu + 0.1)
