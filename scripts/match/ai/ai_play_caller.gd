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


## Weights for every defensive call (same order as `plays`).
static func defense_weights(plays: Array[PlayDef], memory: DefenseMemory, situation: Dictionary,
		last_call: PlayDef = null) -> PackedFloat32Array:
	var expected := expected_categories(situation)
	var out := PackedFloat32Array()
	for p in plays:
		var w := memory.counter_weight(p.counters, expected) if memory != null else 1.0
		w *= defense_situation_mult(p, situation)
		if p == last_call and memory != null:
			w *= memory.tuning.repeat_call_penalty
		out.append(maxf(w, 0.001))
	return out


static func pick_defense(plays: Array[PlayDef], memory: DefenseMemory, situation: Dictionary,
		rng: RandomNumberGenerator, last_call: PlayDef = null) -> PlayDef:
	var w := defense_weights(plays, memory, situation, last_call)
	return plays[weighted_index(w, rng)]


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
