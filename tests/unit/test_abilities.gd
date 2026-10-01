extends GutTest
## X-Factor cards: catalog, ability triggers (drive/series/game/clutch), resets, attribute
## boosts, lineup plumbing and pack weighting.

var db: RosterDB


func before_all() -> void:
	db = GameData.db


func _tracker(slots: Dictionary) -> AbilityTracker:
	var t := AbilityTracker.new()
	var entries := {}
	for slot in slots:
		entries[slot] = {"name": slot, "ability": slots[slot], "attrs": RatingModel.fill_attrs("QB", 80)}
	t.setup(entries)
	t.on_drive(1)
	return t


func _throw(yards: int, carrier := "WR1", type := "tackle") -> Dictionary:
	return {"side": "offense", "type": type, "yards": yards, "pass_thrown": true, "run_play": false,
			"carrier_slot": carrier, "down": 1}


func test_good_players_get_an_xfactor_card() -> void:
	var allen := "allen_josh"
	assert_true(db.cards.has(CardRules.xf_id(allen)))
	var xf: CardDef = db.cards[CardRules.xf_id(allen)]
	var base: CardDef = db.cards[allen]
	assert_eq(xf.ovr, mini(base.ovr + CardRules.XF_BONUS, 99))
	assert_true(xf.is_xfactor())
	assert_has(AbilityRules.for_position("QB"), xf.ability)
	assert_eq(CardRules.split_card_id(xf.id), [allen, CardRules.PROGRAM_XFACTOR])
	assert_eq(base.ability, "", "base cards have no ability")


func test_every_xfactor_ability_fits_its_position() -> void:
	var n := 0
	for id in db.cards:
		var c: CardDef = db.cards[id]
		if c.is_xfactor():
			n += 1
			assert_has(AbilityRules.get_def(c.ability)["pos"], db.players[c.player_id].pos, id)
	assert_gt(n, 100)


func test_every_position_has_an_ability() -> void:
	for pos in RosterDB.POSITIONS:
		assert_false(AbilityRules.for_position(pos).is_empty(), pos)


func test_gunslinger_needs_two_long_completions_in_one_drive() -> void:
	var t := _tracker({"QB": "gunslinger"})
	assert_eq(t.record(_throw(25)).size(), 0)
	assert_eq(t.record(_throw(8)).size(), 0, "short completions don't count")
	var on := t.record(_throw(31))
	assert_eq(on.size(), 1)
	assert_eq(on[0]["id"], "gunslinger")
	assert_true(t.is_on("QB"))
	var side := {"QB": {"attrs": {"thp": 80, "tha": 80}}}
	var boosted := t.apply(side)
	assert_eq(boosted["QB"]["attrs"]["thp"], 88)
	assert_eq(boosted["QB"]["attrs"]["tha"], 84)
	assert_eq(side["QB"]["attrs"]["thp"], 80, "the lineup itself is not modified")


func test_drive_abilities_reset_on_a_new_drive() -> void:
	var t := _tracker({"QB": "gunslinger"})
	t.record(_throw(25))
	t.on_drive(2)
	t.record(_throw(25))
	assert_false(t.is_on("QB"), "progress from the last drive is gone")
	t.record(_throw(25))
	assert_true(t.is_on("QB"))
	t.on_drive(3)
	assert_false(t.is_on("QB"), "the boost ends with the drive")


func test_streak_ability_resets_on_a_miss() -> void:
	var t := _tracker({"QB": "field_general"})
	t.record(_throw(5))
	t.record(_throw(5))
	t.record(_throw(0, "", "incomplete"))
	t.record(_throw(5))
	assert_false(t.is_on("QB"))
	t.record(_throw(5))
	t.record(_throw(5))
	assert_true(t.is_on("QB"))


func test_receiver_abilities_count_only_his_catches() -> void:
	var t := _tracker({"WR1": "deep_threat", "WR2": "deep_threat"})
	var on := t.record(_throw(24, "WR2"))
	assert_eq(on.size(), 1)
	assert_eq(on[0]["slot"], "WR2")
	assert_false(t.is_on("WR1"))


func test_defensive_abilities_credit_the_tackler() -> void:
	var t := _tracker({"DL1": "sack_artist", "LB1": "enforcer"})
	var sack := {"side": "defense", "type": "sack", "yards": -6, "pass_thrown": false, "tackler_slot": "DL1"}
	assert_eq(t.record(sack).size(), 1)
	assert_true(t.is_on("DL1"))
	var tackle := {"side": "defense", "type": "tackle", "yards": 4, "tackler_slot": "LB1"}
	t.record(tackle)
	assert_false(t.is_on("LB1"))
	t.record(tackle)
	assert_true(t.is_on("LB1"))
	t.on_drive(2)
	assert_true(t.is_on("DL1"), "game-long abilities survive possession changes")
	assert_false(t.is_on("LB1"), "series abilities end with the series")


func test_offense_events_dont_trigger_defense_abilities() -> void:
	var t := _tracker({"CB1": "lockdown"})
	t.record({"side": "offense", "type": "incomplete", "pass_thrown": true})
	t.record({"side": "offense", "type": "incomplete", "pass_thrown": true})
	assert_false(t.is_on("CB1"))


func test_clutch_abilities_follow_the_situation() -> void:
	var t := _tracker({"K": "ice_veins", "QB": "two_minute"})
	assert_false(t.is_on("K", {"quarter": 2, "half_seconds_left": 500.0}))
	assert_true(t.is_on("K", {"quarter": 4, "half_seconds_left": 500.0}))
	assert_true(t.is_on("QB", {"quarter": 2, "half_seconds_left": 90.0}))
	var k := t.apply_kicker({"kac": 80, "kpw": 80}, {"quarter": 4})
	assert_eq(k["kac"], 88)


func test_lineup_entries_carry_the_ability() -> void:
	var p := Profile.new()
	Collection.grant_starters(p, db, "BUF")
	var xf := CardRules.xf_id("allen_josh")
	var uid := p.add_card(xf)
	p.lineup["QB"] = uid
	var entries := Collection.lineup_entries(p, db)
	assert_eq(entries["QB"]["ability"], db.cards[xf].ability)
	var t := AbilityTracker.new()
	t.setup(entries)
	assert_true(t.has_any())


func test_xfactor_cards_are_rare_in_regular_packs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var p := Profile.new()
	Collection.grant_starters(p, db, "KC")
	var pack := PackCatalog.get_pack("gold")
	var xf := 0
	var n := 0
	for i in 300:
		for id in EconomyRules.open_pack(pack, p, db, rng):
			n += 1
			if id.ends_with("_xf"):
				xf += 1
	assert_gt(xf, 0, "they do show up")
	assert_lt(float(xf) / n, 0.35)
