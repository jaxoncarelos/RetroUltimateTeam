class_name PassQBBrain
extends Brain
## Drops back, then shuffles in the pocket away from the nearest free rusher.

var drop_spot: Vector2


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, drop: float) -> void:
	super(p_agent, p_ctx)
	drop_spot = p_agent.start_pos + Vector2(-drop, 0.0)


func act(_dt: float) -> void:
	var target := drop_spot
	var threat := ctx.nearest_free(ctx.defense, agent.field_pos)
	if threat != null and agent.field_pos.distance_to(threat.field_pos) < 3.5:
		var away := (agent.field_pos - threat.field_pos).normalized()
		target = agent.field_pos + Vector2(minf(away.x, 0.0), away.y) * 2.0
	agent.move_to(target, 0.75, true)


func label() -> String:
	return "pocket"
