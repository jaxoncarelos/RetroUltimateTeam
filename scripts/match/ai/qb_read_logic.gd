class_name QBReadLogic
extends RefCounted
## CPU quarterback read: scores eligible receivers by projected separation at the catch
## point. evaluate() scores one receiver; best_throw() the best of all of them.


## Returns {"receiver", "target", "openness"} for one receiver, or {} if not throwable.
static func evaluate(ctx: PlayRunner, o: PlayerAgent) -> Dictionary:
	var qb := ctx.qb
	if not o.is_eligible() or not o.can_act() or o.engaged_with != null:
		return {}
	var max_d := RatingModel.max_throw_distance(ctx.tuning, qb.attr("thp"))
	var dist := qb.field_pos.distance_to(o.field_pos)
	var flight := RatingModel.throw_arc(ctx.tuning, qb.attr("thp"), dist).x
	var target := o.field_pos + o.velocity * flight
	target.y = clampf(target.y, 1.5, FieldGeo.WIDTH - 1.5)
	if qb.field_pos.distance_to(target) > max_d:
		return {}
	var sep := 99.0
	for d in ctx.defense:
		if d.is_down:
			continue
		var d_at := d.field_pos + d.velocity * flight * 0.5
		sep = minf(sep, d_at.distance_to(target) - d.max_speed * flight * 0.25)
	return {"receiver": o, "target": target, "openness": sep}


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
