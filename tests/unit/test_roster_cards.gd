extends GutTest
## Phase 4: roster import, real-rating cards (tier from OVR, Prime programs), team OVR,
## lineups, starting squad, difficulty rescale, profile/save + migration.

const HEADER := "id,name,team,pos,jersey,ovr,spd,acc,str,awr,thp,tha,cth,rte,car,elu,blk,tak,cov,prs,kpw,kac"

var db: RosterDB


func before_each() -> void:
	db = RosterDB.new()
	db.load_file(RosterDB.ROSTER_PATH, TeamData.load_all().keys())
	db.fill_depth(TeamData.load_all().keys())
	db.build_catalog()


func test_roster_loads_without_errors() -> void:
	assert_eq(db.errors, [] as Array[String])
	assert_gt(db.players.size(), 32 * 20, "~20-24 real players per team")
	var m: PlayerData = db.players["mahomes_patrick"]
	assert_eq(m.team, "KC")
	assert_eq(m.attrs["thp"], 96, "explicit attribute kept")
	assert_gt(m.attrs["cth"], 0, "blank attribute filled from the profile")


func test_bad_rows_are_reported_not_fatal() -> void:
	var d := RosterDB.new()
	d.parse("\n".join(["# comment", HEADER,
			"a_b,Good Guy,KC,QB,1,80" + ",".repeat(16),
			"bad_pos,Bad Pos,KC,XX,1,80" + ",".repeat(16),
			"short,Too,Few",
			"a_b,Dup Guy,KC,QB,1,80" + ",".repeat(16),
			"bad_team,Bad Team,ZZZ,QB,1,80" + ",".repeat(16)]), ["KC"])
	assert_eq(d.players.size(), 1)
	assert_eq(d.errors.size(), 4)


func test_every_team_can_field_a_full_lineup() -> void:
	for abbr in TeamData.load_all():
		var e := db.team_entries(abbr)
		for slot in TeamRating.ALL_SLOTS:
			assert_true(e.has(slot), "%s missing %s" % [abbr, slot])


func test_card_tier_math() -> void:
	assert_eq(CardRules.tier_for_ovr(64), CardRules.Tier.BRONZE)
	assert_eq(CardRules.tier_for_ovr(69), CardRules.Tier.BRONZE)
	assert_eq(CardRules.tier_for_ovr(70), CardRules.Tier.SILVER)
	assert_eq(CardRules.tier_for_ovr(79), CardRules.Tier.SILVER)
	assert_eq(CardRules.tier_for_ovr(80), CardRules.Tier.GOLD)
	assert_eq(CardRules.tier_for_ovr(90), CardRules.Tier.ELITE)
	assert_eq(CardRules.tier_for_ovr(99), CardRules.Tier.ELITE)
	var attrs := CardRules.card_attrs({"spd": 90, "tha": 40}, 90, 60)
	assert_eq(attrs["spd"], 60)
	assert_eq(attrs["tha"], 40, "clamped at 40")
	assert_eq(CardRules.parse_card_id("mahomes_patrick_gold"), ["mahomes_patrick", CardRules.Tier.GOLD])
	assert_eq(CardRules.split_card_id("mahomes_patrick_prime"), ["mahomes_patrick", "prime"])
	assert_eq(CardRules.split_card_id("mahomes_patrick"), ["mahomes_patrick", "base"])
	assert_eq(CardRules.card_id("mahomes_patrick", CardRules.Tier.GOLD), "mahomes_patrick", "tier arg is legacy")


func test_base_card_is_the_real_rating() -> void:
	var dk: CardDef = db.cards["metcalf_dk"]
	assert_eq(dk.ovr, db.players["metcalf_dk"].ovr, "DK Metcalf's card is his real rating")
	assert_gte(dk.ovr, 84)
	assert_eq(dk.tier, CardRules.Tier.GOLD)
	var m: CardDef = db.cards["mahomes_patrick"]
	assert_eq(m.tier, CardRules.Tier.ELITE)
	assert_eq(m.attrs["thp"], 96, "base card attrs = real attrs")
	var prime: CardDef = db.cards["mahomes_patrick_prime"]
	assert_eq(prime.ovr, mini(m.ovr + CardRules.PRIME_BONUS, 99))
	assert_true(prime.is_prime())
	assert_gt(prime.quicksell, m.quicksell)
	for cid in db.cards:
		var c: CardDef = db.cards[cid]
		assert_eq(c.tier, CardRules.tier_for_ovr(c.ovr), "tier derived from OVR: %s" % cid)
		if c.is_prime():
			assert_gte(db.players[c.player_id].ovr, CardRules.PRIME_MIN_OVR, "only stars get Prime: %s" % cid)


func test_rating_distribution_is_madden_like() -> void:
	var tiers := [0, 0, 0, 0]
	for pid in db.players:
		var p: PlayerData = db.players[pid]
		if not p.generated:
			tiers[CardRules.tier_for_ovr(p.ovr)] += 1
	var n: int = tiers[0] + tiers[1] + tiers[2] + tiers[3]
	gut.p("real players by tier (B/S/G/E): %s of %d" % [tiers, n])
	assert_between(float(tiers[3]) / n, 0.02, 0.10, "90+ is rare")
	assert_between(float(tiers[2]) / n, 0.20, 0.45, "80-89 = good starters")
	assert_gt(tiers[0] + tiers[1], n / 2, "most players are below 80")


func test_young_players_have_potential() -> void:
	var rookie: PlayerData = db.players["jeanty_ashton"]
	assert_gt(rookie.pot, rookie.ovr, "a 21-year-old rookie can grow")
	var vet: PlayerData = db.players["kelce_travis"]
	assert_eq(vet.pot, vet.ovr, "veterans are what they are")
	assert_eq(CardRules.default_pot(64, 22), 64 + 13)
	assert_eq(CardRules.default_pot(80, 30), 80)
	assert_eq(CardRules.default_pot(90, 21), CardRules.POT_CAP)
	var d := RosterDB.new()
	d.parse("\n".join([HEADER + ",age,pot", "a_b,Young Guy,KC,QB,1,64" + ",".repeat(16) + ",22,",
			"c_d,Fixed Pot,KC,QB,2,64" + ",".repeat(16) + ",29,70"]), ["KC"])
	assert_eq(d.errors, [] as Array[String])
	assert_eq(d.players["a_b"].pot, 77)
	assert_eq(d.players["c_d"].pot, 70, "explicit pot wins")


func test_catalog_has_one_base_card_per_player() -> void:
	assert_true(db.cards.has("mahomes_patrick"))
	assert_false(db.cards.has("mahomes_patrick_bronze"), "no tier versions any more")
	for pid in db.players:
		assert_true(db.cards.has(pid), "base card for %s" % pid)


func test_team_ovr_weights_sum_to_one() -> void:
	var total := 0.0
	for s in TeamRating.WEIGHTS:
		total += TeamRating.WEIGHTS[s]
	assert_almost_eq(total, 1.0, 0.001)
	var all80 := {}
	for s in TeamRating.ALL_SLOTS:
		all80[s] = {"ovr": 80}
	assert_eq(TeamRating.team_ovr(all80), 80)


func test_auto_best_uses_each_player_once() -> void:
	var cands := [
		{"key": 1, "pos": "QB", "ovr": 90, "player": "a"},
		{"key": 2, "pos": "QB", "ovr": 85, "player": "a"},
		{"key": 3, "pos": "WR", "ovr": 88, "player": "b"},
		{"key": 4, "pos": "WR", "ovr": 80, "player": "b"},
		{"key": 5, "pos": "WR", "ovr": 70, "player": "c"},
	]
	var best := TeamRating.auto_best(cands)
	assert_eq(best["QB"]["key"], 1)
	assert_eq(best["WR1"]["key"], 3)
	assert_eq(best["WR2"]["key"], 5, "the other version of player b is skipped")


func test_starting_squad_every_team() -> void:
	var ovrs := {}
	for abbr in TeamData.load_all():
		var ids := Collection.starter_card_ids(db, abbr)
		var star := db.franchise_star(abbr)
		assert_has(ids, star.id, "%s gets its franchise star" % abbr)
		var above := 0
		for id in ids:
			var c: CardDef = db.cards[id]
			var p: PlayerData = db.players[c.player_id]
			assert_false(p.generated, "%s starter %s is a real player" % [abbr, id])
			if c.ovr > Collection.STARTER_CAP_MAX:
				above += 1
		assert_eq(above, 1, "%s: only the franchise star is above %d" % [abbr, Collection.STARTER_CAP_MAX])
		var prof := Profile.new()
		Collection.grant_starters(prof, db, abbr)
		for s in TeamRating.ALL_SLOTS:
			assert_true(prof.lineup.has(s), "%s starter lineup fills %s" % [abbr, s])
		var ovr := Collection.team_ovr(prof, db)
		ovrs[abbr] = ovr
		assert_between(ovr, 68, 74, "%s starting team OVR" % abbr)
		assert_has(prof.pending_packs, Collection.STARTER_PACK, "a free starter pack waits")
	gut.p("starting team OVRs: %s" % ovrs)


func test_starter_squad_kc() -> void:
	var prof := Profile.new()
	Collection.grant_starters(prof, db, "KC")
	assert_eq(prof.franchise_team, "KC")
	var m := -1
	for e in prof.cards:
		if e["def"] == "mahomes_patrick":
			m = int(e["uid"])
	assert_ne(m, -1, "KC's franchise star is Mahomes")
	assert_eq(int(prof.lineup["QB"]), m)
	assert_gt(Collection.chemistry(prof, db), 1.9, "mostly franchise players")


func test_difficulty_rescales_opponents() -> void:
	var rookie := TeamRating.opponent_effective_ovr(65, 0, 80, 78)
	var legend := TeamRating.opponent_effective_ovr(65, 3, 80, 78)
	assert_lt(rookie, legend)
	assert_eq(legend, 65 + 7 + 1)
	var e := {"QB": {"attrs": {"thp": 90}, "ovr": 90}}
	var scaled := TeamRating.rescale_entries(e, 90, 72)
	assert_eq(scaled["QB"]["attrs"]["thp"], 72)


func test_profile_round_trip_and_migration() -> void:
	var prof := Profile.new()
	prof.franchise_team = "BUF"
	var uid := prof.add_card("allen_josh", 123)
	prof.lineup["QB"] = uid
	prof.coins = 777
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(prof.to_dict())))
	assert_eq(back.to_dict(), prof.to_dict())
	var v0 := {"team": "SF", "cards": [{"def": "x_bronze"}, {"def": "y_bronze"}], "coins": 50}
	var mig := Profile.from_dict(v0)
	assert_eq(mig.franchise_team, "SF")
	assert_eq(mig.cards.size(), 2)
	assert_ne(mig.cards[0]["uid"], mig.cards[1]["uid"])
	assert_gt(mig.next_uid, int(mig.cards[1]["uid"]))
	assert_eq(mig.cards[0]["def"], "x", "legacy tier suffix dropped")


func test_v1_save_migrates_to_real_cards() -> void:
	var v1 := {"version": 1, "franchise_team": "KC", "coins": 999, "next_uid": 4,
			"cards": [{"uid": 1, "def": "mahomes_patrick_silver", "t": 5, "locked": true, "boost": 2},
					{"uid": 2, "def": "gen_kc_ol_1_bronze", "t": 5, "locked": false, "boost": 0},
					{"uid": 3, "def": "kelce_travis_elite", "t": 5, "locked": false, "boost": 0}],
			"lineup": {"QB": 1, "TE": 3}, "stats": {"games": 12, "wins": 7}}
	var p := Profile.from_dict(JSON.parse_string(JSON.stringify(v1)))
	assert_eq(p.version, Profile.VERSION)
	assert_eq(p.cards[0]["def"], "mahomes_patrick")
	assert_eq(p.cards[0]["boost"], 2, "training kept")
	assert_true(p.cards[0]["locked"])
	assert_eq(p.cards[1]["def"], "gen_kc_ol_1")
	assert_eq(p.cards[2]["def"], "kelce_travis")
	assert_eq(p.cards[0]["xp"], 0)
	assert_eq(int(p.lineup["QB"]), 1)
	assert_eq(p.coins, 999)
	assert_eq(p.stats["wins"], 7)
	assert_eq(int(p.coach["xp"]), 1200, "coach XP back-filled from games")
	assert_eq(int(p.coach["level"]), ProgressionRules.level_from_xp(1200))
	assert_not_null(db.cards.get(p.cards[0]["def"]), "migrated id exists in the catalog")
	assert_eq(Collection.card_ovr(db, p.cards[0]), mini(db.cards["mahomes_patrick"].ovr + 2, 99))
	# Round trip of the new fields.
	p.objectives = {"day": 3, "week": 1, "progress": {"d_win": 1}, "claimed": {"m_first_win": true},
			"totals": {"wins": 7}}
	p.pending_packs.append("starter")
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.to_dict(), p.to_dict())


func test_save_is_atomic_and_falls_back_to_backup() -> void:
	var path := "user://test_save.json"
	for s in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + s):
			DirAccess.remove_absolute(path + s)
	var p1 := Profile.new()
	p1.franchise_team = "KC"
	p1.coins = 100
	assert_true(SaveManager.write_profile(p1, path))
	p1.coins = 200
	assert_true(SaveManager.write_profile(p1, path))
	assert_true(FileAccess.file_exists(path + ".bak"))
	assert_eq(SaveManager.load_profile(path).coins, 200)
	# Corrupt the main file: the backup (previous save) loads instead.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	assert_eq(SaveManager.load_profile(path).coins, 100)
	assert_false(SaveManager.load_profile("user://nope.json").has_team())
