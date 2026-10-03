extends GutTest
## Road to Glory matches end to end (real timers): you only play your side of the ball, the
## coordinators call the plays, your stat line and grades are tracked.


func before_all() -> void:
	SaveManager.disabled = true
	Settings.tutorial_done = true


func after_all() -> void:
	Engine.time_scale = 1.0


func _rtg_config(pos: String) -> Dictionary:
	var r := RtgRules.debug_match_rtg(pos)
	return {"home": "KC", "away": "PHI", "quarter_minutes": 1.5, "rtg": r}


## Plays `n` snaps (READY / SNAP pressed for you, the AI plays your player). Returns snaps.
func _play(m: MatchController, n: int, possessions: Dictionary) -> int:
	var snaps := 0
	var frames := 0
	while snaps < n and frames < 12000:
		await wait_frames(1)
		frames += 1
		if m.phase == MatchController.Phase.FINAL:
			break
		if m.phase == MatchController.Phase.PLAY_CALL and not m.hud.tip_open() and not m.hud.is_choice_open():
			possessions[m.gs.possession] = true
			m._snap()
			snaps += 1
		elif m.phase == MatchController.Phase.LIVE and m._human_offense() and m.runner.qb_is_passer() \
				and m.runner.human_qb() and m.runner.play_time > 1.2:
			var read := QBReadLogic.best_throw(m.runner)
			if not read.is_empty():
				m.runner.throw_ball(read["target"])
		elif m.phase == MatchController.Phase.PAT_CHOICE:
			m._on_choice(0)
		elif m.phase == MatchController.Phase.KICK_METER:
			m.hud.kick_meter.stop_and_kick()
		elif m.hud.is_choice_open() and m.phase == MatchController.Phase.BREAK:
			m._on_choice(0)
	return snaps


func test_receiver_plays_only_offense_and_gets_targets() -> void:
	Engine.time_scale = 6.0
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	m.config = _rtg_config("WR")
	add_child_autofree(m)
	assert_true(m._coach_calls())
	assert_eq(m.runner.lock_slot, "WR1")
	assert_false(m.ocontrol.enabled, "the classic gestures are off for a receiver")
	var poss := {}
	var snaps: int = await _play(m, 16, poss)
	assert_gte(snaps, 12)
	assert_eq(poss.keys(), ["KC"], "a receiver only plays offense")
	var st: Dictionary = m.rtg_track.stats
	gut.p("WR line: %s  grade %s  (%d graded)" % [RtgTracker.line_text("WR", st), m.rtg_track.game_letter(), m.rtg_track.grades.size()])
	assert_gt(int(st["targets"]), 0, "the QB looks your way")
	var res := m.match_result()
	assert_true(res.has("rtg"))
	assert_eq(res["rtg"]["pos"], "WR")


func test_running_back_carries_it() -> void:
	Engine.time_scale = 6.0
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	m.config = _rtg_config("RB")
	add_child_autofree(m)
	var poss := {}
	await _play(m, 16, poss)
	var st: Dictionary = m.rtg_track.stats
	gut.p("RB line: %s  grade %s" % [RtgTracker.line_text("RB", st), m.rtg_track.game_letter()])
	assert_gt(int(st["rush_att"]), 2, "the OC feeds the back")


func test_corner_plays_only_defense() -> void:
	Engine.time_scale = 6.0
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	m.config = _rtg_config("CB")
	add_child_autofree(m)
	assert_eq(m.runner.lock_slot, "CB1")
	var poss := {}
	var snaps: int = await _play(m, 14, poss)
	assert_gte(snaps, 10)
	assert_eq(poss.keys(), ["PHI"], "a corner only plays defense; his offense is simulated")
	gut.p("CB line: %s  grade %s" % [RtgTracker.line_text("CB", m.rtg_track.stats), m.rtg_track.game_letter()])


func test_quarterback_calls_his_own_plays() -> void:
	Engine.time_scale = 6.0
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	m.config = _rtg_config("QB")
	add_child_autofree(m)
	assert_false(m._coach_calls())
	assert_true(m.ocontrol.enabled and m.ocontrol.aim_only)
	var poss := {}
	await _play(m, 10, poss)
	var st: Dictionary = m.rtg_track.stats
	gut.p("QB line: %s  grade %s" % [RtgTracker.line_text("QB", st), m.rtg_track.game_letter()])
	assert_gt(int(st["pass_att"]) + int(st["sacked"]) + int(st["rush_att"]), 0)


func test_leaving_sims_the_rest() -> void:
	var m: MatchController = load("res://scenes/match/match.tscn").instantiate()
	var cfg := _rtg_config("WR")
	cfg["from_hub"] = true
	m.config = cfg
	add_child_autofree(m)
	var frames := 0
	while m.phase != MatchController.Phase.PLAY_CALL and frames < 2000:
		await wait_frames(1)
		frames += 1
	m._sim_rest_of_game()
	assert_eq(m.phase, MatchController.Phase.FINAL)
	assert_gt(m.rtg_track.grades.size(), 0, "the simmed rest still counts toward your grade")
