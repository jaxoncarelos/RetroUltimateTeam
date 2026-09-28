extends GutTest
## Phase 4: roster import, card tiers, team OVR, lineups, difficulty rescale, profile/save.

const HEADER := "id,name,team,pos,jersey,ovr,spd,acc,str,awr,thp,tha,cth,rte,car,elu,blk,tak,cov,prs,kpw,kac"

var db: RosterDB


func before_each() -> void:
	db = RosterDB.new()
	db.load_file(RosterDB.ROSTER_PATH, TeamData.load_all().keys())
	db.fill_depth(TeamData.load_all().keys())
	db.build_catalog()


func test_roster_loads_without_errors() -> void:
	assert_eq(db.errors, [] as Array[String])
	assert_gt(db.players.size(), 200)
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
	assert_eq(CardRules.card_ovr(CardRules.Tier.ELITE, 99), 99)
	assert_eq(CardRules.card_ovr(CardRules.Tier.BRONZE, 60), 55)
	assert_eq(CardRules.card_ovr(CardRules.Tier.GOLD, 80), int(round(lerpf(75, 84, 20.0 / 39.0))))
	assert_false(CardRules.eligible(CardRules.Tier.GOLD, 74))
	assert_true(CardRules.eligible(CardRules.Tier.ELITE, 85))
	var attrs := CardRules.card_attrs({"spd": 90, "tha": 40}, 90, 60)
	assert_eq(attrs["spd"], 60)
	assert_eq(attrs["tha"], 40, "clamped at 40")
	assert_eq(CardRules.parse_card_id("mahomes_patrick_gold"), ["mahomes_patrick", CardRules.Tier.GOLD])


func test_catalog_has_versions_per_eligible_tier() -> void:
	assert_true(db.cards.has("mahomes_patrick_elite"))
	assert_true(db.cards.has("mahomes_patrick_bronze"))
	var gen_ids := db.cards.keys().filter(func(k: String) -> bool: return k.begins_with("gen_"))
	for k in gen_ids:
		assert_true(k.ends_with("_bronze"), "generated depth only exists as bronze: %s" % k)


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


func test_starter_cards_top5_silver() -> void:
	var ids := Collection.starter_card_ids(db, "KC")
	var silver := ids.filter(func(i: String) -> bool: return i.ends_with("_silver"))
	assert_eq(silver.size(), 5)
	assert_has(ids, "mahomes_patrick_silver")
	var prof := Profile.new()
	Collection.grant_starters(prof, db, "KC")
	assert_eq(prof.franchise_team, "KC")
	for s in TeamRating.ALL_SLOTS:
		assert_true(prof.lineup.has(s), "starter lineup fills %s" % s)
	var ovr := Collection.team_ovr(prof, db)
	assert_between(ovr, 55, 72, "starting team OVR is low-tier")
	assert_gt(Collection.chemistry(prof, db), 2.9, "all franchise players = max chemistry")


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
	var uid := prof.add_card("allen_josh_silver", 123)
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
