extends GutTest
## Integration: a human-controlled match driven through its real timers and signals.
## The human throws to the CPU read's best target on offense and just watches on defense.


func before_all() -> void:
	SaveManager.disabled = true
	Settings.tutorial_done = true


func after_all() -> void:
	Engine.time_scale = 1.0


func test_human_match_runs_through_many_plays() -> void:
	Engine.time_scale = 6.0
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	m.config = {"home": "KC", "away": "PHI", "quarter_minutes": 1.5}
	add_child_autofree(m)
	assert_eq(m.human, "KC")
	var snaps := 0
	var possessions := {}
	var t := 0.0
	while snaps < 14 and t < 120.0:
		await wait_frames(1)
		t += get_process_delta_time() * Engine.time_scale
		if m.phase == MatchController.Phase.PLAY_CALL and not m.hud.tip_open():
			possessions[m.gs.possession] = true
			m._snap()
			snaps += 1
		elif m.phase == MatchController.Phase.LIVE and m._human_offense() and m.runner.qb_is_passer() \
				and m.runner.play_time > 1.2:
			var read := QBReadLogic.best_throw(m.runner)
			if not read.is_empty():
				m.runner.throw_ball(read["target"])
		elif m.phase == MatchController.Phase.PAT_CHOICE:
			m._on_choice(1)   # go for two
		elif m.phase == MatchController.Phase.KICK_METER:
			m.hud.kick_meter.stop_and_kick()
	assert_gte(snaps, 14, "the match kept moving")
	assert_true(m.gs.clock.seconds_left < GameClock.QUARTER or m.gs.clock.quarter > 1, "the clock ran")
	gut.p("snaps %d, possessions %s, score %s, clock %s" % [snaps, possessions.keys(), m.gs.score, m.gs.clock.label()])
