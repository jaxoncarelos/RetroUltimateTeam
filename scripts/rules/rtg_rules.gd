class_name RtgRules
extends RefCounted
## Road to Glory career rules (docs/ROAD_TO_GLORY_PLAN.md): creating your player
## (position, archetype, name, number, look), his OVR, XP and attribute upgrades, coach trust,
## the draft, the season (league schedule from SeasonRules), per-game results, season goals,
## awards, the offseason (aging, contracts), retirement and the Hall of Fame. State is one
## plain Dictionary (Profile.rtg) so it saves as JSON. Pure logic (rng passed in).
##
## rtg = {version, stage: "draft"|"season"|"offseason"|"retired", year (career season 1..),
##   player: {first, last, name, pos, arch, jersey, look, attrs, age, dev},
##   team, draft: {round, pick, overall, team, combine}, xp, xp_total, trust (0..100),
##   season: SeasonRules dict, season_stats, games: [{week, opp, home, pf, pa, grade, pts, line}],
##   goals: [{stat, target, xp, coins, text, done}], career: [{year, team, games, stats, grade,
##   awards, ovr, age, wins, losses}], awards: [{year, id, name}], rings, legacy,
##   contract: {years, salary}, offers: [{team, years, salary}], retire_reason}

const VERSION := 1
const POSITIONS := ["QB", "RB", "WR", "CB"]
const SLOT := {"QB": "QB", "RB": "RB", "WR": "WR1", "CB": "CB1"}
const POS_NAMES := {"QB": "QUARTERBACK", "RB": "RUNNING BACK", "WR": "WIDE RECEIVER", "CB": "CORNERBACK"}
const POS_BLURB := {
	"QB": "CALL THE PLAYS. LEFT THUMB MOVES YOU, RIGHT THUMB THROWS.",
	"RB": "TAKE THE HANDOFF. JUKE, SPIN AND TRUCK YOUR WAY UPFIELD.",
	"WR": "RUN YOUR OWN ROUTES, CALL FOR THE BALL, MOSS DEFENDERS.",
	"CB": "SHADOW YOUR MAN, READ HIS BREAK, PICK THE BALL.",
}
const START_OVR := 62
const START_AGE := 21
const START_TRUST := 40

## Archetypes: attribute offsets on top of the position profile at START_OVR.
const ARCHETYPES := {
	"QB": [
		{"id": "gunslinger", "name": "GUNSLINGER", "desc": "BIG ARM, LIVES FOR THE DEEP SHOT", "attrs": {"thp": 11, "tha": -2, "awr": -2}},
		{"id": "field_general", "name": "FIELD GENERAL", "desc": "ACCURATE, READS EVERY COVERAGE", "attrs": {"tha": 8, "awr": 9, "thp": -3}},
		{"id": "scrambler", "name": "SCRAMBLER", "desc": "MAKES PLAYS WITH HIS LEGS", "attrs": {"spd": 14, "acc": 10, "elu": 12, "thp": -2, "tha": -3}},
	],
	"RB": [
		{"id": "power", "name": "POWER BACK", "desc": "RUNS THROUGH ARM TACKLES", "attrs": {"str": 14, "car": 8, "elu": -3, "spd": -2}},
		{"id": "elusive", "name": "ELUSIVE BACK", "desc": "MAKES DEFENDERS MISS", "attrs": {"elu": 11, "acc": 6, "spd": 3, "str": -6}},
		{"id": "receiving", "name": "RECEIVING BACK", "desc": "A WEAPON OUT OF THE BACKFIELD", "attrs": {"cth": 14, "rte": 14, "elu": 2, "str": -4}},
	],
	"WR": [
		{"id": "deep_threat", "name": "DEEP THREAT", "desc": "BLAZING SPEED, TAKES THE TOP OFF", "attrs": {"spd": 9, "acc": 4, "cth": -2, "str": -3}},
		{"id": "route_runner", "name": "ROUTE RUNNER", "desc": "SHARP CUTS, ALWAYS OPEN", "attrs": {"rte": 10, "acc": 5, "awr": 4, "spd": -2}},
		{"id": "possession", "name": "POSSESSION", "desc": "STRONG HANDS IN TRAFFIC", "attrs": {"cth": 9, "str": 10, "rte": 3, "spd": -4}},
	],
	"CB": [
		{"id": "lockdown", "name": "LOCKDOWN", "desc": "STICKS TO HIS MAN LIKE GLUE", "attrs": {"cov": 8, "spd": 4, "acc": 3, "tak": -4}},
		{"id": "ballhawk", "name": "BALLHAWK", "desc": "READS THE QB, PICKS IT OFF", "attrs": {"cth": 16, "awr": 7, "cov": 2, "str": -4}},
		{"id": "hard_hitter", "name": "HARD HITTER", "desc": "TACKLES LIKE A SAFETY", "attrs": {"tak": 14, "str": 12, "cov": -3, "spd": -1}},
	],
}

## What makes each position's OVR (weights sum to 1). These are the upgradeable attributes.
const WEIGHTS := {
	"QB": {"tha": 0.33, "thp": 0.25, "awr": 0.24, "spd": 0.06, "acc": 0.06, "elu": 0.06},
	"RB": {"spd": 0.2, "acc": 0.15, "elu": 0.2, "str": 0.1, "car": 0.15, "cth": 0.1, "awr": 0.1},
	"WR": {"cth": 0.3, "rte": 0.25, "spd": 0.2, "acc": 0.1, "awr": 0.05, "str": 0.05, "elu": 0.05},
	"CB": {"cov": 0.35, "spd": 0.2, "acc": 0.15, "awr": 0.15, "cth": 0.08, "tak": 0.07},
}
const ATTR_NAMES := {"spd": "SPEED", "acc": "ACCELERATION", "str": "STRENGTH", "awr": "AWARENESS",
		"thp": "THROW POWER", "tha": "THROW ACCURACY", "cth": "CATCHING", "rte": "ROUTE RUNNING",
		"car": "CARRYING", "elu": "ELUSIVENESS", "tak": "TACKLE", "cov": "COVERAGE"}

## Development traits: XP multiplier. Awards raise them.
const DEV := ["NORMAL", "STAR", "SUPERSTAR", "X-FACTOR"]
const DEV_XP := [1.0, 1.15, 1.3, 1.5]
const DEV_COLORS := [Color("#b8c0d8"), Color("#ffd21f"), Color("#ff9d2e"), Color("#ff2b6e")]

const SIM_GRADE_POINTS := 64.0    ## a simmed game grades C+
const SIM_XP_SHARE := 0.45        ## and pays this share of a played game's XP
const RETIRE_AGE := 37
const HOF_LEGACY := 150

## Draft picks per round (32 teams).
const PICKS_PER_ROUND := 32

const FIRST_NAMES := ["JALEN", "MARCUS", "TYREE", "CALEB", "DEVON", "ANDRE", "BRYCE", "KEON", "MALIK", "TRAVIS",
		"JAYDEN", "COLE", "DARIUS", "ELI", "ISAIAH", "JAMAL", "KADE", "LANDON", "MASON", "NICO", "OMAR", "QUINN",
		"REGGIE", "SAMMY", "TREY", "VINCE", "WES", "XAVIER", "ZEKE", "BO", "CHASE", "DREW", "GRADY", "HUNTER"]
const LAST_NAMES := ["CARTER", "BROOKS", "HAYES", "COLEMAN", "REED", "WALKER", "PRICE", "BELL", "DIXON", "FOSTER",
		"GRAVES", "HOLLAND", "JENNINGS", "KNOX", "LAWSON", "MOSS", "NASH", "OWENS", "PAYNE", "RHODES", "SIMMS",
		"TATE", "VAUGHN", "WARE", "YOUNG", "BANKS", "CROSS", "DAWSON", "ELLIS", "FLOWERS", "GAINES", "HARDY"]
## Jersey number ranges by position (the create screen cycles within them).
const JERSEYS := {"QB": [1, 19], "RB": [20, 49], "WR": [1, 19], "CB": [20, 49]}

## Difficulty -> opponent OVR offset (ROOKIE .. LEGEND).
const DIFF_OFFSET := [-6, 0, 3, 6]


static func difficulty_offset(d: int) -> int:
	return DIFF_OFFSET[clampi(d, 0, DIFF_OFFSET.size() - 1)]


# ---------------------------------------------------------------- the player

static func archetype(pos: String, id: String) -> Dictionary:
	for a in ARCHETYPES.get(pos, []):
		if a["id"] == id:
			return a
	return ARCHETYPES.get(pos, [{}])[0]


## Starting attributes for a position + archetype.
static func start_attrs(pos: String, arch: String) -> Dictionary:
	var attrs := RatingModel.fill_attrs(pos, START_OVR)
	var off: Dictionary = archetype(pos, arch).get("attrs", {})
	for k in off:
		attrs[k] = clampi(int(attrs[k]) + int(off[k]), 30, 99)
	return attrs


## Position OVR from attributes (WEIGHTS).
static func ovr(pos: String, attrs: Dictionary) -> int:
	var w: Dictionary = WEIGHTS.get(pos, {})
	var total := 0.0
	for k in w:
		total += float(attrs.get(k, 50)) * float(w[k])
	return clampi(int(round(total)), 30, 99)


static func random_name(rng: RandomNumberGenerator) -> Array:
	return [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]


static func random_jersey(pos: String, rng: RandomNumberGenerator) -> int:
	var r: Array = JERSEYS[pos]
	return rng.randi_range(int(r[0]), int(r[1]))


## "J. CARTER" from first/last.
static func short_name(first: String, last: String) -> String:
	return ("%s. %s" % [first.left(1), last]).to_upper() if first != "" else last.to_upper()


static func new_player(pos: String, arch: String, first: String, last: String, jersey: int, look: Dictionary) -> Dictionary:
	return {"first": first.to_upper(), "last": last.to_upper(), "name": short_name(first, last), "pos": pos,
			"arch": arch, "jersey": jersey, "look": look.duplicate(), "attrs": start_attrs(pos, arch),
			"age": START_AGE, "dev": 0}


## A fresh career (stage "draft": the combine and draft come next). `uid` makes the id of
## its Ultimate Team card ("rtg_<uid>"); "" derives one from the player.
static func new_career(player: Dictionary, uid := "") -> Dictionary:
	if uid == "":
		uid = str(absi(hash(str(player.get("name", "")) + str(player.get("jersey", 0)) + str(player.get("arch", "")))))
	return {"version": VERSION, "id": "rtg_" + uid, "stage": "draft", "year": 1, "player": player, "team": "", "draft": {},
			"xp": 0, "xp_total": 0, "trust": START_TRUST, "season": {}, "season_stats": RtgTracker.empty_stats(),
			"games": [], "goals": [], "career": [], "awards": [], "rings": 0, "legacy": 0,
			"contract": {}, "offers": [], "retire_reason": "", "peak_ovr": ovr(player["pos"], player["attrs"]),
			"peak_attrs": (player["attrs"] as Dictionary).duplicate()}


static func player_ovr(rtg: Dictionary) -> int:
	var p: Dictionary = rtg["player"]
	return ovr(str(p["pos"]), p["attrs"])


static func slot_of(rtg: Dictionary) -> String:
	return SLOT[str(rtg["player"]["pos"])]


# ---------------------------------------------------------------- XP & upgrades

## XP to raise an attribute from `value` to value + 1 (gets steeper at the top: a rookie gains
## ~10 OVR his first season, a good player ~2-3 a year in his prime, 95+ takes a great career).
static func upgrade_cost(value: int) -> int:
	return 25 + maxi(0, value - 50) * 5 + maxi(0, value - 75) * 8 + maxi(0, value - 88) * 15


## Season XP is the same whatever the season length: per-game XP × 8 / games (17 games ≈ 0.47).
const REF_GAMES := 8.0


static func xp_scale(games: int) -> float:
	return clampf(REF_GAMES / maxf(games, 1.0), 0.4, 1.0)


static func can_upgrade(rtg: Dictionary, attr: String) -> bool:
	var p: Dictionary = rtg["player"]
	var v := int(p["attrs"].get(attr, 50))
	return WEIGHTS[str(p["pos"])].has(attr) and v < 99 and int(rtg["xp"]) >= upgrade_cost(v)


## Spends XP on +1 to `attr`. Returns true when it happened.
static func upgrade(rtg: Dictionary, attr: String) -> bool:
	if not can_upgrade(rtg, attr):
		return false
	var p: Dictionary = rtg["player"]
	var v := int(p["attrs"][attr])
	rtg["xp"] = int(rtg["xp"]) - upgrade_cost(v)
	p["attrs"][attr] = v + 1
	_track_peak(rtg)
	return true


## Remembers the best version of him (his Legend card is frozen there).
static func _track_peak(rtg: Dictionary) -> void:
	var o := player_ovr(rtg)
	if o >= int(rtg.get("peak_ovr", 0)):
		rtg["peak_ovr"] = o
		rtg["peak_attrs"] = (rtg["player"]["attrs"] as Dictionary).duplicate()


# ---------------------------------------------------------------- Ultimate Team card

static func is_rtg_card(card_id: String) -> bool:
	return card_id.begins_with("rtg_")


## The Ultimate Team card of an active career: {id, name, team, pos, jersey, ovr, attrs, look, age}
## ({} before the draft).
static func card_player(rtg: Dictionary) -> Dictionary:
	if rtg.is_empty() or str(rtg.get("team", "")) == "" or not rtg.has("id"):
		return {}
	var p: Dictionary = rtg["player"]
	return {"id": rtg["id"], "name": "%s %s" % [str(p["first"]).capitalize(), str(p["last"]).capitalize()],
			"team": rtg["team"], "pos": p["pos"], "jersey": int(p["jersey"]), "ovr": player_ovr(rtg),
			"attrs": p["attrs"], "look": p.get("look", {}), "age": int(p["age"])}


## A legend's card: frozen at his peak.
static func legend_card_player(l: Dictionary) -> Dictionary:
	if not l.has("id"):
		return {}
	var attrs: Dictionary = l.get("peak_attrs", l.get("attrs", {}))
	return {"id": l["id"], "name": "%s %s" % [str(l["first"]).capitalize(), str(l["last"]).capitalize()],
			"team": l.get("team", ""), "pos": l["pos"], "jersey": int(l.get("jersey", 0)),
			"ovr": maxi(int(l.get("peak", 0)), ovr(str(l["pos"]), attrs)), "attrs": attrs, "look": l.get("look", {}), "age": 30}


## XP earned by one game: base + grade + stats + win, × development trait.
## sim = a simmed game (a share of it).
static func game_xp(points: float, stats: Dictionary, won: bool, dev: int, sim := false, scale := 1.0) -> int:
	var x := 140.0 + maxf(points - 40.0, 0.0) * 5.0
	x += 40.0 * (int(stats.get("rush_td", 0)) + int(stats.get("rec_td", 0)) + int(stats.get("pass_td", 0)) + int(stats.get("def_td", 0)))
	x += 50.0 * int(stats.get("ints", 0))
	x += minf((int(stats.get("rush_yds", 0)) + int(stats.get("rec_yds", 0))) * 0.5 + int(stats.get("pass_yds", 0)) * 0.15, 120.0)
	x += 60.0 if won else 0.0
	if sim:
		x *= SIM_XP_SHARE
	return int(round(x * scale * DEV_XP[clampi(dev, 0, DEV_XP.size() - 1)]))


## Coach trust change after a game (grade points 0..100).
static func trust_delta(points: float, won: bool) -> int:
	return clampi(int(round((points - 66.0) * 0.45)) + (2 if won else -1), -12, 12)


## Audibles per game for a non-QB (more trust, more say).
static func audibles(trust: int) -> int:
	return 1 + clampi(trust / 34, 0, 2)


# ---------------------------------------------------------------- draft

## Combine grade points (0..100) to draft stock; then where you go.
## Returns {round, pick, overall, team, board: [[overall, team, pos], ...] (picks before yours)}.
static func draft(rtg: Dictionary, combine: float, teams: Dictionary, team_ovr: Dictionary,
		starter_ovr: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var score := float(player_ovr(rtg)) + (combine - 60.0) / 3.5 + rng.randf_range(-2.5, 2.5)
	var rnd := 1
	if score < 70.0:
		rnd = 2
	if score < 66.0:
		rnd = 3
	if score < 62.0:
		rnd = 4 + mini(int((62.0 - score) / 2.0), 3)
	# Draft order: the weakest teams pick first.
	var order: Array = teams.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		return int(team_ovr.get(a, 75)) < int(team_ovr.get(b, 75)) if team_ovr.get(a, 75) != team_ovr.get(b, 75) else a < b)
	# Who takes you: need at your position (a weak starter) plus a little luck.
	var weights := PackedFloat32Array()
	for abbr in order:
		var need := clampf((88.0 - float(starter_ovr.get(abbr, 75))) / 20.0, 0.15, 1.5)
		weights.append(need)
	var idx := AIPlayCaller.weighted_index(weights, rng)
	var team: String = order[idx]
	var pick := idx + 1
	var overall := (rnd - 1) * PICKS_PER_ROUND + pick
	var board: Array = []
	var pos_pool := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "OL", "DL", "WR", "CB", "EDGE"]
	for i in range(maxi(1, overall - 6), overall):
		board.append([i, order[(i - 1) % order.size()], pos_pool[rng.randi() % pos_pool.size()]])
	return {"round": rnd, "pick": pick, "overall": overall, "team": team, "board": board, "combine": combine}


## Rookie contract: years by round, salary by pick.
static func rookie_contract(d: Dictionary) -> Dictionary:
	var overall := int(d.get("overall", 64))
	return {"years": 4 if int(d.get("round", 1)) == 1 else 3, "salary": salary_text(maxf(0.9, 9.0 - overall * 0.06))}


static func salary_text(millions: float) -> String:
	return "$%.1fM" % millions


## Applies the draft: team, contract, a new season on that team, stage "season".
static func sign_rookie(rtg: Dictionary, d: Dictionary, teams: Dictionary, strengths: Dictionary,
		games: int, rng: RandomNumberGenerator) -> void:
	rtg["draft"] = {"round": d["round"], "pick": d["pick"], "overall": d["overall"], "team": d["team"],
			"combine": d.get("combine", 60.0)}
	rtg["team"] = d["team"]
	rtg["contract"] = rookie_contract(d)
	start_season(rtg, teams, strengths, games, rng)


# ---------------------------------------------------------------- seasons

## Team strength with you in the lineup (you move your team's rating by your slot's weight).
static func team_strength(rtg: Dictionary, base_ovr: int, starter_ovr: int) -> int:
	var w := float(TeamRating.WEIGHTS.get(slot_of(rtg), 0.05))
	return clampi(int(round(base_ovr + (player_ovr(rtg) - starter_ovr) * w)), 50, 99)


static func start_season(rtg: Dictionary, teams: Dictionary, strengths: Dictionary, games: int,
		rng: RandomNumberGenerator) -> void:
	rtg["season"] = SeasonRules.new_season(teams, str(rtg["team"]), games, strengths, rng, int(rtg["year"]))
	rtg["season_stats"] = RtgTracker.empty_stats()
	rtg["games"] = []
	rtg["goals"] = season_goals(str(rtg["player"]["pos"]), games, int(rtg["year"]) == 1)
	rtg["stage"] = "season"


## The next game you play: {home, away, label, playoff} or {} (season over).
static func next_game(rtg: Dictionary) -> Dictionary:
	var s: Dictionary = rtg.get("season", {})
	if s.is_empty():
		return {}
	var you := str(rtg["team"])
	match str(s.get("phase", "")):
		"regular":
			var w := int(s["week"])
			if w >= (s["weeks"] as Array).size():
				return {}
			for g in s["weeks"][w]:
				if you in g:
					return {"home": g[0], "away": g[1], "label": "WEEK %d" % (w + 1), "playoff": false}
		"playoffs":
			var mine := SeasonRules.my_playoff_game(s)
			if not mine.is_empty():
				return {"home": mine[0], "away": mine[1],
						"label": SeasonRules.ROUND_NAMES[int(s["playoffs"]["round"])], "playoff": true}
	return {}


## MatchController config for the next game ({} if none). `you` is always the match's home team.
static func game_config(rtg: Dictionary, difficulty: int, conditions: Dictionary) -> Dictionary:
	var g := next_game(rtg)
	if g.is_empty():
		return {}
	var you := str(rtg["team"])
	var opp: String = g["away"] if g["home"] == you else g["home"]
	var p: Dictionary = rtg["player"]
	var trust := int(rtg.get("trust", START_TRUST))
	return {"home": you, "away": opp, "from_hub": true, "difficulty": difficulty, "mode": "rtg",
			"conditions": conditions, "label": g["label"],
			"extra": {"home": g["home"], "away": g["away"], "label": g["label"], "playoff": g["playoff"]},
			"rtg": {"pos": p["pos"], "slot": SLOT[str(p["pos"])], "trust": trust / 100.0, "audibles": audibles(trust),
				"show_tips": int(rtg["year"]) == 1 and (rtg.get("games", []) as Array).is_empty(),
				"player": {"name": p["name"], "jersey": int(p["jersey"]), "attrs": p["attrs"], "look": p.get("look", {})}}}


## A debug RTG match config's "rtg" part (`--rtg-game=WR`): a 74 OVR player of that position.
static func debug_match_rtg(pos: String) -> Dictionary:
	if not pos in POSITIONS:
		pos = "WR"
	var arch: String = ARCHETYPES[pos][0]["id"]
	var attrs := start_attrs(pos, arch)
	for k in WEIGHTS[pos]:
		attrs[k] = mini(int(attrs[k]) + 12, 99)
	return {"pos": pos, "slot": SLOT[pos], "trust": 0.5, "audibles": 2, "team": "KC", "opp": "PHI",
			"player": {"name": "R. ROOKIE", "jersey": 24 if pos in ["RB", "CB"] else 11, "attrs": attrs, "look": {}}}


## Typical stat line for a share (0..1) of a game at an OVR (sims, the rest of a left game).
static func sim_line(pos: String, p_ovr: int, share: float, rng: RandomNumberGenerator) -> Dictionary:
	var f := clampf((p_ovr - 55.0) / 30.0, 0.2, 1.5)
	var line := RtgTracker.empty_stats()
	var n := func(mean: float) -> int: return maxi(0, int(round(rng.randfn(mean * share, maxf(mean * share * 0.35, 0.3)))))
	match pos:
		"RB":
			line["rush_att"] = n.call(15.0)
			line["rush_yds"] = int(round(float(line["rush_att"]) * rng.randf_range(3.0, 5.2) * (0.75 + 0.3 * f)))
			line["rush_td"] = n.call(0.45 * f)
			line["targets"] = n.call(3.0)
			line["rec"] = mini(line["targets"], n.call(2.2))
			line["rec_yds"] = int(line["rec"] * rng.randf_range(5.0, 9.0))
			line["long_rush"] = mini(line["rush_yds"], int(line["rush_yds"] * rng.randf_range(0.2, 0.5)) + 2)
		"WR":
			line["targets"] = n.call(7.0 * (0.8 + 0.25 * f))
			line["rec"] = mini(line["targets"], int(round(line["targets"] * rng.randf_range(0.55, 0.72))))
			line["rec_yds"] = int(line["rec"] * rng.randf_range(10.0, 15.0) * (0.85 + 0.15 * f))
			line["rec_td"] = n.call(0.4 * f)
			line["long_rec"] = mini(line["rec_yds"], int(line["rec_yds"] * rng.randf_range(0.25, 0.55)) + 3)
		"QB":
			line["pass_att"] = n.call(30.0)
			line["pass_comp"] = int(round(line["pass_att"] * clampf(rng.randf_range(0.55, 0.7) + 0.04 * (f - 0.8), 0.45, 0.8)))
			line["pass_yds"] = int(line["pass_comp"] * rng.randf_range(9.5, 12.5) * (0.85 + 0.15 * f))
			line["pass_td"] = n.call(1.5 * f)
			line["ints_thrown"] = n.call(0.8 / maxf(f, 0.5))
			line["sacked"] = n.call(2.0)
		"CB":
			line["def_targets"] = n.call(5.0)
			line["comp_allowed"] = mini(line["def_targets"], int(round(line["def_targets"] * clampf(rng.randf_range(0.5, 0.68) - 0.05 * (f - 0.8), 0.3, 0.8))))
			line["yds_allowed"] = int(line["comp_allowed"] * rng.randf_range(9.0, 13.0))
			line["td_allowed"] = n.call(0.25)
			line["ints"] = n.call(0.14 * f)
			line["pbu"] = n.call(0.6 * f)
			line["tackles"] = n.call(4.0)
	return line


## Adds a game's stat line to the season totals.
static func add_stats(total: Dictionary, line: Dictionary) -> void:
	for k in line:
		if not total.has(k):
			continue
		if str(k).begins_with("long_"):
			total[k] = maxi(int(total[k]), int(line[k]))
		else:
			total[k] = int(total[k]) + int(line[k])


## Applies a finished game (match_result(), or a sim). Returns a summary for the postgame
## screen: {grade, points, xp, trust_before, trust_after, won, line, goals_done: [...],
## season_msg, season_over}.
static func apply_game(rtg: Dictionary, r: Dictionary, teams: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var s: Dictionary = rtg["season"]
	var you := str(rtg["team"])
	var rt: Dictionary = r.get("rtg", {})
	var stats: Dictionary = rt.get("stats", RtgTracker.empty_stats())
	var points := float(rt.get("points", SIM_GRADE_POINTS))
	var won := int(r["pf"]) > int(r["pa"])
	var p: Dictionary = rtg["player"]
	var share := played_share(r)
	var xp := int(round(game_xp(points, stats, won, int(p.get("dev", 0)), false, xp_scale(int(s.get("games", 8))))
			* lerpf(SIM_XP_SHARE, 1.0, share)))
	var sim := share < 1.0
	var trust_before := int(rtg["trust"])
	rtg["trust"] = clampi(trust_before + trust_delta(points, won), 0, 100)
	rtg["xp"] = int(rtg["xp"]) + xp
	rtg["xp_total"] = int(rtg.get("xp_total", 0)) + xp
	add_stats(rtg["season_stats"], stats)
	var extra: Dictionary = r.get("extra", {})
	var home: String = extra.get("home", you)
	var away: String = extra.get("away", r.get("opponent", ""))
	var hs := int(r["pf"]) if home == you else int(r["pa"])
	var as_ := int(r["pa"]) if home == you else int(r["pf"])
	var opp: String = away if home == you else home
	var letter := RtgTracker.letter(points)
	(rtg["games"] as Array).append({"label": extra.get("label", ""), "opp": opp, "home": home == you,
			"pf": int(r["pf"]), "pa": int(r["pa"]), "grade": letter, "pts": points,
			"line": RtgTracker.line_text(str(p["pos"]), stats), "sim": sim})
	var out := {"grade": letter, "points": points, "xp": xp, "trust_before": trust_before,
			"trust_after": int(rtg["trust"]), "won": won, "line": RtgTracker.line_text(str(p["pos"]), stats),
			"goals_done": [], "season_msg": "", "season_over": false}
	for g in rtg["goals"]:
		if not g.get("done", false) and goal_progress(rtg, g) >= int(g["target"]):
			g["done"] = true
			rtg["xp"] = int(rtg["xp"]) + int(g["xp"])
			out["goals_done"].append(g)
	# The league: this week's other games, your result, the playoffs.
	if s["phase"] == "regular":
		SeasonRules.sim_week(s, rng)
		SeasonRules.record_game(s, home, away, hs, as_)
		s["week"] = int(s["week"]) + 1
		if int(s["week"]) >= int(s["games"]):
			SeasonRules.start_playoffs(s, teams)
			if s["playoffs"]["made_it"]:
				out["season_msg"] = "REGULAR SEASON OVER: YOU'RE IN THE PLAYOFFS!"
			else:
				out["season_msg"] = "REGULAR SEASON OVER: NO PLAYOFFS THIS YEAR"
				_finish_playoffs_without_you(s, rng)
				out["season_over"] = true
	elif s["phase"] == "playoffs":
		var winners := SeasonRules.sim_playoff_round(s, rng)
		var mine := SeasonRules.my_playoff_game(s)
		if not mine.is_empty():
			var key := "%s-%s" % [mine[0], mine[1]]
			var tie := int(r["pf"]) == int(r["pa"])
			winners[key] = you if won or tie and rng.randf() < 0.5 else (mine[1] if mine[0] == you else mine[0])
			out["season_msg"] = ("PLAYOFF WIN!" if winners[key] == you else "ELIMINATED IN THE %s" % SeasonRules.ROUND_NAMES[int(s["playoffs"]["round"])])
		SeasonRules.advance_round(s, winners)
		if s["playoffs"].get("you_out", false) and s["phase"] != "done":
			_finish_playoffs_without_you(s, rng)
		if s["phase"] == "done":
			out["season_over"] = true
			if s["playoffs"]["champion"] == you:
				rtg["rings"] = int(rtg.get("rings", 0)) + 1
				out["season_msg"] = "SUPER BOWL CHAMPIONS!"
	if out["season_over"]:
		rtg["stage"] = "offseason"
	return out


## Plays out the rest of the playoffs (you are out or never got in).
static func _finish_playoffs_without_you(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var guard := 8
	while s["phase"] == "playoffs" and guard > 0:
		guard -= 1
		SeasonRules.advance_round(s, SeasonRules.sim_playoff_round(s, rng))


## How much of a game you really played (1 = all of it, 0 = a SIM): a game you left early is
## paid like a sim for the part that was simulated (~20 snaps on the field = a full game).
static func played_share(r: Dictionary) -> float:
	if not bool(r.get("simulated", false)):
		return 1.0
	if not bool(r.get("sim_started", false)):
		return 0.0
	return clampf(int(r.get("rtg", {}).get("stats", {}).get("plays", 0)) / 20.0, 0.0, 1.0)


## A simulated game for you: score from both teams' strengths, your line from sim_line.
static func sim_game(rtg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var g := next_game(rtg)
	if g.is_empty():
		return {}
	var s: Dictionary = rtg["season"]
	var you := str(rtg["team"])
	var sc := SeasonRules.sim_score(int(s["ovr"].get(g["home"], 75)), int(s["ovr"].get(g["away"], 75)), rng)
	var pf := int(sc[0]) if g["home"] == you else int(sc[1])
	var pa := int(sc[1]) if g["home"] == you else int(sc[0])
	if bool(g["playoff"]) and pf == pa:
		pf += 3
	var p: Dictionary = rtg["player"]
	var line := sim_line(str(p["pos"]), player_ovr(rtg), 1.0, rng)
	var pts := clampf(rng.randfn(SIM_GRADE_POINTS, 5.0), 50.0, 76.0)
	return {"team": you, "opponent": g["away"] if g["home"] == you else g["home"], "pf": pf, "pa": pa,
			"simulated": true, "mode": "rtg", "extra": {"home": g["home"], "away": g["away"], "label": g["label"]},
			"rtg": {"pos": p["pos"], "stats": line, "grade": RtgTracker.letter(pts), "points": pts, "graded": 0,
				"highlights": []}}


# ---------------------------------------------------------------- goals & awards

## Three season goals scaled to the season length (rookies a bit lower).
static func season_goals(pos: String, games: int, rookie: bool) -> Array:
	var k := games / 17.0 * (0.8 if rookie else 1.0)
	var defs: Array = {
		"QB": [["pass_yds", 3800, "PASSING YARDS"], ["pass_td", 26, "TD PASSES"], ["rush_yds", 250, "RUSHING YARDS"]],
		"RB": [["rush_yds", 1100, "RUSHING YARDS"], ["rush_td", 9, "RUSHING TDS"], ["rec_yds", 300, "RECEIVING YARDS"]],
		"WR": [["rec_yds", 1000, "RECEIVING YARDS"], ["rec_td", 8, "TD CATCHES"], ["rec", 70, "CATCHES"]],
		"CB": [["ints", 4, "INTERCEPTIONS"], ["pbu", 10, "PASSES DEFENDED"], ["tackles", 50, "TACKLES"]],
	}[pos]
	var out: Array = []
	for d in defs:
		var target := maxi(1, int(round(float(d[1]) * k)))
		if int(d[1]) >= 100:
			target = maxi(10, int(round(target / 10.0)) * 10)
		out.append({"stat": d[0], "target": target, "text": "%d %s" % [target, d[2]], "xp": 400, "coins": 400, "done": false})
	return out


static func goal_progress(rtg: Dictionary, g: Dictionary) -> int:
	var st: Dictionary = rtg["season_stats"]
	var k := str(g["stat"])
	if k == "pbu":
		return int(st.get("pbu", 0)) + int(st.get("ints", 0))
	return int(st.get(k, 0))


## Award definitions: id -> [name, legacy points, XP, coins, dev trait it lifts you to].
const AWARDS := {
	"roy": ["ROOKIE OF THE YEAR", 15, 600, 1500, 1],
	"pro_bowl": ["PRO BOWL", 10, 400, 800, 1],
	"all_pro": ["ALL-PRO", 20, 700, 1500, 2],
	"opoy": ["OFFENSIVE PLAYER OF THE YEAR", 30, 1000, 2500, 3],
	"dpoy": ["DEFENSIVE PLAYER OF THE YEAR", 30, 1000, 2500, 3],
	"mvp": ["MVP", 40, 1200, 3000, 3],
	"ring": ["SUPER BOWL CHAMPION", 25, 800, 3000, 0],
}


## Season rating 0..100 for awards: production per game against an all-pro pace + grades.
static func season_score(pos: String, st: Dictionary, games: int, grade_avg: float) -> float:
	var g := maxf(games, 1.0)
	var prod := 0.0
	match pos:
		"QB":
			prod = (float(st["pass_yds"]) / g / 270.0) * 40.0 + (float(st["pass_td"]) / g / 2.0) * 35.0 \
					- (float(st["ints_thrown"]) / g / 0.8) * 10.0 + (float(st["rush_yds"]) / g / 40.0) * 8.0
		"RB":
			prod = (float(st["rush_yds"]) / g / 85.0) * 45.0 + (float(st["rush_td"] + st["rec_td"]) / g / 0.75) * 30.0 \
					+ (float(st["rec_yds"]) / g / 30.0) * 8.0 - float(st["fumbles"]) * 2.0
		"WR":
			prod = (float(st["rec_yds"]) / g / 80.0) * 45.0 + (float(st["rec_td"]) / g / 0.6) * 30.0 \
					+ (float(st["rec"]) / g / 5.5) * 10.0 - float(st["drops"]) * 1.0
		"CB":
			prod = (float(st["ints"]) / g / 0.3) * 35.0 + (float(st["pbu"]) / g / 0.8) * 20.0 \
					+ (float(st["tackles"]) / g / 4.0) * 10.0 + clampf(1.0 - float(st["comp_allowed"]) / maxf(float(st["def_targets"]), 1.0), 0.0, 1.0) * 25.0 \
					- float(st["td_allowed"]) * 1.5
	return clampf(prod * 0.75 + (grade_avg - 50.0) * 0.6, 0.0, 120.0)


static func grade_avg(rtg: Dictionary) -> float:
	var n := 0
	var sum := 0.0
	for g in rtg.get("games", []):
		sum += float(g["pts"])
		n += 1
	return sum / n if n > 0 else 60.0


## The awards you won this season (ids), from your season score and your team's record.
static func season_awards(rtg: Dictionary) -> Array[String]:
	var pos := str(rtg["player"]["pos"])
	var games := 0
	var wins := 0
	for g in rtg.get("games", []):
		games += 1
		if int(g["pf"]) > int(g["pa"]):
			wins += 1
	var sc := season_score(pos, rtg["season_stats"], games, grade_avg(rtg))
	var ovr_now := player_ovr(rtg)
	var out: Array[String] = []
	var win_pct := float(wins) / maxf(games, 1)
	if int(rtg["year"]) == 1 and sc >= 62.0:
		out.append("roy")
	if sc >= 68.0 or (sc >= 58.0 and ovr_now >= 85):
		out.append("pro_bowl")
	if sc >= 84.0 and ovr_now >= 80:
		out.append("all_pro")
	if sc >= 96.0 and ovr_now >= 84:
		out.append("dpoy" if pos == "CB" else "opoy")
	if pos in ["QB", "RB"] and sc >= 100.0 and win_pct >= 0.65 and ovr_now >= 86:
		out.append("mvp")
	return out


## Wraps up a season: awards (XP, coins, legacy, dev trait), the career log entry. Returns
## {awards: [ids], coins, xp, legacy}.
static func close_season(rtg: Dictionary) -> Dictionary:
	var awards := season_awards(rtg)
	var s: Dictionary = rtg["season"]
	if s.get("playoffs", {}).get("champion", "") == rtg["team"]:
		awards.append("ring")
	var coins := 0
	var xp := 0
	var legacy := 0
	var p: Dictionary = rtg["player"]
	for id in awards:
		var a: Array = AWARDS[id]
		legacy += int(a[1])
		xp += int(a[2])
		coins += int(a[3])
		p["dev"] = maxi(int(p.get("dev", 0)), int(a[4]))
		(rtg["awards"] as Array).append({"year": int(rtg["year"]), "id": id, "name": a[0]})
	var ovr_now := player_ovr(rtg)
	_track_peak(rtg)
	legacy += 5 if ovr_now >= 80 else (2 if ovr_now >= 70 else 0)
	legacy += _milestones(str(p["pos"]), rtg["season_stats"])
	rtg["legacy"] = int(rtg.get("legacy", 0)) + legacy
	rtg["xp"] = int(rtg["xp"]) + xp
	var wins := 0
	var losses := 0
	for g in rtg["games"]:
		if int(g["pf"]) > int(g["pa"]):
			wins += 1
		elif int(g["pf"]) < int(g["pa"]):
			losses += 1
	(rtg["career"] as Array).append({"year": int(rtg["year"]), "team": rtg["team"], "games": (rtg["games"] as Array).size(),
			"stats": (rtg["season_stats"] as Dictionary).duplicate(), "grade": RtgTracker.letter(grade_avg(rtg)),
			"awards": awards.duplicate(), "ovr": ovr_now, "age": int(p["age"]), "wins": wins, "losses": losses})
	return {"awards": awards, "coins": coins, "xp": xp, "legacy": legacy}


## Legacy points for a big season.
static func _milestones(pos: String, st: Dictionary) -> int:
	match pos:
		"QB":
			return (5 if int(st["pass_yds"]) >= 4000 else 0) + (5 if int(st["pass_td"]) >= 30 else 0)
		"RB":
			return (5 if int(st["rush_yds"]) >= 1000 else 0) + (5 if int(st["rush_td"]) >= 10 else 0)
		"WR":
			return (5 if int(st["rec_yds"]) >= 1000 else 0) + (5 if int(st["rec_td"]) >= 10 else 0)
		"CB":
			return (5 if int(st["ints"]) >= 5 else 0) + (3 if int(st["pbu"]) >= 12 else 0)
	return 0


# ---------------------------------------------------------------- offseason

## Age a year; from 30 the legs go first. Returns the attribute changes {attr: delta}.
static func age_player(rtg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var p: Dictionary = rtg["player"]
	p["age"] = int(p["age"]) + 1
	var age := int(p["age"])
	var out := {}
	if age < 30:
		return out
	var hit := 1 + (1 if age >= 32 else 0) + (1 if age >= 34 else 0)
	for k in ["spd", "acc", "elu", "thp"]:
		if not p["attrs"].has(k) or (k == "thp" and age < 33):
			continue
		var d := -rng.randi_range(hit - 1, hit + 1) if k in ["spd", "acc"] else -rng.randi_range(0, hit)
		if d != 0:
			p["attrs"][k] = clampi(int(p["attrs"][k]) + d, 30, 99)
			out[k] = d
	if age >= 31 and p["attrs"].has("awr"):
		p["attrs"]["awr"] = mini(int(p["attrs"]["awr"]) + 1, 99)   # wiser every year
		out["awr"] = 1
	return out


## Contract offers when your deal runs out: three other teams and your own, by OVR.
static func contract_offers(rtg: Dictionary, teams: Dictionary, team_ovr: Dictionary, rng: RandomNumberGenerator) -> Array:
	var you := str(rtg["team"])
	var o := player_ovr(rtg)
	var base := clampf(1.0 + (o - 60) * 0.55, 0.9, 30.0)
	var others: Array = teams.keys()
	others.erase(you)
	# Good players hear from good teams more.
	others.sort_custom(func(a: String, b: String) -> bool: return int(team_ovr.get(a, 75)) > int(team_ovr.get(b, 75)))
	var pool := others.slice(0, 16) if o >= 80 else others
	var out: Array = []
	var picked := {}
	while out.size() < 3 and picked.size() < pool.size():
		var t: String = pool[rng.randi() % pool.size()]
		if picked.has(t):
			continue
		picked[t] = true
		out.append({"team": t, "years": rng.randi_range(2, 5), "salary": salary_text(base * rng.randf_range(0.95, 1.2))})
	out.append({"team": you, "years": rng.randi_range(2, 4), "salary": salary_text(base * (0.9 + int(rtg["trust"]) / 500.0)), "stay": true})
	return out


## Retirement: can you choose it now? Must you?
static func can_retire(rtg: Dictionary) -> bool:
	return int(rtg["year"]) >= 4 or int(rtg["player"]["age"]) >= 30


static func must_retire(rtg: Dictionary) -> String:
	var p: Dictionary = rtg["player"]
	if int(p["age"]) >= RETIRE_AGE:
		return "AGE"
	if int(p["age"]) >= 30 and player_ovr(rtg) < 60:
		return "DECLINE"
	return ""


## Starts the next season: year + 1, aging, contract year used, trust drifts toward 50.
## Returns the aging changes.
static func next_season(rtg: Dictionary, teams: Dictionary, strengths: Dictionary, games: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var changes := age_player(rtg, rng)
	rtg["year"] = int(rtg["year"]) + 1
	rtg["trust"] = int(round(lerpf(float(rtg["trust"]), 50.0, 0.3)))
	var c: Dictionary = rtg.get("contract", {})
	c["years"] = int(c.get("years", 1)) - 1
	rtg["contract"] = c
	rtg["offers"] = []
	start_season(rtg, teams, strengths, games, rng)
	return changes


static func contract_up(rtg: Dictionary) -> bool:
	return int(rtg.get("contract", {}).get("years", 0)) <= 1


## Sign with a team (an offer). Changing teams resets trust a bit.
static func sign(rtg: Dictionary, offer: Dictionary) -> void:
	if str(offer["team"]) != str(rtg["team"]):
		rtg["trust"] = mini(int(rtg["trust"]), 45)
	rtg["team"] = offer["team"]
	rtg["contract"] = {"years": int(offer["years"]) + 1, "salary": offer["salary"]}


## Hangs it up: the career becomes a legend entry (Hall of Fame when the legacy is big enough).
static func retire(rtg: Dictionary, reason: String) -> Dictionary:
	rtg["stage"] = "retired"
	rtg["retire_reason"] = reason
	var p: Dictionary = rtg["player"]
	var counts := {}
	for a in rtg["awards"]:
		counts[a["id"]] = int(counts.get(a["id"], 0)) + 1
	var totals := RtgTracker.empty_stats()
	for c in rtg["career"]:
		add_stats(totals, c["stats"])
	return {"name": p["name"], "first": p["first"], "last": p["last"], "pos": p["pos"], "jersey": p["jersey"],
			"look": p.get("look", {}), "attrs": (p["attrs"] as Dictionary).duplicate(), "peak": int(rtg.get("peak_ovr", 0)),
			"seasons": (rtg["career"] as Array).size(), "team": rtg["team"], "legacy": int(rtg["legacy"]),
			"hof": int(rtg["legacy"]) >= HOF_LEGACY, "awards": counts, "rings": int(rtg.get("rings", 0)),
			"totals": totals, "id": str(rtg.get("id", "rtg_%d" % absi(hash(str(p["name"]) + str(rtg.get("xp_total", 0)))))),
			"peak_attrs": (rtg.get("peak_attrs", p["attrs"]) as Dictionary).duplicate()}
