class_name ModeResults
extends RefCounted
## Applies a finished match to the mode it came from (season week / playoff game /
## challenge). Returns a line for the hub's message ("" = nothing). Pure except for the
## rng it creates.

const PLAYOFF_BERTH_COINS := 500
const PLAYOFF_WIN_COINS := 1000
const SUPER_BOWL_COINS := 3000


static func apply(r: Dictionary, profile: Profile, db: RosterDB) -> String:
	match str(r.get("mode", "")):
		"season":
			return _season(r, profile, db)
		"challenge":
			return _challenge(r, profile, db)
	return ""


static func _season(r: Dictionary, profile: Profile, db: RosterDB) -> String:
	var s := profile.season
	if s.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var you: String = s["team"]
	var won: bool = int(r["pf"]) > int(r["pa"]) and not r.get("forfeit", false)
	var extra: Dictionary = r.get("extra", {})
	var home: String = extra.get("home", you)
	var away: String = extra.get("away", r["opponent"])
	var hs := int(r["pf"]) if home == you else int(r["pa"])
	var as_ := int(r["pa"]) if home == you else int(r["pf"])
	if r.get("forfeit", false):
		hs = 0 if home == you else 21
		as_ = 21 if home == you else 0
	if s["phase"] == "regular":
		SeasonRules.sim_week(s, rng)
		SeasonRules.record_game(s, home, away, hs, as_)
		s["week"] = int(s["week"]) + 1
		if int(s["week"]) >= int(s["games"]):
			SeasonRules.start_playoffs(s, GameData.teams)
			if s["playoffs"]["made_it"]:
				profile.coins += PLAYOFF_BERTH_COINS
				ObjectiveRules.record_event(profile, "playoffs")
				return "REGULAR SEASON OVER: PLAYOFFS! +%d COINS" % PLAYOFF_BERTH_COINS
			return "REGULAR SEASON OVER: NO PLAYOFFS THIS YEAR"
		return "SEASON: WEEK %d DONE" % int(s["week"])
	if s["phase"] == "playoffs":
		var winners := SeasonRules.sim_playoff_round(s, rng)
		var mine := SeasonRules.my_playoff_game(s)
		var msg := ""
		if not mine.is_empty():
			var key := "%s-%s" % [mine[0], mine[1]]
			winners[key] = you if won else (mine[1] if mine[0] == you else mine[0])
			if won:
				profile.coins += PLAYOFF_WIN_COINS
				msg = "PLAYOFF WIN! +%d COINS" % PLAYOFF_WIN_COINS
			else:
				msg = "ELIMINATED IN THE %s" % SeasonRules.ROUND_NAMES[int(s["playoffs"]["round"])]
		SeasonRules.advance_round(s, winners)
		if s["phase"] == "done" and s["playoffs"]["champion"] == you:
			ObjectiveRules.record_event(profile, "titles")
			var pack := PackCatalog.get_pack("elite")
			EconomyRules.grant_pack(profile, pack, db, rng)
			profile.coins += SUPER_BOWL_COINS
			var champ := EconomyRules.champion_reward(profile, db)
			msg = "SUPER BOWL CHAMPIONS! +%d COINS + ELITE PACK" % SUPER_BOWL_COINS
			if champ["card"] != "":
				msg += " + 99 CHAMP %s" % str(champ["name"]).to_upper()
			elif int(champ["coins"]) > 0:
				msg += " + %d BONUS COINS (CHAMP CARD ALREADY OWNED)" % int(champ["coins"])
		return msg
	return ""


static func _challenge(r: Dictionary, profile: Profile, db: RosterDB) -> String:
	var extra: Dictionary = r.get("extra", {})
	var id: String = extra.get("challenge", "")
	if id == "" or not r.get("challenge_won", false):
		return "CHALLENGE FAILED - TRY AGAIN"
	var done: Dictionary = profile.challenges.get("done", {})
	var first := not done.has(id)
	done[id] = true
	profile.challenges["done"] = done
	var def := ChallengeRules.find(id, int(extra.get("daily_seed", 0)))
	ObjectiveRules.record_event(profile, "challenges")
	if not first:
		return "CHALLENGE COMPLETE (REWARD ALREADY CLAIMED)"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	profile.coins += int(def.get("coins", 0))
	var pack_id: String = def.get("pack", "")
	var msg := "CHALLENGE COMPLETE! +%d COINS" % int(def.get("coins", 0))
	if pack_id != "":
		EconomyRules.grant_pack(profile, PackCatalog.get_pack(pack_id), db, rng)
		msg += " + %s" % PackCatalog.get_pack(pack_id).display_name
	return msg
