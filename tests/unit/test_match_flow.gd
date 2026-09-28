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
	# Budget in frames, not wall time: one-time art baking at kickoff causes long first frames.
	var frames := 0
	while snaps < 14 and frames < 5000:
		await wait_frames(1)
		frames += 1
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


## II / Esc / Android back: pause → QUIT TO MENU → confirm (STAY goes back); never soft-locks.
func test_pause_menu_offers_quit_with_confirm() -> void:
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	m.config = {"home": "KC", "away": "PHI", "quarter_minutes": 1.5, "from_hub": true}
	add_child_autofree(m)
	assert_false(get_tree().quit_on_go_back, "Android back is handled by the match")
	var frames := 0
	while m.phase != MatchController.Phase.PLAY_CALL and frames < 2000:
		await wait_frames(1)
		frames += 1
	assert_eq(m.phase, MatchController.Phase.PLAY_CALL)
	m.hud.hide_choice()
	m.request_pause()
	assert_eq(m.phase, MatchController.Phase.PAUSED)
	var opts := m.pause_options()
	assert_eq(opts[-1], "QUIT TO MENU")
	assert_false("RESTART GAME" in opts, "hub games can't restart (only quit)")
	m._on_choice(opts.size() - 1)
	assert_true(m.hud.is_choice_open(), "leaving asks first")
	assert_eq(m._pause_menu, MatchController.PauseMenu.CONFIRM_QUIT)
	m._on_choice(0)   # STAY
	assert_eq(m._pause_menu, MatchController.PauseMenu.MAIN)
	assert_eq(m.phase, MatchController.Phase.PAUSED)
	m.request_pause()   # back again = resume
	assert_eq(m.phase, MatchController.Phase.PLAY_CALL)
	assert_true(m.runner.is_physics_processing())
	# Back during a result banner waits for the next play call instead of freezing it.
	m.phase = MatchController.Phase.RESULT
	m.request_pause()
	assert_eq(m.phase, MatchController.Phase.RESULT)
	assert_true(m._pause_queued)
