extends GutTest
## Squad tools in EconomyRules: SELL DUPLICATES (duplicate_plan / sell_duplicates: which
## copy of a player stays, what is never sold, the coins it pays) and lineup_upgrades
## (the lineup screen's green "▲+N" badges).

var db: RosterDB


func before_all() -> void:
	db = GameData.db


func _starter() -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, db, "KC")
	return p


func test_no_duplicates_no_plan() -> void:
	var prof := _starter()
	# The starting squad has one card per player.
	var plan := EconomyRules.duplicate_plan(prof, db)
	assert_eq(plan["sell_uids"].size(), 0)
	assert_eq(int(plan["coins"]), 0)
	assert_eq(int(plan["players"]), 0)
	assert_eq(EconomyRules.sell_duplicates(prof, db), 0)


func test_keeps_the_best_bench_copy() -> void:
	var prof := _starter()
	var a := prof.add_card("kelce_travis")
	var b := prof.add_card("kelce_travis")
	var c := prof.add_card("kelce_travis")
	prof.find(b)["boost"] = 2   # the best copy
	var plan := EconomyRules.duplicate_plan(prof, db)
	assert_eq(plan["sell_uids"].size(), 2)
	assert_true(a in plan["sell_uids"])
	assert_true(c in plan["sell_uids"])
	assert_false(b in plan["sell_uids"], "the highest OVR copy stays")
	assert_eq(int(plan["players"]), 1)
	assert_eq(int(plan["coins"]), EconomyRules.quicksell_value(db, prof.find(a)) * 2)


func test_ties_keep_the_oldest_copy() -> void:
	var prof := _starter()
	var a := prof.add_card("kelce_travis")
	var b := prof.add_card("kelce_travis")
	assert_eq(EconomyRules.duplicate_plan(prof, db)["sell_uids"], [b] as Array[int])
	assert_true(prof.find(a).size() > 0)


func test_starters_and_locked_cards_are_never_sold() -> void:
	var prof := _starter()
	var qb := int(prof.lineup["QB"])
	var qb_def: String = prof.find(qb)["def"]
	var spare := prof.add_card(qb_def)
	var locked := prof.add_card(qb_def)
	prof.find(locked)["locked"] = true
	var plan := EconomyRules.duplicate_plan(prof, db)
	assert_false(qb in plan["sell_uids"], "the starter stays")
	assert_false(locked in plan["sell_uids"], "locked copies stay")
	assert_true(spare in plan["sell_uids"])


func test_starter_is_kept_even_if_a_bench_copy_is_worse() -> void:
	var prof := _starter()
	var qb := int(prof.lineup["QB"])
	var qb_def: String = prof.find(qb)["def"]
	var worse := prof.add_card(qb_def)
	assert_eq(EconomyRules.duplicate_plan(prof, db)["sell_uids"], [worse] as Array[int])


func test_better_bench_copy_than_the_starter_is_not_sold() -> void:
	var prof := _starter()
	var qb := int(prof.lineup["QB"])
	var qb_def: String = prof.find(qb)["def"]
	var better := prof.add_card(qb_def)
	prof.find(better)["boost"] = 1
	var plan := EconomyRules.duplicate_plan(prof, db)
	assert_false(better in plan["sell_uids"], "an upgrade over the starter is kept")
	assert_false(qb in plan["sell_uids"])


func test_prime_and_base_cards_of_one_player_are_duplicates() -> void:
	var prof := _starter()
	var pid := "kelce_travis"
	if not db.cards.has(CardRules.prime_id(pid)):
		pass_test("no prime card for this player")
		return
	var base := prof.add_card(CardRules.card_id(pid))
	var prime := prof.add_card(CardRules.prime_id(pid))
	var plan := EconomyRules.duplicate_plan(prof, db)
	var keep := prime if Collection.card_ovr(db, prof.find(prime)) >= Collection.card_ovr(db, prof.find(base)) else base
	assert_false(keep in plan["sell_uids"])
	assert_eq(plan["sell_uids"].size(), 1)


func test_retired_cards_are_ignored() -> void:
	var prof := _starter()
	prof.add_card("no_such_player")
	prof.add_card("no_such_player")
	assert_eq(EconomyRules.duplicate_plan(prof, db)["sell_uids"].size(), 0)


func test_sell_duplicates_pays_the_plan() -> void:
	var prof := _starter()
	for i in 3:
		prof.add_card("kelce_travis")
	prof.add_card("mahomes_patrick")
	var lineup := prof.lineup.duplicate()
	var cards := prof.cards.size()
	var coins := prof.coins
	var plan := EconomyRules.duplicate_plan(prof, db)
	var got := EconomyRules.sell_duplicates(prof, db)
	assert_eq(got, int(plan["coins"]))
	assert_gt(got, 0)
	assert_eq(prof.coins, coins + got)
	assert_eq(prof.cards.size(), cards - plan["sell_uids"].size())
	assert_eq(prof.lineup, lineup, "the lineup is untouched")
	assert_eq(EconomyRules.duplicate_plan(prof, db)["sell_uids"].size(), 0, "nothing left to sell")


# ---------------------------------------------------------------- lineup upgrades

func test_auto_lineup_leaves_no_upgrades() -> void:
	var prof := _starter()
	assert_eq(EconomyRules.lineup_upgrades(prof, db), {})


func test_better_bench_card_shows_on_both_slots_of_its_position() -> void:
	var prof := _starter()
	var star := prof.add_card("chase_jamarr")
	var ups := EconomyRules.lineup_upgrades(prof, db)
	assert_true(ups.has("WR1") and ups.has("WR2"))
	assert_eq(int(ups["WR1"]["uid"]), star)
	var wr1 := Collection.card_ovr(db, prof.find(int(prof.lineup["WR1"])))
	assert_eq(int(ups["WR1"]["delta"]), Collection.card_ovr(db, prof.find(star)) - wr1)
	assert_false(ups.has("QB"), "other positions untouched")
	Collection.auto_lineup(prof, db)
	assert_false(EconomyRules.lineup_upgrades(prof, db).has("WR1"), "gone once he starts")


func test_a_starter_elsewhere_is_not_an_upgrade() -> void:
	var prof := _starter()
	var star := prof.add_card("chase_jamarr")
	prof.lineup["WR1"] = star
	# A second Chase card can't also start at WR2, and is no upgrade over himself at equal OVR.
	prof.add_card("chase_jamarr")
	assert_false(EconomyRules.lineup_upgrades(prof, db).has("WR2"))
	assert_false(EconomyRules.lineup_upgrades(prof, db).has("WR1"))


func test_better_copy_of_the_same_player_is_an_upgrade() -> void:
	var prof := _starter()
	var qb := int(prof.lineup["QB"])
	var copy := prof.add_card(prof.find(qb)["def"])
	prof.find(copy)["boost"] = 2
	var ups := EconomyRules.lineup_upgrades(prof, db)
	assert_eq(int(ups["QB"]["uid"]), copy)
	assert_eq(int(ups["QB"]["delta"]), 2)


func test_empty_slot_is_an_upgrade() -> void:
	var prof := _starter()
	var k := int(prof.lineup["K"])
	prof.lineup.erase("K")
	var ups := EconomyRules.lineup_upgrades(prof, db)
	assert_eq(int(ups["K"]["uid"]), k)
	assert_eq(int(ups["K"]["delta"]), Collection.card_ovr(db, prof.find(k)))
