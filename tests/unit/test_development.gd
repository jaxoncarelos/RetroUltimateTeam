extends GutTest
## Player development: young cards gain XP from games (and training) and grow toward their
## potential; veterans don't; tier follows the developed OVR.

var db: RosterDB


func before_all() -> void:
	db = GameData.db


## A young, low-rated real player with plenty of room.
func _prospect_id() -> String:
	var best := ""
	var room := 0
	var ids: Array = db.players.keys()
	ids.sort()
	for pid in ids:
		var p: PlayerData = db.players[pid]
		if not p.generated and p.ovr < 70 and p.pot - p.ovr > room:
			best = pid
			room = p.pot - p.ovr
	return best


func test_prospect_grows_to_potential_then_stops() -> void:
	var pid := _prospect_id()
	assert_ne(pid, "")
	var p: PlayerData = db.players[pid]
	var prof := Profile.new()
	var uid := prof.add_card(pid)
	var e := prof.find(uid)
	assert_eq(Collection.card_ovr(db, e), p.ovr)
	assert_eq(Collection.dev_room(db, e), p.pot - p.ovr)
	assert_eq(Collection.card_tier(db, e), CardRules.Tier.BRONZE)
	var need := CardRules.xp_to_next(0)
	assert_eq(Collection.add_card_xp(db, e, need - 1), 0)
	assert_eq(Collection.add_card_xp(db, e, 1), 1, "exactly enough XP = +1 OVR")
	assert_eq(Collection.card_ovr(db, e), p.ovr + 1)
	Collection.add_card_xp(db, e, 1000000)
	assert_eq(Collection.card_ovr(db, e), p.pot, "grows to potential")
	assert_eq(Collection.dev_room(db, e), 0)
	assert_eq(int(e["xp"]), 0, "maxed cards don't bank XP")
	assert_eq(Collection.add_card_xp(db, e, 5000), 0)
	assert_eq(Collection.card_tier(db, e), CardRules.tier_for_ovr(p.pot), "tier follows the developed OVR")
	var info := Collection.card_info(prof, db, e)
	assert_eq(info["ovr"], p.pot)
	assert_eq(info["base_ovr"], p.ovr)
	assert_false(info["prospect"])
	assert_eq(info["xp_next"], 0)


func test_veterans_do_not_develop() -> void:
	var prof := Profile.new()
	var e := prof.find(prof.add_card("kelce_travis"))
	assert_eq(Collection.dev_room(db, e), 0)
	assert_eq(Collection.add_card_xp(db, e, 100000), 0)
	assert_eq(Collection.card_ovr(db, e), db.players["kelce_travis"].ovr)


func test_games_develop_the_lineup_more_than_the_bench() -> void:
	var prof := Profile.new()
	Collection.grant_starters(prof, db, "KC")
	var bench := prof.add_card(_prospect_id())
	var young_starter := -1
	for s in prof.lineup:
		var e := prof.find(int(prof.lineup[s]))
		if Collection.dev_room(db, e) > 0:
			young_starter = int(e["uid"])
			break
	assert_ne(young_starter, -1, "the starting squad has prospects")
	var ups: Array[Dictionary] = []
	for g in 20:
		ups.append_array(Collection.award_xp(prof, db, g % 2 == 0))
	assert_gt(ups.size(), 0, "level-ups are reported")
	var s_dev := int(prof.find(young_starter)["dev"])
	var b_dev := int(prof.find(bench)["dev"])
	assert_gt(s_dev, b_dev, "starters develop faster than the bench")
	assert_between(s_dev, 2, 8, "a season of games is worth a few OVR")
	for u in ups:
		assert_gt(int(u["to"]), int(u["from"]))


func test_starting_team_ovr_rises_with_development() -> void:
	var prof := Profile.new()
	Collection.grant_starters(prof, db, "NYG")
	var before := Collection.team_ovr(prof, db)
	for g in 60:
		Collection.award_xp(prof, db, true)
	Collection.auto_lineup(prof, db)
	assert_gt(Collection.team_ovr(prof, db), before, "the rookies grew")


func test_training_adds_boost_and_development_xp() -> void:
	var pid := _prospect_id()
	var prof := Profile.new()
	var t := prof.add_card(pid)
	var f := prof.add_card(pid)
	assert_true(EconomyRules.train(prof, db, t, f))
	var e := prof.find(t)
	assert_eq(int(e["boost"]), 1)
	assert_gt(int(e["xp"]) + int(e["dev"]), 0, "training also develops")
	assert_eq(Collection.card_ovr(db, e), db.players[pid].ovr + 1 + int(e["dev"]))
	var entries := {"QB": {}}
	prof.lineup["QB"] = t
	entries = Collection.lineup_entries(prof, db)
	assert_eq(entries["QB"]["ovr"], Collection.card_ovr(db, e), "match lineup uses the developed OVR")
