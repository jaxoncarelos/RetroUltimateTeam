extends GutTest
## Pocket timing with you at QB (base coverages, no throw): receivers get 20 yards downfield in
## under ~3 s and the rush arrives at ~3 s, so you can't sit back there for 5 s untouched.
const DT := 1.0 / 60.0

func _lineup(form: FormationDef, ovr: int) -> Dictionary:
	var out := {}
	for slot in form.slots:
		out[slot] = {"name": slot, "attrs": RatingModel.fill_attrs(form.slots[slot]["pos"], ovr)}
	return out

func test_pocket_time_on_base_coverages() -> void:
	var off_book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	var def_book: PlaybookDef = load("res://data/plays/defense_playbook.tres")
	var r := _run(off_book, def_book, false)
	assert_lt(r["wr20"], 3.0, "a receiver is 20 yards downfield within ~3 s")
	assert_between(r["press"], 2.5, 3.7, "the rush gets home around 3 s")
	assert_lt(r["sack"], 4.8, "holding the ball ~4-5 s gets you sacked")

func _run(off_book: PlaybookDef, def_book: PlaybookDef, blitz: bool) -> Dictionary:
	var tot := {"wr20": 0.0, "n20": 0, "press": 0.0, "np": 0, "sack": 0.0, "ns": 0, "plays": 0}
	for off in off_book.plays:
		if off.category == "RUN":
			continue
		for def in def_book.plays:
			if (def.category == "BLITZ") != blitz:
				continue
			var runner := PlayRunner.new()
			runner.tuning = load("res://data/tuning/gameplay_tuning.tres")
			runner.rng.seed = 3
			runner.human_team = PlayerAgent.Team.OFFENSE
			add_child_autofree(runner)
			runner.setup_play(off, def, 35.0, FieldGeo.CENTER_Y, _lineup(off.formation, 78), _lineup(def.formation, 78))
			runner.snap()
			var t20 := -1.0
			var tp := -1.0
			var ended := false
			runner.play_ended.connect(func(r: Dictionary) -> void: ended = true)
			for i in int(8.0 / DT):
				runner._physics_process(DT)
				if t20 < 0.0:
					for o in runner.offense:
						if o.is_eligible() and o != runner.qb and o.field_pos.x >= 55.0:
							t20 = runner.play_time
				if tp < 0.0 and runner.pressure_on_qb() >= 0.75:
					tp = runner.play_time
				if runner.phase == PlayRunner.Phase.DEAD:
					break
			tot["plays"] += 1
			if t20 > 0.0:
				tot["wr20"] += t20
				tot["n20"] += 1
			if tp > 0.0:
				tot["press"] += tp
				tot["np"] += 1
			if runner.phase == PlayRunner.Phase.DEAD:
				tot["sack"] += runner.play_time
				tot["ns"] += 1
	gut.p(("BLITZ " if blitz else "BASE ") + "plays %d | first receiver 20yd downfield avg %.2fs (%d) | first pressure avg %.2fs (%d) | play over (sack) avg %.2fs (%d)" % [tot["plays"], tot["wr20"] / maxi(tot["n20"], 1), tot["n20"], tot["press"] / maxi(tot["np"], 1), tot["np"], tot["sack"] / maxi(tot["ns"], 1), tot["ns"]])
	return {"wr20": tot["wr20"] / maxi(tot["n20"], 1), "press": tot["press"] / maxi(tot["np"], 1),
			"sack": tot["sack"] / maxi(tot["ns"], 1)}
