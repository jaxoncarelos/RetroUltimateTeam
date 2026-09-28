class_name Profile
extends RefCounted
## The player's save data (PLAN.md §3 SaveData): franchise, coins, owned cards (ids only),
## lineup, season/challenge progress and stats. to_dict()/from_dict() for SaveManager;
## migrate() upgrades old versions. Pure (no nodes, no catalog lookups).

const VERSION := 1
const START_COINS := 1200

var version := VERSION
var franchise_team := ""
var coins := START_COINS
var next_uid := 1
var cards: Array = []            ## [{uid, def, t, locked, boost}]
var lineup: Dictionary = {}      ## slot -> uid
var season: Dictionary = {}
var challenges: Dictionary = {}
var stats := {"games": 0, "wins": 0, "losses": 0, "ties": 0, "packs_opened": 0, "last_win_day": 0,
		"coins_earned": 0}
var sets_done: Dictionary = {}


func has_team() -> bool:
	return franchise_team != ""


func add_card(def_id: String, unix_time := 0) -> int:
	var uid := next_uid
	next_uid += 1
	cards.append({"uid": uid, "def": def_id, "t": unix_time, "locked": false, "boost": 0})
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
				"locked": bool(c.get("locked", false)), "boost": int(c.get("boost", 0))})
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
	return p


## Version chain. v0 (pre-release) stored "team" instead of "franchise_team" and no uids.
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
	return out
