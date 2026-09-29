extends GutTest
## A league always runs: a fresh career gets a season, so the other teams play (and are simulated)
## alongside your games and your division standings move.

func test_fresh_career_needs_and_gets_a_season() -> void:
	var p := Profile.new()
	Collection.grant_starters(p, GameData.db, "SEA")
	assert_true(GameFlow.needs_season(p))
	GameFlow.start_season(p)
	assert_false(GameFlow.needs_season(p))
	assert_eq(p.season["team"], "SEA")
	assert_eq(p.season["phase"], "regular")


func test_a_played_week_also_sims_the_division_rivals() -> void:
	var p := Profile.new()
	Collection.grant_starters(p, GameData.db, "SEA")
	GameFlow.start_season(p)
	var g: Array = []
	for pair in p.season["weeks"][0]:
		if "SEA" in pair:
			g = pair
	var opp: String = g[1] if g[0] == "SEA" else g[0]
	ModeResults.apply({"mode": "season", "team": "SEA", "opponent": opp, "pf": 24, "pa": 10,
			"extra": {"home": g[0], "away": g[1]}}, p, GameData.db)
	var table := SeasonRules.standings(p.season, GameData.teams.keys())
	var played := 0
	for a in table:
		played += int(table[a]["w"]) + int(table[a]["l"]) + int(table[a]["t"])
	assert_eq(played, 2 * 16, "all 32 teams played week 1")
	for rival in ["ARI", "LAR", "SF"]:
		var r: Dictionary = table[rival]
		assert_eq(int(r["w"]) + int(r["l"]) + int(r["t"]), 1, rival + " has played a game")


func test_changing_teams_starts_a_new_season() -> void:
	var p := Profile.new()
	Collection.grant_starters(p, GameData.db, "SEA")
	GameFlow.start_season(p)
	p.franchise_team = "KC"
	assert_true(GameFlow.needs_season(p))
