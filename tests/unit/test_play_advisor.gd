extends GutTest
## PlayAdvisor situational scoring (play bar "BEST" pick and CPU offense calls).

var book: PlaybookDef


func before_each() -> void:
	book = load("res://data/plays/offense_playbook.tres")


func _best(situation: Dictionary, memory: DefenseMemory = null) -> PlayDef:
	return PlayAdvisor.rank(book.plays, situation, memory)[0]


func _top(situation: Dictionary, n: int) -> Array[PlayDef]:
	return PlayAdvisor.rank(book.plays, situation).slice(0, n)


func test_third_and_one_suggests_short_yardage_run() -> void:
	var p := _best({"down": 3, "to_go": 1, "los_x": 50.0})
	assert_eq(p.category, "RUN")
	assert_has(p.tags, "short_yardage")


func test_third_and_long_suggests_a_deep_pass() -> void:
	var p := _best({"down": 3, "to_go": 12, "los_x": 50.0})
	assert_eq(p.category, "DEEP")
	for q in _top({"down": 3, "to_go": 12, "los_x": 50.0}, 4):
		assert_ne(q.category, "RUN", "no runs in the top 4 on 3rd & 12")


func test_goal_line_suggests_goal_line_plays() -> void:
	var p := _best({"down": 1, "to_go": 2, "los_x": 108.0})
	assert_has(p.tags, "goal_line")
	for q in _top({"down": 1, "to_go": 2, "los_x": 108.0}, 4):
		assert_does_not_have(q.tags, "deep")


func test_short_yardage_packages_not_suggested_with_room() -> void:
	for q in _top({"down": 1, "to_go": 10, "los_x": 40.0}, 4):
		assert_does_not_have(q.tags, "short_yardage")
		assert_does_not_have(q.tags, "goal_line")


func test_trailing_late_prefers_passes() -> void:
	for q in _top({"down": 1, "to_go": 10, "los_x": 40.0, "score_diff": -7, "seconds_left": 60.0}, 4):
		assert_ne(q.category, "RUN")


func test_leading_late_prefers_runs() -> void:
	var p := _best({"down": 1, "to_go": 10, "los_x": 40.0, "score_diff": 7, "seconds_left": 60.0})
	assert_eq(p.category, "RUN")


func test_keyed_play_is_demoted() -> void:
	var situation := {"down": 3, "to_go": 1, "los_x": 50.0}
	var first := _best(situation)
	var mem := DefenseMemory.new(load("res://data/tuning/defense_ai_tuning.tres"))
	for i in 3:
		mem.record(first.id, first.formation.id, first.category, 3)
	assert_ne(_best(situation, mem), first)


func test_rank_keeps_every_play() -> void:
	assert_eq(PlayAdvisor.rank(book.plays, {}).size(), book.plays.size())


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func test_suggest_gives_four_distinct_calls_led_by_the_best() -> void:
	var situation := {"down": 1, "to_go": 10, "los_x": 40.0}
	var bar := PlayAdvisor.suggest(book.plays, situation, _rng(1))
	assert_eq(bar.size(), 4)
	assert_eq(bar[0], _best(situation))
	var ids := {}
	for p in bar:
		ids[p.id] = true
	assert_eq(ids.size(), 4)


func test_suggest_varies_across_snaps() -> void:
	var seen := {}
	for i in 40:
		for p in PlayAdvisor.suggest(book.plays, {"down": 1, "to_go": 10, "los_x": 40.0}, _rng(i)):
			seen[p.id] = true
	assert_gte(seen.size(), 10, "the bar should rotate through many concepts")


func test_suggest_stays_situational() -> void:
	for i in 30:
		for q in PlayAdvisor.suggest(book.plays, {"down": 3, "to_go": 12, "los_x": 50.0}, _rng(i)):
			assert_ne(q.category, "RUN", "no runs on 3rd & 12")


func test_suggest_mixes_categories_on_first_down() -> void:
	var cats := {}
	for q in PlayAdvisor.suggest(book.plays, {"down": 1, "to_go": 10, "los_x": 40.0}, _rng(3)):
		cats[q.category] = true
	assert_gte(cats.size(), 2)


func test_suggest_pushes_the_play_you_just_ran_off_the_top() -> void:
	var situation := {"down": 2, "to_go": 6, "los_x": 45.0}
	var first := PlayAdvisor.suggest(book.plays, situation, _rng(1))[0]
	var mem := DefenseMemory.new(load("res://data/tuning/defense_ai_tuning.tres"))
	mem.record(first.id, first.formation.id, first.category, 0)
	mem.record(first.id, first.formation.id, first.category, 0)
	assert_ne(PlayAdvisor.suggest(book.plays, situation, _rng(1), mem)[0], first)
