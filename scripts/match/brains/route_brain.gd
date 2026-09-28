class_name RouteBrain
extends Brain
## Follows absolute waypoints. Cut sharpness comes from route running.
## end_mode "sit" settles at the last point; "continue" keeps running the last direction.

var points: PackedVector2Array
var end_mode := "continue"
var idx := 0
var last_dir := Vector2.RIGHT


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_points: PackedVector2Array, p_end := "continue") -> void:
	super(p_agent, p_ctx)
	points = p_points
	end_mode = p_end


func update(dt: float) -> void:
	act(dt)


func act(_dt: float) -> void:
	if idx < points.size():
		var target := points[idx]
		if agent.field_pos.distance_to(target) < 0.6:
			var prev := agent.start_pos if idx == 0 else points[idx - 1]
			if target != prev:
				last_dir = (target - prev).normalized()
			idx += 1
			if idx < points.size():
				agent.velocity *= RatingModel.cut_keep(ctx.tuning, agent.attr("rte"))
			return
		agent.move_to(target, 1.0, false)
		last_dir = (target - agent.field_pos).normalized()
		return
	if end_mode == "sit":
		agent.move_to(points[points.size() - 1], 1.0, true)
		return
	var ahead := agent.field_pos + last_dir * 5.0
	ahead.y = clampf(ahead.y, 1.0, FieldGeo.WIDTH - 1.0)
	ahead.x = minf(ahead.x, FieldGeo.LENGTH - 1.0)
	agent.move_to(ahead, 1.0, false)


func label() -> String:
	return "route"
