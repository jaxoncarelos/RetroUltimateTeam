class_name DefensePace
extends RefCounted
## "Defense Pace" setting (PLAN.md §4): which CPU-offense snaps the human actually plays.
## The rest are auto-simulated and shown as a quick result.

enum Pace { EVERY_SNAP, KEY_DOWNS, HIGHLIGHTS }

const NAMES := ["EVERY SNAP", "KEY DOWNS", "HIGHLIGHTS"]


## situation: {down, to_go, los_x (offense's field x), half_seconds_left, score_diff (offense's)}
static func human_plays(pace: int, situation: Dictionary) -> bool:
	var down := int(situation.get("down", 1))
	var los_x := float(situation.get("los_x", 35.0))
	var half_left := float(situation.get("half_seconds_left", 9999.0))
	var red_zone := FieldGeo.OPP_GOAL - los_x <= 20.0
	var two_minute := half_left <= 120.0
	match pace:
		Pace.EVERY_SNAP:
			return true
		Pace.KEY_DOWNS:
			return down >= 3 or red_zone or two_minute
		Pace.HIGHLIGHTS:
			var close := absi(int(situation.get("score_diff", 0))) <= 8
			return down == 4 or (down == 3 and red_zone) or (two_minute and close)
	return true


static func from_name(s: String) -> int:
	match s.to_lower():
		"key", "key_downs", "keydowns":
			return Pace.KEY_DOWNS
		"highlights", "high":
			return Pace.HIGHLIGHTS
	return Pace.EVERY_SNAP
