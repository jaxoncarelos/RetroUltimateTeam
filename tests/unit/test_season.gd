extends GutTest
## Season: schedule, score model, standings/tiebreaks, playoff seeding and bracket.

var teams: Dictionary
var rng: RandomNumberGenerator


func before_each() -> void:
	teams = TeamData.load_all()
	rng = RandomNumberGenerator.new()
	rng.seed = 99


func _strengths() -> Dictionary:
	var s := {}
	for a in teams:
		s[a] = 70 + (hash(a) % 15)
	return s


func test_schedule_every_team_plays_once_per_week() -> void:
	var weeks := SeasonRules.make_schedule(teams.keys(), 17, rng)
	assert_eq(weeks.size(), 17)
	var met := {}
	var repeats := 0
	for w in weeks:
		var seen := {}
		for g in w:
			assert_false(seen.has(g[0]) or seen.has(g[1]), "a team plays twice in one week")
			seen[g[0]] = true
			seen[g[1]] = true
			var k := SeasonRules._key(g[0], g[1])
			if met.has(k):
				repeats += 1
			met[k] = true
		assert_eq(seen.size(), 32)
	assert_lt(repeats, 3, "few rematches")


func test_score_model_is_plausible_and_favors_better_teams() -> void:
	var total := 0
	var strong_wins := 0
	var n := 2000
	for i in n:
		var sc := SeasonRules.sim_score(85, 70, rng)
		assert_ne(sc[0], sc[1], "no ties")
		total += sc[0] + sc[1]
		if sc[0] > sc[1]:
			strong_wins += 1
	var avg := float(total) / (2 * n)
	assert_between(avg, 17.0, 27.0, "points per team")
	assert_gt(float(strong_wins) / n, 0.7)


func test_standings_and_tiebreak() -> void:
	var s := {"results": [["KC", "BUF", 24, 17], ["BUF", "SF", 10, 3], ["SF", "KC", 30, 7]]}
	var t := SeasonRules.standings(s, ["KC", "BUF", "SF"])
	assert_eq(t["KC"]["w"], 1)
	assert_eq(t["KC"]["l"], 1)
	var ranked := SeasonRules.rank(["KC", "BUF", "SF"], t)
	assert_eq(ranked[0], "SF", "same record: best point differential first")


func test_full_season_reaches_a_champion() -> void:
	var season := SeasonRules.new_season(teams, "KC", 8, _strengths(), rng)
	for w in 8:
		var mine := SeasonRules.sim_week(season, rng)
		assert_eq(mine.size(), 2)
		SeasonRules.record_game(season, mine[0], mine[1], 21, 14)   # the player "plays"
		season["week"] += 1
	SeasonRules.start_playoffs(season, teams)
	var po: Dictionary = season["playoffs"]
	for conf in ["AFC", "NFC"]:
		assert_eq(po["seeds"][conf].size(), 7)
		for abbr in po["seeds"][conf]:
			assert_eq(teams[abbr].conf, conf)
	assert_eq(po["games"].size(), 6, "3 wild-card games per conference")
	var rounds := 0
	while season["phase"] == "playoffs" and rounds < 6:
		var winners := SeasonRules.sim_playoff_round(season, rng)
		var mine := SeasonRules.my_playoff_game(season)
		if not mine.is_empty():
			winners["%s-%s" % [mine[0], mine[1]]] = "KC"
		SeasonRules.advance_round(season, winners)
		rounds += 1
	assert_eq(season["phase"], "done")
	assert_ne(season["playoffs"]["champion"], "")
	assert_eq(rounds, 4)
	if season["playoffs"]["made_it"]:
		assert_eq(season["playoffs"]["champion"], "KC", "KC won every game it played")
