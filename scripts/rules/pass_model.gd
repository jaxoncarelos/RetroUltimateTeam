class_name PassModel
extends RefCounted
## Pure pass geometry (node-free): trajectory planning from bullet to lob, clearing
## defenders in the throwing lane, in-flight reach checks, catch-point contest geometry and
## aim assist. Constants come from GameplayTuning.
##
## A throw plan is {"landing": Vector2, "dur": float, "apex": float, "loft": float, "kind": Kind}.
##   loft 0 = flat bullet, 1 = full lob. Apex is yards above the straight release→catch line.
##   Duration is the longer of "arm speed" (dist / throw speed) and the hang time a ball
##   with that apex needs under the game's gravity, so the arc always looks physical.

enum Kind { BULLET, TOUCH, LOB }

const RELEASE_Z := 2.0
const CATCH_Z := 1.3
const KIND_NAMES := ["BULLET", "TOUCH", "LOB"]


## Ball height (yards) at normalized flight time u for an arc with this apex.
static func height_at(apex: float, u: float) -> float:
	return lerpf(RELEASE_Z, CATCH_Z, u) + 4.0 * apex * u * (1.0 - u)


## Automatic loft for a throw of `dist` yards: bullets short, lobs deep.
static func auto_loft(t: GameplayTuning, dist: float) -> float:
	return smoothstep(t.lob_start, t.lob_full, dist)


static func bullet_apex(t: GameplayTuning, dist: float) -> float:
	return t.bullet_apex_base + dist * t.bullet_apex_per_yd


static func lob_apex(t: GameplayTuning, dist: float) -> float:
	return t.lob_apex_base + dist * t.lob_apex_per_yd


static func apex_for(t: GameplayTuning, dist: float, loft: float) -> float:
	return lerpf(bullet_apex(t, dist), lob_apex(t, dist), clampf(loft, 0.0, 1.0))


static func loft_for_apex(t: GameplayTuning, dist: float, apex: float) -> float:
	var lo := bullet_apex(t, dist)
	var hi := lob_apex(t, dist)
	return clampf((apex - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)


static func kind_of(t: GameplayTuning, loft: float) -> Kind:
	if loft >= t.lob_threshold:
		return Kind.LOB
	if loft >= t.touch_threshold:
		return Kind.TOUCH
	return Kind.BULLET


## Flight time: arm speed vs. hang time under game gravity (whichever is longer). A flat
## bullet is all arm; from TOUCH loft up the hang time fully applies.
static func duration(t: GameplayTuning, thp: float, dist: float, apex: float, loft := 1.0) -> float:
	var arm := dist / RatingModel.throw_speed(t, thp)
	var hang := sqrt(8.0 * maxf(apex, 0.0) / t.ball_gravity)
	var k := clampf(loft / maxf(t.touch_threshold, 0.01), 0.0, 1.0)
	return maxf(maxf(arm, lerpf(arm, hang, k)), 0.25)


## Minimum apex that carries the ball over every defender standing in the throwing lane.
## `blockers` are defender ground positions (already projected to when the ball passes).
## Defenders near the QB (rushers) or near the target (the coverage man) can't be lobbed
## over, so only those in the middle of the lane count.
static func clearance_apex(t: GameplayTuning, from: Vector2, to: Vector2, blockers: PackedVector2Array) -> float:
	var v := to - from
	var dist := v.length()
	if dist < 1.0:
		return 0.0
	var dir := v / dist
	var need := 0.0
	for b in blockers:
		var rel := b - from
		var s := rel.dot(dir)
		if s < t.lane_skip_near or s > dist - t.lane_skip_far:
			continue
		if absf(rel.cross(dir)) > t.lane_width:
			continue
		var u := s / dist
		var base := lerpf(RELEASE_Z, CATCH_Z, u)
		need = maxf(need, (t.lane_clear_height - base) / (4.0 * u * (1.0 - u)))
	return need


## Full throw plan. Loft is automatic (distance), raised to clear lane blockers but never
## above a full lob for that distance.
static func plan(t: GameplayTuning, thp: float, from: Vector2, landing: Vector2,
		blockers := PackedVector2Array(), kind_override := -1) -> Dictionary:
	var dist := from.distance_to(landing)
	if kind_override >= 0:
		# The player picked the pass type: a flat bullet, a touch pass or a high lob, no matter
		# who stands in the lane (a bullet through traffic is the risk he chose).
		var lofts := [0.0, (t.touch_threshold + t.lob_threshold) * 0.5, 1.0]
		var picked := float(lofts[clampi(kind_override, 0, 2)])
		var apex_p := apex_for(t, dist, picked)
		return {"landing": landing, "dur": duration(t, thp, dist, apex_p, picked), "apex": apex_p,
				"loft": picked, "kind": clampi(kind_override, 0, 2)}
	var auto := apex_for(t, dist, auto_loft(t, dist))
	var clear := clearance_apex(t, from, landing, blockers)
	var apex := minf(maxf(auto, clear), lob_apex(t, dist))
	var loft := loft_for_apex(t, dist, apex)
	var kind := kind_of(t, loft)
	if clear > auto and kind == Kind.BULLET:
		# Lofted over a defender: always telegraph it as a touch pass.
		kind = Kind.TOUCH
		loft = maxf(loft, t.touch_threshold)
	return {"landing": landing, "dur": duration(t, thp, dist, apex, loft), "apex": apex,
			"loft": loft, "kind": kind}


## Distance from p to segment a-b.
static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var s := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * s)


## True when a defender at ground distance `ground_d` from the ball can get a hand on it
## at height z (standing reach, plus his leap if he is jumping).
static func can_reach(t: GameplayTuning, ground_d: float, z: float, extra_height := 0.0) -> bool:
	return ground_d <= t.lane_reach and z <= t.reach_height + extra_height


## How much a defender contests a catch (0 open .. 1 blanketed), from where both players
## are when the ball comes down. A defender trailing the receiver (the receiver is between
## him and the ball's landing spot, i.e. the receiver has a step) contests much less.
## A hanging ball (loft) gives a nearby defender time to close: his contest reach grows.
static func contest(t: GameplayTuning, landing: Vector2, rec: Vector2, def: Vector2, loft := 0.0) -> float:
	var dd := def.distance_to(landing)
	var c := clampf(1.0 - dd / (t.contest_radius + t.lob_contest_extra * loft), 0.0, 1.0)
	if c <= 0.0:
		return 0.0
	# Receiver shields: he is closer to the spot and the defender is on his far side.
	var to_spot := landing - rec
	var to_def := def - rec
	if rec.distance_to(landing) < dd and to_spot.length() > 0.05 and to_def.length() > 0.05 \
			and to_spot.normalized().dot(to_def.normalized()) < -0.2:
		c *= t.trail_contest_mult
	return c


## Aim assist: pulls a raw landing point toward the nearest receiver lead point within
## aim_assist_radius. Returns {"point": Vector2, "index": int} (index -1 = no snap).
static func assist(t: GameplayTuning, raw: Vector2, leads: PackedVector2Array) -> Dictionary:
	var best := -1
	var best_d := t.aim_assist_radius
	for i in leads.size():
		var d := raw.distance_to(leads[i])
		if d < best_d:
			best_d = d
			best = i
	if best < 0 or t.aim_assist_strength <= 0.0:
		return {"point": raw, "index": -1}
	# Stronger the closer the reticle already is (never a hard snap at the edge).
	var k := t.aim_assist_strength * (1.0 - best_d / t.aim_assist_radius * 0.5)
	return {"point": raw.lerp(leads[best], k), "index": best}


## Slingshot pull (pixels) -> throw distance (yards). Slightly progressive so deep balls
## don't need a screen-wide drag while short throws stay precise.
static func pull_to_yards(t: GameplayTuning, pull_px: float, sens := 1.0) -> float:
	return pull_px * t.aim_gain * sens * (1.0 + pull_px / t.aim_curve_px)
