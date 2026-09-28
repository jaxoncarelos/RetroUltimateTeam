extends GutTest
## Economy: pack odds + guarantees, pulls by real rating, buying, quick-sell, training, sets,
## itemized match rewards, postgame, reward packs, and the progression simulation.

var db: RosterDB
var rng: RandomNumberGenerator

const DAY := 86400
const T0 := 1790000000 + 12 * 3600   # a fixed noon-ish time


func before_all() -> void:
	db = GameData.db


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 2026


func _starter(team := "KC") -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, db, team)
	return p


func _real_card_of_tier(tier: int, skip := 0) -> String:
	var ids := db.card_ids_of_tier(tier)
	ids.sort()
	var base := ids.filter(func(i: String) -> bool: return not i.ends_with("_prime"))
	return base[skip % base.size()]


func test_tier_odds_match_config_over_100k_rolls() -> void:
	for id in PackCatalog.STORE:
		var pack := PackCatalog.get_pack(id)
		var counts := [0, 0, 0, 0]
		var n := 100000
		for i in n:
			counts[EconomyRules.roll_tier(pack.odds, rng)] += 1
		for t in 4:
			assert_almost_eq(float(counts[t]) / n, pack.odds[t], 0.005, "%s tier %d" % [id, t])


func test_pack_odds_sum_to_one() -> void:
	for id in PackCatalog.STORE + PackCatalog.REWARD_ONLY:
		var pack := PackCatalog.get_pack(id)
		assert_not_null(pack, id)
		var s := 0.0
		for o in pack.odds:
			s += o
		assert_almost_eq(s, 1.0, 0.001, id)


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


## A Gold pack always has an 80+ real player; 90+ is rare; an Elite pack always has a 90+.
func test_pulls_follow_real_ratings() -> void:
	var prof := _starter()
	var gold := PackCatalog.get_pack("gold")
	var cards := 0
	var elite := 0
	var primes := 0
	for i in 300:
		var best := 0
		for cid in EconomyRules.open_pack(gold, prof, db, rng):
			var c: CardDef = db.cards[cid]
			assert_false(db.players[c.player_id].generated, "packs never pull generated players")
			best = maxi(best, c.ovr)
			cards += 1
			if c.ovr >= 90:
				elite += 1
			if c.is_prime():
				primes += 1
		assert_gte(best, 80, "gold pack guarantee = an 80+ card")
	var rate := float(elite) / cards
	gut.p("gold pack: %.1f%% of cards 90+, %d primes in %d cards" % [rate * 100.0, primes, cards])
	assert_between(rate, 0.02, 0.10, "90+ is rare in a Gold pack")
	var ep := PackCatalog.get_pack("elite")
	for i in 50:
		var best := 0
		for cid in EconomyRules.open_pack(ep, prof, db, rng):
			best = maxi(best, db.cards[cid].ovr)
		assert_gte(best, 90, "elite pack guarantee")


func test_opened_cards_respect_pack_filters() -> void:
	var prof := _starter()
	var qb := PackCatalog.get_pack("qb")
	for i in 30:
		for cid in EconomyRules.open_pack(qb, prof, db, rng):
			var c: CardDef = db.cards[cid]
			assert_eq(db.players[c.player_id].pos, "QB")
			assert_false(db.players[c.player_id].generated)
	var fr := PackCatalog.get_pack("franchise")
	for i in 10:
		var ids := EconomyRules.open_pack(fr, prof, db, rng)
		assert_eq(ids.size(), fr.card_count, "a team pack always fills")
		for cid in ids:
			assert_eq(db.players[db.cards[cid].player_id].team, "KC")


func test_buying_spends_coins_and_adds_cards_atomically() -> void:
	var prof := _starter()
	var before := prof.cards.size()
	var silver := PackCatalog.get_pack("silver")
	prof.coins = silver.price + 100
	var uids := EconomyRules.buy_and_open(prof, silver, db, rng)
	assert_eq(uids.size(), silver.card_count)
	assert_gte(prof.coins, 100, "coach level-up coins may be added")
	assert_eq(prof.cards.size(), before + silver.card_count)
	prof.coins = 100
	assert_eq(EconomyRules.buy_and_open(prof, silver, db, rng), [] as Array[int], "can't afford another")
	assert_eq(prof.coins, 100)


func test_starter_pack_waits_and_opens() -> void:
	var prof := _starter()
	assert_eq(prof.pending_packs, ["starter"])
	var before := prof.cards.size()
	var res := EconomyRules.open_pending(prof, db, rng)
	assert_eq(res["pack"], "starter")
	assert_eq(res["uids"].size(), 5)
	assert_eq(prof.cards.size(), before + 5)
	var best := 0
	for uid in res["uids"]:
		best = maxi(best, Collection.card_ovr(db, prof.find(uid)))
	assert_gte(best, 80, "the first pack has a Gold")
	assert_true(prof.pending_packs.is_empty())
	assert_eq(EconomyRules.open_pending(prof, db, rng), {})
	assert_eq(ObjectiveRules.find(prof, "m_first_pack")["done"], true, "opening it completes an objective")


func test_quicksell_rules() -> void:
	var prof := _starter()
	var starter_uid := int(prof.lineup["QB"])
	assert_eq(EconomyRules.quicksell(prof, db, starter_uid), 0, "starters can't be sold")
	var uid := prof.add_card("kelce_travis")
	var coins := prof.coins
	var value := CardRules.quicksell(CardRules.tier_for_ovr(db.cards["kelce_travis"].ovr))
	assert_eq(EconomyRules.quicksell(prof, db, uid), value)
	assert_eq(prof.coins, coins + value)
	var locked := prof.add_card("kelce_travis")
	prof.find(locked)["locked"] = true
	assert_eq(EconomyRules.quicksell(prof, db, locked), 0, "locked cards are safe")


func test_training_needs_the_same_player() -> void:
	var prof := _starter()
	var target := int(prof.lineup["QB"])
	var dupe := prof.add_card("mahomes_patrick")
	var other := prof.add_card("kelce_travis")
	assert_false(EconomyRules.train(prof, db, target, other))
	assert_true(EconomyRules.train(prof, db, target, dupe))
	assert_eq(int(prof.find(target)["boost"]), 1)
	assert_true(prof.find(dupe).is_empty(), "the duplicate is consumed")
	for i in 5:
		EconomyRules.train(prof, db, target, prof.add_card("mahomes_patrick"))
	assert_eq(int(prof.find(target)["boost"]), EconomyRules.MAX_BOOST)
	assert_false(EconomyRules.can_train(prof, db, target, prof.add_card("mahomes_patrick")),
			"a maxed veteran can't train further")


func test_sets_trade_cards_for_rewards() -> void:
	var prof := _starter()
	var set_def: Dictionary = EconomyRules.SETS[0]
	var have := EconomyRules.set_candidates(prof, db, set_def).size()
	for i in 10:
		prof.add_card(_real_card_of_tier(CardRules.Tier.BRONZE, i))
	assert_eq(EconomyRules.set_candidates(prof, db, set_def).size(), have + 10)
	var before := prof.cards.size()
	assert_eq(EconomyRules.complete_set(prof, db, set_def), "silver")
	assert_eq(prof.cards.size(), before - 10)
	assert_ne(EconomyRules.franchise_elite(prof, db, rng), "")


func test_match_rewards_are_itemized() -> void:
	var win := EconomyRules.match_rewards({"pf": 28, "pa": 0, "tds": 4, "def_ints": 1, "def_sacks": 2,
			"difficulty": 1, "came_back": false})
	assert_eq(win["total"], EconomyRules.WIN_COINS + 80 + 75 + 50)
	var ids: Array = win["items"].map(func(i: Dictionary) -> String: return i["id"])
	assert_eq(ids, ["base", "win", "tds", "defense", "shutout"])
	assert_eq(win["lines"].size(), win["items"].size())
	var legend := EconomyRules.match_rewards({"pf": 21, "pa": 14, "difficulty": 3})
	assert_eq(legend["total"], int(round(EconomyRules.WIN_COINS * 1.6)))
	var loss := EconomyRules.match_rewards({"pf": 10, "pa": 14, "difficulty": 1})
	assert_eq(loss["total"], EconomyRules.LOSS_COINS)
	assert_eq(EconomyRules.match_rewards({"pf": 10, "pa": 14, "forfeit": true})["total"], 0)
	# Win streak: +10% per consecutive win after the first, capped at +50%.
	var s3 := EconomyRules.match_rewards({"pf": 21, "pa": 14, "difficulty": 1}, false, 3)
	assert_eq(s3["total"], EconomyRules.WIN_COINS + int(round(EconomyRules.WIN_COINS * 0.2)))
	var s9 := EconomyRules.match_rewards({"pf": 21, "pa": 14, "difficulty": 1}, false, 9)
	assert_eq(s9["total"], EconomyRules.WIN_COINS + int(round(EconomyRules.WIN_COINS * 0.5)))
	# New-coach bonus for career wins 1-3.
	var first := EconomyRules.match_rewards({"pf": 21, "pa": 14, "difficulty": 1}, false, 1, 1)
	assert_eq(first["total"], EconomyRules.WIN_COINS + EconomyRules.FIRST_WINS_BONUS[0])
	var fourth := EconomyRules.match_rewards({"pf": 21, "pa": 14, "difficulty": 1}, false, 1, 4)
	assert_eq(fourth["total"], EconomyRules.WIN_COINS)


func _box(won: bool, r: RandomNumberGenerator) -> Dictionary:
	var tds := r.randi_range(2, 4) if won else r.randi_range(1, 3)
	return {"pass_comp": r.randi_range(12, 22), "pass_att": 28, "pass_yds": r.randi_range(150, 300),
			"pass_td": tds - 1, "rush_td": 1, "rush_yds": r.randi_range(50, 130), "long_pass": r.randi_range(15, 55),
			"long_run": r.randi_range(6, 40), "def_sacks": r.randi_range(0, 3), "def_ints": r.randi_range(0, 1),
			"fg_made": r.randi_range(0, 2), "fg_long": r.randi_range(25, 51), "tds": tds}


func test_postgame_pays_records_and_develops() -> void:
	var prof := _starter()
	var coins := prof.coins
	var box := {"pass_comp": 15, "pass_yds": 220, "pass_td": 2, "rush_td": 1, "rush_yds": 104, "long_pass": 42,
			"long_run": 22, "def_sacks": 2, "def_ints": 1, "fg_made": 1, "fg_long": 38}
	var r := {"team": "KC", "opponent": "BUF", "pf": 24, "pa": 10, "tds": 3, "def_ints": 1, "def_sacks": 2,
			"difficulty": 1, "mode": "quick", "box": box}
	var res := EconomyRules.postgame(prof, db, r, T0)
	assert_true(res["won"])
	assert_eq(prof.stats["wins"], 1)
	assert_eq(prof.stats["win_streak"], 1)
	assert_eq(prof.coins, coins + int(res["total"]) + _levelup_coins(res), "every coin is itemized")
	var ids: Array = res["items"].map(func(i: Dictionary) -> String: return i["id"])
	assert_has(ids, "base")
	assert_has(ids, "win")
	assert_has(ids, "first_wins")
	assert_has(ids, "objective", "objectives finished this game are paid out")
	var obj_ids: Array = res["objectives"].map(func(o: Dictionary) -> String: return o["id"])
	for id in ["m_first_pass", "m_first_td", "m_first_win", "m_pass40", "m_rush100", "m_sacks2", "m_int"]:
		assert_has(obj_ids, id)
	assert_gt(int(res["coach"]["xp"]), 0)
	assert_gt(int(prof.coach["xp"]), 0)
	# A loss resets the streak.
	EconomyRules.postgame(prof, db, {"pf": 3, "pa": 10, "difficulty": 1}, T0 + 60)
	assert_eq(prof.stats["win_streak"], 0)
	assert_eq(prof.stats["losses"], 1)


func _levelup_coins(res: Dictionary) -> int:
	var n := 0
	for u in res["coach"]["level_ups"]:
		n += int(u["coins"])
	return n


## Progression: 100 simulated games (win 55%) with one day passing every 3 games: daily
## login, postgame (objectives auto-paid), claim the rest, open reward packs, buy the best
## affordable store pack, train duplicates, sell the rest, auto-lineup. Team OVR should
## climb ≈ 72 -> 76-79 (5 games, the first-session hook) -> ~81 (20) -> ~85 (50) -> 88+ (100).
func test_progression_curve() -> void:
	var prof := _starter("BUF")
	var start := Collection.team_ovr(prof, db)
	var at := {}
	var income := {"match": 0, "objectives": 0}
	var t := T0
	for g in range(1, 101):
		if g % 3 == 1:
			t += DAY
			DailyRules.check_in(prof, t)
		var won := rng.randf() < 0.55
		var box := _box(won, rng)
		var r := {"pf": 24 if won else 17, "pa": 17 if won else 24, "tds": box["tds"], "difficulty": 1,
				"def_sacks": box["def_sacks"], "def_ints": box["def_ints"], "box": box}
		var res := EconomyRules.postgame(prof, db, r, t)
		for i in res["items"]:
			income["objectives" if i["id"] == "objective" else "match"] += int(i["coins"])
		income["objectives"] += int(ObjectiveRules.claim_all(prof, t)["coins"])
		while not prof.pending_packs.is_empty():
			EconomyRules.open_pending(prof, db, rng)
		for id in ["elite", "gold", "silver"]:
			var pack := PackCatalog.get_pack(id)
			while EconomyRules.can_buy(prof, pack):
				EconomyRules.buy_and_open(prof, pack, db, rng)
		Collection.auto_lineup(prof, db)
		for e in prof.cards.duplicate():
			var uid := int(e["uid"])
			if prof.in_lineup(uid):
				continue
			var trained := false
			for s in prof.lineup:
				if EconomyRules.train(prof, db, int(prof.lineup[s]), uid):
					trained = true
					break
			if not trained:
				EconomyRules.quicksell(prof, db, uid)
		Collection.auto_lineup(prof, db)
		if g in [5, 10, 20, 50, 100]:
			at[g] = Collection.team_ovr(prof, db)
			var dev := 0
			var boost := 0
			for s in prof.lineup:
				var e := prof.find(int(prof.lineup[s]))
				dev += int(e["dev"])
				boost += int(e["boost"])
			gut.p("  g%d ovr %d lineup dev +%d boost +%d coins %d level %d" % [g, at[g], dev, boost, prof.coins,
					int(prof.coach["level"])])
	gut.p("progression OVR: start %d, %s  coach level %d  income %s" % [start, at, int(prof.coach["level"]), income])
	assert_between(start, 69, 74)
	assert_between(at[5], start + 1, 80, "a quick first-session hook, not an instant endgame")
	assert_between(at[20], 77, 84, "about 80 after a season")
	assert_between(at[50], 82, 88, "about 85 after 50 games")
	assert_gte(at[100], 86, "88+ endgame after 100 games")
	assert_lte(at[100], 95)
	assert_gt(income["objectives"], 0, "objectives are a real income source")
