extends GutTest
## Defense revamp: the hero handed out by the call, drawn paths, block duels (leverage, the TAP!
## window, beating the block), bursts and quicker steering.

const DT := 1.0 / 60.0

var runner: PlayRunner
var touch: TouchInput
var dc: HumanDefenseControl
var off_book: PlaybookDef
var def_book: PlaybookDef


func before_each() -> void:
	off_book = load("res://data/plays/offense_playbook.tres")
	def_book = load("res://data/plays/defense_playbook.tres")
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 5
	runner.human_team = PlayerAgent.Team.DEFENSE
	add_child_autofree(runner)
	touch = TouchInput.new()
	add_child_autofree(touch)
	dc = HumanDefenseControl.new()
	add_child_autofree(dc)
	dc.bind(runner, touch, runner.tuning)
	runner.human_input = dc


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
	dc.on_play_setup()


func _step(n: int) -> void:
	for i in n:
		runner._physics_process(DT)


func _view(p: Vector2) -> Vector2:
	return dc.get_viewport().get_canvas_transform() * FieldProjection.to_screen(p)


func test_hero_by_call() -> void:
	_setup("slants", "cover3")
	assert_eq(runner.controlled.pos_code, "DL")
	_setup("slants", "lb_blitz")
	assert_ne(runner.controlled.pos_code, "DL", "a blitz makes the blitzing second-level player the hero")
	assert_eq(runner.controlled.assignment.get("type", ""), "rush")
	_setup("slants", "press")
	assert_eq(runner.controlled.pos_code, "CB")
	assert_eq(runner.hero_role(runner.controlled), "cover")


func test_a_tap_pick_is_remembered_only_for_the_same_call() -> void:
	_setup("slants", "cover3")
	var lb: PlayerAgent = runner.def_slots["LB1"]
	dc.switcher.manual(lb)
	_setup("slants", "cover3")
	assert_eq(runner.controlled.slot, "LB1", "same call keeps your pick")
	_setup("slants", "press")
	assert_eq(runner.controlled.pos_code, "CB", "a different call hands you its own hero")


func test_drawn_path_is_followed_and_remembered() -> void:
	_setup("slants", "cover3")
	var hero := runner.controlled
	var start := hero.field_pos
	var p1 := start + Vector2(-2.0, -6.0)
	var p2 := start + Vector2(-2.0, -12.0)
	touch.drag_started.emit(_view(start), _view(start))
	touch.dragged.emit(_view(start), _view(p1))
	touch.dragged.emit(_view(start), _view(p2))
	touch.released.emit(_view(start), _view(p2), true)
	assert_gt(runner.hero_path.size(), 1, "the path was recorded")
	# Next play with the same call: the path is back.
	_setup("slants", "cover3")
	assert_gt(runner.hero_path.size(), 1, "remembered for this call and slot")
	runner.snap()
	assert_true(runner.controlled.brain is DrawnPathBrain)
	_step(3)
	var want := (p1 - start).normalized()
	assert_gt(runner.controlled.desired_dir.dot(want), 0.6, "he heads down the drawn line, not straight at the QB")


func test_tapping_the_hero_clears_the_path() -> void:
	_setup("slants", "cover3")
	var hero := runner.controlled
	var start := hero.field_pos
	touch.drag_started.emit(_view(start), _view(start))
	touch.dragged.emit(_view(start), _view(start + Vector2(-3, -8)))
	touch.released.emit(_view(start), _view(start + Vector2(-3, -8)), true)
	assert_false(runner.hero_path.is_empty())
	touch.tapped.emit(_view(start))
	assert_true(runner.hero_path.is_empty())


## Engages the hero with the nearest offensive lineman and returns [hero, blocker].
func _engage_hero(hold := 6.0) -> Array:
	_setup("slants", "cover3")
	runner.snap()
	var hero := runner.controlled
	var blocker: PlayerAgent = null
	var best := INF
	for o in runner.offense:
		if o.pos_code == "OL" and o.field_pos.distance_to(hero.field_pos) < best:
			best = o.field_pos.distance_to(hero.field_pos)
			blocker = o
	hero.field_pos = blocker.field_pos + Vector2(0.9, 0.0)
	hero.engaged_with = blocker
	blocker.engaged_with = hero
	hero.shed_timer = hold
	return [hero, blocker]


func test_pushing_at_the_qb_builds_leverage_and_opens_the_tap_window() -> void:
	var pair := _engage_hero()
	var hero: PlayerAgent = pair[0]
	dc.set_stick((runner.qb.field_pos - hero.field_pos).normalized())
	var opened := false
	for i in 240:
		_step(1)
		if hero.duel_window > 0.0:
			opened = true
			break
	assert_true(opened, "leverage reached the window")
	assert_gt(hero.duel_leverage, runner.tuning.duel_window_at - 0.05)


func test_standing_still_builds_no_leverage() -> void:
	var pair := _engage_hero()
	var hero: PlayerAgent = pair[0]
	_step(120)
	assert_lt(hero.duel_leverage, 0.05)


func test_the_tap_in_the_window_can_beat_the_block_and_bursts() -> void:
	var wins := 0
	for seed_value in 30:
		runner.rng.seed = seed_value + 1
		var pair := _engage_hero()
		var hero: PlayerAgent = pair[0]
		var blocker: PlayerAgent = pair[1]
		hero.duel_window = runner.tuning.duel_window_time * 0.5   # dead-center timing
		hero.duel_leverage = 0.8
		touch.tapped.emit(_view(hero.field_pos))
		if hero.engaged_with == null:
			wins += 1
			assert_gt(hero.burst_timer, 0.0)
			assert_gt(blocker.stun, 0.0, "the beaten blocker is out of it for a moment")
	assert_gt(wins, 15, "a well-timed tap usually wins (%d/30)" % wins)
	assert_lt(wins, 30, "but not always")


func test_a_tap_with_no_window_is_a_burst_not_a_duel_move() -> void:
	_setup("slants", "press")   # a corner hero: not stuck in a block
	runner.snap()
	_step(30)
	var hero := runner.controlled
	assert_true(dc.try_burst())
	assert_gt(hero.burst_timer, 0.0)
	assert_false(dc.try_burst(), "cooling down")


func test_pushing_shortens_the_block_even_without_the_tap() -> void:
	var pair := _engage_hero(3.0)
	var hero: PlayerAgent = pair[0]
	dc.set_stick((runner.qb.field_pos - hero.field_pos).normalized())
	var t_push := 0
	for i in 720:
		_step(1)
		if hero.engaged_with == null:
			t_push = i
			break
	pair = _engage_hero(3.0)
	hero = pair[0]
	dc.set_stick(Vector2.ZERO)
	var t_idle := 0
	for i in 720:
		_step(1)
		if hero.engaged_with == null:
			t_idle = i
			break
	assert_gt(t_push, 0)
	assert_lt(t_push, t_idle, "pushing frees you sooner than standing there")


func test_steering_turns_quicker_than_a_cpu_defender() -> void:
	_setup("slants", "cover3")
	runner.snap()
	var hero := runner.controlled
	dc.set_stick(Vector2(1, 0))
	_step(20)
	assert_almost_eq(hero.accel_mult, runner.tuning.human_accel_mult, 0.001)
	dc.set_stick(Vector2.ZERO)
	assert_eq(hero.accel_mult, 1.0)
