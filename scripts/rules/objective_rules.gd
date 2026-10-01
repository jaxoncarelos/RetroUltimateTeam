class_name ObjectiveRules
extends RefCounted
## Coin objectives ("Throw a 40 yard pass", "Rush for 100 yards"…): 3 rotating dailies and
## 3 weeklies (seeded from the local date) plus Retro Bowl Hall-of-Fame-style milestones,
## each paying coins (some a pack). They make it obvious how to earn coins. Pure logic.
## CONTRACT (used by UI code): keep these signatures stable (extra params are optional).
##
## Objective dictionary shape returned to the UI:
## {"id": String, "kind": "daily"|"weekly"|"milestone", "title": String, "desc": String,
##  "reward": int (coins), "progress": int, "target": int, "done": bool, "claimed": bool,
##  "pack": String (reward pack id, "" = none), "starter": bool (first-session objective),
##  "reward_text": String ("+300" / "+500 + GOLD PACK")}
##
## State in Profile.objectives: {"day": int, "week": int, "progress": {id: int},
## "claimed": {id: true}, "totals": {stat: int, "best_<stat>": int}}.
## Stats: every key of a match box (see match_values) plus event counters recorded with
## record_event ("packs_opened", "packs_gold", "packs_elite", "pulls_elite", "levelups",
## "trains", "sets", "challenges", "playoffs", "titles") and bests recorded with record_best
## ("team_ovr").

const DAILY_COUNT := 3
const WEEKLY_COUNT := 3

## mode "game" = best single game (or best value) reaches target; "total" = sum reaches target.
const DAILY_POOL := [
	{"id": "d_play", "title": "SUIT UP", "desc": "Play a game", "stat": "games", "target": 1, "mode": "total", "reward": 100},
	{"id": "d_win", "title": "DAILY W", "desc": "Win a game", "stat": "wins", "target": 1, "mode": "total", "reward": 150},
	{"id": "d_tds3", "title": "END ZONE DANCE", "desc": "Score 3 TDs in a game", "stat": "tds", "target": 3, "mode": "game", "reward": 150},
	{"id": "d_passtd2", "title": "GUNSLINGER", "desc": "Throw 2 TD passes", "stat": "pass_td", "target": 2, "mode": "total", "reward": 125},
	{"id": "d_rush60", "title": "GROUND GAME", "desc": "Rush for 60 yards", "stat": "rush_yds", "target": 60, "mode": "total", "reward": 125},
	{"id": "d_sack", "title": "GET HOME", "desc": "Get a sack", "stat": "def_sacks", "target": 1, "mode": "total", "reward": 125},
	{"id": "d_comp10", "title": "DINK AND DUNK", "desc": "Complete 10 passes", "stat": "pass_comp", "target": 10, "mode": "total", "reward": 125},
	{"id": "d_pass30", "title": "AIR IT OUT", "desc": "Throw a 30 yard pass", "stat": "long_pass", "target": 30, "mode": "game", "reward": 150},
	{"id": "d_fg", "title": "SPLIT THE UPRIGHTS", "desc": "Kick a field goal", "stat": "fg_made", "target": 1, "mode": "total", "reward": 100},
	{"id": "d_int", "title": "BALL HAWK", "desc": "Intercept a pass", "stat": "def_ints", "target": 1, "mode": "total", "reward": 150},
	{"id": "d_run15", "title": "BREAKAWAY", "desc": "Break a 15 yard run", "stat": "long_run", "target": 15, "mode": "game", "reward": 125},
	{"id": "d_pack", "title": "RIP ONE OPEN", "desc": "Open a pack", "stat": "packs_opened", "target": 1, "mode": "total", "reward": 100},
]
const WEEKLY_POOL := [
	{"id": "w_win5", "title": "WINNING WEEK", "desc": "Win 5 games", "stat": "wins", "target": 5, "mode": "total", "reward": 750},
	{"id": "w_play8", "title": "IRON MAN", "desc": "Play 8 games", "stat": "games", "target": 8, "mode": "total", "reward": 500},
	{"id": "w_tds15", "title": "TD MACHINE", "desc": "Score 15 touchdowns", "stat": "tds", "target": 15, "mode": "total", "reward": 600},
	{"id": "w_pass1000", "title": "AIR RAID", "desc": "Pass for 1,000 yards", "stat": "pass_yds", "target": 1000, "mode": "total", "reward": 750},
	{"id": "w_rush400", "title": "WORKHORSE", "desc": "Rush for 400 yards", "stat": "rush_yds", "target": 400, "mode": "total", "reward": 600},
	{"id": "w_sacks8", "title": "SACK PARTY", "desc": "Get 8 sacks", "stat": "def_sacks", "target": 8, "mode": "total", "reward": 600},
	{"id": "w_ints3", "title": "NO FLY ZONE", "desc": "Intercept 3 passes", "stat": "def_ints", "target": 3, "mode": "total", "reward": 600},
	{"id": "w_packs3", "title": "COLLECTOR", "desc": "Open 3 packs", "stat": "packs_opened", "target": 3, "mode": "total", "reward": 300},
]
## Milestones (lifetime, once each). "starter" ones are the easy first-session batch.
const MILESTONES := [
	{"id": "m_first_pass", "title": "FIRST COMPLETION", "desc": "Complete a pass", "stat": "pass_comp", "target": 1, "mode": "total", "reward": 250, "starter": true},
	{"id": "m_first_td", "title": "PAYDIRT", "desc": "Score a touchdown", "stat": "tds", "target": 1, "mode": "total", "reward": 300, "starter": true},
	{"id": "m_first_win", "title": "FIRST VICTORY", "desc": "Win your first game", "stat": "wins", "target": 1, "mode": "total", "reward": 500, "starter": true},
	{"id": "m_first_pack", "title": "FRESH CARDS", "desc": "Open a pack", "stat": "packs_opened", "target": 1, "mode": "total", "reward": 200, "starter": true},
	{"id": "m_pass_td", "title": "SIX IN THE AIR", "desc": "Throw a touchdown pass", "stat": "pass_td", "target": 1, "mode": "total", "reward": 100},
	{"id": "m_rush_td", "title": "PUNCH IT IN", "desc": "Run in a touchdown", "stat": "rush_td", "target": 1, "mode": "total", "reward": 100},
	{"id": "m_pass40", "title": "BOMBS AWAY", "desc": "Throw a 40 yard pass", "stat": "long_pass", "target": 40, "mode": "game", "reward": 150},
	{"id": "m_pass60", "title": "HAIL MARY ARM", "desc": "Throw a 60 yard pass", "stat": "long_pass", "target": 60, "mode": "game", "reward": 350},
	{"id": "m_run20", "title": "DAYLIGHT", "desc": "Break a 20 yard run", "stat": "long_run", "target": 20, "mode": "game", "reward": 100},
	{"id": "m_run50", "title": "HOUSE CALL", "desc": "Break a 50 yard run", "stat": "long_run", "target": 50, "mode": "game", "reward": 300},
	{"id": "m_rush100", "title": "CENTURY RUSHER", "desc": "Rush for 100 yards in a game", "stat": "rush_yds", "target": 100, "mode": "game", "reward": 250},
	{"id": "m_pass300", "title": "300 CLUB", "desc": "Pass for 300 yards in a game", "stat": "pass_yds", "target": 300, "mode": "game", "reward": 300},
	{"id": "m_tds3", "title": "HAT TRICK", "desc": "Score 3 TDs in a game", "stat": "tds", "target": 3, "mode": "game", "reward": 150},
	{"id": "m_tds5", "title": "SCORING FRENZY", "desc": "Score 5 TDs in a game", "stat": "tds", "target": 5, "mode": "game", "reward": 400},
	{"id": "m_pts40", "title": "HANG FORTY", "desc": "Score 40 points in a game", "stat": "pf", "target": 40, "mode": "game", "reward": 300},
	{"id": "m_sack", "title": "QB HUNTER", "desc": "Sack the quarterback", "stat": "def_sacks", "target": 1, "mode": "total", "reward": 100},
	{"id": "m_sacks2", "title": "PASS RUSH", "desc": "Get 2 sacks in a game", "stat": "def_sacks", "target": 2, "mode": "game", "reward": 150},
	{"id": "m_int", "title": "PICKED OFF", "desc": "Intercept a pass", "stat": "def_ints", "target": 1, "mode": "total", "reward": 100},
	{"id": "m_ints2", "title": "LOCKDOWN", "desc": "Intercept 2 passes in a game", "stat": "def_ints", "target": 2, "mode": "game", "reward": 250},
	{"id": "m_pick6", "title": "PICK SIX", "desc": "Return an interception for a TD", "stat": "def_pick6", "target": 1, "mode": "total", "reward": 350},
	{"id": "m_fg", "title": "THREE POINTS", "desc": "Kick a field goal", "stat": "fg_made", "target": 1, "mode": "total", "reward": 100},
	{"id": "m_fg50", "title": "BIG LEG", "desc": "Kick a 50 yard field goal", "stat": "fg_long", "target": 50, "mode": "game", "reward": 250},
	{"id": "m_shutout", "title": "SHUTOUT", "desc": "Win without allowing a point", "stat": "shutout", "target": 1, "mode": "total", "reward": 400},
	{"id": "m_blowout", "title": "BLOWOUT", "desc": "Win by 21 or more", "stat": "margin", "target": 21, "mode": "game", "reward": 250},
	{"id": "m_comeback", "title": "COMEBACK KIDS", "desc": "Win after trailing", "stat": "comeback", "target": 1, "mode": "total", "reward": 250},
	{"id": "m_wins5", "title": "ON A ROLL", "desc": "Win 5 games", "stat": "wins", "target": 5, "mode": "total", "reward": 250, "pack": "gold"},
	{"id": "m_wins10", "title": "DOUBLE DIGITS", "desc": "Win 10 games", "stat": "wins", "target": 10, "mode": "total", "reward": 500, "pack": "draft"},
	{"id": "m_wins25", "title": "CONTENDER", "desc": "Win 25 games", "stat": "wins", "target": 25, "mode": "total", "reward": 750, "pack": "gold"},
	{"id": "m_wins50", "title": "DYNASTY", "desc": "Win 50 games", "stat": "wins", "target": 50, "mode": "total", "reward": 1500, "pack": "elite"},
	{"id": "m_games10", "title": "REGULAR", "desc": "Play 10 games", "stat": "games", "target": 10, "mode": "total", "reward": 250},
	{"id": "m_games50", "title": "VETERAN", "desc": "Play 50 games", "stat": "games", "target": 50, "mode": "total", "reward": 1000},
	{"id": "m_gold_pack", "title": "GOING GOLD", "desc": "Open a Gold pack", "stat": "packs_gold", "target": 1, "mode": "total", "reward": 250},
	{"id": "m_elite_pack", "title": "HIGH ROLLER", "desc": "Open an Elite pack", "stat": "packs_elite", "target": 1, "mode": "total", "reward": 750},
	{"id": "m_pull90", "title": "JACKPOT", "desc": "Pull a 90+ OVR card", "stat": "pulls_elite", "target": 1, "mode": "total", "reward": 500},
	{"id": "m_levelup", "title": "GROWING UP", "desc": "Develop a player (+1 OVR from XP)", "stat": "levelups", "target": 1, "mode": "total", "reward": 150},
	{"id": "m_train", "title": "PRACTICE MAKES PERFECT", "desc": "Train a card with a duplicate", "stat": "trains", "target": 1, "mode": "total", "reward": 100},
	{"id": "m_team75", "title": "PLAYOFF CALIBER", "desc": "Reach 75 team OVR", "stat": "team_ovr", "target": 75, "mode": "game", "reward": 400},
	{"id": "m_team80", "title": "CONTENDER ROSTER", "desc": "Reach 80 team OVR", "stat": "team_ovr", "target": 80, "mode": "game", "reward": 750},
	{"id": "m_team85", "title": "SUPER TEAM", "desc": "Reach 85 team OVR", "stat": "team_ovr", "target": 85, "mode": "game", "reward": 1500},
	{"id": "m_challenge", "title": "CHALLENGER", "desc": "Complete a challenge", "stat": "challenges", "target": 1, "mode": "total", "reward": 150},
	{"id": "m_playoffs", "title": "POSTSEASON", "desc": "Make the playoffs", "stat": "playoffs", "target": 1, "mode": "total", "reward": 500},
	{"id": "m_title", "title": "CHAMPIONS", "desc": "Win the Super Bowl", "stat": "titles", "target": 1, "mode": "total", "reward": 1250},
]


static func _now(unix_time: int) -> int:
	return unix_time if unix_time >= 0 else int(Time.get_unix_time_from_system())


## Monday-based week number of a local day (day 0 = Thursday 1970-01-01).
static func week_of_day(day: int) -> int:
	return floori((day + 3) / 7.0)


## Resets dailies/weeklies when the day/week changed (unclaimed ones expire).
static func _sync(profile: Profile, unix_time: int) -> Dictionary:
	var o := profile.objectives
	for k in ["progress", "claimed", "totals"]:
		if not o.has(k) or not (o[k] is Dictionary):
			o[k] = {}
	var day := DailyRules.day_of(_now(unix_time))
	var week := week_of_day(day)
	if int(o.get("day", -1)) != day:
		_clear_prefix(o, "d_")
		o["day"] = day
	if int(o.get("week", -1)) != week:
		_clear_prefix(o, "w_")
		o["week"] = week
	return o


static func _clear_prefix(o: Dictionary, prefix: String) -> void:
	for k in ["progress", "claimed"]:
		for id in o[k].keys():
			if str(id).begins_with(prefix):
				o[k].erase(id)


## The pool entries active on a day/week (deterministic from the date).
static func _pick(pool: Array, count: int, seed_key: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var idx: Array = range(pool.size())
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = idx[i]
		idx[i] = idx[j]
		idx[j] = t
	var out := []
	for i in mini(count, idx.size()):
		out.append(pool[idx[i]])
	return out


static func dailies_for_day(day: int) -> Array:
	return _pick(DAILY_POOL, DAILY_COUNT, "daily:%d" % day)


static func weeklies_for_week(week: int) -> Array:
	return _pick(WEEKLY_POOL, WEEKLY_COUNT, "weekly:%d" % week)


static func _progress(o: Dictionary, def: Dictionary, kind: String) -> int:
	if kind != "milestone":
		return int(o["progress"].get(def["id"], 0))
	var key: String = def["stat"] if def["mode"] == "total" else "best_" + str(def["stat"])
	return int(o["totals"].get(key, 0))


static func _make(o: Dictionary, def: Dictionary, kind: String) -> Dictionary:
	var prog := _progress(o, def, kind)
	var target := int(def["target"])
	var pack: String = def.get("pack", "")
	var text := "+%d" % int(def["reward"])
	if pack != "":
		text += " + %s PACK" % pack.to_upper()
	return {"id": def["id"], "kind": kind, "title": def["title"], "desc": def["desc"],
			"reward": int(def["reward"]), "progress": mini(prog, target), "target": target,
			"done": prog >= target, "claimed": o["claimed"].has(def["id"]), "pack": pack,
			"starter": bool(def.get("starter", false)), "reward_text": text, "stat": def["stat"]}


## Every objective currently shown to the player: dailies, weeklies, then milestones
## (unclaimed starter ones first, then finished-unclaimed, in progress, claimed last).
static func active(profile: Profile, unix_time := -1) -> Array[Dictionary]:
	var o := _sync(profile, unix_time)
	var out: Array[Dictionary] = []
	for d in dailies_for_day(int(o["day"])):
		out.append(_make(o, d, "daily"))
	for d in weeklies_for_week(int(o["week"])):
		out.append(_make(o, d, "weekly"))
	var ms: Array[Dictionary] = []
	for d in MILESTONES:
		ms.append(_make(o, d, "milestone"))
	var rank := func(m: Dictionary) -> int:
		if m["claimed"]:
			return 3
		if m["starter"]:
			return 0
		return 1 if m["done"] else 2
	var order: Array[Dictionary] = []
	for r in 4:
		for m in ms:
			if rank.call(m) == r:
				order.append(m)
	out.append_array(order)
	return out


## Only the given kind ("daily" / "weekly" / "milestone").
static func of_kind(profile: Profile, kind: String, unix_time := -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in active(profile, unix_time):
		if o["kind"] == kind:
			out.append(o)
	return out


static func find(profile: Profile, id: String, unix_time := -1) -> Dictionary:
	for o in active(profile, unix_time):
		if o["id"] == id:
			return o
	return {}


## Claims a finished objective; returns coins granted (0 if not claimable). A pack reward is
## queued in Profile.pending_packs; coach XP is added (see claim_details for everything).
static func claim(profile: Profile, id: String, unix_time := -1) -> int:
	return int(claim_details(profile, id, unix_time)["coins"])


## Like claim(): {"coins": int, "pack": String, "xp": int, "level_ups": Array} ({"coins": 0...}
## when not claimable).
static func claim_details(profile: Profile, id: String, unix_time := -1) -> Dictionary:
	var none := {"coins": 0, "pack": "", "xp": 0, "level_ups": []}
	var obj := find(profile, id, unix_time)
	if obj.is_empty() or not obj["done"] or obj["claimed"]:
		return none
	profile.objectives["claimed"][id] = true
	profile.coins += int(obj["reward"])
	profile.stats["coins_earned"] = int(profile.stats.get("coins_earned", 0)) + int(obj["reward"])
	if obj["pack"] != "":
		profile.pending_packs.append(obj["pack"])
	var xp := int(ProgressionRules.XP_OBJECTIVE.get(obj["kind"], 100))
	var ups := ProgressionRules.add_xp(profile, xp)
	return {"coins": int(obj["reward"]), "pack": obj["pack"], "xp": xp, "level_ups": ups}


## Claims everything claimable: {"coins": int, "packs": [ids], "ids": [ids], "level_ups": [...]}.
static func claim_all(profile: Profile, unix_time := -1) -> Dictionary:
	var res := {"coins": 0, "packs": [], "ids": [], "level_ups": []}
	for o in active(profile, unix_time):
		if o["done"] and not o["claimed"]:
			var r := claim_details(profile, o["id"], unix_time)
			res["coins"] += int(r["coins"])
			if r["pack"] != "":
				res["packs"].append(r["pack"])
			res["ids"].append(o["id"])
			res["level_ups"].append_array(r["level_ups"])
	return res


## Stat values of one match box (GameState.box_score(team), or GameState.stats[team] plus
## "won", "longest_pass", "longest_run", "pf", "pa", "def_sacks", "def_ints").
static func match_values(box: Dictionary) -> Dictionary:
	var won: bool = bool(box.get("won", int(box.get("pf", 0)) > int(box.get("pa", 0))))
	var pf := int(box.get("pf", 0))
	var pa := int(box.get("pa", 0))
	var v := {"games": 1, "wins": 1 if won else 0}
	for k in ["pass_comp", "pass_att", "pass_yds", "pass_td", "rush_yds", "rush_td", "def_sacks", "def_ints",
			"def_pick6", "fg_made"]:
		v[k] = maxi(0, int(box.get(k, 0)))
	v["tds"] = int(box.get("tds", v["pass_td"] + v["rush_td"]))
	v["long_pass"] = int(box.get("long_pass", box.get("longest_pass", 0)))
	v["long_run"] = int(box.get("long_run", box.get("longest_run", 0)))
	v["fg_long"] = int(box.get("fg_long", 0))
	v["pf"] = pf
	v["margin"] = pf - pa if won else 0
	v["shutout"] = 1 if won and pa == 0 else 0
	v["comeback"] = 1 if won and bool(box.get("came_back", false)) else 0
	return v


## Feeds one finished match's box score for the human team (see match_values). Returns ids
## newly completed. Forfeits ("forfeit": true) only count as a game played.
static func record_match(profile: Profile, box: Dictionary, unix_time := -1) -> Array[String]:
	var values := {"games": 1} if box.get("forfeit", false) else match_values(box)
	return _apply(profile, values, unix_time)


## Adds `amount` to a counter stat (packs_opened, trains, …). Returns ids newly completed.
static func record_event(profile: Profile, stat: String, amount := 1, unix_time := -1) -> Array[String]:
	return _apply(profile, {stat: amount}, unix_time)


## Records a best-value stat (team_ovr): milestones compare the best ever. Returns ids newly completed.
static func record_best(profile: Profile, stat: String, value: int, unix_time := -1) -> Array[String]:
	return _apply(profile, {stat: value}, unix_time, true)


static func _apply(profile: Profile, values: Dictionary, unix_time: int, best_only := false) -> Array[String]:
	var before := {}
	for o in active(profile, unix_time):
		before[o["id"]] = o["done"]
	var st := profile.objectives
	var totals: Dictionary = st["totals"]
	for k in values:
		var val := int(values[k])
		if not best_only:
			totals[k] = int(totals.get(k, 0)) + val
		totals["best_" + k] = maxi(int(totals.get("best_" + k, 0)), val)
	var periodic := dailies_for_day(int(st["day"])) + weeklies_for_week(int(st["week"]))
	for d in periodic:
		if not values.has(d["stat"]):
			continue
		var val := int(values[d["stat"]])
		var cur := int(st["progress"].get(d["id"], 0))
		st["progress"][d["id"]] = maxi(cur, val) if (d["mode"] == "game" or best_only) else cur + val
	var out: Array[String] = []
	for o in active(profile, unix_time):
		if o["done"] and not before.get(o["id"], false):
			out.append(o["id"])
	return out


## Count of finished-but-unclaimed objectives (for a badge on the hub button).
static func claimable_count(profile: Profile, unix_time := -1) -> int:
	var n := 0
	for o in active(profile, unix_time):
		if o["done"] and not o["claimed"]:
			n += 1
	return n
