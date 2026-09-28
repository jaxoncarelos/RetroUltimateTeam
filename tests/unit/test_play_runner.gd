extends GutTest
## Integration: runs whole plays by stepping the simulation manually (deterministic, fast).

const DT := 1.0 / 60.0

var runner: PlayRunner
var off_book: PlaybookDef
var def_book: PlaybookDef
var ended: Array = []


func before_each() -> void:
	off_book = load("res://data/plays/offense_playbook.tres")
	def_book = load("res://data/plays/defense_playbook.tres")
	runner = PlayRunner.new()
	runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
	runner.rng.seed = 12345
	add_child_autofree(runner)
	ended = []
	runner.play_ended.connect(func(r: Dictionary) -> void: ended.append(r))


func _lineup(form: FormationDef, ovr: int) -> Dictionary:
	var out := {}
	for slot in form.slots:
		out[slot] = {"name": slot, "attrs": RatingModel.fill_attrs(form.slots[slot]["pos"], ovr)}
	return out


## Runs one play to completion; the CPU read throws for pass plays.
func _run_play(off: PlayDef, def: PlayDef) -> Dictionary:
	runner.setup_play(off, def, 35.0, FieldGeo.CENTER_Y, _lineup(off.formation, 80), _lineup(def.formation, 78))
	runner.snap()
	for i in int(20.0 / DT):
		if runner.qb_is_passer() and runner.play_time > 1.2:
			var read := QBReadLogic.best_throw(runner)
			if not read.is_empty():
				runner.throw_ball(read["target"])
		runner._physics_process(DT)
		if not ended.is_empty():
			return ended[0]
	return {}


func test_setup_spawns_nine_per_side() -> void:
	runner.setup_play(off_book.plays[0], def_book.plays[0], 35.0, FieldGeo.CENTER_Y, {}, {})
	assert_eq(runner.offense.size(), 9)
	assert_eq(runner.defense.size(), 9)
	assert_not_null(runner.qb)
	assert_eq(runner.phase, PlayRunner.Phase.PRE_SNAP)


func test_every_offensive_play_ends_cleanly() -> void:
	for off in off_book.plays:
		for def in def_book.plays:
			ended.clear()
			var r := _run_play(off, def)
			assert_false(r.is_empty(), "%s vs %s never ended" % [off.id, def.id])
			if r.is_empty():
				continue
			assert_has(["tackle", "sack", "out", "incomplete", "td", "int", "safety"], r["type"])
			assert_between(float(r["spot_x"]), 0.0, FieldGeo.LENGTH)


func test_run_play_hands_off_to_runner() -> void:
	var dive: PlayDef = null
	for p in off_book.plays:
		if p.id == "hb_dive":
			dive = p
	runner.setup_play(dive, def_book.plays[0], 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 90:
		runner._physics_process(DT)
	assert_not_null(runner.carrier)
	assert_eq(runner.carrier.slot, "RB")


func test_qb_cannot_throw_after_crossing_los() -> void:
	runner.setup_play(off_book.plays[0], def_book.plays[0], 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	runner.qb.field_pos.x = 40.0
	runner._physics_process(DT)
	assert_false(runner.qb_is_passer())
	assert_true(runner.scrambling)


func test_aim_point_clamped_to_throw_range() -> void:
	runner.setup_play(off_book.plays[0], def_book.plays[0], 35.0, FieldGeo.CENTER_Y, {}, {})
	var target := runner.aim_point(Vector2(300, 150), Vector2(0, 150))
	var max_d := RatingModel.max_throw_distance(runner.tuning, runner.qb.attr("thp"))
	assert_almost_eq(runner.qb.field_pos.distance_to(target), max_d, 0.01)
	assert_gt(target.x, runner.qb.field_pos.x, "pulling left throws downfield")


func _find(book: PlaybookDef, id: String) -> PlayDef:
	for p in book.plays:
		if p.id == id:
			return p
	return null


func test_every_run_play_gets_the_ball_to_its_runner() -> void:
	for off in off_book.plays:
		if not off.is_run():
			continue
		runner.setup_play(off, def_book.plays[0], 35.0, FieldGeo.CENTER_Y, {}, {})
		runner.snap()
		for i in 100:
			runner._physics_process(DT)
		var expected := "QB" if off.assignments["QB"]["type"] == "sneak" else "RB"
		assert_not_null(runner.carrier, off.id)
		if runner.carrier != null:
			assert_eq(runner.carrier.slot, expected, "%s runner" % off.id)


func test_qb_sneak_is_a_run_not_a_sack() -> void:
	runner.setup_play(_find(off_book, "qb_sneak"), _find(def_book, "goal_line"), 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	assert_eq(runner.carrier, runner.qb)
	assert_false(runner.qb_is_passer())


func test_press_coverage_jams_the_receiver() -> void:
	runner.setup_play(_find(off_book, "slants"), _find(def_book, "press"), 35.0, FieldGeo.CENTER_Y, {}, {})
	var wr: PlayerAgent = runner.off_slots["WR1"]
	var cb: PlayerAgent = runner.def_slots["CB1"]
	assert_almost_eq(cb.field_pos.distance_to(wr.field_pos), runner.tuning.press_depth, 0.01)
	runner.snap()
	assert_gt(wr.jam_timer, 0.0)


func test_play_action_makes_underneath_zones_bite() -> void:
	runner.setup_play(_find(off_book, "pa_cross"), _find(def_book, "cover3"), 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	var lb: PlayerAgent = runner.def_slots["LB1"]
	assert_gt((lb.brain as ZoneBrain).bite, 0.0)
	var deep: PlayerAgent = runner.def_slots["S1"]
	assert_eq((deep.brain as ZoneBrain).bite, 0.0)


func test_draw_waits_before_the_handoff() -> void:
	runner.setup_play(_find(off_book, "hb_draw"), def_book.plays[0], 35.0, FieldGeo.CENTER_Y, {}, {})
	runner.snap()
	for i in 30:
		runner._physics_process(DT)
	assert_eq(runner.carrier, runner.qb, "still the QB's ball at 0.5s")
