extends GutTest
## The offense gestures must only act while the human is on offense.

var runner: PlayRunner
var input: TouchInput
var control: HumanOffenseControl


func before_each() -> void:
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 7
	add_child_autofree(runner)
	input = autofree(TouchInput.new())
	control = HumanOffenseControl.new()
	add_child_autofree(control)
	control.bind(runner, input, runner.tuning)


func _start_pass_play(human_team: int) -> void:
	var off_book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	var def_book: PlaybookDef = load("res://data/plays/defense_playbook.tres")
	var pass_play: PlayDef = null
	for p in off_book.plays:
		if not p.is_run():
			pass_play = p
			break
	runner.human_team = human_team
	runner.setup_play(pass_play, def_book.plays[0], 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()


func _slingshot() -> void:
	var start := Vector2(300, 150)
	var end := Vector2(220, 150)
	input.drag_started.emit(start, start + Vector2(-10, 0))
	input.dragged.emit(start, end)
	input.released.emit(start, end, true)


func test_human_on_offense_can_throw() -> void:
	_start_pass_play(PlayerAgent.Team.OFFENSE)
	assert_true(runner.qb_is_passer())
	_slingshot()
	assert_true(runner.pass_thrown, "slingshot should throw on offense")


func test_human_on_defense_cannot_throw_for_cpu_qb() -> void:
	_start_pass_play(PlayerAgent.Team.DEFENSE)
	assert_true(runner.qb_is_passer())
	_slingshot()
	assert_false(runner.pass_thrown, "defense gestures must not throw the CPU's pass")
	assert_false(runner.scrambling)
