extends GutTest
## Retro Bowl-style snap: a deliberate pull-back drag snaps (never a tap); the same drag aims/throws, scrambles or steers; swipes hesi/dive/juke.

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


func test_press_on_qb_does_not_snap() -> void:
	_setup("slants")
	touch.pressed.emit(_qb_view())
	assert_eq(snaps, 0)
	assert_eq(runner.phase, PlayRunner.Phase.PRE_SNAP)


func test_tap_never_snaps() -> void:
	_setup("slants")
	var p := _qb_view()
	touch.pressed.emit(p)
	touch.tapped.emit(p)
	touch.released.emit(p, p, false)
	assert_eq(snaps, 0)


func test_short_or_forward_drag_never_snaps() -> void:
	_setup("slants")
	var start := _qb_view()
	touch.drag_started.emit(start, start + Vector2(-12, 0))
	touch.dragged.emit(start, start + Vector2(-20, 0))
	touch.dragged.emit(start, start + Vector2(60, 0))
	touch.dragged.emit(start, start + Vector2(0, 80))
	assert_eq(snaps, 0)
	assert_eq(runner.phase, PlayRunner.Phase.PRE_SNAP)


func test_pull_back_drag_snaps_run_play() -> void:
	_setup("hb_dive")
	var start := _qb_view()
	touch.drag_started.emit(start, start + Vector2(-10, 0))
	assert_eq(snaps, 0)
	touch.dragged.emit(start, start + Vector2(-30, 0))
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
	assert_eq(snaps, 1)
	assert_eq(control.mode, HumanOffenseControl.Mode.AIM)
	_step(30)
	touch.released.emit(start, pull, true)
	assert_true(runner.pass_thrown, "release throws")
	assert_gt(runner.ball.to.x, runner.los_x, "pulled back = thrown downfield")


func test_drag_forward_from_qb_scrambles() -> void:
	_setup("slants")
	var start := _qb_view()
	touch.pressed.emit(start)
	touch.drag_started.emit(start, start + Vector2(-30, 0))
	_step(30)
	touch.dragged.emit(start, start + Vector2(30, 2))
	assert_true(runner.scrambling)
	assert_eq(control.mode, HumanOffenseControl.Mode.STEER)


func test_pull_back_anywhere_snaps_and_aims() -> void:
	_setup("curls")
	var start := _qb_view() + Vector2(100, 60)
	touch.drag_started.emit(start, start + Vector2(-30, 0))
	assert_eq(snaps, 1)
	assert_eq(control.mode, HumanOffenseControl.Mode.AIM)


func test_run_play_same_touch_steers_after_handoff() -> void:
	_setup("hb_dive")
	var start := _qb_view()
	touch.pressed.emit(start)
	touch.drag_started.emit(start, start + Vector2(-30, 0))
	_step(60)
	assert_eq(runner.carrier.slot, "RB")
	touch.dragged.emit(start, start + Vector2(0, 40))
	assert_eq(control.mode, HumanOffenseControl.Mode.STEER)
	touch.dragged.emit(start, start + Vector2(0, 80))
	assert_gt(control.steer_lateral, 0.5, "dragging down steers toward the bottom sideline")


func test_swipe_direction_mapping() -> void:
	assert_eq(HumanOffenseControl.swipe_name(Vector2(-1, 0.2)), "left")
	assert_eq(HumanOffenseControl.swipe_name(Vector2(1, -0.3)), "right")
	assert_eq(HumanOffenseControl.swipe_name(Vector2(0.2, -1)), "up")
	assert_eq(HumanOffenseControl.swipe_name(Vector2(-0.1, 1)), "down")


func _to_carrier() -> PlayerAgent:
	_setup("hb_dive")
	var start := _qb_view()
	touch.drag_started.emit(start, start + Vector2(-30, 0))
	_step(60)
	return runner.carrier


func test_swipe_left_hesitates_then_bursts() -> void:
	var c := _to_carrier()
	touch.swiped.emit(Vector2.LEFT)
	assert_gt(c.hesi_timer, 0.0)
	assert_gt(runner.tuning.hesi_tackle_mult, 0.0)
	_step(int((runner.tuning.hesi_time + 0.05) / DT))
	assert_gt(c.burst_timer, 0.0, "exits with a burst")


func test_swipe_right_dives_and_vertical_swipes_juke() -> void:
	var c := _to_carrier()
	touch.swiped.emit(Vector2.DOWN)
	assert_gt(c.juke_timer, 0.0)
	assert_gt(c.juke_dir, 0.0)
	c.juke_cd = 0.0
	c.juke_timer = 0.0
	touch.swiped.emit(Vector2.UP)
	assert_lt(c.juke_dir, 0.0)
	touch.swiped.emit(Vector2.RIGHT)
	assert_gt(c.dive_timer, 0.0)
