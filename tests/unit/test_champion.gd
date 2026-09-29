extends GutTest
## Winning the Super Bowl: coins, an Elite pack and a locked 99 CHAMP card of the franchise star;
## a second title pays coins instead. CHAMP cards never come out of packs.

func _profile() -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, GameData.db, "KC")
	return p


func test_champ_card_is_99_of_the_franchise_star() -> void:
	var db := GameData.db
	var star := db.franchise_star("KC")
	var c: CardDef = db.cards[CardRules.champ_id(star.id)]
	assert_eq(c.ovr, 99)
	assert_true(c.is_champ())
	assert_eq(c.player_id, star.id)
	assert_eq(CardRules.split_card_id(c.id), [star.id, CardRules.PROGRAM_CHAMP])


func test_champ_cards_are_never_pulled_from_packs() -> void:
	for tier in 4:
		for cid in GameData.db.card_ids_of_tier(tier):
			assert_false(cid.ends_with("_champ"), cid)


func test_reward_is_locked_and_a_repeat_pays_coins() -> void:
	var p := _profile()
	var coins := p.coins
	var r := EconomyRules.champion_reward(p, GameData.db)
	assert_ne(r["card"], "")
	var owned := p.cards.filter(func(e: Dictionary) -> bool: return e["def"] == r["card"])
	assert_eq(owned.size(), 1)
	assert_true(owned[0]["locked"])
	assert_eq(p.coins, coins)
	var again := EconomyRules.champion_reward(p, GameData.db)
	assert_eq(again["card"], "")
	assert_eq(p.coins, coins + EconomyRules.CHAMP_REPEAT_COINS)
	assert_eq(p.cards.filter(func(e: Dictionary) -> bool: return e["def"] == r["card"]).size(), 1)


## Plays a whole season as KC (winning every game). Returns the profile, or null if KC missed the playoffs.
func _title_run(seed_value: int) -> Array:
	var prof := _profile()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var strengths := {}
	for a in GameData.teams:
		strengths[a] = GameData.db.team_ovr(a)
	prof.season = SeasonRules.new_season(GameData.teams, "KC", 4, strengths, rng)
	var last := ""
	for guard in 40:
		if prof.season["phase"] == "done":
			break
		var g: Array = []
		if prof.season["phase"] == "regular":
			for pair in prof.season["weeks"][int(prof.season["week"])]:
				if "KC" in pair:
					g = pair
		else:
			g = SeasonRules.my_playoff_game(prof.season)
		if g.is_empty():
			if prof.season["phase"] == "playoffs" and prof.season["playoffs"]["made_it"] and not prof.season["playoffs"]["you_out"]:
				# First-round bye: the season screen's SIM ROUND button.
				SeasonRules.advance_round(prof.season, SeasonRules.sim_playoff_round(prof.season, rng))
				continue
			return []
		var opp: String = g[1] if g[0] == "KC" else g[0]
		last = ModeResults.apply({"mode": "season", "team": "KC", "opponent": opp, "pf": 30, "pa": 3,
				"extra": {"home": g[0], "away": g[1]}}, prof, GameData.db)
	return [prof, last] if prof.season["phase"] == "done" else []


func test_winning_every_game_through_the_super_bowl_grants_the_card() -> void:
	var run: Array = []
	for s in range(1, 60):
		run = _title_run(s)
		if not run.is_empty():
			break
	assert_false(run.is_empty(), "some seed lets an all-win KC through to the Super Bowl")
	var prof: Profile = run[0]
	assert_eq(prof.season["playoffs"]["champion"], "KC")
	assert_true(str(run[1]).begins_with("SUPER BOWL CHAMPIONS"), run[1])
	var star := GameData.db.franchise_star("KC")
	assert_true(prof.cards.any(func(e: Dictionary) -> bool: return e["def"] == CardRules.champ_id(star.id)))
