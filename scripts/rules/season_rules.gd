class_name SeasonRules
extends RefCounted
## Season mode (PLAN.md §6): schedule for the whole league, a quick score model for games
## the player isn't in, standings, and a 7-team-per-conference playoff to the Super Bowl.
## State lives in a plain Dictionary (Profile.season) so it saves as JSON. Pure logic.
##
## season = {year, games, week, weeks: [[[home, away], ...], ...], results: [[home, away, hs, as], ...],
##           ovr: {abbr: int}, phase: "regular"|"playoffs"|"done", team: your abbr,
##           playoffs: {round, seeds: {AFC: [...], NFC: [...]}, games: [[home, away], ...], log: [...],
##                      champion, you_out}, rewards_log: [...]}

const ROUND_NAMES := ["", "WILD CARD", "DIVISIONAL", "CONFERENCE", "SUPER BOWL"]


static func new_season(teams: Dictionary, you: String, games: int, strengths: Dictionary, rng: RandomNumberGenerator,
		year := 1) -> Dictionary:
	var abbrs: Array = teams.keys()
	abbrs.sort()
	return {
		"year": year, "games": games, "week": 0, "weeks": make_schedule(abbrs, games, rng),
		"results": [], "ovr": strengths.duplicate(), "phase": "regular", "team": you,
		"playoffs": {}, "rewards_log": [],
	}


## `games` weeks; every week each team plays once (random pairings, avoiding rematches
## when possible, alternating home/away).
static func make_schedule(abbrs: Array, games: int, rng: RandomNumberGenerator) -> Array:
	var weeks: Array = []
	var met := {}
	var home_count := {}
	for a in abbrs:
		home_count[a] = 0
	for w in games:
		var best: Array = []
		var best_repeats := 9999
		for attempt in 30:
			var pool: Array = abbrs.duplicate()
			_shuffle(pool, rng)
			var pairs: Array = []
			var repeats := 0
			while pool.size() >= 2:
				var a: String = pool.pop_back()
				var pick := pool.size() - 1
				for i in range(pool.size() - 1, -1, -1):
					if not met.has(_key(a, pool[i])):
						pick = i
						break
				var b: String = pool[pick]
				pool.remove_at(pick)
				if met.has(_key(a, b)):
					repeats += 1
				pairs.append([a, b])
			if repeats < best_repeats:
				best_repeats = repeats
				best = pairs
			if repeats == 0:
				break
		var week: Array = []
		for p in best:
			var a: String = p[0]
			var b: String = p[1]
			met[_key(a, b)] = true
			if home_count[a] <= home_count[b]:
				week.append([a, b])
				home_count[a] += 1
			else:
				week.append([b, a])
				home_count[b] += 1
		weeks.append(week)
	return weeks


static func _key(a: String, b: String) -> String:
	return a + "-" + b if a < b else b + "-" + a


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Quick score model: touchdowns and field goals drawn around an expected score that
## shifts with the OVR gap (+1.5 home). Never returns a tie (overtime field goal).
static func sim_score(ovr_home: int, ovr_away: int, rng: RandomNumberGenerator) -> Array:
	var gap := (ovr_home - ovr_away) + 1.5
	var exp_home := clampf(22.0 + gap * 0.7, 6.0, 45.0)
	var exp_away := clampf(22.0 - gap * 0.7, 6.0, 45.0)
	var h := _points(exp_home, rng)
	var a := _points(exp_away, rng)
	if h == a:
		if rng.randf() < 0.5 + gap * 0.02:
			h += 3
		else:
			a += 3
	return [h, a]


## Points from `expected` (TD/FG mix drawn around it); used to sim the rest of a game.
static func sim_points(expected: float, rng: RandomNumberGenerator) -> int:
	return _points(expected, rng)


static func _points(expected: float, rng: RandomNumberGenerator) -> int:
	var tds := _poisson(expected * 0.72 / 7.0, rng)
	var fgs := _poisson(expected * 0.28 / 3.0, rng)
	return tds * 7 + fgs * 3


static func _poisson(lambda: float, rng: RandomNumberGenerator) -> int:
	var l := exp(-lambda)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l:
			return k
		k += 1
	return k


## Sims every game of the current week except the player's, records them, returns the
## player's pairing [home, away] (or [] if none).
static func sim_week(season: Dictionary, rng: RandomNumberGenerator) -> Array:
	var you: String = season["team"]
	var mine: Array = []
	for g in season["weeks"][season["week"]]:
		if you in g:
			mine = g
			continue
		var sc := sim_score(int(season["ovr"].get(g[0], 75)), int(season["ovr"].get(g[1], 75)), rng)
		season["results"].append([g[0], g[1], sc[0], sc[1]])
	return mine


static func record_game(season: Dictionary, home: String, away: String, hs: int, as_: int) -> void:
	season["results"].append([home, away, hs, as_])


## abbr -> {w, l, t, pf, pa}
static func standings(season: Dictionary, abbrs: Array) -> Dictionary:
	var out := {}
	for a in abbrs:
		out[a] = {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}
	for r in season["results"]:
		var h: String = r[0]
		var a: String = r[1]
		var hs := int(r[2])
		var as_ := int(r[3])
		if not out.has(h) or not out.has(a):
			continue
		out[h]["pf"] += hs
		out[h]["pa"] += as_
		out[a]["pf"] += as_
		out[a]["pa"] += hs
		if hs > as_:
			out[h]["w"] += 1
			out[a]["l"] += 1
		elif as_ > hs:
			out[a]["w"] += 1
			out[h]["l"] += 1
		else:
			out[h]["t"] += 1
			out[a]["t"] += 1
	return out


static func win_pct(r: Dictionary) -> float:
	var g := int(r["w"]) + int(r["l"]) + int(r["t"])
	return 0.0 if g == 0 else (int(r["w"]) + 0.5 * int(r["t"])) / g


## Sorts team abbrs best-first by win %, then point differential, then points scored.
static func rank(abbrs: Array, table: Dictionary) -> Array:
	var out := abbrs.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ra: Dictionary = table[a]
		var rb: Dictionary = table[b]
		if win_pct(ra) != win_pct(rb):
			return win_pct(ra) > win_pct(rb)
		var da := int(ra["pf"]) - int(ra["pa"])
		var db_ := int(rb["pf"]) - int(rb["pa"])
		if da != db_:
			return da > db_
		return int(ra["pf"]) > int(rb["pf"]))
	return out


## 7 seeds for a conference: 4 division winners (1-4), then the best 3 others.
static func seeds(conf: String, teams: Dictionary, table: Dictionary) -> Array:
	var divs := {}
	for abbr in teams:
		var t: TeamData = teams[abbr]
		if t.conf != conf:
			continue
		if not divs.has(t.div):
			divs[t.div] = []
		divs[t.div].append(abbr)
	var winners: Array = []
	var others: Array = []
	for d in divs:
		var ranked := rank(divs[d], table)
		winners.append(ranked[0])
		others.append_array(ranked.slice(1))
	return rank(winners, table) + rank(others, table).slice(0, 3)


## Starts the playoffs after the regular season.
static func start_playoffs(season: Dictionary, teams: Dictionary) -> void:
	var table := standings(season, teams.keys())
	var s := {"AFC": seeds("AFC", teams, table), "NFC": seeds("NFC", teams, table)}
	season["phase"] = "playoffs"
	season["playoffs"] = {"round": 1, "seeds": s, "alive": {"AFC": s["AFC"].duplicate(), "NFC": s["NFC"].duplicate()},
			"games": [], "log": [], "champion": "", "you_out": false,
			"made_it": season["team"] in s["AFC"] or season["team"] in s["NFC"]}
	season["playoffs"]["games"] = round_games(season["playoffs"])


## Pairings for the current round (higher seed at home).
static func round_games(po: Dictionary) -> Array:
	var games: Array = []
	var rnd := int(po["round"])
	if rnd == 4:
		var afc: Array = po["alive"]["AFC"]
		var nfc: Array = po["alive"]["NFC"]
		return [[afc[0], nfc[0]]]
	for conf in ["AFC", "NFC"]:
		var alive: Array = po["alive"][conf]   # kept in seed order
		if rnd == 1:
			# Seed 1 has a bye: 2v7, 3v6, 4v5.
			games.append([alive[1], alive[6]])
			games.append([alive[2], alive[5]])
			games.append([alive[3], alive[4]])
		elif rnd == 2:
			games.append([alive[0], alive[3]])
			games.append([alive[1], alive[2]])
		elif rnd == 3:
			games.append([alive[0], alive[1]])
	return games


## Applies one round's winners (Dictionary "home-away" key -> winner abbr) and advances.
static func advance_round(season: Dictionary, winners: Dictionary) -> void:
	var po: Dictionary = season["playoffs"]
	var losers := {}
	for g in po["games"]:
		var w: String = winners.get("%s-%s" % [g[0], g[1]], g[0])
		var l: String = g[1] if w == g[0] else g[0]
		losers[l] = true
		po["log"].append("%s: %s BEAT %s" % [ROUND_NAMES[int(po["round"])], w, l])
		if l == season["team"]:
			po["you_out"] = true
	if int(po["round"]) == 4:
		for g in po["games"]:
			po["champion"] = winners.get("%s-%s" % [g[0], g[1]], g[0])
		season["phase"] = "done"
		return
	for conf in ["AFC", "NFC"]:
		var keep: Array = []
		for abbr in po["alive"][conf]:
			if not losers.has(abbr):
				keep.append(abbr)
		po["alive"][conf] = keep
	po["round"] = int(po["round"]) + 1
	po["games"] = round_games(po)


## The player's game this round ([home, away]) or [].
static func my_playoff_game(season: Dictionary) -> Array:
	for g in season.get("playoffs", {}).get("games", []):
		if season["team"] in g:
			return g
	return []


## Sims every playoff game of the round except the player's. Returns winners dict.
static func sim_playoff_round(season: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var winners := {}
	for g in season["playoffs"]["games"]:
		if season["team"] in g:
			continue
		var sc := sim_score(int(season["ovr"].get(g[0], 75)), int(season["ovr"].get(g[1], 75)), rng)
		winners["%s-%s" % [g[0], g[1]]] = g[0] if sc[0] > sc[1] else g[1]
	return winners
