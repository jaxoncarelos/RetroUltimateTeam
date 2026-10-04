extends GutTest
## Dives carry risk: a ball carrier's dive lands on the first body in front of him (no flying
## QB sneak over the pile), and a defender's dive is a commitment (down after a miss, no
## second dive for a while).

const DT := 1.0 / 60.0

var t: GameplayTuning = load("res://data/tuning/gameplay_tuning.tres")


func _runner(seed: int, off_id: String, def_id: String) -> PlayRunner:
	var r := PlayRunner.new()
	r.tuning = t
	r.rng.seed = seed
	r.human_team = PlayerAgent.Team.OFFENSE
	add_child_autofree(r)
	var off: PlayDef = load("res://data/plays/offense/%s.tres" % off_id)
	var def: PlayDef = load("res://data/plays/defense/%s.tres" % def_id)
	r.setup_play(off, def, 35.0, FieldGeo.CENTER_Y, {}, {})
	return r


## Snap, dive after `frames`, return the yards gained.
func _sneak_dive(seed: int, frames: int) -> float:
	var r := _runner(seed, "qb_sneak", "cover2")
	var ended := []
	r.play_ended.connect(func(res: Dictionary) -> void: ended.append(res))
	r.snap()
	for i in frames:
		r._physics_process(DT)
	if r.carrier != null and r.carrier.can_act():
		r.carrier.start_dive(t, Vector2.RIGHT)
	for i in 300:
		r._physics_process(DT)
		if not ended.is_empty():
			break
	return r.ball.field_pos.x - r.los_x


func test_qb_sneak_dive_is_a_yard_or_two_not_six() -> void:
	var total := 0.0
	var worst := 0.0
	var n := 12
	for s in n:
		var y := _sneak_dive(s, 6)
		total += y
		worst = maxf(worst, y)
	gut.p("sneak + instant dive: avg %.1f, max %.1f yd" % [total / n, worst])
	assert_lt(total / n, 2.5, "a dive into the pile is short yardage")
	assert_gt(total / n, 0.0, "but it still pushes the pile")
	assert_lt(worst, 4.0)


func test_carrier_dive_lands_on_a_body_in_front() -> void:
	var r := _runner(1, "hb_dive", "cover2")
	r.snap()
	var c := r.qb
	var d: PlayerAgent = r.defense[0]
	c.velocity = Vector2(6.0, 0.0)
	d.field_pos = c.field_pos + Vector2(0.6, 0.0)
	c.start_dive(t, Vector2.RIGHT)
	r._check_dive_stop()
	assert_eq(c.velocity, Vector2.ZERO, "stopped on the defender")


func test_defender_dive_is_a_commitment() -> void:
	var r := _runner(2, "hb_dive", "cover2")
	r.snap()
	var d: PlayerAgent = r.defense[0]
	assert_true(d.can_dive())
	d.start_dive(t, Vector2.LEFT, t.dive_recover)
	assert_false(d.can_dive(), "no second dive while in the air")
	for i in int(t.dive_time / DT) + 2:
		d.step(DT, t)
	assert_false(d.can_act(), "a missed dive leaves him on the ground")
	var up := 0.0
	while not d.can_act() and up < 5.0:
		d.step(DT, t)
		up += DT
	assert_gte(up, t.dive_recover - 0.1, "down about %.1f s" % t.dive_recover)
	assert_false(d.can_dive(), "back up, but he can't dive again right away")
	for i in int(t.dive_cooldown / DT) + 2:
		d.step(DT, t)
	assert_true(d.can_dive())


func test_cpu_defender_does_not_dive_again_while_cooling_down() -> void:
	var r := _runner(3, "hb_dive", "cover2")
	r.snap()
	var c := r.qb
	var d: PlayerAgent = r.defense[0]
	d.dive_cd = 1.0
	d.field_pos = c.field_pos + Vector2(1.6, 0.0)   # inside cpu_dive_range, outside tackle reach
	r.contact._tackles()
	assert_eq(d.dive_timer, 0.0, "no dive while cooling down")
