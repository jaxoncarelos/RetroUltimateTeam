extends GutTest
## Phase 5 economy: pack odds + guarantees, buying, quick-sell, training, sets, rewards,
## and a light progression simulation.

var db: RosterDB
var rng: RandomNumberGenerator


func before_all() -> void:
	db = GameData.db


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 2026


func _starter(team := "KC") -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, db, team)
	return p


func test_tier_odds_match_config_over_100k_rolls() -> void:
	for id in PackCatalog.STORE:
		var pack := PackCatalog.get_pack(id)
		var counts := [0, 0, 0, 0]
		var n := 100000
		for i in n:
			counts[EconomyRules.roll_tier(pack.odds, rng)] += 1
		for t in 4:
			assert_almost_eq(float(counts[t]) / n, pack.odds[t], 0.005, "%s tier %d" % [id, t])


func test_pack_guarantees_hold() -> void:
	for id in PackCatalog.STORE:
		var pack := PackCatalog.get_pack(id)
		for i in 3000:
			var tiers := EconomyRules.roll_pack_tiers(pack, rng)
			assert_eq(tiers.size(), pack.card_count)
			if pack.guarantee_tier >= 0 and tiers.max() < pack.guarantee_tier:
				fail_test("%s broke its guarantee: %s" % [id, tiers])
				return
	pass_test("guarantees held")


func test_opened_cards_respect_pack_filters() -> void:
	var prof := _starter()
	var qb := PackCatalog.get_pack("qb")
	for i in 30:
		for cid in EconomyRules.open_pack(qb, prof, db, rng):
			var c: CardDef = db.cards[cid]
			assert_eq(db.players[c.player_id].pos, "QB")
			assert_false(db.players[c.player_id].generated)
	var fr := PackCatalog.get_pack("franchise")
	for cid in EconomyRules.open_pack(fr, prof, db, rng):
		assert_eq(db.players[db.cards[cid].player_id].team, "KC")


func test_buying_spends_coins_and_adds_cards_atomically() -> void:
	var prof := _starter()
	var before := prof.cards.size()
	prof.coins = 1600
	var silver := PackCatalog.get_pack("silver")
	var uids := EconomyRules.buy_and_open(prof, silver, db, rng)
	assert_eq(uids.size(), silver.card_count)
	assert_eq(prof.coins, 100)
	assert_eq(prof.cards.size(), before + silver.card_count)
	assert_eq(EconomyRules.buy_and_open(prof, silver, db, rng), [] as Array[int], "can't afford another")
	assert_eq(prof.coins, 100)


func test_quicksell_rules() -> void:
	var prof := _starter()
	var starter_uid := int(prof.lineup["QB"])
	assert_eq(EconomyRules.quicksell(prof, db, starter_uid), 0, "starters can't be sold")
	var uid := prof.add_card("kelce_travis_gold")
	var coins := prof.coins
	assert_eq(EconomyRules.quicksell(prof, db, uid), 500)
	assert_eq(prof.coins, coins + 500)
	var locked := prof.add_card("kelce_travis_bronze")
	prof.find(locked)["locked"] = true
	assert_eq(EconomyRules.quicksell(prof, db, locked), 0, "locked cards are safe")


func test_training_needs_the_same_player() -> void:
	var prof := _starter()
	var target := int(prof.lineup["QB"])
	var dupe := prof.add_card("mahomes_patrick_bronze")
	var other := prof.add_card("kelce_travis_bronze")
	assert_false(EconomyRules.train(prof, db, target, other))
	assert_true(EconomyRules.train(prof, db, target, dupe))
	assert_eq(int(prof.find(target)["boost"]), 1)
	assert_true(prof.find(dupe).is_empty(), "the duplicate is consumed")
	for i in 5:
		EconomyRules.train(prof, db, target, prof.add_card("mahomes_patrick_bronze"))
	assert_eq(int(prof.find(target)["boost"]), EconomyRules.MAX_BOOST)


func test_sets_trade_cards_for_rewards() -> void:
	var prof := _starter()
	var set_def: Dictionary = EconomyRules.SETS[0]
	assert_eq(EconomyRules.complete_set(prof, db, set_def), "", "starters are all in the lineup")
	for i in 10:
		prof.add_card("gen_kc_ol_1_bronze" if db.cards.has("gen_kc_ol_1_bronze") else "kelce_travis_bronze")
	var before := prof.cards.size()
	assert_eq(EconomyRules.complete_set(prof, db, set_def), "silver")
	assert_eq(prof.cards.size(), before - 10)
	assert_ne(EconomyRules.franchise_elite(prof, db, rng), "")


func test_match_rewards() -> void:
	var win := EconomyRules.match_rewards({"pf": 28, "pa": 0, "tds": 4, "def_ints": 1, "def_sacks": 2,
			"difficulty": 1, "came_back": false})
	assert_eq(win["total"], EconomyRules.WIN_COINS + 80 + 75 + 50)
	var legend := EconomyRules.match_rewards({"pf": 21, "pa": 14, "difficulty": 3})
	assert_eq(legend["total"], int(round(EconomyRules.WIN_COINS * 1.6)))
	var loss := EconomyRules.match_rewards({"pf": 10, "pa": 14, "difficulty": 1})
	assert_eq(loss["total"], EconomyRules.LOSS_COINS)
	assert_eq(EconomyRules.match_rewards({"pf": 10, "pa": 14, "forfeit": true})["total"], 0)


## Progression: play 100 simulated games (win 55%), buy the best affordable pack whenever
## possible, sell non-starters, auto-lineup. Team OVR should climb roughly along PLAN §5.
func test_progression_curve() -> void:
	var prof := _starter("BUF")
	var start := Collection.team_ovr(prof, db)
	var at := {}
	for g in range(1, 101):
		var won := rng.randf() < 0.55
		prof.coins += EconomyRules.match_rewards({"pf": 24 if won else 17, "pa": 17 if won else 24, "tds": 3,
				"difficulty": 1, "def_sacks": 2})["total"]
		for id in ["elite", "gold", "silver", "bronze"]:
			var pack := PackCatalog.get_pack(id)
			while EconomyRules.can_buy(prof, pack) and id != "bronze":
				EconomyRules.buy_and_open(prof, pack, db, rng)
		Collection.auto_lineup(prof, db)
		for e in prof.cards.duplicate():
			if not prof.in_lineup(int(e["uid"])):
				EconomyRules.quicksell(prof, db, int(e["uid"]))
		if g in [5, 15, 20, 45, 100]:
			at[g] = Collection.team_ovr(prof, db)
	gut.p("progression OVR: start %d, %s" % [start, at])
	assert_between(start, 55, 70)
	assert_gt(at[20], start + 4, "noticeably better after a season")
	assert_gt(at[100], at[20], "still improving late")
	assert_lt(at[20], 90, "no instant endgame")
