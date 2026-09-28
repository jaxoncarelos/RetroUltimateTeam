class_name DownTracker
extends RefCounted
## Downs, distance and line of scrimmage for the team driving toward +x.
## Spots are snapped to whole yards.

enum Outcome { NEXT_DOWN, FIRST_DOWN, TOUCHDOWN, TURNOVER_ON_DOWNS, SAFETY }

var down := 1
var los_x := 35.0
var first_down_x := 45.0
var plays := 0


func start_drive(x: float) -> void:
	down = 1
	plays = 0
	los_x = round(x)
	first_down_x = minf(los_x + 10.0, FieldGeo.OPP_GOAL)


func to_go() -> int:
	return int(first_down_x - los_x)


func is_goal_to_go() -> bool:
	return first_down_x >= FieldGeo.OPP_GOAL


## Whole-yard spot for a dead ball at `spot_x` (the new line of scrimmage unless it scored
## or went for a safety): rounded, and never past the 1 — only the play scores touchdowns.
static func spot_yard(spot_x: float) -> float:
	return clampf(roundf(spot_x), 0.0, FieldGeo.OPP_GOAL - 1.0)


## Apply the dead-ball spot of a play. Incomplete passes pass the current los_x.
func apply_spot(spot_x: float, scored_td := false) -> Outcome:
	plays += 1
	# Only the play decides a touchdown (the ball crossed the plane). A carrier downed short of
	# the goal line is spotted at the 1 at best, never rounded or pushed into the end zone.
	var spot := spot_yard(spot_x)
	if scored_td:
		los_x = FieldGeo.OPP_GOAL
		return Outcome.TOUCHDOWN
	if spot <= FieldGeo.OWN_GOAL:
		los_x = FieldGeo.OWN_GOAL
		return Outcome.SAFETY
	if spot >= first_down_x:
		down = 1
		los_x = spot
		first_down_x = minf(spot + 10.0, FieldGeo.OPP_GOAL)
		return Outcome.FIRST_DOWN
	los_x = spot
	if down >= 4:
		return Outcome.TURNOVER_ON_DOWNS
	down += 1
	return Outcome.NEXT_DOWN


func down_text() -> String:
	var ordinal: String = ["1ST", "2ND", "3RD", "4TH"][clampi(down - 1, 0, 3)]
	var dist := "GOAL" if is_goal_to_go() else str(to_go())
	return "%s & %s" % [ordinal, dist]
