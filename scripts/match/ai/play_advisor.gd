class_name PlayAdvisor
extends RefCounted
## Situational offensive play scoring: down, distance, field position, score and clock
## (plus what the defense is keyed on). Drives the play bar's "BEST" pick and the CPU
## offense's play calling. Pure logic.
## Situation dict: {down, to_go, los_x, score_diff, seconds_left}; los_x in field yards
## for the offense (attacking +x), score_diff from the offense's perspective,
## seconds_left = game seconds remaining (999 = not late).

const SUGGEST_WINDOW := 2.6
const SUGGEST_SHARPNESS := 0.9
const SAME_CATEGORY_MULT := 0.45
const SAME_FORMATION_MULT := 0.7
const RECENT_PENALTY := 0.9   ## per time the play was among your last few calls (newest counts most)


## Score for one play (higher = better call). `memory` may be null.
static func score(p: PlayDef, situation: Dictionary, memory: DefenseMemory = null) -> float:
	var down := int(situation.get("down", 1))
	var to_go := int(situation.get("to_go", 10))
	var los_x := float(situation.get("los_x", 35.0))
	var diff := int(situation.get("score_diff", 0))
	var secs := float(situation.get("seconds_left", 999.0))
	var yards_to_goal := FieldGeo.OPP_GOAL - los_x
	var run := p.category == "RUN"
	var deep := p.category == "DEEP"
	var short := p.category == "SHORT"
	var s := 1.0

	# Down & distance.
	if to_go <= 1:
		s += 3.0 if "short_yardage" in p.tags else 0.0
		s += 1.2 if run else 0.0
		s -= 1.2 if deep else 0.0
	elif to_go <= 3:
		s += 1.2 if run else 0.0
		s += 0.8 if "quick" in p.tags else 0.0
		s -= 0.8 if deep else 0.0
	elif down >= 3 and to_go >= 7:
		s += 2.0 if deep else 0.0
		s += 1.0 if short and "screen" not in p.tags else 0.0
		s -= 2.0 if run else 0.0
		s += 1.0 if p.id == "flood" or "deep" in p.tags else 0.0
	elif down == 2 and to_go >= 7:
		s += 0.9 if short else 0.0
		s += 0.6 if deep else 0.0
		s += 0.8 if "draw" in p.tags or "screen" in p.tags else 0.0
	elif down == 1:
		s += 0.7 if run else 0.0
		s += 0.5 if short else 0.0
		s += 1.0 if "play_action" in p.tags else 0.0
	# Short-yardage and goal-line packages are wasted with room to work.
	if to_go > 3 and yards_to_goal > 5.0:
		s -= 2.0 if "short_yardage" in p.tags or "goal_line" in p.tags else 0.0

	# Field position.
	if yards_to_goal <= 5.0:
		s += 2.5 if "goal_line" in p.tags else 0.0
		s += 1.0 if "red_zone" in p.tags else 0.0
		s -= 2.5 if "deep" in p.tags else 0.0
	elif yards_to_goal <= 20.0:
		s += 1.5 if "red_zone" in p.tags else 0.0
		s -= 1.5 if "deep" in p.tags else 0.0
	elif los_x <= FieldGeo.OWN_GOAL + 8.0:
		# Backed up: avoid long-developing drops in the end zone.
		s += 0.6 if run and "outside" not in p.tags else 0.0
		s -= 0.8 if deep else 0.0

	# Score & clock.
	if secs < 150.0 and diff < 0:
		s += 1.5 if deep or short else 0.0
		s -= 2.0 if run else 0.0
	elif secs < 150.0 and diff > 0:
		s += 2.0 if run else 0.0
		s -= 1.0 if deep else 0.0

	# Don't feed the defense what it is keyed on.
	if memory != null:
		s -= 3.0 * memory.key_level(p.id, p.formation.id if p.formation != null else "", p.category)
	return s


## Plays sorted best-first (stable for ties: playbook order).
static func rank(plays: Array[PlayDef], situation: Dictionary, memory: DefenseMemory = null) -> Array[PlayDef]:
	var scored: Array = []
	for i in plays.size():
		scored.append([score(plays[i], situation, memory), i, plays[i]])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[PlayDef] = []
	for e in scored:
		out.append(e[2])
	return out


## CPU offense: weighted pick favoring well-scored calls, with enough randomness to mix.
static func pick(plays: Array[PlayDef], situation: Dictionary, rng: RandomNumberGenerator,
		memory: DefenseMemory = null, sharpness := 1.1, deep_bias := true) -> PlayDef:
	var w := PackedFloat32Array()
	for p in plays:
		var bias := 0.5 if p.category == "DEEP" and deep_bias else 0.0   # CPU offenses went short too much
		w.append(exp(sharpness * (score(p, situation, memory) + bias)))
	return plays[AIPlayCaller.weighted_index(w, rng)]


## The play bar's `count` suggestions: the best call first, then a varied mix of other
## sensible calls (weighted random among plays scoring within SUGGEST_WINDOW of the best,
## favoring categories and formations not shown yet and plays you haven't just run), so the
## bar keeps showing different concepts instead of the same four every snap.
static func suggest(plays: Array[PlayDef], situation: Dictionary, rng: RandomNumberGenerator,
		memory: DefenseMemory = null, count := 4) -> Array[PlayDef]:
	var scores := {}
	for p in plays:
		scores[p] = score(p, situation, memory) - _recency_penalty(p, memory)
	var ranked := plays.duplicate()
	ranked.sort_custom(func(a: PlayDef, b: PlayDef) -> bool:
		return scores[a] > scores[b] if scores[a] != scores[b] else plays.find(a) < plays.find(b))
	var out: Array[PlayDef] = []
	if ranked.is_empty():
		return out
	out.append(ranked[0])
	var top: float = scores[ranked[0]]
	var pool: Array[PlayDef] = []
	for p in ranked.slice(1):
		if float(scores[p]) >= top - SUGGEST_WINDOW:
			pool.append(p)
	while out.size() < count and not pool.is_empty():
		var w := PackedFloat32Array()
		for p in pool:
			var x := exp(SUGGEST_SHARPNESS * (float(scores[p]) - top))
			for q in out:
				if q.category == p.category:
					x *= SAME_CATEGORY_MULT
				if q.formation == p.formation:
					x *= SAME_FORMATION_MULT
			w.append(x)
		var i := AIPlayCaller.weighted_index(w, rng)
		out.append(pool[i])
		pool.remove_at(i)
	# Thin situations (goal line): top up with the next best calls.
	for p in ranked:
		if out.size() >= count:
			break
		if p not in out:
			out.append(p)
	return out


## Pushes the calls you just ran down the bar (not the keyed warning: that's the defense).
static func _recency_penalty(p: PlayDef, memory: DefenseMemory) -> float:
	if memory == null:
		return 0.0
	var pen := 0.0
	var n := memory.recent.size()
	for i in range(maxi(0, n - 4), n):
		if memory.recent[i]["play"] == p.id:
			pen += RECENT_PENALTY * (1.0 - 0.15 * (n - 1 - i))
	return pen
