class_name AbilityRules
extends RefCounted
## X-Factor card abilities: in-game power-ups that switch on when the card's player (or
## your team) does something during a drive / defensive series / game, roguelite style.
## Example: GUNSLINGER QB — after 2 completions of 20+ yards in a drive his throw power and
## accuracy go up for the rest of that drive.
##
## Each ability: name, short text for the card/HUD, the positions that can carry it,
## `scope` (how long it lasts once on and when its counter resets: "drive" = your
## possession, "series" = the opponent's possession, "game"), the `trigger` that counts
## toward it (see count()), `need` (how many), `streak` (a miss resets the counter) and the
## attribute `boost` (+points while active). "clutch" abilities have no counter: they are
## on whenever their situation holds (clutch_on()). All balance numbers live here.
## Pure logic.

const DEFS := {
	# --- QB
	"gunslinger": {"name": "GUNSLINGER", "text": "2 COMPLETIONS OF 20+ YDS IN A DRIVE: +8 THP +4 THA",
			"pos": ["QB"], "scope": "drive", "trigger": "team_long_completion", "need": 2,
			"boost": {"thp": 8, "tha": 4}},
	"field_general": {"name": "FIELD GENERAL", "text": "3 STRAIGHT COMPLETIONS: +6 THA +6 AWR FOR THE DRIVE",
			"pos": ["QB"], "scope": "drive", "trigger": "team_completion", "need": 3, "streak": true,
			"boost": {"tha": 6, "awr": 6}},
	"two_minute": {"name": "TWO-MINUTE MAN", "text": "LAST 2:00 OF EACH HALF: +6 THA +8 AWR",
			"pos": ["QB"], "scope": "clutch", "trigger": "two_minute", "boost": {"tha": 6, "awr": 8}},
	# --- receivers / backs
	"deep_threat": {"name": "DEEP THREAT", "text": "CATCH A 20+ YD PASS: +5 SPD +4 ACC FOR THE DRIVE",
			"pos": ["WR", "TE"], "scope": "drive", "trigger": "own_long_catch", "need": 1,
			"boost": {"spd": 5, "acc": 4}},
	"route_tech": {"name": "ROUTE TECHNICIAN", "text": "2 CATCHES IN A DRIVE: +8 RTE +5 CTH",
			"pos": ["WR", "TE"], "scope": "drive", "trigger": "own_catch", "need": 2,
			"boost": {"rte": 8, "cth": 5}},
	"yac_monster": {"name": "YAC MONSTER", "text": "BREAK A TACKLE AFTER THE CATCH: +8 ELU +5 STR FOR THE DRIVE",
			"pos": ["WR", "TE", "RB"], "scope": "drive", "trigger": "own_catch_broken", "need": 1,
			"boost": {"elu": 8, "str": 5}},
	"safety_valve": {"name": "SAFETY VALVE", "text": "CATCH A 3RD-DOWN PASS: +8 CTH +6 AWR ALL GAME",
			"pos": ["TE", "RB"], "scope": "game", "trigger": "own_third_down_catch", "need": 1,
			"boost": {"cth": 8, "awr": 6}},
	"bell_cow": {"name": "BELL COW", "text": "3 CARRIES IN A DRIVE: +6 STR +6 ELU +2 SPD",
			"pos": ["RB"], "scope": "drive", "trigger": "own_carry", "need": 3,
			"boost": {"str": 6, "elu": 6, "spd": 2}},
	"home_run": {"name": "HOME RUN HITTER", "text": "A 10+ YD RUN: +5 SPD +5 ACC FOR THE DRIVE",
			"pos": ["RB"], "scope": "drive", "trigger": "own_long_run", "need": 1,
			"boost": {"spd": 5, "acc": 5}},
	# --- line
	"road_grader": {"name": "ROAD GRADER", "text": "2 RUNS OF 4+ YDS IN A DRIVE: +8 BLK +4 STR",
			"pos": ["OL"], "scope": "drive", "trigger": "team_good_run", "need": 2,
			"boost": {"blk": 8, "str": 4}},
	"pass_pro": {"name": "PASS PRO", "text": "3 PASSES WITHOUT A SACK: +8 BLK FOR THE DRIVE",
			"pos": ["OL"], "scope": "drive", "trigger": "team_clean_pass", "need": 3, "streak": true,
			"boost": {"blk": 8}},
	# --- defense
	"sack_artist": {"name": "SACK ARTIST", "text": "GET A SACK: +8 PRS +4 ACC ALL GAME",
			"pos": ["DL", "LB"], "scope": "game", "trigger": "own_sack", "need": 1,
			"boost": {"prs": 8, "acc": 4}},
	"run_stuffer": {"name": "RUN STUFFER", "text": "2 TACKLES FOR 2 YDS OR LESS IN A SERIES: +6 STR +6 TAK",
			"pos": ["DL", "LB"], "scope": "series", "trigger": "own_stuff", "need": 2,
			"boost": {"str": 6, "tak": 6}},
	"enforcer": {"name": "ENFORCER", "text": "2 TACKLES IN A SERIES: +8 TAK +4 SPD",
			"pos": ["LB", "S"], "scope": "series", "trigger": "own_tackle", "need": 2,
			"boost": {"tak": 8, "spd": 4}},
	"ballhawk": {"name": "BALLHAWK", "text": "BREAK UP OR PICK A PASS: +6 COV +4 CTH +3 SPD ALL GAME",
			"pos": ["CB", "S"], "scope": "game", "trigger": "own_pass_defended", "need": 1,
			"boost": {"cov": 6, "cth": 4, "spd": 3}},
	"lockdown": {"name": "LOCKDOWN", "text": "2 INCOMPLETIONS IN A SERIES: +6 COV +4 AWR",
			"pos": ["CB"], "scope": "series", "trigger": "team_incompletion", "need": 2,
			"boost": {"cov": 6, "awr": 4}},
	# --- kicker
	"ice_veins": {"name": "ICE IN THE VEINS", "text": "4TH QUARTER + OT: +8 KAC +4 KPW",
			"pos": ["K"], "scope": "clutch", "trigger": "fourth_quarter", "boost": {"kac": 8, "kpw": 4}},
}

const LONG_PASS := 20      ## yards: a "long" completion / catch
const LONG_RUN := 10
const GOOD_RUN := 4
const STUFF := 2           ## a tackle for this many yards or fewer on a run is a stuff
const TWO_MINUTE := 120.0


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## Ability ids a player at `pos` can carry.
static func for_position(pos: String) -> Array[String]:
	var out: Array[String] = []
	for id in DEFS:
		if pos in DEFS[id]["pos"]:
			out.append(id)
	out.sort()
	return out


## The one ability a player's X-Factor card carries (stable per player id).
static func ability_for(player_id: String, pos: String) -> String:
	var opts := for_position(pos)
	if opts.is_empty():
		return ""
	return opts[absi(hash(player_id)) % opts.size()]


## One-line HUD/card description: "GUNSLINGER: 2 COMPLETIONS OF ...".
static func describe(id: String) -> String:
	var d := get_def(id)
	return "" if d.is_empty() else "%s: %s" % [d["name"], d["text"]]


## How much one play counts toward `id` for the card in `slot`. ev (from the human
## team's point of view): {side: "offense"/"defense", type, yards, pass_thrown, run_play,
## down (before the snap), carrier_slot, tackler_slot, ball_def_slot, broken_tackles}.
## Returns 1 (count it), 0 (no change) or -1 (a miss: resets a streak counter).
static func count(id: String, slot: String, ev: Dictionary) -> int:
	var d := get_def(id)
	if d.is_empty():
		return 0
	var side := str(ev.get("side", ""))
	var type := str(ev.get("type", ""))
	var yards := int(ev.get("yards", 0))
	var passed: bool = ev.get("pass_thrown", false)
	var completed := passed and type in ["tackle", "td", "out", "fumble"]
	var mine := str(ev.get("carrier_slot", "")) == slot
	match str(d["trigger"]):
		"team_long_completion":
			return 1 if side == "offense" and completed and yards >= LONG_PASS else 0
		"team_completion":
			if side != "offense" or not (passed or type == "sack"):
				return 0
			return 1 if completed else -1
		"own_long_catch":
			return 1 if side == "offense" and completed and mine and yards >= LONG_PASS else 0
		"own_catch":
			return 1 if side == "offense" and completed and mine else 0
		"own_catch_broken":
			return 1 if side == "offense" and completed and mine and int(ev.get("broken_tackles", 0)) > 0 else 0
		"own_third_down_catch":
			return 1 if side == "offense" and completed and mine and int(ev.get("down", 1)) == 3 else 0
		"own_carry":
			return 1 if side == "offense" and ev.get("run_play", false) and not passed and mine else 0
		"own_long_run":
			return 1 if side == "offense" and ev.get("run_play", false) and not passed and mine and yards >= LONG_RUN else 0
		"team_good_run":
			return 1 if side == "offense" and ev.get("run_play", false) and not passed and yards >= GOOD_RUN else 0
		"team_clean_pass":
			if side != "offense":
				return 0
			if type == "sack":
				return -1
			return 1 if passed else 0
		"own_sack":
			return 1 if side == "defense" and type == "sack" and str(ev.get("tackler_slot", "")) == slot else 0
		"own_stuff":
			return 1 if side == "defense" and ev.get("run_play", false) and not passed and type == "tackle" \
					and yards <= STUFF and str(ev.get("tackler_slot", "")) == slot else 0
		"own_tackle":
			return 1 if side == "defense" and type in ["tackle", "sack"] and str(ev.get("tackler_slot", "")) == slot else 0
		"own_pass_defended":
			if side != "defense":
				return 0
			if type in ["int", "int_td"] and mine:
				return 1
			return 1 if type == "incomplete" and str(ev.get("ball_def_slot", "")) == slot else 0
		"team_incompletion":
			return 1 if side == "defense" and type in ["incomplete", "int", "int_td"] else 0
	return 0


## Whether a "clutch" ability is on in this situation {quarter, half_seconds_left}.
static func clutch_on(id: String, situation: Dictionary) -> bool:
	var d := get_def(id)
	if d.is_empty() or d["scope"] != "clutch":
		return false
	match str(d["trigger"]):
		"two_minute":
			return float(situation.get("half_seconds_left", 999.0)) <= TWO_MINUTE
		"fourth_quarter":
			return int(situation.get("quarter", 1)) >= 4
	return false


## Attributes with an ability's boost added (clamped to 99).
static func boosted(attrs: Dictionary, id: String) -> Dictionary:
	var out := attrs.duplicate()
	var b: Dictionary = get_def(id).get("boost", {})
	for k in b:
		if out.has(k):
			out[k] = mini(int(out[k]) + int(b[k]), 99)
	return out
