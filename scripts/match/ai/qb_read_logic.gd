class_name QBReadLogic
extends RefCounted
## CPU quarterback read: scores eligible receivers by projected separation at the catch
## point, using the same throw planner as the human (PlayRunner.lead_point / plan_throw:
## bullets short, lobs deep and over lane defenders). evaluate() scores one receiver;
## best_throw() the best of all of them.


## Returns {"receiver", "target", "openness", "kind"} for one receiver, or {} if not throwable.
static func evaluate(ctx: PlayRunner, o: PlayerAgent) -> Dictionary:
	var qb := ctx.qb
	var t := ctx.tuning
	if not o.is_eligible() or not o.can_act() or o.engaged_with != null:
		return {}
	var max_d := RatingModel.max_throw_distance(t, qb.attr("thp"))
	var target := ctx.lead_point(o)
	target.y = clampf(target.y, 1.5, FieldGeo.WIDTH - 1.5)
	if qb.field_pos.distance_to(target) > max_d:
		return {}
	var plan := ctx.plan_throw(target)
	var flight := float(plan["dur"])
	var sep := 99.0
	for d in ctx.defense:
		if d.is_down:
			continue
		# Man defenders run with their man (backs to the ball) and only turn at the end;
		# zone defenders break on the ball after their reaction.
		var look := t.man_look_back if d.brain is ManCoverBrain else maxf(flight - d.reaction - 0.1, 0.0)
		var d_at := d.field_pos + d.velocity * minf(flight, 0.8) * 0.5
		var close := d.max_speed * minf(look, flight) * t.cpu_zone_closing
		sep = minf(sep, d_at.distance_to(target) - close)
	# Deep balls are riskier than they look from the pocket: want a bit more room.
	sep -= maxf(target.x - ctx.los_x - 15.0, 0.0) * t.cpu_deep_caution
	return {"receiver": o, "target": target, "openness": sep, "kind": int(plan["kind"])}


## Returns {"receiver": PlayerAgent, "target": Vector2, "openness": float} or {} if none.
static func best_throw(ctx: PlayRunner) -> Dictionary:
	var best := {}
	var best_score := -INF
	for o in ctx.offense:
		var e := evaluate(ctx, o)
		if e.is_empty():
			continue
		var score: float = e["openness"] + (e["target"].x - ctx.los_x) * 0.06
		if score > best_score:
			best_score = score
			best = e
	return best
