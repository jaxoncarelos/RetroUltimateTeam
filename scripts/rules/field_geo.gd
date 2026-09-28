class_name FieldGeo
extends RefCounted
## Field coordinates in yards. x: 0..120 (end zones included), y: 0..53.33 (top sideline = 0).
## The offense always attacks toward +x; own goal line is x=10, opponent goal line x=110.

const LENGTH := 120.0
const WIDTH := 53.33
const OWN_GOAL := 10.0
const OPP_GOAL := 110.0
const CENTER_Y := WIDTH * 0.5
const HASH_TOP := 23.58
const HASH_BOTTOM := 29.75


## Yard line number shown to the player (0..50).
static func yard_line_number(x: float) -> int:
	var yl := int(round(x - OWN_GOAL))
	return yl if yl <= 50 else 100 - yl


## "OWN 25" / "OPP 40" / "50" relative to the team driving toward +x.
static func spot_text(x: float) -> String:
	var yl := int(round(x - OWN_GOAL))
	if yl == 50:
		return "50"
	return ("OWN %d" % yl) if yl < 50 else ("OPP %d" % (100 - yl))


static func clamp_to_hashes(y: float) -> float:
	return clampf(y, HASH_TOP, HASH_BOTTOM)


static func is_out_of_bounds(p: Vector2) -> bool:
	return p.y < 0.0 or p.y > WIDTH or p.x < 0.0 or p.x > LENGTH
