extends GutTest
## Special packs: X-Factor guarantee, Mystery (secretly another pack), Draft (keep 1 of 3,
## saved until you pick) and the position shelf.

var db: RosterDB
var rng: RandomNumberGenerator


func before_all() -> void:
	db = GameData.db


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 99


func _starter() -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, db, "KC")
	return p


func test_every_shelf_pack_exists_and_is_for_sale() -> void:
	for shelf in PackCatalog.SHELVES:
		for id in shelf[1]:
			var p := PackCatalog.get_pack(id)
			assert_not_null(p, id)
			assert_gt(p.price, 0, id)
			assert_has(PackCatalog.STORE, id)


func test_xfactor_pack_always_has_an_ability_card() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("xfactor")
	for i in 200:
		var ids := EconomyRules.open_pack(pack, prof, db, rng)
		assert_eq(ids.size(), pack.card_count)
		assert_true(ids.any(func(id: String) -> bool: return db.cards[id].is_xfactor()), str(ids))


func test_mystery_pack_turns_into_its_listed_packs_by_weight() -> void:
	var pack := PackCatalog.get_pack("mystery")
	var w := 0.0
	for x in pack.mystery_weights:
		w += x
	assert_almost_eq(w, 1.0, 0.001)
	var counts := {}
	var n := 50000
	for i in n:
		var real := EconomyRules.resolve_mystery(pack, rng)
		counts[real.id] = int(counts.get(real.id, 0)) + 1
	for i in pack.mystery.size():
		assert_almost_eq(float(counts.get(pack.mystery[i], 0)) / n, pack.mystery_weights[i], 0.01, pack.mystery[i])


func test_buying_a_mystery_pack_opens_the_revealed_pack() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("mystery")
	prof.coins = pack.price
	var before := prof.cards.size()
	var r := EconomyRules.buy(prof, pack, db, rng)
	assert_true(r["mystery"])
	assert_has(pack.mystery, (r["pack"] as PackDef).id)
	assert_eq(prof.cards.size(), before + (r["uids"] as Array).size())
	assert_lt(prof.coins, pack.price, "paid the mystery price")


func test_draft_pack_waits_for_a_pick_and_survives_a_save() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("draft")
	prof.coins = pack.price * 2
	var before := prof.cards.size()
	var r := EconomyRules.buy(prof, pack, db, rng)
	assert_true(r["draft"])
	assert_eq(prof.cards.size(), before, "nothing is added until you pick")
	assert_true(EconomyRules.has_pending_draft(prof))
	assert_eq(EconomyRules.buy(prof, pack, db, rng), {}, "finish the pick before buying again")
	var opts: Array = prof.pending_pick["options"]
	assert_eq(opts.size(), pack.card_count)
	assert_true(opts.any(func(id: String) -> bool: return db.cards[id].tier >= CardRules.Tier.GOLD), "1 gold+ guaranteed")
	var saved := Profile.from_dict(JSON.parse_string(JSON.stringify(prof.to_dict())))
	assert_eq(saved.pending_pick["options"], opts, "the same options come back after a restart")
	var uid := EconomyRules.pick_draft(saved, db, 1)
	assert_gt(uid, 0)
	assert_eq(saved.find(uid)["def"], opts[1])
	assert_eq(saved.cards.size(), before + 1, "you keep exactly one")
	assert_false(EconomyRules.has_pending_draft(saved))
	assert_eq(EconomyRules.pick_draft(saved, db, 0), -1, "no second pick")


func test_trenches_pack_is_linemen_only() -> void:
	var prof := _starter()
	var pack := PackCatalog.get_pack("trenches")
	for i in 40:
		for id in EconomyRules.open_pack(pack, prof, db, rng):
			assert_has(["OL", "DL"], db.players[db.cards[id].player_id].pos)


func test_position_packs_are_drafts_of_that_position() -> void:
	for id in ["qb", "receiver", "defense", "trenches"]:
		var prof := _starter()
		prof.pending_packs = []
		var pack := PackCatalog.get_pack(id)
		assert_true(pack.pick, "%s is a draft" % id)
		prof.coins = pack.price
		var before := prof.cards.size()
		var r := EconomyRules.buy(prof, pack, db, rng)
		assert_true(r["draft"])
		assert_eq(prof.cards.size(), before, "nothing added before the pick")
		var opts: Array = prof.pending_pick["options"]
		assert_eq(opts.size(), pack.card_count)
		for o in opts:
			assert_has(pack.positions, db.players[db.cards[o].player_id].pos, "%s option %s" % [id, o])
		assert_gt(EconomyRules.pick_draft(prof, db, 0), 0)


func test_reward_position_pack_opens_as_a_draft() -> void:
	var prof := _starter()
	prof.pending_packs = []
	var before := prof.cards.size()
	EconomyRules.grant_pack(prof, PackCatalog.get_pack("qb"), db, rng)
	assert_eq(prof.cards.size(), before, "a reward draft is queued, not opened blindly")
	assert_eq(prof.pending_packs, ["qb"])
	var res := EconomyRules.open_pending(prof, db, rng)
	assert_true(res["draft"])
	assert_true(EconomyRules.has_pending_draft(prof))
	prof.pending_packs = ["silver"]
	var again := EconomyRules.open_pending(prof, db, rng)
	assert_true(again["draft"], "the waiting pick comes first")
	assert_eq(prof.pending_packs, ["silver"], "the queue is left alone")
