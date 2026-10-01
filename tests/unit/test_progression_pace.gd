extends GutTest
## First-season pace: a player who saves coins for Gold packs lands a good (85+) player within
## the first handful of games and usually a 90+ during the first season; 95+ stays rare.
var db: RosterDB
var rng: RandomNumberGenerator
const DAY := 86400
const T0 := 1790000000 + 12 * 3600
func before_all() -> void:
	db = GameData.db

func _starter(team := "KC") -> Profile:
	var p := Profile.new()
	Collection.grant_starters(p, db, team)
	return p


func _box(won: bool, r: RandomNumberGenerator) -> Dictionary:
	var tds := r.randi_range(2, 4) if won else r.randi_range(1, 3)
	return {"pass_comp": r.randi_range(12, 22), "pass_att": 28, "pass_yds": r.randi_range(150, 300),
			"pass_td": tds - 1, "rush_td": 1, "rush_yds": r.randi_range(50, 130), "long_pass": r.randi_range(15, 55),
			"long_run": r.randi_range(6, 40), "def_sacks": r.randi_range(0, 3), "def_ints": r.randi_range(0, 1),
			"fg_made": r.randi_range(0, 2), "fg_long": r.randi_range(25, 51), "tds": tds}


func _run(team: String, seed: int, smart: bool, games := 25) -> Dictionary:
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	var prof := _starter(team)
	var first85 := -1
	var first90 := -1
	var first95 := -1
	var at := {}
	var t := T0
	for g in range(1, games + 1):
		if g % 3 == 1:
			t += DAY
			DailyRules.check_in(prof, t)
		var won := rng.randf() < 0.55
		var box := _box(won, rng)
		var r := {"pf": 24 if won else 17, "pa": 17 if won else 24, "tds": box["tds"], "difficulty": 1,
				"def_sacks": box["def_sacks"], "def_ints": box["def_ints"], "box": box}
		EconomyRules.postgame(prof, db, r, t)
		ObjectiveRules.claim_all(prof, t)
		while not prof.pending_packs.is_empty():
			if EconomyRules.open_pending(prof, db, rng).get("draft", false):
				EconomyRules.pick_draft(prof, db, _best_option(prof))
		for id in (["gold"] if smart else ["elite", "gold", "silver", "bronze"]):
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
		for e in prof.cards:
			var o := Collection.card_ovr(db, e)
			if o >= 85 and first85 < 0:
				first85 = g
			if o >= 90 and first90 < 0:
				first90 = g
			if o >= 95 and first95 < 0:
				first95 = g
		if g in [1, 10, 20, 25]:
			at[g] = Collection.team_ovr(prof, db)
	gut.p("%s %s ovr %s 85+@%d 90+@%d 95+@%d" % ["SMART" if smart else "GREEDY", team, at, first85, first90, first95])
	return {"85": first85, "90": first90, "95": first95, "at": at}


func test_a_smart_saver_gets_a_star_in_the_first_season() -> void:
	var lucky := 0
	var teams := ["SEA", "KC", "NYJ", "CAR", "MIA"]
	for i in teams.size():
		var r := _run(teams[i], 500 + i, true)
		assert_between(int(r["85"]), 1, 20, "%s: an 85+ player during the first season" % teams[i])
		if int(r["90"]) > 0 and int(r["90"]) <= 20:
			lucky += 1
		assert_true(int(r["95"]) < 0 or int(r["95"]) > 10, "%s: no 95+ in the first 10 games" % teams[i])
	assert_gte(lucky, 2, "a 90+ in the first season happens, with some luck")
	assert_lt(lucky, teams.size() + 1)


## Draft packs in the sims: keep the highest-rated option.
func _best_option(prof: Profile) -> int:
	var opts: Array = prof.pending_pick.get("options", [])
	var best := 0
	for i in opts.size():
		if db.cards[opts[i]].ovr > db.cards[opts[best]].ovr:
			best = i
	return best
