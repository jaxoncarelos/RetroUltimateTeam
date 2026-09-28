class_name Profile
extends RefCounted
## The player's save data (PLAN.md §3 SaveData): franchise, coins, owned cards (ids only),
## lineup, season/challenge progress, objectives, coach level, login streak, unopened reward
## packs and stats. to_dict()/from_dict() for SaveManager; migrate() upgrades old versions.
## Pure (no nodes, no catalog lookups).

const VERSION := 2
const START_COINS := 1200
const LEGACY_TIERS := ["_bronze", "_silver", "_gold", "_elite"]

var version := VERSION
var franchise_team := ""
var coins := START_COINS
var next_uid := 1
var cards: Array = []            ## [{uid, def, t, locked, boost, xp, dev}]
var lineup: Dictionary = {}      ## slot -> uid
var season: Dictionary = {}
var challenges: Dictionary = {}
var stats := {"games": 0, "wins": 0, "losses": 0, "ties": 0, "packs_opened": 0, "last_win_day": 0,
		"coins_earned": 0, "win_streak": 0, "best_streak": 0}
var sets_done: Dictionary = {}
var objectives: Dictionary = {}  ## ObjectiveRules state {day, week, progress, claimed, totals}
var coach := {"xp": 0, "level": 1}   ## ProgressionRules (coach level 1..50)
var login := {"day": 0, "streak": 0}   ## DailyRules (unix day of the last check-in)
var pending_packs: Array = []    ## reward pack ids waiting to be opened (EconomyRules.open_pending)


func has_team() -> bool:
	return franchise_team != ""


func add_card(def_id: String, unix_time := 0) -> int:
	var uid := next_uid
	next_uid += 1
	cards.append({"uid": uid, "def": def_id, "t": unix_time, "locked": false, "boost": 0, "xp": 0, "dev": 0})
	return uid


func find(uid: int) -> Dictionary:
	for c in cards:
		if int(c["uid"]) == uid:
			return c
	return {}


func remove(uid: int) -> bool:
	for i in cards.size():
		if int(cards[i]["uid"]) == uid:
			cards.remove_at(i)
			for slot in lineup.keys():
				if int(lineup[slot]) == uid:
					lineup.erase(slot)
			return true
	return false


func in_lineup(uid: int) -> bool:
	for slot in lineup:
		if int(lineup[slot]) == uid:
			return true
	return false


func to_dict() -> Dictionary:
	return {
		"version": version, "franchise_team": franchise_team, "coins": coins, "next_uid": next_uid,
		"cards": cards.duplicate(true), "lineup": lineup.duplicate(), "season": season.duplicate(true),
		"challenges": challenges.duplicate(true), "stats": stats.duplicate(), "sets_done": sets_done.duplicate(),
		"objectives": objectives.duplicate(true), "coach": coach.duplicate(), "login": login.duplicate(),
		"pending_packs": pending_packs.duplicate(),
	}


static func from_dict(d: Dictionary) -> Profile:
	var data := migrate(d)
	var p := Profile.new()
	p.version = VERSION
	p.franchise_team = str(data.get("franchise_team", ""))
	p.coins = int(data.get("coins", START_COINS))
	p.next_uid = int(data.get("next_uid", 1))
	p.cards = []
	for c in data.get("cards", []):
		p.cards.append({"uid": int(c.get("uid", 0)), "def": str(c.get("def", "")), "t": int(c.get("t", 0)),
				"locked": bool(c.get("locked", false)), "boost": int(c.get("boost", 0)),
				"xp": int(c.get("xp", 0)), "dev": int(c.get("dev", 0))})
	p.lineup = {}
	var lu: Dictionary = data.get("lineup", {})
	for slot in lu:
		p.lineup[str(slot)] = int(lu[slot])
	p.season = data.get("season", {})
	p.challenges = data.get("challenges", {})
	var st: Dictionary = data.get("stats", {})
	for k in p.stats:
		p.stats[k] = int(st.get(k, 0))
	p.sets_done = data.get("sets_done", {})
	p.objectives = _ints_deep(data.get("objectives", {}))
	var co: Dictionary = data.get("coach", {})
	p.coach = {"xp": int(co.get("xp", 0)), "level": maxi(1, int(co.get("level", 1)))}
	var lg: Dictionary = data.get("login", {})
	p.login = {"day": int(lg.get("day", 0)), "streak": int(lg.get("streak", 0))}
	p.pending_packs = []
	for id in data.get("pending_packs", []):
		p.pending_packs.append(str(id))
	return p


## JSON turns every number into a float; objective counters are ints.
static func _ints_deep(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[str(k)] = _ints_deep(v[k])
		return out
	if v is Array:
		var arr := []
		for x in v:
			arr.append(_ints_deep(x))
		return arr
	if v is float and is_equal_approx(v, round(v)):
		return int(v)
	return v


## Version chain.
## v0 (pre-release) stored "team" instead of "franchise_team" and no uids.
## v1 -> v2: tier cards ("mahomes_patrick_gold") became one real-rating base card per player
##   ("mahomes_patrick"); cards gain xp/dev; coach XP is back-filled from games played.
static func migrate(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var v := int(out.get("version", 0))
	if v < 1:
		if out.has("team") and not out.has("franchise_team"):
			out["franchise_team"] = out["team"]
		var uid := 1
		var fixed := []
		for c in out.get("cards", []):
			var entry: Dictionary = c if c is Dictionary else {"def": str(c)}
			if not entry.has("uid"):
				entry["uid"] = uid
			uid = maxi(uid, int(entry["uid"])) + 1
			fixed.append(entry)
		out["cards"] = fixed
		out["next_uid"] = maxi(int(out.get("next_uid", 1)), uid)
		out["version"] = 1
		v = 1
	if v < 2:
		for entry in out.get("cards", []):
			entry["def"] = legacy_to_base_id(str(entry.get("def", "")))
			entry["xp"] = int(entry.get("xp", 0))
			entry["dev"] = int(entry.get("dev", 0))
		var st: Dictionary = out.get("stats", {})
		if not out.has("coach"):
			var xp := int(st.get("games", 0)) * 100
			out["coach"] = {"xp": xp, "level": ProgressionRules.level_from_xp(xp)}   # no back-paid rewards
		out["version"] = 2
	return out


## "mahomes_patrick_gold" -> "mahomes_patrick" (ids without a tier suffix are unchanged).
static func legacy_to_base_id(def_id: String) -> String:
	for suffix in LEGACY_TIERS:
		if def_id.ends_with(suffix):
			return def_id.left(def_id.length() - suffix.length())
	return def_id
