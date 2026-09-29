extends GutTest
## Throw feel: tap to switch pass type, aim sensitivity, and enough time in the pocket for a human QB.

const DT := 1.0 / 60.0

var runner: PlayRunner
var touch: TouchInput
var control: HumanOffenseControl
var off_book: PlaybookDef
var def_book: PlaybookDef


func before_each() -> void:
	off_book = load("res://data/plays/offense_playbook.tres")
	def_book = load("res://data/plays/defense_playbook.tres")
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 3
	runner.human_team = PlayerAgent.Team.OFFENSE
	add_child_autofree(runner)
	touch = autofree(TouchInput.new())
	control = HumanOffenseControl.new()
	add_child_autofree(control)
	control.bind(runner, touch, runner.tuning)


func _play(id: String) -> PlayDef:
	for p in off_book.plays:
		if p.id == id:
			return p
	for p in def_book.plays:
		if p.id == id:
			return p
	return null


func test_tap_cycles_the_pass_type() -> void:
	runner.setup_play(_play("slants"), _play("cover3"), 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 30:
		runner._physics_process(DT)   # past the snap tap's grace
	assert_eq(runner.pass_kind, -1)
	var names: Array[String] = []
	control.pass_kind_changed.connect(func(n: String) -> void: names.append(n))
	for i in 4:
		touch.tapped.emit(Vector2(200, 100))
	assert_eq(names, ["BULLET", "TOUCH", "LOB", "AUTO"])


func test_second_finger_cycles_while_aiming() -> void:
	runner.setup_play(_play("slants"), _play("cover3"), 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 30:
		runner._physics_process(DT)
	touch.extra_tapped.emit(Vector2(400, 200))
	assert_eq(runner.pass_kind, PassModel.Kind.BULLET)


func test_picked_type_shapes_the_throw() -> void:
	runner.setup_play(_play("slants"), _play("cover3"), 35.0, FieldGeo.CENTER_Y, {}, {})
	var target := runner.qb.field_pos + Vector2(14.0, 0.0)
	var bullet := PassModel.plan(runner.tuning, 80.0, runner.qb.field_pos, target, PackedVector2Array(), PassModel.Kind.BULLET)
	var touch_p := PassModel.plan(runner.tuning, 80.0, runner.qb.field_pos, target, PackedVector2Array(), PassModel.Kind.TOUCH)
	var lob := PassModel.plan(runner.tuning, 80.0, runner.qb.field_pos, target, PackedVector2Array(), PassModel.Kind.LOB)
	assert_lt(float(bullet["apex"]), float(touch_p["apex"]))
	assert_lt(float(touch_p["apex"]), float(lob["apex"]))
	assert_lt(float(bullet["dur"]), float(lob["dur"]), "a bullet arrives sooner than a lob")
	assert_eq(int(lob["kind"]), PassModel.Kind.LOB)


func test_a_new_play_goes_back_to_auto() -> void:
	runner.setup_play(_play("slants"), _play("cover3"), 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.cycle_pass_kind()
	runner.setup_play(_play("slants"), _play("cover3"), 35.0, FieldGeo.CENTER_Y, {}, {})
	assert_eq(runner.pass_kind, -1)


func test_lower_sensitivity_needs_a_longer_pull() -> void:
	var t := runner.tuning
	assert_lt(PassModel.pull_to_yards(t, 80.0, Settings.AIM_MULT[0]), PassModel.pull_to_yards(t, 80.0, Settings.AIM_MULT[1]))
	assert_lt(PassModel.pull_to_yards(t, 80.0, Settings.AIM_MULT[1]), PassModel.pull_to_yards(t, 80.0, Settings.AIM_MULT[2]))


func test_a_human_qb_gets_time_even_against_a_blitz() -> void:
	for def_id in ["cover0", "lb_blitz", "zone_blitz"]:
		for off_id in ["pa_cross", "smash", "fade", "slants"]:
			var ended := []
			var r := PlayRunner.new()
			r.tuning = runner.tuning
			r.rng.seed = 9
			r.human_team = PlayerAgent.Team.OFFENSE
			add_child_autofree(r)
			r.play_ended.connect(func(res: Dictionary) -> void: ended.append(res))
			r.setup_play(_play(off_id), _play(def_id), 35.0, FieldGeo.CENTER_Y, {}, {})
			r.snap()
			var sacked_at := 99.0
			for i in int(6.0 / DT):
				r._physics_process(DT)
				if not ended.is_empty():
					if ended[0]["type"] == "sack":
						sacked_at = r.play_time
					break
			assert_gt(sacked_at, 2.3, "%s vs %s: sacked at %.1f s" % [off_id, def_id, sacked_at])


func test_cpu_qb_waits_for_the_deep_man_on_a_deep_call() -> void:
	# On a DEEP call the CPU QB should not dump it to a short man in the first two seconds.
	var early_short := 0
	var n := 0
	for seed_value in 12:
		var r := PlayRunner.new()
		r.tuning = runner.tuning
		r.rng.seed = seed_value + 1
		r.human_team = -1
		add_child_autofree(r)
		r.setup_play(_play("four_verts"), _play("cover3"), 35.0, FieldGeo.CENTER_Y, {}, {})
		r.snap()
		var passer := CpuPasser.new(r, r.rng)
		for i in int(2.0 / DT):
			var made := passer.update(DT)
			r._physics_process(DT)
			if not made.is_empty():
				n += 1
				if float(made["target"].x) - r.los_x < r.tuning.cpu_deep_min_air:
					early_short += 1
				break
	assert_eq(early_short, 0, "no short dump-offs in the first 2 s of a deep call (%d throws)" % n)


func test_cpu_offense_calls_more_deep_shots() -> void:
	var book: PlaybookDef = off_book
	var sit := {"down": 1, "to_go": 10, "los_x": 40.0, "score_diff": 0, "seconds_left": 999.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var deep_biased := 0
	var deep_plain := 0
	for i in 600:
		if PlayAdvisor.pick(book.plays, sit, rng).category == "DEEP":
			deep_biased += 1
		if PlayAdvisor.pick(book.plays, sit, rng, null, 1.1, false).category == "DEEP":
			deep_plain += 1
	assert_gt(deep_biased, deep_plain, "the CPU bias adds deep calls (%d vs %d)" % [deep_biased, deep_plain])
