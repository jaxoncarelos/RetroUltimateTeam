extends GutTest
## LEGEND cards: retired all-time greats from data/legends.csv. One LEGEND card each, kept off
## the real teams and normal pack pools; pulled from the program packs (Hall of Fame, Throwback, era packs,
## Legend Draft), at small odds from Silver+ packs, the "4 ELITES" set and the 100-win objective.

var db: RosterDB
var rng: RandomNumberGenerator


func before_all() -> void:
	db = GameData.db


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 1234


func _starter(team := "KC") -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, db, team)
	return p


func _is_legend(cid: String) -> bool:
	return (db.cards[cid] as CardDef).is_legend()


func test_legends_csv_loads_cleanly() -> void:
	var d := RosterDB.new()
	var teams := TeamData.load_all().keys()
	d.load_file(RosterDB.ROSTER_PATH, teams)
	d.load_legends(RosterDB.LEGENDS_PATH, teams)
	assert_eq(d.errors, [] as Array[String], "no bad rows, no id clashes with the roster")
	assert_between(d.legends.size(), 70, 100)
	var by_pos := {}
	for p in d.legends:
		by_pos[p.pos] = int(by_pos.get(p.pos, 0)) + 1
	gut.p("legends by position: %s" % by_pos)
	for pos in RosterDB.POSITIONS:
		assert_gt(int(by_pos.get(pos, 0)), 0, "at least one %s legend" % pos)


func test_every_legend_is_valid() -> void:
	var eras := {}
	var ids := {}
	for p in db.legends:
		assert_true(p.legend, p.id)
		assert_has(RosterDB.POSITIONS, p.pos, p.id)
		assert_between(p.ovr, 85, 99, "%s OVR" % p.id)
		assert_eq(p.pot, p.ovr, "%s doesn't develop" % p.id)
		assert_not_null(GameData.team(p.team), "%s iconic team %s" % [p.id, p.team])
		assert_between(p.jersey, 0, 99, p.id)
		assert_true(p.era.length() == 5 and p.era.ends_with("s"), "%s era '%s'" % [p.id, p.era])
		eras[p.era] = true
		assert_false(ids.has(p.id), "unique id %s" % p.id)
		ids[p.id] = true
		for a in RatingModel.ATTRS:
			assert_between(int(p.attrs[a]), 25, 99, "%s %s" % [p.id, a])
	assert_gte(eras.size(), 5, "60s through 2010s")
	# The headliners the owner asked for.
	for pid in ["rice_jerry", "johnson_calvin", "sanders_barry", "brady_tom", "taylor_lawrence"]:
		assert_true(db.players.has(pid) and db.players[pid].legend, pid)
	assert_eq(db.players["rice_jerry"].team, "SF")
	assert_eq(db.players["johnson_calvin"].jersey, 81)


func test_one_legend_card_each_and_nothing_else() -> void:
	for p in db.legends:
		var cid := CardRules.legend_id(p.id)
		assert_true(db.cards.has(cid), cid)
		var c: CardDef = db.cards[cid]
		assert_true(c.is_legend())
		assert_eq(c.ovr, p.ovr, "a legend card is his peak rating")
		assert_eq(c.pot, c.ovr)
		assert_eq(c.ability, "")
		assert_eq(CardRules.split_card_id(cid), [p.id, CardRules.PROGRAM_LEGEND])
		for other in [CardRules.card_id(p.id), CardRules.prime_id(p.id), CardRules.core_id(p.id),
				CardRules.xf_id(p.id), CardRules.champ_id(p.id)]:
			assert_false(db.cards.has(other), "no %s" % other)


func test_legends_never_play_for_real_teams() -> void:
	var legend_ids := {}
	for p in db.legends:
		legend_ids[p.id] = true
	for abbr in GameData.teams:
		for p: PlayerData in db.by_team.get(abbr, []):
			assert_false(p.legend, "%s on %s" % [p.id, abbr])
		for slot in db.team_entries(abbr):
			assert_false(legend_ids.has(db.team_entries(abbr)[slot]["id"]), "%s CPU lineup" % abbr)
		for cid in Collection.starter_card_ids(db, abbr):
			assert_false(_is_legend(cid), "%s starter squad: %s" % [abbr, cid])
		var star := db.franchise_star(abbr)
		assert_false(star.legend, "%s franchise star" % abbr)
	for t in CardRules.TABLE.size():
		for cid in db.card_ids_of_tier(t):
			assert_false(_is_legend(cid), "normal pools never hold legends: %s" % cid)


func test_cheap_and_position_packs_have_no_legends_but_elite_rarely_does() -> void:
	var prof := _starter()
	for id in ["bronze", "xfactor", "qb", "trenches"]:
		var pack := PackCatalog.get_pack(id)
		assert_eq(pack.legend_chance, 0.0, id)
		assert_eq(pack.legend_guarantee, 0, id)
		for i in 60:
			for cid in EconomyRules.open_pack(pack, prof, db, rng):
				assert_false(_is_legend(cid), "%s pulled %s" % [id, cid])
	var elite := PackCatalog.get_pack("elite")
	assert_gt(elite.legend_chance, 0.0)
	assert_lt(PackCatalog.get_pack("gold").legend_chance, elite.legend_chance, "Gold: even rarer")
	var packs_with := 0
	var n := 1500
	for i in n:
		var ids := EconomyRules.open_pack(elite, prof, db, rng)
		assert_eq(ids.size(), elite.card_count)
		if ids.any(_is_legend):
			packs_with += 1
	var expect := 1.0 - pow(1.0 - elite.legend_chance, elite.card_count)
	gut.p("elite packs with a legend: %.3f (expected %.3f)" % [float(packs_with) / n, expect])
	assert_almost_eq(float(packs_with) / n, expect, 0.03)


func test_legends_pack_guarantees_a_legend() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("legends")
	assert_has(PackCatalog.STORE, "legends")
	assert_gt(pack.price, PackCatalog.get_pack("elite").price, "the priciest pack on the shelf")
	var ovr_sum := 0
	var n := 400
	for i in n:
		var ids := EconomyRules.open_pack(pack, prof, db, rng)
		assert_eq(ids.size(), pack.card_count)
		var legends := ids.filter(_is_legend)
		assert_gte(legends.size(), 1, str(ids))
		ovr_sum += (db.cards[legends[0]] as CardDef).ovr
	var avg := float(ovr_sum) / n
	gut.p("legends pack: average legend OVR %.1f" % avg)
	assert_between(avg, 88.0, 93.0, "great players, the 99s are rare")


func test_buying_a_legends_pack_adds_the_legend_and_counts_the_pull() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("legends")
	prof.coins = pack.price
	var uids := EconomyRules.buy_and_open(prof, pack, db, rng, 1790000000)
	assert_eq(uids.size(), pack.card_count)
	assert_eq(prof.coins, 0)
	assert_true(uids.any(func(u: int) -> bool: return _is_legend(str(prof.find(u)["def"]))))
	assert_eq(int(prof.objectives["totals"].get("pulls_legend", 0)), 1, "LIVING LEGEND objective counts it")


func test_legend_draft_offers_three_legends() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("legend_draft")
	assert_true(pack.pick)
	prof.coins = pack.price
	var before := prof.cards.size()
	var r := EconomyRules.buy(prof, pack, db, rng)
	assert_true(r["draft"])
	var opts: Array = prof.pending_pick["options"]
	assert_eq(opts.size(), 3)
	for o in opts:
		assert_true(_is_legend(str(o)), "legend draft option %s" % o)
	var uid := EconomyRules.pick_draft(prof, db, 2)
	assert_gt(uid, 0)
	assert_eq(prof.cards.size(), before + 1)
	assert_true(_is_legend(str(prof.find(uid)["def"])))


func test_legend_draft_is_the_100_win_reward_and_the_elite_set_reward() -> void:
	var found := false
	for o in ObjectiveRules.MILESTONES:
		if o.get("pack", "") == "legend_draft":
			found = true
	assert_true(found, "a milestone pays a Legend Draft")
	var s: Dictionary = EconomyRules.SETS.filter(func(d: Dictionary) -> bool: return d["id"] == "elite_to_legend")[0]
	assert_eq(s["reward"], "legend_draft")
	var prof := _starter()
	for p in db.legends.slice(0, 6):
		prof.add_card(CardRules.legend_id(p.id))
	assert_eq(EconomyRules.set_candidates(prof, db, s).size(), 0, "legends are never traded into sets")
	for pid in ["mahomes_patrick", "allen_josh", "barkley_saquon", "jones_chris"]:
		prof.add_card(CardRules.card_id(pid))
	Collection.auto_lineup(prof, db)
	var spare := EconomyRules.set_candidates(prof, db, s).size()
	prof.pending_packs = []
	if spare >= 4:
		assert_eq(EconomyRules.complete_set(prof, db, s), "legend_draft")
		EconomyRules.grant_pack(prof, PackCatalog.get_pack("legend_draft"), db, rng)
		assert_eq(prof.pending_packs, ["legend_draft"], "the pick-one reward is queued for the draft screen")
	else:
		pass_test("lineup took the elites (%d spare)" % spare)


func test_legend_value_is_big_but_sane() -> void:
	var p90 := CardRules.sell_price(90, CardRules.PROGRAM_LEGEND)
	var p99 := CardRules.sell_price(99, CardRules.PROGRAM_LEGEND)
	assert_gt(p90, CardRules.sell_price(90))
	assert_gt(p99, PackCatalog.get_pack("elite").price, "a 99 legend is a career payday")
	# Expected sell-back of a Legends pack stays well under its price (selling can't farm packs).
	var prof := _starter()
	var pack := PackCatalog.get_pack("legends")
	var total := 0
	var n := 600
	for i in n:
		for cid in EconomyRules.open_pack(pack, prof, db, rng):
			total += (db.cards[cid] as CardDef).quicksell
	var ev := float(total) / n
	gut.p("legends pack: average sell-back %d of %d" % [int(ev), pack.price])
	assert_lt(ev, pack.price * 0.5)
	assert_gt(ev, pack.price * 0.15)


func test_a_lineup_with_legends_plays() -> void:
	var prof := _starter()
	var before := Collection.team_ovr(prof, db)
	var chem := Collection.chemistry(prof, db)
	for pid in ["rice_jerry", "johnson_calvin", "sanders_barry", "taylor_lawrence", "sanders_deion", "white_reggie",
			"gonzalez_tony", "stenerud_jan"]:
		prof.add_card(CardRules.legend_id(pid))
	Collection.auto_lineup(prof, db)
	var entries := Collection.lineup_entries(prof, db)
	var names: Array = []
	for slot in entries:
		names.append(entries[slot]["name"])
	assert_has(names, "J. RICE")
	assert_has(names, "C. JOHNSON")
	assert_has(names, "B. SANDERS")
	assert_gt(Collection.team_ovr(prof, db), before + 3, "legends lift the team")
	assert_lte(Collection.chemistry(prof, db), chem, "KC legends (Gonzalez, Stenerud) add no Franchise Chemistry")
	var sf := Profile.new()
	sf.franchise_team = "SF"
	sf.lineup = {"WR1": sf.add_card(CardRules.legend_id("rice_jerry")), "TE": sf.add_card(CardRules.card_id("kittle_george"))}
	assert_eq(Collection.chemistry(sf, db), 0.5, "only the real 49er counts, not the 49ers legend")
	var ml := TeamRating.match_lineup(entries)
	assert_false(ml.is_empty())
	var rice := {}
	for slot in entries:
		if entries[slot]["name"] == "J. RICE":
			rice = entries[slot]
	assert_eq(int(rice["ovr"]), 99)
	assert_gte(int(rice["attrs"]["rte"]), 95, "his attributes drive gameplay")


func test_legends_dont_develop_and_show_their_era() -> void:
	var prof := _starter()
	var uid := prof.add_card(CardRules.legend_id("rice_jerry"))
	var e := prof.find(uid)
	assert_eq(Collection.dev_room(db, e), 0)
	assert_eq(Collection.add_card_xp(db, e, 5000), 0)
	var info := Collection.card_info(prof, db, e)
	assert_true(info["legend"])
	assert_eq(info["era"], "1990s")
	assert_false(info["prospect"])


func test_odds_lines_and_summary() -> void:
	assert_eq(PackCatalog.odds_lines(PackCatalog.get_pack("legend_draft")), [["LEGEND", 100]])
	var el := PackCatalog.odds_lines(PackCatalog.get_pack("elite"))
	assert_eq(el[0][0], "LEGEND")
	assert_string_contains(PackCatalog.summary(PackCatalog.get_pack("legends")), "1 LEGEND")
	assert_string_contains(PackCatalog.summary(PackCatalog.get_pack("legend_draft")), "ALL LEGENDS")
