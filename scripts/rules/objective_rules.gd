class_name ObjectiveRules
extends RefCounted
## Coin objectives ("Throw a 40 yard pass", "Rush for 100 yards"…): daily, weekly and
## milestone goals that make it obvious how to earn coins. Pure logic.
## CONTRACT (used by UI code): keep these signatures stable.
## STUB: the economy pass replaces the internals.

## Objective dictionary shape returned to the UI:
## {"id": String, "kind": "daily"|"weekly"|"milestone", "title": String, "desc": String,
##  "reward": int (coins), "progress": int, "target": int, "done": bool, "claimed": bool}


## Every objective currently shown to the player, dailies first.
static func active(_profile: Profile) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"id": "stub_pass40", "kind": "daily", "title": "AIR IT OUT",
			"desc": "Throw a 40 yard pass", "reward": 250, "progress": 0, "target": 1,
			"done": false, "claimed": false})
	return out


## Claims a finished objective; returns coins granted (0 if not claimable).
static func claim(_profile: Profile, _id: String) -> int:
	return 0


## Feeds one finished match's box score for the human team (GameState.stats[team] plus
## "won": bool, "longest_pass": int, "longest_run": int). Returns ids newly completed.
static func record_match(_profile: Profile, _box: Dictionary) -> Array[String]:
	return []


## Count of finished-but-unclaimed objectives (for a badge on the hub button).
static func claimable_count(profile: Profile) -> int:
	var n := 0
	for o in active(profile):
		if o["done"] and not o["claimed"]:
			n += 1
	return n
