class_name ThrowRisk
extends RefCounted
## The CPU quarterback's risk model for one throw: plan the real flight to a spot, then ask
## every defender how soon he could get there — to the catch point (contest / pick) and to any
## point under the flight low enough to reach (a lane pick or tip) — against when the ball
## and the receiver arrive. Defenders are modelled like the engine plays them: zone defenders
## break on the ball after their reaction (a beat later when far away), man defenders run with
## their man until they turn to look for it. The QB's own accuracy shrinks the window.
## Result: {spot, plan, p_comp, p_int, yards, value, adv} where value = expected yards with an
## interception costing GameplayTuning.qb_int_cost.

const LANE_SAMPLES := [0.2, 0.33, 0.46, 0.59, 0.72, 0.85]


## Best of a few candidate spots for receiver `o` (in stride, a step away from the nearest
## defender, a little short / back toward him). `slop` = extra yards of margin (a receiver the
## QB can't read, e.g. a hand-run Road to Glory receiver). {} when out of range.
static func best_for(ctx: PlayRunner, o: PlayerAgent, slop := 0.0) -> Dictionary:
	var t := ctx.tuning
	var qb := ctx.qb
	if o == null or not o.is_eligible() or not o.can_act() or o.engaged_with != null:
		return {}
	var max_d := RatingModel.max_throw_distance(t, qb.attr("thp"))
	var lead := ctx.lead_point(o)
	var spots := [lead]
	var near := _nearest(ctx.defense, lead)
	if near != null:
		var away := lead - near.field_pos
		if away.length() > 0.01:
			spots.append(lead + away.normalized() * 1.2)
	spots.append(lead.lerp(o.field_pos, 0.3))
	var best := {}
	for s: Vector2 in spots:
		var p := Vector2(s.x, clampf(s.y, 1.2, FieldGeo.WIDTH - 1.2))
		if qb.field_pos.distance_to(p) > max_d or p.x > FieldGeo.LENGTH - 0.5:
			continue
		var e := evaluate(ctx, o, p, slop)
		if best.is_empty() or float(e["value"]) > float(best["value"]):
			best = e
	return best


## Risk of throwing to `o` at `spot`. Mirrors the engine's catch rule: at arrival the nearest
## defender inside the contest radius (wider on a hanging ball) who is closer than the receiver
## wins it (a pick roll); otherwise he contests the catch by how close he is.
static func evaluate(ctx: PlayRunner, o: PlayerAgent, spot: Vector2, slop := 0.0) -> Dictionary:
	var t := ctx.tuning
	var qb := ctx.qb
	var plan := ctx.plan_throw(spot)
	var flight := float(plan["dur"])
	var apex := float(plan["apex"])
	var loft := float(plan["loft"])
	var dist := qb.field_pos.distance_to(spot)
	var err := RatingModel.aim_error(t, qb.attr("tha"), qb.attr("awr"), dist, ctx.pressure_on_qb())
	var r_speed := maxf(o.max_speed * maxf(o.speed_mult, 0.9), 4.0)
	# How far from the spot the receiver still is when it lands (he runs at it; aim error and an
	# unreadable route add to it).
	var rec_d := maxf(o.field_pos.distance_to(spot) - r_speed * flight, 0.0) + slop + err * 0.6
	var cr := t.contest_radius + t.lob_contest_extra * loft
	var def_d := INF
	var catch_d: PlayerAgent = null
	var lane := 0.0
	var lane_d: PlayerAgent = null
	for d in ctx.defense:
		if d.is_down or d.engaged_with != null or not d.can_act() and d.dive_timer <= 0.0:
			continue
		var spd := maxf(d.max_speed * maxf(d.speed_mult, 1.0), 4.0)
		var brk := _break_time(ctx, d, o, spot, flight)
		var dd: float
		if brk >= flight:
			dd = _pos_at(ctx, d, flight).distance_to(spot)
		else:
			dd = maxf(_pos_at(ctx, d, brk).distance_to(spot) - spd * (flight - brk), 0.0)
		if dd < def_d:
			def_d = dd
			catch_d = d
		# Under the flight: can he get a hand on it while it's low?
		for u: float in LANE_SAMPLES:
			var g := qb.field_pos.lerp(spot, u)
			if qb.field_pos.distance_to(g) < t.lane_skip_near or spot.distance_to(g) < t.contest_radius:
				continue
			if PassModel.height_at(apex, u) > t.reach_height + t.jump_height * 0.6:
				continue
			var when := u * flight
			var p0 := _pos_at(ctx, d, minf(brk, when))
			var need := minf(brk, when) + maxf(p0.distance_to(g) - t.lane_reach, 0.0) / spd
			var m := clampf((when - need) / 0.25 + 0.5, 0.0, 1.0)
			if m > lane:
				lane = m
				lane_d = d
	var cov := catch_d.attr("cov") if catch_d != null else 50.0
	# Does a defender beat him to it? (soft: positions are estimates)
	var inside := _sig((cr - def_d) / 0.45)
	var first := inside * _sig((rec_d - def_d - 0.3) / 0.5)
	var p_pick := 0.0
	if catch_d != null:
		p_pick = RatingModel.int_prob(t, cov, catch_d.attr("cth"))
		if loft >= t.lob_threshold and def_d < 0.9:
			p_pick = minf(p_pick * t.undercut_int_mult, 0.75)
	var contest := clampf(1.0 - def_d / cr, 0.0, 1.0) if catch_d != null else 0.0
	if rec_d < def_d:
		contest *= t.trail_contest_mult   # he has a step and shields it
	var p_catch := RatingModel.catch_prob(t, o.attr("cth"), contest, cov) * (1.0 - t.lob_catch_penalty * loft)
	p_catch = lerpf(p_catch, maxf(p_catch, t.easy_catch_floor), clampf(1.0 - contest / t.easy_catch_contest, 0.0, 1.0))
	p_catch *= _sig((t.catch_radius + 0.2 - rec_d) / 0.35)   # he has to get there
	var p_lane_play := 0.0
	var p_int_lane := 0.0
	if lane_d != null and lane > 0.0:
		p_lane_play = clampf(lane * RatingModel.lane_play_prob(t, lane_d.attr("cov"), lane_d.attr("awr")) * 1.4, 0.0, 0.9)
		p_int_lane = p_lane_play * RatingModel.lane_int_prob(t, lane_d.attr("cth"))
	var through := 1.0 - p_lane_play
	var p_int := clampf(through * (first * p_pick + (1.0 - first) * (1.0 - p_catch) * (t.tip_int_chance if contest > 0.3 else 0.0))
			+ p_int_lane, 0.0, 0.95)
	var p_comp := clampf(through * (1.0 - first) * p_catch, 0.0, 1.0)
	var adv := (def_d - rec_d) / 6.0
	var air := spot.x - ctx.los_x
	var yac := clampf(adv, 0.0, 1.6) * t.qb_yac_per_sec
	var yards := air + yac
	return {"spot": spot, "receiver": o, "plan": plan, "p_comp": p_comp, "p_int": p_int, "yards": yards,
			"value": p_comp * yards - p_int * t.qb_int_cost, "adv": adv, "late": rec_d, "def_d": def_d}


static func _sig(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


## When defender `d` turns and goes for a ball thrown now to `spot` arriving after `flight`.
static func _break_time(ctx: PlayRunner, d: PlayerAgent, o: PlayerAgent, spot: Vector2, flight: float) -> float:
	var t := ctx.tuning
	var react := d.reaction + 0.1
	if d.brain is RushBrain or d.brain is PursuitBrain:
		return react
	if d.brain is ManCoverBrain:
		var mark := (d.brain as ManCoverBrain).mark
		if mark == o or d.field_pos.distance_to(spot) < t.ball_react_radius:
			return maxf(react, flight - t.man_look_back)
		return flight + 1.0   # he stays on his own man
	if d.field_pos.distance_to(spot) < t.ball_react_radius:
		return react
	return react + t.ball_rally_delay


## Where defender `d` will be `secs` from now if he keeps doing his job (man: mirror his man;
## anyone else: drift on his current velocity).
static func _pos_at(ctx: PlayRunner, d: PlayerAgent, secs: float) -> Vector2:
	if secs <= 0.0:
		return d.field_pos
	if d.brain is ManCoverBrain and (d.brain as ManCoverBrain).mark != null:
		var mark := (d.brain as ManCoverBrain).mark
		var move := ctx.predict(mark, secs) - mark.field_pos
		return d.field_pos + move.limit_length(d.max_speed * secs)
	return d.field_pos + d.velocity * minf(secs, 0.6)


static func _nearest(group: Array[PlayerAgent], p: Vector2) -> PlayerAgent:
	var best: PlayerAgent = null
	var bd := INF
	for a in group:
		if a.is_down:
			continue
		var dd := a.field_pos.distance_to(p)
		if dd < bd:
			bd = dd
			best = a
	return best
