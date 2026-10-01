extends GutTest
## DefenseMemory (tendency tracking / keying) and the CPU defensive play caller.

var t: DefenseAITuning
var mem: DefenseMemory


func before_each() -> void:
	t = load("res://data/tuning/defense_ai_tuning.tres")
	mem = DefenseMemory.new(t)


func _call(id: String, yards := 5, form := "off_shotgun", cat := "SHORT") -> void:
	mem.record(id, form, cat, yards, id.capitalize())


func test_single_call_is_not_keyed() -> void:
	_call("slants")
	assert_eq(mem.keyed_play(), "")
	assert_eq(mem.key_level("slants", "off_shotgun", "SHORT"), 0.0)


func test_two_calls_in_last_five_key_the_play() -> void:
	_call("slants")
	_call("dive", 4, "off_iform", "RUN")
	_call("deep", 4, "off_iform", "DEEP")
	_call("curls", 4, "off_iform", "SHORT")
	_call("slants")
	assert_eq(mem.keyed_play(), "slants")
	assert_gt(mem.key_level("slants", "off_shotgun", "SHORT"), 0.4)
	assert_eq(mem.keyed_play_name(), "SLANTS")


func test_big_gain_keys_immediately() -> void:
	_call("deep", 32, "off_shotgun", "DEEP")
	assert_eq(mem.keyed_play(), "deep")


func test_stuffed_play_does_not_key() -> void:
	_call("dive", 0, "off_iform", "RUN")
	_call("dive", -1, "off_iform", "RUN")
	assert_eq(mem.keyed_play(), "")


func test_key_level_grows_with_repeats() -> void:
	_call("slants")
	_call("slants")
	var two := mem.key_level("slants")
	_call("slants")
	_call("slants")
	assert_gt(mem.key_level("slants"), two)
	assert_lte(mem.key_level("slants"), 1.0)


func test_key_decays_after_switching() -> void:
	_call("slants")
	_call("slants")
	_call("slants")
	assert_eq(mem.keyed_play(), "slants")
	for id in ["a", "b", "c", "d"]:
		_call(id, 4, "f_" + id, "RUN")
	assert_eq(mem.keyed_play(), "")


func test_mixing_six_plays_stays_unkeyed() -> void:
	var plays := [["slants", "SHORT", "off_shotgun"], ["dive", "RUN", "off_iform"],
			["deep", "DEEP", "off_trips"], ["sweep", "RUN", "off_single"],
			["mesh", "SHORT", "off_empty"], ["fade", "DEEP", "off_goal"]]
	for i in 18:
		var p: Array = plays[i % 6]
		_call(p[0], 5, p[2], p[1])
		assert_eq(mem.keyed_play(), "", "call %d" % i)


func test_counter_weight_favors_counters_of_recent_category() -> void:
	for i in 4:
		_call("dive%d" % i, 4, "form%d" % i, "RUN")
	var vs_run := mem.counter_weight(["RUN"])
	var vs_deep := mem.counter_weight(["DEEP"])
	assert_gt(vs_run, vs_deep * 1.5)
	assert_eq(mem.counter_weight([]), 1.0)


func test_play_caller_counters_run_spam() -> void:
	var book: PlaybookDef = load("res://data/plays/defense_playbook.tres")
	for i in 5:
		_call("hb_dive", 4, "off_iform", "RUN")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var run_counters := 0
	var n := 400
	var situation := {"down": 1, "to_go": 10, "los_x": 40.0}
	for i in n:
		var p := AIPlayCaller.pick_defense(book.plays, mem, situation, rng)
		if "RUN" in p.counters:
			run_counters += 1
	var baseline := 0
	for p in book.plays:
		if "RUN" in p.counters:
			baseline += 1
	assert_gt(float(run_counters) / n, 1.5 * float(baseline) / book.plays.size(),
			"run counters should be called well above their base share")


func test_goal_line_defense_only_near_goal() -> void:
	var p := PlayDef.new()
	p.tags.assign(["goal_line"])
	var far := AIPlayCaller.defense_situation_mult(p, {"los_x": 40.0, "to_go": 10, "down": 1})
	var near := AIPlayCaller.defense_situation_mult(p, {"los_x": 107.0, "to_go": 3, "down": 1})
	assert_lt(far, 0.2)
	assert_gt(near, 1.0)


func test_weighted_index_respects_weights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var hits := [0, 0]
	for i in 1000:
		hits[AIPlayCaller.weighted_index(PackedFloat32Array([1.0, 9.0]), rng)] += 1
	assert_between(hits[1], 850, 950)
