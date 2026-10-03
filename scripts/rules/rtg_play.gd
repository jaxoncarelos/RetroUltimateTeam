class_name RtgPlay
extends RefCounted
## Road to Glory play helpers: does a call feature your player, the coordinator's call (a
## share of calls go your way, more as the coach trusts you), audible options, your job in
## words ("SLANT ROUTE", "MAN: #18 J.CHASE, PRESS"), route names, and the receiver's hot
## routes. Pure logic.

## Hot routes a receiver can switch to pre-snap (path relative to his alignment, +x
## downfield, +y toward the ball's side of the field; mirrored per side by hot_route_path).
const HOT_ROUTES := {
	"GO": {"path": [Vector2(16, 0), Vector2(40, 0)], "end": "continue"},
	"SLANT": {"path": [Vector2(2, 0), Vector2(10, 7)], "end": "continue"},
	"OUT": {"path": [Vector2(10, 0), Vector2(10.5, -10)], "end": "continue"},
	"CURL": {"path": [Vector2(12, 0), Vector2(10, 1.5)], "end": "sit"},
	"POST": {"path": [Vector2(11, 0), Vector2(30, 11)], "end": "continue"},
}
const HOT_ORDER := ["PLAY", "GO", "SLANT", "OUT", "CURL", "POST"]


## True when `play` gives the player in `slot` the ball or a route to get it.
static func features(play: PlayDef, slot: String) -> bool:
	if play == null or play.side != "offense":
		return false
	var asg: Dictionary = play.assignments.get(slot, {})
	var t := str(asg.get("type", ""))
	if slot == "QB":
		return true
	if play.is_run():
		var qb: Dictionary = play.assignments.get("QB", {})
		return t == "carry" or str(qb.get("to", "")) == slot
	return t == "route"


## The offensive coordinator's call for your team. With probability 0.3 + 0.35 × trust (0..1)
## he dials up a play that features you (best situational fit among those), else his usual
## situational pick. Backs see more runs, receivers more passes.
static func oc_call(plays: Array[PlayDef], situation: Dictionary, rng: RandomNumberGenerator, slot: String,
		trust: float) -> PlayDef:
	var pick := PlayAdvisor.pick(plays, situation, rng)
	if rng.randf() >= 0.3 + 0.35 * clampf(trust, 0.0, 1.0):
		return pick
	var mine := featured(plays, situation, slot)
	if mine.is_empty():
		return pick
	# Mostly the best of them, sometimes the next ones (no robot coordinator).
	var i := 0
	var r := rng.randf()
	if r > 0.55:
		i = 1
	if r > 0.85:
		i = 2
	return mine[mini(i, mine.size() - 1)]


## Plays that feature `slot`, best situational fit first.
static func featured(plays: Array[PlayDef], situation: Dictionary, slot: String) -> Array[PlayDef]:
	var out: Array[PlayDef] = []
	for p in PlayAdvisor.rank(plays, situation):
		if features(p, slot):
			out.append(p)
	return out


## Up to `n` audible options that feature you (never the current call).
static func audibles(plays: Array[PlayDef], situation: Dictionary, slot: String, current: PlayDef, n := 3) -> Array[PlayDef]:
	var out: Array[PlayDef] = []
	for p in featured(plays, situation, slot):
		if p != current:
			out.append(p)
		if out.size() >= n:
			break
	return out


## +1 when the ball is toward +y of `start_y` (the inside of the field), else -1.
static func in_sign(start_y: float, ball_y: float) -> float:
	return 1.0 if ball_y >= start_y else -1.0


## Absolute-relative path for a hot route at an alignment (y mirrored toward the ball).
static func hot_route_path(name: String, start_y: float, ball_y: float) -> PackedVector2Array:
	var s := in_sign(start_y, ball_y)
	var out := PackedVector2Array()
	for p: Vector2 in HOT_ROUTES[name]["path"]:
		out.append(Vector2(p.x, p.y * s))
	return out


## Assignment dict for a hot route (a copy: play resources are never modified).
static func hot_assignment(base: Dictionary, name: String, start_y: float, ball_y: float) -> Dictionary:
	var a := base.duplicate()
	a["type"] = "route"
	a["path"] = hot_route_path(name, start_y, ball_y)
	a["end"] = HOT_ROUTES[name]["end"]
	a.erase("delay")
	return a


## Name of a route from its waypoints (relative path, `ins` = +1 when +y is inside).
static func route_name(path: PackedVector2Array, ins: float, end := "continue") -> String:
	if path.is_empty():
		return "ROUTE"
	var last := path[path.size() - 1]
	var prev := path[path.size() - 2] if path.size() >= 2 else Vector2.ZERO
	var seg := last - prev
	var depth := last.x
	var lateral := seg.y * ins    # + = breaking inside
	if end == "sit":
		return "CURL" if depth >= 8.0 else ("HITCH" if depth >= 4.0 else "CHECKDOWN")
	if seg.x < -0.5:
		return "COMEBACK"
	if absf(seg.y) < seg.x * 0.35:
		return "GO" if depth >= 14.0 else "SEAM"
	if absf(seg.x) < absf(seg.y) * 0.5:
		if depth < 4.0:
			return "DRAG" if lateral > 0.0 else "FLAT"
		return "IN" if lateral > 0.0 else "OUT"
	if lateral > 0.0:
		return "SLANT" if path[0].x <= 4.0 else "POST"
	return "WHEEL" if path[0].y * ins < -1.0 and depth > 8.0 else "CORNER"


## Your job on this call, in words for the pre-snap card.
static func job_text(play: PlayDef, slot: String, start_y := FieldGeo.CENTER_Y, ball_y := FieldGeo.CENTER_Y,
		lineup_names: Dictionary = {}) -> String:
	var asg: Dictionary = play.assignments.get(slot, {})
	var t := str(asg.get("type", "block"))
	match t:
		"route":
			var path: PackedVector2Array = asg.get("path", PackedVector2Array())
			return "RUN A %s ROUTE - GET OPEN" % route_name(path, in_sign(start_y, ball_y), str(asg.get("end", "continue")))
		"carry":
			return "TAKE THE HANDOFF - READ YOUR BLOCKS"
		"pass":
			return "DROP BACK AND FIND THE OPEN MAN"
		"handoff":
			return "HAND IT OFF"
		"sneak":
			return "QB SNEAK - PUSH THE PILE"
		"man":
			var who := str(lineup_names.get(asg.get("target", ""), asg.get("target", "")))
			return "MAN COVERAGE: %s%s" % [who, " - PRESS HIM" if asg.get("press", false) else ""]
		"zone":
			return "ZONE: %s" % zone_name(asg.get("center", Vector2(8, 0)), asg.get("size", Vector2(10, 10)))
		"rush":
			return "BLITZ! GET TO THE QUARTERBACK"
	if play.side == "offense" and slot in ["WR1", "WR2", "TE"]:
		return "BLOCK FOR THE BALL CARRIER" if play.is_run() else "STAY IN AND BLOCK"
	if slot == "RB":
		return "STAY IN AND PROTECT THE QB"
	return "DO YOUR JOB"


static func zone_name(center: Vector2, size: Vector2) -> String:
	if center.x >= 13.0:
		return "DEEP HALF" if size.y >= 22.0 else ("DEEP MIDDLE" if absf(center.y) < 4.0 else "DEEP THIRD")
	if absf(center.y) >= 9.0 and center.x < 7.0:
		return "FLAT"
	return "CURL / HOOK"
