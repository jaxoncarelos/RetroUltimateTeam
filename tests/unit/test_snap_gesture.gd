extends GutTest
## Retro Bowl-style snap: pressing the QB snaps; the same drag aims/throws, scrambles or steers.

const DT := 1.0 / 60.0

var runner: PlayRunner
var touch: TouchInput
var control: HumanOffenseControl
var off_book: PlaybookDef
var def_book: PlaybookDef
var snaps := 0


func before_each() -> void:
	off_book = load("res://data/plays/offense_playbook.tres")
	def_book = load("res://data/plays/defense_playbook.tres")
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 3
	add_child_autofree(runner)
	touch = TouchInput.new()
	add_child_autofree(touch)
	control = HumanOffenseControl.new()
	add_child_autofree(control)
	control.bind(runner, touch, runner.tuning)
	snaps = 0
	control.snap_requested.connect(func() -> void:
		snaps += 1
		runner.snap())


func _setup(id: String) -> void:
	for p in off_book.plays:
		if p.id == id:
			runner.setup_play(p, def_book.plays[1], 35.0, FieldGeo.CENTER_Y, {}, {})


func _qb_view() -> Vector2:
	return control.get_viewport().get_canvas_transform() * FieldProjection.to_screen(runner.qb.field_pos)


func _step(n: int) -> void:
	for i in n:
		runner._physics_process(DT)


func test_press_on_qb_snaps_immediately() -> void:
	_setup("slants")
	touch.pressed.emit(_qb_view())
	assert_eq(snaps, 1)
	assert_eq(runner.phase, PlayRunner.Phase.LIVE)


func test_press_away_from_qb_does_not_snap() -> void:
	_setup("slants")
	touch.pressed.emit(_qb_view() + Vector2(0, 120))
	assert_eq(snaps, 0)
	assert_eq(runner.phase, PlayRunner.Phase.PRE_SNAP)


func test_one_gesture_snap_aim_and_throw() -> void:
	_setup("slants")
	var start := _qb_view()
	touch.pressed.emit(start)
	_step(20)
	var pull := start + Vector2(-40, 0)
	touch.drag_started.emit(start, pull)
	assert_eq(control.mode, HumanOffenseControl.Mode.AIM)
	_step(30)
	touch.released.emit(start, pull, true)
	assert_true(runner.pass_thrown, "release throws")
	assert_gt(runner.ball.to.x, runner.los_x, "pulled back = thrown downfield")


func test_drag_forward_from_qb_scrambles() -> void:
	_setup("slants")
	var start := _qb_view()
	touch.pressed.emit(start)
	touch.drag_started.emit(start, start + Vector2(30, 2))
	assert_true(runner.scrambling)
	assert_eq(control.mode, HumanOffenseControl.Mode.STEER)


func test_drag_anywhere_pre_snap_snaps_and_aims() -> void:
	_setup("curls")
	var start := _qb_view() + Vector2(100, 60)
	touch.drag_started.emit(start, start + Vector2(-20, 0))
	assert_eq(snaps, 1)
	assert_eq(control.mode, HumanOffenseControl.Mode.AIM)


func test_run_play_same_touch_steers_after_handoff() -> void:
	_setup("hb_dive")
	var start := _qb_view()
	touch.pressed.emit(start)
	touch.drag_started.emit(start, start + Vector2(0, 10))
	_step(60)
	assert_eq(runner.carrier.slot, "RB")
	touch.dragged.emit(start, start + Vector2(0, 40))
	assert_eq(control.mode, HumanOffenseControl.Mode.STEER)
	touch.dragged.emit(start, start + Vector2(0, 80))
	assert_gt(control.steer_lateral, 0.5, "dragging down steers toward the bottom sideline")
