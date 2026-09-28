class_name QBReadLogic
extends RefCounted
## CPU quarterback read: scores every eligible receiver by projected separation at the
## catch point and returns the best throw. Used by the CPU offense and sandbox autoplay.


## Returns {"receiver": PlayerAgent, "target": Vector2, "openness": float} or {} if none.
static func best_throw(ctx: PlayRunner) -> Dictionary:
	var qb := ctx.qb
	var best := {}
	var best_score := -INF
	var max_d := RatingModel.max_throw_distance(ctx.tuning, qb.attr("thp"))
	for o in ctx.offense:
		if not o.is_eligible() or not o.can_act() or o.engaged_with != null:
			continue
		var dist := qb.field_pos.distance_to(o.field_pos)
		var flight := RatingModel.throw_arc(ctx.tuning, qb.attr("thp"), dist).x
		var target := o.field_pos + o.velocity * flight
		target.y = clampf(target.y, 1.5, FieldGeo.WIDTH - 1.5)
		if qb.field_pos.distance_to(target) > max_d:
			continue
		var sep := 99.0
		for d in ctx.defense:
			if d.is_down:
				continue
			var d_at := d.field_pos + d.velocity * flight * 0.5
			sep = minf(sep, d_at.distance_to(target) - d.max_speed * flight * 0.25)
		var downfield := target.x - ctx.los_x
		var score := sep + downfield * 0.06
		if score > best_score:
			best_score = score
			best = {"receiver": o, "target": target, "openness": sep}
	return best
