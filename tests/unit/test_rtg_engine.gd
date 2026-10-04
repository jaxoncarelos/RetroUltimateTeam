extends GutTest
## Road to Glory engine: the locked player (PlayRunner.lock_slot), RtgControl movement and
## moves, the CPU QB's favorite, catch timing, the corner's jam / telegraph.

const DT := 1.0 / 60.0

var runner: PlayRunner
var pad: RtgPad
var ctl: RtgControl
var ended: Array = []


func before_each() -> void:
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 777
	add_child_autofree(runner)
	pad = RtgPad.new()
	add_child_autofree(pad)
	ctl = RtgControl.new()
	add_child_autofree(ctl)
	ctl.bind(runner, pad, runner.tuning)
	ended = []
	runner.play_ended.connect(func(r: Dictionary) -> void: ended.append(r))


func _lineup(form: FormationDef, ovr: int) -> Dictionary:
	var out := {}
	for slot in form.slots:
		out[slot] = {"name": slot, "attrs": RatingModel.fill_attrs(form.slots[slot]["pos"], ovr)}
	return out


func _setup(off_id: String, def_id: String, side: int, slot: String) -> void:
	var off: PlayDef = load("res://data/plays/offense/%s.tres" % off_id)
	var def: PlayDef = load("res://data/plays/defense/%s.tres" % def_id)
	runner.human_team = side
	runner.lock_slot = slot
	runner.human_input = ctl
	runner.setup_play(off, def, 35.0, FieldGeo.CENTER_Y, _lineup(off.formation, 80), _lineup(def.formation, 78))
	ctl.on_play_setup()


func _step(seconds: float, passer: CpuPasser = null) -> void:
	for i in int(seconds / DT):
		if passer != null:
			passer.update(DT)
		runner._physics_process(DT)
		if not ended.is_empty():
			return


## Steps until the back has the ball (the handoff), so the tests act before contact.
func _until_handoff(rb: PlayerAgent) -> void:
	for i in 180:
		runner._physics_process(DT)
		if runner.carrier == rb:
			return


func test_locked_receiver_stays_yours_and_the_cpu_throws() -> void:
	_setup("slants", "cover3", PlayerAgent.Team.OFFENSE, "WR1")
	var wr: PlayerAgent = runner.off_slots["WR1"]
	assert_eq(runner.locked, wr)
	assert_eq(runner.controlled, wr)
	assert_false(runner.human_qb(), "the CPU throws when you are a receiver")
	runner.snap()
	var passer := CpuPasser.new(runner, runner.rng)
	passer.set_favorite(wr, 2.0)
	assert_eq(passer.progression[0], wr, "your man is read first")
	for i in 480:
		passer.update(DT)
		runner._physics_process(DT)
		if runner.pass_thrown:
			break
	assert_true(runner.pass_thrown, "the CPU QB threw")
	assert_eq(runner.controlled, wr, "control never moves to another receiver")
	_step(8.0)
	assert_false(ended.is_empty())


func test_cpu_qb_is_not_given_the_human_qb_protection() -> void:
	_setup("slants", "cover3", PlayerAgent.Team.OFFENSE, "WR1")
	runner.snap()
	assert_lt(runner.qb_immune_until, 0.0)


func test_running_back_gets_the_handoff_and_the_stick() -> void:
	_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "RB")
	var rb: PlayerAgent = runner.off_slots["RB"]
	runner.snap()
	_until_handoff(rb)
	assert_eq(runner.carrier, rb)
	assert_true(rb.human)
	var y0 := rb.field_pos.y
	pad.stick = Vector2(0.0, -1.0)   # straight up the screen
	_step(0.4)
	assert_lt(rb.field_pos.y, y0 - 1.0, "the stick moves him toward the top sideline")


func test_receiver_on_a_run_play_does_not_take_the_ball() -> void:
	_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "WR1")
	runner.snap()
	var rb: PlayerAgent = runner.off_slots["RB"]
	_until_handoff(rb)
	runner._physics_process(DT)
	assert_eq(runner.carrier, rb)
	assert_false(rb.human, "the back runs on his own")
	assert_true(rb.brain is RunnerBrain)
	assert_eq(runner.controlled, runner.off_slots["WR1"])


func test_plant_and_cut_turns_at_once() -> void:
	_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "RB")
	var rb: PlayerAgent = runner.off_slots["RB"]
	runner.snap()
	_until_handoff(rb)
	pad.stick = Vector2(1.0, 0.0)
	_step(0.25)
	var speed := rb.velocity.length()
	assert_gt(speed, 4.0)
	pad.stick = Vector2(0.0, 1.0)   # hard cut toward the bottom sideline
	runner._physics_process(DT)
	assert_gt(rb.velocity.normalized().y, 0.9, "the cut points him the new way immediately")
	assert_gt(rb.velocity.length(), speed * 0.4, "and keeps a share of his speed")


func test_juke_hops_sideways_and_eases_tackles() -> void:
	var t: GameplayTuning = load("res://data/tuning/gameplay_tuning.tres")
	var c := RatingModel.fill_attrs("RB", 85)
	var d := RatingModel.fill_attrs("LB", 75)
	for kind in ["juke", "spin", "stiff", "truck"]:
		var m := RatingModel.move_tackle_mult(t, kind, c, d)
		assert_lt(m, 1.0, kind)
		assert_gt(m, 0.1, kind)
	assert_lt(RatingModel.move_tackle_mult(t, "juke", RatingModel.fill_attrs("RB", 95), d),
			RatingModel.move_tackle_mult(t, "juke", RatingModel.fill_attrs("RB", 65), d), "better backs juke better")
	_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "RB")
	var rb: PlayerAgent = runner.off_slots["RB"]
	runner.snap()
	_until_handoff(rb)
	pad.stick = Vector2(1.0, 0.0)
	_step(0.15)
	pad.stick = Vector2(0.0, -0.5)
	ctl.press("juke")
	assert_eq(rb.move_kind, "juke")
	runner._physics_process(DT)
	assert_lt(rb.velocity.y, -5.0, "the juke goes the way the stick leans")


func test_power_picks_truck_head_on() -> void:
	_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "RB")
	var rb: PlayerAgent = runner.off_slots["RB"]
	runner.snap()
	_until_handoff(rb)
	var d: PlayerAgent = runner.def_slots["LB1"]
	d.field_pos = rb.field_pos + Vector2(2.0, 0.0)
	rb.velocity = Vector2(6.0, 0.0)
	ctl.press("power")
	assert_eq(rb.move_kind, "truck")
	assert_eq(runner.contact.move_against(rb, d), "truck")
	d.field_pos = rb.field_pos + Vector2(0.0, 1.5)
	assert_eq(runner.contact.move_against(rb, d), "", "a truck does nothing to a man at your side")


func test_buttons_follow_the_situation() -> void:
	_setup("slants", "cover3", PlayerAgent.Team.OFFENSE, "WR1")
	runner.snap()
	_step(0.5)
	var ids := ctl.buttons().map(func(b: Dictionary) -> String: return b["id"])
	assert_has(ids, "call")
	_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "RB")
	runner.snap()
	_until_handoff(runner.off_slots["RB"])
	ids = ctl.buttons().map(func(b: Dictionary) -> String: return b["id"])
	assert_eq(ids, ["juke", "burst", "spin", "power", "dive"])


func test_receiver_runs_his_route_by_hand() -> void:
	_setup("slants", "cover3", PlayerAgent.Team.OFFENSE, "WR1")
	var wr: PlayerAgent = runner.off_slots["WR1"]
	var x0 := wr.field_pos.x
	runner.snap()
	_step(0.6)
	assert_lt(absf(wr.field_pos.x - x0), 0.3, "no autopilot: without the stick he stays put")
	pad.stick = Vector2(1.0, 0.0)
	_step(0.5)
	assert_gt(wr.field_pos.x, x0 + 2.0, "the stick runs him")
	var p := runner.predict(wr, 0.5)
	assert_almost_eq(p.x, wr.field_pos.x + wr.velocity.x * 0.5, 0.5, "the QB reads where he is really going")
	pad.stick = Vector2.ZERO
	_step(0.6)
	assert_lt(wr.velocity.length(), 1.0, "let go and he pulls up")


func test_route_offset_measures_how_far_off_script() -> void:
	_setup("four_verts", "cover3", PlayerAgent.Team.OFFENSE, "WR1")
	var wr: PlayerAgent = runner.off_slots["WR1"]
	assert_almost_eq(runner.route_offset(wr), 0.0, 0.01, "at his alignment he is on it")
	wr.field_pos = wr.start_pos + Vector2(20.0, 0.0)
	assert_lt(runner.route_offset(wr), 1.5, "straight up the field on a go route")
	wr.field_pos = wr.start_pos + Vector2(10.0, 8.0)
	assert_gt(runner.route_offset(wr), 5.0, "drifting inside is off the route")


func test_high_point_catch_wins_contested_balls() -> void:
	var t: GameplayTuning = runner.tuning
	var caught := [0, 0]
	for aggressive in [false, true]:
		for i in 40:
			_setup("four_verts", "cover1", PlayerAgent.Team.OFFENSE, "WR1")
			runner.rng.seed = 500 + i
			var wr: PlayerAgent = runner.off_slots["WR1"]
			var cb: PlayerAgent = runner.def_slots["CB1"]
			runner.snap()
			ended.clear()
			wr.field_pos = Vector2(60.0, 10.0)
			cb.field_pos = Vector2(60.6, 10.4)   # draped on him
			runner.throw_ball(Vector2(60.3, 10.2))
			if aggressive:
				runner.play_time = 0.0
				runner.catch_pressed_at = 0.0
			while runner.ball.state == Ball.State.AIR and ended.is_empty():
				wr.stop()
				cb.stop()
				if aggressive:
					runner.catch_pressed_at = runner.play_time
				runner._physics_process(DT)
			if runner.carrier == wr:
				caught[int(aggressive)] += 1
	gut.p("contested catches: normal %d/40, high point %d/40" % caught)
	assert_gt(caught[1], caught[0] + 10, "tapping CATCH wins the jump ball")
	assert_gt(caught[1], 28)


func test_corner_jams_and_reads_breaks() -> void:
	_setup("slants", "press", PlayerAgent.Team.DEFENSE, "CB1")
	var cb: PlayerAgent = runner.def_slots["CB1"]
	assert_eq(runner.locked, cb)
	runner.snap()
	var wr: PlayerAgent = runner.off_slots["WR1"]
	wr.jam_timer = 0.0
	_step(0.1)
	ctl.press("jam")
	assert_gt(wr.jam_timer, 0.2, "the jam lands from press range")
	var saw := false
	for i in 120:
		runner._physics_process(DT)
		if ctl.tele_agent != null:
			saw = true
			break
	assert_true(saw, "the slant's break is telegraphed")


func test_corner_hands_off_to_ai_when_let_go() -> void:
	_setup("slants", "cover1", PlayerAgent.Team.DEFENSE, "CB1")
	var cb: PlayerAgent = runner.def_slots["CB1"]
	runner.snap()
	pad.stick = Vector2(-1.0, 0.0)
	_step(0.3)
	assert_true(cb.human)
	pad.stick = Vector2.ZERO
	_step(0.1)
	assert_false(cb.human, "his coverage AI takes over again")
	assert_true(cb.brain is ManCoverBrain or cb.brain is BallHawkBrain or cb.brain is PursuitBrain)


func test_aggressive_catch_window() -> void:
	_setup("slants", "cover3", PlayerAgent.Team.OFFENSE, "WR1")
	runner.snap()
	runner.play_time = 2.0
	runner.catch_pressed_at = 1.8
	assert_true(runner.aggressive_catch())
	runner.catch_pressed_at = 1.0
	assert_false(runner.aggressive_catch(), "too early")
	runner.catch_pressed_at = -2.0
	assert_false(runner.aggressive_catch(), "a spent early tap")


func test_result_carries_target_and_cover() -> void:
	_setup("slants", "cover1", PlayerAgent.Team.OFFENSE, "WR1")
	runner.snap()
	var passer := CpuPasser.new(runner, runner.rng)
	passer.set_favorite(runner.off_slots["WR1"], 3.0)
	_step(10.0, passer)
	assert_false(ended.is_empty())
	var r: Dictionary = ended[0]
	assert_true(r.has("target_slot"))
	assert_true(r.has("cover_slot"))
	if r["pass_thrown"]:
		assert_ne(r["target_slot"], "")


## A called run with you at QB: he hands it off at the mesh even while you push the stick
## (he used to run upfield and the ball "teleported" to the back seconds later).
func test_rtg_qb_hands_off_a_run_at_the_mesh() -> void:
	for stick in [Vector2.ZERO, Vector2(1.0, 0.0), Vector2(0.0, 1.0)]:
		_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "QB")
		var qb: PlayerAgent = runner.qb
		var rb: PlayerAgent = runner.off_slots["RB"]
		runner.snap()
		pad.stick = stick
		var gap := -1.0
		var qb_x := 0.0
		for i in 180:
			gap = qb.field_pos.distance_to(rb.field_pos)
			qb_x = qb.field_pos.x - runner.los_x
			runner._physics_process(DT)
			if runner.carrier == rb:
				break
		pad.stick = Vector2.ZERO
		assert_eq(runner.carrier, rb, "handed off (stick %s)" % stick)
		assert_lt(gap, runner.handoff_range + 0.5, "hand to hand, no teleport (stick %s)" % stick)
		assert_lt(qb_x, 0.5, "the QB never ran upfield with it (stick %s)" % stick)


## The back never got to the mesh: the QB keeps it instead of the ball flying across the field.
func test_failed_mesh_never_teleports_the_ball() -> void:
	_setup("hb_dive", "cover3", PlayerAgent.Team.OFFENSE, "QB")
	var rb: PlayerAgent = runner.off_slots["RB"]
	runner.snap()
	rb.field_pos += Vector2(0.0, 15.0)   # knocked far off his path
	rb.brain = IdleBrain.new(rb, runner)
	for i in 200:
		runner._physics_process(DT)
		if runner.carrier != runner.qb or runner.phase != PlayRunner.Phase.LIVE:
			break
	assert_ne(runner.carrier, rb, "no handoff across the field")
