extends GutTest
## Instant replay: the runner records every tick of a play; the player puts the real agents
## back through those frames and ends on the last one.

const DT := 1.0 / 60.0

var runner: PlayRunner


func before_each() -> void:
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 4
	runner.human_team = -1
	runner.record_replay = true
	add_child_autofree(runner)


func _play_one() -> int:
	var off_book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	var def_book: PlaybookDef = load("res://data/plays/defense_playbook.tres")
	var ended := []
	runner.play_ended.connect(func(r: Dictionary) -> void: ended.append(r))
	runner.setup_play(off_book.plays[3], def_book.plays[2], 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	var steps := 0
	while ended.is_empty() and steps < 60 * 20:
		runner._physics_process(DT)
		steps += 1
	return steps


func test_frames_are_recorded_for_the_whole_play() -> void:
	var steps := _play_one()
	assert_gt(runner.replay_frames.size(), 60)
	assert_almost_eq(float(runner.replay_frames.size()), float(steps), 3.0, "one frame per tick")
	var per_frame := runner.agents.size() * PlayRunner.REPLAY_STRIDE + 4
	assert_eq(runner.replay_frames[0].size(), per_frame)


func test_a_new_play_clears_the_recording() -> void:
	_play_one()
	runner.setup_play(runner.off_play, runner.def_play, 35.0, FieldGeo.CENTER_Y, {}, {})
	assert_eq(runner.replay_frames.size(), 0)


func test_replay_puts_agents_back_where_they_were_and_finishes() -> void:
	_play_one()
	var frames := runner.replay_frames
	var last := frames[frames.size() - 1]
	var player := ReplayPlayer.new(runner, 0, 1.0)
	# Frame 0: everyone at their recorded starting spot.
	assert_almost_eq(runner.agents[0].field_pos.x, frames[0][0], 0.001)
	assert_almost_eq(runner.agents[0].field_pos.y, frames[0][1], 0.001)
	var done := false
	for i in frames.size() + 10:
		if player.step(DT):
			done = true
			break
	assert_true(done, "the replay ends")
	assert_almost_eq(runner.agents[0].field_pos.x, last[0], 0.001, "and rests on the final frame")
	assert_almost_eq(runner.ball.field_pos.x, last[runner.agents.size() * PlayRunner.REPLAY_STRIDE], 0.001)


func test_slow_motion_takes_longer() -> void:
	_play_one()
	var fast := ReplayPlayer.new(runner, 0, 1.0)
	var slow := ReplayPlayer.new(runner, 0, 0.5)
	var n_fast := 0
	while not fast.step(DT) and n_fast < 5000:
		n_fast += 1
	var n_slow := 0
	while not slow.step(DT) and n_slow < 5000:
		n_slow += 1
	assert_gt(n_slow, n_fast * 1.8)
