extends GutTest
## Separation of every receiver from his nearest defender at 1.0 / 1.8 / 2.6 s, per coverage.
const DT := 1.0 / 60.0

func _lineup(form: FormationDef, ovr: int) -> Dictionary:
	var out := {}
	for slot in form.slots:
		out[slot] = {"name": slot, "attrs": RatingModel.fill_attrs(form.slots[slot]["pos"], ovr)}
	return out

func test_sep() -> void:
	var t: GameplayTuning = load("res://data/tuning/gameplay_tuning.tres")
	var off_book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	for def_id in ["cover1", "press", "cover3", "cover2"]:
		var def: PlayDef = load("res://data/plays/defense/%s.tres" % def_id)
		var acc := {}   # slot -> [sum t1, sum t2, sum t3, n]
		for off in off_book.plays:
			if off.is_run():
				continue
			var r := PlayRunner.new()
			r.tuning = t
			r.rng.seed = 3
			r.human_team = -1
			add_child(r)
			r.setup_play(off, def, 40.0, FieldGeo.CENTER_Y, _lineup(off.formation, 78), _lineup(def.formation, 84))
			r.snap()
			for i in int(2.7 / DT):
				r._physics_process(DT)
				var tt := r.play_time
				for k in [1.0, 1.8, 2.6]:
					if absf(tt - k) < DT * 0.5:
						for o in r.offense:
							if not o.is_eligible() or not (o.brain is RouteBrain):
								continue
							var near := 99.0
							for d in r.defense:
								near = minf(near, d.field_pos.distance_to(o.field_pos))
							if not acc.has(o.slot):
								acc[o.slot] = [0.0, 0.0, 0.0, 0, 0, 0]
							var idx := [1.0, 1.8, 2.6].find(k)
							acc[o.slot][idx] += minf(near, 12.0)
							acc[o.slot][3 + idx] += 1
				if r.phase != PlayRunner.Phase.LIVE:
					break
			r.queue_free()
		var parts: Array[String] = []
		for s in acc:
			var a: Array = acc[s]
			parts.append("%s %.1f/%.1f/%.1f" % [s, a[0] / maxf(a[3], 1), a[1] / maxf(a[4], 1), a[2] / maxf(a[5], 1)])
		gut.p("%-7s sep@1.0/1.8/2.6s: %s" % [def_id, "  ".join(parts)])
