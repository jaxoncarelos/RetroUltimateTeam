extends GutTest
## The Madden-Mobile-style store: shelves, legends baked into normal packs, era program packs,
## bundles (queued packs), and the rotating FEATURED offers (deal price, limits, countdowns).

const DAY := 86400

var db: RosterDB
var rng: RandomNumberGenerator


func before_all() -> void:
	db = GameData.db


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 77


func _starter(team := "KC") -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, db, team)
	return p


func test_every_store_pack_loads_with_a_price() -> void:
	for id in PackCatalog.STORE:
		var p := PackCatalog.get_pack(id)
		assert_not_null(p, id)
		assert_gt(p.price, 0, id)
		assert_eq(p.id, id)
		for b in p.bundle:
			assert_not_null(PackCatalog.get_pack(b), "%s contains %s" % [id, b])


func test_bundles_are_cheaper_than_their_packs() -> void:
	for id in PackCatalog.STORE:
		var p := PackCatalog.get_pack(id)
		if not p.bundle.is_empty():
			assert_lt(p.price, PackCatalog.bundle_list_price(p), id)


func test_normal_packs_can_hold_a_legend() -> void:
	for id in ["silver", "gold", "pro", "elite", "throwback"]:
		assert_gt(PackCatalog.get_pack(id).legend_chance, 0.0, id)
	assert_eq(PackCatalog.odds_lines(PackCatalog.get_pack("elite"))[0][0], "LEGEND")


func test_throwback_mixes_legends_with_current_cards() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("throwback")
	var legends := 0
	var cards := 0
	for i in 400:
		for cid in EconomyRules.open_pack(pack, prof, db, rng):
			cards += 1
			if db.cards[cid].is_legend():
				legends += 1
	var share := float(legends) / cards
	assert_between(share, 0.02, 0.09, "about 1 card in 20 is a legend (%d/%d)" % [legends, cards])


func test_era_packs_only_give_legends_of_their_era() -> void:
	var prof := _starter()
	for id in PackCatalog.ERA_PACKS:
		var pack := PackCatalog.get_pack(id)
		var seen := 0
		for i in 60:
			var ids := EconomyRules.open_pack(pack, prof, db, rng)
			assert_eq(ids.size(), pack.card_count, id)
			for cid in ids:
				var c: CardDef = db.cards[cid]
				if c.is_legend():
					seen += 1
					assert_has(pack.eras, db.players[c.player_id].era, "%s gave %s" % [id, cid])
		assert_gte(seen, 60, "%s: one legend per pack" % id)


func test_team_pack_legends_come_from_your_franchise() -> void:
	var prof := _starter("SF")
	var pack := PackCatalog.get_pack("team")
	for i in 300:
		for cid in EconomyRules.open_pack(pack, prof, db, rng):
			assert_eq(db.players[db.cards[cid].player_id].team, "SF", cid)


func test_bundle_queues_its_packs_and_opens_them_in_turn() -> void:
	var prof := _starter()
	prof.pending_packs.clear()
	var pack := PackCatalog.get_pack("bundle_rookie")
	prof.coins = pack.price + 10
	var before := prof.cards.size()
	var r := EconomyRules.buy(prof, pack, db, rng, 1000)
	assert_true(r["bundle"])
	assert_eq(prof.coins, 10)
	assert_eq(prof.cards.size(), before, "nothing opened yet")
	assert_eq(prof.pending_packs, ["silver", "silver", "silver", "gold", "xfactor"])
	var opened := 0
	while not prof.pending_packs.is_empty():
		var o := EconomyRules.open_pending(prof, db, rng, 1000)
		assert_false(o.is_empty())
		assert_gt((o["uids"] as Array).size(), 0, str(o["pack"]))
		opened += 1
	assert_eq(opened, 5)


func test_a_bundle_reward_expands_when_opened() -> void:
	var prof := _starter()
	prof.pending_packs = ["bundle_bronze"]   # replaces the starter pack
	var o := EconomyRules.open_pending(prof, db, rng, 1000)
	assert_eq(o["pack"], "bronze")
	assert_eq(prof.pending_packs.size(), 4)


func test_featured_rotates_and_has_three_offers() -> void:
	var t := 1_790_000_000
	var a := StoreRules.featured(t)
	assert_eq(a.size(), 3)
	for o in a:
		assert_not_null(PackCatalog.get_pack(str(o["pack"])), str(o))
		assert_gt(int(o["ends_in"]), 0)
		assert_lte(int(o["price"]), int(o["list_price"]))
	assert_has(PackCatalog.ERA_PACKS, a[0]["pack"])
	assert_lte(int(a[1]["ends_in"]), DAY)
	assert_lte(int(a[0]["ends_in"]), 7 * DAY)
	# Same day -> same offers; the program changes week to week.
	assert_eq(StoreRules.featured(t + 60)[1]["key"], a[1]["key"])
	var programs := {}
	for w in 3:
		programs[StoreRules.featured(t + w * 7 * DAY)[0]["pack"]] = true
	assert_eq(programs.size(), 3, "three weeks, three era programs")


func test_daily_deal_is_discounted_and_limited() -> void:
	var t := 1_790_000_000
	var prof := _starter()
	var deal: Dictionary = StoreRules.featured(t)[1]
	assert_lt(int(deal["price"]), int(deal["list_price"]))
	prof.coins = int(deal["price"]) * 3
	assert_eq(StoreRules.left(prof, deal), 1)
	var r := StoreRules.buy(prof, deal, db, rng, t)
	assert_false(r.is_empty())
	if r.get("draft", false):
		prof.pending_pick = {}
	assert_eq(prof.coins, int(deal["price"]) * 2, "charged the deal price")
	assert_eq(StoreRules.left(prof, deal), 0)
	assert_false(StoreRules.can_buy(prof, deal), "once per day")
	assert_true(StoreRules.buy(prof, deal, db, rng, t).is_empty())
	# Tomorrow's deal is a new offer; yesterday's count is dropped on the next buy.
	var next: Dictionary = StoreRules.featured(t + DAY)[1]
	assert_ne(next["key"], deal["key"])
	assert_eq(StoreRules.left(prof, next), 1)
	prof.coins = int(next["price"])
	StoreRules.buy(prof, next, db, rng, t + DAY)
	assert_false(prof.store_buys.has(deal["key"]))


func test_store_buys_survive_a_save() -> void:
	var prof := _starter()
	prof.store_buys = {"deal:20000": 1}
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(prof.to_dict())))
	assert_eq(int(back.store_buys.get("deal:20000", 0)), 1)


func test_time_left_text() -> void:
	assert_eq(StoreRules.time_left_text(2 * DAY + 3 * 3600 + 5), "2D 3H")
	assert_eq(StoreRules.time_left_text(5 * 3600 + 12 * 60), "5H 12M")
	assert_eq(StoreRules.time_left_text(30), "1M")
