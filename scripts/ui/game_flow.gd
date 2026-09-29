class_name GameFlow
extends RefCounted
## Screen-flow helpers shared by the hub, mode select, pre-match and results screens:
## which game is "next" (season week / playoff game / the next quick-match opponent) and
## applying a finished match to the profile (EconomyRules.postgame + ModeResults).


## The next few quick-match opponents, stable until a game is played (so the hub strip
## and the pre-match screen agree).
static func next_quick_opponents(prof: Profile, n := 3) -> Array[String]:
	var others: Array = GameData.teams.keys()
	others.sort()
	others.erase(prof.franchise_team)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [prof.franchise_team, int(prof.stats.get("games", 0))])
	var out: Array[String] = []
	# Games already played shift the window so the strip scrolls one team per game.
	var start := rng.randi() % maxi(others.size(), 1)
	for i in n:
		if others.is_empty():
			break
		out.append(others[(start + i * 7) % others.size()])
	return out


static func next_quick_config(prof: Profile) -> Dictionary:
	var opp := next_quick_opponents(prof, 1)
	return {"home": prof.franchise_team, "away": opp[0] if not opp.is_empty() else "PHI", "from_hub": true,
			"difficulty": Settings.difficulty, "mode": "quick"}


## The season game the player plays next ({} if no season game is waiting).
static func season_game_config(prof: Profile) -> Dictionary:
	var s := prof.season
	if s.is_empty() or s.get("team", "") != prof.franchise_team:
		return {}
	var you: String = s["team"]
	match str(s.get("phase", "")):
		"regular":
			var w := int(s["week"])
			if w >= (s["weeks"] as Array).size():
				return {}
			for g in s["weeks"][w]:
				if you in g:
					return _cfg(prof, g, "WEEK %d" % (w + 1))
		"playoffs":
			var mine := SeasonRules.my_playoff_game(s)
			if not mine.is_empty():
				return _cfg(prof, mine, SeasonRules.ROUND_NAMES[int(s["playoffs"]["round"])])
	return {}


static func _cfg(prof: Profile, g: Array, label: String) -> Dictionary:
	var you := prof.franchise_team
	var opp: String = g[1] if g[0] == you else g[0]
	return {"home": you, "away": opp, "from_hub": true, "difficulty": Settings.difficulty, "mode": "season",
			"label": label, "extra": {"home": g[0], "away": g[1], "label": label}}


## Starts a new season for the franchise team (year + 1). Every hub PLAY then plays the next
## league game, and the other teams' games are simulated each week.
static func start_season(prof: Profile) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var strengths := {}
	for a in GameData.teams:
		strengths[a] = GameData.db.team_ovr(a)
	strengths[prof.franchise_team] = Collection.team_ovr(prof, GameData.db)
	var year := int(prof.season.get("year", 0)) + 1
	prof.season = SeasonRules.new_season(GameData.teams, prof.franchise_team, Settings.season_games, strengths, rng, year)


## True when the profile has no season for its current franchise (fresh career, or the team changed).
static func needs_season(prof: Profile) -> bool:
	return prof.has_team() and (prof.season.is_empty() or prof.season.get("team", "") != prof.franchise_team)


## What the hub's PLAY button starts: the waiting season game, else a quick match.
static func next_game_config(prof: Profile) -> Dictionary:
	var s := season_game_config(prof)
	return s if not s.is_empty() else next_quick_config(prof)


## Applies a finished match (MatchController.match_result()) to the profile and saves.
## Returns EconomyRules.postgame()'s dictionary plus "coins_before", "coins_after",
## "coach_before" (level progress before the match), "mode_msg" and "result".
static func apply_result(prof: Profile, r: Dictionary) -> Dictionary:
	var coins_before := prof.coins
	var coach_before := ProgressionRules.level_progress(int(prof.coach.get("xp", 0)))
	var out := EconomyRules.postgame(prof, GameData.db, r)
	out["mode_msg"] = ModeResults.apply(r, prof, GameData.db)
	out["coins_before"] = coins_before
	out["coins_after"] = prof.coins
	out["coach_before"] = coach_before
	out["result"] = r
	SaveManager.save()
	return out


## A simulated result for SIM GAME (score model from both teams' OVR).
static func sim_result(prof: Profile, cfg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var you := prof.franchise_team
	var opp: String = cfg.get("away", "PHI")
	var gs := GameState.new(you, opp)
	gs.start_possession(opp, 25.0)   # your team receives the opening kickoff
	GameSim.finish(gs, {you: Collection.team_ovr(prof, GameData.db), opp: GameData.db.team_ovr(opp)}, rng)
	var b := gs.box_score(you)
	return {"team": you, "opponent": opp, "pf": int(b["pf"]), "pa": int(b["pa"]), "forfeit": false, "tds": int(b["tds"]),
			"def_ints": int(b["def_ints"]), "def_sacks": int(b["def_sacks"]),
			"difficulty": int(cfg.get("difficulty", Settings.difficulty)),
			"mode": str(cfg.get("mode", "quick")), "extra": cfg.get("extra", {}), "came_back": false,
			"challenge_won": false, "simulated": true, "box": b}


## First reward pack waiting to be opened, as a pack-opening config ({} if none).
static func open_pending_config(prof: Profile, back := SceneRouter.HUB) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var res := EconomyRules.open_pending(prof, GameData.db, rng, int(Time.get_unix_time_from_system()))
	if res.is_empty():
		return {}
	SaveManager.save()
	return {"uids": res["uids"], "title": res["title"], "pack": res["pack"], "back": back}
