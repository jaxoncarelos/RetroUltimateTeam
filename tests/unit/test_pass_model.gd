extends GutTest
## PassModel (pure throw geometry) + the passing integration in PlayRunner: loft, lane
## clearance, contest geometry, aim assist, receiver leads and deep-ball outcomes.

const DT := 1.0 / 60.0

var t: GameplayTuning


func before_each() -> void:
	t = load("res://data/tuning/gameplay_tuning.tres")


# ---------------------------------------------------------------- pure

func test_height_starts_at_release_and_ends_at_catch() -> void:
	assert_almost_eq(PassModel.height_at(10.0, 0.0), PassModel.RELEASE_Z, 0.001)
	assert_almost_eq(PassModel.height_at(10.0, 1.0), PassModel.CATCH_Z, 0.001)
	assert_gt(PassModel.height_at(10.0, 0.5), 10.0)


func test_short_throws_are_bullets_deep_throws_are_lobs() -> void:
	var short := PassModel.plan(t, 85, Vector2(30, 20), Vector2(38, 20))
	var mid := PassModel.plan(t, 85, Vector2(30, 20), Vector2(52, 20))
	var deep := PassModel.plan(t, 85, Vector2(30, 20), Vector2(75, 20))
	assert_eq(short["kind"], PassModel.Kind.BULLET)
	assert_eq(deep["kind"], PassModel.Kind.LOB)
	assert_gt(float(mid["apex"]), float(short["apex"]))
	assert_gt(float(deep["apex"]), 10.0, "a 45-yard bomb goes high")
	assert_lt(float(short["apex"]), 1.5, "a slant is on a line")


func test_lob_hang_time_matches_its_height() -> void:
	var deep := PassModel.plan(t, 85, Vector2(30, 20), Vector2(75, 20))
	var hang := sqrt(8.0 * float(deep["apex"]) / t.ball_gravity)
	assert_almost_eq(float(deep["dur"]), maxf(hang, 45.0 / RatingModel.throw_speed(t, 85)), 0.001)
	var slant := PassModel.plan(t, 85, Vector2(30, 20), Vector2(38, 20))
	assert_almost_eq(float(slant["dur"]), maxf(8.0 / RatingModel.throw_speed(t, 85), 0.25), 0.001,
			"a bullet flies at arm speed")
	var bullet_speed := 8.0 / float(PassModel.plan(t, 85, Vector2(30, 20), Vector2(38, 20))["dur"])
	var lob_speed := 45.0 / float(deep["dur"])
	assert_lt(lob_speed, bullet_speed, "lobs travel slower over the ground than bullets")


func test_defender_in_lane_forces_touch_over_him() -> void:
	var from := Vector2(30, 20)
	var to := Vector2(42, 20)
	var open := PassModel.plan(t, 85, from, to)
	var lb := PackedVector2Array([Vector2(36, 20.5)])
	var over := PassModel.plan(t, 85, from, to, lb)
	assert_eq(open["kind"], PassModel.Kind.BULLET)
	assert_gt(float(over["apex"]), float(open["apex"]))
	var u := 6.0 / 12.0
	assert_gte(PassModel.height_at(float(over["apex"]), u), t.lane_clear_height - 0.01, "clears his hands")
	assert_ne(over["kind"], PassModel.Kind.BULLET)


func test_lane_ignores_rushers_coverage_and_defenders_off_the_line() -> void:
	var from := Vector2(30, 20)
	var to := Vector2(45, 20)
	var rusher := PackedVector2Array([Vector2(31.5, 20)])
	var cover := PackedVector2Array([Vector2(44, 20)])
	var wide := PackedVector2Array([Vector2(38, 25)])
	var base := float(PassModel.plan(t, 85, from, to)["apex"])
	assert_almost_eq(float(PassModel.plan(t, 85, from, to, rusher)["apex"]), base, 0.001)
	assert_almost_eq(float(PassModel.plan(t, 85, from, to, cover)["apex"]), base, 0.001)
	assert_almost_eq(float(PassModel.plan(t, 85, from, to, wide)["apex"]), base, 0.001)


func test_high_ball_is_out_of_reach() -> void:
	assert_false(PassModel.can_reach(t, 0.3, 6.0))
	assert_true(PassModel.can_reach(t, 0.3, 2.0))
	assert_false(PassModel.can_reach(t, 2.0, 2.0), "too far off the path")
	assert_true(PassModel.can_reach(t, 0.3, 3.2, 0.9), "a leap adds reach")


func test_trailing_defender_contests_less_than_one_in_front() -> void:
	var landing := Vector2(60, 15)
	var rec := Vector2(59.5, 15)
	var trailing := Vector2(58.5, 15)     # behind the receiver
	var in_front := Vector2(61.0, 15)     # between the ball's spot and beyond
	var c_trail := PassModel.contest(t, landing, rec, trailing)
	var c_front := PassModel.contest(t, landing, rec, in_front)
	assert_gt(c_front, c_trail)
	assert_eq(PassModel.contest(t, landing, rec, Vector2(70, 15)), 0.0, "far away = no contest")
	assert_gt(PassModel.contest(t, landing, rec, Vector2(58.0, 15), 1.0),
			PassModel.contest(t, landing, rec, Vector2(58.0, 15), 0.0), "a hanging ball lets him close")


func test_aim_assist_pulls_toward_nearby_lead_only() -> void:
	var leads := PackedVector2Array([Vector2(50, 10), Vector2(50, 40)])
	var near := PassModel.assist(t, Vector2(52, 11), leads)
	assert_eq(near["index"], 0)
	assert_lt((near["point"] as Vector2).distance_to(leads[0]), Vector2(52, 11).distance_to(leads[0]))
	var far := PassModel.assist(t, Vector2(50, 25), leads)
	assert_eq(far["index"], -1)
	assert_eq(far["point"], Vector2(50, 25))
	var off := t.duplicate() as GameplayTuning
	off.aim_assist_strength = 0.0
	assert_eq(PassModel.assist(off, Vector2(52, 11), leads)["point"], Vector2(52, 11))


func test_pull_is_progressive() -> void:
	var a := PassModel.pull_to_yards(t, 40.0)
	var b := PassModel.pull_to_yards(t, 80.0)
	assert_gt(b, a * 2.0, "twice the pull throws more than twice as far")
	assert_gt(PassModel.pull_to_yards(t, 110.0), 45.0, "a deep ball needs well under half the screen")


# ---------------------------------------------------------------- integration

func _find(book: PlaybookDef, id: String) -> PlayDef:
	for p in book.plays:
		if p.id == id:
			return p
	return null


func _lineup(form: FormationDef, ovr: int) -> Dictionary:
	var out := {}
	for slot in form.slots:
		out[slot] = {"name": slot, "attrs": RatingModel.fill_attrs(form.slots[slot]["pos"], ovr)}
	return out


func _runner(seed: int) -> PlayRunner:
	var r := PlayRunner.new()
	r.tuning = t
	r.rng.seed = seed
	r.human_team = -1
	add_child_autofree(r)
	return r


func _setup(r: PlayRunner, off_id: String, def_id: String) -> void:
	var off_book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	var def_book: PlaybookDef = load("res://data/plays/defense_playbook.tres")
	var off := _find(off_book, off_id)
	var def := _find(def_book, def_id)
	r.setup_play(off, def, 35.0, FieldGeo.CENTER_Y, _lineup(off.formation, 78), _lineup(def.formation, 78))
	r.snap()


func _run_out(r: PlayRunner, ended: Array) -> Dictionary:
	for i in int(12.0 / DT):
		r._physics_process(DT)
		if not ended.is_empty():
			return ended[0]
	return {}


func test_lead_point_is_ahead_of_a_streaking_receiver() -> void:
	var r := _runner(1)
	_setup(r, "four_verts", "cover3")
	for i in 60:
		r._physics_process(DT)
	var wr: PlayerAgent = r.off_slots["WR1"]
	var lead := r.lead_point(wr)
	assert_gt(lead.x, wr.field_pos.x + 8.0, "a lob to a go route leads him by many yards")


func test_man_defender_flips_and_trails_a_go_route() -> void:
	var r := _runner(2)
	_setup(r, "four_verts", "cover1")
	var cb: PlayerAgent = r.def_slots["CB1"]
	for i in 90:
		r._physics_process(DT)
	assert_true((cb.brain as ManCoverBrain).flipped)
	assert_lt(cb.field_pos.x, r.off_slots["WR1"].field_pos.x + 0.5, "the receiver has a step")


## Well-thrown deep ball to a receiver with a step on man coverage: mostly caught.
func test_well_placed_lob_vs_man_is_usually_caught() -> void:
	var caught := 0
	var n := 24
	for seed in n:
		var r := _runner(100 + seed)
		var ended := []
		r.play_ended.connect(func(res: Dictionary) -> void: ended.append(res))
		_setup(r, "four_verts", "cover0")
		for i in 72:
			r._physics_process(DT)
		r.throw_ball(r.lead_point(r.off_slots["WR1"]))
		assert_eq(int(r.throw_plan["kind"]), PassModel.Kind.LOB)
		var res := _run_out(r, ended)
		if res.get("type", "") in ["tackle", "td", "out"]:
			caught += 1
	assert_between(float(caught) / n, 0.45, 0.95, "caught %d/%d" % [caught, n])


## An underthrown lob that lands on the trailing defender gets undercut: rarely caught.
func test_underthrown_lob_gets_undercut() -> void:
	var caught := 0
	var n := 24
	for seed in n:
		var r := _runner(200 + seed)
		var ended := []
		r.play_ended.connect(func(res: Dictionary) -> void: ended.append(res))
		_setup(r, "four_verts", "cover0")
		for i in 72:
			r._physics_process(DT)
		var cb: PlayerAgent = r.def_slots["CB1"]
		var plan := r.plan_throw(cb.field_pos)
		r.throw_ball(r.predict(cb.brain.mark, 0.0).lerp(cb.field_pos, 1.0) + cb.velocity * float(plan["dur"]) * 0.8)
		var res := _run_out(r, ended)
		if res.get("type", "") in ["tackle", "td", "out"]:
			caught += 1
	assert_lt(float(caught) / n, 0.45, "caught %d/%d" % [caught, n])


func test_aim_assist_pulls_reticle_onto_receiver() -> void:
	var r := _runner(3)
	_setup(r, "four_verts", "cover3")
	for i in 50:
		r._physics_process(DT)
	var wr: PlayerAgent = r.off_slots["WR1"]
	var lead := r.lead_point(wr)
	# A pull whose raw landing point is 2 yards off his lead (bisect the progressive curve).
	var raw := lead + Vector2(0, 2)
	var want := r.qb.field_pos.distance_to(raw)
	var lo := 0.0
	var hi := 400.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if PassModel.pull_to_yards(t, mid) < want:
			lo = mid
		else:
			hi = mid
	var pull := -(raw - r.qb.field_pos).normalized() * lo
	var aimed := r.aim_point(Vector2(300, 150), Vector2(300, 150) + pull)
	assert_eq(r.aim_assist_target, wr)
	assert_lt(aimed.distance_to(lead), raw.distance_to(lead) - 0.3, "pulled toward the lead")


func test_cpu_read_uses_the_same_planner() -> void:
	var r := _runner(4)
	_setup(r, "four_verts", "cover0")
	for i in 70:
		r._physics_process(DT)
	var e := QBReadLogic.evaluate(r, r.off_slots["WR1"])
	assert_false(e.is_empty())
	assert_eq(int(e["kind"]), PassModel.Kind.LOB)
	assert_almost_eq((e["target"] as Vector2).distance_to(r.lead_point(r.off_slots["WR1"])), 0.0, 0.01)


## The ball gets there: a good arm (85 THP) throws a 15-yard bullet in ~0.5 s, a 30-yard lob
## lands in ~1.3 s and a 50-yard bomb in ~1.6 s (owner: "so slow in the air").
func test_flight_times_feel_quick() -> void:
	var from := Vector2(30, 26)
	var d15 := PassModel.plan(t, 85.0, from, from + Vector2(15, 0))
	var d30 := PassModel.plan(t, 85.0, from, from + Vector2(30, 0))
	var d50 := PassModel.plan(t, 85.0, from, from + Vector2(50, 0))
	assert_lt(float(d15["dur"]), 0.55)
	assert_lt(float(d30["dur"]), 1.4)
	assert_lt(float(d50["dur"]), 1.7)
	assert_lt(float(d15["dur"]), float(d30["dur"]))
	assert_lt(float(d30["dur"]), float(d50["dur"]))
