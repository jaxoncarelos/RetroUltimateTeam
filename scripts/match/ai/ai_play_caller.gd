class_name AIPlayCaller
extends RefCounted
## CPU play calling. Defense: weighted random over the playbook, weighted by what the
## DefenseMemory has learned (counter-calls), down & distance, and situational tags.
## Situation dict: {down, to_go, los_x, score_diff, seconds_left} (offense's perspective
## for los_x; score_diff from the calling side's perspective).


## Rough prior of what the offense will call, by down & distance.
static func expected_categories(situation: Dictionary) -> Dictionary:
	var down := int(situation.get("down", 1))
	var to_go := int(situation.get("to_go", 10))
	if to_go <= 2 and down >= 2:
		return {"RUN": 0.6, "SHORT": 0.3, "DEEP": 0.1}
	if to_go >= 8 and down >= 2:
		return {"RUN": 0.15, "SHORT": 0.45, "DEEP": 0.4}
	return {"RUN": 0.4, "SHORT": 0.4, "DEEP": 0.2}


## Situational fit of a defensive call from its tags (goal_line, prevent, short_yardage).
static func defense_situation_mult(p: PlayDef, situation: Dictionary) -> float:
	var los_x := float(situation.get("los_x", 35.0))
	var to_go := int(situation.get("to_go", 10))
	var down := int(situation.get("down", 1))
	var near_goal := los_x >= FieldGeo.OPP_GOAL - 5.0
	var m := 1.0
	if "goal_line" in p.tags:
		m *= 2.5 if near_goal or (to_go <= 1 and down >= 3) else 0.08
	if "prevent" in p.tags:
		var late := float(situation.get("seconds_left", 999.0)) < 40.0 and int(situation.get("score_diff", 0)) > 0
		m *= 2.0 if late or to_go >= 18 else 0.1
	if near_goal and ("deep" in p.tags):
		m *= 0.4
	return m


## Weights for every defensive call (same order as `plays`). `iq` (difficulty) is an exponent
## on the read of your tendencies: 0 ignores them, 1 = as designed, above 1 jumps on the counter.
static func defense_weights(plays: Array[PlayDef], memory: DefenseMemory, situation: Dictionary,
		last_call: PlayDef = null, iq := 1.0) -> PackedFloat32Array:
	var expected := expected_categories(situation)
	var out := PackedFloat32Array()
	for p in plays:
		var w := pow(memory.counter_weight(p.counters, expected), iq) if memory != null else 1.0
		w *= defense_situation_mult(p, situation)
		if memory != null and p.category == "BLITZ" and "goal_line" not in p.tags and "RUN" not in p.counters:
			w *= memory.tuning.blitz_weight
		if p == last_call and memory != null:
			w *= memory.tuning.repeat_call_penalty
		out.append(maxf(w, 0.001))
	return out


static func pick_defense(plays: Array[PlayDef], memory: DefenseMemory, situation: Dictionary,
		rng: RandomNumberGenerator, last_call: PlayDef = null, iq := 1.0) -> PlayDef:
	var w := defense_weights(plays, memory, situation, last_call, iq)
	return plays[weighted_index(w, rng)]


## CPU 4th-down call: "go", "fg" or "punt". fg_dist/fg_max in yards. `iq` = coach smarts
## (DefenseAITuning.coach_iq_by_difficulty): a timid coach (< 0.4) punts unless desperate and
## only kicks chip shots; a sharp one (>= 0.85) goes for it on short yardage past his own 40
## and in the no-man's land just outside field goal range.
static func fourth_down(situation: Dictionary, fg_dist: float, fg_max: float, iq := 0.7) -> String:
	var to_go := int(situation.get("to_go", 10))
	var los_x := float(situation.get("los_x", 35.0))
	var diff := int(situation.get("score_diff", 0))
	var secs := float(situation.get("seconds_left", 999.0))
	var in_range := fg_dist <= fg_max - (6.0 if iq < 0.4 else 2.0)
	var late := secs < 240.0
	if iq >= 0.85 and not (late and diff > 0):
		if to_go <= 2 and los_x >= FieldGeo.OWN_GOAL + 40.0:
			return "go"
		if to_go <= 4 and not in_range and los_x >= FieldGeo.OWN_GOAL + 60.0:
			return "go"
	if iq < 0.4 and not (late and diff < 0):
		return "fg" if in_range else "punt"
	if late and diff < 0:
		# Trailing late: kick only if a FG ties or wins, otherwise keep the ball.
		if in_range and diff >= -3:
			return "fg"
		return "go"
	if to_go <= 1 and los_x >= FieldGeo.OWN_GOAL + 35.0:
		return "go"
	if in_range:
		return "fg"
	if to_go <= 2 and los_x >= FieldGeo.OWN_GOAL + 50.0:
		return "go"
	return "punt"


## CPU after a touchdown: go for two? `diff` = score difference after the 6 points.
static func go_for_two(diff: int, quarter: int, iq := 0.7) -> bool:
	if quarter < 4 or iq < 0.4:
		return false
	return diff in [-2, -5, -10, 1, 5]


static func weighted_index(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1
