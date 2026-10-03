class_name RtgFlow
extends RefCounted
## Road to Glory screen glue (the parts of the career that need the league data in GameData):
## team ratings for the draft and the schedule, the draft itself, the next game's config,
## applying a finished game (XP, trust, the league week, coins to your wallet) and the
## season's close. Pure rules live in RtgRules.

## Coins paid into your (shared) wallet per RTG game: base + grade bonus.
const GAME_COINS := 80
const GRADE_COINS := {"A": 120, "B": 70, "C": 30}


static func team_ovrs() -> Dictionary:
	var out := {}
	for abbr in GameData.teams:
		out[abbr] = GameData.db.team_ovr(abbr)
	return out


## Each team's real starter OVR at `slot` (the draft's "need").
static func starter_ovrs(slot: String) -> Dictionary:
	var out := {}
	for abbr in GameData.teams:
		out[abbr] = int(GameData.db.team_entries(abbr).get(slot, {}).get("ovr", 70))
	return out


## League strengths for a season, with your team moved by your rating.
static func strengths(rtg: Dictionary) -> Dictionary:
	var s := team_ovrs()
	var you := str(rtg["team"])
	if s.has(you):
		var starter := int(GameData.db.team_entries(you).get(RtgRules.slot_of(rtg), {}).get("ovr", 70))
		s[you] = RtgRules.team_strength(rtg, int(s[you]), starter)
	return s


## Runs the draft once (kept in rtg.pending_draft so leaving and coming back shows the same).
static func draft(rtg: Dictionary, combine: float) -> Dictionary:
	if rtg.has("pending_draft"):
		return rtg["pending_draft"]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d := RtgRules.draft(rtg, combine, GameData.teams, team_ovrs(), starter_ovrs(RtgRules.slot_of(rtg)), rng)
	rtg["pending_draft"] = d
	return d


## After the draft-day reveal: sign, start season 1.
static func sign_rookie(rtg: Dictionary) -> void:
	var d: Dictionary = rtg.get("pending_draft", {})
	if d.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	rtg["team"] = d["team"]
	RtgRules.sign_rookie(rtg, d, GameData.teams, strengths(rtg), Settings.season_games, rng)
	rtg.erase("pending_draft")


static func game_config(rtg: Dictionary) -> Dictionary:
	var g := RtgRules.next_game(rtg)
	if g.is_empty():
		return {}
	return RtgRules.game_config(rtg, Settings.difficulty, GameFlow.roll_conditions(str(g["home"])))


## Applies a finished (or simmed) game to the career and the wallet. Returns RtgRules.apply_game's
## summary plus "coins".
static func apply_game(prof: Profile, r: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := RtgRules.apply_game(prof.rtg, r, GameData.teams, rng)
	var share := RtgRules.played_share(r)
	var coins := int(round((GAME_COINS + int(GRADE_COINS.get(str(out["grade"]).left(1), 0))) * lerpf(0.5, 1.0, share)))
	for g in out["goals_done"]:
		coins += int(g["coins"])
	prof.coins += coins
	prof.stats["coins_earned"] = int(prof.stats.get("coins_earned", 0)) + coins
	out["coins"] = coins
	SaveManager.save()
	return out


## Season over: awards etc. (once; kept in rtg.season_close).
static func close_season(prof: Profile) -> Dictionary:
	var rtg := prof.rtg
	if rtg.has("season_close"):
		return rtg["season_close"]
	var res := RtgRules.close_season(rtg)
	prof.coins += int(res["coins"])
	res["card"] = sync_card(prof)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if RtgRules.contract_up(rtg):
		rtg["offers"] = RtgRules.contract_offers(rtg, GameData.teams, team_ovrs(), rng)
	rtg["season_close"] = res
	SaveManager.save()
	return res


## Next season (after the offseason screen): aging, contract, new schedule.
static func next_season(prof: Profile) -> Dictionary:
	var rtg := prof.rtg
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	rtg.erase("season_close")
	var changes := RtgRules.next_season(rtg, GameData.teams, {}, Settings.season_games, rng)
	# Schedule strengths after aging (your rating moves your team).
	(rtg["season"] as Dictionary)["ovr"] = strengths(rtg)
	GameData.register_rtg(prof)
	SaveManager.save()
	return changes


## Retire: the career becomes a legend.
static func retire(prof: Profile, reason: String) -> Dictionary:
	var legend := RtgRules.retire(prof.rtg, reason)
	prof.rtg_legends.append(legend)
	prof.rtg = {}
	GameData.register_rtg(prof)
	SaveManager.save()
	return legend


## Re-registers your Road to Glory card(s) and, after a finished season, makes sure you own
## your player's card in Ultimate Team (locked: he is yours for good). Returns true when the
## card was just added.
static func sync_card(prof: Profile) -> bool:
	GameData.register_rtg(prof)
	var spec := RtgRules.card_player(prof.rtg)
	if spec.is_empty() or (prof.rtg.get("career", []) as Array).is_empty():
		return false
	var id := str(spec["id"])
	for c in prof.cards:
		if str(c["def"]) == id:
			return false
	var uid := prof.add_card(id, int(Time.get_unix_time_from_system()))
	prof.find(uid)["locked"] = true
	return true
